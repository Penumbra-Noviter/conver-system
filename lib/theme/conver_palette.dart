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
///   消费方统一经 [ConverPalette.of]（或可空场景 [ConverPalette.maybeOf]）
///   获取，未注册时抛带修复指引的 [FlutterError] 而非泛化 null-check。
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

  /// 安全访问当前 [BuildContext] 装配的 [ConverPalette]。
  ///
  /// 未注册时抛带修复指引的 [FlutterError]（消息含「未注册」与
  /// ConverTheme/MaterialApp（ConverApp）装配提示），而非泛化 null-check。
  /// 消费方统一经此入口获取 token，取代 `Theme.of(context).extension<ConverPalette>()!`。
  static ConverPalette of(BuildContext context) {
    final palette = maybeOf(context);
    if (palette == null) {
      throw FlutterError(
        'ConverPalette 未注册：请确保在 ConverTheme/MaterialApp（ConverApp）'
        '下构建当前 Widget 的 BuildContext。',
      );
    }
    return palette;
  }

  /// 可空版本：未注册返回 null、不抛；已注册返回 [ConverPalette] 实例。
  static ConverPalette? maybeOf(BuildContext context) =>
      _themeExtensionOf<ConverPalette>(context);

  /// 从 [Theme] 上取 [T] 类型的 [ThemeExtension] 实例；未注册返回 null。
  static T? _themeExtensionOf<T extends ThemeExtension<T>>(BuildContext context) =>
      Theme.of(context).extension<T>();

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
