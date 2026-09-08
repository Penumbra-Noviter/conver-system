/// StatusView 共享组件契约（M6-01）——状态页（图标 + 可选标题 + 原因/文案 +
/// 可选提示 + 动作区）。
///
/// 验收语义（工单 01 验收 2/3/7 + spec §4.3 + 共识 §3.3）：
/// - 覆盖模拟器列表 `_StatusColumn`（无标题 + 原因 + 可选动作）与运行页
///   `_ErrorView`（标题 + 原因 + 重试/返回动作区）两者形态；
/// - 图标 40px（ink4）+ 标题（ink1，titleSmall）+ 原因（ink2，bodyMedium，
///   居中）+ 可选提示（ink4）+ 动作区；缺省不渲染；
/// - 装饰图标内建 ExcludeSemantics（语义树无图标描述，spec §4.4 覆盖清单 ②）；
/// - 动作区点击派发（T1 页面级错误页「重试」语义）；
/// - 边界防御：空原因 / 超长标题与提示 / 空动作列表不崩（Falsify）。
///
/// 测试 seam（公共接口边界）：[StatusView] 公开构造参数（icon / title /
/// message / hint / actions），经 ConverTheme.dark（ConverPalette 注册）装配。
library;

import 'package:conver_system_mobile/theme/conver_palette.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/widgets/status_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpStatusView(
    WidgetTester tester, {
    IconData icon = Icons.error_outline,
    String? title,
    required String message,
    String? hint,
    List<Widget> actions = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(
          body: Center(
            child: StatusView(
              icon: icon,
              title: title,
              message: message,
              hint: hint,
              actions: actions,
            ),
          ),
        ),
      ),
    );
  }

  group('状态页渲染（验收 2）', () {
    testWidgets('图标 + 标题 + 原因 + 提示 + 动作区', (tester) async {
      await pumpStatusView(
        tester,
        title: '游戏加载失败',
        message: '加载超时（15 秒未收到响应）',
        hint: '可重试',
        actions: [
          FilledButton(onPressed: () {}, child: const Text('重试')),
          OutlinedButton(onPressed: () {}, child: const Text('返回')),
        ],
      );

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(iconWidget.size, 40, reason: '线性图标 40px');
      expect(iconWidget.color, ConverPalette.dark().ink4, reason: '图标 ink4');

      final title = tester.widget<Text>(find.text('游戏加载失败'));
      expect(title.style?.color, ConverPalette.dark().ink1, reason: '标题 ink1');

      final message =
          tester.widget<Text>(find.text('加载超时（15 秒未收到响应）'));
      expect(message.style?.color, ConverPalette.dark().ink2,
          reason: '原因/文案 ink2');
      expect(message.textAlign, TextAlign.center, reason: '原因居中');

      final hint = tester.widget<Text>(find.text('可重试'));
      expect(hint.style?.color, ConverPalette.dark().ink4, reason: '提示 ink4');

      expect(find.text('重试'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
    });

    testWidgets('覆盖 _StatusColumn 形态：无标题单文案 + 单个动作', (tester) async {
      await pumpStatusView(
        tester,
        message: '模拟器启动失败',
        actions: [
          FilledButton(onPressed: () {}, child: const Text('重试')),
        ],
      );

      expect(find.text('模拟器启动失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('游戏加载失败'), findsNothing, reason: '无标题形态');
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('缺省参数：无标题/提示/动作区不渲染', (tester) async {
      await pumpStatusView(tester, message: '模拟器启动失败');

      expect(find.text('模拟器启动失败'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('动作区交互（验收 7 语义）', () {
    testWidgets('动作按钮点击派发回调', (tester) async {
      var retried = 0;
      await pumpStatusView(
        tester,
        title: '游戏加载失败',
        message: '原因文案',
        actions: [
          FilledButton(onPressed: () => retried++, child: const Text('重试')),
        ],
      );

      await tester.tap(find.text('重试'));
      expect(retried, 1, reason: '「重试」动作回调被派发');
    });
  });

  group('装饰图标语义（验收 3）', () {
    testWidgets('图标内建 ExcludeSemantics；标题/原因在语义树可读', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpStatusView(
        tester,
        title: '游戏加载失败',
        message: '原因文案',
      );

      expect(
        find.descendant(
          of: find.byType(ExcludeSemantics),
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
        reason: '装饰图标被 ExcludeSemantics 包裹（内建于组件）',
      );
      expect(find.bySemanticsLabel('游戏加载失败'), findsOneWidget,
          reason: '标题在语义树可读');
      expect(find.bySemanticsLabel('原因文案'), findsOneWidget,
          reason: '原因在语义树可读');
      handle.dispose();
    });
  });

  group('边界输入（Falsify）', () {
    testWidgets('空原因 / 超长标题与提示 / 空动作列表不崩', (tester) async {
      await pumpStatusView(
        tester,
        title: '长' * 300,
        message: '',
        hint: '长' * 300,
        actions: const [],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(StatusView), findsOneWidget);
    });
  });
}