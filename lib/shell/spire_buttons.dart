// SpirePillTap / SpireTextTap — the two button styles used across the
// bridge-flow screens.
//
// Design differs from the sibling template on purpose: template uses a
// sky-blue gradient and a thin underline for text buttons; here we use an
// ember-glow filled pill with a thin top-highlight line, plus a muted ember
// text button with a right-pointing chevron.
import 'package:flutter/material.dart';

import 'spire_theme.dart';

class SpirePillTap extends StatelessWidget {
  const SpirePillTap({
    super.key,
    required this.label,
    required this.onPressed,
    this.width,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: enabled
                    ? const <Color>[
                        SpirePalette.emberBright,
                        SpirePalette.ember,
                        SpirePalette.emberDeep,
                      ]
                    : const <Color>[
                        Color(0xFF4A4D64),
                        Color(0xFF3A3D54),
                      ],
                stops: enabled ? const <double>[0, 0.55, 1] : null,
              ),
              boxShadow: enabled
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x66F2A341),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : null,
              border: const Border(
                top: BorderSide(color: Color(0x80FFFFFF), width: 1),
              ),
            ),
            child: Center(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: enabled
                      ? SpirePalette.abyssDeep
                      : SpirePalette.mistDim,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SpireTextTap extends StatelessWidget {
  const SpireTextTap({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailing = const Icon(Icons.chevron_right, size: 18),
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: enabled ? SpirePalette.mist : SpirePalette.mistDim,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 4),
            IconTheme(
              data: IconThemeData(
                color: enabled ? SpirePalette.mist : SpirePalette.mistDim,
              ),
              child: trailing,
            ),
          ],
        ),
      ),
    );
  }
}
