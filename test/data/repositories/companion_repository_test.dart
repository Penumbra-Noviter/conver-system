/// PS2-02 CompanionRepository 测试 — 三新表数据访问层全语义。
///
/// 沿 MemoryRepository 测试惯例：内存库 + `now` 注入（固定时间戳保证
/// getActivePlan 时间边界可测）。FK 依赖经 seed 链（角色→对话→消息）建立。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CompanionRepository repository;
  late DateTime fixedNow;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    fixedNow = DateTime(2026, 9, 15, 12, 0, 0);
    repository = CompanionRepository(db, now: () => fixedNow);
  });

  tearDown(() async {
    await db.close();
  });

  Future<({int characterId, int conversationId, int messageId})> seedChain(
    AppDatabase database,
  ) async {
    final now = DateTime(2026, 9, 1);
    final character = await database
        .into(database.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '链主',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final conversation = await database
        .into(database.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final message = await database
        .into(database.messages)
        .insertReturning(
          MessagesCompanion.insert(
            conversationId: conversation.id,
            role: Role.user,
            content: '种子消息',
            createdAt: now,
          ),
        );
    return (
      characterId: character.id,
      conversationId: conversation.id,
      messageId: message.id,
    );
  }

  group('关系状态 RelationshipStates', () {
    test('getRelationship 无行返回 null', () async {
      expect(await repository.getRelationship(1), isNull);
    });

    test('upsertRelationship 创建并落库（stage/affinity/updatedAt）', () async {
      final ids = await seedChain(db);
      final state = await repository.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.acquainted,
        affinity: 25,
      );

      expect(state.characterId, ids.characterId);
      expect(state.stage, RelationshipStage.acquainted);
      expect(state.affinity, 25);
      expect(state.updatedAt, fixedNow);

      final reloaded = await repository.getRelationship(ids.characterId);
      expect(reloaded?.stage, RelationshipStage.acquainted);
      expect(reloaded?.affinity, 25);
    });

    test('upsertRelationship 幂等：同角色二次调用更新而非插入', () async {
      final ids = await seedChain(db);
      await repository.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.stranger,
        affinity: 0,
      );

      fixedNow = fixedNow.add(const Duration(hours: 1));
      final updated = await repository.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.familiar,
        affinity: 60,
      );

      expect(updated.stage, RelationshipStage.familiar);
      expect(updated.affinity, 60);
      expect(updated.updatedAt, fixedNow);
      final rows = await db.select(db.relationshipStates).get();
      expect(rows, hasLength(1));
    });

    test('affinity clamp：下界 0 / 上界 100 / 边界保留', () async {
      final ids = await seedChain(db);
      await repository.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.stranger,
        affinity: -5,
      );
      var state = await repository.getRelationship(ids.characterId);
      expect(state?.affinity, 0);

      fixedNow = fixedNow.add(const Duration(minutes: 1));
      await repository.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.stranger,
        affinity: 150,
      );
      state = await repository.getRelationship(ids.characterId);
      expect(state?.affinity, 100);

      fixedNow = fixedNow.add(const Duration(minutes: 1));
      await repository.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.intimate,
        affinity: 0,
      );
      state = await repository.getRelationship(ids.characterId);
      expect(state?.affinity, 0);

      fixedNow = fixedNow.add(const Duration(minutes: 1));
      await repository.upsertRelationship(
        characterId: ids.characterId,
        stage: RelationshipStage.soulmate,
        affinity: 100,
      );
      state = await repository.getRelationship(ids.characterId);
      expect(state?.affinity, 100);
    });

    test('listRelationships 返回全部并按 characterId 排序', () async {
      final idsA = await seedChain(db);
      final now = DateTime(2026, 9, 1);
      final other = await db
          .into(db.characters)
          .insertReturning(
            CharactersCompanion.insert(
              name: '乙',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await repository.upsertRelationship(
        characterId: other.id,
        stage: RelationshipStage.soulmate,
        affinity: 99,
      );
      await repository.upsertRelationship(
        characterId: idsA.characterId,
        stage: RelationshipStage.stranger,
        affinity: 1,
      );

      final rows = await repository.listRelationships();
      expect(rows, hasLength(2));
      expect(rows.first.characterId, lessThan(rows.last.characterId));
    });
  });

  group('主动消息计划 ProactivePlans', () {
    test('createPlan 落库默认 scheduled，字段往返（含 messageId 可空）', () async {
      final ids = await seedChain(db);
      final plan = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '今晚月色很好。',
        scheduledAt: fixedNow.add(const Duration(hours: 2)),
        messageId: ids.messageId,
      );

      expect(plan.status, ProactivePlanStatus.scheduled);
      expect(plan.content, '今晚月色很好。');
      expect(plan.sentAt, isNull);
      expect(plan.messageId, ids.messageId);

      final nullMsgPlan = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '未挂消息的计划',
        scheduledAt: fixedNow.add(const Duration(hours: 3)),
        messageId: null,
      );
      expect(nullMsgPlan.messageId, isNull);
      expect(nullMsgPlan.status, ProactivePlanStatus.scheduled);
    });

    test('getActivePlan：scheduled 且 scheduledAt > now 才返回', () async {
      final ids = await seedChain(db);
      final active = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '在途',
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        messageId: null,
      );
      await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '已过点',
        scheduledAt: fixedNow.subtract(const Duration(minutes: 1)),
        messageId: null,
      );
      await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '恰在 now',
        scheduledAt: fixedNow,
        messageId: null,
      );

      final result = await repository.getActivePlan(ids.characterId);
      expect(result?.id, active.id);
      expect(result?.content, '在途');
    });

    test('getActivePlan：双在途（数据现实）limit(1) 不抛，返回其一（F-125）', () async {
      final ids = await seedChain(db);
      await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '在途 A',
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        messageId: null,
      );
      await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '在途 B',
        scheduledAt: fixedNow.add(const Duration(hours: 2)),
        messageId: null,
      );

      final result = await repository.getActivePlan(ids.characterId);
      // F-125 契约锁：双在途不再抛 StateError（W2 曾实测抛），任取其一。
      expect(result, isA<ProactivePlan>(), reason: '双在途 getActivePlan 不抛（F-125）');
      expect(result!.content, isIn(['在途 A', '在途 B']));
    });

    test('getActivePlan：非 scheduled 状态一律不返回', () async {
      final ids = await seedChain(db);
      for (final status in ProactivePlanStatus.values) {
        if (status == ProactivePlanStatus.scheduled) {
          continue;
        }
        await db
            .into(db.proactivePlans)
            .insert(
              ProactivePlansCompanion.insert(
                characterId: ids.characterId,
                conversationId: ids.conversationId,
                content: 'plan-${status.value}',
                scheduledAt: fixedNow.add(const Duration(hours: 1)),
                status: status,
                messageId: const Value(null),
                sentAt: const Value(null),
              ),
            );
      }
      expect(await repository.getActivePlan(ids.characterId), isNull);
    });

    test('updatePlanStatus：sent 写入 sentAt（显式值与缺省 _now）', () async {
      final ids = await seedChain(db);
      final plan = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '发送计划',
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        messageId: null,
      );

      final explicitSentAt = fixedNow.add(const Duration(minutes: 5));
      await repository.updatePlanStatus(
        plan.id,
        ProactivePlanStatus.sent,
        sentAt: explicitSentAt,
      );
      final reloaded = await db.select(db.proactivePlans).getSingle();
      expect(reloaded.status, ProactivePlanStatus.sent);
      expect(reloaded.sentAt, explicitSentAt);

      fixedNow = fixedNow.add(const Duration(minutes: 6));
      final plan2 = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '缺省 sentAt',
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        messageId: null,
      );
      await repository.updatePlanStatus(plan2.id, ProactivePlanStatus.sent);
      // 上一条 sent 计划也在表中，改按 id 取。
      final row2 = await (db.select(
        db.proactivePlans,
      )..where(($ProactivePlansTable t) => t.id.equals(plan2.id))).getSingle();
      expect(row2.sentAt, fixedNow);
    });

    test('updatePlanStatus：非 sent 状态不写 sentAt（保留原值/保持 null）', () async {
      final ids = await seedChain(db);
      final plan = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '过期计划',
        scheduledAt: fixedNow.subtract(const Duration(hours: 2)),
        messageId: null,
      );

      await repository.updatePlanStatus(plan.id, ProactivePlanStatus.expired);
      var reloaded = await (db.select(
        db.proactivePlans,
      )..where(($ProactivePlansTable t) => t.id.equals(plan.id))).getSingle();
      expect(reloaded.status, ProactivePlanStatus.expired);
      expect(reloaded.sentAt, isNull);

      // sent 后再置 dropped：sentAt 不被清空（仅 sent 写入，其余保留）。
      await repository.updatePlanStatus(
        plan.id,
        ProactivePlanStatus.sent,
        sentAt: fixedNow,
      );
      await repository.updatePlanStatus(plan.id, ProactivePlanStatus.dropped);
      reloaded = await (db.select(
        db.proactivePlans,
      )..where(($ProactivePlansTable t) => t.id.equals(plan.id))).getSingle();
      expect(reloaded.status, ProactivePlanStatus.dropped);
      expect(reloaded.sentAt, fixedNow);
    });

    test('deletePlan：删除返回 true，不存在返回 false', () async {
      final ids = await seedChain(db);
      final plan = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '待删除',
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        messageId: null,
      );
      expect(await repository.deletePlan(plan.id), isTrue);
      expect(await repository.deletePlan(plan.id), isFalse);
    });

    test('listPlansByStatus：按状态过滤并按 scheduledAt 升序', () async {
      final ids = await seedChain(db);
      final later = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '晚些',
        scheduledAt: fixedNow.add(const Duration(hours: 3)),
        messageId: null,
      );
      final sooner = await repository.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '早些',
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        messageId: null,
      );
      await repository.updatePlanStatus(later.id, ProactivePlanStatus.sent);

      final scheduled = await repository.listPlansByStatus(
        ProactivePlanStatus.scheduled,
      );
      expect(scheduled.map((p) => p.id), [sooner.id]);
      final sent = await repository.listPlansByStatus(ProactivePlanStatus.sent);
      expect(sent.map((p) => p.id), [later.id]);
    });
  });

  group('内心独白 InnerThoughts', () {
    test('createThought 落库（characterId/messageId/content/createdAt）', () async {
      final ids = await seedChain(db);
      final thought = await repository.createThought(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: '她没抬头，但指节发白。',
      );

      expect(thought.characterId, ids.characterId);
      expect(thought.messageId, ids.messageId);
      expect(thought.content, '她没抬头，但指节发白。');
      expect(thought.createdAt, fixedNow);
    });

    test('listThoughtsByMessage：按消息过滤并按 createdAt 升序', () async {
      final ids = await seedChain(db);
      final now = DateTime(2026, 9, 1);
      final otherMessage = await db
          .into(db.messages)
          .insertReturning(
            MessagesCompanion.insert(
              conversationId: ids.conversationId,
              role: Role.assistant,
              content: '另一条消息',
              createdAt: now,
            ),
          );

      await repository.createThought(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: '第一条',
      );
      fixedNow = fixedNow.add(const Duration(seconds: 5));
      await repository.createThought(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: '第二条',
      );
      await repository.createThought(
        characterId: ids.characterId,
        messageId: otherMessage.id,
        content: '别的消息的独白',
      );

      final rows = await repository.listThoughtsByMessage(ids.messageId);
      expect(rows.map((t) => t.content), ['第一条', '第二条']);
    });
  });
}
