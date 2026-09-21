/// ChatService 记忆链路集成契约（AC-03）：记忆注入 + 标签剥离落库。
///
/// 装配真实 ChatService（内存 drift + InMemorySecretStore + Fake provider）并
/// 注入 [MemoryService]，验证：
/// 1. 组装消息含记忆注入（人格事实每轮重注入 + 记忆三模式指令）；
/// 2. assistant 回复中的记忆标签被剥离后落库、标签内容落库记忆。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/embedding/embedding_service.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/memory/memory_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../helpers/fake_llm_provider.dart';
import '../helpers/in_memory_secret_store.dart';

/// 记录 backfillPending 调用的 fake [EmbeddingService]（VR-07 懒补嵌 seam）。
class _FakeEmbeddingService implements EmbeddingService {
  int backfillCalls = 0;

  /// 置位后 backfillPending 模拟服务内失败：debugPrint 降级返回 0，不向上抛
  /// （S1 服务内吞错契约——集合层不再 try/catch，降级收敛在服务内部）。
  Object? backfillError;

  @override
  Future<int> backfillPending(
    int characterId, {
    int limit = kEmbeddingMaxBatch,
  }) async {
    backfillCalls++;
    if (backfillError != null) {
      debugPrint('后台补嵌失败，跳过: $backfillError');
      return 0;
    }
    return 0;
  }

  @override
  Future<List<MemoryEntry>> semanticSearch(
    int characterId,
    String queryText,
  ) async => const <MemoryEntry>[];

  @override
  Future<List<List<MemoryEntry>>> buildClusterInput(int characterId) async =>
      const <List<MemoryEntry>>[];
}

