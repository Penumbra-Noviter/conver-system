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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../utils/float32_codec.dart';
import '../../utils/utf16_truncate.dart' show maxSnapshotLength, truncateUtf16;
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
      ..where(
        ($MemoryEntriesTable t) => t.kind.equalsValue(MemoryKind.episodic),
      )
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
    return _db
        .into(_db.memoryEntries)
        .insertReturning(
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
  ///
  /// VR-05 级联标脏（spec §2 D2）：显式传入的 [content] 与现有内容**实际不同**
  /// 时，同步删除该条目的向量行（旧向量语义过期，下次检索前懒补嵌）；内容
  /// 未变或未传 content 时向量保留。
  Future<MemoryEntry?> updateEntry(
    int entryId, {
    String? content,
    int? importance,
  }) async {
    final existing =
        await (_db.select(_db.memoryEntries)
              ..where(($MemoryEntriesTable t) => t.id.equals(entryId)))
            .getSingleOrNull();
    if (existing == null) {
      return null;
    }
    if (content == null && importance == null) {
      return existing;
    }
    if (content != null && content != existing.content) {
      await _deleteEmbeddingsByEntryId(entryId);
    }
    await (_db.update(
      _db.memoryEntries,
    )..where(($MemoryEntriesTable t) => t.id.equals(entryId))).write(
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

  /// 删除记忆条目；返回是否确有条目被删（不存在 → false）。
  ///
  /// VR-05 级联（spec §2 D2）：条目删除前先清该条目的向量行（零残留，
  /// 级联面自管）；[entryId] 无对应条目时向量清理为幂等空操作。
  Future<bool> deleteEntry(int entryId) async {
    await _deleteEmbeddingsByEntryId(entryId);
    final affected = await (_db.delete(
      _db.memoryEntries,
    )..where(($MemoryEntriesTable t) => t.id.equals(entryId))).go();
    return affected > 0;
  }

  // ── 人设演化版本 ──

  /// 指定角色的人设演化版本，按 `createdAt` 倒序（最新在前）。
  Future<List<PersonaRevision>> listRevisions(int characterId) {
    return (_db.select(_db.personaRevisions)
          ..where(
            ($PersonaRevisionsTable t) => t.characterId.equals(characterId),
          )
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
    final affected = await (_db.delete(
      _db.personaRevisions,
    )..where(($PersonaRevisionsTable t) => t.id.equals(revisionId))).go();
    return affected > 0;
  }

  /// 记录一条人设演化版本快照；created_at 由本层赋值。
  Future<PersonaRevision> addRevision({
    required int characterId,
    required String personalitySnapshot,
    String reason = '',
  }) {
    return _db
        .into(_db.personaRevisions)
        .insertReturning(
          PersonaRevisionsCompanion.insert(
            characterId: characterId,
            personalitySnapshot: personalitySnapshot,
            reason: Value(reason),
            createdAt: _now(),
          ),
        );
  }

  // ── 向量条目（VR-05，spec §2 D2 / SR-21）──

  /// 补嵌/更新一条向量（幂等 upsert，SR-21）。
  ///
  /// `content` 快照截断上限 [maxSnapshotLength]（Code Unit 计数，经
  /// [truncateUtf16] 防劈代理对，单源见 `lib/utils/utf16_truncate.dart`，
  /// F-115）后落库；`contentHash` 为 SHA-256 hex，基于**截断后快照**计算
  /// （去重键与落库快照自洽）；同 `(characterId, contentHash)` 已存在 →
  /// 更新同一行（vector/entryId/指纹/updatedAt），不产生第二行。[vector]
  /// 经 float32 小端打包落 blob（[dims] 为模型指纹声明，debug 下断言
  /// `vector.length == dims`）；created_at / updated_at 由本层赋值。返回
  /// 落库后的向量行。
  Future<EmbeddingEntry> upsertEmbedding({
    required int characterId,
    required int entryId,
    required String content,
    required List<double> vector,
    required String model,
    required int dims,
  }) async {
    assert(
      vector.length == dims,
      'vector.length (${vector.length}) must match dims ($dims)',
    );
    final snapshot = truncateUtf16(content, maxSnapshotLength);
    final contentHash = sha256.convert(utf8.encode(snapshot)).toString();
    final now = _now();
    final existing = await _embeddingByCharacterAndHash(
      characterId,
      contentHash,
    );
    if (existing == null) {
      return _db
          .into(_db.embeddingEntries)
          .insertReturning(
            EmbeddingEntriesCompanion.insert(
              characterId: characterId,
              entryId: entryId,
              contentSnapshot: snapshot,
              vector: packFloat32(vector),
              model: model,
              dims: dims,
              contentHash: contentHash,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await (_db.update(
      _db.embeddingEntries,
    )..where(($EmbeddingEntriesTable t) => t.id.equals(existing.id))).write(
      EmbeddingEntriesCompanion(
        entryId: Value(entryId),
        contentSnapshot: Value(snapshot),
        vector: Value(packFloat32(vector)),
        model: Value(model),
        dims: Value(dims),
        updatedAt: Value(now),
      ),
    );
    return (_db.select(_db.embeddingEntries)
          ..where(($EmbeddingEntriesTable t) => t.id.equals(existing.id)))
        .getSingle();
  }

  /// 指定角色的向量行，按 `id` 升序（入嵌序）。[model] / [dims] 非空时叠加
  /// 指纹过滤（spec §2 D2：仅当前指纹向量被检索）。
  Future<List<EmbeddingEntry>> listEmbeddingsByCharacter(
    int characterId, {
    String? model,
    int? dims,
  }) {
    final query = _db.select(_db.embeddingEntries)
      ..where(($EmbeddingEntriesTable t) => t.characterId.equals(characterId));
    if (model != null) {
      query.where(($EmbeddingEntriesTable t) => t.model.equals(model));
    }
    if (dims != null) {
      query.where(($EmbeddingEntriesTable t) => t.dims.equals(dims));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.get();
  }

  /// 按条目 id 删除向量行（条目内容更新/删除时的显式标脏，spec §2 D2）；
  /// 返回是否确有针对该条目的向量行被删。
  Future<bool> deleteEmbeddingByEntryId(int entryId) async {
    return (await _deleteEmbeddingsByEntryId(entryId)) > 0;
  }

  /// 幂等删除指定条目的全部向量行，返回被删行数（级联标脏内部入口，
  /// 零副作用；重复调用返回 0）。
  Future<int> _deleteEmbeddingsByEntryId(int entryId) {
    return (_db.delete(
      _db.embeddingEntries,
    )..where(($EmbeddingEntriesTable t) => t.entryId.equals(entryId))).go();
  }

  /// 按角色 + 内容 hash 查已有向量行（幂等 upsert 的去重判定）。
  Future<EmbeddingEntry?> _embeddingByCharacterAndHash(
    int characterId,
    String contentHash,
  ) {
    return (_db.select(_db.embeddingEntries)
          ..where(
            ($EmbeddingEntriesTable t) => t.characterId.equals(characterId),
          )
          ..where(
            ($EmbeddingEntriesTable t) => t.contentHash.equals(contentHash),
          ))
        .getSingleOrNull();
  }

  // ── 语义命中队列（VR-05，spec §2 D2）──

  /// 入队一条语义命中；同 `(characterId, entryId)` 已有未消费行 → 跳过返回
  /// false（仓储级去重，不同 query 同 pair 同样去重）；新入队返回 true。
  /// created_at 由本层赋值。
  Future<bool> enqueueSemanticHit({
    required int characterId,
    required int entryId,
    required String query,
  }) async {
    final existing =
        await (_db.select(_db.semanticHits)
              ..where(
                ($SemanticHitsTable t) => t.characterId.equals(characterId),
              )
              ..where(($SemanticHitsTable t) => t.entryId.equals(entryId)))
            .getSingleOrNull();
    if (existing != null) {
      return false;
    }
    await _db
        .into(_db.semanticHits)
        .insert(
          SemanticHitsCompanion.insert(
            characterId: characterId,
            entryId: entryId,
            query: query,
            createdAt: _now(),
          ),
        );
    return true;
  }

  /// 指定角色的未消费语义命中队列，按入队序（createdAt 升序，同刻按 id
  /// 兜底——F-106 先例）；[limit] 截断（缺省 3，spec D3 注入上限）。
  /// [limit] < 1 → 空列表（防御性：SQLite `LIMIT -1` 语义为"不限制"，负值
  /// 会把 ≤3 条注入上限打成"全量"，此处归零截断）。
  Future<List<SemanticHit>> listPendingSemanticHits(
    int characterId, {
    int limit = 3,
  }) {
    if (limit < 1) {
      return Future.value(const <SemanticHit>[]);
    }
    return (_db.select(_db.semanticHits)
          ..where(($SemanticHitsTable t) => t.characterId.equals(characterId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(limit))
        .get();
  }

  /// 消费删除一条语义命中；返回是否确有条目被删（注入后消费，spec D3）。
  Future<bool> deleteSemanticHit(int hitId) async {
    final affected = await (_db.delete(
      _db.semanticHits,
    )..where(($SemanticHitsTable t) => t.id.equals(hitId))).go();
    return affected > 0;
  }
}
