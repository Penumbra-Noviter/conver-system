/// 记忆仓储行为契约（AC-01 验收：MemoryEntries + PersonaRevisions 全语义 CRUD；
/// VR-05 扩展：EmbeddingEntries 向量 CRUD + SemanticHits 队列 CRUD 语义）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上运行真 schema；
/// 语义锚点为 ADR-0003（单表 + kind 区分 / 版本化快照）与
/// stage3-vector-recall spec §2 D2 / SR-21（hash 去重 / 截断 2000 / 幂等）。
library;

import 'dart:convert';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/utils/float32_codec.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late MemoryRepository repo;

  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
  void advanceSeconds(int seconds) {
    fakeNow = fakeNow.add(Duration(seconds: seconds));
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MemoryRepository(db, now: () => fakeNow);
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一个角色，返回其 id（记忆条目挂角色名下）。
  Future<int> seedCharacter() async {
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            createdAt: fakeNow,
            updatedAt: fakeNow,
          ),
        );
    return character.id;
  }

  group('记忆条目 CRUD', () {
    test(
      'createEntry 赋值时间戳；listEntries 按 importance 降序、createdAt 倒序',
      () async {
        final characterId = await seedCharacter();
        advanceSeconds(1);
        final low = await repo.createEntry(
          characterId: characterId,
          kind: MemoryKind.episodic,
          content: '低重要旧',
          importance: 1,
        );
        advanceSeconds(1);
        final high = await repo.createEntry(
          characterId: characterId,
          kind: MemoryKind.personaFact,
          content: '高重要新',
          importance: 5,
        );

        final list = await repo.listEntries(characterId);
        expect(list.map((e) => e.content), ['高重要新', '低重要旧']);
        expect(list.first.kind, MemoryKind.personaFact);
        expect(list.first.createdAt, high.createdAt);
        expect(low.createdAt.isBefore(high.createdAt), isTrue);
        expect(low.updatedAt, low.createdAt);
      },
    );

    test('listEntries kind 过滤 + limit 截断', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: 'p1',
      );
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: 'p2',
      );
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'e1',
      );

      final facts = await repo.listEntries(
        characterId,
        kind: MemoryKind.personaFact,
      );
      expect(facts.map((e) => e.content).toSet(), {'p1', 'p2'});

      final limited = await repo.listEntries(characterId, limit: 1);
      expect(limited.length, 1);
    });

    test('listPersonaFacts 仅返回人格事实；listRecentEpisodic 最近 N 条倒序', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '人格',
      );
      advanceSeconds(1);
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '旧情景',
      );
      advanceSeconds(1);
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '新情景',
      );

      final facts = await repo.listPersonaFacts(characterId);
      expect(facts.map((e) => e.content), ['人格']);

      final recent = await repo.listRecentEpisodic(characterId, limit: 1);
      expect(recent.map((e) => e.content), ['新情景']);
    });

    test('searchEntries 子串匹配；空串短路返回空', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '我喜欢吃辣',
      );
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '我讨厌香菜',
      );

      final hits = await repo.searchEntries(characterId, '香菜');
      expect(hits.map((e) => e.content), ['我讨厌香菜']);

      final empty = await repo.searchEntries(characterId, '   ');
      expect(empty, isEmpty);
    });

    test('updateEntry 部分更新仅写显式字段并前移 updated_at；不存在返回 null', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '原始',
      );
      advanceSeconds(10);

      final updated = await repo.updateEntry(entry.id, importance: 7);
      expect(updated!.content, '原始');
      expect(updated.importance, 7);
      expect(updated.updatedAt.isAfter(entry.updatedAt), isTrue);

      final noFields = await repo.updateEntry(entry.id);
      expect(noFields!.content, '原始');

      final missing = await repo.updateEntry(99999, content: 'x');
      expect(missing, isNull);
    });

    test('deleteEntry 存在返回 true、不存在返回 false', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'x',
      );
      expect(await repo.deleteEntry(entry.id), isTrue);
      expect(await repo.deleteEntry(entry.id), isFalse);
      expect(await repo.listEntries(characterId), isEmpty);
    });
  });

  group('人设演化版本', () {
    test('addRevision 落库；listRevisions 按 createdAt 倒序', () async {
      final characterId = await seedCharacter();
      advanceSeconds(1);
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: 'v1',
        reason: '首次',
      );
      advanceSeconds(1);
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: 'v2',
        reason: '演化',
      );

      final revisions = await repo.listRevisions(characterId);
      expect(revisions.map((r) => r.personalitySnapshot), ['v2', 'v1']);
      expect(revisions.first.reason, '演化');
    });
  });

  group('级联删除', () {
    test('删除角色后其记忆条目与人设版本级联清除', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: 'f',
      );
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: 'v',
      );

      await (db.delete(
        db.characters,
      )..where((t) => t.id.equals(characterId))).go();

      // 直接经 drift 查询原始表（绕过仓储过滤），确认 FK CASCADE 生效。
      final entries = await db.select(db.memoryEntries).get();
      final revisions = await db.select(db.personaRevisions).get();
      expect(entries, isEmpty);
      expect(revisions, isEmpty);
    });
  });

  group('向量 CRUD（VR-05）', () {
    const vectorA = [1.0, 0.0, 0.0, 0.0];
    const vectorB = [0.0, 1.0, 0.0, 0.0];

    Future<EmbeddingEntry> upsertSample(
      int characterId,
      int entryId, {
      String content = '记忆内容',
      List<double> vector = vectorA,
      String model = 'text-embedding-3-small',
      int dims = 4,
    }) {
      return repo.upsertEmbedding(
        characterId: characterId,
        entryId: entryId,
        content: content,
        vector: vector,
        model: model,
        dims: dims,
      );
    }

    test('新建：快照/指纹/时间戳落库，blob 可解码往返', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'x',
      );

      final row = await upsertSample(characterId, entry.id);

      expect(row.id, greaterThan(0));
      expect(row.characterId, characterId);
      expect(row.entryId, entry.id);
      expect(row.contentSnapshot, '记忆内容');
      expect(row.contentHash, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(row.contentHash), isTrue);
      expect(row.model, 'text-embedding-3-small');
      expect(row.dims, 4);
      expect(row.createdAt, row.updatedAt);
      final decoded = unpackFloat32(row.vector);
      expect(decoded.length, 4);
      for (var i = 0; i < decoded.length; i++) {
        expect(decoded[i], closeTo(vectorA[i], 1e-6));
      }
    });

    test('验收2-内容超 2000 字符落库快照恰为前 2000 字符', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'x',
      );
      final longContent = List.filled(2500, '字').join();

      final row = await upsertSample(
        characterId,
        entry.id,
        content: longContent,
      );

      expect(row.contentSnapshot.length, 2000);
      expect(row.contentSnapshot, List.filled(2000, '字').join());
      // hash 基于截断后快照计算（SR-21 去重键与落库快照自洽）。
      expect(
        row.contentHash,
        sha256.convert(utf8.encode(row.contentSnapshot)).toString(),
      );
    });

    test('验收1-同 character+contentHash 重复补嵌不产生第二行，vector 更新', () async {
      final characterId = await seedCharacter();
      final entryA = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '喜欢猫',
      );
      final entryB = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '喜欢猫',
      );

      final first = await upsertSample(characterId, entryA.id, content: '喜欢猫');
      advanceSeconds(5);
      await upsertSample(
        characterId,
        entryB.id,
        content: '喜欢猫',
        vector: vectorB,
      );

      final rows = await repo.listEmbeddingsByCharacter(characterId);
      expect(rows.length, 1);
      expect(rows.single.id, first.id);
      expect(rows.single.entryId, entryB.id);
      expect(rows.single.updatedAt.isAfter(first.updatedAt), isTrue);
      final decoded = unpackFloat32(rows.single.vector);
      for (var i = 0; i < decoded.length; i++) {
        expect(decoded[i], closeTo(vectorB[i], 1e-6));
      }
    });

    test('不同角色同内容互不干扰（各一行）', () async {
      final c1 = await seedCharacter();
      final c2 = await seedCharacter();
      await upsertSample(c1, 1, content: '同内容');
      await upsertSample(c2, 2, content: '同内容');

      expect((await repo.listEmbeddingsByCharacter(c1)).length, 1);
      expect((await repo.listEmbeddingsByCharacter(c2)).length, 1);
    });

    test('验收4-listEmbeddingsByCharacter 按 id 升序 + model/dims 指纹过滤', () async {
      final characterId = await seedCharacter();
      final e1 = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'a',
      );
      final e2 = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'b',
      );
      final e3 = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'c',
      );
      advanceSeconds(1);
      await upsertSample(characterId, e1.id, content: 'a');
      await upsertSample(
        characterId,
        e2.id,
        content: 'b',
        model: 'text-embedding-3-small',
        dims: 8,
        vector: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      );
      await upsertSample(
        characterId,
        e3.id,
        content: 'c',
        model: 'other-model',
      );

      final all = await repo.listEmbeddingsByCharacter(characterId);
      expect(all.map((r) => r.contentSnapshot), ['a', 'b', 'c']);

      final byModel = await repo.listEmbeddingsByCharacter(
        characterId,
        model: 'text-embedding-3-small',
      );
      expect(byModel.map((r) => r.contentSnapshot), ['a', 'b']);

      final byDims = await repo.listEmbeddingsByCharacter(characterId, dims: 4);
      expect(byDims.map((r) => r.contentSnapshot), ['a', 'c']);

      final byBoth = await repo.listEmbeddingsByCharacter(
        characterId,
        model: 'text-embedding-3-small',
        dims: 8,
      );
      expect(byBoth.map((r) => r.contentSnapshot), ['b']);

      expect(await repo.listEmbeddingsByCharacter(99999), isEmpty);
    });

    test('deleteEmbeddingByEntryId 删除后不再出现；重复删除 false', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'x',
      );
      await upsertSample(characterId, entry.id);

      expect(await repo.deleteEmbeddingByEntryId(entry.id), isTrue);
      expect(await repo.listEmbeddingsByCharacter(characterId), isEmpty);
      expect(await repo.deleteEmbeddingByEntryId(entry.id), isFalse);
    });

    test('验收5-updateEntry content 实际变化 → 该 entryId 向量行删除（标脏）', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '旧内容',
      );
      await upsertSample(characterId, entry.id, content: '旧内容');

      final updated = await repo.updateEntry(entry.id, content: '新内容');
      expect(updated!.content, '新内容');
      expect(await repo.listEmbeddingsByCharacter(characterId), isEmpty);
    });

    test('验收5-updateEntry content 未变 → 向量保留；无字段部分更新也保留', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '稳定内容',
      );
      await upsertSample(characterId, entry.id, content: '稳定内容');

      await repo.updateEntry(entry.id, content: '稳定内容');
      expect((await repo.listEmbeddingsByCharacter(characterId)).length, 1);

      await repo.updateEntry(entry.id, importance: 3);
      expect((await repo.listEmbeddingsByCharacter(characterId)).length, 1);
    });

    test('验收6-deleteEntry → 该条目向量行同步删除（零残留）', () async {
      final characterId = await seedCharacter();
      final entryA = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'A',
      );
      final entryB = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'B',
      );
      await upsertSample(characterId, entryA.id, content: 'A');
      await upsertSample(characterId, entryB.id, content: 'B');

      expect(await repo.deleteEntry(entryA.id), isTrue);

      final remaining = await repo.listEmbeddingsByCharacter(characterId);
      expect(remaining.map((r) => r.contentSnapshot), ['B']);
      expect(await repo.listEntries(characterId), hasLength(1));
    });

    test('deleteEntry 不存在 → false，其他条目向量不受影响', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: 'x',
      );
      await upsertSample(characterId, entry.id);

      expect(await repo.deleteEntry(99999), isFalse);
      expect((await repo.listEmbeddingsByCharacter(characterId)).length, 1);
    });

    test('vector 长度与 dims 指纹不符 → 断言失败（debug 守卫）', () async {
      final characterId = await seedCharacter();
      expect(
        () =>
            upsertSample(characterId, 1, vector: [1.0, 0.0, 0.0, 0.0], dims: 8),
        throwsA(isA<AssertionError>()),
      );
    });

    test('角色删除 → 向量表按角色级联清空', () async {
      final c1 = await seedCharacter();
      final c2 = await seedCharacter();
      await upsertSample(c1, 1, content: '甲');
      await upsertSample(c2, 2, content: '乙');

      await (db.delete(db.characters)..where((t) => t.id.equals(c1))).go();

      final rows = await db.select(db.embeddingEntries).get();
      expect(rows.map((r) => r.characterId), [c2]);
    });
  });

  group('语义命中队列（VR-05）', () {
    test('enqueue 新 pair 落库并返回 true；createdAt 由仓储赋值', () async {
      final characterId = await seedCharacter();
      final enqueued = await repo.enqueueSemanticHit(
        characterId: characterId,
        entryId: 7,
        query: '喜欢什么',
      );
      expect(enqueued, isTrue);

      final hits = await db.select(db.semanticHits).get();
      expect(hits.single.characterId, characterId);
      expect(hits.single.entryId, 7);
      expect(hits.single.query, '喜欢什么');
      expect(hits.single.createdAt, fakeNow);
    });

    test('验收7-同 character+entryId 已有未消费行 → 跳过；不同 query 同 pair 也去重', () async {
      final characterId = await seedCharacter();
      expect(
        await repo.enqueueSemanticHit(
          characterId: characterId,
          entryId: 3,
          query: '第一次查询',
        ),
        isTrue,
      );
      expect(
        await repo.enqueueSemanticHit(
          characterId: characterId,
          entryId: 3,
          query: '换个问法',
        ),
        isFalse,
      );

      final hits = await db.select(db.semanticHits).get();
      expect(hits.length, 1);
      expect(hits.single.query, '第一次查询');
    });

    test('跨角色同 entryId 各自入队（去重键 = characterId+entryId）', () async {
      final c1 = await seedCharacter();
      final c2 = await seedCharacter();
      expect(
        await repo.enqueueSemanticHit(characterId: c1, entryId: 9, query: 'q'),
        isTrue,
      );
      expect(
        await repo.enqueueSemanticHit(characterId: c2, entryId: 9, query: 'q'),
        isTrue,
      );
      expect((await db.select(db.semanticHits).get()).length, 2);
    });

    test('验收8-listPendingSemanticHits 默认 ≤3 条且按入队序（createdAt 升序）', () async {
      final characterId = await seedCharacter();
      for (var i = 1; i <= 4; i++) {
        advanceSeconds(1);
        await repo.enqueueSemanticHit(
          characterId: characterId,
          entryId: i,
          query: 'q$i',
        );
      }

      final pending = await repo.listPendingSemanticHits(characterId);
      expect(pending.map((h) => h.query), ['q1', 'q2', 'q3']);

      final limited = await repo.listPendingSemanticHits(characterId, limit: 2);
      expect(limited.map((h) => h.query), ['q1', 'q2']);

      // 防御：limit < 1（含 0/负数）不返回任何行——防注入上限被打穿。
      expect(
        await repo.listPendingSemanticHits(characterId, limit: 0),
        isEmpty,
      );
      expect(
        await repo.listPendingSemanticHits(characterId, limit: -1),
        isEmpty,
      );

      expect(await repo.listPendingSemanticHits(99999), isEmpty);
    });

    test('验收8-deleteSemanticHit 消费删除后不再出现；重复删除 false', () async {
      final characterId = await seedCharacter();
      await repo.enqueueSemanticHit(
        characterId: characterId,
        entryId: 1,
        query: 'a',
      );
      await repo.enqueueSemanticHit(
        characterId: characterId,
        entryId: 2,
        query: 'b',
      );

      final hits = await repo.listPendingSemanticHits(characterId);
      expect(await repo.deleteSemanticHit(hits.first.id), isTrue);
      expect(
        (await repo.listPendingSemanticHits(characterId)).map((h) => h.query),
        ['b'],
      );
      expect(await repo.deleteSemanticHit(hits.first.id), isFalse);
    });

    test('角色删除 → 队列表按角色级联清空', () async {
      final c1 = await seedCharacter();
      final c2 = await seedCharacter();
      await repo.enqueueSemanticHit(characterId: c1, entryId: 1, query: 'q1');
      await repo.enqueueSemanticHit(characterId: c2, entryId: 2, query: 'q2');

      await (db.delete(db.characters)..where((t) => t.id.equals(c1))).go();

      final hits = await db.select(db.semanticHits).get();
      expect(hits.map((h) => h.characterId), [c2]);
    });
  });
}
