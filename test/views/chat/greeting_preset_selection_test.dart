/// 新建对话选择 UI 行为契约（NPD-03 验收 4/6/7）。
///
/// 界面语义（spec §4.5 + 工单 NPD-03 验收 4）：点「新建对话」→ 弹出选择面板
/// （开场白下拉 + 预设对话下拉）→ 「开始对话」确认建会话并直达：
/// - 开场白下拉 = 「默认」（first_mes，标「默认」）+ alternate_greetings 各项
///   + 「无开场白」；选项 → greeting 参数映射正确（默认→null、备选→文本、
///   无→空串）；
/// - 预设对话下拉 = 「不使用」+ 各预设名；选择 → 该预设 content 作为
///   presetDialogue 快照固化；
/// - 角色删除/不存在（选择时角色已消失）→ 既有 notice 路径（验收 6）；
/// - 既有调用方零回归（验收 7）：角色页「开始对话」经 createConversationFor
///   不传新参数（first_mes 预插）；选择面板默认即「默认开场白 + 不使用预设」
///   ——确认行为与旧「新建对话」完全一致。
///
/// 测试 seam（公共接口边界）：ChatEntry 公开交互 + ChatController 可观察状态
/// + 落库结果（[ConversationRepository.getConversation]）。经内存库 +
/// InMemorySecretStore + FakeLLMProvider 驱动真实 ChatService。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart';
import '../../helpers/fake_llm_provider.dart';
import '../../helpers/pump_until.dart';

