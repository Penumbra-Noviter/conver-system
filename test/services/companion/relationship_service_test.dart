/// PS2-03 RelationshipService 测试 — 关系状态机核心业务层全语义。
///
/// 覆盖：五值枚举确认、affinity clamp 纯函数、evaluateAfterTurn（首次
/// upsert / proposal 不落库 / 普通推进落库 / 闸门目标不落库）、确认闸门、
/// 注入片段、活跃天数口径、启发式常量可注入（测试用自定义阈值隔离默认值）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/companion/relationship_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

/// 测试专用确定性阈值（与默认值不同，验证「构造可注入」且不锁默认快照）。
const _testThresholds = RelationshipThresholds(
  turnAffinityGain: 3,
  activeDayAffinityGain: 4,
  proactiveOpenAffinityGain: 6,
);

void main() {
  late AppDatabase db;
  late CompanionRepository companion;
  late ConversationRepository conversations;
  late MessageRepository messages;
  late RelationshipService service;
  late DateTime fixedNow;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    fixedNow = DateTime(2026, 9, 15, 12, 0, 0);
    companion = CompanionRepository(db, now: () => fixedNow);
    conversations = ConversationRepository(
      db,
      SettingsRepository(database: db, secretStore: InMemorySecretStore()),
    );
    messages = MessageRepository(db);
    service = RelationshipService(
      companionRepository: companion,
      conversationRepository: conversations,
      messageRepository: messages,
      now: () => fixedNow,
      thresholds: _testThresholds,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<({int characterId, int conversationId})> seedCharacterWithConversation() async {
    final character = await db.into(db.characters).insertReturning(
          CharactersCompanion.insert(
            name: '状态机宿主',
            createdAt: fixedNow,
            updatedAt: fixedNow,
          ),
        );
    final conversation = await db.into(db.conversations).insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: fixedNow,
            updatedAt: fixedNow,
          ),
        );
    return (characterId: character.id, conversationId: conversation.id);
  }

  Future<void> addMessage({
    required int conversationId,
    required DateTime createdAt,
  }) async {
    await db.into(db.messages).insert(
          MessagesCompanion.insert(
            conversationId: conversationId,
            role: Role.assistant,
            content: '心跳',
            createdAt: createdAt,
          ),
        );
  }

  group('枚举与纯函数', () {
    test('RelationshipStage 五值齐全（锚文本）', () {
      expect(
        RelationshipStage.values.map((s) => s.value),
        ['stranger', 'acquainted', 'familiar', 'intimate', 'soulmate'],
      );
    });

    test('clampAffinity：上下界与边界值收敛', () {
      expect(RelationshipService.clampAffinity(-5), 0);
      expect(RelationshipService.clampAffinity(150), 100);
      expect(RelationshipService.clampAffinity(0), 0);
      expect(RelationshipService.clampAffinity(100), 100);
      expect(RelationshipService.clampAffinity(50), 50);
    });

    test('nextAffinity：负增量与超上限均收敛（恒 clamp）', () {
      expect(RelationshipService.nextAffinity(10, -20), 0);
      expect(RelationshipService.nextAffinity(95, 50), 100);
      expect(RelationshipService.nextAffinity(30, 5), 35);
    });

    test('stageForAffinity 五档边界（含端点语义）', () {
      const t = RelationshipThresholds();
      expect(t.stageForAffinity(0), RelationshipStage.stranger);
      expect(t.stageForAffinity(19), RelationshipStage.stranger);
      expect(t.stageForAffinity(20), RelationshipStage.acquainted);
      expect(t.stageForAffinity(39), RelationshipStage.acquainted);
      expect(t.stageForAffinity(40), RelationshipStage.familiar);
      expect(t.stageForAffinity(59), RelationshipStage.familiar);
      expect(t.stageForAffinity(60), RelationshipStage.intimate);
      expect(t.stageForAffinity(79), RelationshipStage.intimate);
      expect(t.stageForAffinity(80), RelationshipStage.soulmate);
      expect(t.stageForAffinity(100), RelationshipStage.soulmate);
    });
  });

  group('注入片段', () {
    test('buildRelationshipInjection 含 stage 英文值与 affinity 数值', () {
      final text = RelationshipService.buildRelationshipInjection(
        stage: RelationshipStage.familiar,
        affinity: 55,
      );
      expect(text, contains('familiar'));
      expect(text, contains('55'));
      expect(text, contains('当前关系阶段'));
    });
  });

  group('evaluateAfterTurn', () {
    test('无状态行：首次 upsert 默认 stranger/0 且不返回 proposal', () async {
      final ids = await seedCharacterWithConversation();
      final proposal = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(proposal, isNull);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.stranger);
      expect(state?.affinity, 0);
    });

    test('普通推进（不活跃）：每回合 +turnAffinityGain 落库', () async {
      final ids = await seedCharacterWithConversation();
      await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      // 第一轮仅创建默认行（无推进）。
      var state = await companion.getRelationship(ids.characterId);
      expect(state?.affinity, 0);

      await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.stranger);
      expect(state?.affinity, _testThresholds.turnAffinityGain);
    });

    test('普通推进（近 7 天活跃）：回合 + 活跃双增量落库', () async {
      final ids = await seedCharacterWithConversation();
      await addMessage(
        conversationId: ids.conversationId,
        createdAt: fixedNow.subtract(const Duration(days: 2)),
      );
      // 首个评估回合创建默认行；第二回合带活跃增量推进。
      await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      final state = await companion.getRelationship(ids.characterId);
      expect(
        state?.affinity,
        _testThresholds.turnAffinityGain + _testThresholds.activeDayAffinityGain,
      );
    });

    test('普通跨档（stranger→acquainted）直接落库 stage+affinity', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.stranger,
        affinity: 18,
      );
      // service 阈值 turn=3：18+3=21 → acquainted。
      await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.acquainted);
      expect(state?.affinity, 21);
    });

    test('跨 intimate 门槛：返回 proposal 且 DB stage/affinity 均不变', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.familiar,
        affinity: 58,
      );
      // 58+3=61 → intimate 档。
      final proposal = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(proposal, isNotNull);
      expect(proposal!.currentStage, RelationshipStage.familiar);
      expect(proposal.targetStage, RelationshipStage.intimate);
      expect(proposal.affinity, 61);

      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.familiar);
      expect(state?.affinity, 58);
    });

    test('跨 soulmate 门槛：返回 proposal 不写库', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.intimate,
        affinity: 78,
      );
      // 78+3=81 → soulmate 档。
      final proposal = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(proposal?.targetStage, RelationshipStage.soulmate);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.intimate);
      expect(state?.affinity, 78);
    });

    test('已 intimate 档内推进：同档直接落库（无 proposal）', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.intimate,
        affinity: 61,
      );
      // 61+3=64 仍在 intimate 档。
      final proposal = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(proposal, isNull);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.intimate);
      expect(state?.affinity, 64);
    });

    test('proposal 场景幂等：同回合重复调用返回相同 proposal 且 DB 不变', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.familiar,
        affinity: 58,
      );

      final first = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      final second = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(first?.targetStage, second?.targetStage);
      expect(first?.affinity, second?.affinity);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.familiar);
      expect(state?.affinity, 58);
    });
  });

  group('确认闸门（SR-10）', () {
    test('confirm 后 stage/affinity 更新且 updatedAt 前移（SR-15 观察）', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.familiar,
        affinity: 58,
      );
      final proposal = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      expect(proposal?.targetStage, RelationshipStage.intimate);

      fixedNow = fixedNow.add(const Duration(hours: 1));
      await service.confirmStageUpgrade(
        characterId: ids.characterId,
        targetStage: RelationshipStage.intimate,
      );

      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.intimate);
      expect(state?.affinity, 61);
      expect(state?.updatedAt, fixedNow);
    });

    test('reject 丢弃：DB 保持不变', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.intimate,
        affinity: 78,
      );
      final proposal = await service.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      expect(proposal?.targetStage, RelationshipStage.soulmate);

      await service.rejectStageUpgrade(characterId: ids.characterId);

      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.intimate);
      expect(state?.affinity, 78);
    });

    test('confirm 无状态行时 no-op 不抛（防御路径）', () async {
      await service.confirmStageUpgrade(
        characterId: 999,
        targetStage: RelationshipStage.intimate,
      );
    });
  });

  group('点开主动消息（+proactiveOpenAffinityGain）', () {
    test('普通档位：+6 落库', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.stranger,
        affinity: 10,
      );

      final proposal = await service.recordProactiveMessageOpened(ids.characterId);
      expect(proposal, isNull);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.affinity, 16);
    });

    test('跨 intimate 门槛：返回 proposal 不写库', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.familiar,
        affinity: 55,
      );

      final proposal = await service.recordProactiveMessageOpened(ids.characterId);
      expect(proposal?.targetStage, RelationshipStage.intimate);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.familiar);
      expect(state?.affinity, 55);
    });

    test('无状态行：先建默认行再推进', () async {
      final ids = await seedCharacterWithConversation();
      final proposal = await service.recordProactiveMessageOpened(ids.characterId);
      expect(proposal, isNull);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.stranger);
      expect(state?.affinity, _testThresholds.proactiveOpenAffinityGain);
    });
  });

  group('活跃天数口径（判定⑨）', () {
    test('activeDays：跨对话 distinct 本地日期数', () async {
      final ids = await seedCharacterWithConversation();
      final conv2 = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: ids.characterId,
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );

      // 同日期（本地）多条去重；跨日期计数。
      final day1 = DateTime(2026, 9, 10, 8);
      final day1b = DateTime(2026, 9, 10, 22);
      final day2 = DateTime(2026, 9, 11, 9);
      final day3 = DateTime(2026, 9, 12, 10);
      await addMessage(conversationId: ids.conversationId, createdAt: day1);
      await addMessage(conversationId: ids.conversationId, createdAt: day1b);
      await addMessage(conversationId: conv2.id, createdAt: day2);
      await addMessage(conversationId: ids.conversationId, createdAt: day3);

      expect(await service.activeDays(ids.characterId), 3);
    });

    test('activeDays：无消息返回 0', () async {
      final ids = await seedCharacterWithConversation();
      expect(await service.activeDays(ids.characterId), 0);
    });

    test('isRecentlyActive：最近消息 ≥ now−7d 为 true', () async {
      final ids = await seedCharacterWithConversation();
      await addMessage(
        conversationId: ids.conversationId,
        createdAt: fixedNow.subtract(const Duration(days: 7)),
      );
      expect(await service.isRecentlyActive(ids.characterId), isTrue);
    });

    test('isRecentlyActive：超过 7 天为 false；无消息为 false', () async {
      final ids = await seedCharacterWithConversation();
      await addMessage(
        conversationId: ids.conversationId,
        createdAt: fixedNow.subtract(const Duration(days: 8)),
      );
      expect(await service.isRecentlyActive(ids.characterId), isFalse);

      final lonely = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '无对话者',
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );
      expect(await service.isRecentlyActive(lonely.id), isFalse);
    });
  });
}