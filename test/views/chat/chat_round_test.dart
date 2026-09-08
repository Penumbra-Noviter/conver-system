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
  }) async {
    generateCallCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    return '新回复';
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

  /// 装配 ChatRound：驱动真实 ChatService + [provider]；[reloadMessages] 缺省
  /// 为「计数 + 返回 [env.reloaded]」，测试可注入定制重载语义（如会话内停止
  /// 经真实仓储读末条）。[connectRetryDelays] 透传 ChatService 连接阶段重试
  /// 退避序列（零部分断流测试注入空序列跳过 1s/2s 生产退避）。
  _RoundEnv wireRound(
    LLMProvider provider, {
    Future<List<Message>> Function()? reloadMessages,
    List<Duration> connectRetryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) {
    final service = ChatService(
      database: db,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: FixedLLMProviderFactory(provider),
      connectRetryDelays: connectRetryDelays,
    );
    late _RoundEnv env;
    final notice = NoticeRunner();
    final round = ChatRound(
      chatService: service,
      messageRepository: messageRepo,
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
    test('重试成功 → 对截断目标 regenerate：截断行替换、不新增 user 行、标记清、'
        'notice 清', () async {
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
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: 'replace 语义：截断行被替换、不新增 user 行、无重复输入');
      expect(env.round.hasInterrupted, isFalse, reason: '重试成功无可重试目标');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '目标标记随替换清除');
      expect(env.notice.notice, isNull, reason: '中断已解决，notice 清空');
      expect(env.round.isRegenerating, isFalse, reason: '防并发标志复位');
    });

    test('图标 regenerate（缺省末条）替换截断消息 → 标记与 notice 一并清除'
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
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: '图标 regenerate replace 成功');
      expect(env.round.isInterrupted(partial.id), isFalse,
          reason: '修复后截断标记清除');
      expect(env.round.hasInterrupted, isFalse);
      expect(env.round.interruptedNoticeTargetId, isNull,
          reason: 'notice 目标已解决');
      expect(env.notice.notice, isNull,
          reason: '横幅「回复已中断」清空——后续再点重试不再触发死路径');
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
          reason: '失败不删行、旧截断行保留（延迟删除语义）');
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
    });
  });

  group('regenerate · 重生成（A4）', () {
    test('成功：重载被调 + 新回复替换旧行', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conversationId: conv.id, role: Role.user, content: 'hi');
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '旧回复');
      final env = wireRound(FakeLLMProvider(tokens: const ['新回复']));

      await env.round.regenerate(conversationId: conv.id);

      expect(env.reloadCalls, greaterThanOrEqualTo(1), reason: '成功重载列表');
      expect(env.round.isRegenerating, isFalse, reason: '完成复位');
      final msgs = await messageRepo.getMessages(conv.id);
      expect([for (final m in msgs) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')]);
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
          reason: '失败不删行、旧回复保留（延迟删除语义）');
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