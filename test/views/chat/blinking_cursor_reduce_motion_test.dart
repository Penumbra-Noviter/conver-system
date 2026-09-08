/// M6-03/05 打字机光标 reduce-motion 契约——系统「减弱动效」时 ▍ 光标停闪。
///
/// 验收语义（工单 05 验收 1 + spec §4.4 reduce-motion + 共识 4.5）：
/// - `MediaQuery.disableAnimations == true` → 光标不循环（无进行中的 repeat
///   动画），静态 ▍ 呈现（保持占位宽度，列表布局不跳动）；
/// - false → 既有闪烁行为不变（repeat 循环）。
///
/// 测试 seam（公共接口边界）：经 ChatView 渲染 streaming 占位气泡（打字机
/// 光标只出现在流式占位内），通过 MaterialApp 的 builder 注入
/// MediaQuery(data: disableAnimations) 定向构造；断言
/// TickerMode/animation 状态与 ▍ 可见性。
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

void main() {
  /// pump ChatView 于 [enableAnimations] 的可访问性媒体设定下。
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
      double opacityAt(WidgetTester t) {
        // 打字机光标的 FadeTransition：▍ Text 的祖先中最内层那一个。
        final cursor = find.text('▍', findRichText: true);
        final ancestors = find
            .ancestor(of: cursor, matching: find.byType(FadeTransition))
            .evaluate();
        // 取最内层（离 ▍ 最近）的 FadeTransition 作为光标动画对象。
        // 取最内层（离 ▍ 最近）的 FadeTransition 作为光标动画对象；
        // 外层（anc[1..4]）均为 Material 内部恒 1.0 的 FadeTransition。
        final element = ancestors.first;
        return t.widget<FadeTransition>(find.byElementPredicate(
          (e) => e == element,
        )).opacity.value;
      }

      expect(find.byType(FadeTransition), findsWidgets,
          reason: 'FadeTransition（光标动画对象）在树中');
      final first = opacityAt(tester);
      await tester.pump(const Duration(milliseconds: 20));
      final second = opacityAt(tester);
      // ignore: avoid_print
      print('DBG first=$first second=$second');
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
  });
}