void main() {
  late AppDatabase db;
  late CharacterRepository characterRepo;
  late ConversationRepository conversationRepo;
  late MessageRepository messageRepo;
  late SettingsRepository settingsRepo;
  late MemoryRepository memoryRepo;
  late MemoryService memoryService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final secretStore = InMemorySecretStore();
    // resolveProvider 走 claude 槽位解析链，需预置 key（对齐 chat_test_env）。
    await secretStore.write(key: 'claude_api_key', value: 'sk-test');
    characterRepo = CharacterRepository(db);
    conversationRepo = ConversationRepository(db, const FakeSettingsReader());
    messageRepo = MessageRepository(db);
    settingsRepo = SettingsRepository(database: db, secretStore: secretStore);
    memoryRepo = MemoryRepository(db);
    memoryService = MemoryService(memoryRepo);
  });

  tearDown(() async {
    await db.close();
  });

  ChatService buildService(
    LLMProvider provider, {
    EmbeddingService? embeddingService,
  }) {
    // S1：回合末副作用收敛为装配层闭包集合（本文件只注册 backfill 钩子）。
    return ChatService(
      lorebookRepository: LorebookRepository(db),
      conversationRepository: conversationRepo,
      characterRepository: characterRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: FixedLLMProviderFactory(provider),
      memoryService: memoryService,
      endOfTurnHooks: [
        // backfill：memoryChanged 门（<add:>/<persona:> 落库才触发）。
        (ctx) async {
          final characterId = ctx.characterId;
          if (embeddingService == null ||
              characterId == null ||
              !ctx.memoryChangedThisTurn) {
            return;
          }
          await embeddingService.backfillPending(characterId);
        },
      ],
    );
  }

  Future<Conversation> seedConversation() async {
    final character = await characterRepo.createCharacter(
      CharactersCompanion.insert(
        name: '艾莉亚',
        firstMes: Value(''),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return conversationRepo.createConversation(characterId: character.id);
  }

  /// 消费流直到 done（完整落库）。
  Future<void> drainStream(Stream<ChatEvent> stream) async {
    await for (final _ in stream) {
      // 消费至流结束。
    }
  }

  group('记忆注入（AC-03）', () {
    test('组装消息含人格事实重注入 + 记忆三模式指令', () async {
      final conv = await seedConversation();
      // 预置一条人格事实。
      await memoryRepo.createEntry(
        characterId: conv.characterId,
        kind: MemoryKind.personaFact,
        content: '她叫艾莉亚',
      );
      final provider = FakeLLMProvider(tokens: const ['好']);
      final service = buildService(provider);

      await drainStream(
        service.streamReply(conversationId: conv.id, content: '你好'),
      );

      final messages = provider.lastMessages!;
      // 第一条为角色人格 system，之后紧跟记忆注入（指令 + 记忆库）。
      expect(messages.any((m) => m.content.contains('关键信息记录模式')), isTrue);
      final library = messages.firstWhere(
        (m) => m.content.contains('【当前记忆库内容】'),
      );
      expect(library.content, contains('人格事实：'));
      expect(library.content, contains('- 她叫艾莉亚'));
    });

    test('无记忆时仍注入指令模板（不注入空记忆库）', () async {
      final conv = await seedConversation();
      final provider = FakeLLMProvider(tokens: const ['好']);
      final service = buildService(provider);

      await drainStream(
        service.streamReply(conversationId: conv.id, content: '你好'),
      );

      final messages = provider.lastMessages!;
      expect(messages.any((m) => m.content.contains('关键信息记录模式')), isTrue);
      expect(messages.any((m) => m.content.contains('【当前记忆库内容】')), isFalse);
    });
  });

  group('标签剥离落库（AC-02 集成）', () {
    test('assistant 落库内容剥离标签；标签内容落库记忆', () async {
      final conv = await seedConversation();
      // 回复含 <persona:> 标签，应剥离后落库 assistant、标签内容落库记忆。
      final provider = FakeLLMProvider(
        tokens: const ['<persona:她叫艾莉亚>', '你好呀'],
      );
      final service = buildService(provider);

      await drainStream(
        service.streamReply(conversationId: conv.id, content: '嗨'),
      );

      final messages = await messageRepo.getMessages(conv.id);
      final assistant = messages
          .where((m) => m.role == Role.assistant)
          .toList();
      expect(assistant, isNotEmpty);
      expect(assistant.last.content, '你好呀');
      expect(assistant.last.content.contains('<persona:'), isFalse);

      final facts = await memoryRepo.listPersonaFacts(conv.characterId);
      expect(facts.map((e) => e.content), ['她叫艾莉亚']);
    });
  });

  group('懒补嵌挂点（VR-07）', () {
    test('记忆落库后触发 backfillPending（enabled 门在服务内）', () async {
      final conv = await seedConversation();
      final embeddingService = _FakeEmbeddingService();
      final provider = FakeLLMProvider(tokens: const ['<add:她今天心情不好>', '好的']);
      final service = buildService(
        provider,
        embeddingService: embeddingService,
      );

      await drainStream(
        service.streamReply(conversationId: conv.id, content: '嗨'),
      );

      // fire-and-forget 补嵌异步执行：轮询等待触达（超时 2s）。
      for (var i = 0; i < 200 && embeddingService.backfillCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(embeddingService.backfillCalls, 1);
      expect(await memoryRepo.listRecentEpisodic(conv.characterId), isNotEmpty);
    });

    test('无记忆落库（无 add/persona 标签）：不触发补嵌', () async {
      final conv = await seedConversation();
      final embeddingService = _FakeEmbeddingService();
      final provider = FakeLLMProvider(tokens: const ['好的']);
      final service = buildService(
        provider,
        embeddingService: embeddingService,
      );

      await drainStream(
        service.streamReply(conversationId: conv.id, content: '嗨'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(embeddingService.backfillCalls, 0);
    });

    test('补嵌内部失败：服务内吞（S1 契约），回合不阻断、assistant 正常落库', () async {
      final conv = await seedConversation();
      final embeddingService = _FakeEmbeddingService()
        ..backfillError = StateError('补嵌失败（测试注入）');
      final provider = FakeLLMProvider(tokens: const ['<add:她今天心情不好>', '好的']);
      final service = buildService(
        provider,
        embeddingService: embeddingService,
      );

      await drainStream(
        service.streamReply(conversationId: conv.id, content: '嗨'),
      );

      final messages = await messageRepo.getMessages(conv.id);
      expect(messages.where((m) => m.role == Role.assistant), isNotEmpty);
    });
  });
}
