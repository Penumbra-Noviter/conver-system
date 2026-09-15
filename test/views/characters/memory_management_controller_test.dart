/// MemoryManagementController 行为契约（AC-05）：加载 / 增改删记忆条目 + 演化历史。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/views/characters/memory_management_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late MemoryRepository repo;
  late int characterId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = MemoryRepository(db);
    final character = await db.into(db.characters).insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    characterId = character.id;
  });

  tearDown(() async {
    await db.close();
  });

  MemoryManagementController buildController() =>
      MemoryManagementController(
        memoryRepository: repo,
        characterId: characterId,
      );

  group('load', () {
    test('加载记忆条目与人设演化版本', () async {
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '她叫艾莉亚',
      );
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: 'v1',
      );
      final controller = buildController();

      await controller.load();

      expect(controller.entries.map((e) => e.content), ['她叫艾莉亚']);
      expect(controller.revisions.map((r) => r.personalitySnapshot), ['v1']);
      expect(controller.loading, isFalse);
    });

    test('失败保留既有列表并置 notice', () async {
      final controller = buildController();
      await controller.load();
      expect(controller.entries, isEmpty);

      // 关闭底层库触发 load 失败。
      await db.close();
      await controller.load();
      expect(controller.notice, isNotNull);
      expect(controller.entries, isEmpty);
    });
  });

  group('增改删', () {
    test('createEntry 后条目可见；updateEntry 更新内容；deleteEntry 移除', () async {
      final controller = buildController();
      await controller.load();

      await controller.createEntry(MemoryKind.episodic, '今天聊了天气');
      expect(controller.entries.map((e) => e.content), ['今天聊了天气']);

      final entry = controller.entries.single;
      await controller.updateEntry(entry.id, content: '今天聊了天气，很开心');
      expect(controller.entries.single.content, '今天聊了天气，很开心');

      await controller.deleteEntry(entry.id);
      expect(controller.entries, isEmpty);
    });
  });

  group('dismissNotice', () {
    test('清除 notice', () async {
      final controller = buildController();
      await db.close();
      await controller.load();
      expect(controller.notice, isNotNull);

      controller.dismissNotice();
      expect(controller.notice, isNull);
    });
  });
}
