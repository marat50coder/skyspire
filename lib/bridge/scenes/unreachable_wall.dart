// UnreachableWall — shown when WaveSensor cannot see any live adapter OR
// when AperturePane blew past the redirect-loop budget.
//
// Flat gradient background (no artwork per user request). Copy block is
// NO INTERNET CONNECTION + "Check your connection and try again".
//
// Button policy (pitfalls §16):
//   • Retry visible until `kOfflineRetryCap` retries.
//   • After the cap we swap the pill for a Contact-Support fallback so
//     users do not keep hammering a dead button.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shell/spire_buttons.dart';
import '../../shell/spire_theme.dart';
import '../charts/bridge_manifest.dart';
import '../charts/public_links.dart';

class UnreachableWall extends StatefulWidget {
  const UnreachableWall({
    super.key,
    required this.onRetryBuild,
  });

  /// Builder for the next screen when the user taps Retry. We build-and-swap
  /// instead of popping so a dead state cannot bubble upwards.
  final WidgetBuilder onRetryBuild;

  @override
  State<UnreachableWall> createState() => _UnreachableWallState();
}

class _UnreachableWallState extends State<UnreachableWall> {
  int _retries = 0;
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy || _retries >= kOfflineRetryCap) return;
    setState(() {
      _busy = true;
      _retries++;
    });
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.onRetryBuild),
    );
  }

  Future<void> _openSupport() async {
    try {
      await launchUrl(Uri.parse(PublicLinks.supportLink),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final retryExhausted = _retries >= kOfflineRetryCap;

    return Scaffold(
      backgroundColor: SpirePalette.abyssDeep,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              SpirePalette.abyssSoft,
              SpirePalette.abyss,
              SpirePalette.abyssDeep,
            ],
            stops: <double>[0, 0.5, 1],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(24, 24, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(flex: 3),
              const Icon(
                Icons.wifi_off_rounded,
                size: 72,
                color: SpirePalette.ember,
              ),
              const SizedBox(height: 20),
              const Text(
                'NO INTERNET CONNECTION',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SpirePalette.mist,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Check your connection and try again',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SpirePalette.mistDim,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  height: 1.4,
                ),
              ),
              const Spacer(flex: 4),
              if (!retryExhausted)
                SpirePillTap(
                  label: _busy ? 'Checking…' : 'Retry',
                  onPressed: _busy ? null : _retry,
                )
              else
                SpirePillTap(
                  label: 'Contact support',
                  onPressed: _openSupport,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
