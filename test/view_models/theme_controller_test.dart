/// ThemeController 契约测试（M1-T04，验收门 G5：theme_mode 映射逐条 + G3 切换行为）。
///
/// 编解码为纯函数逐条断言；控制器经真实 SettingsRepository
/// （内存执行器打真 schema + InMemorySecretStore）验证持久化与通知。
/// 语义锚点：spec 用户拍板①（'auto'→system、缺行/非法 → dark）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_secret_store.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = SettingsRepository(
      database: db,
      secretStore: InMemorySecretStore(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 直查设置表 theme_mode 原始字符串（落表断言，不经仓储读取通道）
  Future<String?> persistedRaw() async {
    final row = await (db.select(db.settings)
          ..where((t) => t.key.equals(SettingsRepository.themeModeKey)))
        .getSingleOrNull();
    return row?.value;
  }

  group('decodeThemeMode 编解码映射（G5 逐条）', () {
    test("'auto' → ThemeMode.system", () {
      expect(decodeThemeMode('auto'), ThemeMode.system);
    });

    test("'light' / 'dark' → 同名 ThemeMode", () {
      expect(decodeThemeMode('light'), ThemeMode.light);
      expect(decodeThemeMode('dark'), ThemeMode.dark);
    });

    test('null / 空串 / 非法值 → dark（缺行与脏数据同归 dark）', () {
      expect(decodeThemeMode(null), ThemeMode.dark);
      expect(decodeThemeMode(''), ThemeMode.dark);
      expect(decodeThemeMode('system'), ThemeMode.dark);
      expect(decodeThemeMode('bogus'), ThemeMode.dark);
      expect(decodeThemeMode('AUTO'), ThemeMode.dark); // 大小写敏感，非法
    });
  });

  group('encodeThemeMode 编码映射', () {
    test('system → auto；light / dark → 同名（三值可往返）', () {
      expect(encodeThemeMode(ThemeMode.system), 'auto');
      expect(encodeThemeMode(ThemeMode.light), 'light');
      expect(encodeThemeMode(ThemeMode.dark), 'dark');

      for (final mode in ThemeMode.values) {
        expect(decodeThemeMode(encodeThemeMode(mode)), mode);
      }
    });
  });

  group('ThemeController（G3 切换行为）', () {
    test('初始（load 前）为 dark 首启基线', () {
      final controller = ThemeController(settingsRepository: repository);
      expect(controller.themeMode, ThemeMode.dark);
      controller.dispose();
    });

    test('load：缺行 → dark；持久化 light → light', () async {
      final empty = ThemeController(settingsRepository: repository);
      await empty.load();
      expect(empty.themeMode, ThemeMode.dark);
      empty.dispose();

      await repository.setMany({SettingsRepository.themeModeKey: 'light'});
      final restored = ThemeController(settingsRepository: repository);
      await restored.load();
      expect(restored.themeMode, ThemeMode.light);
      restored.dispose();
    });

    test('load 持久化 auto → system（跟随系统）', () async {
      await repository.setMany({SettingsRepository.themeModeKey: 'auto'});
      final controller = ThemeController(settingsRepository: repository);
      await controller.load();
      expect(controller.themeMode, ThemeMode.system);
      controller.dispose();
    });

    test('load 持久化非法值 → dark（脏数据容错）', () async {
      await repository.setMany({SettingsRepository.themeModeKey: 'bogus'});
      final controller = ThemeController(settingsRepository: repository);
      await controller.load();
      expect(controller.themeMode, ThemeMode.dark);
      controller.dispose();
    });

    test('setThemeMode 持久化三值字符串并 notifyListeners', () async {
      final controller = ThemeController(settingsRepository: repository);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setThemeMode(ThemeMode.system);
      expect(notifications, 1);
      expect(controller.themeMode, ThemeMode.system);
      expect(await persistedRaw(), 'auto');

      await controller.setThemeMode(ThemeMode.light);
      expect(notifications, 2);
      expect(controller.themeMode, ThemeMode.light);
      expect(await persistedRaw(), 'light');
      controller.dispose();
    });

    test('重启语义：新实例 load 恢复上次 setThemeMode 的偏好', () async {
      final first = ThemeController(settingsRepository: repository);
      await first.setThemeMode(ThemeMode.light);
      first.dispose();

      final second = ThemeController(settingsRepository: repository);
      await second.load();
      expect(second.themeMode, ThemeMode.light);
      second.dispose();
    });

    test('load 也触发通知（恢复值可能异于初始 dark，装配方需应用）', () async {
      await repository.setMany({SettingsRepository.themeModeKey: 'light'});
      final controller = ThemeController(settingsRepository: repository);
      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.load();
      expect(notifications, 1);
      controller.dispose();
    });
  });
}
