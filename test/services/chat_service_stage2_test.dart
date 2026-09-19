/// PS2-07 ChatService 三挂点集成契约测试。
///
/// 覆盖：构造可选注入缺省 null 行为零回归、thought 剥离链（开关矩阵 +
/// 内嵌记忆标签不解析 + 空剥离落库空串）、关系/thought 指令注入（有状态行
/// 注入/无行跳过/开关控制）、回合结束三路 fire-and-forget（proactive 落库 +
/// messageId 回填、关系评估 proposal 回调不写库、任一路抛错隔离不阻断
/// ChatDone）。沿用 chat_service_reflection_test 的 db/seed/drain 惯例。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/companion/proactive_message_service.dart';
import 'package:conver_system_mobile/services/companion/relationship_service.dart';
import 'package:conver_system_mobile/services/companion/thought_service.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/memory/memory_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../helpers/fake_llm_provider.dart';
import '../helpers/in_memory_secret_store.dart';

/// 恒返回 shouldSend=true 的 fake planner（计数）。
class _FakeProactivePlanner {
  _FakeProactivePlanner({this.decision});

  ProactivePlanDecision? decision;
  int calls = 0;

  Future<ProactivePlanDecision?> call({
    required int characterId,
    required int conversationId,
    required List<String> dialogueLines,
  }) async {
    calls++;
    return decision;
  }
}

/// 计数 scheduler（排程不禁用，仅记录调用）。
class _RecordingScheduler implements ProactiveNotificationScheduler {
  int calls = 0;

  @override
  Future<bool> schedule(ProactivePlan plan) async {
    calls++;
    return true;
  }
}

/// 单路抛错替身：关系评估抛错（验证 ChatService 侧隔离）。
class _ThrowingRelationshipService extends RelationshipService {
  _ThrowingRelationshipService({
    required super.companionRepository,
    required super.conversationRepository,
    required super.messageRepository,
  });

  int evaluateCalls = 0;

  @override
  Future<StageUpgradeProposal?> evaluateAfterTurn({
    required int characterId,
    required int conversationId,
  }) async {
    evaluateCalls++;
    throw StateError('boom relationship');
  }
}

/// 单路抛错替身：thought 落库抛错（验证隔离；S5 后服务只收已剥离内容）。
class _ThrowingThoughtService extends ThoughtService {
  _ThrowingThoughtService({
    required super.companionRepository,
    required super.settingsRepository,
  });

  int persistCalls = 0;

  @override
  Future<void> persistThought({
    required int characterId,
    required int messageId,
    required String thoughtContent,
  }) async {
    persistCalls++;
    throw StateError('boom thought');
  }
}

/// 单路抛错替身：主动规划抛错（验证隔离；真实服务内部已 catch，此为防御面）。
class _ThrowingProactiveService extends ProactiveMessageService {
  _ThrowingProactiveService({
    required super.companionRepository,
    required super.settingsRepository,
    required super.messageRepository,
    required super.planner,
    required super.scheduler,
  });

  int planCalls = 0;

  @override
  Future<int> planAfterTurn({
    required int characterId,
    required int conversationId,
  }) async {
    planCalls++;
    throw StateError('boom proactive');
  }
}

