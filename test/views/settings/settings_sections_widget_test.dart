// F-8 设置页存储异常面 widget 测试：三失败路径（抛错注入）+ 两成功路径（锚文本）
// + settings_view 源码文本断言（不再静默吞错 / 空 onTimeout）。
//
// 注入点（依赖 F-9 完成后的 required 签名）：api_config 经抛错 SecretStore fake
// （槽位清空=删键路径命中）；default_model / theme 经 setMany 抛错的仓储子类。
// 语义契约（spec F-8）：失败 → SnackBar「保存失败，请重试」/「主题切换失败」+
// debugPrint；成功锚文本「API 配置已保存」/「默认模型已保存」不变；_saving 必然复位；
// 主题切换失败时 ThemeController 内部态不变 → UI 选中态保持旧值。
library;

import 'dart:io';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:conver_system_mobile/views/settings/api_config_section.dart';
import 'package:conver_system_mobile/views/settings/default_model_section.dart';
import 'package:conver_system_mobile/views/settings/theme_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

/// 写/删必抛的 SecretStore fake——命中 api_config「槽位字段为空 → delete 抛错」路径。
class _ThrowingSecretStore implements SecretStore {
  @override
  Future<void> write({required String key, required String value}) async {
    throw StateError('write failed');
  }

  @override
  Future<void> delete(String key) async {
    throw StateError('delete failed');
  }

  @override
  Future<String> read(String key) async => '';

  @override
  Future<bool> containsKey(String key) async => false;
}

/// setMany 必抛的 [SettingsRepository] 子类——命中 default_model / theme 保存失败路径。
///
/// [SettingsRepository] 为具体类，Dart 允许 extends；构造沿用父类签名
/// （内存库；secretStore 走父类缺省），仅覆盖 setMany——setMany 先行抛错，
/// 不会触达任何存储通道。
class _ThrowingSettingsRepository extends SettingsRepository {
  _ThrowingSettingsRepository({required super.database});

  @override
  Future<void> setMany(Map<String, String> data) async {
    throw StateError('setMany failed');
  }
}

/// 保存按钮是否可点（_saving 复位 = onPressed 非空）。
bool _saveButtonEnabled(WidgetTester tester, String label) {
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, label),
  );
  return button.onPressed != null;
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(database: db, secretStore: InMemorySecretStore());
  });

  tearDown(() async {
    await db.close();
  });

  /// 包一层 MaterialApp + Scaffold，使 SnackBar（ScaffoldMessenger）可呈现。
  Future<void> pumpSection(WidgetTester tester, Widget section) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: section)),
    );
    await tester.pumpAndSettle();
  }

  group('api_config 保存失败（抛错 SecretStore）', () {
    testWidgets('tap「保存 API 配置」→ 失败 SnackBar + 按钮复位', (tester) async {
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: _ThrowingSecretStore(),
          initialValues: const <String, String>{},
        ),
      );

      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(_saveButtonEnabled(tester, '保存 API 配置'), isTrue,
          reason: '_saving 在失败路径也必须复位（按钮恢复可用）');
    });
  });

  group('default_model 保存失败（setMany 抛错仓储）', () {
    testWidgets('tap「保存默认模型」→ 失败 SnackBar + 按钮复位', (tester) async {
      await pumpSection(
        tester,
        DefaultModelSection(
          settingsRepository: _ThrowingSettingsRepository(database: db),
        ),
      );

      await tester.tap(find.text('保存默认模型'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(_saveButtonEnabled(tester, '保存默认模型'), isTrue,
          reason: '_saving 在失败路径也必须复位（按钮恢复可用）');
    });
  });

  group('theme 切换失败（setMany 抛错仓储）', () {
    testWidgets('tap「浅色」→ 失败 SnackBar + themeMode 保持原值', (tester) async {
      final controller = ThemeController(
        settingsRepository: _ThrowingSettingsRepository(database: db),
      );
      await pumpSection(
        tester,
        ThemeSection(themeController: controller),
      );

      expect(controller.themeMode, ThemeMode.dark); // 原值（未 load，首启基线）

      await tester.tap(find.text('浅色'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('主题切换失败'), findsOneWidget);
      expect(controller.themeMode, ThemeMode.dark,
          reason: '控制器失败即抛、内部态未赋值 → 选中态保持旧值');
      controller.dispose();
    });
  });

  group('成功路径（内存库真仓储 + InMemorySecretStore）', () {
    testWidgets('保存 API 配置 → 成功锚「API 配置已保存」', (tester) async {
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: InMemorySecretStore(),
          initialValues: const <String, String>{},
        ),
      );

      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('API 配置已保存'), findsOneWidget);
    });

    testWidgets('保存默认模型 → 成功锚「默认模型已保存」', (tester) async {
      await pumpSection(
        tester,
        DefaultModelSection(settingsRepository: repo),
      );

      await tester.tap(find.text('保存默认模型'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('默认模型已保存'), findsOneWidget);
    });
  });

  group('settings_view 源码文本断言（不静默吞错）', () {
    test('不再含字面量 catch (_) { 与 onTimeout: () {', () {
      final source =
          File('lib/views/settings/settings_view.dart').readAsStringSync();
      expect(source, isNot(contains('catch (_) {')));
      expect(source, isNot(contains('onTimeout: () {')));
    });
  });
}
