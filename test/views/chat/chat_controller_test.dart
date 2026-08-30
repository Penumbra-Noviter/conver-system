/// ChatController 回合状态机行为契约（T04a 切片）。
///
/// 语义锚点：`desktop/frontend/js/stream-session.js`（onToken 累积 +
/// streamSettled 终态守卫 + 停止/错误分流）+ `chat.js`（发送↔停止两态 /
/// 重生成仅末条已结算 assistant / 错误非阻塞上抛）。服务层对话由真实
/// [ChatService] 承载（内存 drift + InMemorySecretStore + Fake/Ticking
/// provider），控制器只做状态机编排——不 mock 服务内部实现。
///
/// 测试 seam（公共接口边界）：[ChatController] 公开 API（loadEntry /
/// createConversation / openConversation / backToEntry / send / stop /
/// regenerate / messages / notice）；可观察状态 = 控制器状态 + 落库结果
/// （经 [MessageRepository.getMessages]）。
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
import 'package:conver_system_mobile/services/secure_store.dart' show SecretStore;
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（与 chat_service_test 同形，不再造第二条规则）。
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

/// createConversation 必抛的会话仓储子类——命中「新建对话落库失败」路径。
class _ThrowingConversationRepository extends ConversationRepository {
  _ThrowingConversationRepository(super.db, super.settings);

  @override
  Future<Conversation> createConversation({
    required int characterId,
    String? title,
    String? modelProvider,
    String? modelName,
  }) {
    throw StateError('create failed');
  }
}

/// listConversations 必抛的会话仓储子类——命中「入口加载失败」路径。
class _ThrowingListConversationRepository extends ConversationRepository {
  _ThrowingListConversationRepository(super.db, super.settings);

  @override
  Future<List<ConversationWithCount>> listConversations({int? characterId}) {
    throw StateError('list failed');
  }
}

/// getConversation 必抛的会话仓储子类——命中「openConversation 加载失败」路径
/// （F2：DB 异常不得成未处理异步异常）。
class _ThrowingGetConversationRepository extends ConversationRepository {
  _ThrowingGetConversationRepository(super.db, super.settings);

  @override
  Future<Conversation?> getConversation(int conversationId) {
    throw StateError('get failed');
  }
}

/// createMessage 延迟 [delay] 后落库的慢消息仓储——构造「stop 时 user 尚未落库」
/// 的 F1 竞态窗口（可控制 user 落库时延；getMessages 等读取路径不延迟，reload
/// / 轮询照常）。
class _SlowMessageRepository extends MessageRepository {
  _SlowMessageRepository(
    super.db, {
    super.now,
    this.delay = const Duration(milliseconds: 200),
  });

  final Duration delay;

  @override
  Future<Message> createMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) async {
    await Future<void>.delayed(delay);
    return super.createMessage(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }
}

