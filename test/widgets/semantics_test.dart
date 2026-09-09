/// a11y widget 语义断言（M6-10）——把无障碍从「走查看」变成「测试顶」。
///
/// 锁定 Issue 03 语义覆盖 / 05 reduce-motion 的产物（spec §4.4 语义覆盖清单
/// ①~④ / 共识 4.5）：气泡 label / 光标与装饰图标排除 / 卡片 button 语义 /
/// tooltip 语义 / reduce-motion 光标静态。纯测试票：零产品代码变更
/// （lib/** 只读，diff 仅含 test/ 下文件），断言失败即产品语义回退。
///
/// 语义树观测（SemanticsTester）：
/// - `find.bySemanticsLabel` 匹配语义 label；`tester.getSemantics` 取某
///   finder 对应（向上融合后）语义节点，读 `getSemanticsData()` 的
///   `tooltip` / `flagsCollection` / `actions`；
/// - tooltip 在语义树中呈现为 `SemanticsData.tooltip`（非 label 字段）——
///   验收 5 的「tooltip 语义 label」断言按此读取（这正是屏幕阅读器朗读的
///   tooltip 资产；`find.bySemanticsLabel` 不会命中 tooltip）；
/// - 「hasTapAction」= `actions` 含 `SemanticsAction.tap`；角色卡常态（非
///   多选）tap 语义接线为空（点击无动作）→ 不宣告 button（F-59 守卫对齐
///   游戏卡 `simulators_view._GameCard`，`button: onOpen != null`
///   同构守卫：tap 有效才宣告）；hint「长按可多选」常态保持；多选态
///   isButton + tap action + hint（M6-03 既有契约，见 characters_view_test）。
library;

import 'dart:io';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/character_card.dart';
import 'package:conver_system_mobile/services/character_file_exchange.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/simulator/manifest_parser.dart';
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart';
import 'package:conver_system_mobile/services/simulator/simulator_server.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/view_models/simulators_controller.dart';
import 'package:conver_system_mobile/views/characters/characters_controller.dart';
import 'package:conver_system_mobile/views/characters/characters_view.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:conver_system_mobile/views/settings/api_config_section.dart';
import 'package:conver_system_mobile/views/simulators/simulators_hooks.dart';
import 'package:conver_system_mobile/views/simulators/simulators_view.dart';
import 'package:conver_system_mobile/widgets/empty_state.dart';
import 'package:conver_system_mobile/widgets/notice_banner.dart';
import 'package:conver_system_mobile/widgets/status_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_env.dart';
import '../helpers/fake_llm_provider.dart';
import '../helpers/in_memory_secret_store.dart';

