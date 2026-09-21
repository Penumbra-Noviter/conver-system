/// ChatService 回合编排行为契约（T03 验收 A2–A5）。
///
/// 语义锚点（逐字对齐）：`desktop/backend/app/services/chat.py`（prepare_chat /
/// complete_chat / stream_reply / regenerate_chat）、`message.py`
/// （auto_insert_greeting / build_message_list / delete_messages_from）、
/// `error_mapping.py`（llm_error_response / domain_error_response）、
/// `llm/resolver.py`（resolve_llm Key 解析链 / ApiKeyMissing 文案）。
///
/// 测试 seam（公共接口边界，不锁内部实现）：[ChatService.streamReply] /
/// [ChatService.regenerate] 两个编排入口 + [llmErrorResponse] /
/// [domainErrorResponse] 两个错误映射纯函数；可观察状态 = 消息落库结果
/// （经 [MessageRepository.getMessages]）+ 事件序列（[ChatEvent]）+ 注入
/// [LLMProvider] / [LLMProviderFactory] 的调用记录。内存 drift 真 schema +
/// [InMemorySecretStore] + Fake / 可控 provider。
library;

import 'dart:async';
import 'dart:math';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/llm/prompt.dart';
import 'package:conver_system_mobile/services/secure_store.dart' show SecretStore;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_llm_provider.dart';
import '../helpers/in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（与仓储测试同形，T03 不另造规则）。
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

/// [LLMProviderFactory] 的内存假实现：记录派生入参；`unsupported` 触发
/// [ProviderNotSupportedError]（工厂派生规则的 T02 面）。
class _FakeFactory implements LLMProviderFactory {
  _FakeFactory(this._provider);

  final LLMProvider _provider;

  int createCallCount = 0;
  String? lastProvider;
  String? lastApiKey;
  String? lastBaseUrl;

  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    createCallCount++;
    lastProvider = provider;
    lastApiKey = apiKey;
    lastBaseUrl = baseUrl;
    if (provider == 'unsupported') {
      throw ProviderNotSupportedError(provider);
    }
    return _provider;
  }
}

/// [LLMProviderFactory] 的抛错假实现：create 原样抛出 [error]
/// （模拟未预期的装配层异常，T03 防御面测试用）。
class _ThrowingFactory implements LLMProviderFactory {
  _ThrowingFactory(this.error);

  final Object error;

  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    throw error;
  }
}

/// 逐 token 延时的可控 provider：先产出 [tokens]（每 token 间隔 [delay]），
/// 产出完后若 [errorAfter] 非空则抛出（原样，不翻译——模拟 T02 wire 层经
/// translateError 翻译后的 LLM 族异常，或模拟连接异常）。
///
/// 停止 / 断流 / 中途业务错误测试需要「产出部分后再中断」，共享
/// FakeLLMProvider（同步一次性产出/立即抛错）无法表达，故本文件私有实现。
class _TickingProvider extends LLMProvider {
  _TickingProvider({
    super.apiKey = 'test-key',
    List<String> tokens = const [],
    this.errorAfter,
    this.delay = const Duration(milliseconds: 5),
  }) : _tokens = List<String>.unmodifiable(tokens);

  final List<String> _tokens;
  final Object? errorAfter;
  final Duration delay;

  int generateCallCount = 0;
  int streamGenerateCallCount = 0;
  List<LlmMessage>? lastMessages;
  int? lastMaxTokens;
  String? lastModel;
  double? lastTemperature;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async {
    generateCallCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    lastTemperature = temperature;
    final e = errorAfter;
    if (e != null) {
      throw e;
    }
    return _tokens.join();
  }

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async* {
    streamGenerateCallCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    lastTemperature = temperature;
    for (final token in _tokens) {
      await Future<void>.delayed(delay);
      yield token;
    }
    final e = errorAfter;
    if (e != null) {
      throw e;
    }
  }

  @override
  Future<void> testConnection({String? model}) async {}
}

/// 产出 [tokens] 后**永久停滞**的 provider（T6/F-17 回归）：yield 完最后一个
/// token 后 `await` 永不完成的 [Completer]——不 complete、不 error、不放 done，
/// 复现真实网络停滞下 `providerSub.cancel()` 无上界挂起（cancel 等下一块/EOF）。
///
/// 与 [_TickingProvider]（会自然收束）互补：本 fake 专用于验证停止路径的
/// `.timeout` 兜底（有界完成 + onTimeout 不抛错继续收尾）。
class _StalledProvider extends LLMProvider {
  _StalledProvider({
    super.apiKey = 'test-key',
    List<String> tokens = const [],
  }) : _tokens = List<String>.unmodifiable(tokens);

  final List<String> _tokens;

  /// 永不完结的挂起点（yield 完后 await 它，使生成器永久挂起）。
  final Completer<void> _stall = Completer<void>();

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async =>
      _tokens.join();

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async* {
    for (final token in _tokens) {
      yield token;
    }
    await _stall.future; // 永久停滞：不 complete / 不 error / 不放 done
  }

  @override
  Future<void> testConnection({String? model}) async {}
}

/// cancel-unwind 以**错误**完成的 provider（F-55 回归专用）：返回一个
/// `onCancel` 处理器抛 [ReadPhaseInterruptedError] 的流——`StreamController`
/// 的 `sub.cancel()` 以该错误完成，确定性复刻 F-55 记录的「停滞流 cancel 后
/// 3s 窗口内连接 EOF 以**错误**完成」（真实 wire 中 EOF 错误经 `await for`
/// 机制路由进生成器收尾，`providerSub.cancel()` 以错误完成）。
///
/// 与 [_StalledProvider]（cancel 干净完成、只走 .timeout 兜底）互补：本 fake
/// 验证「cancel 以**错误**完成时，落库 + close 收尾仍执行」的结构保证（错误
/// 注入零竞态：错误由 cancel 自身触发，无窗口时序依赖）。
class _CancelErrorProvider extends LLMProvider {
  _CancelErrorProvider({super.apiKey = 'test-key'}) {
    _events = StreamController<String>(onCancel: () async {
      // cancel-unwind 断流：取消订阅即抛错 → cancel() 以该错误完成。
      throw ReadPhaseInterruptedError(
        originalError: StateError('cancel-unwind 断流'),
      );
    });
  }

  /// 服务端消费的事件流（token 由测试驱动注入；cancel 时以错误完成）。
  late final StreamController<String> _events;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async =>
      ''; // F-55 测试仅走流式路径。

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) =>
      _events.stream;

  /// 产出 token（ChatService 逐 token 消费；单订阅流在订阅建立前缓冲）。
  void emit(String token) => _events.add(token);

  @override
  Future<void> testConnection({String? model}) async {}
}

/// 依序播放故障序列的流式 provider（M6-06 连接阶段自动重试测试用）。
///
/// [sequence] 的第 i 个元素对应第 i+1 次 [streamGenerate] 调用的行为：
/// 非 null = 该次调用立即抛出该异常（原样，不翻译）；null = 正常产出
/// [tokens]；序列耗尽后一律正常产出。记录相邻调用间隔（[callGaps]，
/// 退避时序断言用）与调用计数。
class _FaultSequenceProvider extends LLMProvider {
  _FaultSequenceProvider({
    super.apiKey = 'test-key',
    List<String> tokens = const [],
    List<Object?> sequence = const [],
    this.onFirstFailure,
  })  : _tokens = List<String>.unmodifiable(tokens),
        _sequence = List<Object?>.unmodifiable(sequence);

  final List<String> _tokens;
  final List<Object?> _sequence;

  /// 首次抛错前完成的信号（重试窗口竞态测试用：确定性等首败已发生）。
  final Completer<void>? onFirstFailure;

  int streamGenerateCallCount = 0;

  /// 相邻两次 streamGenerate 调用的时间间隔（首次调用无前驱不记录）。
  final List<Duration> callGaps = [];

  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastCallAt = Duration.zero;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async =>
      _tokens.join();

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async* {
    final now = _clock.elapsed;
    if (_lastCallAt != Duration.zero) {
      callGaps.add(now - _lastCallAt);
    }
    _lastCallAt = now;
    final attempt = streamGenerateCallCount++;
    if (attempt < _sequence.length) {
      final e = _sequence[attempt];
      if (e != null) {
        final signal = onFirstFailure;
        if (signal != null && !signal.isCompleted) {
          signal.complete();
        }
        throw e;
      }
    }
    for (final token in _tokens) {
      yield token;
    }
  }

  @override
  Future<void> testConnection({String? model}) async {}
}

/// [MessageRepository] 的挂起替身：createMessage 可在进入时挂起于 [gate]
/// （放行后走真实落库）——确定性复现「部分落库挂起期间用户停止 → controller
/// 关闭 → 落库失败收口时 add-after-close」竞态（T06 内层 catch 守卫回归）。
class _GatedMessageRepository extends MessageRepository {
  _GatedMessageRepository(super.db, {super.now});

  /// 挂起器：选中 [gateRole] 角色的 createMessage 进入后 await 其 future。
  Completer<void>? gate;

  /// 挂起白名单角色（null → 全部挂起）。
  Role? gateRole;

  /// createMessage 已进入挂起（测试等待其越过入口后发起停止）。
  final Completer<void> entered = Completer<void>();

  @override
  Future<Message> createMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) async {
    final g = gate;
    if (g != null && (gateRole == null || role == gateRole)) {
      if (!entered.isCompleted) {
        entered.complete();
      }
      await g.future;
    }
    return super.createMessage(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }
}

/// [MessageRepository] 的调用计数替身（S6 I/O 契约）：统计定位读与全量读
/// 调用次数，其余透传真实实现——重生成路径「不再全量拉取、定位读 ≤3 次」
/// 的实证锚（口径：不含 F1 快照 [maxMessageId]，该读原路径已有）。
class _CountingMessageRepository extends MessageRepository {
  _CountingMessageRepository(super.db, {super.now});

  int getMessagesCalls = 0;
  int lastAssistantMessageCalls = 0;
  int lastUserMessageBeforeCalls = 0;
  int messagesBeforeCalls = 0;
  int messageByIdCalls = 0;

  @override
  Future<List<Message>> getMessages(int conversationId) {
    getMessagesCalls++;
    return super.getMessages(conversationId);
  }

  @override
  Future<Message?> lastAssistantMessage(int conversationId) {
    lastAssistantMessageCalls++;
    return super.lastAssistantMessage(conversationId);
  }

  @override
  Future<Message?> lastUserMessageBefore(int conversationId, int beforeId) {
    lastUserMessageBeforeCalls++;
    return super.lastUserMessageBefore(conversationId, beforeId);
  }

  @override
  Future<List<Message>> messagesBefore(int conversationId, int beforeId) {
    messagesBeforeCalls++;
    return super.messagesBefore(conversationId, beforeId);
  }

  @override
  Future<Message?> messageById(int conversationId, int messageId) {
    messageByIdCalls++;
    return super.messageById(conversationId, messageId);
  }
}

/// 可控挂起的 non-streaming provider：generate 在进入时完成 [started]、挂起于
/// [gate]，放行后返回 [reply]——F1（重生成期间并发新消息）与 F4（并发双触发
/// 拒绝）回归测试用：可在 generate 挂起期间对 DB 做并发写入 / 发起第二次调用。
class _HoldableProvider extends LLMProvider {
  _HoldableProvider({super.apiKey = 'test-key', this.reply = '新回复'});

  final String reply;

  /// generate 已进入（测试等待其越过快照捕获 / 目标解析）。
  final Completer<void> started = Completer<void>();

  /// generate 放行信号（测试完成并发注入后打开）。
  final Completer<void> gate = Completer<void>();

  int generateCallCount = 0;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async {
    generateCallCount++;
    if (!started.isCompleted) {
      started.complete();
    }
    await gate.future;
    return reply;
  }

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async* {
    throw StateError('F1/F4 测试不走流式路径');
  }
}

/// 防御面专用：模拟**违反 S3 契约**的 provider——错误不翻译、原样穿透
  /// [streamGenerate]（A2 Falsify 输入构造：ChatService 必须对任意非 LLM
  /// 错误兜底分类，即使 Provider 未走基类默认翻译骨架）。
  class _RawErrorProvider extends LLMProvider {
  _RawErrorProvider(this.error) : super(apiKey: 'test-key');

  /// 流式路径原样抛出的错误（领域错误 / 一般异常）。
  final Object error;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async =>
      '';

  // 原样穿透：不经基类翻译，把错误直接送达 ChatService（防御面测的就是
  // 这条「Provider 违规」路径；基类默认 streamGenerate 不会产生该形态）。
  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async* {
    throw error;
  }

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async* {
    throw UnimplementedError('防御面夹具走覆写 streamGenerate，不走模板路径');
  }
}

