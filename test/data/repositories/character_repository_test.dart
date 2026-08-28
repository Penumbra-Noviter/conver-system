/// 角色仓储行为契约（工单 03 验收 A1/A2/A6/A7 的角色面）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上运行真 schema
/// （M0 seam 复用）；语义锚点：桌面 `services/character.py`。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CharacterRepository repo;

  // 固定起始时刻（秒对齐，drift 落库为 unix 秒），测试内手动前拨。
  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
  void advanceSeconds(int seconds) {
    fakeNow = fakeNow.add(Duration(seconds: seconds));
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CharacterRepository(db, now: () => fakeNow);
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一个角色（可选开场白与指定时间偏移），返回落库行。
  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
    int secondsAgo = 0,
  }) {
    advanceSeconds(secondsAgo);
    return repo.createCharacter(
      CharactersCompanion(
        name: Value(name),
        firstMes: Value(firstMes),
      ),
    );
  }

  /// 直接经 drift 建对话（角色仓储测试只关心计数与级联）。
  Future<Conversation> seedConversation(int characterId) async {
    return db.into(db.conversations).insertReturning(
          ConversationsCompanion.insert(
            characterId: characterId,
            createdAt: fakeNow,
            updatedAt: fakeNow,
          ),
        );
  }

  Future<void> seedMessage(int conversationId, {Role role = Role.user}) async {
    await db.into(db.messages).insert(
          MessagesCompanion.insert(
            conversationId: conversationId,
            role: role,
            content: 'msg',
            createdAt: fakeNow,
          ),
        );
  }

  group('listCharacters（A2 排序 + conversation_count）', () {
    test('按 updated_at 倒序；conversation_count 正确（0 与多对话两态）', () async {
      final older = await seedCharacter(name: '旧角色', secondsAgo: 10);
      final newer = await seedCharacter(name: '新角色', secondsAgo: 5);
      await seedConversation(older.id);
      await seedConversation(older.id);

      final list = await repo.listCharacters();
      expect(list.map((row) => row.character.name), ['新角色', '旧角色']);
      expect(
        list.map((row) => row.conversationCount),
        [0, 2],
      );

      // 更新旧角色（时间前拨）后排到最前，计数不变。
      advanceSeconds(5);
      await repo.updateCharacter(
        older.id,
        const CharactersCompanion(description: Value('已更新')),
      );

      final refreshed = await repo.listCharacters();
      expect(refreshed.map((row) => row.character.id), [older.id, newer.id]);
      expect(refreshed.first.conversationCount, 2);
    });
  });

  group('getCharacterWithCount', () {
    test('存在 → 角色与计数；不存在 → null', () async {
      final char = await seedCharacter();
      final withCount = await repo.getCharacterWithCount(char.id);
      expect(withCount, isNotNull);
      expect(withCount!.conversationCount, 0);

      await seedConversation(char.id);
      expect((await repo.getCharacterWithCount(char.id))!.conversationCount, 1);

      expect(await repo.getCharacterWithCount(999999), isNull);
      expect(await repo.getCharacter(999999), isNull);
    });
  });

  group('createCharacter（时间戳仓储层赋值）', () {
    test('createdAt/updatedAt 由仓储赋值，其余字段走列默认', () async {
      final char = await seedCharacter(name: '诺克斯', secondsAgo: 3);
      expect(char.createdAt, fakeNow);
      expect(char.updatedAt, fakeNow);
      expect(char.description, '');
      expect(char.temperature, 0.7);
    });
  });

  group('updateCharacter（A6 部分更新）', () {
    test('仅显式字段变更且 updated_at 前移', () async {
      final char = await seedCharacter(name: '原名', secondsAgo: 0);
      final before = char.updatedAt;

      advanceSeconds(10);
      final updated = await repo.updateCharacter(
        char.id,
        const CharactersCompanion(description: Value('新描述')),
      );

      expect(updated, isNotNull);
      expect(updated!.name, '原名'); // 未显式提供的字段不变
      expect(updated.description, '新描述');
      expect(updated.updatedAt.isAfter(before), isTrue);
      expect(updated.updatedAt, fakeNow);
    });

    test('角色不存在 → null；无显式字段 → 原行返回且时间戳不动', () async {
      expect(
        await repo.updateCharacter(
          999999,
          const CharactersCompanion(name: Value('x')),
        ),
        isNull,
      );

      final char = await seedCharacter();
      final before = char.updatedAt;
      final result = await repo.updateCharacter(
        char.id,
        const CharactersCompanion(),
      );
      expect(result!.updatedAt, before);
    });
  });

  group('deleteCharacter（A7 两态 + A1 天然级联）', () {
    test('存在 → true 且角色消失', () async {
      final char = await seedCharacter();
      expect(await repo.deleteCharacter(char.id), isTrue);
      expect(await repo.getCharacter(char.id), isNull);
    });

    test('不存在 → false 且零副作用', () async {
      final char = await seedCharacter();
      expect(await repo.deleteCharacter(999999), isFalse);
      expect(await repo.getCharacter(char.id), isNotNull);
    });

    test('删角色 → 其对话与消息经 FK CASCADE 同空', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await seedMessage(conv.id, role: Role.assistant);
      await seedMessage(conv.id, role: Role.user);

      expect(await repo.deleteCharacter(char.id), isTrue);
      expect(await db.select(db.conversations).get(), isEmpty);
      expect(await db.select(db.messages).get(), isEmpty);
    });
  });
}
