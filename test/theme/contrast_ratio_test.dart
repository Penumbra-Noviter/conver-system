// F-73 浅色 accent 前景对比度锁定（WCAG 相对亮度算术断言，spec §4.4）。
//
// 标定口径：WCAG 2.x 相对亮度公式（线性化阈值 0.03928；乘子 12.92 /
// ((c+0.055)/1.055)^2.4），对比度 = (L1+0.05)/(L2+0.05)。
// 断言契约：
// 1. 浅色 accent 作前景 vs 浅色 page/bg/panel1..panel4 各表面对比度 ≥ 4.5:1
//    （WCAG AA 文本/图标前景；发送按钮/链接/选中态/角色 chip label 同系）。
// 2. accentHover 同步深化：与 accent 值不等、更暗（亮度更低）、对浅表 ≥ 4.5。
// 3. accentSoft（wash）RGB 分量与新 accent 一致、alpha 0.12 保留。
// 4. warning 为浅色独立深琥珀警示值：与 accent/accentHover 可区分、对浅表 ≥ 4.5。
// 5. 深色主题零回归：深色 accent 值不变，且深色对照对比度 ≥ 既有水平（≥ 4.5）。
// 6. 渲染消费场景抽样：NavigationBar 选中态（accent on accentSoft-wash-over-bg）、
//    发送按钮（accent on panel1）、Markdown 链接（accent on page）、角色 chip
//    label（accent on panel4）、wizard 活动步（onAccent on accent）均 ≥ 4.5。
//
// 本文件只用纯 Dart 算术 + token 常量，不触碰视图层（静态不变量契约无关）。
library;

import 'dart:math' as math;

