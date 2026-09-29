import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Diagonal hazard stripes used by the top bar of the original game.
class StripesPainter extends CustomPainter {
  const StripesPainter({this.color = Palette.barStripe, this.width = 14, this.gap = 14});

  final Color color;
  final double width;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = width;
    final double step = width + gap;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant StripesPainter old) => false;
}

/// The chunky blue button the original uses for ALL IN, x2 and CASHOUT.
class BlueButton extends StatefulWidget {
  const BlueButton({
    super.key,
    required this.onTap,
    required this.child,
    this.height = 46,
    this.radius = 10,
    this.enabled = true,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double height;
  final double radius;
  final bool enabled;

  @override
  State<BlueButton> createState() => _BlueButtonState();
}

class _BlueButtonState extends State<BlueButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled && widget.onTap != null;
    return GestureDetector(
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapCancel: on ? () => setState(() => _down = false) : null,
      onTapUp: on ? (_) => setState(() => _down = false) : null,
      onTap: on ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 70),
        child: Opacity(
          opacity: on ? 1 : 0.45,
          child: Container(
            height: widget.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Palette.blue, Palette.blueDeep],
              ),
              border: Border.all(color: Palette.blueEdge.withValues(alpha: 0.65), width: 1.4),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// BUILD button drawn on top of the hazard plate artwork.
///
/// Keeps the artwork's natural aspect ratio: no horizontal stretching even
/// when the parent Row hands it a wide slot.
class PlateButton extends StatefulWidget {
  const PlateButton({
    super.key,
    required this.image,
    required this.onTap,
    required this.enabled,
    this.height = 56,
  });

  final ImageProvider image;
  final VoidCallback onTap;
  final bool enabled;
  final double height;

  @override
  State<PlateButton> createState() => _PlateButtonState();
}

class _PlateButtonState extends State<PlateButton> with SingleTickerProviderStateMixin {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: widget.enabled ? () => setState(() => _down = false) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 70),
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : 0.42,
          duration: const Duration(milliseconds: 160),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Center(
              child: Image(
                image: widget.image,
                fit: BoxFit.fitHeight,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small round stepper button of the bet field.
class RoundStepButton extends StatelessWidget {
  const RoundStepButton({super.key, required this.icon, required this.onTap, this.size = 30});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF474D55),
          ),
          child: Icon(icon, size: size * 0.62, color: Colors.white),
        ),
      ),
    );
  }
}

/// One multiplier badge of the Results column.
class ResultChip extends StatelessWidget {
  const ResultChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: Palette.chipBg.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.chipEdge, width: 1.2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Palette.chipText,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Full width banner used for OOPS! and YOU WIN.
class ResultBanner extends StatelessWidget {
  const ResultBanner({
    super.key,
    required this.text,
    required this.win,
    this.subtitle,
  });

  final String text;
  final bool win;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: win
              ? const <Color>[Palette.winA, Palette.winB]
              : const <Color>[Palette.oopsA, Palette.oopsB],
        ),
        border: const Border(
          top: BorderSide(color: Color(0x55FFFFFF), width: 1.5),
          bottom: BorderSide(color: Color(0x33000000), width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _StrokedText(text, size: 27),
          if (subtitle != null) ...<Widget>[
            const SizedBox(width: 12),
            _StrokedText(subtitle!, size: 22),
          ],
        ],
      ),
    );
  }
}

class _StrokedText extends StatelessWidget {
  const _StrokedText(this.text, {required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.5,
    );
    return Stack(
      children: <Widget>[
        Text(
          text,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.18
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xCC2A1200),
          ),
        ),
        Text(text, style: base.copyWith(color: Colors.white)),
      ],
    );
  }
}

/// Animated "Loading . . ." caption of the splash screen.
class LoadingDots extends StatefulWidget {
  const LoadingDots({super.key, this.style});

  final TextStyle? style;

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = widget.style ?? const TextStyle(fontSize: 18);
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        final int n = (_c.value * 4).floor() % 4;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Loading', style: style),
            SizedBox(
              width: style.fontSize! * 1.7,
              child: Text('.' * n, style: style),
            ),
          ],
        );
      },
    );
  }
}

/// Horizontal progress bar of the splash screen.
class SkyProgressBar extends StatelessWidget {
  const SkyProgressBar({super.key, required this.value, required this.width});

  final double value;
  final double width;

  @override
  Widget build(BuildContext context) {
    const double h = 16;
    return Container(
      width: width,
      height: h,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x99101418),
        borderRadius: BorderRadius.circular(h),
        border: Border.all(color: const Color(0xCCFFFFFF), width: 1.6),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: math.max(0.0, math.min(1.0, value)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFFFFE066), Color(0xFFF2921D)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
