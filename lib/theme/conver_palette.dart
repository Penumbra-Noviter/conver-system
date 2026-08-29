import 'package:flutter/material.dart';

import 'colors.dart';

/// 视图层消费的 5 枚语义色 token（ink 四级 + border），随主题深浅自动切换。
///
/// 背景（F-7，Grilling 前提修正）：现有 ColorScheme 只装得下
/// `onSurface=ink1 / surfaceContainer*=panel* / primary=accent / error=danger`，
/// ink2 / ink3 / ink4 / border 无 Material 角色可映射 → 用
/// [ThemeExtension] 承载。
///
/// 契约：
/// - [ConverPalette.dark] / [ConverPalette.light] 值逐字取自 [ConverColors] /
///   [ConverColorsLight] 同名常量（M1 同构契约冻结：不新增/不改任何 token
///   值或名，token 名集仍由 colors.dart 的 25 名映射锁定）。
/// - 装配方（[ConverTheme]）在 dark/light ThemeData 各注册对应 extensions；
///   消费方统一 `Theme.of(context).extension<ConverPalette>()!`。
class ConverPalette extends ThemeExtension<ConverPalette> {
  /// 显式值构造（copyWith / lerp 复用）。
  const ConverPalette({
    required this.ink1,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.border,
  });

  /// 深色板 — 逐字取自 [ConverColors] 同名常量（desktop `:root` 默认段）。
  const ConverPalette.dark()
    : ink1 = ConverColors.ink1,
      ink2 = ConverColors.ink2,
      ink3 = ConverColors.ink3,
      ink4 = ConverColors.ink4,
      border = ConverColors.border;

  /// 浅色板 — 逐字取自 [ConverColorsLight] 同名常量
  /// （desktop `:root[data-theme="light"]` 段，style.css:121）。
  const ConverPalette.light()
    : ink1 = ConverColorsLight.ink1,
      ink2 = ConverColorsLight.ink2,
      ink3 = ConverColorsLight.ink3,
      ink4 = ConverColorsLight.ink4,
      border = ConverColorsLight.border;

  /// 一级文字色（最亮，主文字）。
  final Color ink1;

  /// 二级文字色。
  final Color ink2;

  /// 三级文字色（次标签/说明）。
  final Color ink3;

  /// 四级文字色（最淡，辅助信息）。
  final Color ink4;

  /// 发丝线边框色。
  final Color border;

  @override
  ConverPalette copyWith({
    Color? ink1,
    Color? ink2,
    Color? ink3,
    Color? ink4,
    Color? border,
  }) {
    return ConverPalette(
      ink1: ink1 ?? this.ink1,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      ink4: ink4 ?? this.ink4,
      border: border ?? this.border,
    );
  }

  @override
  ConverPalette lerp(ThemeExtension<ConverPalette>? other, double t) {
    if (other is! ConverPalette) {
      return this;
    }
    return ConverPalette(
      ink1: Color.lerp(ink1, other.ink1, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      ink4: Color.lerp(ink4, other.ink4, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}
