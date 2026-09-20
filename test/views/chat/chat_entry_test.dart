/// 聊天首页角色选择与会话管理 widget 契约（U-1 工单 01）。
///
/// 入口面（锚：spec U-1 + 工单 01 验收标准 7 条）：
/// - 标题「聊天」（无「临时」标注、无「后续里程碑替换」副标题文案）；
/// - 角色选择条：横向渲染全部角色名，tap 切换选中态（选中高亮）；
/// - 「新建对话」以选中角色建会话并直达；无角色禁用 + 提示「请先在角色页创建角色」；
/// - 长按会话列表项弹出「重命名 / 删除」菜单；重命名/删除经控制器落库并刷新；
/// - 最近对话列表：标题 + 消息数，tap 进会话。
///
/// 测试 seam（公共接口边界）：ChatView / ChatEntry 公开接口 + ChatController
/// 可观察状态。经内存库 + InMemorySecretStore + FakeLLMProvider 驱动真实
/// ChatService（不 mock 服务层）。
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
import '../../helpers/pump_until.dart';

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

  ChatController entryController(ChatTestEnv env, LLMProvider provider) =>
      env.controllerOf(provider);

  group('入口 · 角色选择条与新建按钮', () {
    testWidgets('标题「聊天」（无临时标注/无副标题文案）+「新建对话」+ 无会话空态', (tester) async {
      final env = await ChatTestEnv.create();
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      expect(find.text('聊天'), findsOneWidget);
      expect(find.text('临时'), findsNothing);
      expect(find.textContaining('后续里程碑替换'), findsNothing);
      expect(find.text('新建对话'), findsOneWidget);
      expect(find.text('还没有对话'), findsOneWidget);
      await env.close();
    });

    testWidgets('无角色 → 新建按钮禁用 + 提示「请先在角色页创建角色」', (tester) async {
      final env = await ChatTestEnv.create();
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '新建对话'),
      );
      expect(button.onPressed, isNull, reason: '无角色禁用新建');
      expect(find.text('请先在角色页创建角色'), findsOneWidget);
      expect(c.notice, isNull, reason: '禁用提示是 UI 文案，非错误 notice');
      await env.close();
    });

    testWidgets('角色选择条渲染全部角色名 + 默认选中首角色 + tap 切换高亮', (tester) async {
      final env = await ChatTestEnv.create();
      final first = await env.seedCharacter(name: '艾莉亚');
      final second = await env.seedCharacter(name: '白露');
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      // F-136 加固：角色列表异步加载完成（selectedCharacterId 定值）再断言
      // 默认选中首角色——pumpChat 仅 pump 一帧，加载未完成时该值仍是未定
      // 态（F-106 id ASC 修复后列表序稳定，残余窗口只留在加载时序）。
      await pumpUntil(
        tester,
        () => c.selectedCharacterId == first.id,
        why: '角色列表加载未在轮询窗口内完成（默认选中首角色）',
      );

      expect(find.text('艾莉亚'), findsOneWidget);
      expect(find.text('白露'), findsOneWidget);
      expect(c.selectedCharacterId, first.id, reason: '默认选中首角色');
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(Key('character-chip-${first.id}')))
            .selected,
        isTrue,
        reason: '首角色 chip 高亮',
      );

      await tester.tap(find.byKey(Key('character-chip-${second.id}')));
      await tester.pump();

      expect(c.selectedCharacterId, second.id);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(Key('character-chip-${second.id}')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(Key('character-chip-${first.id}')))
            .selected,
        isFalse,
      );
      await env.close();
    });

    testWidgets('新建对话以选中角色建会话（非首角色）', (tester) async {
      final env = await ChatTestEnv.create();
      await env.seedCharacter(name: '艾莉亚');
      final target = await env.seedCharacter(
        name: '白露',
        firstMes: '你好，{{user}}。',
      );
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await tester.tap(find.byKey(Key('character-chip-${target.id}')));
      await tester.pump();
      expect(c.selectedCharacterId, target.id);

      // NPD-03：新建对话先弹选择面板（默认=默认开场白+不使用预设），确认建会话。
      await tester.tap(find.text('新建对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-conversation')));
      await pumpUntil(tester, () => !c.isEntry, why: '进入新会话');

      expect(
        c.activeConversation?.characterId,
        target.id,
        reason: '会话归属选中角色而非首角色',
      );
      expect(
        find.text('你好，User。', findRichText: true),
        findsOneWidget,
        reason: '选中角色开场白经模板替换预插',
      );
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
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: '进入会话 → 对话面板渲染输入框',
      );
      await env.close();
    });

    testWidgets('新建对话 → 进入会话并渲染预插开场白', (tester) async {
      final env = await ChatTestEnv.create();
      await env.seedCharacter(firstMes: '你好，{{user}}。');
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await tester.tap(find.text('新建对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-conversation')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(c.isEntry, isFalse);
      expect(c.activeConversationId, isNotNull);
      expect(
        find.text('你好，User。', findRichText: true),
        findsOneWidget,
        reason: '会话创建预插开场白（{{user}} 已替换）',
      );
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
      await pumpUntil(
        tester,
        () => c.conversations.isNotEmpty,
        why: 'backToEntry 刷新后会话进入列表',
      );
      await tester.pump();
      expect(find.text('与 艾莉亚 的对话'), findsOneWidget);
      await env.close();
    });
  });

  group('入口 · 长按会话管理（重命名 / 删除）', () {
    testWidgets('长按会话 → 弹出「重命名 / 删除」菜单', (tester) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter();
      await env.seedConversation(char.id);
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await tester.longPress(find.text('与 艾莉亚 的对话'));
      await tester.pumpAndSettle();

      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      await env.close();
    });

    testWidgets('重命名流程 → 更新 DB 并刷新列表标题', (tester) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await tester.longPress(find.text('与 艾莉亚 的对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('rename-field')),
        findsOneWidget,
        reason: '重命名对话框预填输入框',
      );
      await tester.enterText(find.byKey(const Key('rename-field')), '我的新对话');
      await tester.tap(find.byKey(const Key('rename-confirm')));
      await pumpUntil(
        tester,
        () => c.conversations.any((e) => e.conversation.title == '我的新对话'),
        why: '重命名落库并刷新列表',
      );

      expect(
        (await env.conversationRepository.getConversation(conv.id))?.title,
        '我的新对话',
      );
      expect(find.widgetWithText(ListTile, '我的新对话'), findsOneWidget);
      await env.close();
    });

    testWidgets('删除流程 → 落库并刷新为空态', (tester) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await tester.longPress(find.text('与 艾莉亚 的对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('删除对话'), findsOneWidget, reason: '删除确认对话框');
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await pumpUntil(tester, () => c.conversations.isEmpty, why: '删除落库并刷新列表');

      expect(await env.conversationRepository.getConversation(conv.id), isNull);
      expect(find.text('还没有对话'), findsOneWidget);
      await env.close();
    });
  });

  group('入口 · 分支来源标记（BR-02 验收 3）', () {
    /// 种子角色 + 会话 + 首答；经真实分支服务生成分支会话（父/锚记录落库）；
    /// 返回源会话 id。
    Future<int> seedBranch(ChatTestEnv env) async {
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      final anchor = await env.seedMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '第一答',
      );
      final branch = env.branchServiceOf();
      await branch.branchFromMessage(conv.id, anchor.id, title: '雪夜分叉');
      return conv.id;
    }

    testWidgets('分支会话列表项显示「分支自「父标题」· 锚预览」（父会话存活）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedBranch(env);
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      // 父会话标题「与 艾莉亚 的对话」+ 锚消息「第一答」预览。
      expect(find.textContaining('分支自「与 艾莉亚 的对话」'), findsOneWidget,
          reason: 'parent 存活 → 显示父标题');
      expect(find.textContaining('第一答'), findsOneWidget,
          reason: '锚消息预览渲染于列表副标');
      expect(find.textContaining('分支自'), findsOneWidget,
          reason: '仅分支会话有标记（父/普通会话无）');
      expect(c.branchSources, isNotEmpty, reason: '控制器分支来源标记已加载');
      await env.close();
    });

    testWidgets('父会话删除后 → 分支列表项降级显示「分支（来源会话已删除）」',
        (tester) async {
      final env = await ChatTestEnv.create();
      final parentId = await seedBranch(env);
      // BR-01 删源置空策略：parent/锚置空、branchTitle 保留（D2 契约）。
      await env.conversationRepository.deleteConversation(parentId);
      final c = entryController(env, FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      expect(find.text('分支（来源会话已删除）'), findsOneWidget,
          reason: '父已删（引用置空）→ 按 branchTitle 降级「分支」标记');
      expect(find.textContaining('分支自'), findsNothing,
          reason: '父标题不可用，不再显示「分支自」');
      await env.close();
    });
  });
}
