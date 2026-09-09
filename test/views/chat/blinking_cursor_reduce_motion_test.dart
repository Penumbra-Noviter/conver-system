/// M6-03/05 打字机光标 reduce-motion 契约——系统「减弱动效」时 ▍ 光标停闪。
///
/// 验收语义（工单 05 验收 1 + spec §4.4 reduce-motion + 共识 4.5）：
/// - `MediaQuery.disableAnimations == true` → 光标不循环（无进行中的 repeat
///   动画），静态 ▍ 呈现（保持占位宽度，列表布局不跳动）；
/// - false → 既有闪烁行为不变（repeat 循环）；
/// - 同挂载内 disableAnimations 运行时翻转（true→false）→ 静态 ▍ 恢复
///   闪烁，且翻转帧本身 opacity 保持连续（不闪断一帧）。
///
/// 测试 seam（公共接口边界）：经 ChatView 渲染 streaming 占位气泡（打字机
/// 光标只出现在流式占位内），通过 MaterialApp 的 builder 注入
/// MediaQuery(data: disableAnimations) 定向构造；同挂载翻转 = re-pump 结构
/// 相同的树（State 保留）仅改媒体设定。断言 TickerMode/animation 状态、
/// ▍ 可见性与 zone 零未处理异常。
///
/// 环境形态同 chat_view_test：每测试体自建 env + 显式 close。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';

import '../../helpers/chat_test_env.dart';
import '../../helpers/fake_llm_provider.dart';

/// 取打字机光标的 FadeTransition（▍ Text 祖先中**最内层**那一个）当前 opacity。
///
/// 外层 anc[1..4] 均为 Material 内部恒 1.0 的 FadeTransition；最内层才是光标
/// 动画对象（`Tween(begin: 0.25, end: 1).animate(controller)`）。
double cursorOpacity(WidgetTester tester) {
  final cursor = find.text('▍', findRichText: true);
  final ancestors = find
      .ancestor(of: cursor, matching: find.byType(FadeTransition))
      .evaluate();
  final element = ancestors.first;
  return tester
      .widget<FadeTransition>(find.byElementPredicate((e) => e == element))
      .opacity
      .value;
}

