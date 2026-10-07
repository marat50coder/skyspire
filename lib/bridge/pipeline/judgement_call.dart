// JudgementCall — single POST to the config endpoint. Decides whether the
// user belongs on the PortalBerth (external URL returned by the partner) or
// the HomeBerth (empty / malformed / 4xx response).
//
// On a successful portal verdict we cache the destination in the SignalVault
// so repeat boots skip this call entirely (see `kCachedUrlLifetime`).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../charts/bridge_manifest.dart';
import '../charts/shrouded_payload.dart';
import '../outcome/berth.dart';
import 'bridge_courier.dart';
import 'signal_vault.dart';

class JudgementCall {
  JudgementCall({required this.courier});

  final BridgeCourier courier;

  /// Returns `null` on any non-portal outcome. Caller must then persist the
  /// `TrailMemory.stayPut` state. On a positive verdict we also cache the
  /// resolved URL via SignalVault.
  Future<Berth> ask(Map<String, dynamic> body) async {
    final endpoint = ShroudedPayload.pullEndpointUrl();
    if (endpoint.isEmpty) return const HomeBerth();
    final uri = Uri.tryParse(endpoint);
    if (uri == null) return const HomeBerth();

    try {
      final res = await courier
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(kVerdictTimeout);
      _log('status=${res.statusCode} bodyLen=${res.body.length} '
          'bodyHead=${_head(res.body, 200)}');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return const HomeBerth();
      }
      if (res.body.isEmpty) return const HomeBerth();

      final decoded = jsonDecode(res.body);
      final url = _extractUrl(decoded);
      if (url == null || url.isEmpty) {
        _log('no url field found in response');
        return const HomeBerth();
      }
      final parsed = Uri.tryParse(url);
      if (parsed == null ||
          !(parsed.isScheme('http') || parsed.isScheme('https'))) {
        _log('url parse rejected: $url');
        return const HomeBerth();
      }
      await SignalVault.cacheDestination(url);
      return PortalBerth(url);
    } catch (e) {
      _log('exception: $e');
      return const HomeBerth();
    }
  }

  String _head(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

  void _log(String msg) {
    if (!kDebugMode) return;
    debugPrint('[judgement] $msg');
  }

  String? _extractUrl(dynamic decoded) {
    if (decoded is! Map) return null;
    // Accept a handful of common field names so the partner can rotate
    // their config schema without a client release.
    for (final key in const <String>['url', 'destination', 'target', 'link', 'u']) {
      final v = decoded[key];
      if (v is String && v.isNotEmpty) return v.trim();
    }
    return null;
  }
}
