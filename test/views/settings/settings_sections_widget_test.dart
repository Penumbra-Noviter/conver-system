// F-8 设置页存储异常面 widget 测试：三失败路径（抛错注入）+ 两成功路径（锚文本）
// + settings_view 源码文本断言（不再静默吞错 / 空 onTimeout）。
//
// 注入点（依赖 F-9 完成后的 required 签名）：api_config 经抛错 SecretStore fake
// （槽位清空=删键路径命中）；default_model / theme 经 setMany 抛错的仓储子类。
// 语义契约（spec F-8）：失败 → SnackBar「保存失败，请重试」/「主题切换失败」+
// debugPrint；成功锚文本「API 配置已保存」/「默认模型已保存」不变；_saving 必然复位；
// 主题切换失败时 ThemeController 内部态不变 → UI 选中态保持旧值。
library;

import 'dart:async';
import 'dart:io';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:conver_system_mobile/views/settings/api_config_section.dart';
import 'package:conver_system_mobile/views/settings/default_model_section.dart';
import 'package:conver_system_mobile/views/settings/settings_view.dart';
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

/// getValue 必抛的 [SettingsRepository] 子类——命中 theme 偏好加载（DB 读）失败路径。
///
/// 仅覆盖 getValue：ThemeController.load() 直读设置表，getValue 抛错即
/// 存储通道异常；_loadEcho 的内层 try/catch 会兜住自己那一路，暴露的
/// 正是 `_themeController.load()` 无 catchError 的未处理异常面（F-12）。
class _LoadThrowingSettingsRepository extends SettingsRepository {
  _LoadThrowingSettingsRepository({required super.database});

  @override
  Future<String> getValue(String key, {String defaultValue = ''}) async {
    throw StateError('getValue failed');
  }
}

/// setMany 可挂起且计数的 [SettingsRepository] 子类——命中 F-13 重入窗口。
///
/// [gate] 为 null 时 setMany 立即完成（正常路径）；测试置 gate =
/// Completer 后首次写入挂起（in-flight），以此锁定重入守卫窗口。
class _HoldingSettingsRepository extends SettingsRepository {
  _HoldingSettingsRepository({required super.database});

  /// setMany 已调用的次数（持久化写入发生次数）。
  int setManyCalls = 0;

  /// 挂起门：非 null 时 setMany await 到 complete 才返回。
  Completer<void>? gate;

  @override
  Future<void> setMany(Map<String, String> data) async {
    setManyCalls++;
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
  }
}

/// getValue 永久挂起的 [SettingsRepository] 子类——命中 load 的 DB 通道挂起路径。
///
/// 只覆盖 getValue 且永不返回：`_themeController.load()` 挂起 → 3s 超时
/// onTimeout 兜底（Flutter 挂起非抛错，须以 timeout 兜底而非 try/catch）。
class _HangingSettingsRepository extends SettingsRepository {
  _HangingSettingsRepository({required super.database});

