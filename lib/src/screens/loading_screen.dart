import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';
import '../data/wallet.dart';
import '../game/sprites.dart';
import '../ui/widgets.dart';
import 'main_menu_screen.dart';

/// Splash screen. Works in both orientations and only fills the bar
/// completely right before the main menu opens.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  static const double _cap = 0.92;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  Sprites? _sprites;
  Wallet? _wallet;
  Settings? _settings;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _c.addListener(() => setState(() {}));
    _c.forward();
    _boot();
  }

  Future<void> _boot() async {
    final DateTime started = DateTime.now();
    final List<Object> loaded = await Future.wait(<Future<Object>>[
      Sprites.load(),
      Wallet.load(),
      Settings.load(),
    ]);
    _sprites = loaded[0] as Sprites;
    _wallet = loaded[1] as Wallet;
    _settings = loaded[2] as Settings;

    // Never flash past the splash: keep it up long enough for the bar to
    // crawl, then run it to the very end.
    final int elapsed = DateTime.now().difference(started).inMilliseconds;
    final int wait = math.max(0, 3200 - elapsed);
    await Future<void>.delayed(Duration(milliseconds: wait));
    if (!mounted) return;

    setState(() => _leaving = true);
    await Future<void>.delayed(const Duration(milliseconds: 620));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (
          BuildContext context,
          Animation<double> a,
          Animation<double> s,
        ) =>
            MainMenuScreen(
              sprites: _sprites!,
              wallet: _wallet!,
              settings: _settings!,
            ),
        transitionsBuilder: (
          BuildContext context,
          Animation<double> a,
          Animation<double> s,
          Widget child,
        ) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _progress {
    // Decelerating crawl up to the cap, then a quick run to 100%.
    final double crawl = Curves.easeOutCubic.transform(_c.value) * _cap;
    return _leaving ? math.max(crawl, _cap) + (1 - _cap) : crawl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3FA8E0),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool portrait = c.maxHeight >= c.maxWidth;
          final String bg = portrait
              ? 'assets/Skyspire_additional_assets/Vertical_Loading_Screen.webp'
              : 'assets/Skyspire_additional_assets/Horizontal_Loading_Screen.webp';
          final double barWidth = math.min(c.maxWidth * 0.72, 460);
          final double fontSize = portrait ? 18 : 16;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(bg, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
              Align(
                alignment: Alignment(0, portrait ? 0.78 : 0.74),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    LoadingDots(
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1.1,
                        shadows: const <Shadow>[
                          Shadow(color: Color(0xAA1B3B55), blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: _progress),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      builder: (
                        BuildContext context,
                        double v,
                        Widget? _,
                      ) =>
                          SkyProgressBar(value: v, width: barWidth),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
