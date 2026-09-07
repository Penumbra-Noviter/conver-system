// F-M5-10「我」页收口三页面渲染冒烟：用户手册（13 节折叠，逐节改写移动端
// 视角）+ 关于 + 桌面版说明。
//
// seam：ManualPage / AboutPage / DesktopNotePage 三个公开 widget 的渲染
// 行为（标题锚 / 内容锚 / 滚动不溢出）。13 节标题为桌面 `index.html`
// #view-guide 逐字蓝本（独立来源，非实现自算）；关于页版本号锚对拍
// `pubspec.yaml` `version`（防常量漂移）。
library;

import 'dart:io';

import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/settings/about_page.dart';
import 'package:conver_system_mobile/views/settings/desktop_note_page.dart';
import 'package:conver_system_mobile/views/settings/manual_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌面 index.html #view-guide 13 节标题（改写蓝本，逐字）。
const _guideTitles = <String>[
  '快速开始',
  '配置你的 AI 接口（新手必读）',
  '角色管理',
  '对话功能',
  '模拟器使用指南',
  'AI 生成游戏',
  '导入游戏与安全须知',
  '搜索消息',
  '设置说明',
  '桌面版功能（Tauri）',
  '支持的模型',
  '常见问题',
  '小贴士',
];

/// 深色暖灰主题 + 高视口包一层 MaterialApp。
///
/// F-7：主题须 [ConverTheme.dark]（注册 ConverPalette ThemeExtension，
/// 未注册的默认 ThemeData 会使 `ConverPalette.of` 抛错崩溃）。
Future<void> pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ConverTheme.dark(),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

/// 展开 [title] 章节并结算动画。
Future<void> expandSection(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  group('ManualPage（用户手册 13 节折叠）', () {
    testWidgets('13 节标题齐全且逐节对应桌面蓝本', (tester) async {
      await pumpPage(tester, const ManualPage());

      for (final title in _guideTitles) {
        expect(find.text(title), findsOneWidget, reason: '缺失章节标题: $title');
      }
    });

    testWidgets('展开「快速开始」→ 移动端视角：底部 5 tab 导航说明', (tester) async {
      await pumpPage(tester, const ManualPage());

      await expandSection(tester, '快速开始');

      expect(find.textContaining('5 个标签'), findsOneWidget,
          reason: '移动端差异项：底部 5 tab 导航须成节');
      expect(find.textContaining('配置 AI 接口'), findsWidgets);
      expect(find.textContaining('本地优先'), findsWidgets);
    });

    testWidgets(
        '展开「模拟器使用指南」→ 移动端差异三项（官方端点 / 游戏目录 / 导入仅文件选择）',
        (tester) async {
      await pumpPage(tester, const ManualPage());

      await expandSection(tester, '模拟器使用指南');

      expect(find.textContaining('官方端点'), findsWidgets,
          reason: '移动端差异项：官方端点需桌面版');
      expect(find.textContaining('simulators/'), findsOneWidget,
          reason: '移动端差异项：游戏目录位置');
      expect(find.textContaining('拖拽'), findsOneWidget,
          reason: '移动端差异项：导入仅文件选择（不支持拖拽）');
    });

    testWidgets('展开「对话功能」→ 已删桌面 Enter 快捷键', (tester) async {
      await pumpPage(tester, const ManualPage());

      await expandSection(tester, '对话功能');

      expect(find.textContaining('Enter'), findsNothing,
          reason: '桌面 Enter 快捷键属桌面专属项，移动端改写须删除');
      expect(find.textContaining('发送'), findsWidgets,
          reason: '移动端以「发送」按钮描述替代快捷键');
    });

    testWidgets('展开「导入游戏与安全须知」→ 已删 per-game CSS + 移动端更紧拦截语义', (tester) async {
      await pumpPage(tester, const ManualPage());

      await expandSection(tester, '导入游戏与安全须知');

      expect(find.textContaining('.css'), findsNothing,
          reason: '每游戏 PC 覆盖层 CSS 文件属桌面专属项，移动端改写须删除');
      expect(find.textContaining('二次确认'), findsOneWidget,
          reason: '移动端恶意命中 = 拒绝 + 清单 + 二次确认（D13 更紧语义）');
      expect(find.textContaining('文件选择'), findsWidgets,
          reason: '移动端差异项：导入仅文件选择');
    });

    testWidgets('展开「设置说明」→ 已删桌面关闭窗口/托盘行为', (tester) async {
      await pumpPage(tester, const ManualPage());

      await expandSection(tester, '设置说明');

      expect(find.textContaining('托盘'), findsNothing,
          reason: '关闭窗口行为/托盘属桌面专属项，移动端设置节须删除');
      expect(find.textContaining('上下文轮数'), findsOneWidget);
    });

    testWidgets('长文页可滚动不溢出：展开「小贴士」并拖动页面', (tester) async {
      await pumpPage(tester, const ManualPage());

      await expandSection(tester, '小贴士');
      expect(find.textContaining('桌面版说明'), findsWidgets,
          reason: '小贴士节与桌面版说明页互文');

      // 展开后拖动页面，确认可滚动且无渲染溢出异常。
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AboutPage（关于）', () {
    testWidgets('应用名「汇流」+ 版本号 + 数据全本地声明 + 技术栈简述', (tester) async {
      await pumpPage(tester, const AboutPage());

      expect(find.text(AboutPage.appName), findsOneWidget);
      expect(find.textContaining(AboutPage.appVersion), findsOneWidget);
      expect(find.textContaining('SQLite'), findsWidgets,
          reason: '数据全本地声明：SQLite');
      expect(find.textContaining('SecureStorage'), findsWidgets,
          reason: '安全存储声明（数据声明与技术栈两处）');
      expect(find.textContaining('drift'), findsOneWidget,
          reason: '技术栈简述');
      expect(find.textContaining('不会上传'), findsOneWidget,
          reason: '数据不上传声明');
    });
  });

  group('DesktopNotePage（桌面版说明）', () {
    testWidgets('Tauri 存在 + 与移动端差异三项 + 获取途径占位', (tester) async {
      await pumpPage(tester, const DesktopNotePage());

      expect(find.textContaining('Tauri'), findsWidgets);
      expect(find.textContaining('官方端点'), findsWidgets,
          reason: '差异项：官方端点游戏可跑');
      expect(find.textContaining('拖拽'), findsWidgets,
          reason: '差异项：拖拽导入');
      expect(find.textContaining('覆盖层'), findsWidgets,
          reason: '差异项：PC 覆盖层');
      expect(find.textContaining('获取途径'), findsOneWidget);
      expect(find.textContaining('占位'), findsOneWidget,
          reason: '获取途径占位，不实装下载链路');
    });
  });

  group('版本防漂移', () {
    test('AboutPage.appVersion 与 pubspec.yaml version 对齐', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml 须含 version 行');
      expect(AboutPage.appVersion, match!.group(1));
    });
  });

  group('Falsify：窄屏渲染不溢出', () {
    testWidgets('320 逻辑宽下三页均无渲染异常', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final page in const <Widget>[
        ManualPage(),
        AboutPage(),
        DesktopNotePage(),
      ]) {
        await tester.pumpWidget(
          MaterialApp(theme: ConverTheme.dark(), home: page),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '窄屏渲染不得溢出/异常: ${page.runtimeType}');
      }
    });
  });
}
