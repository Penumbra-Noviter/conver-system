/// ChatRound 回合状态机独立契约测试（2026-09-07 架构深化候选 5 分离后新增）。
///
/// 语义锚点（逐字对齐 ChatController 既有回合行为，纯搬迁后独立可测）：
/// - 发送：同步置位 isStreaming → 在途 user + 流式占位（合成 id 负值）→
///   streamingText 逐 token 累积 → 终态触发 reloadMessages 回调重载；
/// - 停止：会话内（currentConversationId == 本轮回话）重载后末条 assistant
///   标「已停止」；入口态/后台流停止记待补标记，重进经
///   applyBackgroundStoppedMark 补标（F3b）；
/// - 断流：ChatInterrupted → notice「回复已中断」（非阻塞，先错者胜）；
/// - 重生成：成功重载；失败 notice 折叠（不删行，旧回复保留）。
///
/// 测试 seam（公共接口边界）：[ChatRound] 公开 API（send / stop / regenerate
/// / 只读状态面 / resetForNavigation / applyBackgroundStoppedMark / isStopped）
/// + 注入回调（reloadMessages / notify / 共享 NoticeRunner）；服务层由真实
/// [ChatService] 承载（内存 drift + InMemorySecretStore + Fake/Ticking
/// provider），不 mock 服务内部实现——与 chat_controller_test 同形装配。
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
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/notice_runner.dart';
import 'package:conver_system_mobile/views/chat/chat_round.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（与 chat_test_env 同形，不再造第二条规则）。
class _FakeSettingsReader implements SettingsReader {
  const _FakeSettingsReader();

  @override
  Future<String> get defaultProvider async => '';

  @override
  Future<String> get defaultModel async => '';

  @override
  Future<String> get userName async => '';

  @override
  Future<Map<String, String>> get templateVars async => const {};
}

/// ChatRound 测试环境载体：回合 + 共享 notice 槽 + 注入回调观测（reload 次数
/// / 可编程 reload 返回 / notify 次数）。
class _RoundEnv {
  _RoundEnv(this.round, this.notice);

  final ChatRound round;
  final NoticeRunner notice;
  int notifyCount = 0;
  int reloadCalls = 0;

  /// 缺省 reloadMessages 回调返回的「重载后 DB 列表」（测试可编程注入）。
  List<Message> reloaded = const [];

  /// [trackStreaming] 置位后，经 notify 回调录制 streamingText 变化序列
  /// （打字机累积断言用——逐 token 通知必然采样到每个中间态，轮询会漏末态）。
  bool trackStreaming = false;
  final List<String> seenStreaming = [];
}

/// 首轮 streamGenerate 产出一个 token 后断流（有内容）；后续轮次零内容立即
/// 断流（ChatInterrupted(null)）——构造「上轮截断标记尚存时新一轮零内容断流」
/// 的 F-4 场景。
class _ContentThenZeroInterruptProvider extends TickingFakeLLMProvider {
  _ContentThenZeroInterruptProvider()
      : super(
          tokens: const ['a'],
          errorAfter: LLMConnectionInterruptedError(),
          delay: const Duration(milliseconds: 5),
        );

  int _streamCalls = 0;

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
    _streamCalls++;
    streamGenerateCallCount++;
    if (_streamCalls == 1) {
      await Future<void>.delayed(delay);
      yield 'a';
    }
    // 后续轮次：零内容立即断流（ChatInterrupted(null)）。
    throw LLMConnectionInterruptedError();
  }

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
    return '新回复';
  }
}

/// generate 挂起于 [gate] 的断流重试 provider（F-65② 并发注入回归用）：
/// streamGenerate 产 token 后断流（截断标记），generate（重试）进入后挂起于
/// [gate]——重试挂起期测试注入并发 notice，放行后断言并发提示不被结算清空。
class _GatedInterruptRetryProvider extends TickingFakeLLMProvider {
  _GatedInterruptRetryProvider({required this.reply})
      : super(
          tokens: const ['a'],
          errorAfter: LLMConnectionInterruptedError(),
          delay: const Duration(milliseconds: 5),
        );

  /// regenerate（重试）返回的完整回复。
  final String reply;

  /// generate 放行信号（测试完成并发注入后打开）。
  final Completer<void> gate = Completer<void>();

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
    await gate.future;
    return reply;
  }
}

/// 首轮 stream 产 token 后断流（截断标记）；generate（continueReply）返回
/// **空串**——构造 continueReply 空续写（swipeIndex = -1 no-op 哨兵）场景。
class _InterruptThenEmptyContinueProvider extends TickingFakeLLMProvider {
  _InterruptThenEmptyContinueProvider()
      : super(
          tokens: const ['a'],
          errorAfter: LLMConnectionInterruptedError(),
          delay: const Duration(milliseconds: 5),
        );

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
    return '';
  }
}

/// [MessageRepository] 的挂起替身（R4 立即停止契约测试用）：createMessage 可在
/// 进入时挂起于 [gate]（放行后走真实落库）——确定性构造「send 后立即 stop 时
/// user 写尚未结算」的门控窗口；[gateRole] 限定挂起角色（null → 全部）。
class _GatedMessageRepository extends MessageRepository {
  _GatedMessageRepository(super.db);

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

/// 受控事件流 ChatService 替身（F-65③ reload 窗口确定性构造）：streamReply
/// 返回测试持有的流控制器，测试手动投递 ChatEvent（token / interrupted）并
/// **控制 done 时机**——不 close 则 `onDone` 不触发、`_reloadPending` 保持
/// true（重载窗口跨 await 可观测）。regenerate 本测试不触（UnimplementedError
/// 防静默假通过）。
class _ScriptedChatService implements ChatService {
  final StreamController<ChatEvent> events = StreamController<ChatEvent>();

  @override
  Stream<ChatEvent> streamReply({
    required int conversationId,
    required String content,
  }) =>
      events.stream;

  @override
  Future<RegenerateResult> regenerate({
    required int conversationId,
    int? messageId,
  }) async {
    throw UnimplementedError('F-65③ 脚本化测试不触 regenerate');
  }

  @override
  Future<RegenerateResult> continueReply({
    required int conversationId,
    int? messageId,
  }) async {
    throw UnimplementedError('F-65③ 脚本化测试不触 continueReply');
  }

