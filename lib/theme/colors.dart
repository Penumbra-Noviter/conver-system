import 'package:flutter/material.dart';

/// Warm Stone color tokens (design doc §5.1).
///
/// Single source of truth for the mobile app, mirroring the desktop
/// stylesheet `frontend/css/style.css`: [ConverColors] mirrors the `:root`
/// dark defaults; [ConverColorsLight] mirrors the forced-light section
/// (`:root[data-theme="light"]`, style.css:121). Downstream UI must reference
/// these constants instead of redefining raw values.
///
/// 同构契约（M1-T07，G3）：浅/深两套色值 token **名集相等**（各 25 名），
/// 新增 token 必须成对补入两套并同步 `tokens` 映射；阴影 token
/// （shadow-sm/md/lg）与色值分离暂缓（M1 无 UI 消费方，spec Out of Scope）。
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

  /// Dark-brown foreground drawn on top of the accent
  /// (desktop `--accent-contrast`).
  static const Color accentContrast = Color(0xFF21180D);

  /// Foreground drawn on top of the accent
  /// (desktop `--on-accent: var(--accent-contrast)`).
  static const Color onAccent = accentContrast;

  /// Violet accent for AI-generated content (desktop `--accent-gen`).
  static const Color accentGen = Color(0xFFA855F7);

  /// Translucent violet wash (15%) for generative content
  /// (desktop `--accent-gen-soft`).
  static const Color accentGenSoft = Color.fromRGBO(168, 85, 247, 0.15);

  /// Warm-white foreground drawn on top of danger surfaces
  /// (desktop `--on-danger`).
  static const Color onDanger = Color(0xFFFFFDF8);

  /// Scrim/dialog overlay (desktop `--overlay`).
  static const Color overlay = Color.fromRGBO(24, 20, 16, 0.72);

  /// Semantic status colors; warning reuses the amber accent.
  static const Color success = Color(0xFF79A781);
  static const Color danger = Color(0xFFCF7462);
  static const Color warning = Color(0xFFD29A47);

  /// 全量色值 token 名→值映射 — G3 同构契约的运行时枚举面（Dart 无法
  /// 反射枚举 static const，名集相等测试依赖此映射；共 25 名）。
  /// 新增 token 必须同步登记，遗漏会被名集测试（锚定 25 名全列）拦下。
  static const Map<String, Color> tokens = <String, Color>{
    'page': page,
    'bg': bg,
    'panel1': panel1,
    'panel2': panel2,
    'panel3': panel3,
    'panel4': panel4,
    'border': border,
    'borderStrong': borderStrong,
    'borderTertiary': borderTertiary,
    'ink1': ink1,
    'ink2': ink2,
    'ink3': ink3,
    'ink4': ink4,
    'accent': accent,
    'accentHover': accentHover,
    'accentSoft': accentSoft,
    'accentContrast': accentContrast,
    'onAccent': onAccent,
    'accentGen': accentGen,
    'accentGenSoft': accentGenSoft,
    'onDanger': onDanger,
    'overlay': overlay,
    'success': success,
    'danger': danger,
    'warning': warning,
  };
}

/// Warm Stone light tokens — 逐值镜像桌面样式表强制浅色段
/// （`frontend/css/style.css` `:root[data-theme="light"]`，style.css:121 起）。
///
/// 与深色 [ConverColors] 同构（25 名色值 token，名集相等，G3 契约）：
/// - success / danger 桌面浅色段未覆盖 → 浅色沿用深色值（CSS 变量回退语义）。
/// - warning 桌面浅色段未覆盖，但沿用深色值会使 F-73 对比度违例复现
///   （浅底琥珀前景 ≈2.7:1 < WCAG AA 4.5:1）→ M6 修复：改用浅色独立的
///   深琥珀警示值（TP-3b 授权偏离桌面逐字值，仅改值、名集不变）。
/// - accent 系同理由桌面逐字值 #A96F1D 深化至 #784E14（相对亮度公式验证
///   全浅表 ≥4.5:1，见 test/theme/contrast_ratio_test.dart）。
/// - 阴影 token 与色值分离暂缓（M1 无 UI 消费方）。
abstract final class ConverColorsLight {
  /// Page background — the warm paper canvas (style.css:122).
  static const Color page = Color(0xFFF0ECE5);

  /// Base background above the page layer.
  static const Color bg = Color(0xFFF8F5EF);

