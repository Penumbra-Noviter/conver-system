// C4 设置页行收敛：共享行组件 `_SettingsRow`（占位行/导航行复用）行为回归。
//
// seam：SettingsView 公开构造（仓储/主题控制器/安全存储注入）。共享行组件
// 是 settings_view.dart 文件内私有组件（本票默认不新增文件），经 SettingsView
// 整页渲染断言其渲染契约：
//   - label + note 逐字段渲染（占位行与导航行同结构）；
//   - chevron 仅导航行（onTap 非空）渲染，占位行无 chevron、不可点；
//   - 导航行整行可点 → push 对应静态页。
//
// 文本锚 + 导航行为回归由 settings_nav_test（只读）锁定，本文件补充占位行
// 不可点与 chevron 归属两类共享行组件专属断言。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:conver_system_mobile/views/settings/about_page.dart';
import 'package:conver_system_mobile/views/settings/manual_page.dart';
import 'package:conver_system_mobile/views/settings/settings_view.dart';
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

  /// 高视口 + 深色暖灰主题包一层 MaterialApp（与 settings_nav_test 同装配）。
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

  /// label/note 所在行的祖先 InkWell（导航行整行可点 → 必有 InkWell）。
  Finder rowInkWell(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );

  group('设置页共享行组件（C4 行收敛）', () {
    testWidgets('占位行与导航行同结构渲染：label + note 全命中', (tester) async {
      await pumpSettings(tester);

      for (final text in ['对话', '生成参数与行为', '模板变量', '自定义注入变量']) {
        expect(find.text(text), findsOneWidget, reason: '占位行 $text');
      }
      for (final text in ['用户手册', '使用说明', '关于', '版本信息', '桌面版说明', '桌面端获取指引']) {
        expect(find.text(text), findsOneWidget, reason: '导航行 $text');
      }
    });

    testWidgets('chevron 仅导航行渲染（3 个），占位行无 chevron', (tester) async {
      await pumpSettings(tester);

      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3),
          reason: '仅三导航行渲染 chevron，占位行不渲染（与现状视觉一致）');
      // 占位行 label 所在行不得含 chevron。
      for (final label in ['对话', '模板变量']) {
        expect(
          find.descendant(
            of: rowInkWell(label),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsNothing,
          reason: '占位行「$label」不渲染 chevron',
        );
      }
    });

    testWidgets('占位行不可点：tap「对话」不触发任何导航', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('对话'));
      await tester.pumpAndSettle();

      expect(find.byType(ManualPage), findsNothing);
      expect(find.byType(AboutPage), findsNothing);
      expect(find.text('用户手册'), findsOneWidget, reason: '仍在设置页，未 push');
    });

    testWidgets('导航行整行可点：tap 行内 note → push 对应页', (tester) async {
      await pumpSettings(tester);

      // 点行内 note（「使用说明」）而非 label —— 验证整行 InkWell 触达。
      await tester.tap(find.text('使用说明'));
      await tester.pumpAndSettle();

      expect(find.byType(ManualPage), findsOneWidget,
          reason: '共享行组件 onTap 非空 → 整行可点进 ManualPage');
    });
  });
}