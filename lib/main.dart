// Skyspire entry point.
//
// Boot order (strict — reordering any of these three lines breaks either
// the Rust engine or the attribution/push stack):
//   1. Flutter binding + full-screen immersive mode (both are cheap).
//   2. Firebase.initializeApp — wrapped in try/catch because
//      google-services.json ships blank until the user wires their project.
//   3. SignalVault.prime() + GadgetFingerprint.prime() in parallel so the
//      first BridgeConductor.decide() does not block on platform channels.
//   4. initializeRust — this is the only call that MUST stay on the main
//      isolate; rinf opens an FFI port that LoadingScreen depends on.
//
// After that we hand off to SpireShell which mounts LaunchStage. If the
// BridgeConductor resolves to HomeBerth we land in LoadingScreen (the
// original game splash) so the native sprite/wallet pipeline runs untouched.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import 'bridge/pipeline/gadget_fingerprint.dart';
import 'bridge/pipeline/notice_stream.dart';
import 'bridge/pipeline/signal_vault.dart';
import 'shell/spire_shell.dart';
import 'src/bindings/bindings.dart';

/// Must match the Android applicationId / iOS bundle id.
const String kApplicationId = 'com.skyspire.spiregame';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Full immersive sticky: hide both the status bar and the Android soft
  // navigation bar. The user explicitly asked to never surface the system
  // navigation inside the game. `immersiveSticky` means a swipe from the
  // edges only briefly re-shows the bars; they auto-hide again.
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: const <SystemUiOverlay>[],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Firebase is optional: credentials ship later. Swallow init errors so a
  // missing google-services.json never prevents the game from running.
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Fire the prime-only tasks in parallel. NoticeStream.primeToken() grabs
  // the FCM registration token without raising the user-facing permission
  // dialog — important so BridgeConductor.compose() can embed `push_token`
  // in the very first verdict call. The permission dialog itself is still
  // deferred to OptInCurtain.Accept.
  await Future.wait<void>(<Future<void>>[
    SignalVault.prime(),
    GadgetFingerprint.prime(kApplicationId),
    NoticeStream.instance.primeToken(applicationId: kApplicationId),
  ]);

  // Rust engine comes up last so its FFI port is open before LoadingScreen
  // tries to talk to it. Must stay on the main isolate.
  await initializeRust(assignRustSignal);

  runApp(const SpireShell(applicationId: kApplicationId));
}
