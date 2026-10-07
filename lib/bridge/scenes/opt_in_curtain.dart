// OptInCurtain — the "would you like notifications?" interstitial.
//
// Buttons (per user brief): ACCEPT + SKIP.
// Flow:
//   • ACCEPT → NoticeStream.prime() → push the next Berth.
//   • SKIP   → stamp a 90-hour snooze into SignalVault → push the next Berth.
//
// Both paths always continue — this screen is strictly informational. The
// permission dialog itself is raised by NoticeStream.prime(); if the OS
// rejects it (user tapped "Don't allow" earlier) we flip the OS-denied flag
// so we never re-ask on this install.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shell/spire_buttons.dart';
import '../../shell/spire_media.dart';
import '../../shell/spire_theme.dart';
import '../charts/bridge_manifest.dart';
import '../charts/public_links.dart';
import '../pipeline/notice_stream.dart';
import '../pipeline/signal_vault.dart';

class OptInCurtain extends StatefulWidget {
  const OptInCurtain({
    super.key,
    required this.onDecided,
  });

  final VoidCallback onDecided;

  @override
  State<OptInCurtain> createState() => _OptInCurtainState();
}

class _OptInCurtainState extends State<OptInCurtain> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await NoticeStream.instance.prime();
      await SignalVault.markPermissionAccepted(true);
    } catch (_) {
      await SignalVault.markPermissionDeniedByOs(true);
    }
    if (!mounted) return;
    widget.onDecided();
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await SignalVault.snoozePermissionBy(kPermissionSnooze);
    if (!mounted) return;
    widget.onDecided();
  }

  Future<void> _openPrivacy() async {
    final uri = Uri.parse(PublicLinks.privacyLink);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final bg = isLandscape
        ? SpireMedia.landscapeNotice
        : SpireMedia.portraitNotice;

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
                  Color(0x66000000),
                  Color(0xCC000000),
                ],
                stops: <double>[0, 0.55, 1],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Spacer(),
                Text(
                  'Stay in the loop',
                  textAlign: TextAlign.center,
                  style: SpireTheme.titleStyle(size: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  'Allow notifications so you never miss a bonus round, a\n'
                  'cash-out alert, or a weekend tournament invite.',
                  textAlign: TextAlign.center,
                  style: SpireTheme.bodyStyle(),
                ),
                const SizedBox(height: 28),
                SpirePillTap(
                  label: 'Accept',
                  onPressed: _busy ? null : _accept,
                ),
                const SizedBox(height: 14),
                Center(
                  child: SpireTextTap(
                    label: 'Skip',
                    onPressed: _busy ? null : _skip,
                    trailing: const Icon(Icons.schedule, size: 18),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: SpireTextTap(
                    label: 'Privacy policy',
                    onPressed: _openPrivacy,
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
