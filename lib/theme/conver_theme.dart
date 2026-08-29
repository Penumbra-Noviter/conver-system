import 'package:flutter/material.dart';

import 'colors.dart';
import 'conver_palette.dart';

/// Assembles the Warm Stone [ThemeData] pair (design doc §5.1).
///
/// [dark] 与 [light] 结构同构：colorScheme、scaffold 背景与 NavigationBar
/// 主题（琥珀/深琥珀选中态），仅 token 取自深/浅两套色板
/// （[ConverColors] / [ConverColorsLight]）。装配端（工单 07）以
/// `darkTheme: dark()` + `theme: light()` + 响应式 `themeMode` 注入。
/// Font size tokens are undefined in §5.1 and deferred to M6.
abstract final class ConverTheme {
  /// Builds the locked dark theme (desktop `:root` defaults).
  ///
  /// The app entry must inject this as `darkTheme` with a [ThemeMode] bound
  /// to the persisted theme preference so system light mode can never leak
  /// default light colors before the preference loads.
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
      extensions: [ConverPalette.dark()],
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ConverColors.bg,
        indicatorColor: ConverColors.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? ConverColors.accent : ConverColors.ink3,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? ConverColors.accent : ConverColors.ink3,
          );
        }),
      ),
    );
  }

  /// Builds the light theme — 逐值复刻桌面强制浅色段
  /// （style.css:121 `:root[data-theme="light"]`）。
  ///
  /// 浅色继承桌面的 F-73 对比度问题（warning 即琥珀 accent 的浅底对比度
  /// 不足）：复刻优先、无障碍修复归 M6（spec Out of Scope）。与 [dark]
  /// 结构同构，仅 token 换用 [ConverColorsLight]。
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: ConverColorsLight.accent,
      onPrimary: ConverColorsLight.onAccent,
      secondary: ConverColorsLight.accentHover,
      onSecondary: ConverColorsLight.onAccent,
      surface: ConverColorsLight.bg,
      onSurface: ConverColorsLight.ink1,
      surfaceContainerLowest: ConverColorsLight.page,
      surfaceContainerLow: ConverColorsLight.panel1,
      surfaceContainer: ConverColorsLight.panel2,
      surfaceContainerHigh: ConverColorsLight.panel3,
      surfaceContainerHighest: ConverColorsLight.panel4,
      error: ConverColorsLight.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: ConverColorsLight.page,
      extensions: [ConverPalette.light()],
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ConverColorsLight.bg,
        indicatorColor: ConverColorsLight.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? ConverColorsLight.accent : ConverColorsLight.ink3,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? ConverColorsLight.accent : ConverColorsLight.ink3,
          );
        }),
      ),
    );
  }
}
