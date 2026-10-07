// VaultBridge — Dart side of the ChaCha20 string vault.
//
// Every secret the bridge-flow needs (verdict endpoint, GCD base URL,
// AppsFlyer dev key, Firebase project id, WebView UA fragments and the
// injected JS enhancer bodies) lives in `libspire_vault.so` as encrypted
// bytes. This class loads the library once, hands a slot id to the native
// `vault_unseal` function, copies the plaintext into a Dart string, and
// asks the native side to free the heap buffer. The decoded value is then
// memoised so each slot's cipher pass runs at most once per process.
//
// Gate semantics — `ready`:
//   • `true`  → library opened, fingerprint matches, every attempt to
//               unseal has succeeded so far.
//   • `false` → library missing, wrong fingerprint, or any slot has
//               returned an empty / error result. BridgeConductor refuses
//               to run the gray-flow pipeline when `ready` is false.
//
// This is the same pattern the earlier audit demanded: no .so → white part
// forever, no silent swallow of a NULL ptr into "". The release APK must
// pack the .so for every supported ABI (see android/app/src/main/jniLibs).
import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

// ─── slot id namespace — must match native/vault/src/lib.rs ────────────────
// Change here REQUIRES bumping the matching SLOT_* const in the Rust crate
// AND regenerating sealed.rs via tools/vault_pack.py.
const int kSlotEndpointUrl       = 0x11;
const int kSlotGcdBaseUrl        = 0x12;
const int kSlotAttributionKey    = 0x13;
const int kSlotMessagingProject  = 0x14;

const int kSlotUaProduct         = 0x21;
const int kSlotUaLinuxOpen       = 0x22;
const int kSlotUaBuildLabel      = 0x23;
const int kSlotUaBuildClose      = 0x24;
const int kSlotUaEngineLabel     = 0x25;
const int kSlotUaEngineTail      = 0x26;
const int kSlotUaChromeLabel     = 0x27;
const int kSlotUaMobileSafari    = 0x28;
const int kSlotChromeVersion     = 0x29;
const int kSlotWebkitVersion     = 0x2A;
const int kSlotUaAppIdToken      = 0x2B;
const int kSlotUaAppNameToken    = 0x2C;
const int kSlotAppNameToken      = 0x2D;

const int kSlotJsSafeArea        = 0x31;
const int kSlotJsKeyboard        = 0x32;
const int kSlotJsAutoplay        = 0x33;

const int _kVaultFingerprint     = 0x5B137A94;

// ─── FFI typedefs ──────────────────────────────────────────────────────────
typedef _UnsealNative = ffi.Pointer<ffi.Uint8> Function(
    ffi.Uint32 slotId, ffi.Pointer<ffi.IntPtr> outLen);
typedef _UnsealDart = ffi.Pointer<ffi.Uint8> Function(
    int slotId, ffi.Pointer<ffi.IntPtr> outLen);

typedef _ReleaseNative = ffi.Void Function(
    ffi.Pointer<ffi.Uint8> ptr, ffi.IntPtr len);
typedef _ReleaseDart = void Function(ffi.Pointer<ffi.Uint8> ptr, int len);

typedef _FingerprintNative = ffi.Uint32 Function();
typedef _FingerprintDart = int Function();

class VaultBridge {
  VaultBridge._();

  static final VaultBridge instance = VaultBridge._();

  ffi.DynamicLibrary? _lib;
  _UnsealDart? _unseal;
  _ReleaseDart? _release;
  _FingerprintDart? _fingerprint;
  bool _ready = false;
  bool _loadAttempted = false;

  final Map<int, String> _cache = <int, String>{};

  /// `true` once the .so was loaded, its fingerprint matched, and no slot
  /// has returned garbage so far. BridgeConductor refuses to proceed if
  /// this is false — no silent fallback into "" strings.
  bool get ready => _ready;