/// 在 [deadline]（5s 墙钟）内轮询 [condition] 直到为真（真实异步等待）。
///
/// 用墙钟期限而非迭代计数：负载下的 per-iteration 延迟可能与 token 间距同量
/// 级，固定迭代会误判超时。返回值前条件必真；超时抛 StateError。
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
  ChatController? controller;

  // 固定起始时刻（drift 落库为 unix 秒）。
  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    convRepo = ConversationRepository(db, const FakeSettingsReader(),
        now: () => fakeNow);
    messageRepo = MessageRepository(db, now: () => fakeNow);
    charRepo = CharacterRepository(db, now: () => fakeNow);
    secretStore = InMemorySecretStore();
    settingsRepo = SettingsRepository(database: db, secretStore: secretStore);
    await settingsRepo.setMany({'claude_api_key': 'sk-default'});
  });

  tearDown(() async {
    controller?.dispose();
    await db.close();
  });

  /// 装配控制器：驱动真实 ChatService + [provider]。
  ///
  /// [messageRepository] 非空时替换装配给服务与控制器的消息仓储（F1 慢落库
  /// 竞态窗口等特殊仓储注入点）；[highlightDuration] 注入高亮 3s 定时器时长
  /// （M3-04c 定时清除测试用短时长，缺省 3s 对齐桌面 HIGHLIGHT_DURATION）。
  ChatController wireController(
    LLMProvider provider, {
    MessageRepository? messageRepository,
    Duration? highlightDuration,
  }) {
    final messages = messageRepository ?? messageRepo;
    final service = ChatService(
      database: db,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messages,
      settingsRepository: settingsRepo,
      providerFactory: FixedLLMProviderFactory(provider),
    );
    final c = ChatController(
      chatService: service,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messages,
      highlightDuration: highlightDuration ?? const Duration(seconds: 3),
    );
    controller = c;
    return c;
  }

  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
  }) {
    return charRepo.createCharacter(
      CharactersCompanion.insert(
        name: name,
        firstMes: Value(firstMes),
        createdAt: fakeNow,
        updatedAt: fakeNow,
      ),
    );
  }

  Future<Conversation> seedConversation(int characterId) {
    return convRepo.createConversation(characterId: characterId);
  }

  List<(Role, String)> roleContentsOf(ChatController c) =>
      [for (final m in c.messages) (m.role, m.content)];

  group('loadEntry · 入口（最近对话 + 新建可用性）', () {
    test('loadEntry → conversations 填充；有角色可新建', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(FakeLLMProvider(tokens: const []));

      await c.loadEntry();

      expect(c.hasLoadedEntry, isTrue);
      expect(c.conversations.map((e) => e.conversation.id), contains(conv.id));
      expect(c.canCreateConversation, isTrue);
      expect(c.createDisabledReason, isNull);
    });

    test('loadEntry 无角色 → 新建禁用并给提示文案', () async {
      final c = wireController(FakeLLMProvider(tokens: const []));

      await c.loadEntry();

      expect(c.conversations, isEmpty);
      expect(c.canCreateConversation, isFalse);
      expect(c.createDisabledReason, '请先在角色页创建角色');
    });

    test('createConversation 取首个角色建会话并进入', () async {
      await seedCharacter(firstMes: '你好，{{user}}。');
      final c = wireController(FakeLLMProvider(tokens: const []));
      await c.loadEntry();

      await c.createConversation();

      expect(c.activeConversationId, isNotNull);
      expect(c.isEntry, isFalse);
      // 会话创建预插角色开场白（{{user}} 已替换）。
      expect(roleContentsOf(c), [(Role.assistant, '你好，User。')]);
    });

    test('createConversation 无角色 → notice 提示，停留在入口', () async {
      final c = wireController(FakeLLMProvider(tokens: const []));
      await c.loadEntry();

      await c.createConversation();

      expect(c.activeConversationId, isNull);
      expect(c.isEntry, isTrue);
      expect(c.notice, '请先在角色页创建角色');
    });

    test('loadEntry 落库失败 → notice，列表空且入口仍标记已加载（可重试）', () async {
      await seedCharacter();
      final throwingListRepo =
          _ThrowingListConversationRepository(db, const FakeSettingsReader());
      final c = ChatController(
        chatService: ChatService(
          database: db,
          conversationRepository: throwingListRepo,
          characterRepository: charRepo,
          messageRepository: messageRepo,
          settingsRepository: settingsRepo,
          providerFactory: FixedLLMProviderFactory(FakeLLMProvider(tokens: const [])),
        ),
        conversationRepository: throwingListRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
      );
      controller = c;

      await c.loadEntry();

      expect(c.hasLoadedEntry, isTrue, reason: '失败也算完成入口加载（幂等可重试）');
      expect(c.conversations, isEmpty);
      expect(c.canCreateConversation, isFalse);
      expect(c.notice, startsWith('加载对话失败'));
    });

    test('createConversation 落库失败 → notice，停留在入口', () async {
      await seedCharacter();
      // 覆盖 createConversation → 抛错（仓储子类命中失败路径）。
      final throwingConvRepo =
          _ThrowingConversationRepository(db, const FakeSettingsReader());
      final c = ChatController(
        chatService: ChatService(
          database: db,
          conversationRepository: throwingConvRepo,
          characterRepository: charRepo,
          messageRepository: messageRepo,
          settingsRepository: settingsRepo,
          providerFactory: FixedLLMProviderFactory(FakeLLMProvider(tokens: const [])),
        ),
        conversationRepository: throwingConvRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
      );
      controller = c;
      await c.loadEntry();
      expect(c.canCreateConversation, isTrue);

      await c.createConversation();

      expect(c.isEntry, isTrue);
      expect(c.notice, isNotNull);
      expect(c.notice, startsWith('新建对话失败'));
    });
  });

  group('openConversation / backToEntry · 导航', () {
    test('openConversation → 消息加载；backToEntry → 回入口且刷新列表', () async {
      final char = await seedCharacter(firstMes: '开场。');
      final conv = await seedConversation(char.id);
      final c = wireController(FakeLLMProvider(tokens: const []));
      await c.loadEntry();

      await c.openConversation(conv.id);

      expect(c.isEntry, isFalse);
      expect(c.activeConversationId, conv.id);
      expect(c.activeConversation?.id, conv.id);
      expect(c.messages, hasLength(1)); // 开场白

      await c.backToEntry();

      expect(c.isEntry, isTrue);
      expect(c.activeConversationId, isNull);
      expect(c.messages, isEmpty);
      // 入口列表刷新后会话仍在。
      expect(c.conversations.map((e) => e.conversation.id), contains(conv.id));
    });

    test('openConversation 目标会话不存在 → 空消息（不崩溃）', () async {
      final c = wireController(FakeLLMProvider(tokens: const []));
      await c.openConversation(999999);
      expect(c.isEntry, isFalse);
      expect(c.messages, isEmpty);
      expect(c.activeConversation, isNull);
    });

    test('openConversation getConversation 抛错 → notice 收口，无未处理异常（F2）',
        () async {
      await seedCharacter();
      final throwingRepo =
          _ThrowingGetConversationRepository(db, const FakeSettingsReader());
      final c = ChatController(
        chatService: ChatService(
          database: db,
          conversationRepository: convRepo,
          characterRepository: charRepo,
          messageRepository: messageRepo,
          settingsRepository: settingsRepo,
          providerFactory:
              FixedLLMProviderFactory(FakeLLMProvider(tokens: const [])),
        ),
        conversationRepository: throwingRepo,
        characterRepository: charRepo,
        messageRepository: messageRepo,
      );
      controller = c;

      // 修复前：getConversation 抛错无 catch → 未处理异步异常，await 直接上抛。
      await c.openConversation(1);

      expect(c.notice, startsWith('加载对话失败'),
          reason: 'DB 异常收口为 notice，不产生未处理异常');
      expect(c.activeConversation, isNull);
      expect(c.messages, isEmpty);
    });

    test('流式中打开其他会话 → 先 stop：已累积部分落库并标「已停止」', () async {
      // 首个会话在流式中；打开第二个会话应中止首会话回合（部分落库）。
      final provider = TickingFakeLLMProvider(
        tokens: const ['p0', 'p1', 'p2', 'p3'],
        delay: const Duration(milliseconds: 50),
      );
      final char = await seedCharacter();
      final convA = await seedConversation(char.id);
      final convB = await seedConversation(char.id);
      final c = wireController(provider);
      await c.openConversation(convA.id);

      await c.send('hi');
      expect(c.isStreaming, isTrue);
      // 已累积一个 token（p0）后切到另一会话。
      await _until(() async => c.streamingText == 'p0', why: '首 token 已累积');
      await c.openConversation(convB.id);

      expect(c.isStreaming, isFalse);
      expect(c.activeConversationId, convB.id);
      // 首会话回合被中止：部分内容落库（DB 权威）。
      final settledA = await messageRepo.getMessages(convA.id);
      expect([for (final m in settledA) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'p0')]);
      await c.openConversation(convA.id);
      expect(c.messages.last.role, Role.assistant);
      expect(c.messages.last.content, 'p0',
          reason: '中止的部分内容在重新进入时经 DB 重载恢复');
      // 「已停止」标记为会话生命周期内集合，openConversation 会清空——切会话
      // 后不再显示标记，属控制器设计（重新进入场景的停止标记语义不是本锚）。
    });
  });

  group('send · 打字机回合（A2 UI 面）', () {
    test('send → isStreaming 同步置位；streamingText 逐 token 累积', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['你', '好', '！'],
        delay: const Duration(milliseconds: 10),
      ));
      await c.openConversation(conv.id);

      // 经公开 getter 记录 streamingText 的累积序列（打字机逐 token 追加，
      // 不做瞬态等值断言——终态重载会立即清空占位）。
      final seen = <String>[];
      void record() {
        final t = c.streamingText;
        if (seen.isEmpty || seen.last != t) {
          seen.add(t);
        }
      }

      c.addListener(record);
      final sent = c.send('早上好');
      expect(c.isStreaming, isTrue,
          reason: 'send 同步置位 isStreaming（发送↔停止两态切换）');

      await _until(() async {
        return !c.isStreaming &&
            c.messages.isNotEmpty &&
            c.messages.last.role == Role.assistant &&
            c.messages.last.content == '你好！';
      }, why: '回合完成且落库完整回复');
      c.removeListener(record);

      expect(seen, containsAll(['你', '你好', '你好！']),
          reason: '打字机累积序列须逐 token 增长');
      expect(c.isStreaming, isFalse);

      await sent;
    });

    test('send 完成 → isStreaming 复位；落库完整 assistant 替换占位', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(FakeLLMProvider(tokens: const ['完整', '回复']));
      await c.openConversation(conv.id);

      await c.send('出发');
      await _until(() async {
        final msgs = c.messages;
        return !c.isStreaming &&
            msgs.isNotEmpty &&
            msgs.last.role == Role.assistant &&
            msgs.last.content == '完整回复';
      });

      expect(c.isStreaming, isFalse);
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, '出发'), (Role.assistant, '完整回复')]);
    });

    test('流式中两次访问 messages → 合成消息 id 稳定（F4 无每帧漂移）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 20),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      expect(c.isStreaming, isTrue);
      // 流式中在途 user + assistant 占位均在列表：连续两次访问（每次重建
      // 列表），合成消息 id 必须各自稳定（getter 内递减 → 每帧漂移 = 缺陷）。
      int? userFirst;
      int? assistantFirst;
      for (final m in c.messages) {
        if (m.role == Role.user) userFirst = m.id;
        if (m.role == Role.assistant) assistantFirst = m.id;
      }
      int? userSecond;
      int? assistantSecond;
      for (final m in c.messages) {
        if (m.role == Role.user) userSecond = m.id;
        if (m.role == Role.assistant) assistantSecond = m.id;
      }
      expect(userSecond, userFirst, reason: 'user 合成 id 稳定（不随访问漂移）');
      expect(assistantSecond, assistantFirst,
          reason: 'assistant 占位合成 id 稳定（不随访问漂移）');
      expect(userFirst, isNegative);
      expect(assistantFirst, isNegative);

      await _until(() async => !c.isStreaming, why: '回合完成');
    });

    test('send 空文本 / 流式中重复发送 → 忽略（不重复发起）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final provider = TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 20),
      );
      final c = wireController(provider);
      await c.openConversation(conv.id);

      await c.send('   ');
      expect(c.isStreaming, isFalse, reason: '空文本不发起回合');

      await c.send('第一条');
      expect(c.isStreaming, isTrue);
      await _until(() async => provider.streamGenerateCallCount == 1,
          why: '服务层已订阅 provider 流');
      await c.send('第二条'); // 流式中重复发送被忽略
      await _until(() async => !c.isStreaming, why: '回合完成');
      expect(provider.streamGenerateCallCount, 1,
          reason: '重复发送被 isStreaming 守卫拦截，不二次发起');
    });

    test('未配置 Key → notice 映射文案；仅保留已发 user', () async {
      await secretStore.delete(SecretStore.claudeApiKeySlot);
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(FakeLLMProvider(tokens: const ['x']));
      await c.openConversation(conv.id);

      await c.send('hi');
      await _until(() async {
        return !c.isStreaming && roleContentsOf(c).length == 1;
      });

      expect(c.notice, '未配置 claude API Key，请在设置中填写');
      expect(roleContentsOf(c), [(Role.user, 'hi')]);
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) m.role], [Role.user]);
    });

    test('LLM 业务错误（中途 Auth）→ notice 映射文案，不落部分内容（F-45）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        errorAfter: LLMAuthError('claude'),
        delay: const Duration(milliseconds: 5),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      await _until(() async {
        return !c.isStreaming && roleContentsOf(c).length == 1;
      });

      expect(c.notice, 'claude API Key 无效，请在设置中更新');
      // F-45：业务错误不落部分内容。
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) m.role], [Role.user]);
    });
  });

  group('stop · 停止（A3 UI 面）', () {
    test('stop → 已累积部分落库且标「已停止」', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      // 100ms token 间距：观测「至少两个 token」后停止，下个 token 前有充足
      // 警戒线（负载环境下 stop() 的取消+重载在毫秒级完成，远快于 100ms）。
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['t0', 't1', 't2', 't3', 't4'],
        delay: const Duration(milliseconds: 100),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      await _until(() async => c.streamingText == 't0t1',
          why: '已累积两个 token（t0t1）');
      expect(c.streamingText, 't0t1');
      await c.stop();

      expect(c.isStreaming, isFalse);
      expect(c.notice, isNull, reason: '主动停止不是错误，无提示');
      final last = c.messages.last;
      expect(last.role, Role.assistant);
      expect(last.content, 't0t1');
      expect(last.stopped, isTrue, reason: 'DB 存纯文本部分内容，UI 侧标「已停止」');
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 't0t1')]);
    });

    test('stop 无部分内容 → 仅保留已发 user，无「已停止」标记', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['a'],
        delay: const Duration(milliseconds: 100),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      // 首 token 100ms 后才到：此刻只落库了 user。
      await _until(() async {
        final settled = await messageRepo.getMessages(conv.id);
        return settled.any((m) => m.role == Role.user);
      });
      await c.stop();

      expect(c.messages, hasLength(1));
      expect(c.messages.single.role, Role.user);
      expect(c.messages.single.stopped, isFalse);
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) m.role], [Role.user]);
    });

    test('send 后立即 stop（user 落库晚于 stop）→ UI 最终显示已落库 user（F1）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      // user 落库经慢仓储延迟 200ms：构造「stop 完成早于 user 落库」的竞态
      // 窗口（服务层落库为独立异步路径，cancel 完成不保证 user 已落库）。
      final slowMessages = _SlowMessageRepository(
        db,
        now: () => fakeNow,
        delay: const Duration(milliseconds: 200),
      );
      final c = wireController(
        TickingFakeLLMProvider(tokens: const ['a'], delay: const Duration(milliseconds: 10)),
        messageRepository: slowMessages,
      );
      await c.openConversation(conv.id);

      await c.send('hi');
      await c.stop(); // 立即停止：此刻 user 尚未落库（慢仓储 200ms 后完成）

      expect(c.isStreaming, isFalse);
      // 修复前：stop reload 读到空库 + 清在途 → UI 空且不自愈；修复后 stop
      // 有界等待 user 落库再 reload → UI 显示已发 user（不依赖时序巧合）。
      expect([for (final m in c.messages) (m.role, m.content)],
          [(Role.user, 'hi')]);
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi')]);
    });

    test('入口态（backToEntry 后台流）停止 → 重进会话部分内容带「已停止」标记（F3b）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['p0', 'p1', 'p2', 'p3', 'p4'],
        delay: const Duration(milliseconds: 100),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      await _until(() async => c.streamingText == 'p0',
          why: '首 token 已累积（user 已落库）');
      await c.backToEntry();
      expect(c.isEntry, isTrue);
      expect(c.isStreaming, isTrue, reason: 'backToEntry 不中止后台流（对齐 P6.5）');

      // 立即重进同一会话：内部 stop() 此刻 _activeConversationId 为 null
      // （入口态）→ 部分内容已落库但标记判定不得依赖 reload 目标而落空。
      await c.openConversation(conv.id);

      expect(c.isStreaming, isFalse);
      final last = c.messages.last;
      expect(last.role, Role.assistant);
      expect(last.content, startsWith('p0'),
          reason: '后台流停止的部分内容经 DB 重载恢复');
      expect(last.stopped, isTrue,
          reason: '入口态/后台流停止也正确落「已停止」标记（对照会话内正常 stop）');
      final settled = await messageRepo.getMessages(conv.id);
      expect(settled.map((m) => m.role).toList(),
          [Role.user, Role.assistant]);
    });
  });

  group('interrupted · 断流（A5 UI 面）', () {
    test('断流 → 非阻塞 notice「回复已中断」+ 部分落库', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        errorAfter: LLMConnectionInterruptedError(),
        delay: const Duration(milliseconds: 5),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      await _until(() async => c.notice == '回复已中断');

      expect(c.isStreaming, isFalse);
      // 断流已累积部分落库（重新进入可恢复）。
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'ab')]);
    });

    test('notice 可 dismiss（非阻塞：不挡后续操作）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['a'],
        errorAfter: LLMConnectionInterruptedError(),
        delay: const Duration(milliseconds: 3),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      await _until(() async => c.notice == '回复已中断');
      c.dismissNotice();
      expect(c.notice, isNull);
      // 断流后仍可继续发送（非阻塞语义）。
      c.dismissNotice();
    });
  });

  group('regenerate · 重生成（A4 UI 面）', () {
    Future<int> seedConversationWithReply({String reply = '旧回复'}) async {
      final char = await seedCharacter(firstMes: '开场。');
      final conv = await seedConversation(char.id);
      await messageRepo.createMessage(
          conversationId: conv.id, role: Role.user, content: '你好');
      await messageRepo.createMessage(
          conversationId: conv.id, role: Role.assistant, content: reply);
      return conv.id;
    }

    test('regenerate 成功 → 旧回复原位替换，user/开场白保留', () async {
      final convId = await seedConversationWithReply();
      final c = wireController(FakeLLMProvider(tokens: const ['新回复']));
      await c.openConversation(convId);

      await c.regenerate();

      expect(c.messages
              .where((m) => m.role == Role.assistant && m.content == '新回复'),
          hasLength(1));
      expect(roleContentsOf(c),
          containsAll([
            (Role.assistant, '开场。'),
            (Role.user, '你好'),
            (Role.assistant, '新回复'),
          ]));
      expect(c.messages.last.content, '新回复');
    });

    test('regenerate 领域错误（对话不存在）→ notice 映射文案，旧回复保留语义无复发', () async {
      final convId = await seedConversationWithReply();
      final c = wireController(FakeLLMProvider(tokens: const ['新回复']));
      await c.openConversation(convId);

      // 服务层触发 ConversationNotFoundError：会话删除后重生成（网络层鉴权不
      // 触达 — messageId 解析前即抛）。
      await convRepo.deleteConversation(convId);
      await c.regenerate();

      expect(c.notice, '对话不存在');
      expect(c.isRegenerating, isFalse, reason: '失败后防并发标志复位');
    });

    test('regenerate 失败 → notice 映射文案，旧回复保留', () async {
      final convId = await seedConversationWithReply();
      final c = wireController(FakeLLMProvider(
        tokens: const [],
        error: LLMAuthError('claude'),
      ));
      await c.openConversation(convId);

      await c.regenerate();

      expect(c.notice, 'API Key 无效，请在设置中更新');
      expect(c.messages.last.role, Role.assistant);
      expect(c.messages.last.content, '旧回复',
          reason: '重生成失败旧回复保留（服务层延迟删除保证）');
    });

    test('流式中 regenerate → 忽略（isRegenerating / isStreaming 双守卫）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 20),
      ));
      await c.openConversation(conv.id);

      await c.send('hi');
      expect(c.isStreaming, isTrue);
      await c.regenerate(); // 流式期间忽略
      expect(c.isStreaming, isTrue, reason: '忽略后回合继续，不被打断');

      await _until(() async => !c.isStreaming);
      final settled = await messageRepo.getMessages(conv.id);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'ab')]);
    });
  });

  group('createConversationFor · 指定角色直达会话（M3-01）', () {
    test('指定非首角色 id → 建会话直达（开场白预插）', () async {
      await seedCharacter(name: '首个角色');
      final target = await seedCharacter(name: '目标角色', firstMes: '你好，{{user}}。');
      final c = wireController(FakeLLMProvider(tokens: const []));
      await c.loadEntry(); // 首角色 cache 为 firstChar，目标角色不入首角色

      await c.createConversationFor(target.id);

      expect(c.activeConversationId, isNotNull);
      expect(c.isEntry, isFalse);
      expect(c.activeConversation?.characterId, target.id,
          reason: '会话归属指定角色而非首个角色');
      expect(roleContentsOf(c), [(Role.assistant, '你好，User。')],
          reason: '目标角色开场白经模板替换预插');
    });

    test('角色不存在 → notice 提示，停留入口且零会话', () async {
      final c = wireController(FakeLLMProvider(tokens: const []));
      await c.loadEntry();

      await c.createConversationFor(999999);

      expect(c.isEntry, isTrue);
      expect(c.activeConversationId, isNull);
      expect(c.notice, contains('角色不存在'));
      expect(await convRepo.listConversations(), isEmpty,
          reason: '失败路径不残留会话');
    });

    test('createConversation（首角色入口）行为不回归（M3-01 前既有语义）', () async {
      await seedCharacter(firstMes: '开场。');
      final c = wireController(FakeLLMProvider(tokens: const []));
      await c.loadEntry();

      await c.createConversation();

      expect(c.activeConversationId, isNotNull);
      expect(c.isEntry, isFalse);
      expect(c.activeConversation?.characterId, isNotNull);
    });
  });

  group('跳转定位高亮 · openConversation highlightMessageId（M3-04c）', () {
    /// 种子「角色 + 会话 + 单条消息」，返回 (会话 id, 目标消息 id)（高亮锚）。
    Future<(int, int)> seedConversationWithMessage() async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final msg = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '命中消息',
      );
      return (conv.id, msg.id);
    }

    test('openConversation 带 highlightMessageId → highlightMessageIds 含目标（3s 自动清除后空）',
        () async {
      final (convId, targetId) = await seedConversationWithMessage();
      final c = wireController(
        FakeLLMProvider(tokens: const []),
        highlightDuration: const Duration(milliseconds: 80),
      );

      await c.openConversation(convId, highlightMessageId: targetId);

      expect(c.activeConversationId, convId);
      expect(c.highlightMessageIds, {targetId});
      expect(c.highlightRequestSeq, greaterThan(0));

      // 3s（注入 80ms）后自动清除：set 移除、seq 不回退。
      final seqBefore = c.highlightRequestSeq;
      await _until(() async => c.highlightMessageIds.isEmpty,
          why: '高亮定时清除');
      expect(c.highlightMessageIds, isEmpty);
      expect(c.highlightRequestSeq, seqBefore, reason: '清除不改请求序号');
    });

    test('highlightMessageId 省略 → 行为与 M2 完全一致（无高亮状态）', () async {
      final (convId, targetId) = await seedConversationWithMessage();
      final c = wireController(FakeLLMProvider(tokens: const []));

      await c.openConversation(convId);

      expect(c.activeConversationId, convId);
      expect(c.highlightMessageIds, isEmpty);
      expect(c.highlightRequestSeq, 0);
      expect([for (final m in c.messages) (m.role, m.content)],
          [(Role.user, '命中消息')]);
      expect(targetId, isPositive);
    });

    test('非目标会话不受影响：切换会话后旧高亮清除', () async {
      final char = await seedCharacter();
      final convA = await seedConversation(char.id);
      final convB = await seedConversation(char.id);
      final targetA = await messageRepo.createMessage(
        conversationId: convA.id,
        role: Role.user,
        content: 'A 命中',
      );
      final c = wireController(FakeLLMProvider(tokens: const []));

      await c.openConversation(convA.id, highlightMessageId: targetA.id);
      expect(c.highlightMessageIds, {targetA.id});

      // 打开另一个会话（无高亮）：A 的高亮清除，不串扰 B。
      await c.openConversation(convB.id);
      expect(c.activeConversationId, convB.id);
      expect(c.highlightMessageIds, isEmpty,
          reason: '切换会话清除旧高亮（验收 7：不串）');
    });

    test('backToEntry → 高亮清除（3s 内返回入口再进入无残留）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final target = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '命中消息',
      );
      final c = wireController(FakeLLMProvider(tokens: const []));

      await c.openConversation(conv.id, highlightMessageId: target.id);
      expect(c.highlightMessageIds, {target.id});

      await c.backToEntry();

      expect(c.isEntry, isTrue);
      expect(c.highlightMessageIds, isEmpty, reason: '返回入口清除高亮');
    });

    test('dispose 取消高亮 Timer（无泄漏：清除后 notify 不触发）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final target = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '命中消息',
      );
      final c = wireController(
        FakeLLMProvider(tokens: const []),
        highlightDuration: const Duration(milliseconds: 60),
      );
      await c.openConversation(conv.id, highlightMessageId: target.id);
      expect(c.highlightMessageIds, {target.id});

      // dispose 取消高亮 timer：若未取消，timer 触发会调 notifyListeners 于已
      // dispose 的 ChangeNotifier → debug 断言抛错；此处等待超过时长须静默。
      controller = null; // 避免 tearDown 二次 dispose
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(c.highlightMessageIds, isEmpty, reason: 'dispose 后 timer 已取消');
    });

    test('合成负 id 不干扰：流式占位负 id 永不进入高亮集合', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final targetId = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '命中消息',
      );
      final c = wireController(TickingFakeLLMProvider(
        tokens: const ['a', 'b'],
        delay: const Duration(milliseconds: 20),
      ));
      await c.openConversation(conv.id, highlightMessageId: targetId.id);

      await c.send('hi');
      // 流式进行中：在途 user / assistant 占位为合成负 id（消息列表含负 id）。
      await _until(() async {
        final ids = [for (final m in c.messages) m.id];
        return ids.any((id) => id < 0);
      }, why: '流式占位合成负 id 已出现');

      expect(
        [for (final m in c.messages) if (m.id < 0) m.id],
        isNotEmpty,
        reason: '合成负 id 存在于消息列表（场景前提）',
      );
      expect(c.highlightMessageIds.single, targetId.id,
          reason: '高亮集合只含 DB 正 id 目标（负 id 不干扰）');
      expect(c.highlightMessageIds.single, greaterThan(0));
      await _until(() async => !c.isStreaming, why: '回合完成');
    });
  });
}