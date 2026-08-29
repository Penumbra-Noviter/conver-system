// F-7 视图层 token 主题化：ConverPalette ThemeExtension。
//
// 三部分：
// 1. 静态不变量：lib/views/** + lib/widgets/** 不含 `ConverColors` /
//    `ConverColorsLight` 标识符（词边界正则，忽略合法存续的 `ConverSpacing`）——
//    视图层只经 `Theme.of(context).extension<ConverPalette>()!` 消费。
// 2. 浅色 widget 断言：pump 真实 ConverApp（内存库）→ 切浅色 → 设置页页头
//    「设置」/副标题「应用配置集中管理」/聊天占位标题「聊天」用浅色 ink token。
// 3. 深色回归：同上三锚点用深色 ink token（深色板逐位不变）。
//
// 锚文本限定：`设置` 同时存在于 NavigationBar label 与设置页页头，须以
// `find.descendant(of: find.byType(SettingsView), ...)` 限定；`聊天` 同时存在
// 于 NavigationBar label 与 PlaceholderGroup 标题，须以
// `find.descendant(of: find.byType(PlaceholderGroup), ...)` 限定。
library;

import 'dart:async';
import 'dart:io';

import 'package:conver_system_mobile/app.dart';
import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/theme/colors.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:conver_system_mobile/views/settings/settings_view.dart';
import 'package:conver_system_mobile/widgets/placeholder_group.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 递归收集 [dir] 下全部 `.dart` 文件。
List<File> _dartFilesUnder(Directory dir) {
  final files = <File>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }
  return files;
}

void main() {
  test('静态不变量：lib/views/** + lib/widgets/** 不含 ConverColors / ConverColorsLight', () {
    final unique = <File>[
      ..._dartFilesUnder(Directory('lib/views')),
      ..._dartFilesUnder(Directory('lib/widgets')),
    ];
    final seen = <String>{};
    final files = <File>[
      for (final f in unique)
        if (seen.add(f.path)) f,
    ]..sort((a, b) => a.path.compareTo(b.path));

    // 扫描面 guard（防空目录下断言恒真）。
    expect(files, isNotEmpty, reason: '扫描面应包含视图层/共用组件源文件');
    expect(
      files.map((f) => f.path.replaceAll('\\', '/')),
      contains('lib/views/home_shell.dart'),
      reason: '路径应解析自包根目录',
    );

    final offending = <String>[
      for (final f in files)
        if (RegExp(r'\bConverColors\b').hasMatch(f.readAsStringSync()) ||
            RegExp(r'\bConverColorsLight\b').hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(offending, isEmpty,
        reason: '视图层/共用组件不得直接引用 ConverColors/ConverColorsLight（须经 ConverPalette）');
  });

  group('ConverApp 主题切换下视图层文字 token（F-7）', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(ConverApp(database: db));
      await tester.pumpAndSettle();
    }

    BuildContext contextUnderMaterialApp(WidgetTester tester) =>
        tester.element(find.byType(NavigationBar));

    Finder navLabel(String label) => find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );

    Future<void> setThemeMode(WidgetTester tester, ThemeMode mode) async {
      final controller =
          contextUnderMaterialApp(tester).read<ThemeController>();
      unawaited(controller.setThemeMode(mode));
      await tester.pumpAndSettle();
    }

    testWidgets('浅色：设置页页头/副标题/聊天占位标题用浅色 ink token', (tester) async {
      await pumpApp(tester);
      await setThemeMode(tester, ThemeMode.light);

      // 默认 tab=聊天：PlaceholderGroup 标题用浅色 ink1。
      final chatTitle = tester.widget<Text>(
        find.descendant(
          of: find.byType(PlaceholderGroup),
          matching: find.text('聊天'),
        ),
      );
      expect(chatTitle.style?.color, ConverColorsLight.ink1);

      // 导航到设置 tab。
      await tester.tap(navLabel('设置'));
      await tester.pumpAndSettle();

      // 设置页页头（限定于 SettingsView 内，避开 NavigationBar label）。
      final settingsTitle = tester.widget<Text>(
        find.descendant(
          of: find.byType(SettingsView),
          matching: find.text('设置'),
        ),
      );
      expect(settingsTitle.style?.color, ConverColorsLight.ink1);

      // 设置页副标题（ink3）。
      final subtitle =
          tester.widget<Text>(find.text('应用配置集中管理'));
      expect(subtitle.style?.color, ConverColorsLight.ink3);
    });

    testWidgets('深色回归：同三锚点用深色 ink token（深色板逐位不变）', (tester) async {
      await pumpApp(tester);
      await setThemeMode(tester, ThemeMode.dark);

      final chatTitle = tester.widget<Text>(
        find.descendant(
          of: find.byType(PlaceholderGroup),
          matching: find.text('聊天'),
        ),
      );
      expect(chatTitle.style?.color, ConverColors.ink1);

      await tester.tap(navLabel('设置'));
      await tester.pumpAndSettle();

      final settingsTitle = tester.widget<Text>(
        find.descendant(
          of: find.byType(SettingsView),
          matching: find.text('设置'),
        ),
      );
      expect(settingsTitle.style?.color, ConverColors.ink1);

      final subtitle =
          tester.widget<Text>(find.text('应用配置集中管理'));
      expect(subtitle.style?.color, ConverColors.ink3);
    });
  });
}
