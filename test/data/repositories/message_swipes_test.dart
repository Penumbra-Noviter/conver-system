/// MS-01：MessageRepository swipes 契约（追加/列表/切换/删除/级联 + 不变量）。
///
/// 测试 seam（公共接口边界）：[MessageRepository] 公开 API（addSwipe /
/// listSwipes / switchSwipe / deleteSwipe / deleteMessage）+ 领域错误
/// （SwipeIndexOutOfRangeError / MessageNotFoundError）。经内存 drift 真实
/// schema 驱动，不 mock 内部。
///
/// 语义锚（桌面权威源只读）：
/// - `desktop/backend/app/services/message.py`（add_swipe L346-390 /
///   switch_swipe L471-499 / delete_swipe L502-545）
/// - spec §4.2 / 工单 01 验收 2-5 / SR-27
///
/// 移动端有意偏差（详见 concerns/01.md §3）：桌面候选 0 受保护拒删（
/// message.py L515-516），移动端按工单验收 4/5 允许删空候选集、active 回落
/// 0 锁定（不变量退化态）；删当前候选的回落选择规则与桌面 L536 逐字一致
/// （小于被删 index 的最大现存，否则大于的最小现存）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late MessageRepository repo;

  final now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MessageRepository(db, now: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Message> seedMessage({
    String content = '原始回复',
    Role role = Role.assistant,
  }) async {
    final character = await db.into(db.characters).insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final conversation = await db.into(db.conversations).insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return db.into(db.messages).insertReturning(
          MessagesCompanion.insert(
            conversationId: conversation.id,
            role: role,
            content: content,
            createdAt: now,
          ),
        );
  }

  Future<Message> messageById(int messageId) =>
      (db.select(db.messages)
            ..where(($MessagesTable t) => t.id.equals(messageId)))
          .getSingle();

  group('addSwipe（验收 2：播种/自增/覆写 + 桌面 add_swipe 逐字）', () {
    test('首次追加：播种候选 0 = 原 content，新候选 index 1 且覆写 content/active', () async {
      final msg = await seedMessage(content: '原始回复');

      final index = await repo.addSwipe(msg.id, '重生成回复');

      // 桌面 add_swipe：max_index None → 播种候选 0（原始内容）+ next=1
      //（message.py L378-382）；make_active=True 覆写 content + active
      //（L384-387）。
      expect(index, 1);
      final swipes = await repo.listSwipes(msg.id);
      expect(swipes.map((s) => (s.index, s.content)), [
        (0, '原始回复'),
        (1, '重生成回复'),
      ]);
      final stored = await messageById(msg.id);
      expect(stored.content, '重生成回复');
      expect(stored.activeSwipeIndex, 1);
    });

    test('再次追加：index = max+1（含删中间留空档后不碰撞）', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');
      final second = await repo.addSwipe(msg.id, '候选二');
      expect(second, 2);

      // 删中间候选（index 1）留空档后追加 → index = max+1 = 3，不碰撞
      //（桌面 L382 Falsify HIGH 修复语义）。
      await repo.deleteSwipe(msg.id, 1);
      final third = await repo.addSwipe(msg.id, '候选三');
      expect(third, 3);
      final indexes = await repo.listSwipes(msg.id);
      expect(indexes.map((s) => s.index), [0, 2, 3]);
    });

    test('makeActive=false：候选追加但 content/active 不变', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '激活候选');
      final index = await repo.addSwipe(msg.id, '静默候选', makeActive: false);

      expect(index, 2);
      final stored = await messageById(msg.id);
      expect(stored.content, '激活候选');
      expect(stored.activeSwipeIndex, 1);
    });

    test('消息不存在 → MessageNotFoundError', () async {
      expect(
        () => repo.addSwipe(999999, '内容'),
        throwsA(isA<MessageNotFoundError>()),
      );
    });
  });

  group('listSwipes（验收 2/7）', () {
    test('index 升序返回；无候选消息返回空列表（既有消息零回归）', () async {
      final msg = await seedMessage();
      expect(await repo.listSwipes(msg.id), isEmpty);

      await repo.addSwipe(msg.id, '候选二');
      await repo.addSwipe(msg.id, '候选一');
      final swipes = await repo.listSwipes(msg.id);
      expect(swipes.map((s) => s.index).toList(), [0, 1, 2]);
      expect(swipes.map((s) => s.content).toList(),
          ['原始回复', '候选二', '候选一']);
    });
  });

  group('switchSwipe（验收 3：桌面契约锁 2 逐字）', () {
    test('合法切换：messages.content 覆写为选中候选 + active 更新', () async {
      final msg = await seedMessage(content: '原始回复');
      await repo.addSwipe(msg.id, '候选一');
      await repo.addSwipe(msg.id, '候选二');

      final switched = await repo.switchSwipe(msg.id, 1);

      // 桌面 switch_swipe L495-496：msg.content = swipe.content;
      // msg.active_swipe_index = index。
      expect(switched.id, msg.id);
      expect(switched.content, '候选一');
      expect(switched.activeSwipeIndex, 1);
      final stored = await messageById(msg.id);
      expect(stored.content, '候选一');
      expect(stored.activeSwipeIndex, 1);
    });

    test('切换回候选 0（原始回复）同样覆写', () async {
      final msg = await seedMessage(content: '原始回复');
      await repo.addSwipe(msg.id, '候选一');
      await repo.switchSwipe(msg.id, 0);

      final stored = await messageById(msg.id);
      expect(stored.content, '原始回复');
      expect(stored.activeSwipeIndex, 0);
    });

    test('越界 index → SwipeIndexOutOfRangeError（明确领域异常）', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');

      expect(
        () => repo.switchSwipe(msg.id, 5),
        throwsA(
          isA<SwipeIndexOutOfRangeError>().having(
            (e) => e.message,
            'message',
            contains('5'),
          ),
        ),
      );
      expect(() => repo.switchSwipe(msg.id, -1),
          throwsA(isA<SwipeIndexOutOfRangeError>()));
    });

    test('消息不存在 → MessageNotFoundError', () async {
      expect(
        () => repo.switchSwipe(999999, 0),
        throwsA(isA<MessageNotFoundError>()),
      );
    });
  });

  group('deleteSwipe（验收 4：三边界 + 回落）', () {
    test('删中间非当前候选：active/content 不变', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');
      await repo.addSwipe(msg.id, '候选二'); // active=2

      final result = await repo.deleteSwipe(msg.id, 1);

      expect(result.activeSwipeIndex, 2);
      expect(result.content, '候选二');
      expect((await repo.listSwipes(msg.id)).map((s) => s.index), [0, 2]);
    });

    test('删当前激活候选：回落到小于被删 index 的最大现存（桌面 L536）', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');
      await repo.addSwipe(msg.id, '候选二'); // active=2

      final result = await repo.deleteSwipe(msg.id, 2);

      final swipes = await repo.listSwipes(msg.id);
      expect(swipes.map((s) => s.index), [0, 1]);
      expect(result.activeSwipeIndex, 1);
      expect(result.content, '候选一');
    });

    test('删当前激活候选 0（无更小）：回落到大于的最小现存', () async {
      final msg = await seedMessage(content: '原始回复');
      await repo.addSwipe(msg.id, '候选一');
      await repo.switchSwipe(msg.id, 0); // active=0

      final result = await repo.deleteSwipe(msg.id, 0);

      final swipes = await repo.listSwipes(msg.id);
      expect(swipes.map((s) => s.index), [1]);
      expect(result.activeSwipeIndex, 1);
      expect(result.content, '候选一');
    });

    test('删当前候选含空档：回落到小于被删 index 的最大现存（空档场景）', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');
      await repo.addSwipe(msg.id, '候选二'); // [0,1,2] active=2
      await repo.deleteSwipe(msg.id, 1); // [0,2]

      final result = await repo.deleteSwipe(msg.id, 2);

      expect(result.activeSwipeIndex, 0);
      expect(result.content, '原始回复');
    });

    test('删最后一条候选：候选清空回落 0 锁定，content 保留消息本体', () async {
      final msg = await seedMessage(content: '原始回复');
      await repo.addSwipe(msg.id, '激活内容'); // [0:'原始回复', 1:'激活内容']
      await repo.deleteSwipe(msg.id, 0); // 删原始回复，active 仍 1
      await repo.deleteSwipe(msg.id, 1); // 删最后一条 → 候选清空

      expect(await repo.listSwipes(msg.id), isEmpty);
      final stored = await messageById(msg.id);
      expect(stored.activeSwipeIndex, 0, reason: '候选清空回落 0 锁定');
      expect(stored.content, '激活内容', reason: '消息本体保留最后激活内容');
    });

    test('删不存在的 index → SwipeIndexOutOfRangeError', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');

      expect(
        () => repo.deleteSwipe(msg.id, 7),
        throwsA(isA<SwipeIndexOutOfRangeError>()),
      );
    });

    test('消息不存在 → MessageNotFoundError', () async {
      expect(
        () => repo.deleteSwipe(999999, 0),
        throwsA(isA<MessageNotFoundError>()),
      );
    });
  });

  group('deleteMessage / 级联（验收 4：FK CASCADE）', () {
    test('单删消息 → 候选全部级联删除', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');
      await repo.addSwipe(msg.id, '候选二');

      final deleted = await repo.deleteMessage(msg.id);

      expect(deleted, isTrue);
      expect(await repo.listSwipes(msg.id), isEmpty);
      expect(await db.select(db.messages).get(), isEmpty);
      // 消息行真被删（不残留孤儿候选）。
      expect(
        await db.customSelect(
          'SELECT COUNT(*) AS c FROM message_swipes',
        ).getSingle().then((r) => r.data['c']),
        0,
      );
    });

    test('消息不存在 → false（零副作用）', () async {
      expect(await repo.deleteMessage(999999), isFalse);
    });

    test('deleteMessagesFrom 锚定截断 → 被删消息候选级联清除', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');

      final deleted = await repo.deleteMessagesFrom(
        (await messageById(msg.id)).conversationId,
        msg.id,
      );

      expect(deleted, 1);
      expect(await repo.listSwipes(msg.id), isEmpty);
    });
  });

  group('不变量矩阵（验收 5 / SR-27）', () {
    test('任意操作后 active 必须指向现存候选（无候选退化态视为 0）', () async {
      final msg = await seedMessage(content: '原始回复');

      // 不变量判定以桌面权威语义为准（message.py L483-489 switch_swipe 按
      // 候选行存在性校验；L536 删当前回落「小于被删 index 的最大现存，否则
      // 大于的最小现存」）：active_swipe_index 必须存在于现存候选 index
      // 集合（空集退化态 = 0）。候选 index 可稀疏（删中间留空档后回落可
      // 指向 index 2 而候选仅 1 行），故不按「active < 候选行数」字面断言
      //（spec §4.2 简化为连续无空洞场景；差异见 concerns/01.md）。
      Future<void> assertInvariant() async {
        final stored = await messageById(msg.id);
        final indexes =
            (await repo.listSwipes(msg.id)).map((s) => s.index).toSet();
        if (indexes.isEmpty) {
          expect(stored.activeSwipeIndex, 0, reason: '无候选退化态视为 0');
        } else {
          expect(indexes, contains(stored.activeSwipeIndex),
              reason: 'active 必须指向现存候选 index');
          expect(stored.activeSwipeIndex, greaterThanOrEqualTo(0));
        }
      }

      await assertInvariant();
      await repo.addSwipe(msg.id, 'A'); // [0,1] active=1
      await assertInvariant();
      await repo.addSwipe(msg.id, 'B'); // [0,1,2] active=2
      await assertInvariant();
      await repo.switchSwipe(msg.id, 0); // active=0
      await assertInvariant();
      await repo.deleteSwipe(msg.id, 1); // 非当前删中间 → [0,2] active=0
      await assertInvariant();
      await repo.deleteSwipe(msg.id, 0); // 当前删最小 → 回落 2（稀疏候选）
      await assertInvariant();
      await repo.deleteSwipe(msg.id, 2); // 当前删最后 → 候选清空回落 0
      await assertInvariant();
    });

    test('Falsify 手工越界 active_swipe_index：switchSwipe 以候选行为准修正', () async {
      final msg = await seedMessage();
      await repo.addSwipe(msg.id, '候选一');

      // 手工构造越界行（绕过仓库，模拟损坏态）：active 指向不存在的 index。
      await (db.update(db.messages)
            ..where(($MessagesTable t) => t.id.equals(msg.id)))
          .write(const MessagesCompanion(activeSwipeIndex: Value(9)));

      // 越界 active 不破坏读面（content 独立）；switchSwipe 基于候选行
      // 查询，越界 index 抛明确异常（守卫）。
      final stored = await messageById(msg.id);
      expect(stored.activeSwipeIndex, 9);
      expect(() => repo.switchSwipe(msg.id, 9),
          throwsA(isA<SwipeIndexOutOfRangeError>()));

      // 合法切换后 active 被修正为真实候选。
      final switched = await repo.switchSwipe(msg.id, 1);
      expect(switched.activeSwipeIndex, 1);
    });
  });
}
