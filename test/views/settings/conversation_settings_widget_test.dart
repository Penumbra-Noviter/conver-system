/// 「对话」设置子页 widget 契约（工单 03）——temperature slider / max_tokens
/// 输入 + 保存回显 + 设置页导航入口（验收 5/6）。
///
/// seam：ConversationSettingsPage 公开构造（仓储注入）+ SettingsView 公开构造
/// （导航入口）。读写经真实 SettingsRepository（内存 drift 真 schema），断言
/// 落在 `getTemperature()` / `getMaxTokens()` 可观察值上，不锁内部实现。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:conver_system_mobile/views/settings/conversation_settings_page.dart';
import 'package:conver_system_mobile/views/settings/settings_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

/// 加载失败的仓储替身：getTemperature 抛错 → 覆盖 `_load` catch 分支。
class _LoadFailRepo extends SettingsRepository {
  _LoadFailRepo(AppDatabase db)
      : super(database: db, secretStore: InMemorySecretStore());

  @override
  Future<double> getTemperature() async => throw StateError('load fail');
}

/// 保存失败的仓储替身：setMany 抛错 → 覆盖 `_save` catch 分支。
class _SaveFailRepo extends SettingsRepository {
  _SaveFailRepo(AppDatabase db)
      : super(database: db, secretStore: InMemorySecretStore());

  @override
  Future<void> setMany(Map<String, String> data) async =>
      throw StateError('save fail');
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

  /// 高视口 + 深色暖灰主题（注册 ConverPalette ThemeExtension）包一层
  /// MaterialApp，直接挂载子页。
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: ConversationSettingsPage(settingsRepository: repo),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('初始回显缺省 temperature 0.70 / max_tokens 2048', (tester) async {
    await pumpPage(tester);

    expect(find.text('0.70'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2048'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('保存 max_tokens 后重进页面回显已保存值', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), '4096');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await repo.getMaxTokens(), 4096);

    // 卸载后重建子页（强制重新 _load）→ 回显 4096。
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);
    expect(find.widgetWithText(TextField, '4096'), findsOneWidget);
  });

  testWidgets('max_tokens 非法输入：空回退缺省 / 负数 clamp 1 / 超上限 clamp', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await repo.getMaxTokens(), 2048, reason: '空输入回退缺省');

    await tester.enterText(find.byType(TextField), '-5');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await repo.getMaxTokens(), 1, reason: '负数 clamp 到下限');

    await tester.enterText(find.byType(TextField), '99999999');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await repo.getMaxTokens(), 100000, reason: '超上限 clamp 到上限');
  });

  testWidgets('temperature slider 右拖后保存 → 值高于缺省', (tester) async {
    await pumpPage(tester);

    await tester.drag(find.byType(Slider), const Offset(500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(await repo.getTemperature(), greaterThan(0.7));
  });

  testWidgets('设置页「对话」导航入口 → 子页并可返回', (tester) async {
    final themeController = ThemeController(settingsRepository: repo);
    addTearDown(themeController.dispose);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(
          body: SettingsView(
            settingsRepository: repo,
            themeController: themeController,
            secretStore: InMemorySecretStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationSettingsPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationSettingsPage), findsNothing);
    expect(find.text('对话'), findsOneWidget);
  });

  testWidgets('加载失败 → 保持缺省渲染，无未处理异常', (tester) async {
    final failing = _LoadFailRepo(db);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: ConversationSettingsPage(settingsRepository: failing),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.70'), findsOneWidget);
  });

  testWidgets('保存失败 → SnackBar「保存失败」', (tester) async {
    final failing = _SaveFailRepo(db);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: ConversationSettingsPage(settingsRepository: failing),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败'), findsOneWidget);
  });
}