void main() {
  late AppDatabase db;
  late ConversationRepository convRepo;
  late MessageRepository messageRepo;
  late CharacterRepository charRepo;
  late SettingsRepository settingsRepo;
  late InMemorySecretStore secretStore;
  late ChatService service;

  // 固定起始时刻（drift 落库为 unix 秒），测试内手动拨动。
  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    convRepo = ConversationRepository(db, const FakeSettingsReader(),
        now: () => fakeNow);
    messageRepo = MessageRepository(db, now: () => fakeNow);
    charRepo = CharacterRepository(db, now: () => fakeNow);
    secretStore = InMemorySecretStore();
    settingsRepo = SettingsRepository(database: db, secretStore: secretStore);
    // 默认配置 claude Key（发送/重生成主路径需要；「未配置 Key」用例单独清空）。
    await settingsRepo.setMany({'claude_api_key': 'sk-default'});
  });

  tearDown(() async {
    await db.close();
  });

  void wireService(LLMProvider provider) {
    service = ChatService(
      lorebookRepository: LorebookRepository(db),
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: _FakeFactory(provider),
    );
  }

  /// 以可注入的连接重试退避序列装配服务（M6-06：测试注入短值获得确定性时序）。
  void wireServiceWithRetry(
    LLMProvider provider, {
    List<Duration> retryDelays = const [
      Duration(milliseconds: 20),
      Duration(milliseconds: 20),
    ],
  }) {
    service = ChatService(
      lorebookRepository: LorebookRepository(db),
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: _FakeFactory(provider),
      connectRetryDelays: retryDelays,
    );
  }

  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
    String systemPrompt = '',
    String personality = '',
    String scenario = '',
    String mesExample = '',
    String postHistoryInstructions = '',
    double? temperature,
    String promptMode = 'simple',
    String expertPrompt = '',
  }) {
    return charRepo.createCharacter(
      CharactersCompanion.insert(
        name: name,
        firstMes: Value(firstMes),
        systemPrompt: Value(systemPrompt),
        personality: Value(personality),
        scenario: Value(scenario),
        mesExample: Value(mesExample),
        postHistoryInstructions: Value(postHistoryInstructions),
        temperature: temperature == null
            ? const Value.absent()
            : Value(temperature),
        promptMode: Value(promptMode),
        expertPrompt: Value(expertPrompt),
        createdAt: fakeNow,
        updatedAt: fakeNow,
      ),
    );
  }

  /// 创建对话（角色有 first_mes 时经会话仓储预插开场白——M1 语义）。
  Future<Conversation> seedConversation(int characterId) {
    return convRepo.createConversation(characterId: characterId);
  }

  /// 对话内全部消息（经 MessageRepository 排序：created_at 正序、id 兜底）。
  Future<List<Message>> messagesOf(int conversationId) {
    return messageRepo.getMessages(conversationId);
  }

  /// 角色 [role]、内容 [content] 列表（落库状态断言辅助）。
  Future<List<(Role, String)>> roleContentsOf(int conversationId) async {
    final msgs = await messagesOf(conversationId);
    return [for (final m in msgs) (m.role, m.content)];
  }

  /// 消息候选内容列表（index 升序，候选语义断言辅助；MS-02）。
  Future<List<String>> swipeContentsOf(int messageId) async {
    final swipes = await messageRepo.listSwipes(messageId);
    return [for (final s in swipes) s.content];
  }

  Future<Message> sendUserMessage(int conversationId, String content) {
    return messageRepo.createMessage(
      conversationId: conversationId,
      role: Role.user,
      content: content,
    );
  }

  Future<Message> sendAssistantMessage(int conversationId, String content) {
    return messageRepo.createMessage(
      conversationId: conversationId,
      role: Role.assistant,
      content: content,
    );
  }

  /// 四消息对话种子（MS-03 编辑/删除组共用）：开场白 + 首轮对 + 次轮对。
  /// 返回 (角色, 对话, user1, asst1, user2, asst2)。
  Future<(Character, Conversation, Message, Message, Message, Message)>
      seedFourMessageConversation() async {
    final char = await seedCharacter(firstMes: '开场。');
    final conv = await seedConversation(char.id);
    final user1 = await sendUserMessage(conv.id, '第一轮问');
    final asst1 = await sendAssistantMessage(conv.id, '第一轮答');
    final user2 = await sendUserMessage(conv.id, '第二轮问');
    final asst2 = await sendAssistantMessage(conv.id, '第二轮答');
    return (char, conv, user1, asst1, user2, asst2);
  }

  /// 消息数查询辅助（级联/截断断言：swipe 与 thought 行数归零）。
  Future<int> innerThoughtCountFor(int messageId) async {
    final rows = await (db.select(db.innerThoughts)
          ..where((t) => t.messageId.equals(messageId)))
        .get();
    return rows.length;
  }

  // ── 错误映射纯函数（逐字对齐 error_mapping.py / exceptions.py）──

  group('llmErrorResponse（A2 错误面，逐字对齐 llm_error_response）', () {
    test('Auth：provider 非空 → "{provider} API Key 无效，请在设置中更新" + 401',
        () {
      final mapped = llmErrorResponse(LLMAuthError('claude'), 'claude');
      expect(mapped.status, 401);
      expect(mapped.message, 'claude API Key 无效，请在设置中更新');
    });

    test('Auth：provider 为空 → 无前缀基础文案 + 401', () {
      final mapped = llmErrorResponse(LLMAuthError('claude'), '');
      expect(mapped.status, 401);
      expect(mapped.message, 'API Key 无效，请在设置中更新');
    });

    test('RateLimit → 429 固定消息', () {
      final mapped = llmErrorResponse(LLMRateLimitError('claude'), 'claude');
      expect(mapped.status, 429);
      expect(mapped.message, 'API 请求频率超限，请稍后再试');
    });

    test('Timeout → 504 固定消息', () {
      final mapped = llmErrorResponse(LLMTimeoutError('claude'), 'claude');
      expect(mapped.status, 504);
      expect(mapped.message, 'API 请求超时，请检查网络后重试');
    });

    test('ContentFilter → 400 + str(e)', () {
      final mapped = llmErrorResponse(
          LLMContentFilterError('claude'), 'claude');
      expect(mapped.status, 400);
      expect(mapped.message, '内容被 claude 内容过滤器拦截');
    });

    test('BadRequest → 兜底 502 + str(e)（桌面映射表未显式注册）', () {
      final e = LLMBadRequestError('claude', '参数非法');
      final mapped = llmErrorResponse(e, 'claude');
      expect(mapped.status, 502);
      expect(mapped.message, 'claude API 请求错误: 参数非法');
    });

    test('ResponseParseFailed → 兜底 502 + str(e)', () {
      final e = LLMResponseParseFailedError('claude', 'bad json');
      final mapped = llmErrorResponse(e, 'claude');
      expect(mapped.status, 502);
      expect(mapped.message, e.message);
    });

    test('未注册子类 → 兜底 502 + str(e)', () {
      final e = LLMError('claude API 调用失败: socket 断开');
      final mapped = llmErrorResponse(e, 'claude');
      expect(mapped.status, 502);
      expect(mapped.message, 'claude API 调用失败: socket 断开');
    });
  });

  group('domainErrorResponse（领域族，对齐 domain_error_response）', () {
    test('ConversationNotFound → 404 + str(exc)', () {
      final mapped = domainErrorResponse(ConversationNotFoundError());
      expect(mapped.status, 404);
      expect(mapped.message, '对话不存在');
    });

    test('MessageNotFound → 404 + str(exc)', () {
      final mapped = domainErrorResponse(MessageNotFoundError());
      expect(mapped.status, 404);
      expect(mapped.message, '消息不存在');
    });

    test('CharacterNotFound → 404 + 角色不存在: <id>', () {
      final mapped = domainErrorResponse(CharacterNotFoundError(999999));
      expect(mapped.status, 404);
      expect(mapped.message, '角色不存在: 999999');
    });

    test('ApiKeyMissing → 400 + 未配置文案', () {
      final mapped = domainErrorResponse(ApiKeyMissingError('claude'));
      expect(mapped.status, 400);
      expect(mapped.message, '未配置 claude API Key，请在设置中填写');
    });

    test('ProviderNotSupported → 400 + str(exc)', () {
      final mapped =
          domainErrorResponse(ProviderNotSupportedError('deepseek'));
      expect(mapped.status, 400);
      expect(mapped.message, '不支持的 Provider: deepseek');
    });

    test('InvalidRegenerateTarget 各变体 → 400 + str(exc)', () {
      for (final e in [
        InvalidRegenerateTargetError.noAssistantReply(),
        InvalidRegenerateTargetError.notAssistant(),
        InvalidRegenerateTargetError.noTriggerUser(),
      ]) {
        final mapped = domainErrorResponse(e);
        expect(mapped.status, 400);
        expect(mapped.message, e.message);
      }
    });

    test('未知 DomainError 子类 → 400 + str(e) 兜底', () {
      final mapped = domainErrorResponse(_UnknownDomainError());
      expect(mapped.status, 400);
      expect(mapped.message, '未知领域错误');
    });
  });

  // ── A2 发送链路 ──

  group('streamReply · 发送链路（A2）', () {
    test('A2: 完整发送 → done 落库完整 assistant；组装含开场白与 user', () async {
      final char = await seedCharacter(
        firstMes: '你好，{{user}}！我是{{char}}。',
        systemPrompt: '你是{{char}}，一位冒险向导。',
      );
      final conv = await seedConversation(char.id);
      // 会话创建时预插开场白（模板变量已替换）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '你好，User！我是艾莉亚。'),
      ]);

      wireService(FakeLLMProvider(tokens: const ['你', '好', '，', '冒险者']));

      final events = await service
          .streamReply(conversationId: conv.id, content: '我想出发')
          .toList();

      expect(
        [for (final e in events) if (e is ChatToken) e.token],
        ['你', '好', '，', '冒险者'],
      );
      final done = events.last;
      expect(done, isA<ChatDone>());
      expect((done as ChatDone).messageId, isNotNull);

      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '你好，User！我是艾莉亚。'), // 开场白原样保留
        (Role.user, '我想出发'),
        (Role.assistant, '你好，冒险者'),
      ]);
    });

    test('A2: autoGreeting 零消息守卫——对话无消息且角色有 first_mes → 首条开场白',
        () async {
      // 创建对话时角色无 first_mes（会话仓储不预插开场白）。
      final char = await seedCharacter(name: '影');
      final conv = await seedConversation(char.id);
      expect(await messagesOf(conv.id), isEmpty);

      // 角色后来补上 first_mes（模拟角色编辑）。
      await charRepo.updateCharacter(
        char.id,
        const CharactersCompanion(firstMes: Value('{{user}}，我在{{char}}等你。')),
      );

      wireService(FakeLLMProvider(tokens: const ['回应']));
      await service
          .streamReply(conversationId: conv.id, content: '来了')
          .toList();

      expect(await roleContentsOf(conv.id), [
        (Role.assistant, 'User，我在影等你。'), // 开场白：{{user}}/{{char}} 已替换
        (Role.user, '来了'),
        (Role.assistant, '回应'),
      ]);
    });

    test('A2: 已有消息（预插开场白）→ autoGreeting 不重复插入', () async {
      final char = await seedCharacter(firstMes: '开场。');
      final conv = await seedConversation(char.id);
      expect(await messagesOf(conv.id), hasLength(1)); // 预插开场白

      wireService(FakeLLMProvider(tokens: const ['回复']));
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, 'hi'),
        (Role.assistant, '回复'),
      ]);
    });

    test('A2: 角色无 first_mes → 无开场白，仅 user + assistant', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(FakeLLMProvider(tokens: const ['回复']));
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, '回复'),
      ]);
    });

    test('A2: 组装按角色字段映射 CharacterData + 滑窗 sliding_window_rounds',
        () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '{{char}}的人设',
        scenario: '{{char}}的场景',
        mesExample: '<START>\n{{user}}: 例问\n{{char}}: 例答',
        postHistoryInstructions: '{{char}}的指令',
      );
      final conv = await seedConversation(char.id);

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '{{user}}你好')
          .toList();

      final sent = provider.lastMessages!;
      // 组装顺序：system(personality 回退) → scenario → [叙述风格]（默认开） →
      // mes_example → 历史 → PHI → user。
      expect(sent[0],
          const LlmMessage(role: 'system', content: '艾莉亚的人设'));
      expect(sent[1],
          const LlmMessage(role: 'system', content: '[场景设定]\n艾莉亚的场景'));
      expect(sent[2],
          LlmMessage(role: 'system', content: '[叙述风格]\n${SettingsRepository.narrativeStyleDefaultRules}'));
      expect(sent[3], const LlmMessage(role: 'user', content: '例问'));
      expect(sent[4], const LlmMessage(role: 'assistant', content: '例答'));
      expect(sent[sent.length - 2],
          const LlmMessage(role: 'system', content: '艾莉亚的指令'));
      expect(sent.last, const LlmMessage(role: 'user', content: 'User你好'));
      // 历史（开场白 + user 落库后）位于 PHI 之前。
      final historyRoles = [
        for (final m in sent)
          if (m.role == 'assistant' && m.content == '开场。') m,
      ];
      expect(historyRoles, hasLength(1));
      expect(provider.lastMaxTokens, 2048);
    });

    test('A2: autoGreeting 开场白注入 extraVars（工单 04）', () async {
      await settingsRepo.setMany({'template_vars': '{"city":"长安"}'});
      final char = await seedCharacter(name: '影');
      final conv = await seedConversation(char.id);
      expect(await messagesOf(conv.id), isEmpty);

      await charRepo.updateCharacter(
        char.id,
        const CharactersCompanion(firstMes: Value('{{user}}，我在{{city}}的{{char}}等你。')),
      );

      wireService(FakeLLMProvider(tokens: const ['回应']));
      await service
          .streamReply(conversationId: conv.id, content: '来了')
          .toList();

      expect(await roleContentsOf(conv.id), [
        (Role.assistant, 'User，我在长安的影等你。'),
        (Role.user, '来了'),
        (Role.assistant, '回应'),
      ]);
    });

    test('A2: 组装经 extraVars 注入 system/scenario/phi/userContent（工单 04）',
        () async {
      await settingsRepo.setMany({'template_vars': '{"city":"长安"}'});
      final char = await seedCharacter(
        name: '艾莉亚',
        personality: '{{char}}住在{{city}}',
        scenario: '在{{city}}相遇',
        postHistoryInstructions: '提到{{city}}',
      );
      final conv = await seedConversation(char.id);

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '去{{city}}')
          .toList();

      final sent = provider.lastMessages!;
      expect(sent[0],
          const LlmMessage(role: 'system', content: '艾莉亚住在长安'));
      expect(sent[1],
          const LlmMessage(role: 'system', content: '[场景设定]\n在长安相遇'));
      expect(sent[sent.length - 2],
          const LlmMessage(role: 'system', content: '提到长安'));
      expect(sent.last, const LlmMessage(role: 'user', content: '去长安'));
    });

    test('A2: 零 token 空流不落库（done messageId 为 null）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(FakeLLMProvider(tokens: const []));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatDone>());
      expect((events.last as ChatDone).messageId, isNull);
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'), // 仅已发 user，无空 assistant
      ]);
    });

    test('A2: 未配置 Key → ChatError「未配置 {provider} API Key，请在设置中填写」',
        () async {
      await secretStore.delete(SecretStore.claudeApiKeySlot); // 清空默认 Key
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final factory = _FakeFactory(FakeLLMProvider(tokens: const ['x']));
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: factory,
      );

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(factory.createCallCount, 0, reason: 'Key 缺失在工厂派生之前拦截');
      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message,
          '未配置 claude API Key，请在设置中填写');
      // 桌面 prepare_chat：落库 user 后才解析 Key → user 保留。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });

    test('A2: Key 解析链经设置仓储——provider 特定槽位命中并传给工厂', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'claude_api_key': 'sk-claude-ok'});

      final provider = FakeLLMProvider(tokens: const ['回复']);
      final factory = _FakeFactory(provider);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: factory,
      );

      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(factory.createCallCount, 1);
      expect(factory.lastProvider, 'claude');
      expect(factory.lastApiKey, 'sk-claude-ok');
      expect(factory.lastBaseUrl, isNull);
      expect(provider.streamGenerateCallCount, 1);
    });

    test('A2: 不支持的 Provider → ChatError「不支持的 Provider: {provider}」',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'claude_api_key': 'sk-x'});
      // 对话模型指向不支持 provider。
      await convRepo.updateConversation(
        conv.id,
        const ConversationsCompanion(modelProvider: Value('unsupported')),
      );

      wireService(FakeLLMProvider(tokens: const ['x']));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message,
          '不支持的 Provider: unsupported');
    });

    test('A2: 对话不存在 → ChatError「对话不存在」，无任何落库', () async {
      wireService(FakeLLMProvider(tokens: const ['x']));
      final events = await service
          .streamReply(conversationId: 999999, content: 'hi')
          .toList();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message, '对话不存在');
      expect(await db.select(db.messages).get(), isEmpty);
    });

    test('AR-2 Falsify 回归: 终态错误路径（对话不存在）整体有界完成'
        '（门先于 close 结算，无门/close 闭环挂起）', () async {
      // S1 红态诊断实证（toList 形态）：`.toList()` 收到 done 后显式取消订阅
      // → onCancel（_stopStreamReply）等待 user 写门；`_runStreamReply` catch
      // 内 `await controller.close()` 的完成又依赖 onCancel 收尾——门若只在
      // finally（close 返回后）结算 → 闭环 → 整体卡满 3s 有界窗口（诊断输出：
      // gate timeout 3s 先于 finally 结算触发）。修复：门在 catch 内、close
      // 之前独立结算。2s 上界断言「有界完成」使未修实现红（3s > 2s）。
      wireService(FakeLLMProvider(tokens: const ['x']));
      await service
          .streamReply(conversationId: 999999, content: 'hi')
          .toList()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail(
                '终态错误路径整体未在有界时间内完成（门/close 闭环挂起）'),
          );
    });

    test('A2 F-45: LLM 业务错误不落部分内容（已产出部分也不落库）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(_TickingProvider(
        tokens: const ['a', 'b'],
        errorAfter: LLMAuthError('claude'),
      ));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(
        [for (final e in events) if (e is ChatToken) e.token],
        ['a', 'b'],
      );
      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message,
          'claude API Key 无效，请在设置中更新');
      // F-45：错误后已产出部分不落库。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });

    test('A2 Falsify: 工厂抛意外异常 → ChatError「生成回复失败: …」且不落部分',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'claude_api_key': 'sk-x'});

      // 工厂 create 抛非领域/非 LLM 异常（未预期路径，对齐桌面 O3）。
      final throwingFactory = _ThrowingFactory(StateError('组装层崩溃'));
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: throwingFactory,
      );

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message, '生成回复失败: Bad state: 组装层崩溃');
      // 意外异常不落部分内容（F-45）；user 已发保留。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });

    test('A2 Falsify: provider 流抛领域错误 → ChatError 领域文案（防御面）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(_RawErrorProvider(ConversationNotFoundError()));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message, '对话不存在');
    });

    test('A2 Falsify: provider 流抛一般异常 → ChatError「生成回复失败: …」',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(_RawErrorProvider(StateError('wire 层未知异常')));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message,
          '生成回复失败: Bad state: wire 层未知异常');
    });

    test('A2 Falsify: 工厂抛 LLMError → ChatError 防御映射（provider 未定 → 基础文案）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'claude_api_key': 'sk-x'});

      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: _ThrowingFactory(LLMAuthError('claude')),
      );

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message,
          'API Key 无效，请在设置中更新');
    });

    test('A2 Falsify: 角色缺失（FK 关闭损坏态）→ ChatError 收口不崩溃', () async {
      // 生产态 FK ON + CASCADE 下孤立对话结构不可达；临时关闭 FK 模拟损坏态，
      // 验证服务层把 CharacterNotFoundError 收口为 ChatError（不崩溃、无部分内容）。
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final orphanConv = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: 999999,
              title: const Value('损坏对话'),
              modelProvider: const Value('claude'),
              modelName: const Value('claude-sonnet-5'),
              createdAt: fakeNow,
              updatedAt: fakeNow,
            ),
          );

      wireService(FakeLLMProvider(tokens: const ['x']));
      final events = await service
          .streamReply(conversationId: orphanConv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatError>());
      expect(
        (events.last as ChatError).message,
        '角色不存在: ${orphanConv.characterId}',
      );
    });

    test('A2 Falsify: 流式中对话被删 → 落库失败收口为 ChatError（无未处理异常）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      wireService(_TickingProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 10),
      ));

      final events = <ChatEvent>[];
      final gotFirstToken = Completer<void>();
      final done = Completer<void>();
      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen(
        (e) {
          events.add(e);
          if (e is ChatToken && !gotFirstToken.isCompleted) {
            gotFirstToken.complete();
          }
        },
        onDone: () => done.complete(),
      );
      await gotFirstToken.future;
      await convRepo.deleteConversation(conv.id); // 流式中删除对话（FK CASCADE）
      await done.future; // 等流收尾（不应有未处理异常）
      await sub.cancel();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message,
          startsWith('生成回复失败: '));
    });

    test('A2: 对话字段空 provider/model → 回退设置默认（Key 链照常）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await convRepo.updateConversation(
        conv.id,
        const ConversationsCompanion(
          modelProvider: Value(''),
          modelName: Value(''),
        ),
      );

      final provider = FakeLLMProvider(tokens: const ['回复']);
      final factory = _FakeFactory(provider);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: factory,
      );

      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(factory.lastProvider, 'claude'); // 回退 default_provider
      expect(provider.lastModel, 'claude-sonnet-5'); // 回退 default_model
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, '回复'),
      ]);
    });

    test('AR-3 B1: conv provider/model 覆盖 → 工厂收到覆盖值（resolver 覆盖序）',
        () async {
      // 既有锚只覆盖「空字段回退默认」；本用例补覆盖序正断言：conv 显式
      // provider/model 非空优先传入工厂（deepseek 同协议 → openai 槽 key）。
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({
        'claude_api_key': 'sk-claude',
        'openai_api_key': 'sk-openai',
      });
      await convRepo.updateConversation(
        conv.id,
        const ConversationsCompanion(
          modelProvider: Value('deepseek'),
          modelName: Value('deepseek-v3'),
        ),
      );

      final provider = FakeLLMProvider(tokens: const ['回复']);
      final factory = _FakeFactory(provider);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: factory,
      );

      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(factory.lastProvider, 'deepseek', reason: 'conv 覆盖优先于缺省');
      expect(factory.lastApiKey, 'sk-openai',
          reason: 'deepseek 同协议 → openai 槽位 key');
      expect(provider.lastModel, 'deepseek-v3', reason: 'conv model 覆盖优先');
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, '回复'),
      ]);
    });
  });

  // ── U-2 温度组装 / max_tokens 透传（工单 03）──

  group('streamReply · 生成参数组装（U-2，工单 03）', () {
    test('角色默认 0.7 + 全局未设 → provider 收到 0.7 / 2048', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final provider = _TickingProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.lastTemperature, 0.7);
      expect(provider.lastMaxTokens, 2048);
    });

    test('角色非 0.7 时全局不生效（角色温度为主）', () async {
      final char = await seedCharacter(temperature: 1.2);
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'temperature': '0.9'});

      final provider = _TickingProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.lastTemperature, 1.2, reason: '角色 1.2 覆盖全局 0.9');
    });

    test('角色 0.7 时全局生效（判定为未覆盖 → 兜底全局值）', () async {
      final char = await seedCharacter(); // temperature 取 DB 默认 0.7
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'temperature': '0.9'});

      final provider = _TickingProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.lastTemperature, 0.9, reason: '角色 0.7 视为未覆盖 → 全局 0.9');
    });

    test('max_tokens 全局 4096 → provider 收到 4096', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'max_tokens': '4096'});

      final provider = _TickingProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.lastMaxTokens, 4096);
    });

    test('regenerate 透传 temperature + max_tokens', () async {
      final char = await seedCharacter(temperature: 1.3);
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'max_tokens': '8192'});
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '你好',
      );
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '旧回复',
      );

      final provider = _TickingProvider(tokens: const ['新回复']);
      wireService(provider);
      await service.regenerate(conversationId: conv.id);

      expect(provider.lastTemperature, 1.3);
      expect(provider.lastMaxTokens, 8192);
    });
  });

  // ── A3 停止 ──

  group('streamReply · 停止（A3）', () {
    test('A3: 取消流订阅 → 已累积部分落库（DB 存纯文本部分内容）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(_TickingProvider(
        tokens: const ['t0', 't1', 't2', 't3', 't4'],
        delay: const Duration(milliseconds: 10),
      ));

      final events = <ChatEvent>[];
      final stopAtT2 = Completer<void>();
      late StreamSubscription<ChatEvent> sub;
      sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen((e) {
        events.add(e);
        if (e is ChatToken && e.token == 't2' && !stopAtT2.isCompleted) {
          stopAtT2.complete();
        }
      });
      await stopAtT2.future; // 等收到 t2
      await sub.cancel(); // 停止：取消流订阅（cancel 在生成器 finally 收尾后返回）

      expect(
        [for (final e in events) if (e is ChatToken) e.token],
        ['t0', 't1', 't2'],
      );
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, 't0t1t2'), // 已累积部分落库
      ]);
    });

    test('A3: 无部分内容 → 仅保留已发 user（不落空 assistant）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(_TickingProvider(
        tokens: const ['a'],
        delay: const Duration(milliseconds: 100),
      ));

      late StreamSubscription<ChatEvent> sub;
      sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen((_) {});
      // AR-2 契约（S2）：`await sub.cancel()` 即闩锁——cancel resolve 保证本轮
      // 在途 user 写已结算，无需再预等（修复前 `_until` 预等是绕开「cancel
      // 完成 ≠ user 已落库」竞差的药方，契约落位后删除）。
      await sub.cancel();

      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });

    test('F3: 发送后立即停止且 provider 解析失败 → 无 add-after-close 未处理异常',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'claude_api_key': 'sk-x'});

      // provider 解析阶段抛 LLM 业务错误（工厂装配）+ 调用方随即取消订阅：
      // 无 isClosed 守卫时 `_runStreamReply` 的 catch handler 对已关闭 controller
      // add 抛 StateError → 未处理异步异常（flutter_test 捕获为失败）。
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: _ThrowingFactory(LLMAuthError('claude')),
      );

      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen((_) {});
      // 立即取消订阅 → onCancel（_stopStreamReply）等待 user 写结算门——user 写
      // 已成功即显式 complete，`await sub.cancel()` 即时放行（S3 契约注）。
      await sub.cancel(); // 立即停止 → onCancel → controller 关闭

      // 让 _runStreamReply 的解析失败 handler 执行窗口；此时 user 写已结算
      // （cancel resolve 保证了），解析失败经 catch → finally 终态兜底一并结算
      // 门（S3 契约注）。无守卫则该 handler 的 controller.add 抛 StateError 被
      // zone 捕获为未处理异常 → 本测试失败。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('A3 Falsify: 停止时对话已被删 → 部分落库失败尽力而为不重抛（无未处理异常）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(_TickingProvider(
        tokens: const ['t0', 't1'],
        delay: const Duration(milliseconds: 10),
      ));

      final gotFirstToken = Completer<void>();
      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen(
        (e) {
          if (e is ChatToken && !gotFirstToken.isCompleted) {
            gotFirstToken.complete();
          }
        },
      );
      await gotFirstToken.future;
      await convRepo.deleteConversation(conv.id); // 流式中删除对话（FK CASCADE）
      // 停止：_stopStreamReply 的 _persistAssistant 落库失败 → 尽力而为吞掉不
      // 重抛（日志记录），cancel 正常完成、无未处理异常（zone 捕获则测试失败）。
      await sub.cancel();

      // 对话已删（消息级联删除）→ 无可观察落库。
      expect(await roleContentsOf(conv.id), isEmpty);
    });

    test('A3: 停滞 provider 流（产出后永久停滞）→ 停止有界完成（.timeout 兜底不'
        '抛错，部分内容仍落库 + 事件流关闭）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      wireService(_StalledProvider(tokens: const ['t0', 't1']));

      final events = <ChatEvent>[];
      final gotLastToken = Completer<void>();
      final stream = service.streamReply(conversationId: conv.id, content: 'hi');
      final sub = stream.listen((e) {
        events.add(e);
        if (e is ChatToken && e.token == 't1' && !gotLastToken.isCompleted) {
          gotLastToken.complete();
        }
      });
      await gotLastToken.future; // 已产出 t0、t1；此后 provider 永久停滞

      // AR-2 契约（S3）：已产出 token ⟹ user 写已落地 ⟹ 门在订阅前已完成，
      // `_stopStreamReply` 门等待即时放行；本测试的 3s 有界兜底针对 providerSub
      // cancel 停滞（F-17），与门等待正交。user 行锚定「cancel resolve 保证
      // user 写已结算」契约。
      // 停止：providerSub.cancel() 在停滞流上无上界挂起（F-17）→ 实现包
      // `.timeout` 兜底后仍应有界完成。断言「有界完成」：超时即 fail（非
      // try/catch 预期 TimeoutException——那测的是抛错方向）。
      await sub.cancel().timeout(
            const Duration(seconds: 6),
            onTimeout: () =>
                fail('停止未在有界时间内完成（providerSub.cancel 无限挂起）'),
          );

      // 已累积部分内容仍按停止语义落库（DB 存纯文本部分内容，不写停止标记）。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, 't0t1'),
      ]);
      // 事件流正常关闭 + 无终态事件：`sub.cancel()` 的 Future 依赖 onCancel
      // （即 _stopStreamReply，收尾含 controller.close()）——其上界完成即证明
      // 停止路径已把事件流关闭收尾；且停止路径不发 ChatDone / ChatError /
      // ChatInterrupted（仅 token 已累积）。单订阅流不可 re-listen，故以
      // 「有界完成 + 无终态事件 + 部分落库」三条锚定事件流关闭语义。
      expect([for (final e in events) if (e is ChatToken) e.token], ['t0', 't1']);
      expect(events.whereType<ChatDone>(), isEmpty);
      expect(events.whereType<ChatError>(), isEmpty);
      expect(events.whereType<ChatInterrupted>(), isEmpty);
    });

    test('B5/F-55 先红后绿: cancel-unwind 断流（cancel 以错误完成）→ 部分落库 + '
        'close 收尾仍执行（zone 零未处理异步异常）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // F-55 真实路径：停滞流 cancel 后 3s 窗口内连接 EOF 以**错误**完成
      // （cancel-unwind 断流）→ providerSub.cancel() 以错误完成。既有实现
      // `cancel().timeout` 未包 catch → 错误穿透 `_stopStreamReply`，部分落库
      // 与 close 收尾被跳过。断言「有界完成 + 部分落库」使未修实现红。
      final provider = _CancelErrorProvider();
      wireService(provider);

      final events = <ChatEvent>[];
      final gotLastToken = Completer<void>();
      late StreamSubscription<ChatEvent> sub;
      sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen((e) {
        events.add(e);
        if (e is ChatToken && e.token == 't1' && !gotLastToken.isCompleted) {
          gotLastToken.complete();
        }
      });
      // 产出 t0、t1（单订阅流在订阅建立前缓冲，随订阅送达）。
      provider.emit('t0');
      provider.emit('t1');
      await gotLastToken.future;

      // 停止：onCancel → _stopStreamReply → providerSub.cancel() 以
      // ReadPhaseInterruptedError 完成（cancel-unwind 断流，F-55 真实路径）。
      // 注：cancel 路径下监听者在 onCancel 前已被 StreamController 移除，
      // onDone 不可观察（A3 既有锚）；事件流关闭语义以「有界完成 + 无终态
      // 事件」锚定——有界完成即证明 _stopStreamReply（含 close 收尾）走完。
      await sub.cancel().timeout(
            const Duration(seconds: 6),
            onTimeout: () =>
                fail('停止未在有界时间内完成（cancel-unwind 断流挂起）'),
          );

      // F-55 结构保证：cancel 以错误完成后收尾仍执行——部分落库（close 收尾
      // 随有界完成隐含锚定）。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, 't0t1'),
      ]);
      expect([for (final e in events) if (e is ChatToken) e.token], ['t0', 't1']);
      expect(events.whereType<ChatDone>(), isEmpty,
          reason: '停止路径不发终态事件');
      expect(events.whereType<ChatInterrupted>(), isEmpty,
          reason: '停止路径不发中断事件');
      // zone 零未处理异步异常：未修实现下 cancel 错误穿透成为未处理异步异常，
      // flutter_test zone 捕获即测试失败（错误经 cancel().timeout 抛出而非
      // 吞为 zone 级——修复后 try/catch 承接 + 收尾完整）。
    });

    test('S1 AR-2 门契约: cancel 不在 user 写结算前 resolve → 放行 → resolve'
        '（Completer 门确定性，零墙钟）', () async {
      // 无 first_mes 角色 → autoGreeting 零写 → 全流程唯一 createMessage =
      // user 写；_GatedMessageRepository 按角色门控：门控 user 写即门控整个
      // 结算信号（停止路径无部分内容不落 assistant）。
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      expect(await messagesOf(conv.id), isEmpty, reason: '零写前提');

      final gatedRepo = _GatedMessageRepository(db, now: () => fakeNow);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: gatedRepo,
        settingsRepository: settingsRepo,
        providerFactory:
            _FakeFactory(FakeLLMProvider(tokens: const ['x'])),
      );
      final release = Completer<void>();
      gatedRepo
        ..gate = release
        ..gateRole = Role.user;

      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen((_) {});
      await gatedRepo.entered.future; // user 写已进入门（挂起待放行）。

      final cancelFuture = sub.cancel(); // 不 await：停止语义启动。
      var cancelResolved = false;
      cancelFuture.then((_) => cancelResolved = true);
      await Future<void>.delayed(Duration.zero); // 事件循环轮转，零墙钟。
      expect(cancelResolved, isFalse,
          reason: '取消（停止）不得在 user 写结算前 resolve（门契约）');

      release.complete(); // 放行 user 写落库。
      await cancelFuture; // 写结算后 cancel resolve。
      expect(cancelResolved, isTrue,
          reason: 'user 写结算后 cancel resolve（有界门等待完成）');

      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'), // 已发 user 可见且唯一。
      ]);
    });

    test('AR-2 Falsify: user 写永不结算（停滞）→ 停止经 3s 有界门超时仍完成'
        '（不挂起、事件流照常收尾）', () async {
      // 门永不完成路径（极端本地 drift 写停滞）：user 写被锻死仓储永久挂起
      // （不 complete 不 error）→ `_stopStreamReply` 门等待靠 3s 有界兜底放行
      // （F-17 同款对齐），事件流收尾不被挂死（6s 上界即 fail）。
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final gatedRepo = _GatedMessageRepository(db, now: () => fakeNow);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: gatedRepo,
        settingsRepository: settingsRepo,
        providerFactory:
            _FakeFactory(FakeLLMProvider(tokens: const ['x'])),
      );
      final blocked = Completer<void>();
      gatedRepo
        ..gate = blocked
        ..gateRole = Role.user;

      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen((_) {});
      await gatedRepo.entered.future; // user 写已挂起（测试在停止完成后放行）。

      await sub.cancel().timeout(
            const Duration(seconds: 6),
            onTimeout: () => fail(
                'user 写停滞时停止未在有界时间内完成（门超时兜底失效）'),
          );

      // 放行停滞写 → `_runStreamReply` 解除挂起（已停止 → 不订阅、无事件、
      // 无未处理异常），user 行最终落库。
      blocked.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });
  });

  // ── A5 断流 ──

  group('streamReply · 断流（A5）', () {
    test('A5: 流终止未到终态（连接异常）→ 已累积部分落库 + 中断事件', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 连接异常 = T02 wire 真实断连信号 [LLMConnectionInterruptedError]
      // （LLM 族子类；R3 seam 契约，见 chat_service.dart 注释——断流判定为
      // 严格子类判型，基类 LLMError 属连接阶段业务错误不误判为断流）。
      wireService(_TickingProvider(
        tokens: const ['a', 'b'],
        errorAfter: LLMConnectionInterruptedError(),
      ));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(
        [for (final e in events) if (e is ChatToken) e.token],
        ['a', 'b'],
      );
      final interrupted = events.last;
      expect(interrupted, isA<ChatInterrupted>());
      expect((interrupted as ChatInterrupted).messageId, isNotNull);
      // 已累积部分落库。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, 'ab'),
      ]);
    });

    test('A5 seam: 真实 wire 断连子类 → 同样走断流分支（部分落库 + 中断事件）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 真实 wire（T02）在流中途抛 [LLMConnectionInterruptedError]（LLMError
      // 子类，非基类）——EOF 未到终态 / 连接重置的共享可区分异常。断流判定须
      // 同时识别子类与基类两种信号，否则落入「LLM 业务错误 F-45 不落部分」。
      wireService(_TickingProvider(
        tokens: const ['a', 'b'],
        errorAfter: LLMConnectionInterruptedError(),
      ));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(
        [for (final e in events) if (e is ChatToken) e.token],
        ['a', 'b'],
      );
      final interrupted = events.last;
      expect(interrupted, isA<ChatInterrupted>());
      expect((interrupted as ChatInterrupted).messageId, isNotNull);
      // 已累积部分落库（断流分支，非 F-45 业务错误分支）。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, 'ab'),
      ]);
    });

    test('A5: 断流无部分内容 → 中断事件 messageId 为 null，不落空 assistant',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 零 token 的基类断流（[LLMConnectionInterruptedError]，B2/B6 锚）在 AR-1
      // 判据单行契约下不再走重试窗口（仅 ConnectPhase 可重试）→ 立即
      // ChatInterrupted(null)；wireServiceWithRetry 仅保证退避注入不拖慢。
      wireServiceWithRetry(_TickingProvider(
        tokens: const [],
        errorAfter: LLMConnectionInterruptedError(),
      ));
      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatInterrupted>());
      expect((events.last as ChatInterrupted).messageId, isNull);
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });

    test('A5 Falsify: 断流且对话被删 → 部分落库失败收口为 ChatError（无未处理异常）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      wireService(_TickingProvider(
        tokens: const ['a', 'b'],
        errorAfter: LLMConnectionInterruptedError(),
        delay: const Duration(milliseconds: 10),
      ));

      final events = <ChatEvent>[];
      final gotFirstToken = Completer<void>();
      final done = Completer<void>();
      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen(
        (e) {
          events.add(e);
          if (e is ChatToken && !gotFirstToken.isCompleted) {
            gotFirstToken.complete();
          }
        },
        onDone: () => done.complete(),
      );
      await gotFirstToken.future;
      await convRepo.deleteConversation(conv.id); // 流式中删除对话（FK CASCADE）
      await done.future;
      await sub.cancel();

      expect(events.last, isA<ChatError>());
      expect((events.last as ChatError).message,
          startsWith('生成回复失败: '));
    });

    test('A5 Falsify: 断流部分落库挂起期间停止 → 内层收口守卫 add-after-close'
        '（无未处理异常）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 门控仓库注入：让断流分支的 _persistAssistant 挂起于 createMessage
      // （仅拦 assistant 角色落库；user 消息与开场白不受影响）。
      final gatedRepo = _GatedMessageRepository(db, now: () => fakeNow);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: gatedRepo,
        settingsRepository: settingsRepo,
        providerFactory: _FakeFactory(_TickingProvider(
          tokens: const ['a'],
          errorAfter: LLMConnectionInterruptedError(),
          delay: const Duration(milliseconds: 10),
        )),
      );
      final release = Completer<void>();
      gatedRepo
        ..gate = release
        ..gateRole = Role.assistant;

      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen((_) {});
      await gatedRepo.entered.future; // 断流分支的部分落库已进入挂起。

      // 挂起期间用户停止 → _stopStreamReply 关闭 controller。
      await sub.cancel();

      // 放行落库：_persistAssistant 返回 → 外层 controller.add(ChatInterrupted)
      // 抛 add-after-close StateError → 转内层 catch。无守卫则该 catch 再次 add
      // 到已关闭 controller → 未处理异步异常（flutter_test zone 判失败）。
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  // ── M6-06 连接阶段自动重试 ──

  group('streamReply · 连接阶段自动重试（M6-06）', () {
    test('首次连接失败（connect drop，无 token）→ 重试成功：总调用 2 次、'
        'ChatDone 收束、user 行仅一条、无重复 token', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final provider = _FaultSequenceProvider(
        tokens: const ['你', '好'],
        // 连接相位叶子（ConnectPhase）是自动重试的唯一可重试面（AR-1 判据
        // 单行契约）；基类/ReadPhase 一律不重试。
        sequence: [ConnectPhaseInterruptedError(), null],
      );
      wireServiceWithRetry(provider,
          retryDelays: const [Duration(milliseconds: 50)]);

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(
        [for (final e in events) if (e is ChatToken) e.token],
        ['你', '好'],
      );
      expect(events.last, isA<ChatDone>());
      expect((events.last as ChatDone).messageId, isNotNull);
      expect(provider.streamGenerateCallCount, 2);
      // 重试安全：user 行仅落库一次（unawaited 重放 provider 段，user 落库早于
      // provider 调用），完整回复落库；token 无重复。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, '你好'),
      ]);
    });

    test('连接失败耗尽（三次均 connect drop，无 token）→ 总调用 3 次，'
        '既有断流语义 ChatInterrupted(null) 收束', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final provider = _FaultSequenceProvider(
        tokens: const [],
        sequence: [
          ConnectPhaseInterruptedError(),
          ConnectPhaseInterruptedError(),
          ConnectPhaseInterruptedError(),
        ],
      );
      wireServiceWithRetry(provider);

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.streamGenerateCallCount, 3,
          reason: '重试 2 次 + 首次 = 共 3 次调用');
      expect(events.last, isA<ChatInterrupted>());
      expect((events.last as ChatInterrupted).messageId, isNull);
      // 无部分内容 → 不落空 assistant；仅已发 user（重试不重复 user 行）。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });

    test('退避间隔按注入序列执行（重试发生在首败之后）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final provider = _FaultSequenceProvider(
        tokens: const ['ok'],
        sequence: [
          ConnectPhaseInterruptedError(),
          ConnectPhaseInterruptedError(),
          null,
        ],
      );
      wireServiceWithRetry(provider,
          retryDelays: const [
            Duration(milliseconds: 50),
            Duration(milliseconds: 80),
          ]);

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(events.last, isA<ChatDone>());
      expect(provider.streamGenerateCallCount, 3);
      // 退避时序：第 2 次调用（首次重试）须在首败 + 50ms 之后，第 3 次同理 + 80ms。
      expect(provider.callGaps, hasLength(2));
      expect(provider.callGaps[0] >= const Duration(milliseconds: 50), isTrue,
          reason: '首次重试未按退避 50ms 等待: ${provider.callGaps[0]}');
      expect(provider.callGaps[1] >= const Duration(milliseconds: 80), isTrue,
          reason: '第二次重试未按退避 80ms 等待: ${provider.callGaps[1]}');
    });

    test('流中已产出至少一个 token 后失败 → 不重试（断流路径，调用 1 次）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 基类断流 + 已产出 token：AR-1 下基类=不可重试兜底信号，无论是否产出
      // token 均不重试（B2 基类回归锚；改造前 `!producedToken` 已拦，语义不变）。
      final provider = _TickingProvider(
        tokens: const ['a', 'b'],
        errorAfter: LLMConnectionInterruptedError(),
        delay: const Duration(milliseconds: 5),
      );
      wireServiceWithRetry(provider);

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.streamGenerateCallCount, 1, reason: '已产出 token 不得重试');
      expect(events.last, isA<ChatInterrupted>());
      // 断流既有语义：已累积部分落库 + ChatInterrupted（非 F-45 业务错误分支）。
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, 'ab'),
      ]);
    });

    test('B2: 流中已产出 token 后 ReadPhaseInterruptedError → 不重试（断流路径，'
        '调用 1 次）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 读取相位叶子（真实 wire 流中途断连/EOF 未终态）已产出 token 后失败：
      // 读段不可重试（AR-1 判据单行——仅 ConnectPhase 可重试）。
      final provider = _TickingProvider(
        tokens: const ['a', 'b'],
        errorAfter: ReadPhaseInterruptedError(),
        delay: const Duration(milliseconds: 5),
      );
      wireServiceWithRetry(provider);

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.streamGenerateCallCount, 1, reason: 'ReadPhase 已产 token 不得重试');
      expect(events.last, isA<ChatInterrupted>());
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
        (Role.assistant, 'ab'),
      ]);
    });

    test('B3/F-52 先红后绿: 零 token 基类 LLMConnectionInterruptedError → 不重试'
        '（callCount==1；基类 = 不可重试断流兜底信号）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 基类断流在改造前属「首 token 前」重试窗口（!producedToken 成立 +
      // _isConnectionDrop 成立）→ 会重试（最坏同一 user 内容多次 billable
      // POST，F-52 计费 gap）；改造后重试判据收束为 ConnectPhase 单行类型契约，
      // 基类不再重试。断言 callCount==1 使「仍会重试」的实现红。
      final provider = _FaultSequenceProvider(
        tokens: const [],
        sequence: [LLMConnectionInterruptedError()],
      );
      wireServiceWithRetry(provider);

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.streamGenerateCallCount, 1, reason: '零 token 基类不得重试（F-52）');
      expect(events.last, isA<ChatInterrupted>());
      expect((events.last as ChatInterrupted).messageId, isNull,
          reason: '零部分内容不落空 assistant');
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'), // user 行唯一：≤1 次 billable 发送
      ]);
    });

    test('B4/Q1b: 零 token ReadPhaseInterruptedError（首 token 前 idle / 空 200 体'
        'EOF）→ 不重试，ChatInterrupted(null)，user 行唯一', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 首 token 前 idle（已收 200 后静默）：wire idle 恒编码 read 相位
      // （状态码必已收到）→ 零 token ReadPhase 不可重试（行为变更点 B1）。
      final provider = _FaultSequenceProvider(
        tokens: const [],
        sequence: [ReadPhaseInterruptedError()],
      );
      wireServiceWithRetry(provider);

      final events = await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.streamGenerateCallCount, 1, reason: 'read 相位失败不得重试');
      expect(events.last, isA<ChatInterrupted>());
      expect((events.last as ChatInterrupted).messageId, isNull);
      expect(await roleContentsOf(conv.id), [
        (Role.user, 'hi'),
      ]);
    });

    test('状态码/业务错误映射（Auth/RateLimit/Timeout/BadRequest/ContentFilter）'
        '→ 不重试，走 ChatError', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final businessErrors = <LLMError>[
        LLMAuthError('claude'),
        LLMRateLimitError('claude'),
        LLMTimeoutError('claude'),
        LLMBadRequestError('claude', '参数非法'),
        LLMContentFilterError('claude'),
      ];
      for (final llmError in businessErrors) {
        final provider = _FaultSequenceProvider(
          tokens: const [],
          sequence: [llmError],
        );
        wireServiceWithRetry(provider);
        final events = await service
            .streamReply(conversationId: conv.id, content: 'hi')
            .toList();

        expect(provider.streamGenerateCallCount, 1,
            reason: '业务错误 ${llmError.runtimeType} 不得重试');
        expect(events.last, isA<ChatError>(),
            reason: '业务错误 ${llmError.runtimeType} → ChatError（F-45 不落部分）');
      }
    });

    test('Falsify: 重试退避窗口内停止 → 不再订阅，无 Timer 泄漏、无未处理异常',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final firstFailure = Completer<void>();
      final provider = _FaultSequenceProvider(
        tokens: const [],
        sequence: [
          ConnectPhaseInterruptedError(),
          ConnectPhaseInterruptedError(),
        ],
        onFirstFailure: firstFailure,
      );
      wireServiceWithRetry(provider,
          retryDelays: const [Duration(milliseconds: 100)]);

      final events = <ChatEvent>[];
      final sub = service
          .streamReply(conversationId: conv.id, content: 'hi')
          .listen(events.add);
      await firstFailure.future; // 首败已发生（重试 handler 即将进入退避窗口）。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel(); // 停止：取消挂起的重试窗口。

      // 越过注入退避周期（100ms）后：重试不得再订阅（callCount 保持 1），
      // 无事件产出 + flutter_test zone 捕获未处理异步异常即判失败。
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(provider.streamGenerateCallCount, 1,
          reason: '停止后不得继续重试订阅');
      expect(events, isEmpty, reason: '重试窗口内停止不得产出任何事件');
    });
  });

  // ── A4 重生成 ──

  group('regenerate（A4）', () {
    Future<(Character, Conversation, Message, Message)> seedConversationWithReply({
      String reply = '旧回复',
    }) async {
      final char = await seedCharacter(firstMes: '开场。');
      final conv = await seedConversation(char.id);
      final userMsg = await sendUserMessage(conv.id, '你好');
      final assistantMsg = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: reply,
      );
      return (char, conv, userMsg, assistantMsg);
    }

    test('A4: 成功 → 候选追加（消息数不变，active 切最新）', () async {
      final (_, conv, userMsg, oldAssistant) =
          await seedConversationWithReply();
      final provider = FakeLLMProvider(tokens: const ['新回复']);
      wireService(provider);

      final result = await service.regenerate(conversationId: conv.id);

      expect(result.reply, '新回复');
      expect(result.conversationId, conv.id);
      // 候选归属消息 id = 目标行（候选追加不删行）。
      expect(result.messageId, oldAssistant.id);
      expect(result.replacedMessageId, oldAssistant.id);
      expect(result.swipeIndex, 1, reason: '候选 0 = 原回复播种，新回复 = index 1');
      // 消息数不变：1 assistant + N 候选；messages.content 跟随激活候选。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新回复'),
      ]);
      expect(await swipeContentsOf(oldAssistant.id), ['旧回复', '新回复']);
      // 重生成走 non-streaming generate（非流式）。
      expect(provider.generateCallCount, 1);
      expect(provider.streamGenerateCallCount, 0);
    });

    test('A4: 组装走 append_current_input=False——末条为触发 user，无当前输入',
        () async {
      final (_, conv, userMsg, _) = await seedConversationWithReply();
      final provider = FakeLLMProvider(tokens: const ['新回复']);
      wireService(provider);

      await service.regenerate(conversationId: conv.id);

      final sent = provider.lastMessages!;
      expect(sent.last, LlmMessage(role: 'user', content: userMsg.content));
      // 无幽灵 user：触发 user 在列表中仅出现一次。
      expect(
        sent.where((m) => m == LlmMessage(role: 'user', content: '你好')),
        hasLength(1),
      );
    });

    test('A4: 重生成锚定末条 assistant；显式 messageId 锚定对应目标', () async {
      final (_, conv, userMsg, oldAssistant) =
          await seedConversationWithReply();
      // 追加第二轮 user + assistant。
      await sendUserMessage(conv.id, '第二问');
      final second = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '第二答',
      );
      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);

      // 缺省：末条 assistant（第二答）为目标 → 候选追加，第二答行保留。
      await service.regenerate(conversationId: conv.id);
      expect(await swipeContentsOf(second.id), ['第二答', '新答']);
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
        (Role.user, '第二问'),
        (Role.assistant, '新答'), // active 切到新候选
      ]);

      // 显式：目标 = 第一条 assistant（旧回复）→ 候选挂旧回复，后续不截断。
      provider.lastMessages = null;
      final result = await service.regenerate(
          conversationId: conv.id, messageId: oldAssistant.id);
      expect(result.reply, '新答');
      expect(result.messageId, oldAssistant.id);
      expect(await swipeContentsOf(oldAssistant.id), ['旧回复', '新答']);
      // 时间线无截断：第二答行保留；其 content 仍为第一次缺省 regenerate
      // 置 active 的「新答」（显式目标 = 旧回复，不触碰第二答行）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新答'), // 旧回复行 active 切到新答
        (Role.user, '第二问'),
        (Role.assistant, '新答'), // 第二答行保留（content = 缺省路径激活候选）
      ]);
      // 触发源 user（你好）仍为末条历史（append_current_input=False）。
      expect(provider.lastMessages!.last,
          LlmMessage(role: 'user', content: userMsg.content));
    });

    test('F-64: RegenerateResult 缺省路径 = 末条 assistant（messageId/'
        'replacedMessageId = 候选归属行 id + swipeIndex=1）', () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      // 追加第二轮 user + assistant → 末条 = 第二答。
      await sendUserMessage(conv.id, '第二问');
      final second = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '第二答',
      );
      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);

      final result = await service.regenerate(conversationId: conv.id);

      expect(result.replacedMessageId, second.id,
          reason: '缺省目标 = 末条 assistant（候选归属行 id）');
      expect(result.messageId, second.id, reason: '候选追加不删行 → messageId = 目标行');
      expect(result.swipeIndex, 1);
      expect(await swipeContentsOf(second.id), ['第二答', '新答']);
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
        (Role.user, '第二问'),
        (Role.assistant, '新答'),
      ]);
    });

    test('F-64: RegenerateResult 显式路径 = 指定 messageId 目标行'
        '（非末条目标同样候选追加、后续保留）', () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      // 追加第二轮 user + assistant（目标 = 第一条 assistant，非末条）。
      await sendUserMessage(conv.id, '第二问');
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '第二答',
      );
      wireService(FakeLLMProvider(tokens: const ['新答']));

      final result = await service.regenerate(
          conversationId: conv.id, messageId: oldAssistant.id);

      expect(result.replacedMessageId, oldAssistant.id,
          reason: '显式目标 = 候选归属行 id');
      expect(result.messageId, oldAssistant.id);
      expect(result.swipeIndex, 1);
      expect(await swipeContentsOf(oldAssistant.id), ['旧回复', '新答']);
      // 后续（第二问/第二答）保留：显式非末条目标候选追加不截断。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新答'),
        (Role.user, '第二问'),
        (Role.assistant, '第二答'),
      ]);
    });

    test('A4: LLM 失败（业务错误）→ 旧消息保留（延迟删除：失败不删行）',
        () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      final provider =
          FakeLLMProvider(tokens: const [], error: LLMAuthError('claude'));
      wireService(provider);

      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(isA<LLMAuthError>()),
      );
      // 时间线不变：旧回复原样保留；无候选追加（失败零副作用）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
      ]);
      expect(await messageRepo.listSwipes(oldAssistant.id), isEmpty);
    });

    test('A4: LLM 失败（连接中断信号）→ 旧消息保留', () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      // T02 wire 共享断连信号 [LLMConnectionInterruptedError]（LLM 族子类）。
      final provider = FakeLLMProvider(
          tokens: const [],
          error: LLMConnectionInterruptedError());
      wireService(provider);

      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(isA<LLMError>()),
      );
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
      ]);
      expect(await messageRepo.listSwipes(oldAssistant.id), isEmpty,
          reason: '生成失败不落候选');
    });

    test('F1: 重生成进行中并发新消息 → 新消息保留（候选追加不删行）',
        () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      final provider = _HoldableProvider(reply: '新回复');
      wireService(provider);

      // 网络 generate 挂起（目标已解析、未落库）。
      final regenerating = service.regenerate(conversationId: conv.id);
      await provider.started.future;

      // 生成期间并发发送新 user 消息。
      final concurrent = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '并发新消息',
      );
      expect(concurrent.id, greaterThan(oldAssistant.id));

      provider.gate.complete(); // 放行生成 → 候选追加
      final result = await regenerating;

      expect(result.reply, '新回复');
      // 无「有界删旧」：目标行保留（active 切新回复）、并发新 user 保留在
      // 目标行之后（候选追加不删行、不重排）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新回复'), // 目标行 content 跟随激活候选
        (Role.user, '并发新消息'),
      ]);
      expect(await swipeContentsOf(oldAssistant.id), ['旧回复', '新回复']);
    });

    test('F4: 并发双触发 regenerate → 第二次拒绝「重生成进行中」，第一次结果保留',
        () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      final provider = _HoldableProvider(reply: '新回复');
      wireService(provider);

      final first = service.regenerate(conversationId: conv.id); // 挂起
      await provider.started.future; // 第一次已进入网络阶段（in-flight）

      // 第二次调用 in-flight 期间直接拒绝（双触发守卫）。
      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(isA<RegenerateBusyError>()),
      );

      provider.gate.complete();
      final result = await first;
      expect(result.reply, '新回复');
      // 第一次结果保留（候选追加，无第二次写）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新回复'),
      ]);
      expect(await swipeContentsOf(oldAssistant.id), ['旧回复', '新回复']);
    });

    test('A4: 未配置 Key → 领域错误，旧消息保留', () async {
      await secretStore.delete(SecretStore.claudeApiKeySlot); // 清空默认 Key
      final (_, conv, _, _) = await seedConversationWithReply();
      wireService(FakeLLMProvider(tokens: const ['x'])); // factory 不应被调用

      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(isA<ApiKeyMissingError>()),
      );
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
      ]);
    });

    test('A4: 无触发源 user（仅开场白）→ 拒绝「没有可重生成的用户消息」',
        () async {
      final char = await seedCharacter(firstMes: '开场。');
      final conv = await seedConversation(char.id); // 仅 assistant 开场白

      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(predicate((e) =>
            e is InvalidRegenerateTargetError &&
            e.message == '没有可重生成的用户消息')),
      );
      expect(await messagesOf(conv.id), hasLength(1)); // 开场白保留
    });

    test('A4: 对话中无 assistant → 拒绝「没有可重生成的 AI 回复」', () async {
      final char = await seedCharacter(); // 无开场白
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '只有用户消息');

      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(predicate((e) =>
            e is InvalidRegenerateTargetError &&
            e.message == '没有可重生成的 AI 回复')),
      );
    });

    test('A4: 显式目标不存在 → 拒绝「消息不存在」', () async {
      final (_, conv, _, _) = await seedConversationWithReply();
      wireService(FakeLLMProvider(tokens: const ['x']));

      await expectLater(
        service.regenerate(conversationId: conv.id, messageId: 999999),
        throwsA(isA<MessageNotFoundError>()),
      );
    });

    test('A4: 显式目标非 assistant（user）→ 拒绝「只能重生成 AI 回复」', () async {
      final (_, conv, userMsg, _) = await seedConversationWithReply();
      wireService(FakeLLMProvider(tokens: const ['x']));

      await expectLater(
        service.regenerate(conversationId: conv.id, messageId: userMsg.id),
        throwsA(predicate((e) =>
            e is InvalidRegenerateTargetError &&
            e.message == '只能重生成 AI 回复')),
      );
    });

    test('A4: 对话不存在 → 拒绝「对话不存在」', () async {
      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.regenerate(conversationId: 999999),
        throwsA(isA<ConversationNotFoundError>()),
      );
    });

    test('A4 Falsify: 角色缺失（FK 关闭损坏态）→ regenerate 拒绝 CharacterNotFoundError',
        () async {
      // 生产态 FK ON + CASCADE 下孤立对话结构不可达；临时关闭 FK 模拟损坏态，
      // 验证 regenerate 在角色缺失时抛 CharacterNotFoundError（旧消息保留、无半截断）。
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final orphanConv = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: 999999,
              title: const Value('损坏对话'),
              modelProvider: const Value('claude'),
              modelName: const Value('claude-sonnet-5'),
              createdAt: fakeNow,
              updatedAt: fakeNow,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: orphanConv.id,
              role: Role.user,
              content: '你好',
              createdAt: fakeNow,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: orphanConv.id,
              role: Role.assistant,
              content: '旧回复',
              createdAt: fakeNow,
            ),
          );

      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.regenerate(conversationId: orphanConv.id),
        throwsA(predicate(
            (e) => e is CharacterNotFoundError && e.message.contains('角色不存在'))),
      );
      // 旧消息保留（组装/解析阶段抛错，未触碰 DB）。
      final remaining = await (db.select(db.messages)
            ..where(($MessagesTable t) =>
                t.conversationId.equals(orphanConv.id)))
          .get();
      expect(remaining, hasLength(2));
    });

    test('S6: 重生成不再全量拉取——缺省/显式均 3 次定位读（getMessages=0）',
        () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      // 追加第二轮 user + assistant（缺省目标 = 第二答；显式目标 = 旧回复）。
      await sendUserMessage(conv.id, '第二问');
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '第二答',
      );
      final counting = _CountingMessageRepository(db, now: () => fakeNow);
      messageRepo = counting;
      wireService(FakeLLMProvider(tokens: const ['新答']));

      // 缺省路径：目标解析 = lastAssistantMessage。
      await service.regenerate(conversationId: conv.id);
      expect(counting.getMessagesCalls, 0, reason: '不再全量拉取');
      expect(counting.lastAssistantMessageCalls, 1);
      expect(counting.lastUserMessageBeforeCalls, 1);
      expect(counting.messagesBeforeCalls, 1);
      expect(counting.messageByIdCalls, 0);

      // 显式路径：目标解析 = messageById（归属校验）。
      counting
        ..getMessagesCalls = 0
        ..lastAssistantMessageCalls = 0
        ..lastUserMessageBeforeCalls = 0
        ..messagesBeforeCalls = 0
        ..messageByIdCalls = 0;
      await service.regenerate(
          conversationId: conv.id, messageId: oldAssistant.id);
      expect(counting.getMessagesCalls, 0, reason: '显式路径同样不再全量拉取');
      expect(counting.messageByIdCalls, 1);
      expect(counting.lastAssistantMessageCalls, 0);
      expect(counting.lastUserMessageBeforeCalls, 1);
      expect(counting.messagesBeforeCalls, 1);
    });
  });

  // ── MS-02 continue 续写 ──

  group('continueReply（MS-02）', () {
    Future<(Character, Conversation, Message, Message)> seedConversationWithReply({
      String reply = '原回复',
    }) async {
      final char = await seedCharacter(firstMes: '开场。');
      final conv = await seedConversation(char.id);
      final userMsg = await sendUserMessage(conv.id, '你好');
      final assistantMsg = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: reply,
      );
      return (char, conv, userMsg, assistantMsg);
    }

    test('成功 → 消息条数不变，内容 = 原 active 内容 + 续写片段（新候选激活）',
        () async {
      final (_, conv, _, target) = await seedConversationWithReply();
      final provider = FakeLLMProvider(tokens: const ['（接续）']);
      wireService(provider);

      final result = await service.continueReply(conversationId: conv.id);

      expect(result.reply, '原回复（接续）');
      expect(result.messageId, target.id, reason: '续写不新增消息行');
      expect(result.replacedMessageId, target.id);
      expect(result.swipeIndex, 1, reason: '候选 0 = 原内容播种，续写 = index 1');
      // 不产生新 user 消息：消息条数不变；active 切到续写候选。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '原回复（接续）'),
      ]);
      expect(await swipeContentsOf(target.id), ['原回复', '原回复（接续）']);
      expect(provider.generateCallCount, 1);
      expect(provider.streamGenerateCallCount, 0);
    });

    test('触发形态：尾随 user = 续写指令 + 原消息末段；历史含目标（桌面 '
        'id <= target.id 对齐）', () async {
      final (_, conv, _, target) =
          await seedConversationWithReply(reply: '短回复');
      final provider = FakeLLMProvider(tokens: const ['续']);
      wireService(provider);

      await service.continueReply(conversationId: conv.id);

      final sent = provider.lastMessages!;
      final trigger = sent.last;
      expect(trigger.role, 'user', reason: '续写触发为尾随 user 消息（非 system）');
      expect(trigger.content, contains('（请继续书写上一条 AI 回复'));
      expect(trigger.content, endsWith('\n短回复'));
      // 被续写消息进入上下文（桌面 history_limit 含边界语义）。
      expect(
        sent.where((m) => m == LlmMessage(role: 'assistant', content: '短回复')),
        hasLength(1),
      );
    });

    test('末段截断：超长原内容取末 200 字符作为续写锚点', () async {
      final head = List.filled(60, 'a').join();
      final tail = List.filled(200, 'b').join();
      final (_, conv, _, _) =
          await seedConversationWithReply(reply: '$head$tail');
      final provider = FakeLLMProvider(tokens: const ['续']);
      wireService(provider);

      await service.continueReply(conversationId: conv.id);

      final trigger = provider.lastMessages!.last;
      expect(trigger.content, endsWith('\n$tail'));
      expect(trigger.content, isNot(contains('a')), reason: '锚点只含末 200 字符');
    });

    test('断流/停止部分落库消息（普通 assistant 行）→ continue 直接候选追加',
        () async {
      // 停止/断流路径落库的部分内容即普通 assistant 行（零特殊分支）。
      final (_, conv, _, target) =
          await seedConversationWithReply(reply: '部分回复');
      final provider = FakeLLMProvider(tokens: const ['续']);
      wireService(provider);

      final result = await service.continueReply(conversationId: conv.id);

      expect(result.reply, '部分回复续');
      expect(await swipeContentsOf(target.id), ['部分回复', '部分回复续']);
    });

    test('LLM 失败 → 零落库（无候选、原内容零改动）', () async {
      final (_, conv, _, target) = await seedConversationWithReply();
      final provider =
          FakeLLMProvider(tokens: const [], error: LLMAuthError('claude'));
      wireService(provider);

      await expectLater(
        service.continueReply(conversationId: conv.id),
        throwsA(isA<LLMAuthError>()),
      );
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '原回复'),
      ]);
      expect(await messageRepo.listSwipes(target.id), isEmpty);
    });

    test('空续写（LLM 零产出片段）→ no-op：swipeIndex == -1、无重复候选、'
        '原内容零改动', () async {
      final (_, conv, _, target) = await seedConversationWithReply();
      // generate 返回纯空白 → trim 后空 → 不追加候选（防 base + '' = base 重复行）。
      final provider = FakeLLMProvider(tokens: const ['   ']);
      wireService(provider);

      final result = await service.continueReply(conversationId: conv.id);

      expect(result.reply, '原回复');
      expect(result.swipeIndex, -1, reason: '-1 = 未追加候选（no-op 哨兵）');
      expect(result.messageId, target.id);
      expect(await messageRepo.listSwipes(target.id), isEmpty);
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '原回复'),
      ]);
    });

    test('显式 messageId = 末条 assistant → 通过', () async {
      final (_, conv, _, target) = await seedConversationWithReply();
      final provider = FakeLLMProvider(tokens: const ['续']);
      wireService(provider);

      final result = await service.continueReply(
          conversationId: conv.id, messageId: target.id);

      expect(result.messageId, target.id);
      expect(await swipeContentsOf(target.id), ['原回复', '原回复续']);
    });

    test('显式 messageId 非末条（旧 assistant）→ 拒绝', () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      // 追加第二轮 user + assistant → 旧回复非末条。
      await sendUserMessage(conv.id, '第二问');
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '第二答',
      );
      wireService(FakeLLMProvider(tokens: const ['x']));

      await expectLater(
        service.continueReply(
            conversationId: conv.id, messageId: oldAssistant.id),
        throwsA(isA<InvalidRegenerateTargetError>()),
      );
      expect(await messageRepo.listSwipes(oldAssistant.id), isEmpty);
    });

    test('末条非 assistant（末条 user）→ 拒绝', () async {
      final (_, conv, _, _) = await seedConversationWithReply();
      await sendUserMessage(conv.id, '追问');
      wireService(FakeLLMProvider(tokens: const ['x']));

      await expectLater(
        service.continueReply(conversationId: conv.id),
        throwsA(isA<InvalidRegenerateTargetError>()),
      );
    });

    test('无 assistant（仅 user）→ 拒绝', () async {
      final char = await seedCharacter(); // 无开场白
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '只有用户消息');

      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.continueReply(conversationId: conv.id),
        throwsA(isA<InvalidRegenerateTargetError>()),
      );
    });

    test('显式 messageId 不存在 → 拒绝「消息不存在」', () async {
      final (_, conv, _, _) = await seedConversationWithReply();
      wireService(FakeLLMProvider(tokens: const ['x']));

      await expectLater(
        service.continueReply(conversationId: conv.id, messageId: 999999),
        throwsA(isA<MessageNotFoundError>()),
      );
    });

    test('对话不存在 → 拒绝「对话不存在」', () async {
      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.continueReply(conversationId: 999999),
        throwsA(isA<ConversationNotFoundError>()),
      );
    });

    test('未配置 Key → 领域错误，零落库', () async {
      await secretStore.delete(SecretStore.claudeApiKeySlot); // 清空默认 Key
      final (_, conv, _, _) = await seedConversationWithReply();
      wireService(FakeLLMProvider(tokens: const ['x'])); // factory 不应被调用

      await expectLater(
        service.continueReply(conversationId: conv.id),
        throwsA(isA<ApiKeyMissingError>()),
      );
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '原回复'),
      ]);
    });

    test('并发守卫：同对话 in-flight 期间第二次 continue → 拒绝'
        '「重生成进行中」', () async {
      final (_, conv, _, _) = await seedConversationWithReply();
      final provider = _HoldableProvider(reply: '续');
      wireService(provider);

      final first = service.continueReply(conversationId: conv.id); // 挂起
      await provider.started.future;

      await expectLater(
        service.continueReply(conversationId: conv.id),
        throwsA(isA<RegenerateBusyError>()),
      );

      provider.gate.complete();
      final result = await first;
      expect(result.reply, '原回复续');
    });

    test('Falsify: 角色缺失（FK 关闭损坏态）→ continueReply 拒绝'
        'CharacterNotFoundError 零落库', () async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final orphanConv = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: 999999,
              title: const Value('损坏对话'),
              modelProvider: const Value('claude'),
              modelName: const Value('claude-sonnet-5'),
              createdAt: fakeNow,
              updatedAt: fakeNow,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: orphanConv.id,
              role: Role.user,
              content: '你好',
              createdAt: fakeNow,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: orphanConv.id,
              role: Role.assistant,
              content: '旧回复',
              createdAt: fakeNow,
            ),
          );

      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.continueReply(conversationId: orphanConv.id),
        throwsA(predicate(
            (e) => e is CharacterNotFoundError && e.message.contains('角色不存在'))),
      );
      final remaining = await (db.select(db.messages)
            ..where(($MessagesTable t) =>
                t.conversationId.equals(orphanConv.id)))
          .get();
      expect(remaining, hasLength(2), reason: '组装阶段抛错，零落库');
    });

    test('末段锚防劈代理对：窗口起点为低代理 → 排除后无孤立代理'
        '（F-114 先例）', () async {
      // emoji（高+低代理对）落在窗口起点：text = emoji + 'b'*199，
      // cut 起点 = text[1] 恰为低代理。
      final tail = List.filled(199, 'b').join();
      final (_, conv, _, _) =
          await seedConversationWithReply(reply: '\u{1F600}$tail');
      final provider = FakeLLMProvider(tokens: const ['续']);
      wireService(provider);

      await service.continueReply(conversationId: conv.id);

      final trigger = provider.lastMessages!.last;
      expect(trigger.content, endsWith('\n$tail'));
      expect(trigger.content, isNot(contains('\uFFFD')),
          reason: '窗口开头的孤立低代理被排除');
    });
  });

  group('editAndRegenerate（MS-03 编辑重发）', () {
    test('成功 → 替换 content + 物理截断后续（候选/thought 级联）'
        '+ 新 assistant 落库（swipeIndex=0）', () async {
      final (char, conv, user1, _, _, asst2) =
          await seedFourMessageConversation();
      // 被截断 assistant 带候选 + 内心独白（级联目标）。
      await messageRepo.addSwipe(asst2.id, '二候选', makeActive: false);
      await db.into(db.innerThoughts).insert(InnerThoughtsCompanion.insert(
            characterId: char.id,
            messageId: asst2.id,
            content: '独白',
            createdAt: fakeNow,
          ));
      final provider = FakeLLMProvider(tokens: const ['新的回复']);
      wireService(provider);

      final result = await service.editAndRegenerate(
        conversationId: conv.id,
        messageId: user1.id,
        newContent: '修正后的问题',
      );

      expect(result.reply, '新的回复');
      expect(result.conversationId, conv.id);
      expect(result.messageId, isNot(user1.id),
          reason: '新 assistant 消息，非被编辑 user 行');
      expect(result.replacedMessageId, result.messageId);
      expect(result.swipeIndex, 0,
          reason: '新 assistant 候选 0 = 回复本体（不实际 addSwipe）');
      // 时间线：开场白 + 修正 user + 新 assistant（后续物理截断删净）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '修正后的问题'),
        (Role.assistant, '新的回复'),
      ]);
      // 被截断 assistant 的候选 / 独白 FK CASCADE 级联删除。
      expect(await messageRepo.listSwipes(asst2.id), isEmpty,
          reason: '截断后续消息 → 其候选随消息级联删');
      expect(await innerThoughtCountFor(asst2.id), 0,
          reason: 'InnerThoughts.messageId CASCADE 保持（SR-28）');
      expect(provider.generateCallCount, 1);
      expect(provider.streamGenerateCallCount, 0,
          reason: '编辑重发走 non-streaming generate');
    });

    test('组装契约：generate 收到修正后内容（末条 user），后续不进上下文', () async {
      final (_, conv, user1, _, _, _) = await seedFourMessageConversation();
      final provider = FakeLLMProvider(tokens: const ['新的回复']);
      wireService(provider);

      await service.editAndRegenerate(
        conversationId: conv.id,
        messageId: user1.id,
        newContent: '修正后的问题',
      );

      final sent = provider.lastMessages!;
      expect(sent.last, LlmMessage(role: 'user', content: '修正后的问题'));
      expect(sent.where((m) => m.content.contains('第二轮问')), isEmpty,
          reason: '被截断后续（第二轮问/答）不进上下文');
      expect(
        sent.where(
            (m) => m == LlmMessage(role: 'user', content: '修正后的问题')),
        hasLength(1),
        reason: '无幽灵 user：修正后 user 仅出现一次',
      );
    });

    test('编辑末条 user → 之前消息保留，仅替换目标 + 截断其后 + 新回复', () async {
      final (_, conv, _, _, user2, _) = await seedFourMessageConversation();
      final provider = FakeLLMProvider(tokens: const ['新第二轮答']);
      wireService(provider);

      final result = await service.editAndRegenerate(
        conversationId: conv.id,
        messageId: user2.id,
        newContent: '修正后第二轮问',
      );

      expect(result.reply, '新第二轮答');
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '第一轮问'),
        (Role.assistant, '第一轮答'),
        (Role.user, '修正后第二轮问'),
        (Role.assistant, '新第二轮答'),
      ]);
    });

    test('目标不存在 / 跨对话 → MessageNotFoundError 且零副作用', () async {
      final (_, conv, _, _, _, _) = await seedFourMessageConversation();
      final otherChar = await seedCharacter();
      final otherConv = await seedConversation(otherChar.id);
      final otherMsg = await sendUserMessage(otherConv.id, '他对话消息');
      final provider = FakeLLMProvider(tokens: const ['x']);
      wireService(provider);
      final before = await roleContentsOf(conv.id);

      await expectLater(
        service.editAndRegenerate(
          conversationId: conv.id,
          messageId: 999999,
          newContent: '改',
        ),
        throwsA(isA<MessageNotFoundError>()),
      );
      await expectLater(
        service.editAndRegenerate(
          conversationId: conv.id,
          messageId: otherMsg.id, // 归属校验：他对话 id 视为不存在
          newContent: '改',
        ),
        throwsA(isA<MessageNotFoundError>()),
      );
      expect(await roleContentsOf(conv.id), before);
      expect(provider.generateCallCount, 0, reason: '目标解析失败未触发生成');
    });

    test('目标非 user（assistant）→「只能编辑用户消息」且零副作用', () async {
      final (_, conv, _, asst1, _, _) = await seedFourMessageConversation();
      final provider = FakeLLMProvider(tokens: const ['x']);
      wireService(provider);
      final before = await roleContentsOf(conv.id);
      final beforeSwipes = await messageRepo.listSwipes(asst1.id);

      await expectLater(
        service.editAndRegenerate(
          conversationId: conv.id,
          messageId: asst1.id,
          newContent: '改',
        ),
        throwsA(predicate((e) =>
            e is InvalidRegenerateTargetError &&
            e.message == '只能编辑用户消息')),
      );
      expect(await roleContentsOf(conv.id), before,
          reason: 'content 未改、后续未截断（零副作用）');
      expect(await messageRepo.listSwipes(asst1.id), beforeSwipes);
      expect(provider.generateCallCount, 0);
    });

    test('生成失败 → content 已替换 + 后续已截断（锁定语义），无新回复，'
        '文案经 chatErrorMessage 单源映射', () async {
      final (_, conv, user1, _, _, _) = await seedFourMessageConversation();
      final provider = FakeLLMProvider(
          tokens: const [], error: LLMAuthError('claude'));
      wireService(provider);

      await expectLater(
        service.editAndRegenerate(
          conversationId: conv.id,
          messageId: user1.id,
          newContent: '修正后的问题',
        ),
        throwsA(isA<LLMAuthError>()),
      );

      // 截断后状态即未来状态：替换 + 截断保留、无新回复（用户可再 regenerate）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '修正后的问题'),
      ]);
      // 失败文案经 chatErrorMessage 单源（llmErrorResponse 映射）。
      expect(
        chatErrorMessage(LLMAuthError('claude'), providerName: 'claude'),
        'claude API Key 无效，请在设置中更新',
      );
    });

    test('未配置 Key → ApiKeyMissingError；替换 + 截断保留（未来状态）',
        () async {
      await secretStore.delete(SecretStore.claudeApiKeySlot);
      final (_, conv, user1, _, _, _) = await seedFourMessageConversation();
      wireService(FakeLLMProvider(tokens: const ['x']));

      await expectLater(
        service.editAndRegenerate(
          conversationId: conv.id,
          messageId: user1.id,
          newContent: '修正后的问题',
        ),
        throwsA(isA<ApiKeyMissingError>()),
      );
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '修正后的问题'),
      ]);
    });

    test('F4 并发守卫：编辑重发与 regenerate 共享 in-flight（双向拒绝）',
        () async {
      final (_, conv, user1, _, _, _) = await seedFourMessageConversation();
      // 方向一：regenerate 挂起期间 editAndRegenerate 拒绝。
      final hold1 = _HoldableProvider(reply: '新回复');
      wireService(hold1);
      final regenerating = service.regenerate(conversationId: conv.id);
      await hold1.started.future;
      await expectLater(
        service.editAndRegenerate(
          conversationId: conv.id,
          messageId: user1.id,
          newContent: '修正后的问题',
        ),
        throwsA(isA<RegenerateBusyError>()),
      );
      hold1.gate.complete();
      await regenerating;

      // 方向二：editAndRegenerate 挂起期间 regenerate 拒绝。
      final hold2 = _HoldableProvider(reply: '编辑回复');
      wireService(hold2);
      final editing = service.editAndRegenerate(
        conversationId: conv.id,
        messageId: user1.id,
        newContent: '修正后的问题',
      );
      await hold2.started.future;
      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(isA<RegenerateBusyError>()),
      );
      hold2.gate.complete();
      final result = await editing;
      expect(result.reply, '编辑回复');
    });

    test('Falsify: 对话不存在 → ConversationNotFoundError 且零副作用', () async {
      final (_, conv, _, _, _, _) = await seedFourMessageConversation();
      wireService(FakeLLMProvider(tokens: const ['x']));
      final before = await roleContentsOf(conv.id);

      await expectLater(
        service.editAndRegenerate(
          conversationId: 999999,
          messageId: 1,
          newContent: '改',
        ),
        throwsA(isA<ConversationNotFoundError>()),
      );
      expect(await roleContentsOf(conv.id), before,
          reason: '他对话不受影响');
    });

    test('Falsify: 角色缺失（FK 关闭损坏态）→ CharacterNotFoundError 且'
        '替换截断未发生（破坏性写前校验）', () async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final orphanConv = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: 999999,
              title: const Value('损坏对话'),
              modelProvider: const Value('claude'),
              modelName: const Value('claude-sonnet-5'),
              createdAt: fakeNow,
              updatedAt: fakeNow,
            ),
          );
      final orphanMsg = await db.into(db.messages).insertReturning(
            MessagesCompanion.insert(
              conversationId: orphanConv.id,
              role: Role.user,
              content: '原内容',
              createdAt: fakeNow,
            ),
          );
      await db.into(db.messages).insertReturning(
            MessagesCompanion.insert(
              conversationId: orphanConv.id,
              role: Role.assistant,
              content: '旧回复',
              createdAt: fakeNow,
            ),
          );
      wireService(FakeLLMProvider(tokens: const ['x']));

      await expectLater(
        service.editAndRegenerate(
          conversationId: orphanConv.id,
          messageId: orphanMsg.id,
          newContent: '修正后',
        ),
        throwsA(isA<CharacterNotFoundError>()),
      );
      // 角色校验在 replaceAndTruncateFollowing 之前 → 零副作用。
      final msgs = await (db.select(db.messages)
            ..where((t) => t.conversationId.equals(orphanConv.id)))
          .get();
      expect([for (final m in msgs) m.content], ['原内容', '旧回复']);
    });
  });

  group('deleteMessage（MS-03 删除单条）', () {
    test('删 user → 截断含自身及后续（候选/thought 级联），返回条数', () async {
      final (char, conv, user1, _, _, asst2) =
          await seedFourMessageConversation();
      await messageRepo.addSwipe(asst2.id, '二候选', makeActive: false);
      await db.into(db.innerThoughts).insert(InnerThoughtsCompanion.insert(
            characterId: char.id,
            messageId: asst2.id,
            content: '独白',
            createdAt: fakeNow,
          ));
      wireService(FakeLLMProvider(tokens: const ['x']));

      final deleted = await service.deleteMessage(
          conversationId: conv.id, messageId: user1.id);

      expect(deleted, 4,
          reason: '删 user1 起 4 条（user1/第一答/第二问/第二答）');
      expect(await roleContentsOf(conv.id), [(Role.assistant, '开场。')]);
      expect(await messageRepo.listSwipes(asst2.id), isEmpty);
      expect(await innerThoughtCountFor(asst2.id), 0);
    });

    test('删 assistant → 仅删该条 + swipes/thought 级联 + '
        'ProactivePlans.messageId setNull（SR-28）', () async {
      final (char, conv, _, _, _, asst2) =
          await seedFourMessageConversation();
      await messageRepo.addSwipe(asst2.id, '二候选', makeActive: false);
      await db.into(db.innerThoughts).insert(InnerThoughtsCompanion.insert(
            characterId: char.id,
            messageId: asst2.id,
            content: '独白',
            createdAt: fakeNow,
          ));
      final planId = await db.into(db.proactivePlans).insert(
            ProactivePlansCompanion.insert(
              characterId: char.id,
              conversationId: conv.id,
              content: '计划文案',
              scheduledAt: fakeNow,
              status: ProactivePlanStatus.scheduled,
              messageId: Value(asst2.id),
            ),
          );
      wireService(FakeLLMProvider(tokens: const ['x']));

      final deleted = await service.deleteMessage(
          conversationId: conv.id, messageId: asst2.id);

      expect(deleted, 1);
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '第一轮问'),
        (Role.assistant, '第一轮答'),
        (Role.user, '第二轮问'),
      ]);
      expect(await messageRepo.listSwipes(asst2.id), isEmpty);
      expect(await innerThoughtCountFor(asst2.id), 0);
      // plan 行保留且 messageId 置空（FK SET NULL——不残留 dangling 引用）。
      final plan = await (db.select(db.proactivePlans)
            ..where((t) => t.id.equals(planId)))
          .getSingle();
      expect(plan.messageId, isNull);
    });

    test('删 system（非 user 非 assistant）→ 仅删该条', () async {
      final (char, conv, _, _, _, _) = await seedFourMessageConversation();
      final sys = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.system,
        content: '系统消息',
      );
      wireService(FakeLLMProvider(tokens: const ['x']));

      final deleted = await service.deleteMessage(
          conversationId: conv.id, messageId: sys.id);

      expect(deleted, 1);
      expect(await messagesOf(conv.id), hasLength(5),
          reason: '开场 + 四消息（仅删 system 一条）');
    });

    // 删除不存在 / 跨对话消息 → MessageNotFoundError 且零副作用
    test('Falsify: 对话不存在 → ConversationNotFoundError', () async {
      wireService(FakeLLMProvider(tokens: const ['x']));
      await expectLater(
        service.deleteMessage(conversationId: 999999, messageId: 1),
        throwsA(isA<ConversationNotFoundError>()),
      );
    });

    test('删除不存在 / 跨对话消息 → MessageNotFoundError 且零副作用', () async {
      final (_, conv, _, _, _, _) = await seedFourMessageConversation();
      final otherChar = await seedCharacter();
      final otherConv = await seedConversation(otherChar.id);
      final otherMsg = await sendUserMessage(otherConv.id, '他对话消息');
      wireService(FakeLLMProvider(tokens: const ['x']));
      final before = await roleContentsOf(conv.id);

      await expectLater(
        service.deleteMessage(conversationId: conv.id, messageId: 999999),
        throwsA(isA<MessageNotFoundError>()),
      );
      await expectLater(
        // 跨对话归属校验拒绝（他对话 id 视为不存在）。
        service.deleteMessage(
            conversationId: conv.id, messageId: otherMsg.id),
        throwsA(isA<MessageNotFoundError>()),
      );
      expect(await roleContentsOf(conv.id), before);
    });

    test('删末条 assistant 后 regenerate 行为仍正确（缺省锚定前一 assistant / '
        '无 assistant 拒绝）', () async {
      // a) 唯一 assistant 被删 → 末条为 user → 缺省 regenerate 拒绝。
      final charA = await seedCharacter(); // 无开场白
      final convA = await seedConversation(charA.id);
      await sendUserMessage(convA.id, '问');
      final aa = await sendAssistantMessage(convA.id, '答');
      wireService(FakeLLMProvider(tokens: const ['x']));
      await service.deleteMessage(conversationId: convA.id, messageId: aa.id);
      await expectLater(
        service.regenerate(conversationId: convA.id),
        throwsA(isA<InvalidRegenerateTargetError>()),
      );

      // b) 末条 assistant 被删 → 缺省 regenerate 锚定前一 assistant 成功。
      final (_, convB, _, asst1, _, asst2) =
          await seedFourMessageConversation();
      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);
      await service.deleteMessage(conversationId: convB.id, messageId: asst2.id);
      final result = await service.regenerate(conversationId: convB.id);
      expect(result.messageId, asst1.id);
      expect(await swipeContentsOf(asst1.id), ['第一轮答', '新答']);
    });
  });

  // ── switchSwipe（F-140 契约补位：归属校验进服务层，与 deleteMessage 同构）──

  group('switchSwipe（F-140 契约补位）', () {
    test('成功切换 → content/activeSwipeIndex 覆写为选中候选，返回后切换 Message',
        () async {
      final (_, conv, _, asst1, _, _) = await seedFourMessageConversation();
      await messageRepo.addSwipe(asst1.id, '候选一', makeActive: true);
      await messageRepo.addSwipe(asst1.id, '候选二', makeActive: true);
      wireService(FakeLLMProvider(tokens: const []));

      final switched = await service.switchSwipe(
          conversationId: conv.id, messageId: asst1.id, index: 1);

      expect(switched.id, asst1.id, reason: '服务层返回切换后的该 Message');
      expect(switched.content, '候选一',
          reason: 'content 已被仓库层覆写为选中候选');
      expect(switched.activeSwipeIndex, 1, reason: 'active index 同步为选中候选');
      final row =
          (await messagesOf(conv.id)).firstWhere((m) => m.id == asst1.id);
      expect(row.content, '候选一', reason: 'DB 行 content 同步覆写');
      expect(row.activeSwipeIndex, 1, reason: 'DB 行 active index 同步');
      // 对拍 MessageRepository.listSwipes：候选集内容原样保留（仅 active 移动）。
      expect(await swipeContentsOf(asst1.id), ['第一轮答', '候选一', '候选二'],
          reason: '候选集 index 升序内容不变');
    });

    test('Falsify: 不存在 / 跨对话 → MessageNotFoundError 且零副作用', () async {
      final (_, conv, _, _, _, _) = await seedFourMessageConversation();
      final otherChar = await seedCharacter();
      final otherConv = await seedConversation(otherChar.id);
      final otherMsg = await sendUserMessage(otherConv.id, '他对话消息');
      wireService(FakeLLMProvider(tokens: const []));
      final before = await roleContentsOf(conv.id);

      await expectLater(
        service.switchSwipe(
            conversationId: conv.id, messageId: 999999, index: 0),
        throwsA(isA<MessageNotFoundError>()),
      );
      await expectLater(
        // 跨对话归属校验拒绝（他对话 id 视为不存在）。
        service.switchSwipe(
            conversationId: conv.id, messageId: otherMsg.id, index: 0),
        throwsA(isA<MessageNotFoundError>()),
      );
      expect(await roleContentsOf(conv.id), before, reason: '校验失败零副作用');
    });

    test('越界 index → SwipeIndexOutOfRangeError 由仓库层原样上抛，active 不变',
        () async {
      final (_, conv, _, asst1, _, _) = await seedFourMessageConversation();
      await messageRepo.addSwipe(asst1.id, '候选一', makeActive: true);
      await messageRepo.addSwipe(asst1.id, '候选二', makeActive: true);
      wireService(FakeLLMProvider(tokens: const []));

      await expectLater(
        service.switchSwipe(
            conversationId: conv.id, messageId: asst1.id, index: 99),
        throwsA(isA<SwipeIndexOutOfRangeError>()),
      );
      final row =
          (await messagesOf(conv.id)).firstWhere((m) => m.id == asst1.id);
      expect(row.content, '候选二', reason: '失败不切换 active');
      expect(row.activeSwipeIndex, 2, reason: '失败后 active index 保持');
    });
  });

  // ── 世界书注入链（WL-03：扫描→激活→注入；重生成同吃；滑窗与 depth 解耦）──

  group('世界书注入链（WL-03）', () {
    late LorebookRepository lorebookRepo;

    setUp(() {
      lorebookRepo = LorebookRepository(db);
    });

    /// 为角色落一条世界书条目（字段可覆盖，默认 world 位置 + 必进概率）。
    Future<int> seedLorebookEntry(
      int characterId, {
      String title = '条目',
      List<String> keys = const [],
      String content = '知识内容',
      bool constant = false,
      int order = 100,
      int probability = 100,
      String groupName = '',
      String matchMode = 'or',
      String position = 'world',
      int depth = 20,
      bool enabled = true,
    }) async {
      final entry = await lorebookRepo.createEntry(
        characterId,
        LorebookEntryDraft(
          title: title,
          keys: keys,
          content: content,
          constant: constant,
          order: order,
          probability: probability,
          groupName: groupName,
          matchMode: matchMode,
          position: position,
          depth: depth,
          enabled: enabled,
        ),
      );
      return entry.id;
    }

    test('验收4：端到端——扫描→激活→注入 buildMessages，命中注入 [世界知识] 于 scenario 后',
        () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
      );
      await seedLorebookEntry(char.id, keys: ['剑'], content: '剑是身份的象征');
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '我拔出了剑');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '剑在手中')
          .toList();

      final sent = provider.lastMessages!;
      final knowledge =
          sent.where((m) => m.content.startsWith('[世界知识]')).toList();
      expect(knowledge, hasLength(1));
      expect(knowledge.single.content, '[世界知识]\n剑是身份的象征');
      // 位置：scenario 之后。
      final scenarioIndex =
          sent.indexWhere((m) => m.content.startsWith('[场景设定]'));
      expect(scenarioIndex, isNot(-1));
      // NPD-01：叙述风格默认开 → scenario 后先注入 [叙述风格]，[世界知识] 紧随其后。
      expect(sent[scenarioIndex + 1].content, startsWith('[叙述风格]'));
      expect(sent[scenarioIndex + 2].content, startsWith('[世界知识]'));
      // [世界知识] 位于历史（开场白）之前。
      final greetingIndex =
          sent.indexWhere((m) => m.role == 'assistant' && m.content == '开场。');
      final knowledgeIndex = sent.indexWhere((m) => m.content.startsWith('[世界知识]'));
      expect(knowledgeIndex, lessThan(greetingIndex));
    });

    test('验收4：世界书为空 / 全部禁用 → 零注入（与无世界书基线一致）', () async {
      final char = await seedCharacter(firstMes: '开场。', personality: '人设');
      final conv = await seedConversation(char.id);
      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: '你好').toList();
      final baseline = provider.lastMessages!;
      expect(baseline.where((m) => m.content.startsWith('[世界知识]')), isEmpty);

      // 全禁用条目角色：输出与无条目角色逐条一致。
      final char2 = await seedCharacter(firstMes: '开场。', personality: '人设');
      await seedLorebookEntry(char2.id,
          keys: ['你好'], content: '禁用知识', enabled: false);
      final conv2 = await seedConversation(char2.id);
      final provider2 = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider2);
      await service
          .streamReply(conversationId: conv2.id, content: '你好')
          .toList();
      expect(provider2.lastMessages!, baseline);
    });

    test('世界书仓储读取失败 → 降级空注入，不阻断主回复', () async {
      final char = await seedCharacter(firstMes: '开场。', personality: '人设');
      await seedLorebookEntry(char.id, keys: ['你好'], content: '知识');
      final conv = await seedConversation(char.id);

      // 只读面抛错的仓储（模拟 DB 故障），主回复必须仍可用、无世界书注入。
      final provider = FakeLLMProvider(tokens: const ['回复']);
      service = ChatService(
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: _FakeFactory(provider),
        lorebookRepository: _ThrowingLorebookRepo(db),
      );
      await service.streamReply(conversationId: conv.id, content: '你好').toList();

      final sent = provider.lastMessages!;
      expect(sent.where((m) => m.content.startsWith('[世界知识]')), isEmpty);
      expect(await roleContentsOf(conv.id), contains(
        (Role.assistant, '回复'),
      ));
    });

    test('验收2：before_char / after_char / world 三位置端到端注入', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
      );
      await seedLorebookEntry(char.id,
          keys: ['剑'], content: '前置知识', position: 'before_char');
      await seedLorebookEntry(char.id,
          keys: ['剑'], content: '后置知识', position: 'after_char');
      await seedLorebookEntry(char.id, keys: ['剑'], content: '世界知识');
      final conv = await seedConversation(char.id);

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '剑在手')
          .toList();

      final sent = provider.lastMessages!;
      expect(sent[0], const LlmMessage(role: 'system', content: '前置知识'));
      expect(sent[1], const LlmMessage(role: 'system', content: '人设'));
      expect(sent[2],
          const LlmMessage(role: 'system', content: '[场景设定]\n场景'));
      expect(sent[3], const LlmMessage(role: 'system', content: '后置知识'));
      expect(sent[4],
          LlmMessage(role: 'system', content: '[叙述风格]\n${SettingsRepository.narrativeStyleDefaultRules}'));
      expect(sent[5],
          const LlmMessage(role: 'system', content: '[世界知识]\n世界知识'));
    });

    test('验收4：激活 RNG 可注入——同种子两次装配结果一致（可复现）', () async {
      final char = await seedCharacter(firstMes: '开场。', personality: '人设');
      // 中间概率（50%）条目：命中与否依赖 RNG 掷点。
      await seedLorebookEntry(char.id,
          keys: ['剑'], content: '概率知识', probability: 50);

      Future<List<LlmMessage>> sendOnce(int conversationId) async {
        final provider = FakeLLMProvider(tokens: const ['回复']);
        service = ChatService(
          lorebookRepository: LorebookRepository(db),
          conversationRepository: convRepo,
          characterRepository: charRepo,
          messageRepository: messageRepo,
          settingsRepository: settingsRepo,
          providerFactory: _FakeFactory(provider),
          lorebookRandom: Random(42),
        );
        await service
            .streamReply(conversationId: conversationId, content: '剑在手')
            .toList();
        return provider.lastMessages!;
      }

      final conv1 = await seedConversation(char.id);
      final sent1 = await sendOnce(conv1.id);
      final conv2 = await seedConversation(char.id);
      final sent2 = await sendOnce(conv2.id);
      expect(sent1, sent2, reason: '同种子两次激活结果一致（RNG 可复现）');
    });

    test('验收5：重生成路径（append_current_input=false）同样吃到注入，'
        '尾随 system 剥离不被破坏', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        postHistoryInstructions: '保持人设',
      );
      await seedLorebookEntry(char.id, keys: ['剑'], content: '剑知识');
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '我拔出了剑');
      await sendAssistantMessage(conv.id, '旧的回复');

      final provider = FakeLLMProvider(tokens: const ['新回复']);
      wireService(provider);
      await service.regenerate(conversationId: conv.id);

      final sent = provider.lastMessages!;
      // 世界书知识已注入（重生成路径同吃）。
      expect(sent.where((m) => m.content.startsWith('[世界知识]')), hasLength(1));
      // 尾随剥离仍生效：末条为触发 user，PHI 不残留。
      expect(sent.last, LlmMessage(role: 'user', content: '我拔出了剑'));
      expect(sent.last.role, isNot('system'));
    });

    test('验收6：滑窗与 depth 解耦——maxRounds 改动不影响激活窗口', () async {
      final char = await seedCharacter(firstMes: '开场。', personality: '人设');
      // depth=20：扫描最近 40 条对话消息，不受消息滑窗 maxRounds 影响。
      await seedLorebookEntry(char.id,
          keys: ['旧词'], content: '旧词知识', depth: 20);
      final conv = await seedConversation(char.id);
      // 8 条历史：触发词位于第 1 条（maxRounds=1 → 消息滑窗仅 2 条，在窗之外）。
      await sendUserMessage(conv.id, '旧词出现于此');
      await sendAssistantMessage(conv.id, '答1');
      await sendUserMessage(conv.id, '问2');
      await sendAssistantMessage(conv.id, '答2');
      await sendUserMessage(conv.id, '问3');
      await sendAssistantMessage(conv.id, '答3');
      await sendUserMessage(conv.id, '问4');
      await sendAssistantMessage(conv.id, '答4');

      await settingsRepo.setMany({'sliding_window_rounds': '1'});
      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '新问')
          .toList();

      final sent = provider.lastMessages!;
      // 触发词位于消息滑窗之外，但世界书扫描窗（depth）不受 maxRounds 影响 → 仍激活。
      expect(sent.where((m) => m.content.startsWith('[世界知识]')), hasLength(1));
      // 消息滑窗本身仍生效：历史仅末 2 条（答4 + 已落库的当前输入）→ 追加输入。
      final historyMsgs = [
        for (final m in sent)
          if (m.role == 'user' || m.role == 'assistant') m.content,
      ];
      expect(historyMsgs, ['答4', '新问', '新问']);
      // 触发词消息（旧词出现于此）在滑窗之外，不进入消息列表。
      expect(historyMsgs, isNot(contains('旧词出现于此')));
    });

    test('验收4：扫描深度 = max(enabled.depth)——单条目浅 depth 不缩小扫描窗', () async {
      final char = await seedCharacter(firstMes: '开场。', personality: '人设');
      // 条目A depth=1（若单独取 depth 只看最近 2 条），条目B depth=20。
      await seedLorebookEntry(char.id,
          keys: ['旧词'], content: '浅知识', depth: 1);
      await seedLorebookEntry(char.id, keys: ['剑'], content: '深知识', depth: 20);
      final conv = await seedConversation(char.id);
      // 4 条历史：旧词在第 1 条（depth=1 的 2 条窗口之外），剑在末条。
      await sendUserMessage(conv.id, '旧词早先说');
      await sendAssistantMessage(conv.id, '答1');
      await sendUserMessage(conv.id, '问2');
      await sendAssistantMessage(conv.id, '我手持剑');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '继续')
          .toList();

      final sent = provider.lastMessages!;
      final knowledge =
          sent.where((m) => m.content.startsWith('[世界知识]')).toList();
      expect(knowledge, hasLength(1));
      // max(depth)=20 → 两条均命中，按 (order, id) 升序合并。
      expect(knowledge.single.content, '[世界知识]\n浅知识\n\n深知识');
    });

    test('验收4：世界书多条目注入内容不重排历史/PHI/user（位置稳定）', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        postHistoryInstructions: '指令',
      );
      await seedLorebookEntry(char.id, keys: ['剑'], content: '知识一', order: 200);
      await seedLorebookEntry(char.id, keys: ['剑'], content: '知识二', order: 100);
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '剑');
      await sendAssistantMessage(conv.id, '旧答');

      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '继续')
          .toList();

      final sent = provider.lastMessages!;
      // 合并单条，按 order 升序（知识二 order=100 在前）。
      expect(
        sent.where((m) => m.content.startsWith('[世界知识]')).single.content,
        '[世界知识]\n知识二\n\n知识一',
      );
      // 位置：system 之后、历史（开场白）之前。
      final greetingIndex =
          sent.indexWhere((m) => m.role == 'assistant' && m.content == '开场。');
      expect(
        sent[greetingIndex - 1].content,
        startsWith('[世界知识]'),
      );
      // 尾随结构稳定：PHI + user。
      expect(sent.last, LlmMessage(role: 'user', content: '继续'));
      expect(sent[sent.length - 2],
          const LlmMessage(role: 'system', content: '指令'));
    });
  });

  // ── 叙述风格注入链（NPD-01：设置读取 → 透传 → 零注入）──

  group('叙述风格注入链（NPD-01）', () {
    test('验收5：缺省开启 + 规则空 → 注入默认规则常量段，位置 scenario 后 / mes_example 前', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
        mesExample: '<START>\n{{user}}: 例问\n{{char}}: 例答',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: '再来').toList();

      final sent = provider.lastMessages!;
      final narrative = sent
          .where((m) => m.content.startsWith('[叙述风格]'))
          .toList();
      expect(narrative, hasLength(1));
      expect(
        narrative.single.content,
        '[叙述风格]\n${SettingsRepository.narrativeStyleDefaultRules}',
      );
      // 位置：scenario 之后、mes_example 之前。
      final scenarioIndex =
          sent.indexWhere((m) => m.content.startsWith('[场景设定]'));
      final narrativeIndex = sent.indexWhere(
        (m) => m.content.startsWith('[叙述风格]'),
      );
      final userExampleIndex = sent.indexWhere((m) => m.content == '例问');
      expect(scenarioIndex, isNot(-1));
      expect(narrativeIndex, greaterThan(scenarioIndex));
      expect(narrativeIndex, lessThan(userExampleIndex));
    });

    test('验收5：自定义 rules 透传注入（DB 非空返回原值）', () async {
      await settingsRepo.setMany({
        SettingsRepository.narrativeStyleRulesKey: '自定义叙述规则',
      });
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: '再来').toList();

      final sent = provider.lastMessages!;
      expect(
        sent.where((m) => m.content.startsWith('[叙述风格]')).single.content,
        '[叙述风格]\n自定义叙述规则',
      );
    });

    test('验收6：开关关闭（enabled=false）→ 组装零注入且不读 rules', () async {
      await settingsRepo.setMany({
        SettingsRepository.narrativeStyleEnabledKey: '0',
        SettingsRepository.narrativeStyleRulesKey: '不应被读取的规则',
      });
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '你好');

      // 计数仓储替身：验证关闭路径不触碰 rules getter（验收 6「不读 rules」）。
      final probing = _NarrativeProbeRepo(db, secretStore);
      final provider = FakeLLMProvider(tokens: const ['回复']);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: probing,
        providerFactory: _FakeFactory(provider),
      );
      await service.streamReply(conversationId: conv.id, content: '再来').toList();

      final sent = provider.lastMessages!;
      expect(
        sent.where((m) => m.content.startsWith('[叙述风格]')),
        isEmpty,
        reason: '开关关闭 → 组装零注入',
      );
      expect(probing.narrativeRulesReadCount, 0, reason: '开关关闭 → 不读 rules');
      expect(await roleContentsOf(conv.id), contains((Role.assistant, '回复')));
    });

    test('验收5：regenerate 共用同一条腿（_assembleMessages）→ 重生成路径亦注入', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '问题');
      final oldAssistant = await sendAssistantMessage(conv.id, '旧答');

      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);
      await service.regenerate(
        conversationId: conv.id,
        messageId: oldAssistant.id,
      );

      final sent = provider.lastMessages!;
      expect(
        sent.where((m) => m.content.startsWith('[叙述风格]')),
        hasLength(1),
        reason: 'regenerate 同吃叙述风格注入',
      );
      expect(await swipeContentsOf(oldAssistant.id), ['旧答', '新答']);
    });

    test('设置读取失败 → 降级零注入，不阻断主回复（沿世界书降级先例）', () async {
      final char = await seedCharacter(firstMes: '开场。', personality: '人设');
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: _ThrowingNarrativeSettingsRepo(db, secretStore),
        providerFactory: _FakeFactory(provider),
      );
      await service.streamReply(conversationId: conv.id, content: '再来').toList();

      final sent = provider.lastMessages!;
      expect(sent.where((m) => m.content.startsWith('[叙述风格]')), isEmpty);
      expect(await roleContentsOf(conv.id), contains((Role.assistant, '回复')));
    });
  });

  // ── 预设对话注入链（NPD-02：会话快照 → _assembleMessages 透传 → 注入）──

  group('预设对话注入链（NPD-02）', () {
    const snapshot = '<START>\n{{user}}: 请自我介绍\n{{char}}: 我叫艾莉亚。';

    test('验收6：会话快照非空 → 透传 buildMessages，注入 mes_example 后 / history 前',
        () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
        mesExample: '<START>\n{{user}}: 例问\n{{char}}: 例答',
      );
      final conv = await convRepo.createConversation(
        characterId: char.id,
        presetDialogue: snapshot,
      );
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: '再来').toList();

      final sent = provider.lastMessages!;
      final exampleIndex = sent.indexWhere((m) => m.content == '例问');
      final presetUserIndex = sent.indexWhere((m) => m.content == '请自我介绍');
      final presetCharIndex = sent.indexWhere((m) => m.content == '我叫艾莉亚。');
      final historyIndex = sent.indexWhere((m) => m.content == '你好');
      final currentIndex = sent.indexWhere((m) => m.content == '再来');
      expect(exampleIndex, isNot(-1), reason: 'mes_example 应注入');
      expect(presetUserIndex, greaterThan(exampleIndex),
          reason: 'presetDialogue 注入于 mes_example 之后');
      expect(presetCharIndex, greaterThan(presetUserIndex));
      expect(historyIndex, greaterThan(presetCharIndex),
          reason: 'presetDialogue 注入于 history 之前');
      expect(currentIndex, greaterThan(historyIndex));
      expect(await roleContentsOf(conv.id), contains((Role.assistant, '回复')));
    });

    test('验收6：会话无快照 → 零注入（组装输出不含预设 few-shot）', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        mesExample: '<START>\n{{user}}: 例问\n{{char}}: 例答',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: '再来').toList();

      final sent = provider.lastMessages!;
      expect(sent.where((m) => m.content == '请自我介绍'), isEmpty,
          reason: '无快照 → 零注入');
      expect(sent.where((m) => m.content == '我叫艾莉亚。'), isEmpty);
      // 常规 few-shot（mes_example）不受影响。
      expect(sent.where((m) => m.content == '例问'), hasLength(1));
    });

    test('验收5：快照固化——改角色卡 presetDialogues 实时值不影响已建会话注入源',
        () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        mesExample: '<START>\n{{user}}: 例问\n{{char}}: 例答',
      );
      final conv = await convRepo.createConversation(
        characterId: char.id,
        presetDialogue: snapshot,
      );
      // 创建后修改角色卡 presetDialogues 实时值（改卡不影响已建会话）。
      await (db.update(db.characters)..where((t) => t.id.equals(char.id))).write(
        CharactersCompanion(
          presetDialogues: Value(const [
            {'name': '变更', 'content': '后改的预设对话'},
          ]),
        ),
      );
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: '再来').toList();

      final sent = provider.lastMessages!;
      expect(sent.where((m) => m.content == '请自我介绍'), hasLength(1),
          reason: '注入源为创建时固化的快照');
      expect(sent.where((m) => m.content == '我叫艾莉亚。'), hasLength(1));
      expect(sent.where((m) => m.content.contains('后改的预设对话')), isEmpty,
          reason: '改卡实时值不进入已建会话注入');
    });

    test('验收5：regenerate 共用同一条腿（_assembleMessages）→ 重生成路径亦注入',
        () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
      );
      final conv = await convRepo.createConversation(
        characterId: char.id,
        presetDialogue: snapshot,
      );
      await sendUserMessage(conv.id, '问题');
      final oldAssistant = await sendAssistantMessage(conv.id, '旧答');

      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);
      await service.regenerate(
        conversationId: conv.id,
        messageId: oldAssistant.id,
      );

      final sent = provider.lastMessages!;
      expect(sent.where((m) => m.content == '请自我介绍'), hasLength(1),
          reason: 'regenerate 同吃预设对话注入');
      expect(sent.where((m) => m.content == '我叫艾莉亚。'), hasLength(1));
      // 注入位于触发 user（历史末条）之前。
      final triggerIndex = sent.indexWhere((m) => m.content == '问题');
      final presetCharIndex = sent.indexWhere((m) => m.content == '我叫艾莉亚。');
      expect(triggerIndex, greaterThan(presetCharIndex));
      expect(await swipeContentsOf(oldAssistant.id), ['旧答', '新答']);
    });
  });

  // ── 专家模式注入链（NPD-04：CharacterData 透传 → buildMessages 分流）──

  group('专家模式注入链（NPD-04）', () {
    test('expert + 非空 expertPrompt → system 段仅一条（expert prompt 内容），'
        '无 scenario/PHI 独立 system（验收 3）', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
        postHistoryInstructions: '保持人设。',
        promptMode: 'expert',
        expertPrompt: '你是{{char}}，月下剑客。',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '再来')
          .toList();

      final sent = provider.lastMessages!;
      // [叙述风格] 为独立注入段（expert 亦注入，NPD-01 契约延续）——断言
      // 非叙述风格的 system 段仅一条 expert prompt，无 personality/scenario/PHI。
      final nonNarrativeSystems = [
        for (final m in sent)
          if (m.role == 'system' && !m.content.startsWith('[叙述风格]')) m.content,
      ];
      expect(nonNarrativeSystems, [
        '你是艾莉亚，月下剑客。',
      ], reason: 'system 段仅一条 expert prompt，无 personality/scenario/PHI');
      expect(sent.where((m) => m.content.startsWith('[场景设定]')), isEmpty);
      expect(sent.where((m) => m.content == '保持人设。'), isEmpty);
      expect(await roleContentsOf(conv.id), contains((Role.assistant, '回复')));
    });

    test('expert + 空 expertPrompt → 回退 simple 结构化组装（验收 4）', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
        postHistoryInstructions: '保持人设。',
        promptMode: 'expert',
        expertPrompt: '   ',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '你好');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: '再来')
          .toList();

      final sent = provider.lastMessages!;
      expect(
        sent.where((m) => m.content == '人设'),
        hasLength(1),
        reason: '回退 simple：personality 结构化 system 生效',
      );
      expect(sent.where((m) => m.content == '[场景设定]\n场景'), hasLength(1));
      expect(
        sent.where((m) => m.content == '保持人设。'),
        hasLength(1),
        reason: 'PHI 恢复注入',
      );
    });

    test(
      'expert 角色 + mesExample/world/narrative/preset 注入照旧（验收 5 组装链）',
      () async {
        final char = await seedCharacter(
          firstMes: '开场。',
          personality: '人设',
          scenario: '场景',
          mesExample: '<START>\n{{user}}: 例问\n{{char}}: 例答',
          promptMode: 'expert',
          expertPrompt: '专家整段',
        );
        final conv = await convRepo.createConversation(
          characterId: char.id,
          presetDialogue: '<START>\n{{user}}: 示范问\n{{char}}: 示范答',
        );
        await sendUserMessage(conv.id, '你好');

        final provider = FakeLLMProvider(tokens: const ['回复']);
        wireService(provider);
        await service
            .streamReply(conversationId: conv.id, content: '再来')
            .toList();

        final sent = provider.lastMessages!;
        // mes_example 注入。
        expect(sent.where((m) => m.content == '例问'), hasLength(1));
        expect(sent.where((m) => m.content == '例答'), hasLength(1));
        // 叙述风格注入（expert 亦注入，NPD-01 契约延续）。
        expect(sent.where((m) => m.content.startsWith('[叙述风格]')), hasLength(1));
        // 预设对话 few-shot 注入。
        expect(sent.where((m) => m.content == '示范问'), hasLength(1));
        expect(sent.where((m) => m.content == '示范答'), hasLength(1));
      },
    );

    test('regenerate 路径：expert 角色末条为触发 user，尾随系统剥离不破坏（验收 5）', () async {
      final char = await seedCharacter(
        firstMes: '开场。',
        personality: '人设',
        scenario: '场景',
        postHistoryInstructions: '保持人设。',
        promptMode: 'expert',
        expertPrompt: '专家整段',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '问题');
      final oldAssistant = await sendAssistantMessage(conv.id, '旧答');

      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);
      await service.regenerate(
        conversationId: conv.id,
        messageId: oldAssistant.id,
      );

      final sent = provider.lastMessages!;
      expect(sent.last.role, 'user', reason: '末条为触发 user');
      expect(sent.last.content, '问题');
      // [叙述风格] 为独立注入段；非叙述风格 system 段仅 expert prompt 一条
      //（expert 无 PHI——三处替代面不产出 scenario/PHI 独立 system）。
      final nonNarrativeSystems = [
        for (final m in sent)
          if (m.role == 'system' && !m.content.startsWith('[叙述风格]')) m.content,
      ];
      expect(nonNarrativeSystems, ['专家整段']);
      expect(await swipeContentsOf(oldAssistant.id), ['旧答', '新答']);
    });
  });

  // ── SP-01 · 采样参数组解析 + SR-24 值域守卫 ──

  group('SP-01 · 采样参数组解析 + SR-24 值域守卫', () {
    Future<void> setSamplingColumns(
      int conversationId, {
      double? topP,
      double? presencePenalty,
      double? frequencyPenalty,
      int? maxTokens,
    }) async {
      await (db.update(db.conversations)
            ..where((t) => t.id.equals(conversationId)))
          .write(
            ConversationsCompanion(
              topP: topP == null ? const Value.absent() : Value(topP),
              presencePenalty: presencePenalty == null
                  ? const Value.absent()
                  : Value(presencePenalty),
              frequencyPenalty: frequencyPenalty == null
                  ? const Value.absent()
                  : Value(frequencyPenalty),
              maxTokens:
                  maxTokens == null ? const Value.absent() : Value(maxTokens),
            ),
          );
    }

    test('streamReply conv 列非空 → 三参数与 maxTokens 覆盖透传；温度既有链不变',
        () async {
      final char = await seedCharacter(temperature: 0.3);
      final conv = await seedConversation(char.id);
      await setSamplingColumns(
        conv.id,
        topP: 0.4,
        presencePenalty: -1.2,
        frequencyPenalty: 0.8,
        maxTokens: 512,
      );

      final provider = FakeLLMProvider(tokens: const ['r']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: 'hi').toList();

      expect(provider.lastTopP, 0.4);
      expect(provider.lastPresencePenalty, -1.2);
      expect(provider.lastFrequencyPenalty, 0.8);
      expect(provider.lastMaxTokens, 512);
      expect(provider.lastTemperature, 0.3,
          reason: 'conv 无温度列，温度恒走角色为主既有链');
    });

    test('streamReply conv 列 NULL → topP/presence/frequency null（不覆盖 provider '
        '默认）、maxTokens 走全局、温度既有链', () async {
      await settingsRepo.setMany({'max_tokens': '777'});
      final char = await seedCharacter(temperature: 0.3);
      final conv = await seedConversation(char.id);

      final provider = FakeLLMProvider(tokens: const ['r']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: 'hi').toList();

      expect(provider.lastTopP, isNull);
      expect(provider.lastPresencePenalty, isNull);
      expect(provider.lastFrequencyPenalty, isNull);
      expect(provider.lastMaxTokens, 777, reason: 'conv 列 NULL → 全局 max_tokens');
      expect(provider.lastTemperature, 0.3);
    });

    test('conv 列 NULL + 角色温度 == 默认 → 回退全局温度（既有链保持）', () async {
      await settingsRepo.setMany({'temperature': '0.5'});
      final char = await seedCharacter(); // temperature 缺省 0.7 == defaultTemperature
      final conv = await seedConversation(char.id);

      final provider = FakeLLMProvider(tokens: const ['r']);
      wireService(provider);
      await service.streamReply(conversationId: conv.id, content: 'hi').toList();

      expect(provider.lastTemperature, 0.5,
          reason: '角色温度 == 默认 → 全局兜底（F-76 判定契约保持）');
    });

    test('SR-24 topP 守卫：NaN/±Infinity 回退 null，越界 clamp [0,1]，绝不透传',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = FakeLLMProvider(tokens: const ['r']);
      wireService(provider);

      Future<void> sendWith({required double topP}) async {
        await setSamplingColumns(conv.id, topP: topP);
        await service.streamReply(conversationId: conv.id, content: 'hi').toList();
      }

      await sendWith(topP: double.nan);
      expect(provider.lastTopP, isNull, reason: 'NaN 回退 null（不覆盖 provider 默认）');
      await sendWith(topP: double.infinity);
      expect(provider.lastTopP, isNull, reason: '+Infinity 回退 null');
      await sendWith(topP: double.negativeInfinity);
      expect(provider.lastTopP, isNull, reason: '-Infinity 回退 null');
      await sendWith(topP: 1.5);
      expect(provider.lastTopP, 1.0, reason: '越界 clamp 到上限');
      await sendWith(topP: -0.5);
      expect(provider.lastTopP, 0.0, reason: '越界 clamp 到下限');
      await sendWith(topP: 0.0);
      expect(provider.lastTopP, 0.0, reason: '合法下边界原样透传');
      await sendWith(topP: 1.0);
      expect(provider.lastTopP, 1.0, reason: '合法上边界原样透传');
    });

    test('SR-24 presence/frequency 守卫：NaN/Infinity 回退 null，越界 clamp [-2,2]',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = FakeLLMProvider(tokens: const ['r']);
      wireService(provider);

      Future<void> sendWith({
        double? presencePenalty,
        double? frequencyPenalty,
      }) async {
        await setSamplingColumns(
          conv.id,
          presencePenalty: presencePenalty,
          frequencyPenalty: frequencyPenalty,
        );
        await service.streamReply(conversationId: conv.id, content: 'hi').toList();
      }

      await sendWith(presencePenalty: double.nan);
      expect(provider.lastPresencePenalty, isNull, reason: 'NaN 回退 null');
      await sendWith(presencePenalty: -3.0);
      expect(provider.lastPresencePenalty, -2.0, reason: '越界 clamp 到下限');
      await sendWith(presencePenalty: 2.5);
      expect(provider.lastPresencePenalty, 2.0, reason: '越界 clamp 到上限');

      await sendWith(frequencyPenalty: double.infinity);
      expect(provider.lastFrequencyPenalty, isNull, reason: '+Infinity 回退 null');
      await sendWith(frequencyPenalty: -3.0);
      expect(provider.lastFrequencyPenalty, -2.0, reason: '越界 clamp 到下限');
      await sendWith(frequencyPenalty: 2.5);
      expect(provider.lastFrequencyPenalty, 2.0, reason: '越界 clamp 到上限');

      await sendWith(presencePenalty: -2.0, frequencyPenalty: 2.0);
      expect(provider.lastPresencePenalty, -2.0, reason: '合法下边界原样透传');
      expect(provider.lastFrequencyPenalty, 2.0, reason: '合法上边界原样透传');
    });

    test('SR-24 maxTokens 守卫：<1 回退全局，合法值覆盖（绝不透传非法值）', () async {
      await settingsRepo.setMany({'max_tokens': '888'});
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = FakeLLMProvider(tokens: const ['r']);
      wireService(provider);

      Future<void> sendWith(int? maxTokens) async {
        await setSamplingColumns(conv.id, maxTokens: maxTokens);
        await service.streamReply(conversationId: conv.id, content: 'hi').toList();
      }

      await sendWith(null);
      expect(provider.lastMaxTokens, 888, reason: 'conv 列 NULL → 全局兜底');
      await sendWith(0);
      expect(provider.lastMaxTokens, 888, reason: 'maxTokens=0 非法 → 回退全局');
      await sendWith(-10);
      expect(provider.lastMaxTokens, 888, reason: 'maxTokens=-10 非法 → 回退全局');
      await sendWith(512);
      expect(provider.lastMaxTokens, 512, reason: '合法值覆盖全局');
    });

    test('regenerate conv 列非空 → generate 收到三参数 + maxTokens 覆盖（共享透传腿）',
        () async {
      final char = await seedCharacter(firstMes: '开场。');
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '问题');
      final asst = await sendAssistantMessage(conv.id, '旧答');
      await setSamplingColumns(
        conv.id,
        topP: 0.6,
        presencePenalty: -0.5,
        frequencyPenalty: 1.0,
        maxTokens: 300,
      );

      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);
      await service.regenerate(conversationId: conv.id, messageId: asst.id);

      expect(provider.lastTopP, 0.6);
      expect(provider.lastPresencePenalty, -0.5);
      expect(provider.lastFrequencyPenalty, 1.0);
      expect(provider.lastMaxTokens, 300);
      expect(await swipeContentsOf(asst.id), ['旧答', '新答']);
    });

    test('continueReply conv 列非空 → generate 收到三参数 + maxTokens 覆盖', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '问题');
      await sendAssistantMessage(conv.id, '旧答。');
      await setSamplingColumns(
        conv.id,
        topP: 0.2,
        presencePenalty: 1.5,
        frequencyPenalty: -1.0,
        maxTokens: 200,
      );

      final provider = FakeLLMProvider(tokens: const ['续写']);
      wireService(provider);
      final result = await service.continueReply(conversationId: conv.id);

      expect(result.swipeIndex, 1);
      expect(provider.lastTopP, 0.2);
      expect(provider.lastPresencePenalty, 1.5);
      expect(provider.lastFrequencyPenalty, -1.0);
      expect(provider.lastMaxTokens, 200);
    });
  });

  // ── Prompt Debug 只读追溯（PD-04，验收 3/4/5；SR-31）──

  group('Prompt Debug 只读追溯（PD-04）', () {
    /// 落一条世界书条目（source 可指定：manual→world / auto→memory）。
    /// 独立建仓避免污染既有字段缺省；constant=true 保证确定性（RNG 无关）。
    Future<void> seedDebugLorebookEntry(
      int characterId, {
      String content = '知识内容',
      String source = 'manual',
      String position = 'world',
    }) async {
      final repo = LorebookRepository(db);
      await repo.createEntry(
        characterId,
        LorebookEntryDraft(
          content: content,
          constant: true,
          position: position,
          source: source,
        ),
      );
    }

    test('验收3 SR-31：promptDebug 零 LLM 调用（工厂 create 计数 0）+ '
        '零落库（消息表行数不变）+ 零外发（无 generate/stream 调用）', () async {
      final char = await seedCharacter(
        personality: '人设',
        scenario: '场景',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '问1');
      await sendAssistantMessage(conv.id, '答1');

      final provider = FakeLLMProvider(tokens: const ['回复']);
      final factory = _FakeFactory(provider);
      service = ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: factory,
      );
      factory.createCallCount = 0;
      final before = (await messagesOf(conv.id)).length;

      final result = await service.promptDebug(conversationId: conv.id);

      expect(factory.createCallCount, 0, reason: '零 LLM：promptDebug 不建 Provider');
      expect(provider.generateCallCount, 0);
      expect(provider.streamGenerateCallCount, 0);
      expect(await messagesOf(conv.id), hasLength(before),
          reason: '零落库：消息表行数不变');
      expect(result.characterName, char.name);
      expect(result.model, '${conv.modelProvider}/${conv.modelName}');
      expect(result.promptMode, char.promptMode);
    });

    test('验收4：promptDebug 与真实发送走同一组装核心与同一上游——逐条 content '
        '一致（历史滑窗 + 世界书扫描 + 叙述风格 + 预设 + expert 参数）',
        () async {
      await settingsRepo.setMany({
        SettingsRepository.narrativeStyleEnabledKey: '1',
        SettingsRepository.narrativeStyleRulesKey: '不要 AI 味',
      });
      final char = await seedCharacter(
        personality: '{{char}}的人设',
        scenario: '{{char}}的场景',
        mesExample: '<START>\n{{user}}: 例1\n{{char}}: 例2',
        postHistoryInstructions: '保持人设。',
      );
      final conv = await convRepo.createConversation(
        characterId: char.id,
        presetDialogue: '<START>\n{{user}}: 预1\n{{char}}: 预2',
      );
      await sendUserMessage(conv.id, '问1');
      await sendAssistantMessage(conv.id, '答1');
      await seedDebugLorebookEntry(char.id, content: '剑是身份的象征');
      await seedDebugLorebookEntry(
        char.id,
        content: '记忆宫殿条目',
        source: 'auto',
      );

      final provider = FakeLLMProvider(tokens: const []);
      wireService(provider);
      // 真实发送（零 token → 空流不落库 assistant，仅 history 多一条 user）。
      await service.streamReply(conversationId: conv.id, content: '实时输入')
          .toList();
      final realSent = provider.lastMessages!;

      final debug = await service.promptDebug(conversationId: conv.id);

      // 逐条一致：除末条（真实=当前输入 / debug=空 content 占位）外全部相同。
      expect(debug.segments.length, realSent.length,
          reason: '同一组装核心产出同长度序列');
      for (var i = 0; i < realSent.length - 1; i++) {
        expect(debug.segments[i].role, realSent[i].role,
            reason: 'role 逐条一致 @$i');
        expect(debug.segments[i].content, realSent[i].content,
            reason: 'content 逐条一致 @$i（同一上游）');
      }
      expect(debug.segments.last.role, 'user');
      expect(debug.segments.last.content, '',
          reason: 'debug 末条为 user 空内容占位（桌面对齐）');
      expect(debug.segments.last.source, sourceUser);
      // 同一上游确实携带全部注入物。
      final contents = [for (final s in debug.segments) s.content];
      expect(contents, contains('[叙述风格]\n不要 AI 味'));
      expect(contents, contains(contains('剑是身份的象征')));
      expect(contents, contains(contains('记忆宫殿条目')));
      expect(contents, contains('预1'));
      expect(contents, contains('保持人设。'));
    });

    test('验收4 expert：system 段单条 expert_prompt（来源 character），'
        '无 scenario/PHI', () async {
      final char = await seedCharacter(
        personality: '人设',
        scenario: '场景',
        postHistoryInstructions: '保持人设。',
        promptMode: 'expert',
        expertPrompt: '你是{{char}}，专家整段。',
      );
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '问');

      final debug = await (ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: _FakeFactory(FakeLLMProvider()),
      ))
          .promptDebug(conversationId: conv.id);

      expect(debug.promptMode, 'expert');
      expect(debug.segments.first,
          (role: 'system', content: '你是艾莉亚，专家整段。', source: sourceCharacter));
      expect(debug.segments.where((s) => s.content.startsWith('[场景设定]')),
          isEmpty);
      expect(debug.segments.where((s) => s.content == '保持人设。'), isEmpty);
    });

    test('验收5：空对话 + 无注入 → 仅 system(character) + user(user) '
        '（叙述风格关闭排除干扰）', () async {
      await settingsRepo.setMany({SettingsRepository.narrativeStyleEnabledKey: '0'});
      final char = await seedCharacter(personality: '你是空态角色。');
      final conv = await seedConversation(char.id);

      final debug = await (ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: _FakeFactory(FakeLLMProvider()),
      ))
          .promptDebug(conversationId: conv.id);

      expect([
        for (final s in debug.segments)
          (role: s.role, content: s.content, source: s.source),
      ], [
        (role: 'system', content: '你是空态角色。', source: sourceCharacter),
        (role: 'user', content: '', source: sourceUser),
      ]);
    });

    test('世界书 manual → world / auto → memory 来源在 promptDebug 逐段保真',
        () async {
      await settingsRepo.setMany({SettingsRepository.narrativeStyleEnabledKey: '0'});
      final char = await seedCharacter(personality: '人设');
      final conv = await seedConversation(char.id);
      await seedDebugLorebookEntry(
        char.id,
        content: '手动世界知识',
        source: 'manual',
        position: 'before_char',
      );
      await seedDebugLorebookEntry(
        char.id,
        content: '记忆条目',
        source: 'auto',
      );

      final debug = await (ChatService(
        lorebookRepository: LorebookRepository(db),
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: _FakeFactory(FakeLLMProvider()),
      ))
          .promptDebug(conversationId: conv.id);

      final byContent = {
        for (final s in debug.segments) s.content: s.source,
      };
      expect(byContent['手动世界知识'], sourceWorld);
      expect(byContent['[世界知识]\n记忆条目'], sourceMemory);
    });

    test('对话不存在 → ConversationNotFoundError（只读守护，SR-31 无副作用）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = FakeLLMProvider(tokens: const ['回复']);
      wireService(provider);
      final before = (await messagesOf(conv.id)).length;

      await expectLater(
        service.promptDebug(conversationId: conv.id + 9999),
        throwsA(isA<ConversationNotFoundError>()),
      );
      expect(provider.generateCallCount, 0);
      expect(await messagesOf(conv.id), hasLength(before));
    });
  });
}

