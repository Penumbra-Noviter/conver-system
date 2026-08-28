import 'package:flutter/material.dart';

import 'colors.dart';

/// Assembles the Warm Stone dark [ThemeData] (design doc §5.1).
///
/// M0 scope only: color scheme, scaffold background, and NavigationBar theme
/// with the amber selected state. Light theme structure is deferred to M1;
/// font size tokens are undefined in §5.1 and deferred to M6.
abstract final class ConverTheme {
  /// Builds the locked dark theme.
  ///
  /// The app entry must inject this via an explicit `ThemeMode.dark`
  /// (assembly belongs to the navigation shell ticket) so system light mode
  /// can never leak default light colors.
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: ConverColors.accent,
      onPrimary: ConverColors.onAccent,
      secondary: ConverColors.accentHover,
      onSecondary: ConverColors.onAccent,
      surface: ConverColors.bg,
      onSurface: ConverColors.ink1,
      surfaceContainerLowest: ConverColors.page,
      surfaceContainerLow: ConverColors.panel1,
      surfaceContainer: ConverColors.panel2,
      surfaceContainerHigh: ConverColors.panel3,
      surfaceContainerHighest: ConverColors.panel4,
      error: ConverColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: ConverColors.page,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ConverColors.bg,
        indicatorColor: ConverColors.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? ConverColors.accent : ConverColors.ink3);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(color: selected ? ConverColors.accent : ConverColors.ink3);
        }),
      ),
    );
  }
}