void main() {
  /// pump ChatView 于 [enableAnimations] 的可访问性媒体设定下。
  ///
  /// 同挂载翻转：re-pump 结构相同的树（MaterialApp/ChatView 原位 update），
  /// `_BlinkingCursorState` 不重建，仅 MediaQuery.disableAnimations 改变 →
  /// 走 didChangeDependencies 运行时翻转路径。
  Future<void> pumpChat(
    WidgetTester tester,
    ChatController controller, {
    required bool enableAnimations,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: !enableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(body: ChatView(controller: controller)),
      ),
    );
    await tester.pump();
  }

  group('reduce-motion：▍ 光标停闪（验收 1）', () {
    testWidgets('disableAnimations=true → 无 repeat 动画 + ▍ 静态可见', (tester) async {
      final env = await ChatTestEnv.create();
      final controller = env.controllerOf(
        TickingFakeLLMProvider(
          tokens: const ['早', '上', '好', '啊', '这', '条', '长'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await controller.loadEntry();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await controller.openConversation(conv.id);
      await pumpChat(tester, controller, enableAnimations: false);

      // 发送消息进入 streaming（▍ 光标出现）。
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      expect(find.text('▍'), findsOneWidget, reason: '光标静态呈现（不隐藏）');

      // 图形不变：取 FadeTransition 的 opacity 值，两个时点应一致（静态）。
      // （该 FadeTransition 即打字机光标动画对象；token 序列足够长保证
      // 采样窗口内流式未完成、光标持续存在。）
      expect(find.byType(FadeTransition), findsWidgets,
          reason: 'FadeTransition（光标动画对象）在树中');
      final first = cursorOpacity(tester);
      await tester.pump(const Duration(milliseconds: 20));
      final second = cursorOpacity(tester);
      expect(second, first, reason: '光标透明度恒定（静态呈现）');

      // drain：让流式跑完避免 Timer pending。
      await tester.pump(const Duration(seconds: 1));
      await env.close();
    });

    testWidgets('disableAnimations=false（常态）→ 既有闪烁行为不变', (tester) async {
      final env = await ChatTestEnv.create();
      final controller = env.controllerOf(
        TickingFakeLLMProvider(
          tokens: const ['早', '上', '好', '啊', '这', '条', '长'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await controller.loadEntry();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await controller.openConversation(conv.id);
      await pumpChat(tester, controller, enableAnimations: true);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      expect(find.text('▍'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.binding.transientCallbackCount,
          greaterThan(0), reason: '常态下存在 repeat 动画（闪烁进行中）');
      await tester.pump(const Duration(seconds: 1));
      await env.close();
    });

    testWidgets('同挂载 disableAnimations true→false 翻转：静态 ▍ → 恢复闪烁（zone 零未处理异常）',
        (tester) async {
      final env = await ChatTestEnv.create();
      final controller = env.controllerOf(
        TickingFakeLLMProvider(
          tokens: const ['早', '上', '好', '啊', '这', '条', '长'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await controller.loadEntry();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await controller.openConversation(conv.id);
      await pumpChat(tester, controller, enableAnimations: false);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      expect(find.text('▍'), findsOneWidget, reason: 'reduce-motion 下光标静态呈现');

      // 同挂载翻转 true→false：re-pump 同一棵树（State 保留），仅媒体设定改变。
      await pumpChat(tester, controller, enableAnimations: true);
      expect(find.text('▍'), findsOneWidget, reason: '翻转后流式占位光标仍在');

      // 翻转后 repeat 恢复 → 闪烁进行中（_appliedOnce 守卫不吞掉真实翻转）。
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: '翻转后存在 repeat 动画（闪烁恢复）');
      expect(tester.takeException(), isNull,
          reason: '翻转路径 zone 零未处理异常（无 Ticker 泄漏 / 无 setState 风暴）');

      // drain：让流式跑完避免 Timer pending。
      await tester.pump(const Duration(seconds: 1));
      await env.close();
    });

    testWidgets('翻转恢复闪烁同一帧：光标 opacity 保持连续（不闪断一帧）', (tester) async {
      final env = await ChatTestEnv.create();
      final controller = env.controllerOf(
        TickingFakeLLMProvider(
          tokens: const ['早', '上', '好', '啊', '这', '条', '长'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await controller.loadEntry();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await controller.openConversation(conv.id);
      await pumpChat(tester, controller, enableAnimations: false);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      expect(find.text('▍'), findsOneWidget);

      // 静态帧 opacity：reduce-motion 下 controller.value=1.0 → 完全不透明。
      final staticOpacity = cursorOpacity(tester);
      expect(staticOpacity, moreOrLessEquals(1.0),
          reason: '静态呈现为全不透明（占位宽度稳定基线）');

      // 同挂载翻转 reduce→正常；不额外推进动画时间，直接断言翻转帧本身：
      // opacity 须保持连续（从全不透明起步，不先掉到暗帧再恢复）。
      await pumpChat(tester, controller, enableAnimations: true);
      expect(find.text('▍'), findsOneWidget);
      final flipFrameOpacity = cursorOpacity(tester);
      expect(flipFrameOpacity, moreOrLessEquals(staticOpacity),
          reason: '翻转同一帧光标 opacity 保持连续（不闪断一帧）');

      // 翻转后持续闪烁（且不卡在静态全不透明）。
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: '翻转后 repeat 恢复（闪烁持续进行）');
      expect(tester.takeException(), isNull);

      // drain：让流式跑完避免 Timer pending。
      await tester.pump(const Duration(seconds: 1));
      await env.close();
    });
  });
}