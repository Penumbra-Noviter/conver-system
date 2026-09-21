/// Prompt Debug 只读面板 + 聊天页入口（PD-04，验收 6/7/8 视图面）。
///
/// 覆盖：
/// - 面板：顶部角色名/模型/prompt_mode；每段 role 徽标 + 来源色标（单一映射
///   表）；content 等宽预排版保留换行；空 segments 空态提示；关闭即弃（无
///   编辑入口）；
/// - 来源枚举非法值 → 默认样式不抛错（防御，验收 7）；
/// - 入口：对话态顶栏出现「Prompt 调试」按钮，点按经 ChatService.promptDebug
///   （只读）拉取结果弹面板；入口页（无会话）不出现该按钮。
library;

import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/prompt.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:conver_system_mobile/views/chat/prompt_debug_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../helpers/chat_test_env.dart';
import '../../helpers/fake_llm_provider.dart';
import '../../helpers/pump_until.dart';

void main() {
  Future<void> pumpSheet(WidgetTester tester, PromptDebugResult result) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: PromptDebugSheet(result: result)),
      ),
    );
    await tester.pump();
  }

  PromptDebugResult resultWith(List<PromptSegment> segments) => PromptDebugResult(
        characterName: '艾莉亚',
        model: 'claude/claude-sonnet-5',
        promptMode: 'simple',
        segments: segments,
      );

  group('PromptDebugSheet · 只读面板', () {
    testWidgets('顶部角色名/模型/prompt_mode + role 徽标 + 来源色标 + 等宽 content',
        (tester) async {
      await pumpSheet(
        tester,
        resultWith([
          (role: 'system', content: '你是艾莉亚，月下剑客。', source: sourceCharacter),
          (
            role: 'user',
            content: '第一行\n第二行',
            source: sourceUser,
          ),
          (
            role: 'assistant',
            content: '[世界知识]\n剑是身份的象征',
            source: sourceWorld,
          ),
        ]),
      );

      expect(find.text('艾莉亚'), findsOneWidget);
      expect(find.text('模型 claude/claude-sonnet-5 · prompt_mode simple'),
          findsOneWidget);
      // role 徽标。
      expect(find.text('system'), findsOneWidget);
      expect(find.text('user'), findsOneWidget);
      expect(find.text('assistant'), findsOneWidget);
      // 来源色标标签（单一映射表出中文标签）。
      expect(find.text('角色'), findsOneWidget);
      expect(find.text('世界书'), findsOneWidget);
      // 等宽预排版保留换行（content 两行）。
      expect(find.text('第一行\n第二行'), findsOneWidget,
          reason: 'content 保留换行，等宽预排版');
    });

    testWidgets('空 segments → 空态提示（不崩）', (tester) async {
      await pumpSheet(tester, resultWith(const []));
      expect(find.text('暂无分段可展示'), findsOneWidget);
      expect(find.text('艾莉亚'), findsOneWidget, reason: '顶部元数据仍展示');
    });

    testWidgets('来源枚举非法值 → 默认样式不抛错（防御，验收 7）', (tester) async {
      await pumpSheet(
        tester,
        resultWith([
          (role: 'system', content: '未知来源段', source: 'bogus-source'),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('未知'), findsOneWidget, reason: '非法来源回落默认标签');
      expect(find.text('未知来源段'), findsOneWidget);
    });

    testWidgets('关闭即弃、无编辑入口：无 TextField / 无保存类按钮，关闭按钮 pop',
        (tester) async {
      await pumpSheet(
        tester,
        resultWith([
          (role: 'system', content: '内容', source: sourceCharacter),
        ]),
      );
      expect(find.byType(TextField), findsNothing, reason: '只读面板无编辑入口');
      expect(find.text('保存'), findsNothing);
      // 关闭按钮存在（关闭即弃）。
      expect(find.byKey(const Key('prompt-debug-close')), findsOneWidget);
      await tester.tap(find.byKey(const Key('prompt-debug-close')));
      await tester.pump();
      // Sheet 页面无卸载表现（非 route 栈）——只断言按钮仍可移除面板无从谈起，
      // 改为验证点按不抛错（防御）。
      expect(tester.takeException(), isNull);
    });
  });

  group('聊天页入口 + 面板导航', () {
    Future<(ChatTestEnv, ChatController, ChatService, FakeLLMProvider)>
        openConversationWith(
      WidgetTester tester,
      FakeLLMProvider provider,
    ) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter(
        name: '艾莉亚',
        firstMes: '',
      );
      final conv = await env.seedConversation(char.id);
      await env.messageRepository.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '问1',
      );
      final service = ChatService(
        lorebookRepository: env.lorebookRepository,
        conversationRepository: env.conversationRepository,
        characterRepository: env.characterRepository,
        messageRepository: env.messageRepository,
        settingsRepository: env.settingsRepository,
        providerFactory: FixedLLMProviderFactory(provider),
      );
      final controller = ChatController(
        chatService: service,
        conversationRepository: env.conversationRepository,
        characterRepository: env.characterRepository,
        messageRepository: env.messageRepository,
      );
      await controller.loadEntry();
      await controller.openConversation(conv.id);
      await tester.pumpWidget(
        Provider<ChatService>.value(
          value: service,
          child: MaterialApp(
            theme: ConverTheme.dark(),
            home: Scaffold(body: ChatView(controller: controller)),
          ),
        ),
      );
      await tester.pump();
      return (env, controller, service, provider);
    }

    testWidgets('对话态顶栏出现「Prompt 调试」入口，点按 → 开面板（只读，零 LLM）',
        (tester) async {
      final provider = FakeLLMProvider(tokens: const ['回复']);
      final (env, controller, service, llm) =
          await openConversationWith(tester, provider);
      expect(find.byKey(const Key('prompt-debug-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('prompt-debug-button')));
      await pumpUntil(
        tester,
        () => find.byType(PromptDebugSheet).evaluate().isNotEmpty,
        why: '点按 Prompt 调试 → 面板弹出',
      );

      // 面板展示真实组装结果：system(角色来源) + 顶部元数据。
      expect(find.byType(PromptDebugSheet), findsOneWidget);
      expect(find.text('艾莉亚'), findsWidgets, reason: '顶部角色名');
      expect(find.text('角色'), findsWidgets, reason: '来源色标');
      // SR-31 只读：面板打开全程零 LLM 调用、零落库、零外发。
      expect(llm.generateCallCount, 0, reason: '零 LLM（generate）');
      expect(llm.streamGenerateCallCount, 0, reason: '零 LLM（stream）');
      expect(controller.activeConversation, isNotNull);
      // history/user 来源段可能在 ListView 折叠区外 → 滚动定位后断言
      // （懒构建 ListView 只挂载视口内条目）。
      final listFinder = find.descendant(
        of: find.byType(PromptDebugSheet),
        matching: find.byType(ListView),
      );
      await tester.scrollUntilVisible(
        find.text('历史'),
        80,
        scrollable: find.descendant(
          of: find.byType(PromptDebugSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('历史'), findsWidgets, reason: '世界书/历史来源色标');
      await tester.scrollUntilVisible(
        find.text('用户'),
        80,
        scrollable: find.descendant(
          of: find.byType(PromptDebugSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('用户'), findsWidgets, reason: 'user 来源色标');
      expect(listFinder, findsOneWidget);

      await tester.tap(find.byKey(const Key('prompt-debug-close')));
      // 关闭即弃：等退场动画完成后面板从树中移除；对话态不受影响
      // （无编辑入口、无持久化）。
      await pumpUntil(
        tester,
        () => find.byType(PromptDebugSheet).evaluate().isEmpty,
        why: '关闭即弃：面板退场移除',
      );
      expect(controller.activeConversation, isNotNull,
          reason: '关闭面板不影响对话态');
      await env.close();
    });

    testWidgets('入口页（无会话）不出现「Prompt 调试」入口', (tester) async {
      final env = await ChatTestEnv.create();
      final service = ChatService(
        lorebookRepository: env.lorebookRepository,
        conversationRepository: env.conversationRepository,
        characterRepository: env.characterRepository,
        messageRepository: env.messageRepository,
        settingsRepository: env.settingsRepository,
        providerFactory: FixedLLMProviderFactory(FakeLLMProvider()),
      );
      final controller = ChatController(
        chatService: service,
        conversationRepository: env.conversationRepository,
        characterRepository: env.characterRepository,
        messageRepository: env.messageRepository,
      );
      await controller.loadEntry();
      await tester.pumpWidget(
        Provider<ChatService>.value(
          value: service,
          child: MaterialApp(
            theme: ConverTheme.dark(),
            home: Scaffold(body: ChatView(controller: controller)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('prompt-debug-button')), findsNothing);
      await env.close();
    });
  });
}