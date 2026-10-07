// SpireShell — root MaterialApp. Keeps every colour/font decision in one
// place so a redesign only has to touch SpireTheme.
import 'package:flutter/material.dart';

import '../launch/launch_stage.dart';
import 'spire_theme.dart';

class SpireShell extends StatelessWidget {
  const SpireShell({super.key, required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skyspire',
      debugShowCheckedModeBanner: false,
      theme: SpireTheme.build(),
      home: LaunchStage(applicationId: applicationId),
    );
  }
}