  @override
  Future<RegenerateResult> editAndRegenerate({
    required int conversationId,
    required int messageId,
    required String newContent,
  }) async {
    throw UnimplementedError('F-65③ 脚本化测试不触 editAndRegenerate');
  }

  @override
  Future<PromptDebugResult> promptDebug({required int conversationId}) async {
    // PD-04：脚本化测试仅编排 streamReply 事件流，不触 promptDebug 只读腿。
    throw UnimplementedError('F-65③ 脚本化测试不触 promptDebug');
  }

  @override
  Future<int> deleteMessage({
    required int conversationId,
    required int messageId,
  }) async {
    throw UnimplementedError('F-65③ 脚本化测试不触 deleteMessage');
  }

  @override
  Future<Message> switchSwipe({
    required int conversationId,
    required int messageId,
    required int index,
  }) async {
    // 接口顺应存根：_ScriptedChatService implements ChatService，ChatService
    // 新增 switchSwipe 后编译必需（F-140）。脚本化编排仅驱动 streamReply
    // 事件流；switchSwipe 组走真实 ChatService（行为等价由该组既有断言
    // 承保）——被触即炸，保持脚本化测试诚实性（F-65③ 关联）。
    throw UnimplementedError('F-65③ 脚本化测试不触 switchSwipe');
  }
}

/// [MessageRepository] 的挂起替身（switchSwipe 防并发测试用）：switchSwipe
/// 进入时挂起于 [gate]（放行后走真实切换）——确定性构造「切换进行中重复触发」
/// 的门控窗口；[entered] 标记首次进入。
class _GatedSwitchRepository extends MessageRepository {
  _GatedSwitchRepository(super.db);

  /// 挂起器：switchSwipe 进入后 await 其 future。
  Completer<void>? gate;

  /// switchSwipe 已进入挂起（测试等待其越过入口后发起第二次触发）。
  final Completer<void> entered = Completer<void>();

  /// switchSwipe 实际调用次数（断言防并发守卫只放行一次）。
  int switchCalls = 0;

  @override
  Future<Message> switchSwipe(int messageId, int index) async {
    switchCalls++;
    final g = gate;
    if (g != null) {
      if (!entered.isCompleted) {
        entered.complete();
      }
      await g.future;
    }
    return super.switchSwipe(messageId, index);
  }
}

/// 在 [deadline]（5s 墙钟）内轮询 [condition] 直到为真（与
/// chat_controller_test 同款墙钟语义）。
Future<void> _until(
  Future<bool> Function() condition, {
  String why = '',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('等待条件超时: $why');
}

void main() {
  late AppDatabase db;
  late ConversationRepository convRepo;
  late MessageRepository messageRepo;
  late CharacterRepository charRepo;
  late SettingsRepository settingsRepo;
  late InMemorySecretStore secretStore;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    convRepo = ConversationRepository(db, const _FakeSettingsReader());
    messageRepo = MessageRepository(db);
    charRepo = CharacterRepository(db);
    secretStore = InMemorySecretStore();
    settingsRepo = SettingsRepository(database: db, secretStore: secretStore);
    await settingsRepo.setMany({'claude_api_key': 'sk-default'});
  });

  tearDown(() async {
    await db.close();
  });

  /// 装配 ChatRound：驱动真实 ChatService + [provider]；[messageRepository] 可
  /// 注入特殊仓储（R4 门控 user 写用；缺省真实 messageRepo）；[reloadMessages]
  /// 缺省为「计数 + 返回 [env.reloaded]」，测试可注入定制重载语义（如会话内
  /// 停止经真实仓储读末条）。[connectRetryDelays] 透传 ChatService 连接阶段重试
  /// 退避序列（零部分断流测试注入空序列跳过 1s/2s 生产退避）。
  _RoundEnv wireRound(
    LLMProvider provider, {
    MessageRepository? messageRepository,
    Future<List<Message>> Function()? reloadMessages,
    List<Duration> connectRetryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
    ChatService? serviceOverride,
  }) {
    final service = serviceOverride ??
        ChatService(
          lorebookRepository: LorebookRepository(db),
          conversationRepository: convRepo,
          characterRepository: charRepo,
          messageRepository: messageRepository ?? messageRepo,
          settingsRepository: settingsRepo,
          providerFactory: FixedLLMProviderFactory(provider),
          connectRetryDelays: connectRetryDelays,
        );
    late _RoundEnv env;
    final notice = NoticeRunner();
    final round = ChatRound(
      chatService: service,
      messageRepository: messageRepository ?? messageRepo,
      noticeRunner: notice,
      reloadMessages: reloadMessages ?? () async {
        env.reloadCalls++;
        return env.reloaded;
      },
      notify: () {
        env.notifyCount++;
        if (env.trackStreaming) {
          final t = env.round.streamingText;
          if (env.seenStreaming.isEmpty || env.seenStreaming.last != t) {
            env.seenStreaming.add(t);
          }
        }
      },
    );
    env = _RoundEnv(round, notice);
    return env;
  }

