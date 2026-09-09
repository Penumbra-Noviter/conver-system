/// EmptyState 共享组件契约（M6-01）——空态三段式（线性图标 + 主文案 + 可选提示）。
///
/// 验收语义（工单 01 验收 1/3 + spec §4.2 + 共识 §2.2）：
/// - 装饰性线性图标 40px（ink4）+ 主文案（ink3，bodyMedium）+ 可选提示
///   （ink4，bodySmall）；可选提示缺省不渲染；
/// - 装饰图标内建 ExcludeSemantics（语义树无图标描述，spec §4.4 覆盖清单 ②）；
/// - 空态不加操作入口（TP-4 定案），不预建参数槽；未来需要经版本控制恢复；
/// - 边界防御：空主文案 / 超长提示不崩（Falsify）。
///
/// 测试 seam（公共接口边界）：[EmptyState] 公开构造参数（icon / message /
/// hint），经 ConverTheme.dark（ConverPalette 注册）装配。
library;

import 'package:conver_system_mobile/theme/conver_palette.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpEmptyState(
    WidgetTester tester, {
    IconData icon = Icons.person_outline,
    required String message,
    String? hint,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(
          body: Center(
            child: EmptyState(
              icon: icon,
              message: message,
              hint: hint,
            ),
          ),
        ),
      ),
    );
  }

  group('三段式渲染（验收 1）', () {
    testWidgets('图标 40px ink4 + 主文案 ink3 + 提示 ink4', (tester) async {
      await pumpEmptyState(
        tester,
        icon: Icons.chat_bubble_outline,
        message: '还没有对话',
        hint: '点「新建对话」开始第一段聊天',
      );

      final iconWidget =
          tester.widget<Icon>(find.byIcon(Icons.chat_bubble_outline));
      expect(iconWidget.size, 40, reason: '线性图标 40px');
      expect(iconWidget.color, ConverPalette.dark().ink4, reason: '图标 ink4');

      final message = tester.widget<Text>(find.text('还没有对话'));
      expect(message.style?.color, ConverPalette.dark().ink3,
          reason: '主文案 ink3');
      expect(message.textAlign, TextAlign.center, reason: '主文案居中');

      final hint =
          tester.widget<Text>(find.text('点「新建对话」开始第一段聊天'));
      expect(hint.style?.color, ConverPalette.dark().ink4, reason: '提示 ink4');
    });

    testWidgets('可选提示缺省：hint 不渲染', (tester) async {
      await pumpEmptyState(tester, message: '暂无角色');

      expect(find.text('暂无角色'), findsOneWidget);
      expect(find.text('点「新建角色」创建你的第一个角色'), findsNothing,
          reason: '未传 hint 不渲染提示行');
    });
  });

  group('装饰图标语义（验收 3）', () {
    testWidgets('图标内建 ExcludeSemantics；主文案/提示在语义树可读', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpEmptyState(
        tester,
        message: '暂无角色',
        hint: '点「新建角色」创建你的第一个角色',
      );

      expect(
        find.descendant(
          of: find.byType(ExcludeSemantics),
          matching: find.byIcon(Icons.person_outline),
        ),
        findsOneWidget,
        reason: '装饰图标被 ExcludeSemantics 包裹（内建于组件）',
      );
      expect(find.bySemanticsLabel('暂无角色'), findsOneWidget,
          reason: '主文案在语义树可读');
      expect(find.bySemanticsLabel('点「新建角色」创建你的第一个角色'),
          findsOneWidget, reason: '提示在语义树可读');
      handle.dispose();
    });
  });

  group('边界输入（Falsify）', () {
    testWidgets('空主文案 / 超长提示不崩', (tester) async {
      await pumpEmptyState(tester, message: '', hint: '长' * 500);
      expect(tester.takeException(), isNull);
      expect(find.byType(EmptyState), findsOneWidget);
    });
  });
}