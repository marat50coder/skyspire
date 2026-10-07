// SpireShell — root MaterialApp. Keeps every colour/font decision in one
// place so a redesign only has to touch SpireTheme.
//
// Also owns `rootNavigatorKey`: a single GlobalKey<NavigatorState> wired
// into MaterialApp.navigatorKey so background services (NoticeStream) can
// route the user to AperturePane without needing a BuildContext. Without
// this, a push-notification tap while the app was already running would
// only stash the URL in SignalVault but never actually open the webview —
// the user would stay on whatever screen was in front.
import 'package:flutter/material.dart';

import '../launch/launch_stage.dart';
import 'spire_theme.dart';

/// Single root navigator key. Exposed as a top-level `final` so any
/// background callback (NoticeStream.onMessageOpenedApp / local-tap) can
/// `rootNavigatorKey.currentState?.pushReplacement(...)` without threading a
/// BuildContext through the whole FCM wiring.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'spire-root-nav');

class SpireShell extends StatelessWidget {
  const SpireShell({super.key, required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skyspire',
      debugShowCheckedModeBanner: false,
      theme: SpireTheme.build(),
      navigatorKey: rootNavigatorKey,
      home: LaunchStage(applicationId: applicationId),
    );
  }
}
