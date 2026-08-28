/// 主题装配行为断言（M1-T07，工单验收 A4/A5）。
///
/// F-4 契约锁（test/app_contract_test.dart，本票已按其注释退役）只能以
/// 源码文本锚锁定装配行，无运行态判别力；本测试承接其防回归意图并升级为
/// **行为断言**：pump 真实 ConverApp → 改 ThemeController 值 → 断言
/// MaterialApp 实际生效对应 ThemeData（themeMode 深浅真实切换具判别力——
/// darkTheme 非 null 后 ThemeMode 三值才有行为差异）。
///
/// 数据面注入内存执行器（M0 seam）：首启/切换/重启路径全部确定性运行，
/// 不依赖平台通道（测试环境下真实通道挂起，见工单 06 证据）。
library;

import 'dart:async';

import 'package:conver_system_mobile/app.dart';
import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/theme/colors.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
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

  /// MaterialApp 之下的任一 context（NavigationBar 元素稳定存在）。
  BuildContext contextUnderMaterialApp(WidgetTester tester) =>
      tester.element(find.byType(NavigationBar));

  testWidgets('A4 首启行为：设置表无 theme_mode 行 → themeMode dark 且深色生效', (
    tester,
  ) async {
    await pumpApp(tester);

    final context = contextUnderMaterialApp(tester);
    expect(context.read<ThemeController>().themeMode, ThemeMode.dark);
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, ConverColors.page);
  });

  testWidgets('F-4 承接：切 light → MaterialApp 实际生效浅色；切回 dark 恢复', (
    tester,
  ) async {
    await pumpApp(tester);

    final controller = contextUnderMaterialApp(tester).read<ThemeController>();

    unawaited(controller.setThemeMode(ThemeMode.light));
    await tester.pumpAndSettle();
    final light = Theme.of(contextUnderMaterialApp(tester));
    expect(light.brightness, Brightness.light);
    expect(light.scaffoldBackgroundColor, ConverColorsLight.page);
    expect(light.colorScheme.primary, ConverColorsLight.accent);

    // 切回 dark：themeMode 深浅双向切换均真实生效（判别性断言的核心）。
    unawaited(controller.setThemeMode(ThemeMode.dark));
    await tester.pumpAndSettle();
    final dark = Theme.of(contextUnderMaterialApp(tester));
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, ConverColors.page);
  });

  testWidgets('重启恢复：持久化 theme_mode=light 后重建应用 → 启动即浅色', (
    tester,
  ) async {
    await pumpApp(tester);
    final controller = contextUnderMaterialApp(tester).read<ThemeController>();
    unawaited(controller.setThemeMode(ThemeMode.light));
    await tester.pumpAndSettle();
    expect(
      Theme.of(contextUnderMaterialApp(tester)).brightness,
      Brightness.light,
    );

    // 模拟重启：同一数据库重建应用（全新控制器），持久化偏好直接生效。
    await tester.pumpWidget(ConverApp(database: db));
    await tester.pumpAndSettle();
    final context = contextUnderMaterialApp(tester);
    expect(context.read<ThemeController>().themeMode, ThemeMode.light);
    expect(Theme.of(context).brightness, Brightness.light);
  });
}
