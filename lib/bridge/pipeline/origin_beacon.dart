// OriginBeacon — glue between AppsFlyer attribution and the verdict payload.
//
// Two paths run in parallel:
//   1) `appsflyer_sdk` fires its own conversion-data / open-attribution /
//      deep-link callbacks and we scoop whichever arrives first.
//   2) If the SDK stays silent beyond [kOrganicRescueDelay] we fall back to
//      a direct GCD v4.0 query so the verdict call still carries campaign
//      data — this covers cases where AF's first POST got rate-limited or
//      the device had Play Services disabled.
//
// The attribution data is finally merged into the verdict body by `compose`
// so JudgementCall can POST a single JSON blob to the config endpoint.
import 'dart:async';
import 'dart:convert';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

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
  Map<String, dynamic> get snapshot =>
      Map<String, dynamic>.unmodifiable(_attribution);

  /// Spin up the AppsFlyer SDK and hook its callbacks. Safe to call before
  /// a dev key is wired in — if the key is empty we just stay dormant.
  Future<void> warmUp() async {
    final devKey = ShroudedPayload.pullAttributionKey();
    if (devKey.isEmpty) {
      _log('warmUp: dev key empty, dormant');
      if (!_firstPulse.isCompleted) _firstPulse.complete();
      return;
    }
    try {
      final opts = AppsFlyerOptions(
        afDevKey: devKey,
        appId: applicationId,
        showDebug: kDebugMode,
        timeToWaitForATTUserAuthorization: 15,
      );
      _sdk = AppsflyerSdk(opts);
      // CRITICAL: the listeners MUST be installed BEFORE initSdk(). The AF
      // Flutter plugin dispatches the very first conversion payload during
      // initSdk; if the handler is not registered at that moment the first
      // dispatch is silently dropped and the next one only arrives after
      // the SDK's internal cache cycle (10–20 s later).
      _sdk!.onInstallConversionData((data) {
        _log('cb=install payload.size=${_sizeOf(data)} '
            'af_status=${_pick(data, 'af_status')} '
            'media_source=${_pick(data, 'media_source')}');
        _attribution = _flatten(data);
        try {
          _afId = _attribution['appsflyer_id']?.toString() ??
              _attribution['app_id']?.toString();
        } catch (_) {}
        if (!_firstPulse.isCompleted) _firstPulse.complete();
      });
      _sdk!.onAppOpenAttribution((data) {
        _log('cb=appOpen payload.size=${_sizeOf(data)} '
            'af_status=${_pick(data, 'af_status')}');
        _attribution.addAll(_flatten(data));
        if (!_firstPulse.isCompleted) _firstPulse.complete();
      });
      _sdk!.onDeepLinking((DeepLinkResult result) {
        try {
          final payload = result.deepLink?.clickEvent;
          _log('cb=deepLink status=${result.status} '
              'payload.size=${_sizeOf(payload)}');
          if (payload is Map) {
            _attribution.addAll(_flatten(payload));
          }
        } catch (_) {}
        if (!_firstPulse.isCompleted) _firstPulse.complete();
      });

      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
      _log('initSdk returned');
      // AF's getAppsFlyerUID is a cheap platform channel call.
      try {
        _afId = await _sdk!.getAppsFlyerUID();
        _log('af_uid=$_afId');
      } catch (_) {}
    } catch (e) {
      _log('warmUp exception: $e');
      if (!_firstPulse.isCompleted) _firstPulse.complete();
    }
  }

  /// Wait up to [kOrganicRescueDelay] for the first conversion callback,
  /// polling the shared `_attribution` map every 150 ms so we exit the
  /// moment the SDK calls back. If nothing arrives, try the direct GCD
  /// endpoint as a last resort.
  Future<Map<String, dynamic>> captureAttribution() async {
    final deadline = DateTime.now().add(kOrganicRescueDelay);
    while (DateTime.now().isBefore(deadline)) {
      if (_firstPulse.isCompleted || _attribution.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (_attribution.isEmpty) {
      _log('captureAttribution: still empty after '
          '${kOrganicRescueDelay.inSeconds}s — trying GCD rescue');
      await _gcdRescue();
    }
    _log('captureAttribution: size=${_attribution.length} '
        'af_status=${_attribution['af_status']}');
    return Map<String, dynamic>.unmodifiable(_attribution);
  }

  /// Keep polling for new attribution bytes beyond the initial budget. Used
  /// by BridgeConductor when the first verdict came back empty — gives the
  /// SDK a second chance to deliver the payload before giving up.
  Future<Map<String, dynamic>> awaitLateArrival(Duration extra) async {
    final deadline = DateTime.now().add(extra);
    while (DateTime.now().isBefore(deadline)) {
      if (_attribution.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
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
      _log('gcdRescue status=${res.statusCode} bodyLen=${res.body.length}');
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) _attribution.addAll(_flatten(decoded));
      }
    } catch (e) {
      _log('gcdRescue exception: $e');
    }
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
        out[k.toString()] = v;
      });
    }
    return out;
  }

  int _sizeOf(dynamic data) {
    if (data is Map) return data.length;
    if (data is List) return data.length;
    return 0;
  }

  String _pick(dynamic data, String key) {
    try {
      if (data is Map) return (data[key]?.toString() ?? 'null');
    } catch (_) {}
    return 'null';
  }

  void _log(String msg) {
    if (!kDebugMode) return;
    debugPrint('[origin] $msg');
  }
}
