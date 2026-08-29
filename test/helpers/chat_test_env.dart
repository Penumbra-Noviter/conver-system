/// 聊天 widget 测试装配基座 — 真实 ChatService（内存 drift + InMemorySecretStore
/// + 注入 [LLMProvider] 抽象替身）+ 内存仓储，收敛装配噪音供
/// `chat_view_test` / `chat_entry_test` 复用（装配形状与
/// `chat_controller_test` 同形：provider 经 FixedLLMProviderFactory 注入）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';

import 'fake_llm_provider.dart';
import 'in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（conversationRepository 的只读设置面）。
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

/// 聊天 widget 测试环境：内存库 + 四仓储 + InMemorySecretStore + 装配函数。
///
/// 用 [controllerOf] 装配 ChatController（驱动真实 ChatService）；用
/// [seedCharacter] / [seedConversation] / [seedMessage] 铺垫数据。
class ChatTestEnv {
  ChatTestEnv._(
    this.db,
    this.conversationRepository,
    this.characterRepository,
    this.messageRepository,
    this.settingsRepository,
    this.secretStore,
  );

  /// 创建环境并预置默认 claude Key（未配置 Key 的测试自行删除）。
  static Future<ChatTestEnv> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    final secretStore = InMemorySecretStore();
    final env = ChatTestEnv._(
      db,
      ConversationRepository(db, const FakeSettingsReader()),
      CharacterRepository(db),
      MessageRepository(db),
      SettingsRepository(database: db, secretStore: secretStore),
      secretStore,
    );
    await env.secretStore.write(key: 'claude_api_key', value: 'sk-e2e-test');
    return env;
  }

  final AppDatabase db;
  final ConversationRepository conversationRepository;
  final CharacterRepository characterRepository;
  final MessageRepository messageRepository;
  final SettingsRepository settingsRepository;
  final InMemorySecretStore secretStore;

  /// 释放内存库。
  Future<void> close() => db.close();

  /// 装配 ChatController：真实 ChatService + [provider] 经固定工厂注入。
  ///
  /// 控制器为纯状态机（不自动 loadEntry），UI 挂载时机由测试控制。
  ChatController controllerOf(LLMProvider provider) {
    final service = ChatService(
      database: db,
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
      settingsRepository: settingsRepository,
      providerFactory: FixedLLMProviderFactory(provider),
    );
    return ChatController(
      chatService: service,
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
    );
  }

  /// 种子角色；[name] 为非空必填，[firstMes] 为开场白（空 → 不预插）。
  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
  }) {
    return characterRepository.createCharacter(
      CharactersCompanion.insert(
        name: name,
        firstMes: Value(firstMes),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// 种子对话（创建即可能预插开头白，取决于角色 firstMes）。
  Future<Conversation> seedConversation(int characterId) =>
      conversationRepository.createConversation(characterId: characterId);

  /// 种子单条消息。
  Future<Message> seedMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) {
    return messageRepository.createMessage(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }
}