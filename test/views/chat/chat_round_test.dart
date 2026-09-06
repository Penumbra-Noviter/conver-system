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
  /// 经真实仓储读末条）。
  _RoundEnv wireRound(
    LLMProvider provider, {
    Future<List<Message>> Function()? reloadMessages,
  }) {
    final service = ChatService(
      database: db,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: FixedLLMProviderFactory(provider),
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
  });
}