void main() {
  // ─────────────────────────── 通用断言 helper ───────────────────────────

  /// 取 [finder] 对应（向上融合后）语义节点的 tooltip 字段（验收 5 锚）。
  String? semanticsTooltipOf(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData().tooltip;

  /// 语义节点数据（flags / actions / label / hint 全量读取）。
  SemanticsData semanticsDataOf(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData();

  // ─────────────────────────── 聊天装配（复用 chat_test_env）──────────

  Future<void> pumpChat(WidgetTester tester, ChatController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: ChatView(controller: controller)),
      ),
    );
    await tester.pump();
  }

  /// 循环 pump 直至 [condition] 为真（真实异步落库 / 回合 / 流完成）。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String why = '',
  }) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: why);
  }

  /// 种子角色 + 会话并打开；返回控制器。
  Future<ChatController> openSeededConversation(
    WidgetTester tester,
    ChatTestEnv env,
    LLMProvider provider, {
    String name = '艾莉亚',
    List<(Role, String)> messages = const [],
  }) async {
    final char = await env.seedCharacter(name: name);
    final conv = await env.seedConversation(char.id);
    for (final (role, content) in messages) {
      await env.seedMessage(
        conversationId: conv.id,
        role: role,
        content: content,
      );
    }
    final c = env.controllerOf(provider);
    await c.loadEntry();
    await c.openConversation(conv.id);
    await pumpChat(tester, c);
    return c;
  }

  /// 经 UI 发送一条消息（输入框 + 发送按钮）。
  Future<void> sendViaUi(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
  }

  // ─────────────────────────── 角色列表装配（内联本文件）───────────────
  late AppDatabase charsDb;
  late CharacterRepository charRepo;
  late ConversationRepository convRepo;
  late MessageRepository msgRepo;
  late ChatController chatController;
  late CharactersController charsController;

  Future<void> setupChars(WidgetTester tester, {String name = '诺克斯'}) async {
    charsDb = AppDatabase(NativeDatabase.memory());
    charRepo = CharacterRepository(charsDb);
    convRepo = ConversationRepository(charsDb, const _FakeSettingsReader());
    msgRepo = MessageRepository(charsDb);
    chatController = ChatController(
      chatService: ChatService(
        database: charsDb,
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: msgRepo,
        settingsRepository: SettingsRepository(
          database: charsDb,
          secretStore: InMemorySecretStore(),
        ),
        providerFactory:
            FixedLLMProviderFactory(FakeLLMProvider(tokens: const [])),
      ),
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: msgRepo,
    );
    charsController = CharactersController(
      characterRepository: charRepo,
      fileExchange: _NoopExchange(),
      navigation: ShellNavigation(),
      chatController: chatController,
    );
    await charRepo.createCharacter(
      CharactersCompanion.insert(
        name: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: CharactersView(controller: charsController)),
      ),
    );
    for (var i = 0; i < 100 && charsController.loading; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
  }

  Future<void> closeChars() => charsDb.close();

  // ─────────────────────────── 模拟器装配（setUp 真实异步区）────────────
  late Directory simParent;
  late SimulatorDataDir simDataDir;
  late _ManifestFake simManifest;
  SimulatorsController? simController;

  setUp(() async {
    simParent = await Directory.systemTemp.createTemp('m6-10-sem-sim-');
    simDataDir = SimulatorDataDir(resolveDocumentsDir: () async => simParent);
    simManifest = _ManifestFake(
      result: parseManifest(
        '{"version":2,"simulators":[{"id":"g","file":"g.html",'
        '"name":"人生模拟器 v3","type":"ai","description":"AI 模拟"}]}',
      ),
    );
  });

  tearDown(() async {
    simController?.dispose();
    simController = null;
    await simParent.delete(recursive: true);
  });

  /// 挂载 SimulatorsView 并 pump 至 ready（hooks 注入 onOpen 接线）。
  Future<void> mountReadySims(
    WidgetTester tester,
    SimulatorsHooks hooks,
  ) async {
    simController = SimulatorsController(
      dataDir: simDataDir,
      seed: (_) async => false,
      createServer: (dir) => _StubServer(),
      loadManifest: simManifest.call,
      port: 0,
      hooks: hooks,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: SimulatorsView(controller: simController!),
      ),
    );
    for (var i = 0;
        i < 200 && simController!.state == SimulatorsState.loading;
        i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
  }

  // ─────────────────────────── 验收 1：气泡语义 label ───────────────────

  group('气泡语义 label（验收 1）', () {
    testWidgets('user 气泡「你: 内容」经 find.bySemanticsLabel 命中', (tester) async {
      final env = await ChatTestEnv.create();
      await openSeededConversation(
        tester,
        env,
        FakeLLMProvider(tokens: const []),
        messages: [(Role.user, '早上好')],
      );

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('你: 早上好'), findsOneWidget,
          reason: 'user 气泡 label「你: 内容」（前缀锚「你: 」+ 内容包含）');
      handle.dispose();
      await env.close();
    });

    testWidgets('assistant 气泡「<角色名>: 内容」经 find.bySemanticsLabel 命中',
        (tester) async {
      final env = await ChatTestEnv.create();
      await openSeededConversation(
        tester,
        env,
        FakeLLMProvider(tokens: const []),
        messages: [
          (Role.user, 'hi'),
          (Role.assistant, '早上好！'),
        ],
      );

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('艾莉亚: 早上好！'), findsOneWidget,
          reason: 'assistant 气泡 label「角色名: 内容」（角色名取当前会话角色）');
      handle.dispose();
      await env.close();
    });

    testWidgets('空角色名回退：「角色: 内容」（角色解析空/缺失不抛错）', (tester) async {
      final env = await ChatTestEnv.create();
      await openSeededConversation(
        tester,
        env,
        FakeLLMProvider(tokens: const []),
        name: '   ',
        messages: [
          (Role.user, 'hi'),
          (Role.assistant, '回复'),
        ],
      );

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('角色: 回复'), findsOneWidget,
          reason: '空角色名回退占位词「角色」（trim 后空 → 回退，不抛错不出现空白前缀）');
      handle.dispose();
      await env.close();
    });
  });

  // ─────────────────────────── 验收 2：光标排除 ─────────────────────────

  group('▍光标语义排除（验收 2）', () {
    testWidgets('streaming 占位气泡含「▍」但语义树无「▍」节点', (tester) async {
      final env = await ChatTestEnv.create();
      await openSeededConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['早', '上'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await sendViaUi(tester, 'hi');
      await tester.pump(const Duration(milliseconds: 11));

      // ▍ 光标存在于 widget 树。
      expect(find.text('▍'), findsOneWidget,
          reason: 'streaming 占位气泡含单点光标');

      final handle = tester.ensureSemantics();
      // 语义树无「▍」label（ExcludeSemantics 生效，spec §4.4 覆盖清单 ②）。
      expect(find.bySemanticsLabel('▍'), findsNothing,
          reason: '▍ 光标被 ExcludeSemantics 排除，不产生朗读噪音');
      expect(
        find.bySemanticsLabel(RegExp('▍')),
        findsNothing,
        reason: '任何 label 字符串均不含 ▍（含气泡合并 label 亦排除光标）',
      );
      // 结构性锚：光标 Text 确被 ExcludeSemantics 包裹（rollback 光标级
      // 排除 → 本断言红；与 label 级断言互补灵敏度）。
      expect(
        find.descendant(
          of: find.byType(ExcludeSemantics),
          matching: find.text('▍'),
        ),
        findsOneWidget,
        reason: '▍ 光标被 ExcludeSemantics 包裹（光标级语义排除）',
      );
      handle.dispose();

      // drain：让流式跑完（防 dispose 时 Timer pending）。
      await pumpUntil(
        tester,
        () => find.text('▍').evaluate().isEmpty,
        why: '光标随流式结束消失',
      );
      await env.close();
    });
  });

  // ─────────────────────────── 验收 3：装饰图标排除 ─────────────────────

  group('装饰图标语义排除（验收 3）', () {
    testWidgets('EmptyState 装饰图标被 ExcludeSemantics 排除，文案在语义树可读',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(
            body: Center(
              child: EmptyState(
                icon: Icons.person_outline,
                message: '暂无角色',
                hint: '点「新建角色」创建你的第一个角色',
              ),
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();

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
      final glyph = String.fromCharCode(Icons.person_outline.codePoint);
      expect(find.bySemanticsLabel(glyph), findsNothing,
          reason: '图标字形不以 label 形式进入语义树');
      handle.dispose();
    });

    testWidgets('StatusView 装饰图标被 ExcludeSemantics 排除，标题/原因在语义树可读',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(
            body: Center(
              child: StatusView(
                icon: Icons.error_outline,
                title: '游戏加载失败',
                message: '原因文案',
              ),
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();

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
      final glyph = String.fromCharCode(Icons.error_outline.codePoint);
      expect(find.bySemanticsLabel(glyph), findsNothing,
          reason: '图标字形不以 label 形式进入语义树');
      handle.dispose();
    });
  });

  // ─────────────────────────── 验收 4：卡片 button 语义 ─────────────────

  group('卡片 button 语义（验收 4）', () {
    testWidgets(
        '角色卡常态：不宣告 button + 长按多选 hint + 长按 action（F-59 守卫）',
        (tester) async {
      await setupChars(tester);
      final handle = tester.ensureSemantics();
      final data = semanticsDataOf(tester, find.text('诺克斯'));

      // F-59：常态（非多选）tap 无效 → 对齐游戏卡 button 守卫不宣告按钮。
      expect(data.flagsCollection.isButton, isFalse,
          reason: '常态非多选 tap 为 null，不宣告 button（F-59 守卫对齐）');
      expect(data.hint, contains('长按可多选'),
          reason: '长按多选 hint 在语义树');
      expect(data.actions & SemanticsAction.longPress.index != 0, isTrue,
          reason: '长按 action 存在（常态主交互 = 长按进入多选）');
      handle.dispose();
      await closeChars();
    });

    testWidgets('多选态：tap 接线 → hasTapAction，button + hint 保留', (tester) async {
      await setupChars(tester);
      await tester.longPress(find.text('诺克斯'));
      await tester.pump();
      expect(charsController.selectionMode, isTrue,
          reason: '长按进入多选（场景前提）');

      final handle = tester.ensureSemantics();
      final data = semanticsDataOf(tester, find.text('诺克斯'));
      expect(data.flagsCollection.isButton, isTrue,
          reason: '多选态仍为 button 语义');
      expect(data.hint, contains('长按可多选'), reason: 'hint 在多选态保留');
      expect(data.actions & SemanticsAction.tap.index != 0, isTrue,
          reason: '多选态 tap 勾选 → hasTapAction true');
      handle.dispose();
      await closeChars();
    });

    testWidgets('游戏卡 Semantics(button) + hasTapAction（onOpen 接线）',
        (tester) async {
      // temp dir 须在 setUp（真实异步区）创建——fake async 内建目录会挂起
      // （对齐 simulators_view_test 形态）。
      await mountReadySims(tester, const _OnOpenHooks());

      final handle = tester.ensureSemantics();
      final data = semanticsDataOf(tester, find.text('人生模拟器 v3'));
      expect(data.flagsCollection.isButton, isTrue,
          reason: '游戏卡 button 语义（Semantics(button) 生效）');
      expect(data.actions & SemanticsAction.tap.index != 0, isTrue,
          reason: 'onOpen 接线 → hasTapAction（点击可打开）');
      handle.dispose();
    });
  });

  // ─────────────────────────── 验收 5：tooltip 语义 ─────────────────────

  group('IconButton tooltip 语义（验收 5）', () {
    testWidgets('聊天锚：返回 / 重生成 / 导出对话 / 发送 tooltip 在语义数据',
        (tester) async {
      final env = await ChatTestEnv.create();
      // 种子仅 [user, assistant] 且 assistant 已结算（末条）→ 重生成可点。
      await openSeededConversation(
        tester,
        env,
        FakeLLMProvider(tokens: const []),
        messages: [
          (Role.user, '问题'),
          (Role.assistant, '旧回复'),
        ],
      );
      final handle = tester.ensureSemantics();

      expect(semanticsTooltipOf(tester, find.byIcon(Icons.arrow_back)), '返回',
          reason: '顶栏返回按钮 tooltip（tooltip 即语义 label 资产）');
      expect(semanticsTooltipOf(tester, find.byIcon(Icons.refresh)), '重生成',
          reason: '末条已结算 assistant → 重生成 IconButton tooltip');
      expect(semanticsTooltipOf(tester, find.byIcon(Icons.more_vert)), '导出对话',
          reason: '顶栏导出菜单（⋯）tooltip');
      expect(semanticsTooltipOf(tester, find.byIcon(Icons.send)), '发送',
          reason: '发送按钮 tooltip（非 streaming 态）');
      handle.dispose();
      await env.close();
    });

    testWidgets('聊天锚：streaming 态发送 ↔ 停止两态 tooltip 切换', (tester) async {
      final env = await ChatTestEnv.create();
      final streaming = TickingFakeLLMProvider(
        tokens: const ['早', '上', '好'],
        delay: const Duration(milliseconds: 10),
      );
      await openSeededConversation(tester, env, streaming);

      final handle = tester.ensureSemantics();
      expect(semanticsTooltipOf(tester, find.byIcon(Icons.send)), '发送',
          reason: '生成前为发送');
      handle.dispose();

      await sendViaUi(tester, 'hi');
      await tester.pump(const Duration(milliseconds: 11));

      final handle2 = tester.ensureSemantics();
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(semanticsTooltipOf(tester, find.byIcon(Icons.stop)), '停止',
          reason: '生成中发送↔停止两态：tooltip 随状态切换');
      handle2.dispose();

      // drain：让流式跑完（防 dispose 时 Timer pending）。
      await pumpUntil(
        tester,
        () => find.text('▍').evaluate().isEmpty,
        why: '流式完成',
      );
      await env.close();
    });

    testWidgets('角色卡锚：导入角色卡 / 编辑 / 导出 / 删除 tooltip 在语义数据',
        (tester) async {
      await setupChars(tester);
      final handle = tester.ensureSemantics();

      expect(semanticsTooltipOf(tester, find.byIcon(Icons.file_open_outlined)),
          '导入角色卡',
          reason: '角色页头部导入入口 tooltip');
      expect(
        semanticsTooltipOf(tester, find.byIcon(Icons.edit_outlined)),
        '编辑',
        reason: '角色卡编辑按钮 tooltip',
      );
      expect(
        semanticsTooltipOf(tester, find.byIcon(Icons.file_download_outlined)),
        '导出',
        reason: '角色卡导出按钮 tooltip',
      );
      expect(semanticsTooltipOf(tester, find.byIcon(Icons.delete_outline)),
          '删除',
          reason: '角色卡删除按钮 tooltip');
      handle.dispose();
      await closeChars();
    });

    testWidgets('NoticeBanner 关闭按钮 tooltip「关闭提示」在语义数据', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(
            body: NoticeBanner(notice: '回复已中断', onDismiss: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 141));
      await tester.pump();
      final handle = tester.ensureSemantics();

      expect(semanticsTooltipOf(tester, find.byIcon(Icons.close)), '关闭提示',
          reason: 'NoticeBanner 关闭按钮 tooltip（T3 共享组件，M6-03 tooltip 审计产物）');
      handle.dispose();
    });

    testWidgets('api_config 密钥可见性按钮 tooltip 动态切换：显示密钥 ↔ 隐藏密钥',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(
            body: ApiConfigSection(
              settingsRepository:
                  SettingsRepository(database: db, secretStore: InMemorySecretStore()),
              secretStore: InMemorySecretStore(),
              providerFactory:
                  FixedLLMProviderFactory(FakeLLMProvider(tokens: const [])),
              initialValues: const <String, String>{},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();

      // 每 provider 一个密钥可见性按钮（claude/openai 双槽位）：锚定 claude
      // 槽位（api-key-claude 输入框内 suffixIcon）。
      Finder claudeVisibilityIcon() => find.descendant(
            of: find.byKey(const ValueKey('api-key-claude')),
            matching: find.byIcon(Icons.visibility_outlined),
          );

      // 初始不可见 →「显示密钥」。
      expect(claudeVisibilityIcon(), findsOneWidget);
      expect(semanticsTooltipOf(tester, claudeVisibilityIcon()), '显示密钥',
          reason: '初始 tooltip「显示密钥」（M6-03 审计补齐的 tooltip）');

      // 点击 → 可见 →「隐藏密钥」。
      await tester.tap(claudeVisibilityIcon());
      await tester.pumpAndSettle();
      final claudeHiddenIcon = find.descendant(
        of: find.byKey(const ValueKey('api-key-claude')),
        matching: find.byIcon(Icons.visibility_off_outlined),
      );
      expect(claudeHiddenIcon, findsOneWidget);
      expect(semanticsTooltipOf(tester, claudeHiddenIcon), '隐藏密钥',
          reason: 'tooltip 随可见性状态切换「隐藏密钥」');
      handle.dispose();
    });
  });

  // ─────────────────────────── 验收 6：reduce-motion ────────────────────

  group('reduce-motion 光标静态（验收 6）', () {
    testWidgets('disableAnimations=true → 光标 FadeTransition 透明度恒定（静态呈现）',
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
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(body: ChatView(controller: controller)),
        ),
      );
      await tester.pump();

      await sendViaUi(tester, 'hi');
      expect(find.text('▍'), findsOneWidget, reason: '光标静态呈现（不隐藏）');

      double opacityAt() {
        final cursor = find.text('▍', findRichText: true);
        final inner = find
            .ancestor(of: cursor, matching: find.byType(FadeTransition))
            .evaluate()
            .first;
        return tester.widget<FadeTransition>(
          find.byElementPredicate((e) => e == inner),
        ).opacity.value;
      }

      final first = opacityAt();
      await tester.pump(const Duration(milliseconds: 20));
      final second = opacityAt();
      expect(second, first,
          reason: 'reduce-motion 下光标透明度恒定（无进行中 repeat 动画）');

      // drain：让流式跑完（防 dispose 时 Timer pending）。
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await env.close();
    });
  });
}

