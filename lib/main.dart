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
import 'bridge/pipeline/signal_vault.dart';
import 'shell/spire_shell.dart';
import 'src/bindings/bindings.dart';

/// Must match the Android applicationId / iOS bundle id.
const String kApplicationId = 'com.skyspire.spiregame';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Firebase is optional: credentials ship later. Swallow init errors so a
  // missing google-services.json never prevents the game from running.
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Fire the two prime-only tasks in parallel.
  await Future.wait<void>(<Future<void>>[
    SignalVault.prime(),
    GadgetFingerprint.prime(kApplicationId),
  ]);

  // Rust engine comes up last so its FFI port is open before LoadingScreen
  // tries to talk to it. Must stay on the main isolate.
  await initializeRust(assignRustSignal);

  runApp(const SpireShell(applicationId: kApplicationId));
}
