// SpireTheme — colour tokens and typography for every bridge-flow screen.
//
// The palette is derived from the Skyspire tower artwork (deep indigo
// twilight + warm ember accents) — intentionally different from the sibling
// template's "sky blue" scheme so a visual diff between the two apps is
// obvious even to a human reviewer.
import 'package:flutter/material.dart';

class SpirePalette {
  const SpirePalette._();

  // Primary deep indigo — mapped to the night sky in the loading screen.
  static const Color abyss = Color(0xFF0E1230);
  static const Color abyssDeep = Color(0xFF070927);
  static const Color abyssSoft = Color(0xFF1A1F4A);

  // Warm highlight — matches the ember glow on the Skyspire tower apex.
  static const Color ember = Color(0xFFF2A341);
  static const Color emberBright = Color(0xFFFFC66B);
  static const Color emberDeep = Color(0xFFC57818);

  // Supporting tones.
  static const Color mist = Color(0xFFE7E9F8);
  static const Color mistDim = Color(0xFF9CA2C7);
  static const Color edge = Color(0x33FFFFFF);
}

class SpireTheme {
  const SpireTheme._();

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: SpirePalette.abyss,
      colorScheme: const ColorScheme.dark(
        primary: SpirePalette.ember,
        onPrimary: SpirePalette.abyssDeep,
        secondary: SpirePalette.emberBright,
        onSecondary: SpirePalette.abyssDeep,
        surface: SpirePalette.abyssSoft,
        onSurface: SpirePalette.mist,
      ),
      textTheme: base.textTheme
          .apply(
            fontFamily: 'Roboto',
            bodyColor: SpirePalette.mist,
            displayColor: SpirePalette.mist,
          ),
    );
  }

  /// Headline style used by OptInCurtain and UnreachableWall.
  static TextStyle titleStyle({double size = 22, FontWeight weight = FontWeight.w700}) {
    return TextStyle(
      color: SpirePalette.mist,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: 0.2,
      height: 1.0, // see pitfalls §11 — zero line-height breaks safe-area math
    );
  }

  /// Body style for descriptions.
  static TextStyle bodyStyle({double size = 14}) {
    return TextStyle(
      color: SpirePalette.mistDim,
      fontSize: size,
      fontWeight: FontWeight.w400,
      height: 1.35,
    );
  }
}
