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
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存假实现 — SettingsReader 的单测替身（与工单 03 测试同形）。
class FakeSettingsReader implements SettingsReader {
  const FakeSettingsReader([this.values = const {}]);

  final Map<String, String> values;

  @override
  Future<String> defaultProvider() async => values['default_provider'] ?? '';

  @override
  Future<String> defaultModel() async => values['default_model'] ?? '';

  @override
  Future<String> userName() async => values['user_name'] ?? '';
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
}