  @override
  Future<String> getValue(String key, {String defaultValue = ''}) {
    // 永久挂起（模拟平台通道缺失导致 DB 读取永不返回）
    return Completer<String>().future;
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
  ///
  /// 主题须用 [ConverTheme.dark]（F-7 起各 section 消费
  /// `extension<ConverPalette>()!`，默认 ThemeData 不含该扩展会空指针崩溃；
  /// 真实应用由 ConverApp 装配同一主题注册）。
  Future<void> pumpSection(WidgetTester tester, Widget section) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: section),
      ),
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

  group('theme 偏好加载失败（load 抛错仓储）', () {
    testWidgets('load 抛错 → 无 zone 未处理异常 + 保持缺省 dark', (tester) async {
      final throwingRepo = _LoadThrowingSettingsRepository(database: db);
      final controller = ThemeController(settingsRepository: throwingRepo);
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(
            body: SettingsView(
              settingsRepository: throwingRepo,
              themeController: controller,
              secretStore: InMemorySecretStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.themeMode, ThemeMode.dark,
          reason: 'load 失败 → 保持缺省 dark（未 load 基线）');
      controller.dispose();
    });
  });

  group('theme 偏好加载挂起/成功（F-12 补充路径）', () {
    testWidgets('load 挂起 → 3s 超时 onTimeout 兜底 + 保持缺省 dark', (tester) async {
      final hangingRepo = _HangingSettingsRepository(database: db);
      final controller = ThemeController(settingsRepository: hangingRepo);
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(
            body: SettingsView(
              settingsRepository: hangingRepo,
              themeController: controller,
              secretStore: InMemorySecretStore(),
            ),
          ),
        ),
      );
      // 推进假时钟越过 3s 超时，触发 onTimeout 兜底（挂起非抛错 → 不产生异常）
      await tester.pump(const Duration(seconds: 4));
      expect(controller.themeMode, ThemeMode.dark,
          reason: 'load 挂起 → 超时兜底，保持缺省 dark');
      controller.dispose();
    });

    testWidgets('load 成功 → catchError 不吞成功路径，themeMode 恢复持久化值', (tester) async {
      final okRepo = SettingsRepository(
        database: db,
        secretStore: InMemorySecretStore(),
      );
      await okRepo.setMany({SettingsRepository.themeModeKey: 'light'});
      final controller = ThemeController(settingsRepository: okRepo);
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(
            body: SettingsView(
              settingsRepository: okRepo,
              themeController: controller,
              secretStore: InMemorySecretStore(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.light,
          reason: 'load 成功 → 恢复持久化 light，catchError 不吞成功路径');
      controller.dispose();
    });
  });

  group('theme 切换重入守卫（挂起 setMany 仓储）', () {
    testWidgets('in-flight 期间 tap「跟随系统」→ 不产生第二次写入', (tester) async {
      final holding = _HoldingSettingsRepository(database: db)
        ..gate = Completer<void>();
      final controller = ThemeController(settingsRepository: holding);
      await pumpSection(tester, ThemeSection(themeController: controller));

      await tester.tap(find.text('浅色'));
      await tester.pump();
      expect(holding.setManyCalls, 1,
          reason: '首次点击已触发持久化（in-flight 挂起中）');

      // in-flight 期间点「跟随系统」（非旧值）→ 重入守卫应吞掉，不产生第二次写入
      await tester.tap(find.text('跟随系统'));
      await tester.pump();
      expect(holding.setManyCalls, 1,
          reason: 'in-flight 期间后续点击被守卫吞掉，不产生第二次写入');

      holding.gate!.complete();
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.light,
          reason: '释放门后首次写入正常提交为 light');
      controller.dispose();
    });

    testWidgets('in-flight 期间 tap「深色」（旧值）→ 同样不产生第二次写入', (tester) async {
      final holding = _HoldingSettingsRepository(database: db)
        ..gate = Completer<void>();
      final controller = ThemeController(settingsRepository: holding);
      await pumpSection(tester, ThemeSection(themeController: controller));

      await tester.tap(find.text('浅色'));
      await tester.pump();
      expect(holding.setManyCalls, 1);

      // 反向点击「深色」= 当前 themeMode 旧值 → 守卫吞掉，不产生第二次写入
      await tester.tap(find.text('深色'));
      await tester.pump();
      expect(holding.setManyCalls, 1,
          reason: 'in-flight 期间反向点击旧值也不产生第二次写入');

      holding.gate!.complete();
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.light);
      controller.dispose();
    });

    testWidgets('守卫复位：in-flight 完成后可正常再次切换（非永久锁死）', (tester) async {
      final holding = _HoldingSettingsRepository(database: db)
        ..gate = Completer<void>();
      final controller = ThemeController(settingsRepository: holding);
      await pumpSection(tester, ThemeSection(themeController: controller));

      // 第一次切换：浅色（挂起 → 释放门）
      await tester.tap(find.text('浅色'));
      await tester.pump();
      expect(holding.setManyCalls, 1);
      holding.gate!.complete();
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.light);

      // 守卫复位后再次切换：深色 → 第二次写入正常发生
      await tester.tap(find.text('深色'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(holding.setManyCalls, 2,
          reason: '守卫完成后复位，可正常再次切换（非永久锁死）');
      expect(controller.themeMode, ThemeMode.dark);
      controller.dispose();
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
    test('不再含字面量 catch (_) { 与 onTimeout: () {，且 load 路径带 catchError', () {
      final source =
          File('lib/views/settings/settings_view.dart').readAsStringSync();
      expect(source, isNot(contains('catch (_) {')));
      expect(source, isNot(contains('onTimeout: () {')));
      // F-12：主题偏好加载路径必须补 catchError（而不是静默 try/catch 或空 onTimeout）
      expect(source, contains('catchError'));
    });
  });
}
