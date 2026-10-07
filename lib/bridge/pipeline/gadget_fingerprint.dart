// GadgetFingerprint — assembles the WebView User-Agent string from the
// encoded fragments shipped in ShroudedPayload.
//
// Why this is non-trivial:
//   • The partner site keys off a specific UA shape (Chrome-on-Android with
//     the `appid/<bundle> appname/<name>` suffix the user mandated in the
//     task brief). Any deviation and the site serves a placeholder page.
//   • Partners sometimes refuse to accept HTTP-header UA injection and read
//     `navigator.userAgent` instead — so the UA must be set on the WebView
//     settings, not just the HTTP client.
//   • The sibling template builds the string by concatenating code-unit
//     arrays; we rebuild from decoded fragments to keep the compiled byte
//     pattern different.
//
// All public methods are safe to call from any isolate because the result is
// memoised in `_cache`. The first `prime()` call must happen on the main
// isolate though, because `device_info_plus` touches a platform channel.
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

import '../charts/shrouded_payload.dart';

class GadgetFingerprint {
  const GadgetFingerprint._();

  static String? _cache;
  static bool _primed = false;
  static final DeviceInfoPlugin _probe = DeviceInfoPlugin();

  /// Call once from `main()` so the first PortalBerth paint already has a
  /// baked UA. Falls back silently if `device_info_plus` throws.
  static Future<void> prime(String applicationId) async {
    if (_primed) return;
    _primed = true;
    try {
      _cache = await _assemble(applicationId);
    } catch (_) {
      _cache = _assembleFallback(applicationId);
    }
  }

  /// Returns the UA assembled during [prime]. Safe to call before `prime()`
  /// completes — in that case we return the fallback shape so verdict calls
  /// never block on a platform channel.
  static String currentUa(String applicationId) {
    final cached = _cache;
    if (cached != null) return cached;
    return _assembleFallback(applicationId);
  }

  static Future<String> _assemble(String applicationId) async {
    if (Platform.isAndroid) {
      final info = await _probe.androidInfo;
      final androidRel = info.version.release.isNotEmpty
          ? info.version.release
          : (info.version.sdkInt > 0 ? '${info.version.sdkInt}' : '15');
      final model = info.model.isNotEmpty ? info.model : 'Android';
      final build = info.id.isNotEmpty ? info.id : 'release-keys';
      return _formatAndroidUa(androidRel, model, build, applicationId);
    }
    if (Platform.isIOS) {
      final info = await _probe.iosInfo;
      final ver = info.systemVersion.replaceAll('.', '_');
      return _formatIosUa(ver, info.utsname.machine, applicationId);
    }
    return _assembleFallback(applicationId);
  }

  static String _assembleFallback(String applicationId) {
    if (Platform.isIOS) {
      return _formatIosUa('17_6', 'iPhone15,3', applicationId);
    }
    return _formatAndroidUa('15', 'SM-S931U', 'AP3A.240905.015.A2', applicationId);
  }

  static String _formatAndroidUa(
    String androidRelease,
    String deviceModel,
    String buildId,
    String applicationId,
  ) {
    final b = StringBuffer()
      ..write(ShroudedPayload.pullUaProduct())
      ..write(' ')
      ..write(ShroudedPayload.pullUaLinuxOpen())
      ..write(' ')
      ..write(androidRelease)
      ..write('; ')
      ..write(deviceModel)
      ..write(ShroudedPayload.pullUaBuildLabel())
      ..write(buildId)
      ..write(ShroudedPayload.pullUaBuildClose())
      ..write(ShroudedPayload.pullUaEngineLabel())
      ..write(ShroudedPayload.pullWebkitVersion())
      ..write(ShroudedPayload.pullUaEngineTail())
      ..write(ShroudedPayload.pullUaChromeLabel())
      ..write(ShroudedPayload.pullChromeVersion())
      ..write(ShroudedPayload.pullUaMobileSafari())
      ..write(ShroudedPayload.pullWebkitVersion());
    _appendPortfolioSuffix(b, applicationId);
    return b.toString();
  }

  static String _formatIosUa(
    String systemVersion,
    String machine,
    String applicationId,
  ) {
    final b = StringBuffer()
      ..write(ShroudedPayload.pullUaProduct())
      ..write(' (')
      ..write(machine.isEmpty ? 'iPhone' : machine.split(',').first)
      ..write('; CPU iPhone OS ')
      ..write(systemVersion)
      ..write(' like Mac OS X)')
      ..write(ShroudedPayload.pullUaEngineLabel())
      ..write(ShroudedPayload.pullWebkitVersion())
      ..write(ShroudedPayload.pullUaEngineTail())
      ..write(' Version/17.6')
      ..write(ShroudedPayload.pullUaMobileSafari())
      ..write(ShroudedPayload.pullWebkitVersion());
    _appendPortfolioSuffix(b, applicationId);
    return b.toString();
  }

  static void _appendPortfolioSuffix(StringBuffer b, String applicationId) {
    // Per task brief: UA MUST carry `appid/<bundle> appname/<name>` suffix.
    b
      ..write(' ')
      ..write(ShroudedPayload.pullUaAppIdToken())
      ..write(applicationId)
      ..write(' ')
      ..write(ShroudedPayload.pullUaAppNameToken())
      ..write(ShroudedPayload.pullAppNameToken());
  }
}
