/// 消息仓储行为契约（工单 05 验收 A1–A7 + 天然级联回归）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上运行真 schema
/// （M0 seam 复用）；语义锚点：桌面 `services/message.py`。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存假实现 — SettingsReader 的单测替身（与工单 03 测试同形）。
class FakeSettingsReader implements SettingsReader {
  const FakeSettingsReader([this.values = const {}]);

  final Map<String, String> values;

  @override
  Future<String> get defaultProvider async => values['default_provider'] ?? '';

  @override
  Future<String> get defaultModel async => values['default_model'] ?? '';

  @override
  Future<String> get userName async => values['user_name'] ?? '';

  @override
  Future<Map<String, String>> get templateVars async => const {};
}

void main() {
  late AppDatabase db;
  late ConversationRepository convRepo;
  late MessageRepository repo;

  // 固定起始时刻（秒对齐，drift 落库为 unix 秒），测试内手动拨动。
  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    convRepo = ConversationRepository(
      db,
      const FakeSettingsReader(),
      now: () => fakeNow,
    );
    repo = MessageRepository(db, now: () => fakeNow);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
  }) async {
    return db.into(db.characters).insertReturning(
          CharactersCompanion.insert(
            name: name,
            firstMes: Value(firstMes),
            createdAt: fakeNow,
            updatedAt: fakeNow,
          ),
        );
  }

  /// 无开场白对话（标题为占位默认值，便于驱动自动命名判定）。
  Future<Conversation> seedConversation(int characterId) {
    return convRepo.createConversation(characterId: characterId);
  }

  Future<Conversation> conversationOf(int conversationId) {
    return (db.select(db.conversations)
          ..where(($ConversationsTable t) => t.id.equals(conversationId)))
        .getSingle();
  }

  /// 原始 select（无排序）读库内消息行——库状态断言用，
  /// 排序语义由 [MessageRepository.getMessages] 单独锚定。
  Future<List<Message>> messagesOf(int conversationId) {
    return (db.select(db.messages)
          ..where(($MessagesTable t) => t.conversationId.equals(conversationId)))
        .get();
  }

  Future<Message> sendUserMessage(
    int conversationId,
    String content,
  ) {
    return repo.createMessage(
      conversationId: conversationId,
      role: Role.user,
      content: content,
    );
  }

  group('createMessage 副作用（A1 前移 + A7 时间戳仓储赋值）', () {
    test('A1: 落库前移所属对话 updated_at；消息时间戳由仓储层赋值', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      expect(conv.updatedAt, conv.createdAt); // 无开场白：创建时刻即更新时刻

      fakeNow = fakeNow.add(const Duration(seconds: 5));
      final msg = await sendUserMessage(conv.id, '你好');

      expect(msg.conversationId, conv.id);
      expect(msg.role, Role.user);
      expect(msg.content, '你好');
      expect(msg.createdAt, fakeNow); // 注入时钟值，非墙钟（1700000005）

      final after = await conversationOf(conv.id);
      expect(after.updatedAt, fakeNow);
      expect(after.updatedAt.isAfter(conv.createdAt), isTrue);
    });

    test('对话不存在 → FK ON 下插入被拒绝，不产生任何消息行', () async {
      await expectLater(
        repo.createMessage(conversationId: 999999, role: Role.user, content: 'x'),
        throwsA(anything),
      );
      expect(await db.select(db.messages).get(), isEmpty);
    });
  });

  group('自动命名（A2 截断规则 / A3 两态不覆盖 / A7 角色判定）', () {
    test('A2: 首条 user 消息 → 占位标题替换为 ≤20 字原样', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      expect(conv.title, '与 艾莉亚 的对话');

      await sendUserMessage(conv.id, '一段不足二十字的留言');

      final after = await conversationOf(conv.id);
      expect(after.title, '一段不足二十字的留言');
    });

    test('A2: 超 20 字 → 取前 20 字加「…」', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      await sendUserMessage(conv.id, '一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子');

      final after = await conversationOf(conv.id);
      expect(after.title, '一二三四五六七八九十甲乙丙丁戊己庚辛壬癸…');
    });

    test('A2: 20 字整 → 原样不加省略号（边界）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      await sendUserMessage(conv.id, '一二三四五六七八九十甲乙丙丁戊己庚辛壬癸');

      final after = await conversationOf(conv.id);
      expect(after.title, '一二三四五六七八九十甲乙丙丁戊己庚辛壬癸');
    });

    test('A2: 折叠空白为单空格并去首尾', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      await sendUserMessage(conv.id, '  你好，   世界\t！\n 修剪  ');

      final after = await conversationOf(conv.id);
      expect(after.title, '你好， 世界 ！ 修剪');
    });

    test('A2: 不剥 Markdown，语法字符原样保留', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      await sendUserMessage(conv.id, '**加粗** 和 `代码` 片段一起超出二十个字');

      final after = await conversationOf(conv.id);
      expect(after.title, '**加粗** 和 `代码` 片段一起超出…');
    });

    test('A2: 长度按 Unicode 码点计（emoji 不在截断点被劈开）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      await sendUserMessage(conv.id, '😀' * 25);

      final after = await conversationOf(conv.id);
      expect(after.title, '😀' * 20 + '…');
    });

    test('有开场白（assistant）时首条 user 消息仍触发命名（查在插入前的时序锚）',
        () async {
      final char = await seedCharacter(name: '艾莉亚', firstMes: '欢迎，冒险者。');
      final conv = await seedConversation(char.id);
      expect(await messagesOf(conv.id), hasLength(1)); // 仅 assistant 开场白
      expect(conv.title, '与 艾莉亚 的对话');

      await sendUserMessage(conv.id, '我来了');

      final after = await conversationOf(conv.id);
      expect(after.title, '我来了');
    });

    test('A3: 已有 user 消息后再发 → 标题保持首条结果不被覆盖', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      await sendUserMessage(conv.id, '第一条消息标题');
      await sendUserMessage(conv.id, '完全不同的第二条消息内容');

      final after = await conversationOf(conv.id);
      expect(after.title, '第一条消息标题');
    });

    test('A3: 标题已被显式命名（≠占位值）→ 不覆盖', () async {
      final char = await seedCharacter();
      final conv = await convRepo.createConversation(
        characterId: char.id,
        title: '我的冒险',
      );

      await sendUserMessage(conv.id, '首条用户消息内容');

      final after = await conversationOf(conv.id);
      expect(after.title, '我的冒险');
    });

    test('user 消息 content 为空 → 不触发命名（桌面 not content 守卫），前移照常',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final msg = await sendUserMessage(conv.id, '');

      final after = await conversationOf(conv.id);
      expect(after.title, '与 艾莉亚 的对话'); // 标题不动
      expect(after.updatedAt, msg.createdAt); // 前移副作用照常
    });

    test('A7: assistant / system 消息不触发命名判定', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      await repo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '助手内容很长很长很长很长很长很长很长很长很长很长很长很长很长很长',
      );
      await repo.createMessage(
        conversationId: conv.id,
        role: Role.system,
        content: '系统指令内容很长很长很长很长很长很长很长很长很长很长很长很长很长很长',
      );

      var after = await conversationOf(conv.id);
      expect(after.title, '与 艾莉亚 的对话'); // 两种角色都不触发

      await sendUserMessage(conv.id, '此刻才轮到 user');
      after = await conversationOf(conv.id);
      expect(after.title, '此刻才轮到 user');
    });

    test('占位比对按当前角色名计算（桌面 default_conversation_title 实况）', () async {
      final char = await seedCharacter(name: '旧名');
      final conv = await seedConversation(char.id);

      // 角色改名：历史占位标题「与 旧名 的对话」≠ 当前占位「与 新名 的对话」
      // → 按桌面语义视作显式命名，不覆盖。
      await (db.update(db.characters)
            ..where(($CharactersTable t) => t.id.equals(char.id)))
          .write(const CharactersCompanion(name: Value('新名')));

      await sendUserMessage(conv.id, '触发判定的首条消息');

      final after = await conversationOf(conv.id);
      expect(after.title, '与 旧名 的对话');
    });
  });

  group('getMessages（A4 排序语义）', () {
    test('A4: created_at 正序，同秒以 id 兜底', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      // 先插时间更晚的（id 更小），再插两条同秒更早的（id 更大）——
      // 同时锚定 created_at asc 的主导性与同秒 id 兜底。
      fakeNow = fakeNow.add(const Duration(seconds: 10));
      final m1 = await sendUserMessage(conv.id, 'later');
      fakeNow = fakeNow.add(const Duration(seconds: -5));
      final m2 = await sendUserMessage(conv.id, 'early-a');
      final m3 = await sendUserMessage(conv.id, 'early-b');

      expect(m1.createdAt.isAfter(m2.createdAt), isTrue);
      expect(m2.createdAt, m3.createdAt); // 同秒

      final listed = await repo.getMessages(conv.id);
      expect(listed.map((m) => m.id), [m2.id, m3.id, m1.id]);
    });

    test('无消息 → 空列表', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      expect(await repo.getMessages(conv.id), isEmpty);
    });
  });

  group('recentMessages（C3 定位读：等价 (createdAt asc, id asc) 取尾 N）', () {
    test('等价 getMessages 升序序取尾 N（时间主导 + 同秒 id 兜底）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      fakeNow = fakeNow.add(const Duration(seconds: 10));
      final m1 = await sendUserMessage(conv.id, 'later');
      fakeNow = fakeNow.add(const Duration(seconds: -5));
      final m2 = await sendUserMessage(conv.id, 'early-a');
      final m3 = await sendUserMessage(conv.id, 'early-b');
      // getMessages 升序：[m2(早), m3(同秒 id 兜底), m1(晚)]。
      expect(m2.createdAt, m3.createdAt);
      final full = await repo.getMessages(conv.id);
      expect(full.map((m) => m.id), [m2.id, m3.id, m1.id]);

      final recent2 = await repo.recentMessages(conv.id, 2);
      expect(
        recent2.map((m) => m.id),
        [m3.id, m1.id],
        reason: 'asc 序取尾 2 = [m3, m1]',
      );
      expect(recent2.first.createdAt.isBefore(recent2.last.createdAt), isTrue,
          reason: '返回保持升序');

      // 与 getMessages 尾 N 逐条等价的 oracle 断言（非自证：以 getMessages 为锚）。
      for (final requested in [1, 2, 3, 5]) {
        final k = requested > full.length ? full.length : requested;
        final expected = full.skip(full.length - k);
        final got = await repo.recentMessages(conv.id, requested);
        expect(got.map((m) => m.id), expected.map((m) => m.id),
            reason: 'requested=$requested');
      }
    });

    test('同秒多条 → id asc 兜底取尾（不依赖插入顺序）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      // 不拨动 fakeNow：三条同秒，升序靠 id 兜底。
      final m1 = await sendUserMessage(conv.id, 'a');
      final m2 = await sendUserMessage(conv.id, 'b');
      final m3 = await sendUserMessage(conv.id, 'c');
      expect(m1.id < m2.id && m2.id < m3.id, isTrue,
          reason: '同秒窗口判定依赖 id 兜底，锚定 id 递增');

      final recent = await repo.recentMessages(conv.id, 2);
      expect(recent.map((m) => m.id), [m2.id, m3.id], reason: '尾 2 = m2, m3');
    });

    test('limit ≥ 条数 → 全量升序；limit < 条数 → 截尾', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final m1 = await sendUserMessage(conv.id, 'a');
      final m2 = await sendUserMessage(conv.id, 'b');
      final m3 = await sendUserMessage(conv.id, 'c');

      final all = await repo.recentMessages(conv.id, 10);
      expect(all.map((m) => m.id), [m1.id, m2.id, m3.id],
          reason: 'limit 超量 → 全量升序');
      final tail1 = await repo.recentMessages(conv.id, 1);
      expect(tail1.map((m) => m.id), [m3.id], reason: 'limit=1 → 仅末条');
    });

    test('空会话 → 空列表', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      expect(await repo.recentMessages(conv.id, 20), isEmpty);
    });

    test('limit ≤ 0 → 空列表（防 SQLite LIMIT 负数即无限制的隐式全量）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, 'a');
      expect(await repo.recentMessages(conv.id, 0), isEmpty);
      expect(await repo.recentMessages(conv.id, -1), isEmpty);
    });

    test('跨对话隔离：他对话消息不串入', () async {
      final char = await seedCharacter();
      final convA = await seedConversation(char.id);
      final convB = await seedConversation(char.id);
      final a1 = await sendUserMessage(convA.id, '甲的 a');
      final a2 = await sendUserMessage(convA.id, '甲的 b');
      final b1 = await sendUserMessage(convB.id, '乙的 a');

      expect((await repo.recentMessages(convA.id, 10)).map((m) => m.id),
          [a1.id, a2.id]);
      expect((await repo.recentMessages(convA.id, 1)).single.id, a2.id);
      expect((await repo.recentMessages(convB.id, 10)).single.id, b1.id,
          reason: '他对话消息不串入');
    });
  });

  group('messageStats（C3 决策面定位读聚含）', () {
    test('混合角色：total / userCount / chars 精确', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      // 内容为 BMP 字符串：SQLite LENGTH 计码点 == Dart String.length。
      await repo.createMessage(
          conversationId: conv.id, role: Role.user, content: '你好ABC'); // 5
      await repo.createMessage(
          conversationId: conv.id, role: Role.assistant, content: '回复123'); // 5
      await repo.createMessage(
          conversationId: conv.id, role: Role.user, content: '结尾'); // 2

      final stats = await repo.messageStats(conv.id);
      expect(stats.total, 3);
      expect(stats.userCount, 2);
      expect(stats.chars, 12, reason: '5 + 5 + 2');
    });

    test('空会话 → (0, 0, 0)', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      expect(await repo.messageStats(conv.id), (total: 0, userCount: 0, chars: 0));
    });

    test('跨对话隔离 + system 角色不计 userCount', () async {
      final char = await seedCharacter();
      final convA = await seedConversation(char.id);
      final convB = await seedConversation(char.id);
      await repo.createMessage(
          conversationId: convA.id, role: Role.user, content: 'A用户');
      await repo.createMessage(
          conversationId: convA.id, role: Role.system, content: 'A系统');
      await repo.createMessage(
          conversationId: convB.id, role: Role.user, content: 'B');

      final stats = await repo.messageStats(convA.id);
      expect(stats.total, 2);
      expect(stats.userCount, 1, reason: 'system 消息不计 user');
      expect(await repo.messageStats(convB.id), (total: 1, userCount: 1, chars: 1));
    });
  });

  group('latestMessageAt（F-81 判定⑨单源）', () {
    test('跨多对话取全局 max：最新 createdAt 胜出，他角色不影响', () async {
      final charA = await seedCharacter();
      final charB = await seedCharacter(name: '孤立者');
      final convA1 = await seedConversation(charA.id);
      final convA2 = await seedConversation(charA.id);
      final convB = await seedConversation(charB.id);

      // 乱序插入（先较新后较旧）：同 createdAt 集合，断言与插入顺序无关。
      final newer = fakeNow.subtract(const Duration(hours: 1));
      final older = fakeNow.subtract(const Duration(days: 3));
      final otherNewer = fakeNow.subtract(const Duration(minutes: 10));
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: convA2.id,
              role: Role.assistant,
              content: '较新',
              createdAt: newer,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: convA1.id,
              role: Role.user,
              content: '较旧',
              createdAt: older,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: convB.id,
              role: Role.assistant,
              content: '他角色更近',
              createdAt: otherNewer,
            ),
          );

      expect(await repo.latestMessageAt(charA.id), newer);
      expect(await repo.latestMessageAt(charB.id), otherNewer);
    });

    test('单对话：全局 max = 该对话内最新 createdAt（乱序插入）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final t1 = fakeNow.subtract(const Duration(days: 2));
      final t2 = fakeNow.subtract(const Duration(days: 1));
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: conv.id,
              role: Role.user,
              content: '较新',
              createdAt: t2,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: conv.id,
              role: Role.assistant,
              content: '较旧后插',
              createdAt: t1,
            ),
          );

      expect(await repo.latestMessageAt(char.id), t2);
    });

    test('无消息 → null（有对话无消息 / 无对话角色）', () async {
      final char = await seedCharacter();
      await seedConversation(char.id);
      expect(await repo.latestMessageAt(char.id), isNull);

      final lonely = await seedCharacter(name: '无对话者');
      expect(await repo.latestMessageAt(lonely.id), isNull);
    });
  });

  group('deleteMessagesFrom（A5 锚定截断 + A6 边界与零副作用）', () {
    test('A5: 删除 id≥target（含）全部消息并返回条数；不前移 conv.updated_at',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final m1 = await sendUserMessage(conv.id, 'a');
      final m2 = await sendUserMessage(conv.id, 'b');
      final m3 = await sendUserMessage(conv.id, 'c');
      await sendUserMessage(conv.id, 'd');
      final before = await conversationOf(conv.id);

      final deleted = await repo.deleteMessagesFrom(conv.id, m3.id);

      expect(deleted, 2);
      expect(
        (await messagesOf(conv.id)).map((m) => m.id),
        [m1.id, m2.id],
      );

      final after = await conversationOf(conv.id);
      expect(after.updatedAt, before.updatedAt); // 不前移
      expect(after, before); // 对话行零变化
    });

    test('A6: 截点在首条 → 全删清空', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final m1 = await sendUserMessage(conv.id, 'a');
      await sendUserMessage(conv.id, 'b');
      await sendUserMessage(conv.id, 'c');

      final deleted = await repo.deleteMessagesFrom(conv.id, m1.id);

      expect(deleted, 3);
      expect(await messagesOf(conv.id), isEmpty);
    });

    test('A6: 越界 target（无消息满足）→ 返回 0 且零副作用', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, 'a');
      await sendUserMessage(conv.id, 'b');
      final before = await conversationOf(conv.id);

      final deleted = await repo.deleteMessagesFrom(conv.id, 999999);

      expect(deleted, 0);
      expect(await messagesOf(conv.id), hasLength(2));
      expect(await conversationOf(conv.id), before); // 行零变化
    });

    test('跨对话隔离：截断仅作用于指定对话', () async {
      final char = await seedCharacter();
      final convA = await seedConversation(char.id);
      final convB = await seedConversation(char.id);
      await sendUserMessage(convA.id, 'a1');
      final m2a = await sendUserMessage(convA.id, 'a2');
      final b1 = await sendUserMessage(convB.id, 'b1');
      final b2 = await sendUserMessage(convB.id, 'b2');

      final deleted = await repo.deleteMessagesFrom(convA.id, m2a.id);

      expect(deleted, 1);
      expect((await messagesOf(convA.id)).map((m) => m.content), ['a1']);
      expect((await messagesOf(convB.id)).map((m) => m.id), [b1.id, b2.id]);
    });
  });

  group('天然级联回归（M0 外键 CASCADE，零显式级联代码）', () {
    test('删角色 → 对话与消息经外键 CASCADE 一并消失', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '将随级联消失');
      expect(await db.select(db.messages).get(), hasLength(1));

      await (db.delete(db.characters)
            ..where(($CharactersTable t) => t.id.equals(char.id)))
          .go();

      expect(await db.select(db.conversations).get(), isEmpty);
      expect(await db.select(db.messages).get(), isEmpty);
    });

    test('删对话 → 其消息随之消失（消息侧回归），其他对话不受影响', () async {
      final char = await seedCharacter();
      final convA = await seedConversation(char.id);
      final convB = await seedConversation(char.id);
      await sendUserMessage(convA.id, 'a1');
      await sendUserMessage(convB.id, 'b1');

      expect(await convRepo.deleteConversation(convA.id), isTrue);
      expect(await messagesOf(convA.id), isEmpty);
      expect(await messagesOf(convB.id), hasLength(1));
    });
  });

  group('searchMessages（M3-04a 跨对话 content 模糊检索）', () {
    /// 带头像的角色种子（join 上下文断言用；既有 seedCharacter 无头像参数）。
    Future<Character> seedCharacterWithAvatar({
      String name = '星野',
      String avatar = 'data:image/png;base64,abc',
    }) {
      return db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: name,
              avatar: Value(avatar),
              createdAt: fakeNow,
              updatedAt: fakeNow,
            ),
          );
    }

    test('命中 content + join 上下文（角色/对话标题/头像/role）', () async {
      final char = await seedCharacterWithAvatar(name: '星野');
      final conv = await convRepo.createConversation(
        characterId: char.id,
        title: '夜话',
      );
      final msg = await sendUserMessage(conv.id, '今晚的星空很美');

      final hits = await repo.searchMessages('星空');

      expect(hits, hasLength(1));
      final hit = hits.single;
      expect(hit.message.id, msg.id);
      expect(hit.message.conversationId, conv.id);
      expect(hit.message.role, Role.user);
      expect(hit.message.content, '今晚的星空很美');
      expect(hit.message.createdAt, msg.createdAt);
      expect(hit.conversation.title, '夜话');
      expect(hit.character.id, char.id);
      expect(hit.character.name, '星野');
      expect(hit.character.avatar, 'data:image/png;base64,abc');
    });

    test('负例：角色名/对话标题命中不返回（仅 content 检索，对齐桌面）', () async {
      final char = await seedCharacter(name: '风语者');
      final conv = await convRepo.createConversation(
        characterId: char.id,
        title: '机密会议',
      );
      await sendUserMessage(conv.id, '今天天气不错');

      expect(await repo.searchMessages('风语者'), isEmpty);
      expect(await repo.searchMessages('机密'), isEmpty);
    });

    test('负例：开场白 first_mes 不直接命中（角色列非检索范围）', () async {
      // 「引导者」带开场白但不为其建对话 → 开场白不作为消息内容落库。
      await seedCharacter(name: '引导者', firstMes: '欢迎来到冒险世界');
      final other = await seedCharacter(name: '路人');
      final conv = await seedConversation(other.id);
      await sendUserMessage(conv.id, '闲聊内容');

      expect(await repo.searchMessages('欢迎来到冒险世界'), isEmpty);
    });

    test('中文子串命中 + 英文大小写不敏感命中（SQLite LIKE 语义）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '今天天气不错');
      await sendUserMessage(conv.id, 'Hello World');

      expect(await repo.searchMessages('天气'), hasLength(1));
      expect(await repo.searchMessages('hello'), hasLength(1));
      expect(await repo.searchMessages('HELLO'), hasLength(1));
    });

    test('排序：createdAt 倒序 + 同秒 id 倒序兜底', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      fakeNow = fakeNow.add(const Duration(seconds: 10));
      final m1 = await sendUserMessage(conv.id, '关键词 alpha'); // t=+10, id 较小
      fakeNow = fakeNow.add(const Duration(seconds: -5)); // 回到 t=+5
      final m2 = await sendUserMessage(conv.id, '关键词 beta'); // t=+5, id 较小
      final m3 = await sendUserMessage(conv.id, '关键词 gamma'); // t=+5, id 较大

      final hits = await repo.searchMessages('关键词');

      expect(hits.map((h) => h.message.id), [m1.id, m3.id, m2.id]);
    });

    test('limit 默认 50 截断（>50 条命中只回 50）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      for (var i = 0; i < 55; i++) {
        await sendUserMessage(conv.id, '批量命中 $i');
      }

      final hits = await repo.searchMessages('批量');

      expect(hits, hasLength(50));
    });

    test('空串/纯空白 → 空列表（不抛错、零查询）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '有点内容');

      expect(await repo.searchMessages(''), isEmpty);
      expect(await repo.searchMessages('   '), isEmpty);
    });
  });

  group('语义化定位读（S6）', () {
    Future<Message> send(int conversationId, Role role, String content) {
      return repo.createMessage(
        conversationId: conversationId,
        role: role,
        content: content,
      );
    }

    test('lastAssistantMessage: 无消息 / 仅 user → null', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      expect(await repo.lastAssistantMessage(conv.id), isNull);

      await sendUserMessage(conv.id, '只有用户消息');
      expect(await repo.lastAssistantMessage(conv.id), isNull);
    });

    test('lastAssistantMessage: 末条 assistant（createdAt DESC 优先，user 不干扰）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await send(conv.id, Role.assistant, '开场');
      await sendUserMessage(conv.id, '第一问');
      final first = await send(conv.id, Role.assistant, '第一答');
      fakeNow = fakeNow.add(const Duration(seconds: 5));
      await sendUserMessage(conv.id, '第二问');
      final second = await send(conv.id, Role.assistant, '第二答');

      final last = await repo.lastAssistantMessage(conv.id);

      expect(last, isNotNull);
      expect(last!.id, second.id);
      expect(last.content, '第二答');
      expect(first.id, isNot(second.id), reason: '两条 assistant 均已落库');
    });

    test('lastAssistantMessage: 同秒两条 assistant → id 大者胜（id DESC 兜底）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      // 不拨动 fakeNow：三条同秒，判定只能靠 id 兜底。
      await send(conv.id, Role.assistant, '开场');
      await send(conv.id, Role.assistant, '旧答');
      final last = await send(conv.id, Role.assistant, '末答');

      final got = await repo.lastAssistantMessage(conv.id);

      expect(got!.id, last.id, reason: '同秒末条 = id 最大者');
    });

    test('lastUserMessageBefore: beforeId 前无 user（无 user / 全部晚于）→ null',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await send(conv.id, Role.assistant, '开场');

      // 仅 assistant → null。
      expect(
        await repo.lastUserMessageBefore(conv.id, 999999),
        isNull,
      );

      await sendUserMessage(conv.id, '你好');
      final reply = await send(conv.id, Role.assistant, '回复');
      // beforeId 指向最早 user 自身 → 其前无 user → null（id < beforeId 开区间）。
      expect(await repo.lastUserMessageBefore(conv.id, reply.id), isNotNull);
    });

    test('lastUserMessageBefore: 取 id < beforeId 的最近一条 user（role 过滤）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final u1 = await sendUserMessage(conv.id, '第一问');
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      final a1 = await send(conv.id, Role.assistant, '第一答');
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      final u2 = await sendUserMessage(conv.id, '第二问');
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      final a2 = await send(conv.id, Role.assistant, '第二答');

      expect((await repo.lastUserMessageBefore(conv.id, a2.id))!.id, u2.id);
      expect((await repo.lastUserMessageBefore(conv.id, a1.id))!.id, u1.id);
    });

    test('lastUserMessageBefore: 同秒多条 → id 大者胜（与 _lastUserBefore 逐位等价）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      // 不拨动 fakeNow：u1/u2 同秒，beforeId 前最近 user 靠 id 兜底。
      final u1 = await sendUserMessage(conv.id, '第一问');
      final a1 = await send(conv.id, Role.assistant, '第一答');
      final u2 = await sendUserMessage(conv.id, '第二问');
      final a2 = await send(conv.id, Role.assistant, '第二答');

      final got = await repo.lastUserMessageBefore(conv.id, a2.id);

      expect(got!.id, u2.id, reason: '同秒取 id 最大者');
      expect(u1.id, isNot(u2.id));
      expect(a1.id, isNot(a2.id));
    });

    test('messagesBefore: id < beforeId 开区间正序（与 getMessages 同序）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final m1 = await sendUserMessage(conv.id, 'm1');
      fakeNow = fakeNow.add(const Duration(seconds: 10));
      final m2 = await sendUserMessage(conv.id, 'm2');
      fakeNow = fakeNow.add(const Duration(seconds: -5)); // 回到较早时刻
      final m3 = await sendUserMessage(conv.id, 'm3');
      fakeNow = fakeNow.add(const Duration(seconds: 20));
      final m4 = await sendUserMessage(conv.id, 'm4');

      final before = await repo.messagesBefore(conv.id, m4.id);

      expect(before.map((m) => m.id), [m1.id, m3.id, m2.id],
          reason: 'createdAt ASC（m3 早于 m2）+ id ASC 兜底');
      // 与 getMessages 过滤同序：全量正序取 id < beforeId 逐条一致。
      final full = await repo.getMessages(conv.id);
      expect(
        before.map((m) => m.id),
        full.where((m) => m.id < m4.id).map((m) => m.id),
        reason: '与 getMessages 同序',
      );
    });

    test('messagesBefore: beforeId 小于全部 → 空列表', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final first = await sendUserMessage(conv.id, '最早');

      expect(await repo.messagesBefore(conv.id, first.id), isEmpty);
    });

    test('messageById: 本对话命中', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final u = await sendUserMessage(conv.id, '你好');
      await send(conv.id, Role.assistant, '回复');

      final got = await repo.messageById(conv.id, u.id);

      expect(got, isNotNull);
      expect(got!.id, u.id);
      expect(got.role, Role.user);
    });

    test('messageById: 跨对话同 id → null（对话归属校验）', () async {
      final charA = await seedCharacter(name: '甲');
      final charB = await seedCharacter(name: '乙');
      final convA = await seedConversation(charA.id);
      final convB = await seedConversation(charB.id);
      final inA = await sendUserMessage(convA.id, '甲的消息');
      final inB = await sendUserMessage(convB.id, '乙的消息');

      expect((await repo.messageById(convB.id, inA.id)), isNull,
          reason: 'id 属于另一对话 → 归属校验拒绝');
      expect((await repo.messageById(convA.id, inB.id)), isNull);
    });

    test('messageById: 不存在 id → null', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '有一条');

      expect(await repo.messageById(conv.id, 999999), isNull);
    });

    test('lastMessage: 末条 = createdAt DESC, id DESC（同秒 id 兜底）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final u1 = await sendUserMessage(conv.id, '第一问');
      final a1 = await send(conv.id, Role.assistant, '第一答');
      // 同秒：a1 之后同秒插入 u2 → 末条 = u2（id 兜底）。
      final u2 = await sendUserMessage(conv.id, '第二问');

      final last = await repo.lastMessage(conv.id);

      expect(last!.id, u2.id, reason: '同秒末条 = id 最大者');
      expect(last.role, Role.user);
      expect(u1.id, isNot(a1.id));
    });

    test('lastMessage: 无消息 → null；跨对话隔离', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final other = await seedConversation(char.id);

      expect(await repo.lastMessage(conv.id), isNull);

      await sendUserMessage(other.id, '另一对话有消息');
      expect(await repo.lastMessage(conv.id), isNull,
          reason: '他对话消息不串入');
      expect(await repo.lastMessage(other.id), isNotNull);
    });
  });

  group('replaceAndTruncateFollowing（MS-03 编辑重发数据原语）', () {
    test('成功 → 就地替换 content + 物理截断后续（id > messageId）'
        '单事务原子，返回截断条数', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final u1 = await sendUserMessage(conv.id, '第一问');
      await repo.createMessage(
          conversationId: conv.id, role: Role.assistant, content: '第一答');
      await sendUserMessage(conv.id, '第二问');
      final a2 = await repo.createMessage(
          conversationId: conv.id, role: Role.assistant, content: '第二答');
      // 被截断消息带候选（FK CASCADE 承保：删消息级联删候选）。
      await repo.addSwipe(a2.id, '二候选', makeActive: false);

      final deleted = await repo.replaceAndTruncateFollowing(
        conversationId: conv.id,
        messageId: u1.id,
        content: '修正后的问题',
      );

      expect(deleted, 3, reason: '截断 id > u1.id 的 3 条（第一答/第二问/第二答）');
      final msgs = await repo.getMessages(conv.id);
      expect([for (final m in msgs) m.content], ['修正后的问题']);
      expect(msgs.single.role, Role.user, reason: '替换只触碰 content，role 不变');
      expect(await repo.listSwipes(a2.id), isEmpty,
          reason: '被截断消息候选随 FK CASCADE 级联删');
    });

    test('消息不存在 → MessageNotFoundError（零副作用，强校验）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '有一条');

      await expectLater(
        repo.replaceAndTruncateFollowing(
          conversationId: conv.id,
          messageId: 999999,
          content: '改',
        ),
        throwsA(isA<MessageNotFoundError>()),
      );
      expect(await repo.getMessages(conv.id), hasLength(1));
    });
  });
}
