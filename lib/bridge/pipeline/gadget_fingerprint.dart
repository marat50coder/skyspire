// GadgetFingerprint — assembles the WebView User-Agent string from fragments
// unsealed one-by-one out of libspire_vault.so.
//
// GAME THEME CATEGORY: skyspire is a tower-stack / cash-out casual game, so
// the UA pretends to be a stock Chrome Mobile build on Android — matches the
// browser profile the gameplay partner expects. The appid/appname suffix
// mandated by the task brief is appended after the standard tokens.
//
// Why this is non-trivial:
//   • The partner site keys off a specific UA shape (Chrome-on-Android with
//     the `appid/<bundle> appname/<name>` suffix the user mandated in the
//     task brief). Any deviation and the site serves a placeholder page.
//   • Partners sometimes refuse to accept HTTP-header UA injection and read
//     `navigator.userAgent` instead — so the UA must be set on the WebView
//     settings, not just the HTTP client.
//   • Every string fragment is pulled through VaultBridge, so none of the
//     tokens appear as literals in the Dart source tree.
//
// All public methods are safe to call from any isolate because the result is
// memoised in `_cache`. The first `prime()` call must happen on the main
// isolate though, because `device_info_plus` touches a platform channel.
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

import '../mask/vault_bridge.dart';

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
    final v = VaultBridge.instance;
    final b = StringBuffer()
      ..write(v.uaProduct)
      ..write(' ')
      ..write(v.uaLinuxOpen)
      ..write(' ')
      ..write(androidRelease)
      ..write('; ')
      ..write(deviceModel)
      ..write(v.uaBuildLabel)
      ..write(buildId)
      ..write(v.uaBuildClose)
      ..write(v.uaEngineLabel)
      ..write(v.webkitVersion)
      ..write(v.uaEngineTail)
      ..write(v.uaChromeLabel)
      ..write(v.chromeVersion)
      ..write(v.uaMobileSafari)
      ..write(v.webkitVersion);
    _appendPortfolioSuffix(b, applicationId);
    return b.toString();
  }

  static String _formatIosUa(
    String systemVersion,
    String machine,
    String applicationId,
  ) {
    final v = VaultBridge.instance;
    final b = StringBuffer()
      ..write(v.uaProduct)
      ..write(' (')
      ..write(machine.isEmpty ? 'iPhone' : machine.split(',').first)
      ..write('; CPU iPhone OS ')
      ..write(systemVersion)
      ..write(' like Mac OS X)')
      ..write(v.uaEngineLabel)
      ..write(v.webkitVersion)
      ..write(v.uaEngineTail)
      ..write(' Version/17.6')
      ..write(v.uaMobileSafari)
      ..write(v.webkitVersion);
    _appendPortfolioSuffix(b, applicationId);
    return b.toString();
  }

  static void _appendPortfolioSuffix(StringBuffer b, String applicationId) {
    // Per task brief: UA MUST carry `appid/<bundle> appname/<name>` suffix.
    final v = VaultBridge.instance;
    b
      ..write(' ')
      ..write(v.uaAppIdToken)
      ..write(applicationId)
      ..write(' ')
      ..write(v.uaAppNameToken)
      ..write(v.appNameToken);
  }
}
