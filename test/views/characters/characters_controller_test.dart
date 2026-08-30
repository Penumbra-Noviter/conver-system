/// CharactersController 行为契约（M3-01 切片：列表 / 加载 / 编辑保存 / 单删 /
/// 导出占位 / 回入口）。
///
/// 测试 seam（公共接口边界）：[CharactersController] 公开 API（characters /
/// loading / notice / refresh / deleteCharacter / startConversation /
/// exportCharacter / saveCharacter）+ 真实仓储（内存 drift，复刻
/// chat_controller_test 的装配形状）+ 真实 ChatController（FakeLLMProvider）
/// + 注入 [CharacterFileExchange] fake（永不触真平台通道）。
///
/// 级联断言复用仓储契约：删除角色后其对话与消息经 FK CASCADE 同空
/// （character_repository_test.dart:172 同源语义）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/character_file_exchange.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/views/characters/characters_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（与 chat_controller_test 同形）。
class FakeSettingsReader implements SettingsReader {
  const FakeSettingsReader([this.values = const {}]);

  final Map<String, String> values;

  @override
  Future<String> get defaultProvider async => values['default_provider'] ?? '';

  @override
  Future<String> get defaultModel async => values['default_model'] ?? '';

  @override
  Future<String> get userName async => values['user_name'] ?? '';
}

/// listCharacters 必抛的角色仓储子类——命中「加载失败 → notice」路径。
class _ThrowingListCharactersRepository extends CharacterRepository {
  _ThrowingListCharactersRepository(super.db);

  @override
  Future<List<CharacterWithCount>> listCharacters() {
    throw StateError('list failed');
  }
}

/// exportCharacter 必抛的 seam fake——命中「导出失败 → notice 兜底」路径。
class _ThrowingExchange implements CharacterFileExchange {
  @override
  Future<String> exportCharacter(Character character) {
    throw StateError('export failed');
  }
}

/// 记录调用链 + 返回标注文案的 seam fake（断言经 seam 导出的调用链；
/// never 触真平台通道）。
class FakeCharacterFileExchange implements CharacterFileExchange {
  final List<Character> exported = <Character>[];

  @override
  Future<String> exportCharacter(Character character) async {
    exported.add(character);
    return '已导出 ${character.name}.json（角色导出随后续批次交付）';
  }
}

