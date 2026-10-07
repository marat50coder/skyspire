// BridgeConductor — single entry point that produces a Berth.
//
// Decision tree (short form):
//   1. If TapResolver has a pending URL → PortalBerth(that URL).
//   2. Read TrailMemory:
//        • stayPut → HomeBerth (short-circuit, no verdict call).
//        • opened  → either serve the cached destination or re-ask verdict.
//        • fresh   → run attribution + ask verdict.
//   3. If no reach → UnreachableBerth.
//
// Only the LaunchStage calls `decide()`. Everything the conductor needs
// (SignalVault, WaveSensor, OriginBeacon, JudgementCall) is wired in through
// the constructor so unit tests can stub them.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show PlatformDispatcher, debugPrint, kDebugMode;

import 'charts/bridge_manifest.dart';
import 'mask/vault_bridge.dart';
import 'outcome/berth.dart';
import 'pipeline/bridge_courier.dart';
import 'pipeline/judgement_call.dart';
import 'pipeline/notice_stream.dart';
import 'pipeline/origin_beacon.dart';
import 'pipeline/signal_vault.dart';
import 'pipeline/tap_resolver.dart';
import 'pipeline/wave_sensor.dart';

class BridgeConductor {
  BridgeConductor({required this.applicationId})
      : courier = BridgeCourier(applicationId) {
    _origin = OriginBeacon(applicationId: applicationId, courier: courier);
    _judgement = JudgementCall(courier: courier);
  }

  final String applicationId;
  final BridgeCourier courier;
  late final OriginBeacon _origin;
  late final JudgementCall _judgement;

  OriginBeacon get origin => _origin;

  Future<Berth> decide() async {
    // Step 0 — vault gate. If libspire_vault.so is missing or the baked
    // fingerprint does not match the Dart side, EVERY secret unseal returns
    // "" and the pipeline cannot build a valid verdict body. In that case
    // we send the user into the native shell and never touch the config
    // endpoint. This closes the previous audit's "silent empty endpoint"
    // trap.
    if (!_probeVault()) {
      _log('vault not ready — forcing HomeBerth');
      return const HomeBerth();
    }

    // Step 1 — pending push URL always wins.
    final pending = await TapResolver.consume();
    if (pending != null && pending.isNotEmpty) {
      final parsed = Uri.tryParse(pending);
      if (parsed != null &&
          (parsed.isScheme('http') || parsed.isScheme('https'))) {
        await SignalVault.writeTrail(TrailMemory.opened);
        _log('route=push pending=$pending');
        return PortalBerth(pending);
      }
    }

    final trail = await SignalVault.readTrail();
    _log('trail=$trail');
    if (trail == TrailMemory.stayPut) {
      _log('route=home (sticky trail)');
      return const HomeBerth();
    }

    // Step 2 — connectivity gate. UnreachableBerth is a soft stop that the
    // UnreachableWall screen can retry from without re-running the whole
    // boot pipeline (it just builds a fresh LaunchStage).
    if (!await WaveSensor.isReachable()) {
      _log('route=unreachable (no reach)');
      return const UnreachableBerth();
    }

    if (trail == TrailMemory.opened) {
      final cached = await SignalVault.readCachedDestination();
      if (cached != null) {
        _log('route=portal (cached) url=$cached');
        return PortalBerth(cached);
      }
      // Cached URL expired — fall through to a full verdict refresh.
    }

    // Step 3 — spin AppsFlyer up, wait for the attribution, then ask the
    // config endpoint for a verdict.
    await _origin.warmUp();
    final attribution = await _origin.captureAttribution();
    _log('attribution.size=${attribution.length} '
        'af_status=${attribution['af_status']} '
        'media_source=${attribution['media_source']} '
        'campaign=${attribution['campaign']}');

    final berth = await _askVerdict(attribution);
    _log('verdict.berth=$berth');

    // Retry pass: a HomeBerth without a real af_status is almost always a
    // timing miss — the GCD rescue filled `_attribution` with 14-ish non-
    // attribution keys OR the AF SDK fires its real callback a moment
    // later. Give it `kLateAttributionWindow` more seconds and re-ask the
    // endpoint if a usable payload shows up.
    //
    // IMPORTANT: condition is "no af_status", NOT "attribution.isEmpty".
    // The GCD-rescue path can populate `_attribution` with partial data
    // that has no af_status/media_source — a size check would miss that.
    Berth finalBerth = berth;
    Map<String, dynamic> finalAttr = attribution;
    final firstAfStatus =
        (attribution['af_status']?.toString() ?? '').trim();
    if (berth is HomeBerth && firstAfStatus.isEmpty) {
      _log('retry pass: no af_status in first attribution — waiting for SDK');
      final late = await _origin.awaitLateArrival(kLateAttributionWindow);
      final lateAfStatus = (late['af_status']?.toString() ?? '').trim();
      if (lateAfStatus.isNotEmpty) {
        _log('late attribution arrived: size=${late.length} '
            'af_status=$lateAfStatus '
            'media_source=${late['media_source']}');
        finalAttr = late;
        finalBerth = await _askVerdict(late);
        _log('verdict.berth(retry)=$finalBerth');
      } else {
        _log('no usable af_status after retry window — accepting HomeBerth');
      }
    }

    switch (finalBerth) {
      case PortalBerth():
        await SignalVault.writeTrail(TrailMemory.opened);
      case HomeBerth():
        // IMPORTANT: only lock the trail to stayPut if the attribution
        // explicitly declared the user as organic. Any other reason the
        // verdict came back empty (SDK still cold, verdict timeout, 5xx,
        // partner config glitch) is transient — retry on next boot.
        final afStatus = (finalAttr['af_status']?.toString() ?? '')
            .toLowerCase()
            .trim();
        if (afStatus == 'organic') {
          await SignalVault.writeTrail(TrailMemory.stayPut);
          _log('trail→stayPut (declared organic)');
        } else {
          _log('trail stays fresh (af_status=$afStatus) — will re-ask next boot');
        }
      case UnreachableBerth():
        // JudgementCall never returns UnreachableBerth today, but keep the
        // branch so future changes don't silently fall through.
        break;
    }
    return finalBerth;
  }

  Future<Berth> _askVerdict(Map<String, dynamic> attribution) async {
    final body = _origin.compose(
      bundleId: applicationId,
      platform: Platform.operatingSystem,
      storeHint: _storeHint(),
      locale: _locale(),
      pushToken: NoticeStream.instance.presence.token,
      firebaseProjectId:
          VaultBridge.instance.messagingProject.isNotEmpty
              ? VaultBridge.instance.messagingProject
              : null,
    );
    body.addAll(attribution);
    _log('verdict.body.keys=${body.keys.toList()}');
    return _judgement.ask(body);
  }

  String _storeHint() {
    if (Platform.isAndroid) return 'google_play';
    if (Platform.isIOS) return 'app_store';
    return 'unknown';
  }

  String _locale() {
    try {
      final loc = PlatformDispatcher.instance.locale;
      return '${loc.languageCode}_${loc.countryCode ?? ''}';
    } catch (_) {
      return 'en_US';
    }
  }

  void dispose() {
    courier.close();
  }

  void _log(String msg) {
    if (!kDebugMode) return;
    debugPrint('[bridge] $msg');
  }

  bool _probeVault() {
    // Touch one slot to force the DynamicLibrary.open path and the
    // fingerprint check. We check endpointUrl because any mis-ship of
    // the .so would otherwise manifest only inside JudgementCall.
    final probe = VaultBridge.instance.endpointUrl;
    return VaultBridge.instance.ready && probe.isNotEmpty;
  }
}
