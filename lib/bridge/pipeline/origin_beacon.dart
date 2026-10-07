// OriginBeacon — glue between AppsFlyer attribution and the verdict payload.
//
// Two paths run in parallel:
//   1) `appsflyer_sdk` fires its own `onConversionDataSuccess` callback.
//      That's the normal case; we scoop the data and call it a day.
//   2) If the SDK stays silent beyond `kOrganicRescueDelay` we poll the GCD
//      v4 endpoint ourselves. This happens when the device never had Play
//      Services or when AF's first POST is rate-limited.
//
// The attribution data is finally merged into the verdict body by `compose`
// so JudgementCall can POST a single JSON blob to the config endpoint.
import 'dart:async';
import 'dart:convert';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';

import '../charts/bridge_manifest.dart';
import '../charts/shrouded_payload.dart';
import 'bridge_courier.dart';

class OriginBeacon {
  OriginBeacon({required this.applicationId, required this.courier});

  final String applicationId;
  final BridgeCourier courier;

  AppsflyerSdk? _sdk;
  Map<String, dynamic> _attribution = <String, dynamic>{};
  String? _afId;
  final Completer<void> _firstPulse = Completer<void>();

  String? get appsFlyerId => _afId;

  /// Spin up the AppsFlyer SDK and hook its callbacks. Safe to call before
  /// a dev key is wired in — if the key is empty we just stay dormant.
  Future<void> warmUp() async {
    final devKey = ShroudedPayload.pullAttributionKey();
    if (devKey.isEmpty) {
      // No dev key yet: user said "appsflyer и firebase дам тебе позже".
      // Mark the first-pulse completer so the splash is not blocked.
      if (!_firstPulse.isCompleted) _firstPulse.complete();
      return;
    }
    try {
      final opts = AppsFlyerOptions(
        afDevKey: devKey,
        appId: applicationId,
        showDebug: false,
        timeToWaitForATTUserAuthorization: 15,
      );
      _sdk = AppsflyerSdk(opts);
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
      _sdk!.onInstallConversionData((data) {
        _attribution = _flatten(data);
        try {
          _afId = _attribution['appsflyer_id']?.toString() ??
              _attribution['app_id']?.toString();
        } catch (_) {}
        if (!_firstPulse.isCompleted) _firstPulse.complete();
      });
      _sdk!.onAppOpenAttribution((data) {
        _attribution.addAll(_flatten(data));
      });
      // AF's getAppsFlyerUID is a cheap platform channel call.
      try {
        _afId = await _sdk!.getAppsFlyerUID();
      } catch (_) {}
    } catch (_) {
      if (!_firstPulse.isCompleted) _firstPulse.complete();
    }
  }

  /// Wait up to [kOrganicRescueDelay] for the first conversion callback,
  /// then fall back to a direct GCD query if the SDK stayed silent.
  Future<Map<String, dynamic>> captureAttribution() async {
    try {
      await _firstPulse.future.timeout(kOrganicRescueDelay);
    } on TimeoutException {
      await _gcdRescue();
    } catch (_) {}
    return Map<String, dynamic>.unmodifiable(_attribution);
  }

  Future<void> _gcdRescue() async {
    final devKey = ShroudedPayload.pullAttributionKey();
    if (devKey.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${ShroudedPayload.pullGcdBaseUrl()}$applicationId',
      );
      final res = await courier
          .get(uri, headers: <String, String>{'authentication': devKey})
          .timeout(kVerdictTimeout);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) _attribution.addAll(_flatten(decoded));
      }
    } catch (_) {}
  }

  /// Assemble the body posted to the config endpoint.
  Map<String, dynamic> compose({
    required String bundleId,
    required String platform,
    required String storeHint,
    required String locale,
    required String? pushToken,
    required String? firebaseProjectId,
  }) {
    return <String, dynamic>{
      'af_id': _afId,
      'bundle_id': bundleId,
      'os': platform,
      'store_id': storeHint,
      'locale': locale,
      'push_token': pushToken,
      'firebase_project_id': firebaseProjectId,
      ..._attribution,
    };
  }

  Map<String, dynamic> _flatten(dynamic raw) {
    final out = <String, dynamic>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map || v is List) {
          out[k.toString()] = v;
        } else {
          out[k.toString()] = v;
        }
      });
    }
    return out;
  }
}
