/// 对话仓储行为契约（工单 03 验收 A1/A3/A4/A6/A7 的对话面）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上运行真 schema
/// （M0 seam 复用）；语义锚点：桌面 `services/conversation.py`。
library;

import 'dart:convert';

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
  Future<String> get defaultProvider async => values['default_provider'] ?? '';

  @override
  Future<String> get defaultModel async => values['default_model'] ?? '';

  @override
  Future<String> get userName async => values['user_name'] ?? '';

  @override
  Future<Map<String, String>> get templateVars async {
    final raw = values['template_vars'] ?? '';
    if (raw.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const {};
      }
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return const {};
    }
  }
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

    test('first_mes 含自定义变量 → 开场白注入 extraVars（工单 04）', () async {
      final char = await seedCharacter(
        name: '艾莉亚',
        firstMes: '欢迎来到{{city}}，{{user}}！我是{{char}}。',
      );
      final withVars = ConversationRepository(
        db,
        const FakeSettingsReader({
          'user_name': '阿明',
          'template_vars': '{"city":"长安"}',
        }),
        now: () => fakeNow,
      );

      final conv = await withVars.createConversation(characterId: char.id);

      expect(
        (await messagesOf(conv.id)).single.content,
        '欢迎来到长安，阿明！我是艾莉亚。',
      );
    });

    test('template_vars 非法 JSON → extraVars 回退空 map，开场白仅替换 user/char',
        () async {
      final char = await seedCharacter(
        name: '艾莉亚',
        firstMes: '欢迎{{city}}，{{user}}。',
      );
      final broken = ConversationRepository(
        db,
        const FakeSettingsReader({'template_vars': 'not-json'}),
        now: () => fakeNow,
      );

      final conv = await broken.createConversation(characterId: char.id);

      expect((await messagesOf(conv.id)).single.content, '欢迎{{city}}，User。');
    });

    test('角色无 first_mes → 不预插消息（message_count 0）', () async {
      final char = await seedCharacter(name: '无名');
      final conv = await repo.createConversation(characterId: char.id);
      final listed = await repo.listConversations(characterId: char.id);
      expect(listed.single.messageCount, 0);
      expect(await messagesOf(conv.id), isEmpty);
    });
  });

  group('createConversation · greeting 三态（NPD-03 验收 1/2）', () {
    test('未传（null）→ 预插 first_mes（模板变量替换，零回归断言）', () async {
      final char = await seedCharacter(
        name: '艾莉亚',
        firstMes: '你好，{{user}}！我是{{char}}。',
      );
      final withUser = ConversationRepository(
        db,
        const FakeSettingsReader({'user_name': '阿明'}),
        now: () => fakeNow,
      );
      final conv = await withUser.createConversation(
        characterId: char.id,
        greeting: null,
      );
      expect(
        (await messagesOf(conv.id)).single.content,
        '你好，阿明！我是艾莉亚。',
        reason: '显式传 null 与未传语义一致：预插 first_mes 并模板替换',
      );
    });

    test('指定文本 → 预插该内容（模板变量替换后），无视 first_mes 原值', () async {
      final char = await seedCharacter(
        name: '夜莺',
        firstMes: '不会被使用的旧开场白',
      );
      final withUser = ConversationRepository(
        db,
        const FakeSettingsReader({'user_name': '旅人'}),
        now: () => fakeNow,
      );

      final conv = await withUser.createConversation(
        characterId: char.id,
        greeting: '{{user}}，欢迎来到{{char}}的故事。',
      );

      expect(
        (await messagesOf(conv.id)).single.content,
        '旅人，欢迎来到夜莺的故事。',
        reason: '指定 greeting 文本替换 {{user}}/{{char}} 后预插',
      );
    });

    test('first_mes 为空 + 指定文本 → 仍预插指定文本（greeting 独立于 first_mes）',
        () async {
      final char = await seedCharacter(name: '空开场角色');
      final conv = await repo.createConversation(
        characterId: char.id,
        greeting: '显式指定开场白。',
      );

      expect((await messagesOf(conv.id)).single.content, '显式指定开场白。');
    });

    test('显式空串 → 不预插（消息表为空），即使角色有 first_mes', () async {
      final char = await seedCharacter(
        name: '艾莉亚',
        firstMes: '有开场白但被显式禁用',
      );
      final conv = await repo.createConversation(
        characterId: char.id,
        greeting: '',
      );
      expect(await messagesOf(conv.id), isEmpty,
          reason: 'greeting 显式空串 = 无开场白：消息表必须为空');
      expect(
        (await repo.listConversations(characterId: char.id)).single.messageCount,
        0,
      );
    });

    test('first_mes 为空 + 未传 greeting → 不预插（既有语义不变，验收 2）',
        () async {
      final char = await seedCharacter(name: '无名');
      final conv = await repo.createConversation(characterId: char.id);
      expect(await messagesOf(conv.id), isEmpty);
    });
  });

  group('createConversation · 预设对话快照（NPD-02 验收 5）', () {
    test('带 presetDialogue → 快照固化入 conversations.preset_dialogue', () async {
      final char = await seedCharacter(name: '艾莉亚');
      final conv = await repo.createConversation(
        characterId: char.id,
        presetDialogue: '<START>\n{{user}}: 你好\n{{char}}: 欢迎',
      );

      final stored = await repo.getConversation(conv.id);
      expect(stored!.presetDialogue, '<START>\n{{user}}: 你好\n{{char}}: 欢迎');
    });

    test('空串 → 快照列不落伪值（null），其余创建语义零回归', () async {
      final char = await seedCharacter(name: '诺克斯');
      final conv = await repo.createConversation(
        characterId: char.id,
        presetDialogue: '',
      );
      expect(conv.presetDialogue, isNull);
    });

    test('快照语义契约锁：改角色卡 presetDialogues 实时值不影响已建会话快照',
        () async {
      final char = await seedCharacter(name: '艾莉亚');
      final conv = await repo.createConversation(
        characterId: char.id,
        presetDialogue: '<START>\n{{user}}: 固化快照{{char}}',
      );

      // 创建后修改角色卡 presetDialogues（实时值变为另一快照文本）。
      await (db.update(db.characters)..where((t) => t.id.equals(char.id))).write(
        CharactersCompanion(
          presetDialogues: Value(const [
            {'name': '变更', 'content': '后改的内容'},
          ]),
        ),
      );

      // 已建会话的注入源仍为创建时固化的快照（改卡零影响）。
      final stored = await repo.getConversation(conv.id);
      expect(stored!.presetDialogue, '<START>\n{{user}}: 固化快照{{char}}');
    });

    test('纯空白 → 非空串原样固化（桌面 or None 语义；注入门控在 buildMessages',
        () async {
      final char = await seedCharacter(name: '夜莺');
      final conv = await repo.createConversation(
        characterId: char.id,
        presetDialogue: '   ',
      );
      // 桌面 `data.preset_dialogue or None`：Python 纯空白 truthy → 原样固化
      // （buildMessages 侧以 trim 门控零注入），非空串不归一为 null。
      expect(conv.presetDialogue, '   ');
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
