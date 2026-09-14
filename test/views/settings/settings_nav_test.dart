// F-M5-10「我」页收口导航测试：设置页三占位（用户手册/关于/桌面版说明）
// 真实化为可点击导航入口 + 进入对应页面可返回；「对话」「模板变量」两占位
// 保持原样（不在 M5 范围，锚共识 D1）。
//
// seam：SettingsView 公开构造（仓储/主题控制器/安全存储注入）+ 三个页面类
// 公开构造。导航经 root Navigator push（与 characters_view 既有全屏下钻
// 同一模式）；三页面渲染细节冒烟在 manual_pages_test.dart。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:conver_system_mobile/views/settings/about_page.dart';
import 'package:conver_system_mobile/views/settings/desktop_note_page.dart';
import 'package:conver_system_mobile/views/settings/manual_page.dart';
import 'package:conver_system_mobile/views/settings/settings_view.dart';
import 'package:conver_system_mobile/views/settings/template_vars_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;
  late ThemeController themeController;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(database: db, secretStore: InMemorySecretStore());
    themeController = ThemeController(settingsRepository: repo);
  });

  tearDown(() async {
    themeController.dispose();
    await db.close();
  });

  /// 高视口（设置页内容超默认 600px 视口）+ 深色暖灰主题包一层 MaterialApp。
  ///
  /// F-7：主题须 [ConverTheme.dark]（注册 ConverPalette ThemeExtension，
  /// 未注册的默认 ThemeData 会使 `ConverPalette.of` 抛错崩溃）。
  Future<void> pumpSettings(WidgetTester tester) async {
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
  }

  group('设置页三占位真实化为导航入口（F-M5-10）', () {
    testWidgets('三入口行存在且带 chevron 触达语义', (tester) async {
      await pumpSettings(tester);

      expect(find.text('用户手册'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('桌面版说明'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(5),
          reason: '三入口 + 「对话」（工单 03）+「模板变量」（工单 04）共 5 行 chevron');
    });

    testWidgets('「对话」与「模板变量」导航入口并存', (tester) async {
      await pumpSettings(tester);

      expect(find.text('对话'), findsOneWidget);
      expect(find.text('生成参数与行为'), findsOneWidget);
      expect(find.text('模板变量'), findsOneWidget);
      expect(find.text('自定义注入变量'), findsOneWidget);
    });

    testWidgets('点「模板变量」→ TemplateVarsPage，返回 → 回到设置页', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('模板变量'));
      await tester.pumpAndSettle();
      expect(find.byType(TemplateVarsPage), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(TemplateVarsPage), findsNothing);
      expect(find.text('模板变量'), findsOneWidget,
          reason: '返回后回到设置页，入口行仍在');
    });

    testWidgets('点「用户手册」→ ManualPage，返回 → 回到设置页', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('用户手册'));
      await tester.pumpAndSettle();
      expect(find.byType(ManualPage), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ManualPage), findsNothing);
      expect(find.text('用户手册'), findsOneWidget,
          reason: '返回后回到设置页，入口行仍在');
    });

    testWidgets('点「关于」→ AboutPage（应用名「汇流」）', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.text('汇流'), findsWidgets);
    });

    testWidgets('点「桌面版说明」→ DesktopNotePage（Tauri 文案）', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('桌面版说明'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopNotePage), findsOneWidget);
      expect(find.textContaining('Tauri'), findsWidgets);
    });
  });
}
