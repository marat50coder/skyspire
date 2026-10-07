// LaunchStage — the first widget mounted after main(). Shows the loading
// background, runs BridgeConductor.decide() on a Future and swaps itself out
// for the appropriate screen (HomeBerth → MainMenuScreen, PortalBerth →
// AperturePane, UnreachableBerth → UnreachableWall).
//
// We enforce `kMinimumSplashLinger` so the user always sees the artwork for
// at least ~1.6s — otherwise a fast decide() path would flash the splash and
// jump straight into either the game or the WebView.
import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/bridge_conductor.dart';
import '../bridge/charts/bridge_manifest.dart';
import '../bridge/outcome/berth.dart';
import '../bridge/pipeline/signal_vault.dart';
import '../bridge/scenes/aperture_pane.dart';
import '../bridge/scenes/opt_in_curtain.dart';
import '../bridge/scenes/unreachable_wall.dart';
import '../shell/spire_media.dart';
import '../shell/spire_theme.dart';
import '../src/screens/loading_screen.dart';

class LaunchStage extends StatefulWidget {
  const LaunchStage({
    super.key,
    required this.applicationId,
  });

  final String applicationId;

  @override
  State<LaunchStage> createState() => _LaunchStageState();
}

class _LaunchStageState extends State<LaunchStage>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final BridgeConductor _conductor;
  Timer? _dotTicker;
  int _dots = 0;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _conductor = BridgeConductor(applicationId: widget.applicationId);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _dotTicker = Timer.periodic(
      const Duration(milliseconds: 420),
      (_) => setState(() => _dots = (_dots + 1) % 4),
    );
    _advance();
  }

  Future<void> _advance() async {
    final progressTicker = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) {
        if (!mounted) return;
        setState(() {
          _progress = (_progress + 0.03).clamp(0.0, 0.92);
        });
      },
    );
    final startedAt = DateTime.now();
    Berth berth;
    try {
      berth = await _conductor.decide();
    } catch (_) {
      berth = const HomeBerth();
    }
    progressTicker.cancel();

    // Enforce minimum splash duration so the artwork isn't a flash.
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < kMinimumSplashLinger) {
      await Future<void>.delayed(kMinimumSplashLinger - elapsed);
    }
    setState(() => _progress = 1);
    await Future<void>.delayed(const Duration(milliseconds: 220));

    if (!mounted) return;
    await _route(berth);
  }

  Future<void> _route(Berth berth) async {
    final nav = Navigator.of(context);
    switch (berth) {
      case HomeBerth():
        // Hand off to the native game's own splash — that path owns Rust
        // sprite/settings/wallet warm-up and finally lands on MainMenuScreen.
        await nav.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const LoadingScreen(),
          ),
        );
      case PortalBerth(destination: final url):
        final shouldPrompt = await _shouldPromptPermission();
        if (shouldPrompt) {
          // OptInCurtain owns the hop to AperturePane itself (see the
          // comment at the top of opt_in_curtain.dart about the mounted-
          // after-pushReplacement bug).
          await nav.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => OptInCurtain(
                destination: url,
                applicationId: widget.applicationId,
              ),
            ),
          );
        } else {
          await nav.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AperturePane(
                destination: url,
                applicationId: widget.applicationId,
              ),
            ),
          );
        }
      case UnreachableBerth():
        await nav.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => UnreachableWall(
              onRetryBuild: (_) => LaunchStage(
                applicationId: widget.applicationId,
              ),
            ),
          ),
        );
    }
  }

  Future<bool> _shouldPromptPermission() async {
    if (await SignalVault.permissionAccepted()) return false;
    if (await SignalVault.permissionDeniedByOs()) return false;
    final snoozeUntil = await SignalVault.permissionSnoozeUntil();
    if (snoozeUntil != null && snoozeUntil.isAfter(DateTime.now())) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _dotTicker?.cancel();
    _pulse.dispose();
    _conductor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final bg = isLandscape
        ? SpireMedia.landscapeLoading
        : SpireMedia.portraitLoading;

    return Scaffold(
      backgroundColor: SpirePalette.abyssDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x44000000),
                  Color(0xB3000000),
                ],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 24, 24, 36),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.55, end: 1.0).animate(_pulse),
                    child: Text(
                      'Loading${'.' * _dots}',
                      style: SpireTheme.titleStyle(size: 18, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 4,
                    width: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          SpirePalette.ember,
                        ),
                        backgroundColor: SpirePalette.edge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
