import 'package:conver_system_mobile/theme/colors.dart';
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
}
