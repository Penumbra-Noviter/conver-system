/// ReflectionService 行为契约（ADR-0004 阶段 1.5）：节流 + 反思组装 + JSON
/// 数组解析 + 去重落库。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/memory/reflection_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../../helpers/fake_llm_provider.dart' show FakeLLMProvider;
import '../../helpers/in_memory_secret_store.dart';

void main() {
  group('parseReflectionFacts', () {
    test('直接 JSON 数组', () {
      expect(
        parseReflectionFacts('["用户喜欢咖啡", "用户讨厌香菜"]'),
        ['用户喜欢咖啡', '用户讨厌香菜'],
      );
    });

    test('```json 代码块包裹', () {
      expect(
        parseReflectionFacts('```json\n["用户喜欢咖啡"]\n```'),
        ['用户喜欢咖啡'],
      );
    });

    test('周围有解释文字 + 方括号范围', () {
      expect(
        parseReflectionFacts('以下是提炼的事实：["用户喜欢咖啡"] 共一条'),
        ['用户喜欢咖啡'],
      );
    });

    test('过滤非字符串与空串', () {
      expect(
        parseReflectionFacts('["用户喜欢咖啡", 123, "", "  ", null]'),
        ['用户喜欢咖啡'],
      );
    });

    test('非 JSON / 非数组 / 空串 → 空列表', () {
      expect(parseReflectionFacts(''), isEmpty);
      expect(parseReflectionFacts('这不是 JSON'), isEmpty);
      expect(parseReflectionFacts('{"a": 1}'), isEmpty);
    });
  });

  group('buildReflectionMessages', () {
    test('system 含角色名指令；user 含已有事实与对话记录', () {
      final messages = buildReflectionMessages(
        charName: '艾莉亚',
        dialogueLines: ['用户：你好', '艾莉亚：你好呀'],
        existingFacts: ['用户喜欢咖啡'],
      );
      expect(messages.length, 2);
      expect(messages[0].role, 'system');
      expect(messages[0].content, contains('艾莉亚'));
      expect(messages[0].content, contains('JSON 字符串数组'));
      expect(messages[1].role, 'user');
      expect(messages[1].content, contains('- 用户喜欢咖啡'));
      expect(messages[1].content, contains('用户：你好'));
      expect(messages[1].content, contains('艾莉亚：你好呀'));
    });

    test('无已有事实 → （暂无）占位', () {
      final messages = buildReflectionMessages(
        charName: '艾莉亚',
        dialogueLines: const ['用户：你好'],
        existingFacts: const [],
      );
      expect(messages[1].content, contains('（暂无）'));
    });
  });

  group('extractPersonaFactsWithProvider', () {
    test('generate 输出经 parseReflectionFacts 解析并透传 model', () async {
      final llm = FakeLLMProvider(tokens: ['["用户喜欢咖啡", "用户讨厌香菜"]']);
      final facts = await extractPersonaFactsWithProvider(
        llm: llm,
        model: 'claude-sonnet-5',
        charName: '艾莉亚',
        dialogueLines: const ['用户：你好'],
        existingFacts: const [],
      );
      expect(facts, ['用户喜欢咖啡', '用户讨厌香菜']);
      expect(llm.generateCallCount, 1);
      expect(llm.lastModel, 'claude-sonnet-5');
    });
  });

  group('ReflectionService.reflectAfterTurn', () {
    late AppDatabase db;
    late CharacterRepository characterRepo;
    late ConversationRepository conversationRepo;
    late MessageRepository messageRepo;
    late MemoryRepository memoryRepo;
    late SettingsRepository settingsRepo;

    late int extractorCalls;
    late List<String> extractorResult;
    late String capturedCharName;
    late List<String> capturedDialogueLines;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      characterRepo = CharacterRepository(db);
      conversationRepo = ConversationRepository(db, const FakeSettingsReader());
      messageRepo = MessageRepository(db);
      memoryRepo = MemoryRepository(db);
      settingsRepo = SettingsRepository(
        database: db,
        secretStore: InMemorySecretStore(),
      );
      // 开关读取约定 = 服务内部（reflectAfterTurn 首行门）：缺省关闭，用例
      // 需反思路径时显式开启（对齐服务内读语义的断言迁移）。
      await settingsRepo.setMany({
        SettingsRepository.memoryReflectionEnabledKey: 'true',
      });
      extractorCalls = 0;
      extractorResult = const [];
      capturedCharName = '';
      capturedDialogueLines = const [];
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> seedConversation() async {
      final character = await characterRepo.createCharacter(
        CharactersCompanion.insert(
          name: '艾莉亚',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final conv = await conversationRepo.createConversation(
        characterId: character.id,
      );
      return conv.id;
    }

    Future<void> seedUserMessages(int conversationId, int count) async {
      for (var i = 0; i < count; i++) {
        await messageRepo.createMessage(
          conversationId: conversationId,
          role: Role.user,
          content: '用户消息 $i',
        );
      }
    }

    ReflectionService buildService({int interval = 6}) {
      return ReflectionService(
        characterRepository: characterRepo,
        memoryRepository: memoryRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        extractor: ({
          required String charName,
          required List<String> dialogueLines,
          required List<String> existingFacts,
        }) async {
          extractorCalls++;
          capturedCharName = charName;
          capturedDialogueLines = dialogueLines;
          return extractorResult;
        },
        interval: interval,
      );
    }

    test('未到节流点（5 条 user，%6!=0）→ 零调用零落库', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 5);
      final service = buildService();

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(added, 0);
      expect(extractorCalls, 0);
    });

    test('零 user 消息 → 零调用', () async {
      final convId = await seedConversation();
      final service = buildService();

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(added, 0);
      expect(extractorCalls, 0);
    });

    test('到节流点（6 条 user）→ 反思并落库人格事实', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 6);
      extractorResult = ['用户喜欢咖啡', '用户讨厌香菜'];
      final service = buildService();

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(extractorCalls, 1);
      expect(capturedCharName, '艾莉亚');
      expect(added, 2);
      final facts = await memoryRepo.listPersonaFacts(1);
      expect(
        facts.map((e) => e.content),
        unorderedEquals(['用户喜欢咖啡', '用户讨厌香菜']),
      );
    });

    test('去重：已有事实与单次提取内重复均不落库', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 6);
      await memoryRepo.createEntry(
        characterId: 1,
        kind: MemoryKind.personaFact,
        content: '用户喜欢咖啡',
      );
      extractorResult = ['用户喜欢咖啡', '  ', '用户喜欢茶', '用户喜欢茶'];
      final service = buildService();

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(added, 1);
      final facts = await memoryRepo.listPersonaFacts(1);
      expect(
        facts.map((e) => e.content),
        unorderedEquals(['用户喜欢咖啡', '用户喜欢茶']),
      );
    });

    test('角色不存在 → 零落库（节流满足后）', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 6);
      extractorResult = ['用户喜欢咖啡'];
      final service = buildService();

      final added = await service.reflectAfterTurn(
        characterId: 99999,
        conversationId: convId,
      );

      expect(added, 0);
      expect(extractorCalls, 0);
    });

    test('节流间隔可注入（interval=2）', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 2);
      extractorResult = ['用户喜欢咖啡'];
      final service = buildService(interval: 2);

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(extractorCalls, 1);
      expect(added, 1);
    });

    test('历史超 historyLimit（25 条，interval=5）→ sublist 截断分支照常反思', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 25);
      extractorResult = ['用户喜欢咖啡'];
      final service = buildService(interval: 5);

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(extractorCalls, 1, reason: '25 % 5 == 0 → 节流放行');
      expect(added, 1);
    });

    test('署名逐字：user「用户：」+ assistant 角色名（经 recentMessages + 单源窗口）',
        () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 6); // 6 % 6 == 0 → 节流放行。
      for (var i = 0; i < 2; i++) {
        await messageRepo.createMessage(
          conversationId: convId,
          role: Role.assistant,
          content: '助手回应 $i',
        );
      }
      extractorResult = ['用户平和'];
      final service = buildService();

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(added, 1);
      expect(capturedDialogueLines, [
        for (var i = 0; i < 6; i++) '用户：用户消息 $i',
        for (var i = 0; i < 2; i++) '艾莉亚：助手回应 $i',
      ], reason: '署名文本逐字：用户:/角色名:');
    });

    test('historyLimit 构造可注入：窗口只含最近 N 条并保持升序', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 6);
      await messageRepo.createMessage(
        conversationId: convId,
        role: Role.assistant,
        content: '最后答',
      );
      extractorResult = ['事实'];
      final service = ReflectionService(
        characterRepository: characterRepo,
        memoryRepository: memoryRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        extractor: ({
          required String charName,
          required List<String> dialogueLines,
          required List<String> existingFacts,
        }) async {
          extractorCalls++;
          capturedDialogueLines = dialogueLines;
          return extractorResult;
        },
        interval: 6,
        historyLimit: 3,
      );

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(added, 1);
      expect(capturedDialogueLines, [
        '用户：用户消息 4',
        '用户：用户消息 5',
        '艾莉亚：最后答',
      ], reason: '尾 3 升序：u4、u5、最后答');
    });

    test('extractor 抛错：服务内吞错返回 0（S1 降级契约，不向上抛）', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 6);
      final service = ReflectionService(
        characterRepository: characterRepo,
        memoryRepository: memoryRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        extractor: ({
          required String charName,
          required List<String> dialogueLines,
          required List<String> existingFacts,
        }) async {
          throw StateError('reflection boom（测试注入）');
        },
        interval: 6,
      );

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(added, 0, reason: '失败路径返回 0（无新事实语义）');
      expect(await memoryRepo.listPersonaFacts(1), isEmpty);
    });

    test('开关关闭 → 零调用零落库（首行门，C8 开关读取收敛服务内）', () async {
      final convId = await seedConversation();
      await seedUserMessages(convId, 6);
      await settingsRepo.setMany({
        SettingsRepository.memoryReflectionEnabledKey: 'false',
      });
      extractorResult = ['用户喜欢咖啡'];
      final service = buildService();

      final added = await service.reflectAfterTurn(
        characterId: 1,
        conversationId: convId,
      );

      expect(added, 0, reason: '开关关闭 → 首行返回 0');
      expect(extractorCalls, 0, reason: '开关关闭路径 extractor 零调用');
      expect(await memoryRepo.listPersonaFacts(1), isEmpty);
    });
  });
}
