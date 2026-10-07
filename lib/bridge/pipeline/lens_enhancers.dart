// LensEnhancers — the three JS snippets we inject on every PortalBerth load.
//
// All three live in ShroudedPayload (encoded) and are concatenated here into
// one `runJavaScript` payload. Keeping them in a single call avoids spamming
// the WebView's main thread with three dispatches.
import '../charts/shrouded_payload.dart';

class LensEnhancers {
  const LensEnhancers._();

  /// Combined JS enhancer bundle — safe-area padding reset, keyboard scroll
  /// nudge, and `video` autoplay priming (muted + playsinline).
  static String assembleBundle() {
    final sb = StringBuffer()
      ..writeln(ShroudedPayload.pullJsSafeAreaScript())
      ..writeln(ShroudedPayload.pullJsKeyboardScript())
      ..writeln(ShroudedPayload.pullJsAutoplayScript());
    return sb.toString();
  }
}
