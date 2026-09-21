/// 聊天 widget 测试装配基座 — 真实 ChatService（内存 drift + InMemorySecretStore
/// + 注入 [LLMProvider] 抽象替身）+ 内存仓储，收敛装配噪音供
/// `chat_view_test` / `chat_entry_test` 复用（装配形状与
/// `chat_controller_test` 同形：provider 经 FixedLLMProviderFactory 注入）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/branch/branch_service.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/conversation_export_file_exchange.dart';
import 'package:conver_system_mobile/services/conversation_export_service.dart';
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

  @override
  Future<Map<String, String>> get templateVars async => const {};
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
    this.lorebookRepository,
    this.settingsRepository,
    this.secretStore,
    DateTime Function() now,
  ) : _now = now;

  /// 时间戳来源（直抄 chat_controller_test 的 fakeNow 注入形态）：角色仓储
  /// 与分支服务复用同一时钟，保证测试内不产生第二个独立时间源（F-141）。
  final DateTime Function() _now;

  /// 创建环境并预置默认 claude Key（未配置 Key 的测试自行删除）。
  ///
  /// [now] 为时间戳来源注入点（测试确定性用，直抄 chat_controller_test 的
  /// `fakeNow` 可变变量 + 闭包先例），缺省 [DateTime.now]——既有 8 个消费
  /// 文件一律零实参调用 `ChatTestEnv.create()`，源码级兼容零破坏（F-141）。
  static Future<ChatTestEnv> create({DateTime Function()? now}) async {
    final clock = now ?? DateTime.now;
    final db = AppDatabase(NativeDatabase.memory());
    final secretStore = InMemorySecretStore();
    final env = ChatTestEnv._(
      db,
      ConversationRepository(db, const FakeSettingsReader()),
      CharacterRepository(db, now: clock),
      MessageRepository(db),
      LorebookRepository(db),
      SettingsRepository(database: db, secretStore: secretStore),
      secretStore,
      clock,
    );
    await env.secretStore.write(key: 'claude_api_key', value: 'sk-e2e-test');
    return env;
  }

  final AppDatabase db;
  final ConversationRepository conversationRepository;
  final CharacterRepository characterRepository;
  final MessageRepository messageRepository;
  final LorebookRepository lorebookRepository;
  final SettingsRepository settingsRepository;
  final InMemorySecretStore secretStore;

  /// 释放内存库。
  Future<void> close() => db.close();

  /// 装配 ChatController：真实 ChatService + [provider] 经固定工厂注入。
  ///
  /// 控制器为纯状态机（不自动 loadEntry），UI 挂载时机由测试控制。
  /// M4-03 导出依赖为可选：不传则 controller 导出降级为「导出功能未配置」
  /// notice（既有测试装配不破坏）；传 fake 断言导出调用链。
  /// [connectRetryDelays] 透传 ChatService 连接阶段重试退避（M6-08 零部分
  /// 断流测试注入空序列跳过生产 1s/2s 退避，直接收束）。
  ChatController controllerOf(
    LLMProvider provider, {
    ConversationExportService? exportService,
    ConversationExportFileExchange? exportFileExchange,
    BranchService? branchService,
    List<Duration> connectRetryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) {
    final service = ChatService(
      lorebookRepository: lorebookRepository,
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
      settingsRepository: settingsRepository,
      providerFactory: FixedLLMProviderFactory(provider),
      connectRetryDelays: connectRetryDelays,
    );
    return ChatController(
      chatService: service,
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
      exportService: exportService,
      exportFileExchange: exportFileExchange,
      branchService: branchService,
    );
  }

  /// 装配分支服务（BR-02）：真实仓储 + 内存库（与 [controllerOf] 同源）。
  ///
  /// 分支流程测试用：`env.controllerOf(provider, branchService: env.branchServiceOf())`。
  BranchService branchServiceOf() {
    return BranchService(
      database: db,
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
      lorebookRepository: lorebookRepository,
      now: _now,
    );
  }

  /// 种子角色；[name] 为非空必填，[firstMes] 为开场白（空 → 不预插）。
  ///
  /// 时间戳取自注入时钟（F-141：移除字面 [DateTime.now]，测试可确定性控制
  /// seed 落库时刻）；companion 的 createdAt/updatedAt 属必填命名参数，其
  /// 值恒被 createCharacter 覆写、仅占位——任取一值占位即可，无观测语义
  /// （勿以此断言时间）。
  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
  }) {
    final now = _now();
    return characterRepository.createCharacter(
      CharactersCompanion.insert(
        name: name,
        firstMes: Value(firstMes),
        createdAt: now,
        updatedAt: now,
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