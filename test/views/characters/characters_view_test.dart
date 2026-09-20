/// CharactersView widget 行为契约（M3-01 切片：角色 tab 卡片列表）。
///
/// 验收语义（工单 01 验收 1/2/3/5/7）：
/// - 单列卡片语义对齐桌面 `characterCardHtml`：头像（缺省首字占位）/ 名称 /
///   描述（空 → personality 前 60 字）/ 开场白前 60 字（超长「…」）/ 标签 /
///   温度（一位小数）/ 对话数徽标，排序 updated_at 倒序（仓储契约）；
/// - 空态「暂无角色」+ 创建引导；RefreshIndicator 下拉刷新重拉 + 切回 tab
///   自动刷新（controller 幂等，不重复闪烁）；
/// - 卡片四按钮：开始对话 / 编辑 / 导出 / 删除；删除确认文案含角色对话数；
/// - 导出经 [CharacterFileExchange] seam（注入 fake 断言调用链 + notice 文案，
///   永不触真平台通道）；编辑 push 表单并预填。
///
/// 测试 seam（公共接口边界）：[CharactersView] 公开接口 + [CharactersController]
/// 可观察状态 + 真实仓储（内存 drift）。装配基座内联于本文件
/// （重复 controller 测试内联装配，避免新增范围外 helper 文件）。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/character_card.dart';
import 'package:conver_system_mobile/services/character_file_exchange.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/document_parse_service.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/views/characters/characters_controller.dart';
import 'package:conver_system_mobile/views/characters/characters_view.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/widgets/notice_banner.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';
import '../../helpers/pump_until.dart';

/// [SettingsReader] 的内存假实现（与 chat 系测试同形）。
class FakeSettingsReader implements SettingsReader {
  const FakeSettingsReader([this.values = const {}]);

  final Map<String, String> values;

  @override
  Future<String> get defaultProvider async => values['default_provider'] ?? '';

  @override
  Future<String> get defaultModel async => values['default_model'] ?? '';

  @override
  Future<String> get userName async => values['user_name'] ?? '';

  @override
  Future<Map<String, String>> get templateVars async => const {};
}

/// 记录调用链 + 返回标注文案的 seam fake（同 controller 测试契约）。
class FakeCharacterFileExchange implements CharacterFileExchange {
  final List<Character> exported = <Character>[];

  @override
  Future<String> exportCharacter(Character character) async {
    exported.add(character);
    return '已导出 ${character.name}.json（角色导出随后续批次交付）';
  }

  @override
  Future<CharacterDraft?> importCharacter() async => null;
}

/// refresh 即抛错的控制器变体（探测 CharactersView._ensureLoaded 刷新失败
/// 防御分支：失败仅 debugPrint，保持缺省空列表）。
class _RefreshThrowingController extends CharactersController {
  _RefreshThrowingController({
    required super.characterRepository,
    required super.fileExchange,
    required super.navigation,
    required super.chatController,
  });

  @override
  Future<void> refresh() async {
    throw StateError('模拟刷新失败');
  }
}

/// 本文件的装配基座：内存 drift + 四仓储 + ChatController + 导航 + seam fake
/// + CharactersController。测试体内显式 close（对齐 chat_view_test 形态）。
class _CharsEnv {
  _CharsEnv({
    required this.db,
    required this.characterRepository,
    required this.conversationRepository,
    required this.messageRepository,
    required this.chatController,
    required this.navigation,
    required this.exchange,
    required this.controller,
  });

  final AppDatabase db;
  final CharacterRepository characterRepository;
  final ConversationRepository conversationRepository;
  final MessageRepository messageRepository;
  final ChatController chatController;
  final ShellNavigation navigation;
  final FakeCharacterFileExchange exchange;
  final CharactersController controller;