void main() {
  late AppDatabase db;
  late ConversationRepository convRepo;
  late MessageRepository messageRepo;
  late CharacterRepository charRepo;
  late ChatController chatController;
  late ShellNavigation navigation;
  late FakeCharacterFileExchange exchange;
  late CharactersController controller;

  // 固定起始时刻（drift 落库为 unix 秒）。
  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
  void advanceSeconds(int seconds) {
    fakeNow = fakeNow.add(Duration(seconds: seconds));
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    convRepo = ConversationRepository(db, const FakeSettingsReader(),
        now: () => fakeNow);
    messageRepo = MessageRepository(db, now: () => fakeNow);
    charRepo = CharacterRepository(db, now: () => fakeNow);
    final service = ChatService(
      database: db,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
      settingsRepository:
          SettingsRepository(database: db, secretStore: InMemorySecretStore()),
      providerFactory:
          FixedLLMProviderFactory(FakeLLMProvider(tokens: const ['ok'])),
    );
    chatController = ChatController(
      chatService: service,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
    );
    navigation = ShellNavigation();
    exchange = FakeCharacterFileExchange();
    controller = CharactersController(
      characterRepository: charRepo,
      fileExchange: exchange,
      navigation: navigation,
      chatController: chatController,
    );
  });

  tearDown(() async {
    controller.dispose();
    chatController.dispose();
    await db.close();
  });

  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
    int secondsAgo = 0,
  }) {
    advanceSeconds(secondsAgo);
    return charRepo.createCharacter(
      CharactersCompanion(
        name: Value(name),
        firstMes: Value(firstMes),
      ),
    );
  }

  Future<Conversation> seedConversation(int characterId) {
    return convRepo.createConversation(characterId: characterId);
  }

  Future<Message> seedMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) {
    return messageRepo.createMessage(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }

  group('refresh · 列表（排序 + 对话数 + 空态）', () {
    test('列表填充且按 updated_at 倒序、conversation_count 正确', () async {
      final older = await seedCharacter(name: '旧角色', secondsAgo: 10);
      await seedCharacter(name: '新角色', secondsAgo: 5);
      await seedConversation(older.id);

      await controller.refresh();

      expect(controller.hasLoaded, isTrue);
      expect(controller.loading, isFalse);
      expect(controller.characters.map((r) => r.character.name),
          ['新角色', '旧角色']);
      expect(controller.characters.map((r) => r.conversationCount), [0, 1]);
    });

    test('空库 → 空列表（empty 态）', () async {
      await controller.refresh();
      expect(controller.characters, isEmpty);
      expect(controller.notice, isNull);
    });

    test('落库失败 → notice，空列表复位（失败也算完成可重试）', () async {
      final throwing = _ThrowingListCharactersRepository(db);
      final broken = CharactersController(
        characterRepository: throwing,
        fileExchange: exchange,
        navigation: navigation,
        chatController: chatController,
      );

      await broken.refresh();

      expect(broken.notice, startsWith('加载角色失败'));
      expect(broken.characters, isEmpty);
      expect(broken.hasLoaded, isTrue);
      broken.dispose();
    });
  });

  group('deleteCharacter · 单删 + 级联', () {
    test('确认删除后列表移除 + 级联对话与消息全消失（FK CASCADE 实证）',
        () async {
      final char = await seedCharacter(name: '待删角色');
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: '你好');
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '你好呀');
      await controller.refresh();
      expect(controller.characters, hasLength(1));

      final deleted = await controller.deleteCharacter(char.id);

      expect(deleted, isTrue);
      expect(controller.characters, isEmpty, reason: '删除后列表即时刷新');
      expect(await convRepo.listConversations(characterId: char.id), isEmpty,
          reason: '角色名下对话经 FK CASCADE 消失');
      expect(await messageRepo.getMessages(conv.id), isEmpty,
          reason: '对话名下消息经 FK CASCADE 消失');
    });

    test('删除当前打开对话所属角色 → 聊天回入口（backToEntry 语义）', () async {
      final char = await seedCharacter(name: '开聊角色', firstMes: '开场。');
      final conv = await seedConversation(char.id);
      await chatController.openConversation(conv.id);
      expect(chatController.isEntry, isFalse);

      await controller.refresh();
      await controller.deleteCharacter(char.id);

      expect(chatController.isEntry, isTrue,
          reason: '当前正打开该角色会话 → 删除后回聊天入口');
      expect(controller.characters, isEmpty);
    });

    test('非本角色会话打开中 → 删除不回入口', () async {
      final charA = await seedCharacter(name: '甲');
      final charB = await seedCharacter(name: '乙', secondsAgo: 3);
      final convA = await seedConversation(charA.id);
      await chatController.openConversation(convA.id);

      await controller.refresh();
      await controller.deleteCharacter(charB.id);

      expect(chatController.isEntry, isFalse,
          reason: '打开的会话归属另一角色，不触发回入口');
      expect(controller.characters, hasLength(1));
    });

    test('角色不存在 → false 且零副作用 + notice', () async {
      await seedCharacter(name: '保留');
      await controller.refresh();

      final deleted = await controller.deleteCharacter(999999);

      expect(deleted, isFalse);
      expect(controller.characters, hasLength(1), reason: '零副作用');
      expect(controller.notice, contains('角色不存在'));
    });
  });

  group('startConversation · 开始对话（直达 chat tab）', () {
    test('切到聊天 tab 并以指定角色直达新会话（默认模型）', () async {
      final char = await seedCharacter(name: '目标角色', firstMes: '你好，{{user}}。');
      await controller.refresh();

      await controller.startConversation(char.id);

      expect(navigation.current, ShellTab.chat);
      expect(chatController.isEntry, isFalse);
      expect(chatController.activeConversation?.characterId, char.id);
      expect(
        chatController.messages.map((m) => (m.role, m.content)),
        [(Role.assistant, '你好，User。')],
        reason: '直达新会话并预插开场白（默认模型路径）',
      );
    });

    test('角色不存在 → notice，不残留会话', () async {
      await controller.refresh();

      await controller.startConversation(999999);

      expect(chatController.notice, contains('角色不存在'));
      expect(chatController.isEntry, isTrue);
      expect(await convRepo.listConversations(), isEmpty);
    });
  });

  group('exportCharacter · 导出 seam（本票占位）', () {
    test('经 seam 调用并展示返回文案（调用链可断言）', () async {
      final char = await seedCharacter(name: '导出我');
      await controller.refresh();

      await controller.exportCharacter(char);

      expect(exchange.exported.map((c) => c.id), [char.id],
          reason: '导出经 character_file_exchange seam 调用');
      expect(controller.notice, contains('随后续批次交付'),
          reason: 'stub/fake 返回文案展示为占位提示');
    });

    test('seam 抛错 → notice 兜底（异常/超时降级）', () async {
      final char = await seedCharacter(name: '失败导出');
      await controller.refresh();
      final failing = _ThrowingExchange();
      final broken = CharactersController(
        characterRepository: charRepo,
        fileExchange: failing,
        navigation: navigation,
        chatController: chatController,
      );

      await broken.exportCharacter(char);

      expect(broken.notice, startsWith('导出失败'));
      broken.dispose();
    });

    test('真实 CharacterFileExchangeStub → 占位文案（验收 7 语义）', () async {
      final char = await seedCharacter(name: '导我');
      await controller.refresh();
      final stubWired = CharactersController(
        characterRepository: charRepo,
        fileExchange: const CharacterFileExchangeStub(),
        navigation: navigation,
        chatController: chatController,
      );

      await stubWired.exportCharacter(char);

      expect(stubWired.notice, '角色导出（V2 JSON 卡）随后续批次交付',
          reason: '装配 Stub 时展示占位提示（随后续批次交付）');
      stubWired.dispose();
    });
  });

  group('dismissNotice · 关闭非阻塞提示', () {
    test('有 notice → 清除；无 notice → 零通知', () async {
      await controller.refresh();
      await controller.exportCharacter(await seedCharacter(name: 'x'));
      expect(controller.notice, isNotNull);

      controller.dismissNotice();
      expect(controller.notice, isNull);

      var notified = 0;
      controller.addListener(() => notified++);
      controller.dismissNotice(); // 无 notice：不重复通知
      expect(notified, 0);
    });
  });

  group('saveCharacter · 编辑保存（部分更新）', () {
    test('保存后列表反映更新，未显式字段不变', () async {
      final char = await seedCharacter(name: '原名', firstMes: '开场'); // firstMes 非空
      await controller.refresh();

      await controller.saveCharacter(
        char.id,
        const CharactersCompanion(description: Value('新描述')),
      );

      final row = controller.characters.single;
      expect(row.character.description, '新描述');
      expect(row.character.name, '原名', reason: '未显式提供的字段不变（部分更新）');
      expect(row.character.firstMes, '开场');
    });

    test('更新不存在角色 → notice，列表保持', () async {
      await controller.refresh();
      await controller.saveCharacter(
        999999,
        const CharactersCompanion(description: Value('x')),
      );
      expect(controller.notice, contains('角色不存在'));
    });
  });
}