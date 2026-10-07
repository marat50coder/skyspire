// LensEnhancers — the three JS snippets we inject on every PortalBerth load.
//
// All three live inside libspire_vault.so as ChaCha20-encrypted blobs. We
// pull them lazily through VaultBridge and concatenate them into one
// `runJavaScript` payload. Keeping it in a single call avoids spamming the
// WebView's main thread with three dispatches.
import '../mask/vault_bridge.dart';

class LensEnhancers {
  const LensEnhancers._();

  /// Combined JS enhancer bundle — safe-area padding reset, keyboard scroll
  /// nudge, and `video` autoplay priming (muted + playsinline).
  static String assembleBundle() {
    final v = VaultBridge.instance;
    final sb = StringBuffer()
      ..writeln(v.jsSafeAreaScript)
      ..writeln(v.jsKeyboardScript)
      ..writeln(v.jsAutoplayScript);
    return sb.toString();
  }
}