  static Future<_CharsEnv> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    final characterRepository = CharacterRepository(db);
    final conversationRepository =
        ConversationRepository(db, const FakeSettingsReader());
    final messageRepository = MessageRepository(db);
    final chatController = ChatController(
      chatService: ChatService(
        database: db,
        conversationRepository: conversationRepository,
        characterRepository: characterRepository,
        messageRepository: messageRepository,
        settingsRepository: SettingsRepository(
          database: db,
          secretStore: InMemorySecretStore(),
        ),
        providerFactory:
            FixedLLMProviderFactory(FakeLLMProvider(tokens: const ['ok'])),
      ),
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
    );
    final navigation = ShellNavigation();
    final exchange = FakeCharacterFileExchange();
    return _CharsEnv(
      db: db,
      characterRepository: characterRepository,
      conversationRepository: conversationRepository,
      messageRepository: messageRepository,
      chatController: chatController,
      navigation: navigation,
      exchange: exchange,
      controller: CharactersController(
        characterRepository: characterRepository,
        fileExchange: exchange,
        navigation: navigation,
        chatController: chatController,
      ),
    );
  }

  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String description = '',
    String personality = '',
    String firstMes = '',
    List<String> tags = const [],
    double temperature = 0.7,
    List<Map<String, String>> presetDialogues = const [],
    String promptMode = 'simple',
    String expertPrompt = '',
  }) {
    return characterRepository.createCharacter(
      CharactersCompanion(
        name: Value(name),
        description: Value(description),
        personality: Value(personality),
        firstMes: Value(firstMes),
        tags: Value(tags),
        temperature: Value(temperature),
        presetDialogues: Value(presetDialogues),
        promptMode: Value(promptMode),
        expertPrompt: Value(expertPrompt),
      ),
    );
  }

  Future<Conversation> seedConversation(int characterId) =>
      conversationRepository.createConversation(characterId: characterId);

  Future<void> close() => db.close();
}

