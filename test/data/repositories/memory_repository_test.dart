/// 记忆仓储行为契约（AC-01 验收：MemoryEntries + PersonaRevisions 全语义 CRUD）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上运行真 schema；
/// 语义锚点为 ADR-0003（单表 + kind 区分 / 版本化快照）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
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
    final character = await db.into(db.characters).insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            createdAt: fakeNow,
            updatedAt: fakeNow,
          ),
        );
    return character.id;
  }

  group('记忆条目 CRUD', () {
    test('createEntry 赋值时间戳；listEntries 按 importance 降序、createdAt 倒序', () async {
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
    });

    test('listEntries kind 过滤 + limit 截断', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.personaFact, content: 'p1');
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.personaFact, content: 'p2');
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.episodic, content: 'e1');

      final facts = await repo.listEntries(characterId, kind: MemoryKind.personaFact);
      expect(facts.map((e) => e.content).toSet(), {'p1', 'p2'});

      final limited = await repo.listEntries(characterId, limit: 1);
      expect(limited.length, 1);
    });

    test('listPersonaFacts 仅返回人格事实；listRecentEpisodic 最近 N 条倒序', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.personaFact, content: '人格');
      advanceSeconds(1);
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.episodic, content: '旧情景');
      advanceSeconds(1);
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.episodic, content: '新情景');

      final facts = await repo.listPersonaFacts(characterId);
      expect(facts.map((e) => e.content), ['人格']);

      final recent = await repo.listRecentEpisodic(characterId, limit: 1);
      expect(recent.map((e) => e.content), ['新情景']);
    });

    test('searchEntries 子串匹配；空串短路返回空', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.episodic, content: '我喜欢吃辣');
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.episodic, content: '我讨厌香菜');

      final hits = await repo.searchEntries(characterId, '香菜');
      expect(hits.map((e) => e.content), ['我讨厌香菜']);

      final empty = await repo.searchEntries(characterId, '   ');
      expect(empty, isEmpty);
    });

    test('updateEntry 部分更新仅写显式字段并前移 updated_at；不存在返回 null', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
          characterId: characterId, kind: MemoryKind.episodic, content: '原始');
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
          characterId: characterId, kind: MemoryKind.episodic, content: 'x');
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
          reason: '首次');
      advanceSeconds(1);
      await repo.addRevision(
          characterId: characterId,
          personalitySnapshot: 'v2',
          reason: '演化');

      final revisions = await repo.listRevisions(characterId);
      expect(revisions.map((r) => r.personalitySnapshot), ['v2', 'v1']);
      expect(revisions.first.reason, '演化');
    });
  });

  group('级联删除', () {
    test('删除角色后其记忆条目与人设版本级联清除', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
          characterId: characterId, kind: MemoryKind.personaFact, content: 'f');
      await repo.addRevision(
          characterId: characterId, personalitySnapshot: 'v');

      await (db.delete(db.characters)
            ..where((t) => t.id.equals(characterId)))
          .go();

      // 直接经 drift 查询原始表（绕过仓储过滤），确认 FK CASCADE 生效。
      final entries = await db.select(db.memoryEntries).get();
      final revisions = await db.select(db.personaRevisions).get();
      expect(entries, isEmpty);
      expect(revisions, isEmpty);
    });
  });
}
