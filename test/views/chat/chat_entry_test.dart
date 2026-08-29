/// 最小临时会话入口 widget 契约（T04b 切片）。
///
/// 入口面（锚：spec ID-2「最小临时会话入口：最近对话列表（listConversations）+
/// 『新建对话』（取首个角色，无角色禁用并提示）+ 界面标注『临时』」）：
/// - 标题「聊天」+「临时」标注（M3 替换的占位语义，best-judgment ② 细化）；
/// - 最近对话列表：标题 + 消息数，tap 进会话；
/// - 「新建对话」：有角色可点并进入新会话（渲染预插开场白）；无角色禁用 +
///   提示「请先在角色页创建角色」；无会话空态。
///
/// 测试 seam（公共接口边界）：ChatView / ChatEntry 公开接口 + ChatController
/// 可观察状态（isEntry / activeConversationId / conversations）。经内存库 +
/// InMemorySecretStore + FakeLLMProvider 驱动真实 ChatService（不 mock 服务层）。
///
/// 环境形态同 chat_view_test：每测试体自建 env + 测试体内 inline close
/// （tearDown 阶段在 FakeAsync 边界可能挂起——实证）。
library;

import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart';
import '../../helpers/fake_llm_provider.dart';

void main() {
  /// pump ChatView（入口或对话态由 controller.isEntry 决定）。
  Future<void> pumpChat(WidgetTester tester, ChatController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: ChatView(controller: controller)),
      ),
    );
    await tester.pump();
  }

  /// 循环 pump 直至 [condition] 为真（真实异步落库 / 回合收尾）。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String why = '',
  }) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: why);
  }

  ChatController entryController(ChatTestEnv env, LLMProvider provider) =>
      env.controllerOf(provider);

  group('入口 · 临时标注与新建按钮', () {
    testWidgets('标题「聊天」+「临时」标注 +「新建对话」+ 无会话空态', (tester) async {
      final env = await ChatTestEnv.create();
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      expect(find.text('聊天'), findsOneWidget);
      expect(find.text('临时'), findsOneWidget);
      expect(find.text('新建对话'), findsOneWidget);
      expect(find.text('还没有对话'), findsOneWidget);
      await env.close();
    });

    testWidgets('无角色 → 新建按钮禁用 + 提示「请先在角色页创建角色」', (tester) async {
      final env = await ChatTestEnv.create();
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '新建对话'));
      expect(button.onPressed, isNull, reason: '无角色禁用新建');
      expect(find.text('请先在角色页创建角色'), findsOneWidget);
      expect(c.notice, isNull, reason: '禁用提示是 UI 文案，非错误 notice');
      await env.close();
    });
  });

  group('入口 · 最近对话列表', () {
    testWidgets('渲染会话标题 + 消息数；tap 进会话显示输入框', (tester) async {
      final env = await ChatTestEnv.create();
      // 角色无开场白 → 会话创建不预插，手动 seed 1 条消息保证计数精确。
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await env.seedMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '开场。',
      );
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      expect(find.text('与 艾莉亚 的对话'), findsOneWidget);
      expect(find.text('1 条消息'), findsOneWidget);

      await tester.tap(find.text('与 艾莉亚 的对话'));
      await tester.pump();
      await tester.pump();

      expect(c.isEntry, isFalse);
      expect(c.activeConversationId, conv.id);
      expect(find.byType(TextField), findsOneWidget,
          reason: '进入会话 → 对话面板渲染输入框');
      await env.close();
    });

    testWidgets('新建对话 → 进入会话并渲染预插开场白', (tester) async {
      final env = await ChatTestEnv.create();
      await env.seedCharacter(firstMes: '你好，{{user}}。');
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await tester.tap(find.text('新建对话'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(c.isEntry, isFalse);
      expect(c.activeConversationId, isNotNull);
      expect(find.text('你好，User。', findRichText: true), findsOneWidget,
          reason: '会话创建预插开场白（{{user}} 已替换）');
      await env.close();
    });

    testWidgets('空会话列表 → 空态文案；列表随入口刷新随会话更新', (tester) async {
      final env = await ChatTestEnv.create();
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);
      expect(find.text('还没有对话'), findsOneWidget);

      // 会话更新（updated_at 前移）后回入口刷新 → 仍渲染列表。
      final char = await env.seedCharacter();
      await env.seedConversation(char.id);
      await c.backToEntry(); // loadEntry 幂等刷新（含 backToEntry）
      await pumpUntil(tester, () => c.conversations.isNotEmpty,
          why: 'backToEntry 刷新后会话进入列表');
      await tester.pump();
      expect(find.text('与 艾莉亚 的对话'), findsOneWidget);
      await env.close();
    });
  });
}