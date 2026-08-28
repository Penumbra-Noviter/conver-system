/// 对话仓储行为契约（工单 03 验收 A1/A3/A4/A6/A7 的对话面）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上运行真 schema
/// （M0 seam 复用）；语义锚点：桌面 `services/conversation.py`。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存假实现 — SettingsReader 的单测替身（键名镜像桌面设置键）。
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
  late ConversationRepository repo;

  // 固定起始时刻（秒对齐，drift 落库为 unix 秒），测试内手动前拨。
  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
  void advanceSeconds(int seconds) {
    fakeNow = fakeNow.add(Duration(seconds: seconds));
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ConversationRepository(db, FakeSettingsReader(), now: () => fakeNow);
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

  Future<List<Message>> messagesOf(int conversationId) {
    return (db.select(db.messages)
          ..where(($MessagesTable t) => t.conversationId.equals(conversationId)))
        .get();
  }

  group('listConversations（A3 排序 + message_count + 过滤）', () {
    test('按 updated_at 倒序、message_count 正确、按 characterId 过滤', () async {
      final charA = await seedCharacter(name: '甲');
      final charB = await seedCharacter(name: '乙');

      final convA1 = await repo.createConversation(characterId: charA.id);
      advanceSeconds(5);
      final convB1 = await repo.createConversation(characterId: charB.id);
      advanceSeconds(5);
      final convA2 = await repo.createConversation(characterId: charA.id);

      await seedMessage(convA1.id);
      await seedMessage(convA1.id);
      await seedMessage(convA2.id, role: Role.assistant);

      final all = await repo.listConversations();
      expect(all.map((row) => row.conversation.id), [convA2.id, convB1.id, convA1.id]);
      expect(all.map((row) => row.messageCount), [1, 0, 2]);

      final filtered = await repo.listConversations(characterId: charA.id);
      expect(filtered.map((row) => row.conversation.id), [convA2.id, convA1.id]);
      expect(filtered.map((row) => row.messageCount), [1, 2]);

      final empty = await repo.listConversations(characterId: 999999);
      expect(empty, isEmpty);
    });
  });

  group('createConversation（A4 标题占位 / provider-model 回退 / 预插开场白）', () {
    test('无显式 title 落占位「与 {角色名} 的对话」；显式 title 优先', () async {
      final char = await seedCharacter(name: '艾莉亚');

      final conv = await repo.createConversation(characterId: char.id);
      expect(conv.title, '与 艾莉亚 的对话');

      final named = await repo.createConversation(
        characterId: char.id,
        title: '我的冒险',
      );
      expect(named.title, '我的冒险');
    });

    test('角色名称为空 → 占位「与 角色 的对话」', () async {
      final char = await seedCharacter(name: '');
      final conv = await repo.createConversation(characterId: char.id);
      expect(conv.title, '与 角色 的对话');
    });

    test('provider/model：显式值（非空）优先，否则落 SettingsReader 值', () async {
      final char = await seedCharacter();
      final withSettings = ConversationRepository(
        db,
        FakeSettingsReader({
          'default_provider': 'deepseek',
          'default_model': 'kimi-k2',
        }),
        now: () => fakeNow,
      );

      final defaulted = await withSettings.createConversation(characterId: char.id);
      expect(defaulted.modelProvider, 'deepseek');
      expect(defaulted.modelName, 'kimi-k2');

      final overridden = await withSettings.createConversation(
        characterId: char.id,
        modelProvider: 'claude',
        modelName: 'claude-opus-4',
      );
      expect(overridden.modelProvider, 'claude');
      expect(overridden.modelName, 'claude-opus-4');

      // 显式空串视同未提供 → 回退设置值。
      final explicitEmpty = await withSettings.createConversation(
        characterId: char.id,
        modelProvider: '',
      );
      expect(explicitEmpty.modelProvider, 'deepseek');
    });

    test('设置缺失或空串 → 回退常量 claude / claude-sonnet-5', () async {
      final char = await seedCharacter();
      final conv = await repo.createConversation(characterId: char.id);
      expect(conv.modelProvider, 'claude');
      expect(conv.modelName, 'claude-sonnet-5');
    });

    test('角色有 first_mes → 预插 assistant 开场白且 {{user}}/{{char}} 已替换',
        () async {
      final char = await seedCharacter(
        name: '艾莉亚',
        firstMes: '你好，{{user}}！我是{{char}}。',
      );
      // 步进时钟：对话创建与开场白落库各取一秒，模拟桌面 datetime.now 的
      // 先后序（对话 T，开场白 T+ε → updated_at 前移至开场白时刻）。
      var tick = fakeNow;
      final steppingRepo = ConversationRepository(
        db,
        const FakeSettingsReader({'user_name': '阿明'}),
        now: () {
          final current = tick;
          tick = tick.add(const Duration(seconds: 1));
          return current;
        },
      );

      final conv = await steppingRepo.createConversation(characterId: char.id);

      final messages = await messagesOf(conv.id);
      expect(messages, hasLength(1));
      expect(messages.single.role, Role.assistant);
      expect(messages.single.content, '你好，阿明！我是艾莉亚。');
      // 桌面 create_message 副作用：开场白落库前移对话 updated_at。
      expect(conv.updatedAt.isAfter(conv.createdAt), isTrue);
      expect(conv.updatedAt, messages.single.createdAt);
    });

    test('user_name 未配置 → 开场白 {{user}} 兜底 User', () async {
      final char = await seedCharacter(name: '诺克斯', firstMes: '嗨，{{user}}。');
      final conv = await repo.createConversation(characterId: char.id);
      expect((await messagesOf(conv.id)).single.content, '嗨，User。');
    });

    test('角色无 first_mes → 不预插消息（message_count 0）', () async {
      final char = await seedCharacter(name: '无名');
      final conv = await repo.createConversation(characterId: char.id);
      final listed = await repo.listConversations(characterId: char.id);
      expect(listed.single.messageCount, 0);
      expect(await messagesOf(conv.id), isEmpty);
    });
  });

  group('updateConversation（A6 部分更新）', () {
    test('仅显式字段变更且 updated_at 前移', () async {
      final char = await seedCharacter();
      final conv = await repo.createConversation(characterId: char.id);
      final before = conv.updatedAt;
      final originalProvider = conv.modelProvider;

      advanceSeconds(10);
      final updated = await repo.updateConversation(
        conv.id,
        const ConversationsCompanion(title: Value('改名')),
      );

      expect(updated, isNotNull);
      expect(updated!.title, '改名');
      expect(updated.modelProvider, originalProvider); // 未显式提供的字段不变
      expect(updated.updatedAt.isAfter(before), isTrue);
    });

    test('对话不存在 → null；无显式字段 → 原行返回', () async {
      expect(
        await repo.updateConversation(
          999999,
          const ConversationsCompanion(title: Value('x')),
        ),
        isNull,
      );

      final char = await seedCharacter();
      final conv = await repo.createConversation(characterId: char.id);
      final result = await repo.updateConversation(
        conv.id,
        const ConversationsCompanion(),
      );
      expect(result!.id, conv.id);
      expect(result.updatedAt, conv.updatedAt);
    });
  });

  group('deleteConversation / deleteAllConversations（A7 两态 + A1 级联）', () {
    test('删单对话 → 其消息经 FK CASCADE 同空；存在/不存在两态', () async {
      final char = await seedCharacter();
      final convA = await repo.createConversation(characterId: char.id);
      final convB = await repo.createConversation(characterId: char.id);
      await seedMessage(convA.id);

      expect(await repo.deleteConversation(convA.id), isTrue);
      expect(await messagesOf(convA.id), isEmpty);
      expect(await db.select(db.conversations).get(), hasLength(1));

      expect(await repo.deleteConversation(convA.id), isFalse);
      expect(await repo.deleteConversation(999999), isFalse);
      expect(await repo.getConversation(convB.id), isNotNull);
    });

    test('deleteAllConversations → conversations 与 messages 全空', () async {
      final char = await seedCharacter();
      final convA = await repo.createConversation(characterId: char.id);
      final convB = await repo.createConversation(characterId: char.id);
      await seedMessage(convA.id);
      await seedMessage(convB.id, role: Role.assistant);

      await repo.deleteAllConversations();
      expect(await db.select(db.conversations).get(), isEmpty);
      expect(await db.select(db.messages).get(), isEmpty);
    });
  });
}
