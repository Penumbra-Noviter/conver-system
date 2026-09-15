/// 记忆仓储 — 人机恋板块（ADR-0003）记忆条目与人设演化版本的数据访问层。
///
/// 无桌面权威源（移动端先行表），语义锚点为 ADR-0003 与逆向对照材料
/// （`.scratch/aiyun-unpack/DYNAMIC_UNPACK_REPORT.md`，仅本地对照学习）。
///
/// 对齐要点：
/// - `MemoryEntries` 单表 + kind 区分（persona_fact 人格事实 / episodic 情景记忆）；
/// - 人格事实（persona_fact）抗 OOC 每轮重注入，故 [listPersonaFacts] 单独暴露；
/// - 情景记忆（episodic）少数次注入，[listRecentEpisodic] 按最近截断；
/// - 排序：条目列表按 `importance` 降序、`createdAt` 倒序（高重要 + 新的在前）；
/// - created_at / updated_at 全部由本层赋值（drift 列无 DB 默认，对齐既有仓储惯例）；
/// - `PersonaRevisions` 记录人设演化快照，随角色删除级联清除。
library;

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/tables.dart';

/// 记忆仓储 — 记忆条目 + 人设演化版本两表的 CRUD 语义。
class MemoryRepository {
  /// [now] 为时间戳来源注入点（测试确定性用），缺省 [DateTime.now]。
  MemoryRepository(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  // ── 记忆条目 ──

  /// 指定角色的记忆条目，按 `importance` 降序、`createdAt` 倒序（同重要度新的
  /// 在前）。[kind] 非空时按类型过滤；[limit] 非空时截断前 N 条。
  Future<List<MemoryEntry>> listEntries(
    int characterId, {
    MemoryKind? kind,
    int? limit,
  }) {
    final query = _db.select(_db.memoryEntries)
      ..where(($MemoryEntriesTable t) => t.characterId.equals(characterId));
    if (kind != null) {
      query.where(($MemoryEntriesTable t) => t.kind.equalsValue(kind));
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.importance),
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.id),
    ]);
    if (limit != null) {
      query.limit(limit);
    }
    return query.get();
  }

  /// 指定角色的全部人格事实（kind = persona_fact），抗 OOC 每轮重注入用。
  ///
  /// 与 [listEntries] 同排序（importance 降序、createdAt 倒序）。
  Future<List<MemoryEntry>> listPersonaFacts(int characterId) =>
      listEntries(characterId, kind: MemoryKind.personaFact);

  /// 指定角色最近的 [limit] 条情景记忆（kind = episodic），按 `createdAt` 倒序
  /// （最近在前）。少数次注入用，缺省取最近 10 条。
  Future<List<MemoryEntry>> listRecentEpisodic(
    int characterId, {
    int limit = 10,
  }) {
    final query = _db.select(_db.memoryEntries)
      ..where(($MemoryEntriesTable t) => t.characterId.equals(characterId))
      ..where(($MemoryEntriesTable t) => t.kind.equalsValue(MemoryKind.episodic))
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    return query.get();
  }

  /// 检索指定角色记忆条目中 `content` 子串匹配 [query] 的条目（`<search:>`
  /// 指令落地）。空串 / 纯空白 → 空列表（零查询短路）；按重要性降序、新在前；
  /// [limit] 截断（缺省 10）。
  Future<List<MemoryEntry>> searchEntries(
    int characterId,
    String query, {
    int limit = 10,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return Future.value(const <MemoryEntry>[]);
    }
    final pattern = '%$trimmed%';
    final stmt = _db.select(_db.memoryEntries)
      ..where(($MemoryEntriesTable t) => t.characterId.equals(characterId))
      ..where(($MemoryEntriesTable t) => t.content.like(pattern))
      ..orderBy([
        (t) => OrderingTerm.desc(t.importance),
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    return stmt.get();
  }

  /// 创建记忆条目；created_at / updated_at 由本层赋值（显式传入的时间戳被覆盖）。
  Future<MemoryEntry> createEntry({
    required int characterId,
    required MemoryKind kind,
    required String content,
    int importance = 0,
  }) {
    final now = _now();
    return _db.into(_db.memoryEntries).insertReturning(
          MemoryEntriesCompanion.insert(
            characterId: characterId,
            kind: kind,
            content: content,
            importance: Value(importance),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 部分更新记忆条目：仅写 [content] / [importance] 中显式提供的字段，并前移
  /// updated_at。条目不存在返回 null；两字段都未显式提供时返回现有条目
  /// （零 UPDATE 语句，对齐角色仓储部分更新语义）。
  Future<MemoryEntry?> updateEntry(
    int entryId, {
    String? content,
    int? importance,
  }) async {
    final existing = await (_db.select(_db.memoryEntries)
          ..where(($MemoryEntriesTable t) => t.id.equals(entryId)))
        .getSingleOrNull();
    if (existing == null) {
      return null;
    }
    if (content == null && importance == null) {
      return existing;
    }
    await (_db.update(_db.memoryEntries)
          ..where(($MemoryEntriesTable t) => t.id.equals(entryId)))
        .write(
      MemoryEntriesCompanion(
        content: content == null ? const Value.absent() : Value(content),
        importance: importance == null
            ? const Value.absent()
            : Value(importance),
        updatedAt: Value(_now()),
      ),
    );
    return (_db.select(_db.memoryEntries)
          ..where(($MemoryEntriesTable t) => t.id.equals(entryId)))
        .getSingleOrNull();
  }

  /// 删除记忆条目；返回是否确有条目被删（不存在 → false 且零副作用）。
  Future<bool> deleteEntry(int entryId) async {
    final affected = await (_db.delete(_db.memoryEntries)
          ..where(($MemoryEntriesTable t) => t.id.equals(entryId)))
        .go();
    return affected > 0;
  }

  // ── 人设演化版本 ──

  /// 指定角色的人设演化版本，按 `createdAt` 倒序（最新在前）。
  Future<List<PersonaRevision>> listRevisions(int characterId) {
    return (_db.select(_db.personaRevisions)
          ..where(
              ($PersonaRevisionsTable t) => t.characterId.equals(characterId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .get();
  }

  /// 单条人设演化版本；不存在返回 null（人设演化确认闸门用）。
  Future<PersonaRevision?> getRevision(int revisionId) {
    return (_db.select(_db.personaRevisions)
          ..where(($PersonaRevisionsTable t) => t.id.equals(revisionId)))
        .getSingleOrNull();
  }

  /// 删除单条人设演化版本（拒绝演化 / 清理用）；返回是否确有版本被删。
  Future<bool> deleteRevision(int revisionId) async {
    final affected = await (_db.delete(_db.personaRevisions)
          ..where(($PersonaRevisionsTable t) => t.id.equals(revisionId)))
        .go();
    return affected > 0;
  }

  /// 记录一条人设演化版本快照；created_at 由本层赋值。
  Future<PersonaRevision> addRevision({
    required int characterId,
    required String personalitySnapshot,
    String reason = '',
  }) {
    return _db.into(_db.personaRevisions).insertReturning(
          PersonaRevisionsCompanion.insert(
            characterId: characterId,
            personalitySnapshot: personalitySnapshot,
            reason: Value(reason),
            createdAt: _now(),
          ),
        );
  }
}