import 'package:conver_system_mobile/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 线性化单个 sRGB 通道（0..1）。
double _linearize(double channel) {
  if (channel <= 0.03928) {
    return channel / 12.92;
  }
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 相对亮度：L = 0.2126 R + 0.7152 G + 0.0722 B（线性 sRGB）。
double _relativeLuminance(Color color) {
  return 0.2126 * _linearize(color.r) +
      0.7152 * _linearize(color.g) +
      0.0722 * _linearize(color.b);
}

/// WCAG 对比度：(较亮 L + 0.05) / (较暗 L + 0.05)，恒 ≥ 1。
double _contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// 浅色主题 6 张表面（accent 作前景出现的全部底色）。
const List<Color> _lightSurfaces = [
  ConverColorsLight.page,
  ConverColorsLight.bg,
  ConverColorsLight.panel1,
  ConverColorsLight.panel2,
  ConverColorsLight.panel3,
  ConverColorsLight.panel4,
];

/// 深色主题 6 张表面（深色对照/零回归面）。
const List<Color> _darkSurfaces = [
  ConverColors.page,
  ConverColors.bg,
  ConverColors.panel1,
  ConverColors.panel2,
  ConverColors.panel3,
  ConverColors.panel4,
];

void _expectForegroundOnLightSurfaces(Color fg, String tokenName) {
  for (final surface in _lightSurfaces) {
    expect(
      _contrastRatio(fg, surface),
      greaterThanOrEqualTo(4.5),
      reason: '$tokenName($fg) 作前景于 $surface 应对比度 ≥ 4.5:1'
          '（WCAG AA；F-73），实际 '
          '${_contrastRatio(fg, surface).toStringAsFixed(2)}',
    );
  }
}

void _expectForegroundOnDarkSurfaces(Color fg, String tokenName) {
  for (final surface in _darkSurfaces) {
    expect(
      _contrastRatio(fg, surface),
      greaterThanOrEqualTo(4.5),
      reason: '深色 $tokenName($fg) 作前景于 $surface 应对比度 ≥ 4.5:1'
          '（零回归基线），实际 '
          '${_contrastRatio(fg, surface).toStringAsFixed(2)}',
    );
  }
}

void main() {
  group('WCAG 算术助手自检（防公式误写）', () {
    test('黑/白基准：白色 L=1.0，黑色 L=0.0，黑白对比度=21:1', () {
      expect(_relativeLuminance(const Color(0xFFFFFFFF)), closeTo(1.0, 1e-9));
      expect(_relativeLuminance(const Color(0xFF000000)), closeTo(0.0, 1e-12));
      expect(_contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 1e-9));
    });

    test('对称性 / 恒正性：对比度与参数顺序无关且 ≥ 1', () {
      const a = Color(0xFF784E14);
      const b = Color(0xFFF0ECE5);
      final r1 = _contrastRatio(a, b);
      final r2 = _contrastRatio(b, a);
      expect(r1, closeTo(r2, 1e-12));
      expect(r1, greaterThanOrEqualTo(1.0));
    });
  });

  group('F-73 浅色 accent 前景对比度（spec §4.4，WCAG AA ≥4.5:1）', () {
    test('浅色 accent 于全部浅色表面（page/bg/panel1..4）≥ 4.5:1', () {
      _expectForegroundOnLightSurfaces(ConverColorsLight.accent, 'accent');
    });

    test('accentHover 与 accent 可区分：值不等且 hover 更暗', () {
      final accent = ConverColorsLight.accent;
      final hover = ConverColorsLight.accentHover;
      expect(hover, isNot(equals(accent)),
          reason: 'accentHover 须与 accent 保持可区分（接收标准 2）');
      expect(
        _relativeLuminance(hover),
        lessThan(_relativeLuminance(accent)),
        reason: '浅色主题 hover 应比 accent 更暗（darkens rather than lightens）',
      );
    });

    test('accentHover 于全部浅色表面 ≥ 4.5:1（hover 亦属前景族）', () {
      _expectForegroundOnLightSurfaces(
          ConverColorsLight.accentHover, 'accentHover');
    });

    test('accentSoft RGB 分量与新 accent 一致且 alpha 0.12 保留', () {
      final accent = ConverColorsLight.accent;
      final soft = ConverColorsLight.accentSoft;
      expect(soft.r, closeTo(accent.r, 1e-9));
      expect(soft.g, closeTo(accent.g, 1e-9));
      expect(soft.b, closeTo(accent.b, 1e-9));
      expect(soft.a, closeTo(0.12, 1e-9),
          reason: 'accentSoft 的 alpha 0.12 保留（接收标准 3）');
    });

    test('warning 为浅色独立深琥珀警示值：可区分且于浅表 ≥ 4.5:1', () {
      final warning = ConverColorsLight.warning;
      expect(warning, isNot(equals(ConverColorsLight.accent)));
      expect(warning, isNot(equals(ConverColorsLight.accentHover)));
      expect(
        warning,
        isNot(equals(ConverColors.warning)),
        reason: '浅色 warning 不再沿用深色值（接收标准 3）',
      );
      _expectForegroundOnLightSurfaces(warning, 'warning');
    });

    test('渲染消费场景抽样：NavBar 选中态 / 发送按钮 / 链接 / chip / wizard', () {
      // NavigationBar 选中态：accent 图标落在 accentSoft wash-over-bg 合成面上。
      final indicator = Color.lerp(
        ConverColorsLight.bg,
        ConverColorsLight.accent,
        ConverColorsLight.accentSoft.a,
      )!;
      expect(
        _contrastRatio(ConverColorsLight.accent, indicator),
        greaterThanOrEqualTo(4.5),
        reason: 'NavigationBar 选中态图标/标签（accent on accentSoft-over-bg）',
      );

      // 发送按钮图标：accent on 输入栏 surfaceContainerLow = panel1。
      expect(
        _contrastRatio(
            ConverColorsLight.accent, ConverColorsLight.panel1),
        greaterThanOrEqualTo(4.5),
        reason: '发送按钮（accent on panel1）',
      );

      // Markdown 链接/行内代码/列表圆点：accent on 气泡 surfaceContainerLowest=page。
      expect(
        _contrastRatio(ConverColorsLight.accent, ConverColorsLight.page),
        greaterThanOrEqualTo(4.5),
        reason: 'Markdown 链接（accent on page）',
      );

      // 角色 chip label（头像首字）：accent on surfaceContainerHighest=panel4。
      expect(
        _contrastRatio(
            ConverColorsLight.accent, ConverColorsLight.panel4),
        greaterThanOrEqualTo(4.5),
        reason: '角色 chip label（accent on panel4）',
      );

      // wizard 活动步：onAccent（暖白）落在 accent 实底上。
      expect(
        _contrastRatio(
            ConverColorsLight.onAccent, ConverColorsLight.accent),
        greaterThanOrEqualTo(4.5),
        reason: 'wizard 活动步 onAccent on accent',
      );
    });

    test('accent 深浅两套互不相同（浅色已授权偏离桌面逐字值）', () {
      expect(ConverColorsLight.accent, isNot(equals(ConverColors.accent)));
      expect(ConverColorsLight.accentHover,
          isNot(equals(ConverColors.accentHover)));
    });
  });

  group('深色主题零回归（F-73 不触碰深色调色板）', () {
    test('深色 accent 值逐位不变（#D29A47）', () {
      expect(ConverColors.accent, const Color(0xFFD29A47));
      expect(ConverColors.accentHover, const Color(0xFFDFAA5C));
    });

    test('深色 accent / accentHover 于深色表面对比度 ≥ 4.5（既有水平之上）', () {
      _expectForegroundOnDarkSurfaces(ConverColors.accent, 'accent');
      _expectForegroundOnDarkSurfaces(ConverColors.accentHover, 'accentHover');
    });
  });
}