void main() {
  Future<void> pumpChat(WidgetTester tester, ChatController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: ChatView(controller: controller)),
      ),
    );
    await tester.pump();
  }

  /// 以完整 companion（含 alternateGreetings / presetDialogues）种子角色。
  Future<Character> seedRichCharacter(
    ChatTestEnv env, {
    required String name,
    String firstMes = '',
    List<String> alternateGreetings = const [],
    List<Map<String, String>> presetDialogues = const [],
  }) {
    return env.characterRepository.createCharacter(
      CharactersCompanion(
        name: Value(name),
        firstMes: Value(firstMes),
        alternateGreetings: Value(alternateGreetings),
        presetDialogues: Value(presetDialogues),
      ),
    );
  }

  /// 打开新建对话选择面板（点「新建对话」）。
  Future<void> openSelectionSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('new-conversation')));
    await tester.pumpAndSettle();
  }

  group('新建对话选择面板 · 开场白选项（NPD-03 验收 4）', () {
    testWidgets('点「新建对话」→ 弹出选择面板（开场白下拉 + 预设下拉 + 开始按钮）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(env, name: '艾莉亚', firstMes: '默认问候。');
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);

      expect(find.byKey(const Key('new-conversation-sheet')), findsOneWidget,
          reason: '新建对话先弹选择面板而非直接建会话');
      expect(find.text('开场白'), findsOneWidget);
      expect(find.text('预设对话'), findsOneWidget);
      expect(find.byKey(const Key('start-conversation')), findsOneWidget);
      await env.close();
    });

    testWidgets('开场白下拉含「默认」标 first_mes + alternate_greetings 各项 + 「无开场白」',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(
        env,
        name: '艾莉亚',
        firstMes: '默认问候{{user}}。',
        alternateGreetings: const ['备选一', '备选二'],
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);
      await tester.tap(find.byKey(const Key('greeting-select')));
      await tester.pumpAndSettle();

      expect(find.text('默认（默认问候{{user}}。）'), findsWidgets,
          reason: '默认选项标注 first_mes 内容（按钮选中值 + 菜单项各一）');
      expect(find.text('备选一'), findsWidgets);
      expect(find.text('备选二'), findsWidgets);
      expect(find.text('无开场白'), findsWidgets);
      await env.close();
    });

    testWidgets('选「无开场白」+ 开始对话 → greeting 空串：会话无开场白（消息为空）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(
        env,
        name: '艾莉亚',
        firstMes: '默认问候。',
        alternateGreetings: const ['备选一'],
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);
      await tester.tap(find.byKey(const Key('greeting-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('无开场白'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-conversation')));
      await pumpUntil(tester, () => !c.isEntry, why: '确认后进入新会话');

      expect(c.activeConversationId, isNotNull);
      expect(c.messages, isEmpty, reason: 'greeting 显式空串 → 零预插');
      await env.close();
    });

    testWidgets('选备选开场白 + 开始对话 → greeting=该文本预插（模板替换）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(
        env,
        name: '夜莺',
        firstMes: '默认问候。',
        alternateGreetings: const ['{{user}}，这是{{char}}的备选开场。'],
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);
      await tester.tap(find.byKey(const Key('greeting-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('{{user}}，这是{{char}}的备选开场。'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-conversation')));
      await pumpUntil(tester, () => !c.isEntry, why: '确认后进入新会话');

      expect(
        c.messages.map((m) => (m.role, m.content)),
        [(Role.assistant, 'User，这是夜莺的备选开场。')],
        reason: '备选文本经模板替换预插为开场白',
      );
      await env.close();
    });

    testWidgets('选「默认」+ 开始对话 → greeting null：first_mes 预插（零回归）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(
        env,
        name: '艾莉亚',
        firstMes: '你好，{{user}}。',
        alternateGreetings: const ['备选一'],
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);
      // 默认即「默认开场白」选中，无需切换；直接确认。
      await tester.tap(find.byKey(const Key('start-conversation')));
      await pumpUntil(tester, () => !c.isEntry, why: '确认后进入新会话');

      expect(
        c.messages.map((m) => (m.role, m.content)),
        [(Role.assistant, '你好，User。')],
        reason: '默认选项 = greeting null → first_mes 模板替换预插（零回归）',
      );
      await env.close();
    });
  });

  group('新建对话选择面板 · 预设对话选择（NPD-03 验收 4）', () {
    testWidgets('预设下拉含「不使用」+ 各预设名；选预设 → presetDialogue 快照固化',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(
        env,
        name: '艾莉亚',
        presetDialogues: const [
          {'name': '咖啡厅', 'content': '<START>\n{{user}}: 你好\n{{char}}: 欢迎'},
          {'name': '雨天', 'content': '<START>\n{{user}}: 下雨了\n{{char}}: 嗯'},
        ],
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);
      await tester.tap(find.byKey(const Key('preset-select')));
      await tester.pumpAndSettle();

      expect(find.text('不使用'), findsWidgets);
      expect(find.text('咖啡厅'), findsWidgets);
      expect(find.text('雨天'), findsWidgets);

      await tester.tap(find.text('咖啡厅'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-conversation')));
      await pumpUntil(tester, () => !c.isEntry, why: '确认后进入新会话');

      final stored = await env.conversationRepository
          .getConversation(c.activeConversationId!);
      expect(stored!.presetDialogue, '<START>\n{{user}}: 你好\n{{char}}: 欢迎',
          reason: '选中预设的 content 固化为快照');
      await env.close();
    });

    testWidgets('预设选「不使用」+ 开始对话 → presetDialogue null（快照空）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(
        env,
        name: '艾莉亚',
        presetDialogues: const [
          {'name': '咖啡厅', 'content': '快照A'},
        ],
        firstMes: '你好。',
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);
      await tester.tap(find.byKey(const Key('start-conversation')));
      await pumpUntil(tester, () => !c.isEntry, why: '确认后进入新会话');

      final stored = await env.conversationRepository
          .getConversation(c.activeConversationId!);
      expect(stored!.presetDialogue, isNull, reason: '不使用 → 快照列不落伪值');
      await env.close();
    });
  });

  group('新建对话选择面板 · guard 与既有调用方零回归（NPD-03 验收 6/7）', () {
    testWidgets('无角色 → 新建按钮禁用（既有 U-1 语义），不弹面板', (tester) async {
      final env = await ChatTestEnv.create();
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '新建对话'),
      );
      expect(button.onPressed, isNull, reason: '无角色禁用新建');
      await tester.ensureVisible(find.text('请先在角色页创建角色'));
      expect(find.text('请先在角色页创建角色'), findsOneWidget);
      await env.close();
    });

    testWidgets('选中角色在打开面板后不存在 → 确认走既有 notice 路径（验收 6）',
        (tester) async {
      final env = await ChatTestEnv.create();
      final char = await seedRichCharacter(env, name: '艾莉亚', firstMes: '你好。');
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      await openSelectionSheet(tester);
      // 面板打开期间角色被删（进入选择 UI 后角色消失场景；controller 选中态
      // 未过期，真实删除路径还伴随 invalidateEntryCache——此处等价模拟）。
      await env.characterRepository.deleteCharacter(char.id);
      await tester.tap(find.byKey(const Key('start-conversation')));
      await tester.pumpAndSettle();

      expect(c.isEntry, isTrue, reason: '角色不存在 → 停留入口');
      expect(c.notice, contains('角色不存在或已删除'));
      expect(await env.conversationRepository.listConversations(), isEmpty,
          reason: '失败路径不残留会话');
      await env.close();
    });

    testWidgets('面板默认选择 = 默认开场白 + 不使用预设：确认后消息/快照与旧「新建对话」一致',
        (tester) async {
      final env = await ChatTestEnv.create();
      await seedRichCharacter(
        env,
        name: '艾莉亚',
        firstMes: '你好，{{user}}。',
        alternateGreetings: const ['备选一'],
        presetDialogues: const [
          {'name': '咖啡厅', 'content': '快照A'},
        ],
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      // 对照组：角色页「开始对话」= createConversationFor 不传新参数（验收 7）。
      final direct = env.controllerOf(FakeLLMProvider(tokens: const []));
      await direct.loadEntry();
      await direct.createConversationFor(
          (await env.characterRepository.listCharacters()).single.character.id);
      expect(
        direct.messages.map((m) => (m.role, m.content)),
        [(Role.assistant, '你好，User。')],
        reason: '角色页开始对话零回归：first_mes 预插',
      );

      // 实验组：选择面板默认确认 → 与对照组结果一致。
      await openSelectionSheet(tester);
      await tester.tap(find.byKey(const Key('start-conversation')));
      await pumpUntil(tester, () => !c.isEntry, why: '确认后进入新会话');

      expect(
        c.messages.map((m) => (m.role, m.content)),
        [(Role.assistant, '你好，User。')],
        reason: '面板默认确认与旧「新建对话」可观察结果一致',
      );
      expect(
        (await env.conversationRepository.getConversation(c.activeConversationId!))
            ?.presetDialogue,
        isNull,
      );
      await env.close();
    });
  });
}