import 'package:flutter/material.dart';

/// Warm Stone color tokens (design doc §5.1).
///
/// Single source of truth for the mobile app, mirroring the desktop
/// stylesheet `frontend/css/style.css` `:root` (dark defaults). Downstream UI
/// must reference these constants instead of redefining raw values.
abstract final class ConverColors {
  /// Page background — the deepest warm black layer.
  static const Color page = Color(0xFF171512);

  /// Base background above the page layer.
  static const Color bg = Color(0xFF1D1A16);

  /// Panel layers, ordered from dark to light.
  static const Color panel1 = Color(0xFF211E19);
  static const Color panel2 = Color(0xFF27231D);
  static const Color panel3 = Color(0xFF2E2922);
  static const Color panel4 = Color(0xFF373128);

  /// Warm-white (rgb 244, 237, 226) hairline borders at three opacities.
  static const Color border = Color.fromRGBO(244, 237, 226, 0.07);
  static const Color borderStrong = Color.fromRGBO(244, 237, 226, 0.13);
  static const Color borderTertiary = Color.fromRGBO(244, 237, 226, 0.04);

  /// Four-level text hierarchy, from primary to the faintest.
  static const Color ink1 = Color(0xFFF1ECE4);
  static const Color ink2 = Color(0xFFC8C0B5);
  static const Color ink3 = Color(0xFF9E9385);
  static const Color ink4 = Color(0xFF7F7467);

  /// Amber accent — the single interactive emphasis color.
  static const Color accent = Color(0xFFD29A47);

  /// Hover state of the accent.
  static const Color accentHover = Color(0xFFDFAA5C);

  /// Translucent amber wash (13%) for soft selected backgrounds.
  static const Color accentSoft = Color.fromRGBO(210, 154, 71, 0.13);

  /// Foreground drawn on top of the accent.
  static const Color onAccent = Color(0xFF21180D);

  /// Semantic status colors; warning reuses the amber accent.
  static const Color success = Color(0xFF79A781);
  static const Color danger = Color(0xFFCF7462);
  static const Color warning = Color(0xFFD29A47);
}

/// Corner radius tokens (§5.1: restrained radii 3-12, chat bubble 12).
abstract final class ConverRadii {
  static const double xs = 3;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;

  /// Chat bubble corner radius.
  static const double bubble = 12;
}

/// Spacing tokens on the 8pt grid (§5.1: 4/8/12/16/20/24/32/40/48).
///
/// Numeric suffixes intentionally mirror the desktop token names
/// (`--space-1` ... `--space-12`) so the two sides stay lookup-compatible.
abstract final class ConverSpacing {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
}
