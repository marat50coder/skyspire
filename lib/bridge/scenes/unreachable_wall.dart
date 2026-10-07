// UnreachableWall — shown when WaveSensor cannot see any live adapter OR
// when AperturePane blew past the redirect-loop budget.
//
// Button policy (pitfalls §16):
//   • Retry visible until `kOfflineRetryCap` retries.
//   • After the cap we hide Retry entirely and only expose the Support link.
//     Otherwise users keep tapping the dead button and generate noise.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shell/spire_buttons.dart';
import '../../shell/spire_media.dart';
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
    // Replace rather than pushReplace — avoids any lingering state in the
    // retry builder; the LaunchStage will spin up a fresh BridgeConductor.
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
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final bg = isLandscape
        ? SpireMedia.landscapeOffline
        : SpireMedia.portraitOffline;
    final retryExhausted = _retries >= kOfflineRetryCap;

    return Scaffold(
      backgroundColor: SpirePalette.abyssDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover),
          Container(color: const Color(0xB3030516)),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Spacer(),
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 72,
                  color: SpirePalette.ember,
                ),
                const SizedBox(height: 16),
                Text(
                  "You're offline",
                  textAlign: TextAlign.center,
                  style: SpireTheme.titleStyle(size: 24),
                ),
                const SizedBox(height: 10),
                Text(
                  retryExhausted
                      ? "We couldn't reach the servers after several tries.\n"
                          "Please check your connection or ping support."
                      : "Check your Wi-Fi or mobile data and tap Retry\n"
                          "to pick up where you left off.",
                  textAlign: TextAlign.center,
                  style: SpireTheme.bodyStyle(),
                ),
                const SizedBox(height: 28),
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
                const SizedBox(height: 12),
                if (!retryExhausted)
                  Center(
                    child: SpireTextTap(
                      label: 'Support',
                      onPressed: _openSupport,
                      trailing: const Icon(Icons.open_in_new, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