class _UnknownDomainError extends DomainError {
  _UnknownDomainError() : super('未知领域错误');
}

/// listEntries 抛错的 [LorebookRepository]——世界书读失败降级路径测试用
/// （模拟 DB 故障；主回复必须仍可用、世界书零注入）。
class _ThrowingLorebookRepo extends LorebookRepository {
  _ThrowingLorebookRepo(super.db);

  @override
  Future<List<LorebookEntry>> listEntries(int characterId) async {
    throw StateError('db down');
  }
}

/// 计数 `narrativeStyleRules` 读取次数的仓储替身（NPD-01 验收 6：开关关闭
/// 时组装链不得读取 rules；超类行为不变，仅叠加计数）。
class _NarrativeProbeRepo extends SettingsRepository {
  _NarrativeProbeRepo(AppDatabase db, InMemorySecretStore secretStore)
      : super(database: db, secretStore: secretStore);

  int narrativeRulesReadCount = 0;

  @override
  Future<String> get narrativeStyleRules async {
    narrativeRulesReadCount++;
    return super.narrativeStyleRules;
  }
}

/// 叙述风格设置读取抛错的仓储替身（NPD-01：设置读取失败降级路径——主回复
/// 必须仍可用、叙述风格零注入，沿世界书降级先例）。
class _ThrowingNarrativeSettingsRepo extends SettingsRepository {
  _ThrowingNarrativeSettingsRepo(AppDatabase db, InMemorySecretStore secretStore)
      : super(database: db, secretStore: secretStore);

  @override
  Future<bool> get narrativeStyleEnabled async => throw StateError('db down');
}
