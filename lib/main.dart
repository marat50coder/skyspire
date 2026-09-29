import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Hide the status and navigation bars: nothing but the game is on screen.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SkyspireApp());
}

class SkyspireApp extends StatelessWidget {
  const SkyspireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skyspire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF15171A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7EE0),
          brightness: Brightness.dark,
        ),
      ),
      home: const LoadingScreen(),
    );
  }
}