void main() {
  late AppDatabase db;
  late CharacterRepository characterRepo;
  late ConversationRepository conversationRepo;
  late MessageRepository messageRepo;
  late SettingsRepository settingsRepo;
  late MemoryRepository memoryRepo;
  late MemoryService memoryService;
  late CompanionRepository companionRepo;
  late DateTime fixedNow;

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
    fixedNow = DateTime(2026, 9, 15, 12, 0, 0);
    companionRepo = CompanionRepository(db, now: () => fixedNow);
  });

  tearDown(() async {
    await db.close();
  });

  Future<({int characterId, Conversation conversation})> seedConversation() async {
    final character = await characterRepo.createCharacter(
          CharactersCompanion.insert(
            name: '艾莉亚',
            firstMes: Value(''),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    final conversation =
        await conversationRepo.createConversation(characterId: character.id);
    return (characterId: character.id, conversation: conversation);
  }

  Future<void> drainStream(Stream<ChatEvent> stream) async {
    await for (final _ in stream) {}
  }

  ThoughtService buildThought() =>
      ThoughtService(companionRepository: companionRepo, settingsRepository: settingsRepo);

  RelationshipService buildRelationship() => RelationshipService(
        companionRepository: companionRepo,
        conversationRepository: conversationRepo,
        messageRepository: messageRepo,
        now: () => fixedNow,
      );

  ProactiveMessageService buildProactive(
    ProactivePlanner planner,
    ProactiveNotificationScheduler scheduler,
  ) =>
      ProactiveMessageService(
        companionRepository: companionRepo,
        settingsRepository: settingsRepo,
        messageRepository: messageRepo,
        planner: planner,
        scheduler: scheduler,
        now: () => fixedNow,
      );

  ChatService buildService({
    required LLMProvider provider,
    ThoughtService? thoughtService,
    RelationshipService? relationshipService,
    ProactiveMessageService? proactiveMessageService,
    void Function(StageUpgradeProposal proposal)? onStageUpgradeProposal,
  }) {
    return ChatService(
      database: db,
      conversationRepository: conversationRepo,
      characterRepository: characterRepo,
      messageRepository: messageRepo,
      settingsRepository: settingsRepo,
      providerFactory: FixedLLMProviderFactory(provider),
      memoryService: memoryService,
      thoughtService: thoughtService,
      relationshipService: relationshipService,
      proactiveMessageService: proactiveMessageService,
      companionRepository: companionRepo,
      onStageUpgradeProposal: onStageUpgradeProposal,
    );
  }

  /// 轮询等待条件成立（fire-and-forget 异步），超时 2s 抛错。
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('waitFor 超时');
  }

  group('thought 剥离链（先于记忆，判定②）', () {
    test('开关开：正文无标签残留 + InnerThoughts 落库可查回', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.innerThoughtEnabledKey: 'true',
      });
      final provider = FakeLLMProvider(tokens: const ['你好<thought>她没抬头</thought>啊']);
      final service = buildService(provider: provider, thoughtService: buildThought());

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      final messages = await messageRepo.getMessages(seed.conversation.id);
      final assistant = messages.singleWhere((m) => m.role == Role.assistant);
      expect(assistant.content, '你好啊');
      final thoughts = await companionRepo.listThoughtsByMessage(assistant.id);
      expect(thoughts.single.content, '她没抬头');
    });

    test('开关关：剥离生效但不落库', () async {
      final seed = await seedConversation();
      final provider = FakeLLMProvider(tokens: const ['有<thought>独白</thought>正文']);
      final service = buildService(provider: provider, thoughtService: buildThought());

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      final messages = await messageRepo.getMessages(seed.conversation.id);
      final assistant = messages.singleWhere((m) => m.role == Role.assistant);
      expect(assistant.content, '有正文');
      expect(await companionRepo.listThoughtsByMessage(assistant.id), isEmpty);
    });

    test('thought 内嵌记忆标签不被记忆解析（thought 先进记忆链路）', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.innerThoughtEnabledKey: 'true',
        SettingsRepository.memoryPromptModeKey: 'medium',
      });
      final provider = FakeLLMProvider(
        tokens: const ['正文<thought>记住 <add>喜欢雨</add></thought>'],
      );
      final service = buildService(provider: provider, thoughtService: buildThought());

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      final messages = await messageRepo.getMessages(seed.conversation.id);
      final assistant = messages.singleWhere((m) => m.role == Role.assistant);
      // 正文无 thought 块；thought 内容里的 <add> 不进入记忆表。
      expect(assistant.content, '正文');
      expect(await memoryRepo.listEntries(seed.characterId), isEmpty);
    });

    test('空剥离结果：落库为空串消息（守卫在剥离前）', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.innerThoughtEnabledKey: 'true',
      });
      final provider = FakeLLMProvider(tokens: const ['<thought>   </thought>']);
      final service = buildService(provider: provider, thoughtService: buildThought());

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      final messages = await messageRepo.getMessages(seed.conversation.id);
      final assistant = messages.singleWhere((m) => m.role == Role.assistant);
      expect(assistant.content, '');
      // 空独白不落库。
      expect(
        await companionRepo.listThoughtsByMessage(assistant.id),
        isEmpty,
      );
    });

    test('thought 服务注入但抛错：正文仍剥离（剥离恒生效），thought 不落库，ChatDone 不受阻', () async {
      final seed = await seedConversation();
      final provider = FakeLLMProvider(tokens: const ['有<thought>独白</thought>正文']);
      final throwing = _ThrowingThoughtService(
        companionRepository: companionRepo,
        settingsRepository: settingsRepo,
      );
      final service = buildService(provider: provider, thoughtService: throwing);

      // streamReply 正常完结（无未处理异常）。
      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );
      expect(throwing.persistCalls, 1);
      final messages = await messageRepo.getMessages(seed.conversation.id);
      // 剥离经顶层纯函数恒生效（不依赖服务）；服务抛错只丢 thought 落库。
      expect(
        messages.singleWhere((m) => m.role == Role.assistant).content,
        '有正文',
      );
      expect(
        await companionRepo
            .listThoughtsByMessage(messages.singleWhere((m) => m.role == Role.assistant).id),
        isEmpty,
      );
    });
  });

  group('组装注入（关系 + thought 指令）', () {
    test('有状态行：注入关系 system 块（stage 英文值 + affinity）', () async {
      final seed = await seedConversation();
      await companionRepo.upsertRelationship(
        characterId: seed.characterId,
        stage: RelationshipStage.familiar,
        affinity: 55,
      );
      final provider = FakeLLMProvider(tokens: const ['你好']);
      final service = buildService(
        provider: provider,
        relationshipService: buildRelationship(),
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      final systemText = provider.lastMessages!
          .where((m) => m.role == 'system')
          .map((m) => m.content)
          .join('\n');
      expect(systemText, contains('familiar'));
      expect(systemText, contains('55'));
    });

    test('无状态行：不注入关系块（判定⑧）', () async {
      final seed = await seedConversation();
      final provider = FakeLLMProvider(tokens: const ['你好']);
      final service = buildService(
        provider: provider,
        relationshipService: buildRelationship(),
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      final systemText = provider.lastMessages!
          .where((m) => m.role == 'system')
          .map((m) => m.content)
          .join('\n');
      expect(systemText, isNot(contains('当前关系阶段')));
    });

    test('innerThoughtEnabled 开：注入 thought 指令 system 块；关：不含', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.innerThoughtEnabledKey: 'true',
      });
      var provider = FakeLLMProvider(tokens: const ['你好']);
      var service = buildService(provider: provider, thoughtService: buildThought());

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );
      expect(
        provider.lastMessages!
            .where((m) => m.role == 'system')
            .map((m) => m.content)
            .join('\n'),
        contains('<thought>'),
      );

      // 关 → 不含指令。
      await settingsRepo.setMany({
        SettingsRepository.innerThoughtEnabledKey: '',
      });
      provider = FakeLLMProvider(tokens: const ['你好']);
      service = buildService(provider: provider, thoughtService: buildThought());
      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );
      expect(
        provider.lastMessages!
            .where((m) => m.role == 'system')
            .map((m) => m.content)
            .join('\n'),
        isNot(contains('内心独白必须用')),
      );
    });
  });

  group('回合结束链（三路 fire-and-forget）', () {
    test('proactive 开启 + shouldSend：新 assistant 行 + scheduled 计划 + messageId 回填', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.proactiveMessageEnabledKey: 'true',
      });
      final planner = _FakeProactivePlanner(
        decision: (
          shouldSend: true,
          minutesFromNow: 30,
          content: '今晚月色很好。',
        ),
      );
      final scheduler = _RecordingScheduler();
      final provider = FakeLLMProvider(tokens: const ['你好']);
      final service = buildService(
        provider: provider,
        proactiveMessageService: buildProactive(
          planner.call,
          scheduler,
        ),
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      await waitFor(() => planner.calls > 0);
      expect(await companionRepo.listPlansByStatus(ProactivePlanStatus.scheduled), hasLength(1));
      final plan = (await companionRepo.listPlansByStatus(ProactivePlanStatus.scheduled)).single;
      expect(plan.content, '今晚月色很好。');
      expect(plan.messageId, isNotNull);
      expect(scheduler.calls, 1);

      final persisted = await messageRepo.getMessages(seed.conversation.id);
      final proactiveMessage = persisted
          .where((m) => m.role == Role.assistant)
          .where((m) => m.content == '今晚月色很好。')
          .toList();
      expect(proactiveMessage, hasLength(1));
      expect(proactiveMessage.single.id, plan.messageId);
    });

    test('proactive 开关关：planner 不被调用（服务内部零副作用）', () async {
      final seed = await seedConversation();
      final planner = _FakeProactivePlanner(
        decision: (
          shouldSend: true,
          minutesFromNow: 30,
          content: '今晚月色很好。',
        ),
      );
      final provider = FakeLLMProvider(tokens: const ['你好']);
      final service = buildService(
        provider: provider,
        proactiveMessageService: buildProactive(
          planner.call,
          _RecordingScheduler(),
        ),
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(planner.calls, 0);
    });

    test('关系评估跨 intimate 门槛：回调收到 proposal 且 DB stage 不变', () async {
      final seed = await seedConversation();
      await companionRepo.upsertRelationship(
        characterId: seed.characterId,
        stage: RelationshipStage.familiar,
        affinity: 58,
      );
      final provider = FakeLLMProvider(tokens: const ['你好']);
      StageUpgradeProposal? received;
      final service = buildService(
        provider: provider,
        relationshipService: buildRelationship(),
        onStageUpgradeProposal: (proposal) => received = proposal,
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      // 本回合消息刚落库（真实 now）→ 活跃信号 true → 增量 = 回合1 + 活跃2 = 3。
      await waitFor(() => received != null);
      expect(received!.currentStage, RelationshipStage.familiar);
      expect(received!.targetStage, RelationshipStage.intimate);
      expect(received!.affinity, 61);
      // 评估不写库：DB stage/affinity 保持原值（确认由 UI 层触发）。
      final state = await companionRepo.getRelationship(seed.characterId);
      expect(state?.stage, RelationshipStage.familiar);
      expect(state?.affinity, 58);
    });

    test('单路抛错隔离：proactive 抛错不阻断 ChatDone，其余两路仍执行', () async {
      final seed = await seedConversation();
      await settingsRepo.setMany({
        SettingsRepository.proactiveMessageEnabledKey: 'true',
        SettingsRepository.innerThoughtEnabledKey: 'true',
      });
      await companionRepo.upsertRelationship(
        characterId: seed.characterId,
        stage: RelationshipStage.familiar,
        affinity: 59,
      );
      final throwingProactive = _ThrowingProactiveService(
        companionRepository: companionRepo,
        settingsRepository: settingsRepo,
        messageRepository: messageRepo,
        planner: ({required characterId, required conversationId, required dialogueLines}) async => null,
        scheduler: _RecordingScheduler(),
      );
      final provider = FakeLLMProvider(tokens: const ['你好<thought>独白</thought>啦']);
      StageUpgradeProposal? received;
      final service = buildService(
        provider: provider,
        thoughtService: buildThought(),
        relationshipService: buildRelationship(),
        proactiveMessageService: throwingProactive,
        onStageUpgradeProposal: (proposal) => received = proposal,
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );

      await waitFor(() => received != null);
      expect(throwingProactive.planCalls, 1);
      // thought 路仍执行（落库）。
      final messages = await messageRepo.getMessages(seed.conversation.id);
      final assistant = messages.singleWhere((m) => m.role == Role.assistant);
      expect(assistant.content, '你好啦');
      expect(
        await companionRepo.listThoughtsByMessage(assistant.id),
        hasLength(1),
      );
    });

    test('关系评估抛错：主回复仍 ChatDone（未处理异常不冒泡）', () async {
      final seed = await seedConversation();
      final throwing = _ThrowingRelationshipService(
        companionRepository: companionRepo,
        conversationRepository: conversationRepo,
        messageRepository: messageRepo,
      );
      final provider = FakeLLMProvider(tokens: const ['你好']);
      final service = buildService(
        provider: provider,
        relationshipService: throwing,
      );

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );
      expect(throwing.evaluateCalls, 1);
    });
  });

  group('缺省 null（阶段 1.5 行为零回归）', () {
    test('三服务/仓储/回调缺省：正常回合落库 + ChatDone', () async {
      final seed = await seedConversation();
      final provider = FakeLLMProvider(tokens: const ['你好']);
      final service = buildService(provider: provider);

      await drainStream(
        service.streamReply(conversationId: seed.conversation.id, content: '嗨'),
      );
      final messages = await messageRepo.getMessages(seed.conversation.id);
      expect(
        messages.where((m) => m.role == Role.assistant).single.content,
        '你好',
      );
    });
  });
}