  Future<Character> seedCharacter({String name = '艾莉亚'}) {
    return charRepo.createCharacter(
      CharactersCompanion.insert(
        name: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<Conversation> seedConversation(int characterId) =>
      convRepo.createConversation(characterId: characterId);

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

  group('send · 回合启动（A2）', () {
    test('send → isStreaming 同步置位；streamingText 逐 token 累积后落库',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(TickingFakeLLMProvider(
        tokens: const ['你', '好', '！'],
        delay: const Duration(milliseconds: 10),
      ));

      env.round.send(conversationId: conv.id, text: '早上好');

      expect(env.round.isStreaming, isTrue,
          reason: 'send 同步置位 isStreaming（发送↔停止两态切换）');
      expect(env.round.pendingUserText, '早上好', reason: '在途 user 缓冲');
      expect(env.round.pendingUserSyntheticId, isNegative,
          reason: '合成 id 负值，仅 ListView key 消费');
      expect(env.round.assistantSyntheticId, isNegative);
      expect(env.notifyCount, greaterThan(0), reason: '状态变化经 notify 通知');

      env.trackStreaming = true;
      await _until(() async => !env.round.isStreaming, why: '回合完成');
      env.trackStreaming = false;

      expect(env.seenStreaming, containsAll(['你', '你好', '你好！']),
          reason: '打字机累积序列须逐 token 增长（经 notify 采样每个中间态）');
      expect(env.round.streamingText, isEmpty, reason: '终态清空占位文本');
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, '早上好'), (Role.assistant, '你好！')]);
    });

    test('send 空文本 / 流式中重复 send → 忽略（不重复发起）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 20),
      );
      final env = wireRound(provider);

      env.round.send(conversationId: conv.id, text: '   ');
      expect(env.round.isStreaming, isFalse, reason: '空文本不发起回合');

      env.round.send(conversationId: conv.id, text: '第一条');
      expect(env.round.isStreaming, isTrue);
      env.round.send(conversationId: conv.id, text: '第二条');

      expect(env.round.pendingUserText, '第一条',
          reason: '流式中重复 send 被忽略，在途仍是第一条');
      await _until(() async => !env.round.isStreaming, why: '回合完成');
      expect(provider.streamGenerateCallCount, 1, reason: '只发起一次流式生成');
    });

    test('终态 done → reloadMessages 回调被调；占位清空（替换为 DB 权威列表）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(FakeLLMProvider(tokens: const ['完整', '回复']));

      env.round.send(conversationId: conv.id, text: '出发');

      await _until(() async => !env.round.isStreaming && env.reloadCalls >= 1,
          why: '终态重载');
      expect(env.round.hasSyntheticAssistant, isFalse,
          reason: '重载后合成占位不再渲染');
      expect(env.round.pendingUserText, isNull, reason: '在途 user 已清空');
    });
  });

  group('stop · 停止（A3 / F1 / F3b）', () {
    test('会话内停止：重载返回末条 assistant → isStopped 标记', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        TickingFakeLLMProvider(
          tokens: const ['a', 'b'],
          delay: const Duration(milliseconds: 10),
        ),
        // 会话内停止重载：经真实仓储读当前会话（停止时部分内容已落库）。
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.round.streamingText.isNotEmpty,
          why: '已累积 token（部分内容将落库）');

      await env.round.stop(currentConversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs.last.role, Role.assistant, reason: '部分内容已落库为 assistant');
      expect(env.round.isStopped(msgs.last.id), isTrue,
          reason: '会话内停止：末条 assistant 标「已停止」');
      expect(env.round.isStreaming, isFalse);
      expect(env.round.hasSyntheticAssistant, isFalse,
          reason: '重载后占位替换为 DB 权威列表（streamingStopped 随清在途复位）');
    });

    test('后台流停止（currentConversationId 非本轮回话）→ 重进补标（F3b）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 10),
      ));

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.round.streamingText.isNotEmpty,
          why: '已累积 token');

      // 入口态/后台流停止（reload 目标为空）：不重载，记待补标记。
      await env.round.stop(currentConversationId: null);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs.last.role, Role.assistant, reason: '部分内容已落库');
      expect(env.round.isStopped(msgs.last.id), isFalse,
          reason: '后台停止不直接标（标记待重进补）');

      // 重进该会话（openConversation 重载后）：补标一次。
      final applied =
          env.round.applyBackgroundStoppedMark(conv.id, msgs);
      expect(applied, isTrue, reason: '有待补标记且末条 assistant → 补标');
      expect(env.round.isStopped(msgs.last.id), isTrue,
          reason: 'F3b：重进补「已停止」标记');

      // 再次 apply（无待补标记）→ false 零副作用。
      expect(env.round.applyBackgroundStoppedMark(conv.id, msgs), isFalse,
          reason: '待补集合已清，重复 apply 零副作用');
    });

    test('R4 立即停止契约：user 写未结算前 stop 不完成；放行后 user 行落库且'
        'reload 已执行（AR-2）', () async {
      // 无 first_mes 角色 → autoGreeting 零写 → 门控 user 写即门控整个结算
      // 信号。send 后立即 stop：stop 的完成依赖 cancel（ChatService onCancel 门
      // 等待 user 写结算）——修复前无此契约，该测试因竞态不可写。
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final gatedRepo = _GatedMessageRepository(db);
      final release = Completer<void>();
      gatedRepo
        ..gate = release
        ..gateRole = Role.user;
      // 注入的 reload 既计数（断言「reload 已执行」）又读真实 DB（断言
      // reload 载荷 = cancel resolve 后必见已发 user）。
      var reloadCalls = 0;
      final env = wireRound(
        FakeLLMProvider(tokens: const ['x']),
        messageRepository: gatedRepo,
        reloadMessages: () async {
          reloadCalls++;
          return messageRepo.getMessages(conv.id);
        },
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await gatedRepo.entered.future; // user 写已进入门（挂起待放行）。

      final stopFuture = env.round.stop(currentConversationId: conv.id);
      var stopped = false;
      stopFuture.then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero); // 事件循环轮转，零墙钟。
      expect(stopped, isFalse,
          reason: 'user 写未结算前 stop（取消）不得完成（门契约）');

      release.complete(); // 放行 user 写落库。
      await stopFuture; // 写结算后 stop 完成。
      expect(stopped, isTrue, reason: 'user 写结算后 stop 完成');

      // cancel resolve 保证写已结算 → reload 必见已发 user（不再需要轮询补偿）。
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)], [(Role.user, 'hi')],
          reason: 'user 行已落库（立即停止路径）');
      expect(reloadCalls, greaterThanOrEqualTo(1),
          reason: 'stop 后 reload 已执行');
    });
  });

  group('interrupted · 断流（A5）', () {
    test('断流 → 非阻塞 notice「回复已中断」+ 部分落库', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(TickingFakeLLMProvider(
        tokens: const ['a'],
        delay: const Duration(milliseconds: 10),
        errorAfter: LLMConnectionInterruptedError(),
      ));

      env.round.send(conversationId: conv.id, text: 'hi');

      await _until(() async => env.notice.notice == '回复已中断',
          why: '断流 notice');
      expect(env.round.isStreaming, isFalse);
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'a')],
          reason: '已累积部分落库');
    });

    test('断流有部分内容 → isInterrupted 标记，isStopped 假（两标互斥）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(TickingFakeLLMProvider(
        tokens: const ['a'],
        delay: const Duration(milliseconds: 10),
        errorAfter: LLMConnectionInterruptedError(),
      ));

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 2,
          why: '截断行落库');

      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue,
          reason: '截断回复标「回复中断」（UI 侧标记）');
      expect(env.round.isStopped(partial.id), isFalse,
          reason: '断流非主动停止，「已停止」与「回复中断」不并存于同一消息');
      expect(env.round.hasInterrupted, isTrue, reason: '存在可重试截断目标');
    });

    test('断流零部分内容（ChatInterrupted(null)）→ 无标记、无重试目标', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        TickingFakeLLMProvider(
          tokens: const [],
          errorAfter: LLMConnectionInterruptedError(),
        ),
        // 无 token 的连接中断属「首 token 前」重试窗口：注入空退避序列以便
        // 直接收束（生产为 [1s,2s] 退避耗尽后到该终态）。
        connectRetryDelays: const [],
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');

      expect(env.round.hasInterrupted, isFalse,
          reason: '零部分内容无截断目标（重试目标解析语义自洽）');
      expect(env.round.isInterrupted(-999), isFalse);
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) m.role], [Role.user],
          reason: '无部分内容不落空 assistant');
    });
  });

  group('retryInterrupted · 断流重试（M6-08）', () {
    test('重试成功 → 对截断目标 regenerate（候选追加）：消息行数不变、active 切'
        '最新候选、标记与 notice 一并结算', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '新回复'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 2,
          why: '截断行落库');
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue,
          reason: '截断标记前置条件');

      await env.round.retryInterrupted(conversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2),
          reason: '候选语义：截断行保留（消息数不变、不新增 user 行、无重复输入）');
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: 'addSwipe(make_active)：active content 覆写为新回复');
      final swipes = await messageRepo.listSwipes(partial.id);
      expect([for (final s in swipes) s.index], [0, 1],
          reason: '候选 0 = 截断原文播种、1 = 新回复（原回复保留为候选）');
      expect([for (final s in swipes) s.content], ['a', '新回复'],
          reason: '候选内容逐条保留');
      expect(env.round.hasInterrupted, isFalse, reason: '重试成功无可重试目标');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '结算键 = 目标消息 id：标记随新候选移除');
      expect(env.notice.notice, isNull, reason: '中断已解决，notice 清空');
      expect(env.round.isRegenerating, isFalse, reason: '防并发标志复位');
    });

    test('图标 regenerate（缺省末条）为截断消息追加候选 → 标记与 notice 一并清除'
        '（B1=W6 F-1 死重试按钮回归）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '新回复'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 2,
          why: '截断行落库');
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);
      expect(env.round.interruptedNoticeTargetId, partial.id);

      // 用户点气泡「重生成」图标（非横幅重试）：缺省目标 = 末条 assistant =
      // 截断消息。修复前 regenerate 成功不清标记/notice → 残留死重试。
      await env.round.regenerate(conversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2),
          reason: '图标 regenerate 候选追加成功：消息行数不变');
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: 'active content 覆写为新回复');
      expect(await messageRepo.listSwipes(partial.id), hasLength(2),
          reason: '截断原文保留为候选 0');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '修复后截断标记清除');
      expect(env.round.hasInterrupted, isFalse);
      expect(env.round.interruptedNoticeTargetId, isNull,
          reason: 'notice 目标已解决');
      expect(env.notice.notice, isNull,
          reason: '横幅「回复已中断」清空——后续再点重试不再触发死路径');
      expect(env.round.isRegenerating, isFalse);
    });

    test('F-64：图标 regenerate 结算键 = (目标消息 id, swipeIndex)（消费过程结果'
        '而非调用前推断，零预解析）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '新回复'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 2,
          why: '截断行落库');
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);
      expect(env.round.interruptedNoticeTargetId, partial.id);

      // 图标路径零预解析（messageId: null 走服务缺省）；结算键 = 服务返回的
      // 目标消息 id + 新候选 swipeIndex（候选追加语义下目标行 id 不删恒命中）。
      await env.round.regenerate(conversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2),
          reason: '图标 regenerate 候选追加成功（服务缺省目标 = 末条 assistant）');
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: 'active content 切换为新候选');
      expect(await messageRepo.listSwipes(partial.id), hasLength(2),
          reason: '旧回复保留为候选（候选语义可观察差异）');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '结算键 = 目标行 id：截断标记随新候选移除');
      expect(env.round.hasInterrupted, isFalse);
      expect(env.round.interruptedNoticeTargetId, isNull,
          reason: '被解目标 == notice 目标：notice 目标复位');
      expect(env.notice.notice, isNull, reason: '横幅「回复已中断」清空');
      expect(env.round.isRegenerating, isFalse);
    });

    test('F-65②：重试挂起期并发 notice 注入 → 放行后并发 notice 保留'
        '（文案门：不清「导出成功」）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = _GatedInterruptRetryProvider(reply: '新回复');
      final env = wireRound(provider,
          reloadMessages: () => messageRepo.getMessages(conv.id));

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 2,
          why: '截断行落库');
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);

      // 发起重试：generate 挂起于 gate（网络窗口）。
      final retry = env.round.retryInterrupted(conversationId: conv.id);
      await _until(() async => provider.generateCallCount >= 1,
          why: 'generate 已进入挂起');

      // 挂起期并发 notice 注入（覆盖「回复已中断」）。
      env.notice.set('导出成功');

      // 放行重试 → 结算完成（文案门未命中 → 不吞并发提示）。
      provider.gate.complete();
      await retry;

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2),
          reason: '重试候选追加成功：消息行数不变');
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: 'active content 切换为新候选');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '目标标记已结算（新候选追加）');
      expect(env.round.interruptedNoticeTargetId, isNull,
          reason: '无余标：notice 目标复位');
      expect(env.notice.notice, '导出成功',
          reason: 'F-65②：结算文案门（notice==回复已中断）未命中 → 并发提示保留');
      expect(env.round.isRegenerating, isFalse);
    });

    test('重试失败 → 旧截断行保留 + 既有 notice 保持「回复已中断」（先错者胜）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptThenAuthFailProvider(),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 2,
          why: '截断行落库');
      final partial = (await messageRepo.getMessages(conv.id)).last;

      await env.round.retryInterrupted(conversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'a')],
          reason: '失败零落库：旧截断行与候选均保留');
      expect(env.round.isInterrupted(partial.id), isTrue, reason: '标记保留');
      expect(env.notice.notice, '回复已中断',
          reason: '先错者胜：既有「回复已中断」不被失败文案覆盖');
      expect(env.round.isRegenerating, isFalse, reason: '失败后防并发标志复位');
    });

    test('重试期间 isRegenerating 防并发（重复重试被忽略）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = InterruptStreamRetryProvider(reply: '新回复');
      final env = wireRound(provider,
          reloadMessages: () => messageRepo.getMessages(conv.id));

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');

      // 首次重试进行中（同步置 isRegenerating）再触发第二次 → 守卫忽略。
      await env.round.retryInterrupted(conversationId: conv.id);
      await env.round.retryInterrupted(conversationId: conv.id);

      expect(provider.generateCallCount, 1,
          reason: '重试期间重复重试被忽略（isRegenerating 守卫）');
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) m.role], [Role.user, Role.assistant],
          reason: '无重复生成/无重复行');
    });

    test('无截断目标（零部分断流）→ retryInterrupted 零副作用', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        TickingFakeLLMProvider(
          tokens: const [],
          errorAfter: LLMConnectionInterruptedError(),
        ),
        connectRetryDelays: const [],
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      expect(env.round.hasInterrupted, isFalse);

      await env.round.retryInterrupted(conversationId: conv.id);
      expect(env.round.isRegenerating, isFalse, reason: '无目标不进入重试');
      expect(env.notice.notice, '回复已中断', reason: '既有 notice 不受影响');
    });
  });

  group('reload 窗口 · ③（F-65③：窗口内重试不可达，无静默 no-op）', () {
    test('done 收尾前 _reloadPending 保持 → 重试判据关闭（按钮不可达）；'
        'done 收尾后判据恢复（按钮弹入可用）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final service = _ScriptedChatService();
      final env = wireRound(
        FakeLLMProvider(tokens: const []),
        serviceOverride: service,
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      // 受控投递：先 token（有内容）再断流（截断目标 id=1）。
      service.events.add(const ChatToken('a'));
      service.events.add(const ChatInterrupted(1));
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');

      // 未 close：onDone 未触发 → _reloadPending 仍 true（reload 一帧窗口内）。
      expect(env.round.interruptedNoticeTargetId, 1,
          reason: '截断目标已解析（判据前置）');
      expect(env.round.hasRetryableInterrupted, isFalse,
          reason: 'F-65③：reload 窗口内重试判据随 _reloadPending 关闭——重试'
              '按钮不可达，杜绝「窗口内点击静默 no-op」');

      // done 收尾：重载触发 → 窗口结束 → 判据恢复（按钮弹入，可重试）。
      await service.events.close();
      await _until(() async => env.round.hasRetryableInterrupted,
          why: 'reload 收尾后按钮弹入可用');
      expect(env.reloadCalls, greaterThanOrEqualTo(1), reason: 'done 触发重载');
      env.round.dispose();
    });
  });

  group('标记状态机 · 断流/停止/重试交错（M6-08 Falsify）', () {
    test('先断流 → 重试成功 → 再发送断流：标记仅落在新截断目标（无残留）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '新回复'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      // 第一轮：断流 + 重试成功。
      env.round.send(conversationId: conv.id, text: '第一问');
      await _until(() async => env.notice.notice == '回复已中断', why: '第一次断流');
      final firstPartial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(firstPartial.id), isTrue);
      await env.round.retryInterrupted(conversationId: conv.id);
      expect(env.round.hasInterrupted, isFalse, reason: '重试成功标记清空');
      expect(env.round.isInterrupted(firstPartial.id), isFalse,
          reason: '旧目标标记无残留');

      // 第二轮：再发送再断流 → 标记仅落在新截断行。
      env.round.send(conversationId: conv.id, text: '第二问');
      await _until(() async => env.notice.notice == '回复已中断', why: '第二次断流');
      final secondPartial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(secondPartial.id), isTrue,
          reason: '新截断行标记');
      expect(env.round.hasInterrupted, isTrue);
      expect(env.round.isInterrupted(firstPartial.id), isFalse,
          reason: '旧目标（已被替换删除）不再在列表中');
    });

    test('停止不产生「回复中断」标记；断流不产生「已停止」标记', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        TickingFakeLLMProvider(
          tokens: const ['a', 'b'],
          delay: const Duration(milliseconds: 10),
        ),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.round.streamingText.isNotEmpty, why: '已累积 token');
      await env.round.stop(currentConversationId: conv.id);

      final stopped = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isStopped(stopped.id), isTrue, reason: '主动停止标「已停止」');
      expect(env.round.isInterrupted(stopped.id), isFalse,
          reason: '主动停止不产生「回复中断」标记');
      expect(env.round.hasInterrupted, isFalse);
    });

    test('上轮截断尚存时新一轮零内容断流 → notice 目标复位 null（不指向上一轮'
        '截断，F-4）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = _ContentThenZeroInterruptProvider();
      final env = wireRound(
        provider,
        reloadMessages: () => messageRepo.getMessages(conv.id),
        connectRetryDelays: const [],
      );

      // 第一轮：有内容断流 → notice 目标为该截断消息。
      env.round.send(conversationId: conv.id, text: '第一问');
      await _until(() async => env.notice.notice == '回复已中断', why: '第一次断流');
      final firstPartial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.interruptedNoticeTargetId, firstPartial.id);

      // 第二轮：零内容断流（ChatInterrupted(null)）→ 提示仍「回复已中断」但
      // notice 目标复位为 null（不指向上一轮截断）。
      env.round.send(conversationId: conv.id, text: '第二问');
      await _until(() async => env.notice.notice == '回复已中断', why: '第二次断流');
      expect(env.round.interruptedNoticeTargetId, isNull,
          reason: '零内容断流无截断目标，横幅重试不指向上一条截断');
      expect(env.round.hasInterrupted, isTrue,
          reason: '上一轮截断气泡小标保留（标记面独立于 notice 目标面）');

      // 且横幅重试零副作用（不重试上一轮截断、generate 未被调用）。
      final callsBefore = provider.generateCallCount;
      await env.round.retryInterrupted(conversationId: conv.id);
      expect(provider.generateCallCount, callsBefore,
          reason: '无可重试目标，retry 零副作用');
      expect(env.round.isRegenerating, isFalse);
      expect(env.notice.notice, '回复已中断');

      // F-4 配对门补断言：零内容断流态（target==null）下图标重生成旧截断
      // （缺省末条 = 上轮截断 A）→ 配对门（target(null) != replacedId(A)）不
      // 误清横幅——notice 保持「回复已中断」、notice 目标保持 null。
      await env.round.regenerate(conversationId: conv.id);
      expect(provider.generateCallCount, callsBefore + 1,
          reason: '图标 regenerate 走服务缺省（零预解析）');
      expect(env.notice.notice, '回复已中断',
          reason: '配对门：target==null 态图标重生成不清横幅');
      expect(env.round.interruptedNoticeTargetId, isNull,
          reason: 'notice 目标保持 null（零内容断流态无重试目标）');
      expect(env.round.hasInterrupted, isFalse,
          reason: '旧截断行已被替换删除，气泡标记随结算移除');
    });

    test('F-65①：双截断部分重试 → 目标推进到最近剩余截断、横幅保持 → 再重试 → '
        '全清（候选语义：DB 行保留，A/B 均 active 切新回复）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '新回复'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      // 第一轮：断流 → 截断 A。
      env.round.send(conversationId: conv.id, text: '第一问');
      await _until(() async => env.notice.notice == '回复已中断', why: '第一次断流');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 2,
          why: '截断 A 落库');
      final truncatedA = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.interruptedNoticeTargetId, truncatedA.id);

      // 第二轮：断流 → 截断 B（marks={A,B}，notice 目标 = B）。
      env.round.send(conversationId: conv.id, text: '第二问');
      await _until(() async => (await messageRepo.getMessages(conv.id)).length == 4,
          why: '截断 B 落库');
      final truncatedB = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.interruptedNoticeTargetId, truncatedB.id);
      expect(env.round.hasInterrupted, isTrue);

      // 重试 B：B 候选追加（行保留、active 切新回复），余标 A 推进为 notice
      // 目标、横幅保持。
      await env.round.retryInterrupted(conversationId: conv.id);
      expect(env.round.interruptedNoticeTargetId, truncatedA.id,
          reason: 'F-65① 目标推进 = max(marks)（DB 主键单调即时序）');
      expect(env.round.hasInterrupted, isTrue, reason: '余标 A 仍在');
      expect(env.round.isInterrupted(truncatedB.id), isFalse,
          reason: 'B 标记已结算（候选追加不删行，行保留）');
      expect(env.notice.notice, '回复已中断',
          reason: '横幅保持（notice 不清，持续指向最近剩余截断）');

      // 重试 A：A 候选追加（行保留）→ 标记全清、横幅消失。
      await env.round.retryInterrupted(conversationId: conv.id);
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [
            (Role.user, '第一问'),
            (Role.assistant, '新回复'), // A 行 active 切新回复
            (Role.user, '第二问'),
            (Role.assistant, '新回复'), // B 行 active 切新回复
          ],
          reason: '候选语义：双截断行保留（1 assistant + N 候选），不重写删除');
      expect(env.round.hasInterrupted, isFalse, reason: '全清');
      expect(env.round.interruptedNoticeTargetId, isNull);
      expect(env.notice.notice, isNull, reason: '中断全部解决，横幅消失');
    });
  });

  group('regenerate · 重生成（A4）', () {
    test('成功：重载被调 + 候选追加（消息行数不变、active 切最新、旧回复保留为候选）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final userMsg =
          await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      final oldReply = await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '旧回复');
      final env = wireRound(FakeLLMProvider(tokens: const ['新回复']));

      await env.round.regenerate(conversationId: conv.id);

      expect(env.reloadCalls, greaterThanOrEqualTo(1), reason: '成功重载列表');
      expect(env.round.isRegenerating, isFalse, reason: '完成复位');
      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2),
          reason: '候选语义：消息行数不变（1 user + 1 assistant）');
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: 'active content 切换为最新候选');
      expect(msgs.last.id, oldReply.id,
          reason: '目标消息行保留（候选归属行 id 不变）');
      expect(userMsg.id, msgs.first.id);
      final swipes = await messageRepo.listSwipes(oldReply.id);
      expect([for (final s in swipes) s.index], [0, 1],
          reason: '候选 0 = 旧回复播种、1 = 新回复');
      expect([for (final s in swipes) s.content], ['旧回复', '新回复'],
          reason: '旧回复保留为候选（可对比，不丢失历史）');
    });

    test('失败（LLM 生成抛错）→ notice 折叠；不删行、旧回复保留', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '旧回复');
      final env = wireRound(
        TickingFakeLLMProvider(errorAfter: LLMError('boom')),
      );

      await env.round.regenerate(conversationId: conv.id);

      expect(env.notice.notice, 'boom',
          reason: 'LLMError 经 llmErrorResponse 折叠（先错者胜）');
      expect(env.round.isRegenerating, isFalse);
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '旧回复')],
          reason: '失败零落库：旧回复与候选均保留');
    });
  });

  group('操作编排 · continueReply（MS-02 契约：swipeIndex / -1 哨兵）', () {
    test('继续生成成功 → 消息行数不变、内容 = 原回复 + 续写片段、候选追加置激活',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      final reply = await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '原文');
      final env = wireRound(
        FakeLLMProvider(tokens: const ['续']),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      await env.round.continueReply(conversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2),
          reason: '续写不新增消息行（候选追加，不产生新 user）');
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '原文续')],
          reason: 'active 候选 = 原内容 + 续写片段');
      expect(msgs.last.id, reply.id, reason: '候选归属行不变');
      final swipes = await messageRepo.listSwipes(reply.id);
      expect([for (final s in swipes) s.index], [0, 1],
          reason: '候选 0 = 原回复播种、1 = 续写结果');
      expect(env.round.isRegenerating, isFalse, reason: '防并发标志复位');
    });

    test('截断消息继续生成成功 → 结算键 (messageId, swipeIndex)：标记与 notice 清除',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '补全'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);

      await env.round.continueReply(conversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2), reason: '消息行数不变');
      expect(msgs.last.content, 'a补全',
          reason: '截断内容 + 续写片段成为新 active 候选');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '目标消息获得新候选 = 回复已修复 → 截断标记结算');
      expect(env.round.hasInterrupted, isFalse);
      expect(env.round.interruptedNoticeTargetId, isNull);
      expect(env.notice.notice, isNull, reason: 'notice 目标已解决并清空');
    });

    test('空续写（swipeIndex = -1 哨兵）→ 不落重复候选、不结算截断标记', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        _InterruptThenEmptyContinueProvider(),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);

      await env.round.continueReply(conversationId: conv.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs.last.content, 'a',
          reason: '空续写 no-op：内容零改动');
      expect(await messageRepo.listSwipes(partial.id), isEmpty,
          reason: '-1 哨兵：未追加候选（无重复候选行）');
      expect(env.round.isInterrupted(partial.id), isTrue,
          reason: '无新候选 → 截断标记保留（未结算）');
      expect(env.notice.notice, '回复已中断',
          reason: '既有中断提示保留（-1 不推进 notice 目标）');
    });

    test('继续生成失败 → notice 单源映射、零候选、内容不变', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      final reply = await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '原文');
      final env = wireRound(
        TickingFakeLLMProvider(errorAfter: LLMError('boom')),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      await env.round.continueReply(conversationId: conv.id);

      expect(env.notice.notice, 'boom',
          reason: 'LLMError 经 chatErrorMessage 单源映射');
      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs.last.content, '原文', reason: '失败零落库、内容不变');
      expect(await messageRepo.listSwipes(reply.id), isEmpty,
          reason: '失败不产生候选');
      expect(env.round.isRegenerating, isFalse);
    });

    test('regenerate 挂起期 continueReply → 被忽略（isRegenerating 共享防并发）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '旧回复');
      final provider = _GatedInterruptRetryProvider(reply: '新回复');
      final env = wireRound(provider,
          reloadMessages: () => messageRepo.getMessages(conv.id));

      final regen = env.round.regenerate(conversationId: conv.id);
      await _until(() async => provider.generateCallCount >= 1,
          why: 'generate 已挂起');
      await env.round.continueReply(conversationId: conv.id);

      provider.gate.complete();
      await regen;

      expect(provider.generateCallCount, 1,
          reason: 'continueReply 在 regenerate 挂起期被守卫忽略');
      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2), reason: '仅 regenerate 一次候选追加');
      expect(env.round.isRegenerating, isFalse);
    });
  });

  group('操作编排 · switchSwipe（候选切换）', () {
    test('切换成功 → reload 反映新 active 内容与 DB active index', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      final reply = await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '原回复');
      await messageRepo.addSwipe(reply.id, '候选一', makeActive: true);
      await messageRepo.addSwipe(reply.id, '候选二', makeActive: true);
      late _RoundEnv env;
      env = wireRound(
        FakeLLMProvider(tokens: const []),
        reloadMessages: () async {
          env.reloadCalls++;
          return messageRepo.getMessages(conv.id);
        },
      );

      await env.round.switchSwipe(
          conversationId: conv.id, messageId: reply.id, index: 1);

      expect(env.reloadCalls, greaterThanOrEqualTo(1), reason: '切换后重载列表');
      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs.last.content, '候选一', reason: 'active 切换为 index 1 候选');
      expect(msgs.last.activeSwipeIndex, 1, reason: 'DB active index 同步');
    });

    test('越界 index → notice「候选序号不存在」、active 不变、守卫复位', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      final reply = await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '原回复');
      await messageRepo.addSwipe(reply.id, '候选一', makeActive: true);
      final env = wireRound(FakeLLMProvider(tokens: const []));

      await env.round.switchSwipe(
          conversationId: conv.id, messageId: reply.id, index: 99);

      expect(env.notice.notice, '候选序号不存在: 99',
          reason: 'SwipeIndexOutOfRangeError 经 chatErrorMessage 单源映射');
      expect((await messageRepo.getMessages(conv.id)).last.content, '候选一',
          reason: '失败不切换 active');
      expect(env.round.isBusy, isFalse, reason: '失败后忙碌态复位');
    });

    test('目标不存在（跨对话/已删）→ notice「消息不存在」', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(FakeLLMProvider(tokens: const []));

      await env.round.switchSwipe(
          conversationId: conv.id, messageId: 9999, index: 0);

      expect(env.notice.notice, '消息不存在',
          reason: '归属校验失败经 chatErrorMessage 单源映射');
      expect(env.round.isBusy, isFalse);
    });

    test('切换挂起期重复触发 → 被忽略（防并发守卫；放行后仅一次切换）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      final reply = await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '原回复');
      await messageRepo.addSwipe(reply.id, '候选一', makeActive: true);
      final gated = _GatedSwitchRepository(db);
      final gate = Completer<void>();
      gated.gate = gate;
      final env = wireRound(FakeLLMProvider(tokens: const []),
          messageRepository: gated,
          reloadMessages: () => messageRepo.getMessages(conv.id));

      final first = env.round.switchSwipe(
          conversationId: conv.id, messageId: reply.id, index: 1);
      await _until(() async => gated.entered.isCompleted, why: '切换已挂起');
      await env.round.switchSwipe(
          conversationId: conv.id, messageId: reply.id, index: 1);

      gate.complete();
      await first;

      expect(gated.switchCalls, 1,
          reason: '挂起期重复切换被防并发守卫忽略');
      expect(env.round.isBusy, isFalse, reason: '完成后忙碌态复位');
    });
  });

  group('操作编排 · deleteMessage / editMessage（MS-03 服务 + 截断标记结算）', () {
    test('删 user → 截断后续（含截断 assistant）；被删截断标记与 notice 结算清空',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '新回复'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      final userMsg = (await messageRepo.getMessages(conv.id)).first;
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);

      await env.round.deleteMessage(
          conversationId: conv.id, messageId: userMsg.id);

      expect(await messageRepo.getMessages(conv.id), isEmpty,
          reason: '删 user 截断含自身及后续（候选级联删）');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '幽灵防御：被删截断行标记随 reload prune');
      expect(env.round.hasInterrupted, isFalse);
      expect(env.round.interruptedNoticeTargetId, isNull,
          reason: 'notice 目标已随删除结算');
      expect(env.notice.notice, isNull, reason: '无遗留死重试横幅');
      expect(env.round.isBusy, isFalse);
    });

    test('删 assistant → 仅删该条、后续保留、无关截断标记不受影响', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final user1 =
          await seedMessage(conversationId: conv.id, role: Role.user, content: 'u1');
      final assistant = await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: 'a1');
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'u2');
      final env = wireRound(FakeLLMProvider(tokens: const []));

      await env.round.deleteMessage(
          conversationId: conv.id, messageId: assistant.id);

      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'u1'), (Role.user, 'u2')],
          reason: '删 assistant 仅删该条、后续保留');
      expect(user1.id, msgs.first.id);
    });

    test('删除失败（目标不存在）→ notice「消息不存在」、列表不变', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      final env = wireRound(FakeLLMProvider(tokens: const []));

      await env.round.deleteMessage(
          conversationId: conv.id, messageId: 9999);

      expect(env.notice.notice, '消息不存在');
      expect(await messageRepo.getMessages(conv.id), hasLength(1),
          reason: '失败零副作用');
      expect(env.round.isBusy, isFalse);
    });

    test('编辑重发成功 → user 就地替换 + 截断后续 + 新 assistant；行数不变', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final userMsg =
          await seedMessage(conversationId: conv.id, role: Role.user, content: '你好');
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '旧回复');
      final env = wireRound(
        FakeLLMProvider(tokens: const ['新回复']),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      await env.round.editMessage(
          conversationId: conv.id, messageId: userMsg.id, newContent: '修正');

      final msgs = await messageRepo.getMessages(conv.id);
      expect(msgs, hasLength(2), reason: '编辑不新增行（user 就地替换 + 新 assistant）');
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, '修正'), (Role.assistant, '新回复')],
          reason: '截断旧后续 + 生成新回复');
      expect(env.round.isRegenerating, isFalse, reason: '生成类守卫复位');
    });

    test('编辑截断后续 → 被删截断标记 prune、notice 结算', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(
        InterruptStreamRetryProvider(reply: '新回复'),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      final userMsg = (await messageRepo.getMessages(conv.id)).first;
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);

      await env.round.editMessage(
          conversationId: conv.id, messageId: userMsg.id, newContent: '修正');

      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, '修正'), (Role.assistant, '新回复')],
          reason: '编辑截断旧回复并生成新回复');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '幽灵防御：被截断删除的标记随 reload prune');
      expect(env.round.hasInterrupted, isFalse);
      expect(env.notice.notice, isNull, reason: '中断已结算');
    });

    test('编辑失败 → notice 单源映射 + 已替换已截断状态保留（服务层语义）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final userMsg =
          await seedMessage(conversationId: conv.id, role: Role.user, content: '你好');
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '旧回复');
      final env = wireRound(
        TickingFakeLLMProvider(errorAfter: LLMError('boom')),
        reloadMessages: () => messageRepo.getMessages(conv.id),
      );

      await env.round.editMessage(
          conversationId: conv.id, messageId: userMsg.id, newContent: '修正');

      expect(env.notice.notice, 'boom', reason: 'chatErrorMessage 单源映射');
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, '修正')],
          reason: '编辑失败保留已替换 + 已截断状态（用户可再 regenerate）');
      expect(env.round.isRegenerating, isFalse);
    });
  });

  group('isBusy · 操作进行中状态面', () {
    test('regenerate 挂起期 isBusy true；完成后复位', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '旧回复');
      final provider = _GatedInterruptRetryProvider(reply: '新回复');
      final env = wireRound(provider,
          reloadMessages: () => messageRepo.getMessages(conv.id));

      final regen = env.round.regenerate(conversationId: conv.id);
      await _until(() async => provider.generateCallCount >= 1,
          why: 'generate 已挂起');
      expect(env.round.isBusy, isTrue, reason: '生成类操作进行中忙碌');

      provider.gate.complete();
      await regen;
      expect(env.round.isBusy, isFalse, reason: '完成后复位');
    });
  });

  group('导航面 · resetForNavigation', () {
    test('清在途合成；后台流不中止、token 继续落库（后台流语义）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 20),
      ));

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.round.streamingText.isNotEmpty,
          why: '首个 token 到达');

      // openConversation / backToEntry 共用清理：清在途，流不中止（后台继续）。
      env.round.resetForNavigation();

      expect(env.round.pendingUserText, isNull, reason: '在途 user 清空');
      expect(env.round.streamingText, isEmpty, reason: '占位文本清空');
      expect(env.round.isStreaming, isTrue,
          reason: '后台流不中止（对齐 backToEntry 语义）');
      expect(env.round.hasSyntheticAssistant, isTrue,
          reason: '后台流继续渲染占位（占位 id 生命周期随回合）');

      // 后台流继续：token 持续到达并完整落库（reset 不清回合生命周期）。
      await _until(() async => !env.round.isStreaming, why: '后台流自然完成');
      expect(env.reloadCalls, greaterThanOrEqualTo(1),
          reason: '自然终态（ChatDone → _finishRound）经 reloadMessages 重载');
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'ab')],
          reason: 'reset 后 token 仍继续落库（后台流完整落地）');
    });

    test('截断标记随 resetForNavigation 清空（跨会话不串标，验收 6）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final env = wireRound(TickingFakeLLMProvider(
        tokens: const ['a'],
        delay: const Duration(milliseconds: 10),
        errorAfter: LLMConnectionInterruptedError(),
      ));

      env.round.send(conversationId: conv.id, text: 'hi');
      await _until(() async => env.notice.notice == '回复已中断', why: '断流 notice');
      final partial = (await messageRepo.getMessages(conv.id)).last;
      expect(env.round.isInterrupted(partial.id), isTrue);

      env.round.resetForNavigation();

      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '返回入口/切换会话清理截断标记');
      expect(env.round.hasInterrupted, isFalse);
    });
  });
}