  /// Panel layers, ordered from light to dark (higher elevation, darker).
  static const Color panel1 = Color(0xFFF4F0E9);
  static const Color panel2 = Color(0xFFEBE5DB);
  static const Color panel3 = Color(0xFFE2DACF);
  static const Color panel4 = Color(0xFFD7CFC2);

  /// Warm-brown (rgb 63, 51, 38) hairline borders at three opacities.
  static const Color border = Color.fromRGBO(63, 51, 38, 0.09);
  static const Color borderStrong = Color.fromRGBO(63, 51, 38, 0.16);
  static const Color borderTertiary = Color.fromRGBO(63, 51, 38, 0.05);

  /// Four-level text hierarchy, from primary to the faintest.
  static const Color ink1 = Color(0xFF28211A);
  static const Color ink2 = Color(0xFF51463A);
  static const Color ink3 = Color(0xFF766A5C);
  static const Color ink4 = Color(0xFF988C7D);

  /// Dark-amber accent — F-73 深化档（#784E14，TP-3b 授权偏离桌面逐字值）。
  ///
  /// 桌面逐字值 #A96F1D 作前景于浅表（page #F0ECE5）仅 ≈2.7:1 < WCAG AA
  /// 4.5:1；按共识 4.3 推荐 A 以相对亮度公式深化至 #784E14——accent 于
  /// page/bg/panel1..4 全表 ≥4.5:1（算术验证见 test/theme/contrast_ratio_test.dart）。
  /// 深色 accent #D29A47 不受影响。
  static const Color accent = Color(0xFF784E14);

  /// Hover state of the accent — 更深一档（darkens rather than lightens），
  /// 与 [accent] 保持可区分且同为 ≥4.5:1 前景档。
  static const Color accentHover = Color(0xFF6B4311);

  /// Translucent amber wash (12%) for soft selected backgrounds — RGB 分量
  /// 与新 accent 一致（alpha 0.12 保留）。
  static const Color accentSoft = Color.fromRGBO(120, 78, 20, 0.12);

  /// Warm-white foreground drawn on top of the accent
  /// (desktop `--accent-contrast`).
  static const Color accentContrast = Color(0xFFFFFBF4);

  /// Foreground drawn on top of the accent
  /// (desktop `--on-accent: var(--accent-contrast)`).
  static const Color onAccent = accentContrast;

  /// Violet accent for AI-generated content (desktop `--accent-gen`).
  static const Color accentGen = Color(0xFF9333EA);

  /// Translucent violet wash (15%) for generative content
  /// (desktop `--accent-gen-soft`).
  static const Color accentGenSoft = Color.fromRGBO(147, 51, 234, 0.15);

  /// Warm-white foreground drawn on top of danger surfaces
  /// (desktop `--on-danger`).
  static const Color onDanger = Color(0xFFFFFDF8);

  /// Scrim/dialog overlay — lighter than the dark theme's
  /// (desktop `--overlay`, style.css:143).
  static const Color overlay = Color.fromRGBO(42, 33, 23, 0.42);

  /// Semantic status colors — success / danger 桌面浅色段未覆盖，沿用深色值
  /// （CSS 回退语义）；warning 为 M6 修复的浅色独立深琥珀警示值（F-73：
  /// 沿用深色琥珀 #D29A47 作浅底前景对比度不足，名集不变仅值变）。
  static const Color success = ConverColors.success;
  static const Color danger = ConverColors.danger;
  static const Color warning = Color(0xFF854906);

  /// 全量色值 token 名→值映射 — G3 同构契约的运行时枚举面（共 25 名，
  /// 与 [ConverColors.tokens] 名集相等；维护说明见彼处）。
  static const Map<String, Color> tokens = <String, Color>{
    'page': page,
    'bg': bg,
    'panel1': panel1,
    'panel2': panel2,
    'panel3': panel3,
    'panel4': panel4,
    'border': border,
    'borderStrong': borderStrong,
    'borderTertiary': borderTertiary,
    'ink1': ink1,
    'ink2': ink2,
    'ink3': ink3,
    'ink4': ink4,
    'accent': accent,
    'accentHover': accentHover,
    'accentSoft': accentSoft,
    'accentContrast': accentContrast,
    'onAccent': onAccent,
    'accentGen': accentGen,
    'accentGenSoft': accentGenSoft,
    'onDanger': onDanger,
    'overlay': overlay,
    'success': success,
    'danger': danger,
    'warning': warning,
  };
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
