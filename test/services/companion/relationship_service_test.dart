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

    test('floorForStage 默认阈值数值标定（intimate 60 / soulmate 80，常量推导）', () {
      const t = RelationshipThresholds();
      expect(t.floorForStage(RelationshipStage.stranger), 0);
      expect(t.floorForStage(RelationshipStage.acquainted), t.strangerMax + 1);
      expect(t.floorForStage(RelationshipStage.familiar), t.acquaintedMax + 1);
      expect(t.floorForStage(RelationshipStage.intimate), t.familiarMax + 1);
      expect(t.floorForStage(RelationshipStage.soulmate), t.intimateMax + 1);
      // 验收锚（F-82）：默认阈值下 intimate 60、soulmate 80。
      expect(t.floorForStage(RelationshipStage.intimate), 60);
      expect(t.floorForStage(RelationshipStage.soulmate), 80);
    });

    test('floorForStage 与 stageForAffinity 反向自洽（默认 + 自定义阈值推导）', () {
      // 自定义 max 阈值：验证档位下限从实例常量推导，不锁默认快照。
      const customMax = RelationshipThresholds(
        strangerMax: 9,
        acquaintedMax: 19,
        familiarMax: 29,
        intimateMax: 39,
      );
      for (final t in [const RelationshipThresholds(), customMax]) {
        for (final stage in RelationshipStage.values) {
          final floor = t.floorForStage(stage);
          // 落库 affinity 达下限 → 必映射回本档。
          expect(t.stageForAffinity(floor), stage);
          // 下限 − 1 → 必为前一档（intimate 时 familiar、soulmate 时 intimate）。
          if (stage.index > 0) {
            expect(
              t.stageForAffinity(floor - 1),
              RelationshipStage.values[stage.index - 1],
            );
          }
        }
      }
    });

    test('F-96 构造校验：intimateMax 越界 100 → 构造失败（assert，debug）', () {
      // 修复前构造不校验 → 正常返回 → 本测试红；修复后 assert 抛错 → 绿。
      expect(
        () => RelationshipThresholds(intimateMax: 100),
        throwsAssertionError,
      );
    });

    test('F-96 构造校验：max 非严格递增 → 构造失败（递减与平档）', () {
      // 递减倒挂：familiarMax 90 > intimateMax 89。
      expect(
        () => RelationshipThresholds(familiarMax: 90, intimateMax: 89),
        throwsAssertionError,
      );
      // 平档：familiarMax == intimateMax，非严格递增。
      expect(
        () => RelationshipThresholds(familiarMax: 89, intimateMax: 89),
        throwsAssertionError,
      );
    });

    test('F-96 构造校验：合法边界通过（相邻 gap 恰 1 + intimateMax 恰 99）', () {
      // 全链 gap 恰 1：stranger 10 < acquainted 11 < familiar 12 < intimate 13。
      const tightMax = RelationshipThresholds(
        strangerMax: 10,
        acquaintedMax: 11,
        familiarMax: 12,
        intimateMax: 13,
      );
      expect(tightMax.floorForStage(RelationshipStage.intimate), 13);
      expect(tightMax.floorForStage(RelationshipStage.soulmate), 14);

      // intimateMax 恰 99：soulmate 下限 100 恰达 affinityMax 上界。
      const boundaryMax = RelationshipThresholds(
        strangerMax: 19,
        acquaintedMax: 39,
        familiarMax: 59,
        intimateMax: 99,
      );
      expect(boundaryMax.floorForStage(RelationshipStage.soulmate), 100);
      expect(
        boundaryMax.stageForAffinity(
          boundaryMax.floorForStage(RelationshipStage.soulmate),
        ),
        RelationshipStage.soulmate,
      );
    });

    test('F-96 全档合法空间：floor 全档 ≤ affinityMax 且相邻 gap ≥ 1（默认 + 自定义）', () {
      const customMax = RelationshipThresholds(
        strangerMax: 9,
        acquaintedMax: 19,
        familiarMax: 29,
        intimateMax: 39,
      );
      for (final t in [const RelationshipThresholds(), customMax]) {
        final floors = [
          for (final stage in RelationshipStage.values) t.floorForStage(stage),
        ];
        for (var i = 0; i < floors.length; i++) {
          expect(
            floors[i],
            lessThanOrEqualTo(RelationshipThresholds.affinityMax),
          );
          if (i > 0) {
            expect(floors[i] - floors[i - 1], greaterThanOrEqualTo(1));
          }
        }
        // soulmate 下限显式锚：intimateMax + 1 ≤ affinityMax。
        expect(
          t.floorForStage(RelationshipStage.soulmate),
          lessThanOrEqualTo(RelationshipThresholds.affinityMax),
        );
      }
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

    test('F-82 复现：确认前活跃窗口滑出 → 落库 affinity 达 intimate 档下限（58→60）', () async {
      final ids = await seedCharacterWithConversation();
      // 默认阈值（turn=1 / activeDay=2）构造：现有 _testThresholds（turn=3）
      // 下确认重算 58+3=61 仍达下限，无法复现「跨档后数值不足」中间态。
      final defaultService = RelationshipService(
        companionRepository: companion,
        conversationRepository: conversations,
        messageRepository: messages,
        now: () => fixedNow,
      );
      await addMessage(
        conversationId: ids.conversationId,
        createdAt: fixedNow.subtract(const Duration(days: 2)),
      );
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.familiar,
        affinity: 58,
      );

      // 评估时活跃：58 + 1 + 2 = 61 → intimate proposal（不写库）。
      final proposal = await defaultService.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      expect(proposal?.targetStage, RelationshipStage.intimate);
      expect(proposal?.affinity, 61);

      // 确认前活跃窗口滑出（>7d）：仅 turn 增量 58 + 1 = 59，低于 intimate 下限 60。
      fixedNow = fixedNow.add(const Duration(days: 8));
      final ok = await defaultService.confirmStageUpgrade(
        characterId: ids.characterId,
        targetStage: RelationshipStage.intimate,
      );
      expect(ok, isTrue);

      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.intimate);
      // 修复前：落库 59（stageForAffinity(59)=familiar）→ 红；
      // 修复后：clamp 至下限 60，落库值与 stage 档自洽 → 绿。
      expect(state?.affinity, greaterThanOrEqualTo(60));
      expect(
        const RelationshipThresholds().stageForAffinity(state!.affinity),
        RelationshipStage.intimate,
      );
    });

    test('F-82 复现：确认前活跃窗口滑出 → 落库 affinity 达 soulmate 档下限（78→80）', () async {
      final ids = await seedCharacterWithConversation();
      final defaultService = RelationshipService(
        companionRepository: companion,
        conversationRepository: conversations,
        messageRepository: messages,
        now: () => fixedNow,
      );
      await addMessage(
        conversationId: ids.conversationId,
        createdAt: fixedNow.subtract(const Duration(days: 2)),
      );
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.intimate,
        affinity: 78,
      );

      // 评估时活跃：78 + 1 + 2 = 81 → soulmate proposal（不写库）。
      final proposal = await defaultService.evaluateAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      expect(proposal?.targetStage, RelationshipStage.soulmate);
      expect(proposal?.affinity, 81);

      // 确认前活跃窗口滑出：仅 turn 增量 78 + 1 = 79，低于 soulmate 下限 80。
      fixedNow = fixedNow.add(const Duration(days: 8));
      final ok = await defaultService.confirmStageUpgrade(
        characterId: ids.characterId,
        targetStage: RelationshipStage.soulmate,
      );
      expect(ok, isTrue);

      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.soulmate);
      expect(state?.affinity, greaterThanOrEqualTo(80));
      expect(
        const RelationshipThresholds().stageForAffinity(state!.affinity),
        RelationshipStage.soulmate,
      );
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

  group('F1 targetStage 域校验（W3 返修：单向自增，拒降档/越级）', () {
    test('合法后继 familiar→intimate 允许并写库', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.familiar,
        affinity: 58,
      );

      final ok = await service.confirmStageUpgrade(
        characterId: ids.characterId,
        targetStage: RelationshipStage.intimate,
      );

      expect(ok, isTrue);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.intimate);
    });

    test('降档 soulmate→familiar 拒绝且 DB 不变', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.soulmate,
        affinity: 80,
      );

      final ok = await service.confirmStageUpgrade(
        characterId: ids.characterId,
        targetStage: RelationshipStage.familiar,
      );

      expect(ok, isFalse);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.soulmate);
      expect(state?.affinity, 80);
    });

    test('越级 stranger→soulmate 拒绝且 DB 不变', () async {
      final ids = await seedCharacterWithConversation();
      await companion.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.stranger,
        affinity: 10,
      );

      final ok = await service.confirmStageUpgrade(
        characterId: ids.characterId,
        targetStage: RelationshipStage.soulmate,
      );

      expect(ok, isFalse);
      final state = await companion.getRelationship(ids.characterId);
      expect(state?.stage, RelationshipStage.stranger);
      expect(state?.affinity, 10);
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
    test('isRecentlyActive：最近消息 ≥ now−7d 为 true', () async {
      final ids = await seedCharacterWithConversation();
      await addMessage(
        conversationId: ids.conversationId,
        createdAt: fixedNow.subtract(const Duration(days: 7)),
      );
      expect(await service.isRecentlyActive(ids.characterId), isTrue);
    });

    test('isRecentlyActive：跨对话取全局 max（最新消息在另一对话）', () async {
      final ids = await seedCharacterWithConversation();
      await addMessage(
        conversationId: ids.conversationId,
        createdAt: fixedNow.subtract(const Duration(days: 8)),
      );
      final conv2 = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: ids.characterId,
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );
      await addMessage(
        conversationId: conv2.id,
        createdAt: fixedNow.subtract(const Duration(hours: 2)),
      );

      // 判定⑨单源（F-81）：isRecentlyActive 观测值与 repository 口径一致。
      expect(
        await messages.latestMessageAt(ids.characterId),
        fixedNow.subtract(const Duration(hours: 2)),
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