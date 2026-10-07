// OptInCurtain — "would you like notifications?" interstitial.
//
// Chrome stripped down per request: no title, no body copy, no privacy link.
// Only the two pill buttons remain (Accept + Skip, both share the same
// ember gradient).
//
// Navigation ownership used to live in LaunchStage via an onDecided
// callback. That caused a subtle bug: LaunchStage pushReplaces this curtain
// onto itself, so by the time the user tapped Accept, LaunchStage.State was
// already disposed, `_mounted` was false, and the callback silently did
// nothing. The user saw the notification system dialog, tapped Allow, and
// then... stayed on the curtain. Now this screen owns the next hop
// directly: it knows the destination URL + applicationId and does its own
// `Navigator.pushReplacement(AperturePane(...))`.
import 'package:flutter/material.dart';

import '../../shell/spire_buttons.dart';
import '../../shell/spire_media.dart';
import '../../shell/spire_theme.dart';
import '../charts/bridge_manifest.dart';
import '../pipeline/notice_stream.dart';
import '../pipeline/signal_vault.dart';
import 'aperture_pane.dart';

class OptInCurtain extends StatefulWidget {
  const OptInCurtain({
    super.key,
    required this.destination,
    required this.applicationId,
  });

  final String destination;
  final String applicationId;

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
    await _goToPortal();
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await SignalVault.snoozePermissionBy(kPermissionSnooze);
    await _goToPortal();
  }

  Future<void> _goToPortal() async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AperturePane(
          destination: widget.destination,
          applicationId: widget.applicationId,
        ),
      ),
    );
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
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 24, 24, 36),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SpirePillTap(
                    label: 'Accept',
                    onPressed: _busy ? null : _accept,
                  ),
                  const SizedBox(height: 14),
                  SpirePillTap(
                    label: 'Skip',
                    onPressed: _busy ? null : _skip,
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
