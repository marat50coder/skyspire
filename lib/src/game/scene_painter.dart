import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'engine.dart';
import 'sprites.dart';

/// Draws the whole Skyspire scene: sky, city, tower, crane and effects.
class ScenePainter extends CustomPainter {
  ScenePainter({required this.engine, required this.sprites, required this.repaint})
    : super(repaint: repaint);

  final SkyEngine engine;
  final Sprites sprites;
  final Listenable repaint;

  /// Height fraction of the city bitmap where the pavement surface sits.
  static const double _cityGroundFraction = 0.845;

  /// Height fraction of the hook bitmap where the load hangs.
  static const double _hookPivotFraction = 0.86;

  final Paint _img = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    final Metrics m = engine.m;
    canvas.clipRect(Offset.zero & size);

    _paintSky(canvas, size);
    _paintClouds(canvas, size);
    _paintCity(canvas, size);
    _paintBase(canvas);
    _paintTower(canvas);
    _paintDebris(canvas, size);
    _paintFlying(canvas);
    _paintPuffs(canvas, size);
    _paintCrane(canvas, m);
    _paintPopup(canvas, m);
  }

  // ---- background ---------------------------------------------------------

  void _paintSky(Canvas canvas, Size size) {
    final ui.Image sky = sprites.sky;
    // A window into the gradient that slides towards the deeper blue at the
    // top of the bitmap as the camera climbs.
    const double span = 0.46;
    const double startTop = 1 - span;
    final double t = (engine.camScroll / (size.height * 16)).clamp(0.0, 1.0);
    final double srcTop = startTop * (1 - t);
    canvas.drawImageRect(
      sky,
      Rect.fromLTWH(
        0,
        sky.height * srcTop,
        sky.width.toDouble(),
        sky.height * span,
      ),
      Offset.zero & size,
      _img,
    );
  }

  void _paintClouds(Canvas canvas, Size size) {
    final Metrics m = engine.m;
    for (final Cloud c in engine.clouds) {
      final double y = engine.cloudScreenY(c);
      final double w = m.w * 0.62 * c.scale;
      final ui.Image img = sprites.clouds[c.sprite];
      final double hh = w * img.height / img.width;
      if (y + hh < -m.h * 0.2 || y - hh > m.h * 1.2) continue;
      _img.color = Colors.white.withValues(alpha: c.alpha);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(c.x - w / 2, y - hh / 2, w, hh),
        _img,
      );
      _img.color = const Color(0xFFFFFFFF);
    }
  }

  void _paintCity(Canvas canvas, Size size) {
    final Metrics m = engine.m;
    final ui.Image img = sprites.city;
    final double w = m.w * 1.25;
    final double h = w * img.height / img.width;
    final double groundScreen = engine.screenY(0);
    final double top = groundScreen - _cityGroundFraction * h;
    final double left = (m.w - w) / 2;
    if (top > size.height) return;

    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(left, top, w, h),
      _img,
    );

    // Stretch the bottom of the road down so there is never a gap below it,
    // then shade it so the flat strip reads as asphalt falling into shadow.
    final double bottom = top + h;
    if (bottom < size.height) {
      const double slice = 0.035;
      final Rect fill = Rect.fromLTRB(0, bottom - 1, size.width, size.height);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(
          0,
          img.height * (1 - slice),
          img.width.toDouble(),
          img.height * slice,
        ),
        Rect.fromLTRB(left, fill.top, left + w, fill.bottom),
        _img,
      );
      canvas.drawRect(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            fill.topLeft,
            fill.bottomLeft,
            const <Color>[Color(0x00000000), Color(0x77000000)],
          ),
      );
    }
  }

  // ---- tower --------------------------------------------------------------

  void _paintBase(Canvas canvas) {
    final Metrics m = engine.m;
    final double w = m.baseW;
    final double h = w / engine.baseAspect;
    final double bottom = engine.screenY(0);
    if (bottom - h > m.h) return;
    _drawBlock(
      canvas,
      sprites.base,
      cx: m.axisX,
      cy: bottom - h / 2,
      w: w,
      h: h,
      angle: 0,
    );
  }

  void _paintTower(Canvas canvas) {
    final Metrics m = engine.m;
    for (final PlacedBlock b in engine.tower) {
      final double bottom = engine.screenY(b.bottomY);
      if (bottom < -b.height || bottom - b.height > m.h) continue;
      // Short squash on impact, like a weight settling into place.
      final double s = b.squash;
      final double sy = 1 - 0.09 * s;
      final double sx = 1 + 0.07 * s;
      final double hh = b.height * sy;
      _drawBlock(
        canvas,
        sprites.blocks[b.sprite],
        cx: m.axisX + b.dx,
        cy: bottom - hh / 2,
        w: b.width * sx,
        h: hh,
        angle: b.angle,
      );
    }
  }

  void _paintDebris(Canvas canvas, Size size) {
    for (final Flying d in engine.debris) {
      final double y = engine.screenY(d.y);
      if (y < -d.height || y > size.height + d.height) continue;
      _drawBlock(
        canvas,
        sprites.blocks[d.sprite],
        cx: d.x,
        cy: y,
        w: d.width,
        h: d.height,
        angle: d.angle,
      );
    }
  }

  void _paintFlying(Canvas canvas) {
    final Flying? f = engine.flying;
    if (f == null) return;
    _drawBlock(
      canvas,
      sprites.blocks[f.sprite],
      cx: f.x,
      cy: engine.screenY(f.y),
      w: f.width,
      h: f.height,
      angle: f.angle,
    );
  }

  // ---- effects ------------------------------------------------------------

  void _paintPuffs(Canvas canvas, Size size) {
    for (final Puff p in engine.puffs) {
      final double t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final double alpha = t < 0.25 ? t / 0.25 : 1.0;
      final ui.Image img = sprites.clouds[p.sprite];
      final double w = p.size;
      final double h = w * img.height / img.width;
      final double y = engine.screenY(p.y);
      if (y < -h || y > size.height + h) continue;
      _img.color = Colors.white.withValues(alpha: alpha * 0.92);
      canvas.save();
      canvas.translate(p.x, y);
      canvas.rotate(p.angle);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(-w / 2, -h / 2, w, h),
        _img,
      );
      canvas.restore();
      _img.color = const Color(0xFFFFFFFF);
    }
  }

  // ---- crane --------------------------------------------------------------

  void _paintCrane(Canvas canvas, Metrics m) {
    final ui.Image hook = sprites.hook;
    final double hw = m.w * 0.105;
    final double hh = hw * hook.height / hook.width;
    final double pivotY = engine.pivotScreenY;
    final double top = pivotY - hh * _hookPivotFraction;

    // Rope reaching up beyond the top edge of the play area.
    if (top > 0) {
      final Paint rope = Paint()
        ..color = const Color(0xFF1C1C1C)
        ..strokeWidth = m.w * 0.009
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(
        Offset(engine.trolleyX - hw * 0.24, 0),
        Offset(engine.trolleyX - hw * 0.24, top + 2),
        rope,
      );
      canvas.drawLine(
        Offset(engine.trolleyX + hw * 0.24, 0),
        Offset(engine.trolleyX + hw * 0.24, top + 2),
        rope,
      );
    }

    if (engine.hasHangingBlock) {
      _paintHangingBlock(canvas, m, pivotY);
    }

    canvas.drawImageRect(
      hook,
      Rect.fromLTWH(0, 0, hook.width.toDouble(), hook.height.toDouble()),
      Rect.fromLTWH(engine.trolleyX - hw / 2, top, hw, hh),
      _img,
    );
  }

  void _paintHangingBlock(Canvas canvas, Metrics m, double pivotY) {
    final int sprite = engine.currentSprite;
    final double bw = m.blockW;
    final double bh = engine.blockHeight(sprite);
    final double cx = engine.hangCenterX;
    final double cy = engine.hangCenterY;
    final double a = engine.theta;
    final double ca = math.cos(a);
    final double sa = math.sin(a);

    Offset corner(double lx, double ly) =>
        Offset(cx + lx * ca - ly * sa, cy + lx * sa + ly * ca);

    final Paint sling = Paint()
      ..color = const Color(0xFF1C1C1C)
      ..strokeWidth = m.w * 0.0065
      ..strokeCap = StrokeCap.round;
    final Offset pivot = Offset(engine.trolleyX, pivotY);
    canvas.drawLine(pivot, corner(-bw * 0.33, -bh * 0.45), sling);
    canvas.drawLine(pivot, corner(bw * 0.33, -bh * 0.45), sling);

    _drawBlock(
      canvas,
      sprites.blocks[sprite],
      cx: cx,
      cy: cy,
      w: bw,
      h: bh,
      angle: a,
    );
  }

  // ---- popup --------------------------------------------------------------

  void _paintPopup(Canvas canvas, Metrics m) {
    final Popup? p = engine.popup;
    if (p == null) return;

    final double t = (p.age / p.life).clamp(0.0, 1.0);
    // Overshoot on the way in, fade and drift up on the way out.
    double scale;
    if (p.age < 0.26) {
      final double u = p.age / 0.26;
      scale = 1.25 - 0.25 * math.cos(u * math.pi * 0.5) - 0.55 * (1 - u) * (1 - u);
      scale = scale.clamp(0.05, 1.3);
    } else {
      scale = 1 + 0.05 * (t - 0.2);
    }
    final double fade = t > 0.75 ? 1 - (t - 0.75) / 0.25 : 1.0;
    final double rise = t > 0.5 ? (t - 0.5) * m.h * 0.12 : 0.0;

    final bool zero = p.kind == PopupKind.zero;
    final double fontSize = m.w * (zero ? 0.30 : 0.26) / (1 + p.text.length * 0.035);

    canvas.save();
    canvas.translate(p.x, p.y - rise);
    canvas.scale(scale);

    final TextStyle base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      letterSpacing: -fontSize * 0.02,
      height: 1.0,
    );

    final TextPainter stroke = _layout(
      p.text,
      base.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = fontSize * 0.15
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      ),
    );
    final TextPainter fill = _layout(
      p.text,
      base.copyWith(
        foreground: zero
            ? (Paint()..color = const Color(0xFFD62C2C))
            : (Paint()
                ..shader = ui.Gradient.linear(
                  Offset(0, -stroke.height * 0.4),
                  Offset(0, stroke.height * 0.55),
                  const <Color>[Color(0xFFFFE066), Color(0xFFEE7C12)],
                )),
      ),
    );

    final Offset at = Offset(-stroke.width / 2, -stroke.height / 2);
    canvas.saveLayer(
      Rect.fromCenter(
        center: Offset.zero,
        width: stroke.width * 1.6,
        height: stroke.height * 2,
      ),
      Paint()..color = Colors.white.withValues(alpha: fade),
    );
    stroke.paint(canvas, at);
    fill.paint(canvas, at);
    canvas.restore();
    canvas.restore();
  }

  TextPainter _layout(String text, TextStyle style) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  // ---- helpers ------------------------------------------------------------

  /// Draws a block sprite so that only its opaque content occupies the
  /// destination rectangle (no transparent padding around it).
  void _drawBlock(
    Canvas canvas,
    BlockSprite sprite, {
    required double cx,
    required double cy,
    required double w,
    required double h,
    required double angle,
  }) {
    canvas.save();
    canvas.translate(cx, cy);
    if (angle != 0) canvas.rotate(angle);
    canvas.drawImageRect(
      sprite.image,
      sprite.trim,
      Rect.fromLTWH(-w / 2, -h / 2, w, h),
      _img,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) => true;
}
