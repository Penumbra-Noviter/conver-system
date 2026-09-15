/// 阶段 2 三表仓储 — RelationshipStates / ProactivePlans / InnerThoughts CRUD。
///
/// 无桌面权威源（移动端先行表，spec §3），语义锚点为 Grilling 共识与
/// PS2-01 数据契约。
///
/// 对齐要点（沿 MemoryRepository 惯例）：
/// - `now` 注入点：时间戳本层赋值（relationship.updatedAt / thought.createdAt）
///   与 `getActivePlan` 的「在途」判定共用（测试注入固定时间）；
/// - `upsertRelationship` 按 characterId 唯一索引 upsert（drift `DoUpdate`
///   显式 conflict target，非默认主键 target——实测语义）；
/// - `affinity` 0-100 仓储层 clamp（沿 spec：无 DB CHECK 先例）；
/// - 排序确定性：所有 list 查询带显式 id 兜底。
library;

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/tables.dart';

/// 阶段 2 三表的 CRUD 语义实现（关系状态 / 主动消息计划 / 内心独白）。
class CompanionRepository {
  /// [now] 为时间戳来源注入点（测试确定性用，含 getActivePlan 时间边界），
  /// 缺省 [DateTime.now]。affinity clamp 下/上界常量见类注释。
  CompanionRepository(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// affinity 合法区间 [0, 100]（spec §3；仓储层 clamp，DB 无 CHECK）。
  static const int affinityMin = 0;
  static const int affinityMax = 100;

  // ── 关系状态 ──

  /// 指定角色的关系状态；无行返回 null。
  Future<RelationshipState?> getRelationship(int characterId) {
    return (_db.select(_db.relationshipStates)
          ..where(
              ($RelationshipStatesTable t) => t.characterId.equals(characterId)))
        .getSingleOrNull();
  }

  /// 创建或更新角色关系状态（按 characterId 唯一索引 upsert，幂等：同角色
  /// 二次调用更新而非插新行）。[affinity] clamp 到 [affinityMin,
  /// affinityMax]；updated_at 由本层赋值。
  ///
  /// 冲突目标显式声明为 characterId（drift `DoUpdate` 默认以主键 id 为
  /// 冲突目标，对 unique characterId 索引无效——实测语义）。
  Future<RelationshipState> upsertRelationship({
    required int characterId,
    required RelationshipStage stage,
    required int affinity,
  }) {
    final clamped = affinity.clamp(affinityMin, affinityMax);
    final now = _now();
    final companion = RelationshipStatesCompanion.insert(
      characterId: characterId,
      stage: stage,
      affinity: Value(clamped),
      updatedAt: now,
    );
    return _db.into(_db.relationshipStates).insertReturning(
      companion,
      onConflict: DoUpdate((_) => companion, target: [_db.relationshipStates.characterId]),
    );
  }

  /// 全部关系状态，按 characterId 升序（确定性排序）。
  Future<List<RelationshipState>> listRelationships() {
    return (_db.select(_db.relationshipStates)
          ..orderBy([(t) => OrderingTerm.asc(t.characterId)]))
        .get();
  }

  // ── 主动消息计划 ──

  /// 创建一条主动消息计划：默认 status = scheduled，sentAt 不写入，messageId
  /// 可空（无已落消息时传 null）。
  Future<ProactivePlan> createPlan({
    required int characterId,
    required int conversationId,
    required String content,
    required DateTime scheduledAt,
    int? messageId,
  }) {
    return _db.into(_db.proactivePlans).insertReturning(
          ProactivePlansCompanion.insert(
            characterId: characterId,
            conversationId: conversationId,
            content: content,
            scheduledAt: scheduledAt,
            sentAt: const Value(null),
            status: ProactivePlanStatus.scheduled,
            messageId: Value(messageId),
          ),
        );
  }

  /// 指定角色的「在途」计划：status == scheduled 且 scheduledAt > now（now 取
  /// 本层注入点，测试确定性）。到点 / 其他状态一律不返回。
  Future<ProactivePlan?> getActivePlan(int characterId) {
    final at = _now();
    return (_db.select(_db.proactivePlans)
          ..where(($ProactivePlansTable t) =>
              t.characterId.equals(characterId) &
              t.status.equalsValue(ProactivePlanStatus.scheduled) &
              t.scheduledAt.isBiggerThanValue(at)))
        .getSingleOrNull();
  }

  /// 按消息 id 反查计划（C1 送达收口用：通知深链 payload 只有 messageId）。
  /// messageId 可空列——null/未命中 → null；同 messageId 双计划按 W2 实测
  /// 会抛 StateError（正常不可达：createPlan 由消息回填唯一），docstring 明示。
  Future<ProactivePlan?> getPlanByMessageId(int messageId) {
    return (_db.select(_db.proactivePlans)
          ..where(($ProactivePlansTable t) => t.messageId.equals(messageId)))
        .getSingleOrNull();
  }

  /// 更新计划状态；`sentAt` **仅** status = sent 时写入（显式传入优先，
  /// 缺省取本层 now），其余状态不触碰 sentAt（保留原值）。
  Future<void> updatePlanStatus(
    int planId,
    ProactivePlanStatus status, {
    DateTime? sentAt,
  }) async {
    await (_db.update(_db.proactivePlans)
          ..where(($ProactivePlansTable t) => t.id.equals(planId)))
        .write(
      ProactivePlansCompanion(
        status: Value(status),
        sentAt: status == ProactivePlanStatus.sent
            ? Value(sentAt ?? _now())
            : const Value.absent(),
      ),
    );
  }

  /// 删除计划；返回是否确有计划被删（不存在 → false 且零副作用）。
  Future<bool> deletePlan(int planId) async {
    final affected = await (_db.delete(_db.proactivePlans)
          ..where(($ProactivePlansTable t) => t.id.equals(planId)))
        .go();
    return affected > 0;
  }

  /// 按状态列出计划，scheduledAt 升序 + id 升序（确定性）。
  Future<List<ProactivePlan>> listPlansByStatus(ProactivePlanStatus status) {
    return (_db.select(_db.proactivePlans)
          ..where(($ProactivePlansTable t) => t.status.equalsValue(status))
          ..orderBy([
            (t) => OrderingTerm.asc(t.scheduledAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  // ── 内心独白 ──

  /// 创建一条内心独白（剥离的 `<thought>` 内容）；created_at 由本层赋值。
  Future<InnerThought> createThought({
    required int characterId,
    required int messageId,
    required String content,
  }) {
    return _db.into(_db.innerThoughts).insertReturning(
          InnerThoughtsCompanion.insert(
            characterId: characterId,
            messageId: messageId,
            content: content,
            createdAt: _now(),
          ),
        );
  }

  /// 指定消息的内心独白（thought 随消息级联删除前的查询面），createdAt 升序
  /// + id 升序（确定性）。
  Future<List<InnerThought>> listThoughtsByMessage(int messageId) {
    return (_db.select(_db.innerThoughts)
          ..where(($InnerThoughtsTable t) => t.messageId.equals(messageId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }
}