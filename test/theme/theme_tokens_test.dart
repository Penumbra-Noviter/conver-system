import 'package:conver_system_mobile/theme/colors.dart';
import 'package:conver_system_mobile/theme/conver_palette.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('G0.2a theme tokens (design doc §5.1, desktop :root dark defaults)', () {
    test('page and accent anchors match the desktop source values', () {
      expect(ConverColors.page, const Color(0xFF171512));
      expect(ConverColors.accent, const Color(0xFFD29A47));
    });

    test('ink hierarchy has four distinct levels', () {
      expect(ConverColors.ink1, const Color(0xFFF1ECE4));
      expect(ConverColors.ink2, const Color(0xFFC8C0B5));
      expect(ConverColors.ink3, const Color(0xFF9E9385));
      expect(ConverColors.ink4, const Color(0xFF7F7467));
      final levels = <Color>{
        ConverColors.ink1,
        ConverColors.ink2,
        ConverColors.ink3,
        ConverColors.ink4,
      };
      expect(levels.length, 4);
    });

    test('panel layers exist (bg + panel1..panel4, dark to light)', () {
      expect(ConverColors.bg, const Color(0xFF1D1A16));
      expect(ConverColors.panel1, const Color(0xFF211E19));
      expect(ConverColors.panel2, const Color(0xFF27231D));
      expect(ConverColors.panel3, const Color(0xFF2E2922));
      expect(ConverColors.panel4, const Color(0xFF373128));
    });

    test('warm-white border tiers at 0.07 / 0.13 / 0.04 opacity', () {
      expect(ConverColors.border, const Color.fromRGBO(244, 237, 226, 0.07));
      expect(ConverColors.borderStrong, const Color.fromRGBO(244, 237, 226, 0.13));
      expect(ConverColors.borderTertiary, const Color.fromRGBO(244, 237, 226, 0.04));
    });

    test('accent family: hover, soft wash (13%), on-accent', () {
      expect(ConverColors.accentHover, const Color(0xFFDFAA5C));
      expect(ConverColors.accentSoft, const Color.fromRGBO(210, 154, 71, 0.13));
      expect(ConverColors.onAccent, const Color(0xFF21180D));
    });

    test('semantic colors: success / danger / warning(=amber accent)', () {
      expect(ConverColors.success, const Color(0xFF79A781));
      expect(ConverColors.danger, const Color(0xFFCF7462));
      expect(ConverColors.warning, const Color(0xFFD29A47));
    });

    test('radii cover 3/6/8/10/12 with bubble at 12', () {
      expect(ConverRadii.xs, 3.0);
      expect(ConverRadii.sm, 6.0);
      expect(ConverRadii.md, 8.0);
      expect(ConverRadii.lg, 10.0);
      expect(ConverRadii.xl, 12.0);
      expect(ConverRadii.bubble, 12.0);
    });

    test('spacing grid covers 4/8/12/16/20/24/32/40/48', () {
      expect(ConverSpacing.space1, 4.0);
      expect(ConverSpacing.space2, 8.0);
      expect(ConverSpacing.space3, 12.0);
      expect(ConverSpacing.space4, 16.0);
      expect(ConverSpacing.space5, 20.0);
      expect(ConverSpacing.space6, 24.0);
      expect(ConverSpacing.space8, 32.0);
      expect(ConverSpacing.space10, 40.0);
      expect(ConverSpacing.space12, 48.0);
    });
  });

  test('dark side: 5 缺名 token 补齐自桌面 :root 默认段（M1-T07）', () {
    // 桌面 style.css `:root`（深色默认段）逐值：
    expect(ConverColors.accentContrast, const Color(0xFF21180D));
    expect(ConverColors.onAccent, ConverColors.accentContrast); // --on-accent
    expect(ConverColors.accentGen, const Color(0xFFA855F7));
    expect(
      ConverColors.accentGenSoft,
      const Color.fromRGBO(168, 85, 247, 0.15),
    );
    expect(ConverColors.onDanger, const Color(0xFFFFFDF8));
    expect(ConverColors.overlay, const Color.fromRGBO(24, 20, 16, 0.72));
  });

  group('G3 light tokens (M1-T07, desktop :root[data-theme="light"] style.css:121)', () {
    test('A1 抽样锚点：page / accent / ink1 / overlay / accentGen 逐点对源', () {
      expect(ConverColorsLight.page, const Color(0xFFF0ECE5)); // #f0ece5
      expect(ConverColorsLight.accent, const Color(0xFFA96F1D)); // #a96f1d
      expect(ConverColorsLight.ink1, const Color(0xFF28211A)); // #28211a
      expect(
        ConverColorsLight.overlay,
        const Color.fromRGBO(42, 33, 23, 0.42), // rgba(42, 33, 23, 0.42)
      );
      expect(ConverColorsLight.accentGen, const Color(0xFF9333EA)); // #9333ea
    });

    test('浅色段 25 值逐字转录（含 rgba 分量与 alpha 浮点）', () {
      // 色值锚定自 style.css:121-147（强制浅色段），逐行对源。
      expect(ConverColorsLight.page, const Color(0xFFF0ECE5));
      expect(ConverColorsLight.bg, const Color(0xFFF8F5EF));
      expect(ConverColorsLight.panel1, const Color(0xFFF4F0E9));
      expect(ConverColorsLight.panel2, const Color(0xFFEBE5DB));
      expect(ConverColorsLight.panel3, const Color(0xFFE2DACF));
      expect(ConverColorsLight.panel4, const Color(0xFFD7CFC2));
      expect(ConverColorsLight.border, const Color.fromRGBO(63, 51, 38, 0.09));
      expect(
        ConverColorsLight.borderStrong,
        const Color.fromRGBO(63, 51, 38, 0.16),
      );
      expect(
        ConverColorsLight.borderTertiary,
        const Color.fromRGBO(63, 51, 38, 0.05),
      );
      expect(ConverColorsLight.ink1, const Color(0xFF28211A));
      expect(ConverColorsLight.ink2, const Color(0xFF51463A));
      expect(ConverColorsLight.ink3, const Color(0xFF766A5C));
      expect(ConverColorsLight.ink4, const Color(0xFF988C7D));
      expect(ConverColorsLight.accent, const Color(0xFFA96F1D));
      expect(ConverColorsLight.accentHover, const Color(0xFF925F17));
      expect(
        ConverColorsLight.accentSoft,
        const Color.fromRGBO(169, 111, 29, 0.12),
      );
      expect(ConverColorsLight.accentContrast, const Color(0xFFFFFBF4));
      expect(ConverColorsLight.onAccent, ConverColorsLight.accentContrast);
      expect(ConverColorsLight.accentGen, const Color(0xFF9333EA));
      expect(
        ConverColorsLight.accentGenSoft,
        const Color.fromRGBO(147, 51, 234, 0.15),
      );
      expect(ConverColorsLight.onDanger, const Color(0xFFFFFDF8));
      expect(
        ConverColorsLight.overlay,
        const Color.fromRGBO(42, 33, 23, 0.42),
      );
    });

    test('A2 同构契约：浅/深 token 名集相等且恰为桌面 25 名', () {
      const expectedNames = <String>{
        'page', 'bg', 'panel1', 'panel2', 'panel3', 'panel4',
        'border', 'borderStrong', 'borderTertiary',
        'ink1', 'ink2', 'ink3', 'ink4',
        'accent', 'accentHover', 'accentSoft',
        'accentContrast', 'onAccent',
        'accentGen', 'accentGenSoft',
        'onDanger', 'overlay',
        'success', 'danger', 'warning',
      };
      expect(ConverColors.tokens.keys.toSet(), expectedNames);
      expect(ConverColorsLight.tokens.keys.toSet(), expectedNames);
      expect(ConverColors.tokens.length, 25);
      expect(ConverColorsLight.tokens.length, 25);
      // 映射值与同名 static const 一致（映射登记不漂移）。
      expect(ConverColorsLight.tokens['page'], ConverColorsLight.page);
      expect(ConverColors.tokens['accentGen'], ConverColors.accentGen);
    });

    test('success / danger / warning 浅色沿用深色值（CSS 回退语义，F-73 注记）', () {
      expect(ConverColorsLight.success, ConverColors.success);
      expect(ConverColorsLight.danger, ConverColors.danger);
      expect(ConverColorsLight.warning, ConverColors.warning);
    });
  });

  group('ConverTheme.dark() (G0.2a ThemeData assembly)', () {
    final theme = ConverTheme.dark();

    test('locks dark brightness', () {
      expect(theme.brightness, Brightness.dark);
    });

    test('scaffold background is the warm-black page color', () {
      expect(theme.scaffoldBackgroundColor, ConverColors.page);
    });

    test('colorScheme carries the amber accent as primary', () {
      expect(theme.colorScheme.primary, ConverColors.accent);
      expect(theme.colorScheme.onPrimary, ConverColors.onAccent);
    });

    test('navigationBar selected state uses the amber accent', () {
      final nav = theme.navigationBarTheme;
      expect(nav.indicatorColor, ConverColors.accentSoft);
      expect(
        nav.iconTheme?.resolve(const {WidgetState.selected})?.color,
        ConverColors.accent,
      );
      expect(
        nav.iconTheme?.resolve(const <WidgetState>{})?.color,
        ConverColors.ink3,
      );
      expect(
        nav.labelTextStyle?.resolve(const {WidgetState.selected})?.color,
        ConverColors.accent,
      );
    });
  });

  group('ConverTheme.light() (M1-T07 ThemeData assembly)', () {
    final theme = ConverTheme.light();

    test('locks light brightness and warm-paper scaffold background', () {
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, ConverColorsLight.page);
    });

    test('colorScheme carries the dark-amber accent as primary', () {
      expect(theme.colorScheme.primary, ConverColorsLight.accent);
      expect(theme.colorScheme.onPrimary, ConverColorsLight.onAccent);
      expect(theme.colorScheme.surface, ConverColorsLight.bg);
    });

    test('navigationBar selected state uses the light-theme amber', () {
      final nav = theme.navigationBarTheme;
      expect(nav.backgroundColor, ConverColorsLight.bg);
      expect(nav.indicatorColor, ConverColorsLight.accentSoft);
      expect(
        nav.iconTheme?.resolve(const {WidgetState.selected})?.color,
        ConverColorsLight.accent,
      );
      expect(
        nav.iconTheme?.resolve(const <WidgetState>{})?.color,
        ConverColorsLight.ink3,
      );
    });
  });

  group('ConverPalette (F-7 ThemeExtension，5 枚 token 深/浅镜像)', () {
    test('dark() 5 枚 == ConverColors 同名常量（逐字）', () {
      final p = ConverPalette.dark();
      expect(p.ink1, ConverColors.ink1);
      expect(p.ink2, ConverColors.ink2);
      expect(p.ink3, ConverColors.ink3);
      expect(p.ink4, ConverColors.ink4);
      expect(p.border, ConverColors.border);
    });

    test('light() 5 枚 == ConverColorsLight 同名常量（逐字）', () {
      final p = ConverPalette.light();
      expect(p.ink1, ConverColorsLight.ink1);
      expect(p.ink2, ConverColorsLight.ink2);
      expect(p.ink3, ConverColorsLight.ink3);
      expect(p.ink4, ConverColorsLight.ink4);
      expect(p.border, ConverColorsLight.border);
    });

    test('ConverTheme dark/light 注册对应 ConverPalette extensions', () {
      final dark = ConverTheme.dark();
      final light = ConverTheme.light();
      expect(dark.extension<ConverPalette>(), isNotNull);
      expect(light.extension<ConverPalette>(), isNotNull);
      expect(dark.extension<ConverPalette>()!.ink1, ConverColors.ink1);
      expect(light.extension<ConverPalette>()!.ink1, ConverColorsLight.ink1);
    });

    test('copyWith：部分覆盖保留其余、全参数覆盖整体替换', () {
      const base = ConverPalette.dark();
      final partial = base.copyWith(ink1: const Color(0xFF000001));
      expect(partial.ink1, const Color(0xFF000001));
      expect(partial.ink2, base.ink2);
      expect(partial.ink3, base.ink3);
      expect(partial.ink4, base.ink4);
      expect(partial.border, base.border);

      final full = base.copyWith(
        ink1: const Color(0xFF000001),
        ink2: const Color(0xFF000002),
        ink3: const Color(0xFF000003),
        ink4: const Color(0xFF000004),
        border: const Color(0xFF000005),
      );
      expect(full.ink1, const Color(0xFF000001));
      expect(full.border, const Color(0xFF000005));
    });

    test('lerp：t=0 取自身、t=1 取目标、异型 other 回退自身', () {
      const a = ConverPalette.dark();
      const b = ConverPalette.light();
      final atZero = a.lerp(b, 0.0);
      expect(atZero.ink1, a.ink1);
      final atOne = a.lerp(b, 1.0);
      expect(atOne.ink1, b.ink1);
      // 非 ConverPalette 的 other → 回退自身（ThemeExtension 契约）。
      expect(a.lerp(null, 0.5).ink1, a.ink1);
    });
  });
}
