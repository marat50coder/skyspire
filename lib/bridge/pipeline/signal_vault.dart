// SignalVault — thin typed wrapper around SharedPreferences (+ a hardened
// companion in flutter_secure_storage for the pending deep-link URL).
//
// Each key is prefixed with `vq8_` (see BridgeManifest.kVaultKeyPrefix) so a
// static scan across sibling apps cannot cluster this project's preference
// payload with any other build's.
//
// All methods are no-throw: a corrupted or missing preference file must not
// prevent the LaunchStage from reaching a Berth. We log and fall back.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../charts/bridge_manifest.dart';
import '../outcome/berth.dart';

class SignalVault {
  const SignalVault._();

  // Short, non-descriptive keys. Prefix is folded in to avoid collision with
  // the engine's own preference keys (`settings:*`, `wallet:*`).
  static const String _kTrail = '${kVaultKeyPrefix}trail';
  static const String _kDestination = '${kVaultKeyPrefix}dest';
  static const String _kDestinationExpires = '${kVaultKeyPrefix}dstExp';
  static const String _kPermissionSnoozeUntil = '${kVaultKeyPrefix}permUntil';
  static const String _kPermissionAccepted = '${kVaultKeyPrefix}permYes';
  static const String _kPermissionDeniedByOs = '${kVaultKeyPrefix}permOsNo';
  static const String _kPendingSecureUrl = '${kVaultKeyPrefix}pendUrl';

  /// Trail-schema epoch. Bump this integer whenever the logic that WRITES
  /// `_kTrail` changes meaning (e.g. we tighten the stayPut criteria). On
  /// the next cold-boot `prime()` sees a stale value, wipes the trail and
  /// its cached destination, and the user falls back into the fresh-boot
  /// pipeline. This frees users whose SharedPreferences got poisoned by
  /// an older build before the criteria tightened.
  static const int _kTrailEpoch = 2;
  static const String _kTrailEpochKey = '${kVaultKeyPrefix}trailEpoch';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  // ── trail memory
  static Future<TrailMemory> readTrail() async {
    try {
      final p = await _prefs();
      return TrailMemory.parse(p.getString(_kTrail));
    } catch (_) {
      return TrailMemory.fresh;
    }
  }

  static Future<void> writeTrail(TrailMemory value) async {
    try {
      final p = await _prefs();
      await p.setString(_kTrail, value.wire);
    } catch (_) {}
  }

  // ── cached destination
  static Future<String?> readCachedDestination() async {
    try {
      final p = await _prefs();
      final url = p.getString(_kDestination);
      if (url == null || url.isEmpty) return null;
      final exp = p.getInt(_kDestinationExpires) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (exp > 0 && nowMs > exp) return null;
      return url;
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheDestination(String url) async {
    try {
      final p = await _prefs();
      await p.setString(_kDestination, url);
      final expiresAt = DateTime.now()
          .add(kCachedUrlLifetime)
          .millisecondsSinceEpoch;
      await p.setInt(_kDestinationExpires, expiresAt);
    } catch (_) {}
  }

  // ── permission bookkeeping
  static Future<bool> permissionAccepted() async {
    try {
      final p = await _prefs();
      return p.getBool(_kPermissionAccepted) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markPermissionAccepted(bool value) async {
    try {
      final p = await _prefs();
      await p.setBool(_kPermissionAccepted, value);
    } catch (_) {}
  }

  static Future<bool> permissionDeniedByOs() async {
    try {
      final p = await _prefs();
      return p.getBool(_kPermissionDeniedByOs) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markPermissionDeniedByOs(bool value) async {
    try {
      final p = await _prefs();
      await p.setBool(_kPermissionDeniedByOs, value);
    } catch (_) {}
  }

  static Future<DateTime?> permissionSnoozeUntil() async {
    try {
      final p = await _prefs();
      final ms = p.getInt(_kPermissionSnoozeUntil);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> snoozePermissionBy(Duration gap) async {
    try {
      final p = await _prefs();
      final until = DateTime.now().add(gap).millisecondsSinceEpoch;
      await p.setInt(_kPermissionSnoozeUntil, until);
    } catch (_) {}
  }

  // ── pending deep-link URL (goes through secure storage so a backup
  // extractor does not leak the attribution payload between re-installs).
  static Future<String?> consumePendingSecureUrl() async {
    try {
      final v = await _secure.read(key: _kPendingSecureUrl);
      if (v == null || v.isEmpty) return null;
      await _secure.delete(key: _kPendingSecureUrl);
      return v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> stashPendingSecureUrl(String url) async {
    try {
      await _secure.write(key: _kPendingSecureUrl, value: url);
    } catch (_) {}
  }

  static Future<void> prime() async {
    // Warm up SharedPreferences so the first `decide()` call doesn't block
    // on the platform channel.
    try {
      final p = await _prefs();
      // Trail-schema migration: wipe the sticky trail if it was written by
      // an older build whose stayPut criteria no longer match the current
      // logic. See the comment on `_kTrailEpoch` above.
      final seen = p.getInt(_kTrailEpochKey) ?? 0;
      if (seen < _kTrailEpoch) {
        await p.remove(_kTrail);
        await p.remove(_kDestination);
        await p.remove(_kDestinationExpires);
        await p.setInt(_kTrailEpochKey, _kTrailEpoch);
      }
    } catch (_) {}
  }
}
