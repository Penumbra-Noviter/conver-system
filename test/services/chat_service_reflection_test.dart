/// ChatService 后台反思挂点集成契约（ADR-0004）：assistant 完整落库后
/// fire-and-forget 触发 ReflectionService，开关控制是否启用、失败降级不阻断。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/memory/memory_service.dart';
import 'package:conver_system_mobile/services/memory/reflection_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../helpers/fake_llm_provider.dart';
import '../helpers/in_memory_secret_store.dart';

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

  Future<void> drainStream(Stream<ChatEvent> stream) async {
    await for (final _ in stream) {
      // 消费至流结束。
    }
  }

  ChatService buildService({
    required LLMProvider provider,
    required ReflectionService reflectionService,
  }) {
    return ChatService(
      database: db,
      conversationRepository: conversationRepo,
      characterRepository: characterRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: FixedLLMProviderFactory(provider),
      memoryService: memoryService,
      reflectionService: reflectionService,
    );
  }

  ReflectionService buildReflection(List<String> result) {
    return ReflectionService(
      characterRepository: characterRepo,
      memoryRepository: memoryRepo,
      messageRepository: messageRepo,
      extractor: ({
        required String charName,
        required List<String> dialogueLines,
        required List<String> existingFacts,
      }) async =>
          result,
      interval: 1,
    );
  }

  test('开关开启：assistant 落库后触发反思并落库人格事实', () async {
    final conv = await seedConversation();
    await settingsRepo.setMany({
      SettingsRepository.memoryReflectionEnabledKey: 'true',
    });
    final provider = FakeLLMProvider(tokens: const ['你好']);
    final service = buildService(
      provider: provider,
      reflectionService: buildReflection(['用户喜欢咖啡']),
    );

    await drainStream(
      service.streamReply(conversationId: conv.id, content: '嗨'),
    );

    // fire-and-forget 反思异步执行：轮询等待落库（超时 2s）。
    var facts = await memoryRepo.listPersonaFacts(conv.characterId);
    for (var i = 0; i < 200 && facts.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      facts = await memoryRepo.listPersonaFacts(conv.characterId);
    }
    expect(facts.map((e) => e.content), contains('用户喜欢咖啡'));
  });

  test('开关关闭（缺省）：不触发反思', () async {
    final conv = await seedConversation();
    var extractorCalls = 0;
    final reflectionService = ReflectionService(
      characterRepository: characterRepo,
      memoryRepository: memoryRepo,
      messageRepository: messageRepo,
      extractor: ({
        required String charName,
        required List<String> dialogueLines,
        required List<String> existingFacts,
      }) async {
        extractorCalls++;
        return const ['用户喜欢咖啡'];
      },
      interval: 1,
    );
    final provider = FakeLLMProvider(tokens: const ['你好']);
    final service = buildService(
      provider: provider,
      reflectionService: reflectionService,
    );

    await drainStream(
      service.streamReply(conversationId: conv.id, content: '嗨'),
    );
    // 给 fire-and-forget 路径留出执行窗口，随后断言未被调用。
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(extractorCalls, 0);
    expect(await memoryRepo.listPersonaFacts(conv.characterId), isEmpty);
  });
}