// ─────────────────────────── 支撑类型（仅本文件用）───────────────────────

/// 角色列表 env 用的无操作文件交换 seam（CharacterFileExchange 契约）。
class _NoopExchange implements CharacterFileExchange {
  @override
  Future<String> exportCharacter(Character character) async => 'x';

  @override
  Future<CharacterDraft?> importCharacter() async => null;
}

class _FakeSettingsReader implements SettingsReader {
  const _FakeSettingsReader();

  @override
  Future<String> get defaultProvider async => '';

  @override
  Future<String> get defaultModel async => '';

  @override
  Future<String> get userName async => '';
}

class _ManifestFake {
  _ManifestFake({required this.result});

  ManifestParseResult result;

  Future<ManifestParseResult> call(int port) async => result;
}

class _StubServer extends SimulatorServer {
  _StubServer() : super(Directory.systemTemp);

  bool _running = false;

  @override
  Future<int> start({required int port}) async {
    _running = true;
    return 8642;
  }

  @override
  Future<void> stop() async {}

  @override
  bool get isRunning => _running;
}

/// 游戏卡 onOpen 接线（验收 4 前提：可点 → hasTapAction）。
class _OnOpenHooks extends SimulatorsHooks {
  const _OnOpenHooks();

  @override
  void Function(SimulatorGame game)? get onOpen => (game) {};
}