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

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
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
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
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
  }) async =>
      _tokens.join();

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
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
  }) async =>
      ''; // F-55 测试仅走流式路径。

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
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
  }) async =>
      _tokens.join();

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
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
  }) async {
    generateCallCount++;
    if (!started.isCompleted) {
      started.complete();
    }
    await gate.future;
    return reply;
  }

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) async* {
    throw StateError('F1/F4 测试不走流式路径');
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
      database: db,
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
      database: db,
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

  Future<Message> sendUserMessage(int conversationId, String content) {
    return messageRepo.createMessage(
      conversationId: conversationId,
      role: Role.user,
      content: content,
    );
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
      // 组装顺序：system(personality 回退) → scenario → mes_example → 历史 → PHI → user。
      expect(sent[0],
          const LlmMessage(role: 'system', content: '艾莉亚的人设'));
      expect(sent[1],
          const LlmMessage(role: 'system', content: '[场景设定]\n艾莉亚的场景'));
      expect(sent[2], const LlmMessage(role: 'user', content: '例问'));
      expect(sent[3], const LlmMessage(role: 'assistant', content: '例答'));
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
        database: db,
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
        database: db,
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
        database: db,
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

      wireService(FakeLLMProvider(
        tokens: const [],
        error: ConversationNotFoundError(),
      ));
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

      wireService(FakeLLMProvider(
        tokens: const [],
        error: StateError('wire 层未知异常'),
      ));
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
        database: db,
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
        database: db,
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
        database: db,
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

    test('F-76: 角色温度越界（上界）→ clamp 到 2.0 不透传', () async {
      final char = await seedCharacter(temperature: 9.9);
      final conv = await seedConversation(char.id);

      final provider = _TickingProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.lastTemperature, 2.0, reason: '9.9 clamp 到 2.0');
    });

    test('F-76: 角色温度越界（下界）→ clamp 到 0.0 不透传', () async {
      final char = await seedCharacter(temperature: -1.5);
      final conv = await seedConversation(char.id);

      final provider = _TickingProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.lastTemperature, 0.0, reason: '-1.5 clamp 到 0.0');
    });

    test('F-76: 角色温度 Infinity → 回退全局（NaN/Infinity 不判为覆盖）',
        () async {
      final char = await seedCharacter(temperature: double.infinity);
      final conv = await seedConversation(char.id);
      await settingsRepo.setMany({'temperature': '0.9'});

      final provider = _TickingProvider(tokens: const ['回复']);
      wireService(provider);
      await service
          .streamReply(conversationId: conv.id, content: 'hi')
          .toList();

      expect(provider.lastTemperature, 0.9,
          reason: 'Infinity 不判为显式覆盖 → 回退全局 0.9');
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
        database: db,
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
        database: db,
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
        database: db,
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
        database: db,
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

    test('A4: 成功 → 单事务删旧 + 插新（旧 assistant 替换，user 保留）',
        () async {
      final (_, conv, userMsg, oldAssistant) =
          await seedConversationWithReply();
      final provider = FakeLLMProvider(tokens: const ['新回复']);
      wireService(provider);

      final result = await service.regenerate(conversationId: conv.id);

      expect(result.reply, '新回复');
      expect(result.conversationId, conv.id);
      expect(result.messageId, isNot(oldAssistant.id));
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新回复'),
      ]);
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
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '第二答',
      );
      final provider = FakeLLMProvider(tokens: const ['新答']);
      wireService(provider);

      // 缺省：末条 assistant（第二答）为目标 → 截断其及之后（无），替换为 新答。
      await service.regenerate(conversationId: conv.id);
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
        (Role.user, '第二问'),
        (Role.assistant, '新答'),
      ]);

      // 显式：目标 = 第一条 assistant（旧回复）→ 截断其及之后全部。
      provider.lastMessages = null;
      final result = await service.regenerate(
          conversationId: conv.id, messageId: oldAssistant.id);
      expect(result.reply, '新答');
      expect(result.messageId, isNot(oldAssistant.id));
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新答'),
      ]);
      // 截断后触发源 user（你好）仍为末条历史（append_current_input=False）。
      expect(provider.lastMessages!.last,
          LlmMessage(role: 'user', content: userMsg.content));
    });

    test('F-64: RegenerateResult.replacedMessageId 缺省路径 = 末条 assistant'
        '（实际替换目标行 id，有界删旧前已知）', () async {
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
          reason: '缺省目标 = 末条 assistant（实际被替换行 id）');
      expect(result.messageId, isNot(second.id), reason: '新回复为新 id');
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
        (Role.user, '第二问'),
        (Role.assistant, '新答'),
      ]);
    });

    test('F-64: RegenerateResult.replacedMessageId 显式路径 = 指定 messageId'
        '目标行 id（被替换行非末条）', () async {
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
          reason: '显式目标 = 实际被替换行 id');
      expect(result.messageId, isNot(oldAssistant.id));
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新答'),
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
      // 时间线不变：旧回复原样保留。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '旧回复'),
      ]);
    });

    test('A4: LLM 失败（连接中断信号）→ 旧消息保留', () async {
      final (_, conv, _, _) = await seedConversationWithReply();
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
    });

    test('F1: 重生成进行中并发新消息 → 新消息保留（有界删除防数据丢失）',
        () async {
      final (_, conv, _, oldAssistant) = await seedConversationWithReply();
      final provider = _HoldableProvider(reply: '新回复');
      wireService(provider);

      // 网络 generate 挂起（快照已捕获、事务未执行）。
      final regenerating = service.regenerate(conversationId: conv.id);
      await provider.started.future;

      // 生成期间并发发送新 user 消息（id > snapshotMaxId）。
      final concurrent = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '并发新消息',
      );
      expect(concurrent.id, greaterThan(oldAssistant.id));

      provider.gate.complete(); // 放行生成 → 有界删旧 + 插新
      final result = await regenerating;

      expect(result.reply, '新回复');
      // 有界删除只替换快照内 target 之后的旧消息；并发新 user 保留，
      // 新回复以新 id 落在其后（F1 数据完整性）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.user, '并发新消息'),
        (Role.assistant, '新回复'),
      ]);
    });

    test('F4: 并发双触发 regenerate → 第二次拒绝「重生成进行中」，第一次结果保留',
        () async {
      final (_, conv, _, _) = await seedConversationWithReply();
      final provider = _HoldableProvider(reply: '新回复');
      wireService(provider);

      final first = service.regenerate(conversationId: conv.id); // 挂起
      await provider.started.future; // 第一次已进入网络阶段（in-flight）

      // 第二次调用基于同一快照解析目标，会把第一次的新回复当截断目标 → 拒绝。
      await expectLater(
        service.regenerate(conversationId: conv.id),
        throwsA(isA<RegenerateBusyError>()),
      );

      provider.gate.complete();
      final result = await first;
      expect(result.reply, '新回复');
      // 第一次结果保留（无第二次事务删除）。
      expect(await roleContentsOf(conv.id), [
        (Role.assistant, '开场。'),
        (Role.user, '你好'),
        (Role.assistant, '新回复'),
      ]);
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
  });
}

class _UnknownDomainError extends DomainError {
  _UnknownDomainError() : super('未知领域错误');
}