void main() {

  Future<void> pumpChars(
    WidgetTester tester,
    _CharsEnv env,
    CharactersController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: CharactersView(controller: controller)),
      ),
    );
    // initState 后帧回调触发 refresh；循环 pump 到列表渲染完成。
    for (var i = 0; i < 100 && controller.loading; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
  }

  group('卡片字段 · 对齐桌面 characterCardHtml（验收 1）', () {
    testWidgets('渲染名称/描述/温度/对话数徽标/标签/首字头像', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '诺克斯',
        description: '冷峻的守夜人',
        tags: const ['刺客', '暗夜'],
        temperature: 0.75,
      );
      // 建一个对话使对话数徽标为 1（不保留变量：仅需落库副作用）。
      await env.seedConversation(
          (await env.characterRepository.listCharacters()).single.character.id);

      await pumpChars(tester, env, env.controller);

      expect(find.text('诺克斯'), findsOneWidget);
      expect(find.text('冷峻的守夜人'), findsOneWidget);
      expect(find.text('温度 0.8'), findsOneWidget, reason: '一位小数显示');
      expect(find.text('1 对话'), findsOneWidget, reason: '对话数徽标');
      expect(find.text('#刺客'), findsOneWidget);
      expect(find.text('#暗夜'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CircleAvatar),
          matching: find.text('诺'),
        ),
        findsOneWidget,
        reason: '缺省首字占位头像',
      );
      await env.close();
    });

    testWidgets('描述空 → personality 前 60 字兜底；开场白超 60 字截断加「…」',
        (tester) async {
      final env = await _CharsEnv.create();
      final longGreeting = '开' * 70;
      final longPersonality = '性' * 70;
      await env.seedCharacter(
        name: '话痨',
        description: '',
        personality: longPersonality,
        firstMes: longGreeting,
      );

      await pumpChars(tester, env, env.controller);

      // personality 前 60 字兜底。
      expect(find.text('${'性' * 60}…'), findsOneWidget,
          reason: '描述空 → personality 前 60 字 + 省略号');
      expect(find.text('${'开' * 60}…'), findsOneWidget,
          reason: '开场白前 60 字 + 省略号（超长截断）');
      await env.close();
    });
  });

  group('空态 · 暂无角色 + 创建引导（验收 2）', () {
    testWidgets('空库 → 空态文案 + 引导', (tester) async {
      final env = await _CharsEnv.create();

      await pumpChars(tester, env, env.controller);

      expect(find.text('暂无角色'), findsOneWidget);
      expect(find.textContaining('创建'), findsWidgets, reason: '创建引导存在');
      await env.close();
    });
  });

  group('四按钮 · 开始对话 / 编辑 / 导出 / 删除（验收 3/4/5/7）', () {
    testWidgets('卡片渲染四个操作，点开始对话切到聊天 tab 并直达新会话',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '开聊', firstMes: '你好，{{user}}。');

      await pumpChars(tester, env, env.controller);

      expect(find.byTooltip('编辑'), findsOneWidget);
      expect(find.byTooltip('导出'), findsOneWidget);
      expect(find.byTooltip('删除'), findsOneWidget);
      expect(find.text('开始对话'), findsOneWidget);

      await tester.tap(find.text('开始对话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();

      expect(env.navigation.current, ShellTab.chat);
      expect(env.chatController.isEntry, isFalse, reason: '直达新会话');
      expect(env.chatController.activeConversation, isNotNull);
      await env.close();
    });

    testWidgets('点导出 → 经 seam 调用并展示占位提示（never 触真通道）',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '导我');

      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('导出'));
      await tester.pump();
      await tester.pump();

      final exported = env.exchange.exported.first;
      expect(exported.name, '导我', reason: 'seam 收到该角色（调用链）');
      expect(find.textContaining('随后续批次交付'), findsOneWidget,
          reason: '占位提示文案展示');
      expect(find.textContaining('导我.json'), findsOneWidget,
          reason: '文件名构造语义出现在提示中');
      await env.close();
    });

    testWidgets('点删除 → 确认弹窗文案含对话数；确认后列表移除 + 级联入库',
        (tester) async {
      final env = await _CharsEnv.create();
      final char =
          await env.seedCharacter(name: '删除我', firstMes: '开场。');
      final conv = await env.seedConversation(char.id);
      await env.messageRepository.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '一条消息',
      );

      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();

      expect(find.textContaining('删除后其 1 个对话与消息将一并删除'),
          findsOneWidget, reason: '删除确认文案含对话数');
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();

      expect(env.controller.characters, isEmpty, reason: '删除后列表即时刷新');
      expect(await env.conversationRepository
              .listConversations(characterId: char.id),
          isEmpty, reason: '级联：对话消失');
      expect(await env.messageRepository.getMessages(conv.id), isEmpty,
          reason: '级联：消息消失');
      await env.close();
    });

    testWidgets('取消删除 → 零副作用（角色保留）', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '保留我');

      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(env.controller.characters, hasLength(1));
      expect(find.text('保留我'), findsOneWidget);
      await env.close();
    });
  });

  group('编辑 · 表单预填与保存（验收 4）', () {
    testWidgets('点编辑 → push 表单并预填角色字段；保存（部分更新）成功',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '原名',
        description: '旧描述',
        firstMes: '开场。',
      );

      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();

      // 表单预填（名称 / 描述 / 开场白）。
      expect(find.widgetWithText(TextField, '原名'), findsOneWidget);
      expect(find.widgetWithText(TextField, '旧描述'), findsOneWidget);
      expect(find.widgetWithText(TextField, '开场。'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      // 改名称后保存 → 列表反映更新，未表单字段（如 personality）不变。
      await tester.enterText(
        find.widgetWithText(TextField, '原名'),
        '新名',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      await pumpUntil(
        tester,
        () => find.text('新名').evaluate().isNotEmpty,
        why: '保存后列表刷新展示新名',
      );
      expect(env.controller.characters.single.character.name, '新名');
      expect(env.controller.characters.single.character.description, '旧描述');
      await env.close();
    });

    testWidgets('编辑表单清空名称 → 保存拦截（「角色名称不能为空」）', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '原名');

      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '原名'), '  ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('角色名称不能为空'), findsOneWidget);
      expect(env.controller.characters.single.character.name, '原名',
          reason: '拦截：零副作用');
      await env.close();
    });

    testWidgets('编辑表单点取消 → 零副作用（数据不变且回到列表）', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '原名', description: '旧描述');

      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '原名'), '改名');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(env.controller.characters.single.character.name, '原名',
          reason: '取消零副作用');
      expect(find.text('原名'), findsOneWidget, reason: '回到列表且展示原值');
      await env.close();
    });
  });

  group('编辑 · 预设对话列表（NPD-03 验收 5）', () {
    Future<void> openEdit(WidgetTester tester, _CharsEnv env) async {
      // 高画布：预设对话区位于表单下部，默认 800x600 视口下 ListView 懒构建
      // 不到该段（widget 不在树中即断言找不到）。拉高画布使其全部进入
      // cacheExtent。
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
    }

    /// 读取预设行字段文本（TextFormField 内层 TextField 的 controller 值）。
    String presetFieldText(WidgetTester tester, String key) {
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(TextField),
        ),
      );
      return field.controller!.text;
    }

    testWidgets('既有 presetDialogues 预填各行列（重开面板字段还原）', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '艾莉亚',
        presetDialogues: const [
          {'name': '寒暄', 'content': '你好，请问怎么称呼？'},
          {'name': '战斗', 'content': '准备好了吗{{user}}。'},
        ],
      );

      await openEdit(tester, env);

      expect(presetFieldText(tester, 'preset-name-0'), '寒暄',
          reason: '重开面板：第 0 行 name 字段还原');
      expect(presetFieldText(tester, 'preset-content-0'), '你好，请问怎么称呼？');
      expect(presetFieldText(tester, 'preset-name-1'), '战斗',
          reason: '重开面板：第 1 行字段还原');
      expect(presetFieldText(tester, 'preset-content-1'), '准备好了吗{{user}}。');
      await env.close();
    });

    testWidgets('增删行：添加行数 +1，删除行数 -1；保存 payload 含 presetDialogues 落库',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '艾莉亚',
        presetDialogues: const [
          {'name': '寒暄', 'content': '你好。'},
        ],
      );

      await openEdit(tester, env);
      expect(find.byKey(const Key('preset-name-0')), findsOneWidget);

      // 添加一行 → 两行；该项为零值，保存时被空项去重过滤。
      await tester.tap(find.byKey(const Key('preset-add')));
      await tester.pump();
      expect(find.byKey(const Key('preset-name-1')), findsOneWidget);

      // 删除新增空行 → 回一行；再删原行 → 零行。
      await tester.tap(find.byKey(const Key('preset-delete-1')));
      await tester.pump();
      expect(find.byKey(const Key('preset-name-1')), findsNothing);

      await tester.tap(find.byKey(const Key('preset-delete-0')));
      await tester.pump();
      expect(find.byKey(const Key('preset-name-0')), findsNothing);

      // 重新添加并填写 → 保存 payload 含该预设落库。
      await tester.tap(find.byKey(const Key('preset-add')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('preset-name-0')), '雨后');
      await tester.enterText(
          find.byKey(const Key('preset-content-0')), '雨停了，{{user}}。');

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final saved = env.controller.characters.single.character;
      expect(saved.presetDialogues, [
        {'name': '雨后', 'content': '雨停了，{{user}}。'},
      ]);
      await env.close();
    });

    testWidgets('上限 10：满行时添加按钮禁用（超出阻止）；删除后解除', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '艾莉亚',
        presetDialogues: [
          for (var i = 0; i < 10; i++)
            {'name': '预设$i', 'content': '内容$i'},
        ],
      );

      await openEdit(tester, env);

      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('preset-add')))
            .onPressed,
        isNull,
        reason: '已达上限 10：添加按钮禁用（超出阻止）',
      );

      // 删除一行 → 解除禁用，可继续添加。
      await tester.tap(find.byKey(const Key('preset-delete-9')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('preset-add')))
            .onPressed,
        isNotNull,
      );
      await env.close();
    });

    testWidgets('空项去重：name/content 任空过滤 + 同名保留首个 + conver_system 往返',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '艾莉亚',
        presetDialogues: const [
          {'name': '寒暄', 'content': '你好。'},
          {'name': '寒暄', 'content': '重复同名（应被保留首个去重）'},
          {'name': '  ', 'content': '空白名（应被过滤）'},
          {'name': '缺内容', 'content': '   '},
        ],
      );

      await openEdit(tester, env);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final saved = env.controller.characters.single.character;
      expect(saved.presetDialogues, [
        {'name': '寒暄', 'content': '你好。'},
      ], reason: '同名去重保留首个 + 空字段过滤');

      // conver_system 往返：toV2Card 读回同一列表。
      final ns = ((toV2Card(saved)['data']! as Map<String, dynamic>)['extensions']!
              as Map<String, dynamic>)['conver_system']!
          as Map<String, dynamic>;
      expect(ns['preset_dialogues'], [
        {'name': '寒暄', 'content': '你好。'},
      ]);
      await env.close();
    });
  });

  group('编辑 · 专家模式两态切换（NPD-04 验收 7）', () {
    Future<void> openEditTall(WidgetTester tester, _CharsEnv env) async {
      // 高画布：专家提示词 textarea 位于表单下部，默认 800x600 视口下
      // ListView 懒构建不到该段。拉高画布使其全部进入 cacheExtent。
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpChars(tester, env, env.controller);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
    }

    /// 读取专家提示词 textarea 文本（TextFormField 内层 TextField 的
    /// controller 值）。
    String expertPromptText(WidgetTester tester) {
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('expert-prompt-field')),
          matching: find.byType(TextField),
        ),
      );
      return field.controller!.text;
    }

    testWidgets('expert 角色打开编辑：专家态展示大 textarea（预填 expertPrompt）+ '
        '结构化字段灰显', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '专家',
        personality: '人设A',
        promptMode: 'expert',
        expertPrompt: '你是{{char}}，整段专家提示词。',
      );

      await openEditTall(tester, env);

      expect(
        expertPromptText(tester),
        '你是{{char}}，整段专家提示词。',
        reason: 'textarea 预填角色 expertPrompt',
      );
      final personality = tester.widget<TextFormField>(
        find.byKey(const Key('field-personality')),
      );
      expect(personality.enabled, isFalse, reason: '专家态结构化字段（人格）灰显');
      await env.close();
    });

    testWidgets('两态切换可逆：expert → simple 保留 expertPrompt；再切回 expert 还原', (
      tester,
    ) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '专家',
        personality: '人设A',
        promptMode: 'expert',
        expertPrompt: '保留这段提示词',
      );

      await openEditTall(tester, env);

      // 切到 simple：结构化字段恢复可编辑，expertPrompt 不丢（controller 态）。
      // 段按文本命中歧义（「专家模式」同时为小节标题），故限定在 SegmentedButton 内。
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('基础模式'),
        ),
      );
      await tester.pumpAndSettle();
      final personality = tester.widget<TextFormField>(
        find.byKey(const Key('field-personality')),
      );
      expect(personality.enabled, isTrue, reason: 'simple 态结构化字段恢复可编辑');

      // 再切回 expert：textarea 内容还原（可逆不丢）。
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('专家模式'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        expertPromptText(tester),
        '保留这段提示词',
        reason: 'expert → simple → expert 切换 expertPrompt 不丢',
      );
      await env.close();
    });

    testWidgets('专家态保存 payload 同时携带 prompt_mode + expert_prompt 落库', (
      tester,
    ) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '专家', personality: '人设A');

      await openEditTall(tester, env);
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('专家模式'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('expert-prompt-field')),
          matching: find.byType(TextField),
        ),
        '你是{{char}}，专家整段。',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      await pumpUntil(
        tester,
        () => env.controller.characters.single.character.promptMode == 'expert',
        why: '保存后列表刷新，角色 promptMode 为 expert',
      );
      final saved = env.controller.characters.single.character;
      expect(saved.promptMode, 'expert');
      expect(saved.expertPrompt, '你是{{char}}，专家整段。');
      await env.close();
    });

    testWidgets('expert → simple 保存：promptMode 回到 simple 且 expertPrompt '
        '保留（可逆不丢，落库仍携带）', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '专家',
        promptMode: 'expert',
        expertPrompt: '要保留的专家整段',
      );

      await openEditTall(tester, env);
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('基础模式'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      await pumpUntil(
        tester,
        () => env.controller.characters.single.character.promptMode == 'simple',
        why: '保存后列表刷新，角色 promptMode 为 simple',
      );
      final saved = env.controller.characters.single.character;
      expect(saved.promptMode, 'simple');
      expect(
        saved.expertPrompt,
        '要保留的专家整段',
        reason: 'expert → simple 保存 expertPrompt 不丢',
      );
      await env.close();
    });

    testWidgets('DB 脏模式值（非 simple/expert）→ 归一为基础模式并持久化回写'
        '（Falsify：非 expert 值收敛 simple，防 SegmentedButton 越集选中与脏值扩散）', (
      tester,
    ) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '脏模式',
        promptMode: 'weird',
        expertPrompt: '未知模式下的文本',
      );

      // 打开编辑页不崩；脏模式归一为基础模式（结构化字段可编辑、无 textarea）。
      await openEditTall(tester, env);
      expect(find.text('编辑角色'), findsOneWidget);
      final personality = tester.widget<TextFormField>(
        find.byKey(const Key('field-personality')),
      );
      expect(personality.enabled, isTrue, reason: 'weird 归一为 simple（结构化字段可编辑）');
      expect(
        find.byKey(const Key('expert-prompt-field')),
        findsNothing,
        reason: '非 expert 态不展示专家提示词 textarea',
      );

      // 保存后持久化归一：promptMode 回写 simple（非脏值扩散），expertPrompt
      // 保留（可逆不丢）。
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => env.controller.characters.single.character.promptMode == 'simple',
        why: '保存后列表刷新，脏模式被归一为 simple',
      );
      final saved = env.controller.characters.single.character;
      expect(saved.promptMode, 'simple', reason: '脏模式值回写 simple（归一收敛）');
      expect(saved.expertPrompt, '未知模式下的文本');
      await env.close();
    });
  });

  group('下拉刷新 · RefreshIndicator（验收 2）', () {
    testWidgets('下拉 → controller 重新拉取并展示新增角色', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '旧角色');

      await pumpChars(tester, env, env.controller);
      expect(find.text('旧角色'), findsOneWidget);

      // 数据源新增一个角色后下拉刷新。
      await env.seedCharacter(name: '新角色');
      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('新角色'), findsOneWidget, reason: '下拉刷新重新拉取');
      expect(find.text('旧角色'), findsOneWidget);
      await env.close();
    });
  });

  group('notice 身份 seq · F-65④（同文案新旧不误清）', () {
    testWidgets('NoticeBanner 收到控制器 noticeId（角色页 seq 接线：视图传 id）',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '导我');
      await pumpChars(tester, env, env.controller);

      await tester.tap(find.byTooltip('导出'));
      await tester.pump();
      await tester.pump();
      expect(env.controller.noticeId, isNotNull, reason: 'notice 置位即分配身份');

      final banner = tester.widget<NoticeBanner>(find.byType(NoticeBanner));
      expect(banner.noticeId, env.controller.noticeId,
          reason: 'characters_view 把控制器 noticeId 传给 NoticeBanner');
      await env.close();
    });

    testWidgets('④ 同文案新旧 notice：出口过渡窗口内同文案新 notice → 陈旧 dismiss'
        ' 不误清新 notice（notice 身份 seq end-to-end）', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '导我');
      await pumpChars(tester, env, env.controller);

      const notice = '已导出 导我.json（角色导出随后续批次交付）';
      // 第一次导出 → notice（fake seam 固定文案，id=1）。
      await tester.tap(find.byTooltip('导出'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('随后续批次交付'), findsOneWidget);
      final firstId = env.controller.noticeId;
      expect(firstId, isNotNull, reason: 'notice 置位即分配身份');

      // 点关闭 → 140ms 出口过渡开始（分步 pump，不 settle）。
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(env.controller.noticeId, firstId, reason: '过渡完成前身份不变');

      // 过渡窗口内同文案新 notice：再次导出 → 新 seq（同文案也分新身份）。
      final char = env.controller.characters.single.character;
      unawaited(env.controller.exportCharacter(char));
      for (var i = 0; i < 60 && env.controller.noticeId == firstId; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(env.controller.noticeId, isNot(firstId),
          reason: '窗口内同文案新 notice 分配新身份 seq');
      expect(env.controller.notice, notice);

      // 越过 140ms 计时 → 陈旧 dismiss（id1）不得误清新 notice（id2）。
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(env.controller.noticeId, isNot(firstId),
          reason: '新 notice 未被陈旧 dismiss 清掉');
      expect(env.controller.notice, notice,
          reason: '陈旧 dismiss 不误清新 notice');
      expect(find.textContaining('随后续批次交付'), findsOneWidget,
          reason: '新 notice 持续呈现');
      expect(tester.takeException(), isNull, reason: 'zone 零未处理异常');
    });
  });

  group('覆盖缺口补齐（F-67）', () {
    testWidgets('刷新抛错 → 仅 debugPrint 日志，保持缺省空列表（_ensureLoaded 防御）',
        (tester) async {
      final env = await _CharsEnv.create();
      final throwing = _RefreshThrowingController(
        characterRepository: env.characterRepository,
        fileExchange: env.exchange,
        navigation: env.navigation,
        chatController: env.chatController,
      );
      addTearDown(throwing.dispose);

      // 捕获 debugPrint 输出：临时替换全局钩子，断言后必须在本测试体内
      // 还原（flutter_test 的 foundation 不变量检查在 tearDown 前执行）。
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logs.add(message ?? '');
      };
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ConverTheme.dark(),
            home: Scaffold(body: CharactersView(controller: throwing)),
          ),
        );
        // initState 后帧回调触发 _ensureLoaded → refresh 抛错被捕获。
        for (var i = 0; i < 100 && throwing.loading; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump();
        await tester.pump();

        expect(
          logs.any((l) => l.contains('角色列表刷新失败')),
          isTrue,
          reason: '刷新失败折叠为 debugPrint（对齐 ChatView._ensureEntryLoaded）',
        );
        expect(find.text('暂无角色'), findsOneWidget,
            reason: '刷新失败保持缺省空列表');
      } finally {
        debugPrint = original;
      }
      await env.close();
    });

    testWidgets('点「新建角色」→ push 6 步向导（步骤①三卡片）', (tester) async {
      final env = await _CharsEnv.create();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            // 入口经 context.read<CharacterRepository>() 构造 WizardController；
            // M4-05 追加 SettingsRepository + LLMProviderFactory（装配
            // DocumentParseService）；C2 收敛后视图改 context.read 消费装配图
            // 的 DocumentParseService（本测试按 app.dart 同构图提供 provider）。
            Provider<CharacterRepository>.value(value: env.characterRepository),
            Provider<SettingsRepository>.value(
              value: SettingsRepository(
                database: env.db,
                secretStore: InMemorySecretStore(),
              ),
            ),
            Provider<LLMProviderFactory>.value(
              value:
                  FixedLLMProviderFactory(FakeLLMProvider(tokens: const ['ok'])),
            ),
            Provider<DocumentParseService>.value(
              value: DocumentParseService(
                settings: SettingsRepository(
                  database: env.db,
                  secretStore: InMemorySecretStore(),
                ),
                providerFactory:
                    FixedLLMProviderFactory(FakeLLMProvider(tokens: const ['ok'])),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ConverTheme.dark(),
            home: Scaffold(body: CharactersView(controller: env.controller)),
          ),
        ),
      );
      for (var i = 0; i < 100 && env.controller.loading; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();

      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();

      // 向导出现（步骤①）——M3-01 stub 已被真实导航替换。
      expect(find.text('智能导入'), findsOneWidget);
      expect(find.text('从模板开始'), findsOneWidget);
      expect(find.text('手动创建'), findsOneWidget);

      // 返回角色页（步骤①返回 = 退出向导）。
      await tester.tap(find.byTooltip('退出'));
      await tester.pumpAndSettle();
      expect(find.text('新建角色'), findsOneWidget, reason: '退出向导回列表页');
      await env.close();
    });

    testWidgets('多选态批量删除：确认对话框文案含选中数；取消零副作用；确认级联删除',
        (tester) async {
      final env = await _CharsEnv.create();
      final a = await env.seedCharacter(name: '阿甲');
      await env.seedCharacter(name: '阿乙');
      await env.seedConversation(a.id);

      await pumpChars(tester, env, env.controller);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();
      await tester.tap(find.text('阿乙'));
      await tester.pump();
      expect(find.text('已选 2 个角色'), findsOneWidget);

      await tester.tap(find.byTooltip('批量删除'));
      await tester.pumpAndSettle();

      expect(find.text('批量删除角色'), findsOneWidget, reason: '确认对话框标题');
      expect(
        find.textContaining('删除将移除 2 个角色及其对话与消息'),
        findsOneWidget,
        reason: '确认文案含选中数与级联说明',
      );

      // 取消 → 零副作用（角色保留、仍在多选态）。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(env.controller.characters, hasLength(2), reason: '取消零副作用');
      expect(env.controller.selectionMode, isTrue, reason: '取消后仍在多选态');

      // 确认 → 级联删除 + 列表刷新 + 退出多选。
      await tester.tap(find.byTooltip('批量删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => env.controller.characters.isEmpty,
        why: '批量删除后列表刷新为空',
      );
      expect(env.controller.selectionMode, isFalse, reason: '删除完成自动退出多选');
      expect(find.text('已选'), findsNothing, reason: '批量栏消失');
      expect(await env.conversationRepository
              .listConversations(characterId: a.id),
          isEmpty, reason: '级联：对话消失');
      await env.close();
    });

    testWidgets('多选态点勾选框 onChanged → 切换选中（toggleSelection 直连）',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '阿甲');

      await pumpChars(tester, env, env.controller);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();
      expect(env.controller.selection, hasLength(1), reason: '长按默认勾选');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(env.controller.selection, isEmpty, reason: '点勾选框取消勾选');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(env.controller.selection, hasLength(1), reason: '再点勾选框重新勾选');
      await env.close();
    });

    testWidgets(':351 多选态 tap 卡片 → toggleSelection（与勾选框同源直触）',
        (tester) async {
      final env = await _CharsEnv.create();
      final a = await env.seedCharacter(name: '阿甲');
      final b = await env.seedCharacter(name: '阿乙');

      await pumpChars(tester, env, env.controller);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();
      expect(env.controller.selection, {a.id}, reason: '长按默认勾选阿甲');

      // tap 阿乙卡片追加勾选。
      await tester.tap(find.text('阿乙'));
      await tester.pump();
      expect(env.controller.selection, {a.id, b.id}, reason: 'tap 追加勾选');

      // 退出多选后 tap 卡片应无效（onTap 为 null，F-59 守卫）。
      env.controller.exitSelectionMode();
      await tester.pump();
      await tester.tap(find.text('阿乙'));
      await tester.pump();
      expect(env.controller.selectionMode, isFalse);
      expect(env.controller.selection, isEmpty, reason: '非多选态 tap 零副作用');
      await env.close();
    });
  });

  group('语义覆盖（M6-03 验收 4）', () {
    testWidgets('常态：非多选角色卡不宣告按钮 + 长按多选 hint 保持（F-59 守卫）',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '诺克斯');

      await pumpChars(tester, env, env.controller);

      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.text('诺克斯'));
      // F-59：常态（非多选）tap 无效 → 对齐游戏卡 button 守卫不宣告按钮，
      // 避免 TalkBack 宣告可点实则不可点的卡片。
      expect(node.flagsCollection.isButton, isFalse,
          reason: '常态非多选 tap 为 null，不宣告 button（F-59 守卫对齐）');
      expect(
        node.hint,
        contains('长按可多选'),
        reason: '长按多选 hint 在语义树（卡片 hint）',
      );
      handle.dispose();
      await env.close();
    });

    testWidgets('多选态：勾选后 tap 语义保留 button + hint', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '诺克斯');

      await pumpChars(tester, env, env.controller);
      // 长按进入多选并勾选。
      await tester.longPress(find.text('诺克斯'));
      await tester.pump();

      expect(env.controller.selectionMode, isTrue, reason: '长按进入多选');
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.text('诺克斯'));
      expect(node.flagsCollection.isButton, isTrue,
          reason: '多选态 tap 切换勾选仍为 button 语义');
      expect(node.hint, contains('长按可多选'),
          reason: 'hint 在多选态保留');
      handle.dispose();
      await env.close();
    });

    testWidgets('退出多选态 → 回到不宣告按钮 + hint 保持（F-59 往返）',
        (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(name: '诺克斯');

      await pumpChars(tester, env, env.controller);
      // 长按进入多选 → tap 有效，宣告 button。
      await tester.longPress(find.text('诺克斯'));
      await tester.pump();
      expect(env.controller.selectionMode, isTrue, reason: '长按进入多选');

      // 退出多选态 → tap 恢复为 null，button 宣告撤销（守卫往返闭环）。
      env.controller.exitSelectionMode();
      await tester.pump();
      expect(env.controller.selectionMode, isFalse, reason: '退出多选');

      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.text('诺克斯'));
      expect(node.flagsCollection.isButton, isFalse,
          reason: '退出多选后 tap 为 null，撤销 button 宣告（F-59 往返）');
      expect(node.hint, contains('长按可多选'),
          reason: 'hint 退出多选后仍保留');
      handle.dispose();
      await env.close();
    });
  });

  group('1.3x 大字无溢出（M6-05 验收 4）', () {
    testWidgets('角色列表（长名称/长描述/长引导）1.3x 下 pump 无 overflow', (tester) async {
      final env = await _CharsEnv.create();
      await env.seedCharacter(
        name: '非常长的角色名称用于探测系统大字下卡片行的溢出边界',
        description: '很长的描述内容，用来在 1.3x 下检查描述区是否横向溢出，'
            '同时撑起足够的文本长度让换行与截断路径都能被触达。' * 3,
        firstMes: '开场白也写得比较长，确保卡片底部徽标行不溢出。' * 2,
        tags: const ['长标签一', '长标签二', '长标签三'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: Scaffold(body: CharactersView(controller: env.controller)),
        ),
      );
      for (var i = 0; i < 100 && env.controller.loading; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: '角色列表在 1.3x 下无 RenderFlex overflow');
      await env.close();
    });
  });

  group('世界书入口（WL-04 验收 1）', () {
    testWidgets('卡片存在世界书按钮；tap push LorebookEditorView', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final env = await _CharsEnv.create();
      await env.seedCharacter();
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: MultiProvider(
            providers: [
              Provider<LorebookRepository>(
                create: (_) => LorebookRepository(env.db),
              ),
            ],
            child: Scaffold(body: CharactersView(controller: env.controller)),
          ),
        ),
      );
      for (var i = 0; i < 100 && env.controller.loading; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: '360dp 下加世界书按钮后卡片按钮行无溢出');
      expect(find.byTooltip('世界书'), findsOneWidget);

      await tester.tap(find.byTooltip('世界书'));
      await tester.pumpAndSettle();

      expect(find.text('暂无世界书条目'), findsOneWidget,
          reason: 'push 世界书编辑器页');
      await env.close();
    });
  });
}