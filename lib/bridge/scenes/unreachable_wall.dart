// UnreachableWall — shown when WaveSensor cannot see any live adapter OR
// when AperturePane blew past the redirect-loop budget.
//
// Flat gradient background, headline + sub-copy, single Retry pill. There
// is no "Contact support" / Privacy / Support fallback — per the audit
// requirement, no plaintext proxy URL is allowed to ship in the client.
import 'package:flutter/material.dart';

import '../../shell/spire_buttons.dart';
import '../../shell/spire_theme.dart';
import '../charts/bridge_manifest.dart';

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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final retryExhausted = _retries >= kOfflineRetryCap;

    // In landscape the screen is much wider than it is tall; a full-width
    // pill looks like a bar across the display. Shrink it by 20% from each
    // side so it occupies the center 60% of the available width.
    final EdgeInsets pillPadding = isLandscape
        ? EdgeInsets.symmetric(horizontal: mq.size.width * 0.2)
        : EdgeInsets.zero;

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
              Padding(
                padding: pillPadding,
                child: SpirePillTap(
                  label: retryExhausted
                      ? 'Please try later'
                      : (_busy ? 'Checking…' : 'Retry'),
                  onPressed:
                      (retryExhausted || _busy) ? null : _retry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
