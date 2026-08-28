/// 主题控制器 — theme_mode 三值字符串 ↔ ThemeMode 编解码与切换通知。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/setting.py`（ALLOWED_KEYS 含 theme_mode；
/// 桌面为字符串原样存取，无 ThemeMode 概念）
///
/// 职责边界（M1-T04，spec 用户拍板①）：
/// - theme_mode ∈ `'auto' | 'light' | 'dark'` 字符串落 settings 表；
///   `'auto'` → [ThemeMode.system]；**缺行 / 非法值 → dark**
/// - 编解码为纯函数（[decodeThemeMode] / [encodeThemeMode]），控制器仅做
///   显式 set + notify（不引入流订阅，避免 M1 过度设计）；装配响应归工单 07、
///   切换调用归工单 06
library;

import 'package:flutter/foundation.dart';
// ThemeMode 定义于 material 库（dart:ui 只有 Brightness，无 ThemeMode）
import 'package:flutter/material.dart' show ThemeMode;

import '../data/repositories/settings_repository.dart';

/// theme_mode 落库字符串 → [ThemeMode]。
///
/// `'auto'` → system；`'light'` / `'dark'` → 同名；null、空串、其他任意
/// 非法值 → dark（首启无记录与脏数据同归 dark，用户拍板①）。
ThemeMode decodeThemeMode(String? raw) {
  switch (raw) {
    case 'auto':
      return ThemeMode.system;
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.dark;
  }
}

/// [ThemeMode] → theme_mode 落库字符串（三值；system ↔ 'auto'）。
String encodeThemeMode(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return 'auto';
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
  }
}

/// 设置的消费面视图模型：持有当前 [ThemeMode]，切换即持久化并通知监听者。
///
/// 用法：装配方（工单 07）构造后先 [load] 恢复持久化偏好，再将本控制器经
/// provider 注入；ListenableBuilder 监听 [themeMode] 即得「切换即时生效」。
class ThemeController extends ChangeNotifier {
  /// 创建控制器；[settingsRepository] 经构造注入（读写 theme_mode 原始字符串）
  ThemeController({required SettingsRepository settingsRepository})
    : _settings = settingsRepository;

  final SettingsRepository _settings;

  /// 当前主题模式；[load] 完成前为 dark（首启基线，与缺行缺省一致）。
  ThemeMode get themeMode => _themeMode;

  ThemeMode _themeMode = ThemeMode.dark;

  /// 从设置表恢复持久化的 theme_mode（缺行 / 非法值 → dark）。
  ///
  /// 完成后无条件 [notifyListeners]（恢复值可能与初始 dark 不同，
  /// 装配方监听后应用到 MaterialApp）。
  Future<void> load() async {
    final raw = await _settings.getValue(SettingsRepository.themeModeKey);
    _themeMode = decodeThemeMode(raw);
    notifyListeners();
  }

  /// 切换主题：编码为三值字符串持久化到设置表，随后 [notifyListeners]
  /// 驱动监听方即时生效。
  Future<void> setThemeMode(ThemeMode mode) async {
    await _settings
        .setMany({SettingsRepository.themeModeKey: encodeThemeMode(mode)});
    _themeMode = mode;
    notifyListeners();
  }
}
