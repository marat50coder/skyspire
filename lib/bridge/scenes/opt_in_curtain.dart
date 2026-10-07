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
      await NoticeStream.instance.prime(applicationId: widget.applicationId);
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
            stops: <double>[0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(24, 24, 24, 36),
          child: isLandscape ? _buildLandscape() : _buildPortrait(),
        ),
      ),
    );
  }

  // Headline block requested verbatim by the user. UPPERCASE lines are the
  // call-to-action; the trailing two lines are the softer sub-copy.
  Widget _buildHeadline({TextAlign align = TextAlign.center}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'ALLOW\nNOTIFICATION\nABOUT BONUSES\nAND PROMOS',
          textAlign: align,
          style: TextStyle(
            color: SpirePalette.mist,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Stay tuned for special\noffers nad rewards',
          textAlign: align,
          style: TextStyle(
            color: SpirePalette.mistDim,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // Portrait: headline pulled down to the vertical mid-point, pills pinned
  // to the bottom. User explicitly asked for the copy to sit closer to the
  // centre of the screen in vertical mode (default top-anchored layout
  // looked too high against the gradient background).
  Widget _buildPortrait() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Spacer(flex: 5),
        _buildHeadline(),
        const Spacer(flex: 4),
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
    );
  }

  // Landscape: headline on the left half, two small pills on the right half
  // on one baseline. Pills remain ~1/4 of the portrait width per the user's
  // earlier "в 4 раза меньше" request against the horizontal art.
  Widget _buildLandscape() {
    const double kLandscapePillWidth = 170;
    const double kLandscapePillHeight = 44;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildHeadline(align: TextAlign.left),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  SpirePillTap(
                    label: 'Accept',
                    width: kLandscapePillWidth,
                    height: kLandscapePillHeight,
                    onPressed: _busy ? null : _accept,
                  ),
                  const SizedBox(width: 20),
                  SpirePillTap(
                    label: 'Skip',
                    width: kLandscapePillWidth,
                    height: kLandscapePillHeight,
                    onPressed: _busy ? null : _skip,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
