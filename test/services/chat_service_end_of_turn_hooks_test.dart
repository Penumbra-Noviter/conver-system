/// ChatService 回合末副作用集合（S1）专项契约测试。
///
/// 覆盖：列表序执行、ctx 内容（characterId / conversationId /
/// memoryChangedThisTurn）、memoryChanged 门 → backfill 触发、reflect 落库
/// 成功后补嵌（闭包内协作）、服务内吞错不中断后续钩子与主回复、空集合
/// 零副作用。降级契约 = 服务内吞错，集合层只做顺序编排（不 try/catch）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/companion/relationship_service.dart';
import 'package:conver_system_mobile/services/embedding/embedding_service.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/memory/memory_service.dart';
import 'package:conver_system_mobile/services/memory/reflection_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../helpers/fake_llm_provider.dart';
import '../helpers/in_memory_secret_store.dart';

/// 记录 backfillPending 调用的 fake [EmbeddingService]（懒补嵌 seam）。
class _FakeEmbeddingService implements EmbeddingService {
  int backfillCalls = 0;

  @override
  Future<int> backfillPending(
    int characterId, {
    int limit = kEmbeddingMaxBatch,
  }) async {
    backfillCalls++;
    return 0;
  }

  @override
  Future<List<MemoryEntry>> semanticSearch(
    int characterId,
    String queryText,
  ) async =>
      const <MemoryEntry>[];

  @override
  Future<List<List<MemoryEntry>>> buildClusterInput(int characterId) async =>
      const <List<MemoryEntry>>[];
}

/// getRelationship 抛错的 companion 仓储（关系服务内吞错的失败注入点）。
class _BoomCompanionRepository extends CompanionRepository {
  _BoomCompanionRepository(super.db);

  int getCalls = 0;

  @override
  Future<RelationshipState?> getRelationship(int characterId) async {
    getCalls++;
    throw StateError('relationship boom（测试注入）');
  }
}