  /// Lazy load. Safe to call from any isolate; subsequent calls short-
  /// circuit on `_loadAttempted`.
  void _ensureLoaded() {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      _lib = _openLibrary();
      _unseal = _lib!
          .lookup<ffi.NativeFunction<_UnsealNative>>('vault_unseal')
          .asFunction();
      _release = _lib!
          .lookup<ffi.NativeFunction<_ReleaseNative>>('vault_release')
          .asFunction();
      _fingerprint = _lib!
          .lookup<ffi.NativeFunction<_FingerprintNative>>('vault_fingerprint')
          .asFunction();
      final fp = _fingerprint!();
      if (fp != _kVaultFingerprint) {
        _logDebug('fingerprint mismatch: got 0x${fp.toRadixString(16)} '
            'expected 0x${_kVaultFingerprint.toRadixString(16)}');
        return;
      }
      _ready = true;
      _logDebug('ready');
    } catch (e) {
      _logDebug('load failure: $e');
    }
  }

  ffi.DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libspire_vault.so');
    }
    if (Platform.isIOS) {
      // On iOS the vault is linked statically into the Flutter runner; the
      // bridge-flow iOS target is not shipped on this project but keep the
      // code path for future use.
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError('vault only shipped for Android');
  }

  /// Fetch a secret by slot id. Returns an empty string AND flips `ready`
  /// to false if anything went wrong, so callers never silently continue
  /// with partial data.
  String unseal(int slotId) {
    _ensureLoaded();
    if (!_ready) return '';
    final cached = _cache[slotId];
    if (cached != null) return cached;
    final outLen = calloc<ffi.IntPtr>();
    try {
      final ptr = _unseal!(slotId, outLen);
      final len = outLen.value;
      if (ptr == ffi.nullptr || len <= 0) {
        _ready = false;
        _logDebug('slot 0x${slotId.toRadixString(16)} unseal returned null');
        return '';
      }
      try {
        final bytes = ptr.asTypedList(len);
        // Copy BEFORE releasing — asTypedList is a view into native memory.
        final copy = List<int>.from(bytes, growable: false);
        final decoded = utf8.decode(copy, allowMalformed: false);
        _cache[slotId] = decoded;
        return decoded;
      } finally {
        _release!(ptr, len);
      }
    } finally {
      calloc.free(outLen);
    }
  }

  // ─── typed accessors ─────────────────────────────────────────────────────
  // One short method per slot so callers do not pass raw hex ids around.
  String get endpointUrl       => unseal(kSlotEndpointUrl);
  String get gcdBaseUrl        => unseal(kSlotGcdBaseUrl);
  String get attributionKey    => unseal(kSlotAttributionKey);
  String get messagingProject  => unseal(kSlotMessagingProject);

  String get uaProduct         => unseal(kSlotUaProduct);
  String get uaLinuxOpen       => unseal(kSlotUaLinuxOpen);
  String get uaBuildLabel      => unseal(kSlotUaBuildLabel);
  String get uaBuildClose      => unseal(kSlotUaBuildClose);
  String get uaEngineLabel     => unseal(kSlotUaEngineLabel);
  String get uaEngineTail      => unseal(kSlotUaEngineTail);
  String get uaChromeLabel     => unseal(kSlotUaChromeLabel);
  String get uaMobileSafari    => unseal(kSlotUaMobileSafari);
  String get chromeVersion     => unseal(kSlotChromeVersion);
  String get webkitVersion     => unseal(kSlotWebkitVersion);
  String get uaAppIdToken      => unseal(kSlotUaAppIdToken);
  String get uaAppNameToken    => unseal(kSlotUaAppNameToken);
  String get appNameToken      => unseal(kSlotAppNameToken);

  String get jsSafeAreaScript  => unseal(kSlotJsSafeArea);
  String get jsKeyboardScript  => unseal(kSlotJsKeyboard);
  String get jsAutoplayScript  => unseal(kSlotJsAutoplay);

  void _logDebug(String msg) {
    if (!kDebugMode) return;
    debugPrint('[vault] $msg');
  }
}