void main() {
  late AppDatabase db;
  late CharacterRepository characterRepo;
  late ConversationRepository conversationRepo;
  late MessageRepository messageRepo;
  late SettingsRepository settingsRepo;
  late MemoryRepository memoryRepo;
  late MemoryService memoryService;
  late CompanionRepository companionRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final secretStore = InMemorySecretStore();
    await secretStore.write(key: 'claude_api_key', value: 'sk-test');
    characterRepo = CharacterRepository(db);
    conversationRepo = ConversationRepository(db, const FakeSettingsReader());
    messageRepo = MessageRepository(db);
    settingsRepo = SettingsRepository(database: db, secretStore: secretStore);
    memoryRepo = MemoryRepository(db);
    memoryService = MemoryService(memoryRepo);
    companionRepo = CompanionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<({int characterId, Conversation conversation})> seedConversation() async {
    final character = await characterRepo.createCharacter(
      CharactersCompanion.insert(
        name: '艾莉亚',
        firstMes: Value(''),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final conversation =
        await conversationRepo.createConversation(characterId: character.id);
    return (characterId: character.id, conversation: conversation);
  }

  Future<void> drainStream(Stream<ChatEvent> stream) async {
    await for (final _ in stream) {
      // 消费至流结束。
    }
  }

  ChatService buildService(
    LLMProvider provider, {
    List<EndOfTurnHook> hooks = const [],
    MemoryService? memory,
  }) {
    return ChatService(
      database: db,
      conversationRepository: conversationRepo,
      characterRepository: characterRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: FixedLLMProviderFactory(provider),
      memoryService: memory,
      companionRepository: companionRepo,
      endOfTurnHooks: hooks,
    );
  }

  /// 轮询等待条件成立（fire-and-forget 异步），超时 2s 抛错。
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('waitFor 超时');
  }

  group('集合编排（S1）', () {
    test('依列表序执行且 ctx 携带 characterId / conversationId / memoryChanged', () async {
      final seed = await seedConversation();
      final order = <String>[];
      EndOfTurnContext? captured;
      final service = buildService(
        FakeLLMProvider(tokens: const ['你好']),
        hooks: [
          (ctx) async {
            order.add('backfill');
            captured = ctx;
          },
          (ctx) async => order.add('reflect'),
          (ctx) async => order.add('plan'),
          (ctx) async => order.add('relate'),
        ],
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      await waitFor(() => order.length == 4);
      expect(order, ['backfill', 'reflect', 'plan', 'relate']);
      expect(captured!.characterId, seed.characterId);
      expect(captured!.conversationId, seed.conversation.id);
      expect(captured!.memoryChangedThisTurn, isFalse,
          reason: '无记忆标签 → memoryChanged 恒 false');
    });

    test('endOfTurnHooks 缺省 const []：回合正常、零副作用', () async {
      final seed = await seedConversation();
      final service = buildService(FakeLLMProvider(tokens: const ['你好']));

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      final messages = await messageRepo.getMessages(seed.conversation.id);
      expect(
        messages.where((m) => m.role == Role.assistant).single.content,
        '你好',
      );
    });

    test('memoryChanged 门：backfill 闭包按 ctx 真值触发', () async {
      final seed = await seedConversation();
      final embedding = _FakeEmbeddingService();
      final service = buildService(
        FakeLLMProvider(tokens: const ['<add:她今天心情不好>', '好的']),
        memory: memoryService,
        hooks: [
          (ctx) async {
            final characterId = ctx.characterId;
            if (!ctx.memoryChangedThisTurn || characterId == null) {
              return;
            }
            await embedding.backfillPending(characterId);
          },
        ],
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      await waitFor(() => embedding.backfillCalls > 0);
      expect(embedding.backfillCalls, 1);
      expect(await memoryRepo.listRecentEpisodic(seed.characterId), isNotEmpty);
    });

    test('reflect 闭包内协作：反思落库成功后直接补嵌（集合层无因果边）', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.memoryReflectionEnabledKey: 'true',
      });
      final embedding = _FakeEmbeddingService();
      final reflection = ReflectionService(
        characterRepository: characterRepo,
        memoryRepository: memoryRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        extractor: ({
          required String charName,
          required List<String> dialogueLines,
          required List<String> existingFacts,
        }) async =>
            const ['用户喜欢咖啡'],
        interval: 1,
      );
      final service = buildService(
        FakeLLMProvider(tokens: const ['你好']),
        hooks: [
          (ctx) async {
            // backfill 门：无 memoryChanged（本回合无记忆标签）→ 空操作。
          },
          (ctx) async {
            final characterId = ctx.characterId;
            if (characterId == null) {
              return;
            }
            await reflection.reflectAfterTurn(
              characterId: characterId,
              conversationId: ctx.conversationId,
            );
            // 反思成功（服务内吞错，不抛即视为成功）→ 补嵌。
            await embedding.backfillPending(characterId);
          },
        ],
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      await waitFor(() => embedding.backfillCalls > 0);
      expect(embedding.backfillCalls, 1);
      var factCount = 0;
      for (var i = 0; i < 200 && factCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        factCount =
            (await memoryRepo.listPersonaFacts(seed.characterId)).length;
      }
      expect(factCount, 1);
      expect(
        (await memoryRepo.listPersonaFacts(seed.characterId))
            .map((e) => e.content),
        contains('用户喜欢咖啡'),
      );
    });

    test('反射服务内吞错：后续 plan/relate 仍执行、ChatDone 不阻断', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.memoryReflectionEnabledKey: 'true',
      });
      final order = <String>[];
      final reflection = ReflectionService(
        characterRepository: characterRepo,
        memoryRepository: memoryRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        extractor: ({
          required String charName,
          required List<String> dialogueLines,
          required List<String> existingFacts,
        }) async =>
            throw StateError('reflection boom（测试注入）'),
        interval: 1,
      );
      final service = buildService(
        FakeLLMProvider(tokens: const ['你好']),
        hooks: [
          (ctx) async {
            // backfill：恒空操作（本用例无 embedding 场景）。
          },
          (ctx) async {
            // 进入即记录（并发完成序不定，断言进入序 = 列表序）。
            order.add('reflect');
            final characterId = ctx.characterId;
            if (characterId == null) {
              return;
            }
            await reflection.reflectAfterTurn(
              characterId: characterId,
              conversationId: ctx.conversationId,
            );
          },
          (ctx) async => order.add('plan'),
          (ctx) async => order.add('relate'),
        ],
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      await waitFor(() => order.length == 3);
      expect(order, ['reflect', 'plan', 'relate']);
      // 失败路径零落库（服务内吞错返回 0）。
      expect(await memoryRepo.listPersonaFacts(seed.characterId), isEmpty);
    });

    test('关系服务内吞错：不产生未处理异步异常、assistant 正常落库', () async {
      final seed = await seedConversation();
      final boomRepo = _BoomCompanionRepository(db);
      final relationship = RelationshipService(
        companionRepository: boomRepo,
        conversationRepository: conversationRepo,
        messageRepository: messageRepo,
        now: () => DateTime(2026, 9, 15, 12, 0, 0),
      );
      final service = buildService(
        FakeLLMProvider(tokens: const ['你好']),
        hooks: [
          (ctx) async {
            final characterId = ctx.characterId;
            if (characterId == null) {
              return;
            }
            await relationship.evaluateAfterTurn(
              characterId: characterId,
              conversationId: ctx.conversationId,
            );
          },
        ],
      );

      // drain 正常结束 = 无未处理异步异常冒泡（集合层不 try/catch）。
      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      expect(boomRepo.getCalls, 1);
      final messages = await messageRepo.getMessages(seed.conversation.id);
      expect(
        messages.where((m) => m.role == Role.assistant).single.content,
        '你好',
      );
    });
  });
}