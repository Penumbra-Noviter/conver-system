/// G0.2c 冒烟测试 — drift schema 与桌面 ORM 逐字段对齐（schemaVersion=8，
/// 13 表：4 基础表 + 记忆两表 + 阶段 2 三表 + 阶段 3 两表 + MS-01 候选表 +
/// WL-01 世界书条目表 + NPD-02 characters.preset_dialogues /
/// conversations.preset_dialogue 两列）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上运行，
/// 经构造注入 seam 打开真实 schema，不依赖设备、无 repositories。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/db_meta.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schemaVersion 冻结为 8', () {
    expect(db.schemaVersion, 8);
  });

  test('内存执行器打开成功，12 表可定位', () async {
    final tables = await sqliteMasterNames(db, 'table');
    expect(
      tables,
      containsAll([
        'characters',
        'conversations',
        'messages',
        'settings',
        'memory_entries',
        'persona_revisions',
        'relationship_states',
        'proactive_plans',
        'inner_thoughts',
        'embedding_entries',
        'semantic_hits',
        'message_swipes',
        'lorebook_entries',
      ]),
    );
  });

  test('4 表可写入读取（含列默认值，角色→对话→消息链）', () async {
    final now = DateTime.now();

    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            tags: const Value(['奇幻', '导师']),
            extensions: const Value({'v2': true}),
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(character.description, '');
    expect(character.version, '1.0');
    expect(character.temperature, 0.7);
    expect(character.tags, ['奇幻', '导师']);
    expect(character.extensions, {'v2': true});
    expect(character.alternateGreetings, isEmpty);

    final conversation = await db
        .into(db.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(conversation.title, '新对话');
    expect(conversation.modelProvider, 'claude');
    expect(conversation.modelName, 'claude-sonnet-5');

    final message = await db
        .into(db.messages)
        .insertReturning(
          MessagesCompanion.insert(
            conversationId: conversation.id,
            role: Role.assistant,
            content: '你好，旅者。',
            createdAt: now,
          ),
        );
    expect(message.role, Role.assistant);
    expect(message.content, '你好，旅者。');

    await db
        .into(db.settings)
        .insert(
          SettingsCompanion.insert(key: 'theme', value: const Value('dark')),
        );
    final setting = await db.select(db.settings).getSingle();
    expect(setting.key, 'theme');
    expect(setting.value, 'dark');
  });

  test('Role converter 显式按 .value 落库', () {
    const converter = RoleConverter();
    expect(converter.toSql(Role.user), 'user');
    expect(converter.toSql(Role.assistant), 'assistant');
    expect(converter.toSql(Role.system), 'system');
    expect(converter.fromSql('user'), Role.user);
    expect(converter.fromSql('assistant'), Role.assistant);
    expect(converter.fromSql('system'), Role.system);
    expect(() => converter.fromSql('tool'), throwsArgumentError);
  });

  test('消息落库后 role 的存储值与回读值一致', () async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '诺克斯',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final conversation = await db
        .into(db.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );

    for (final role in Role.values) {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: conversation.id,
              role: role,
              content: 'msg-${role.value}',
              createdAt: now,
            ),
          );
    }

    final rows = await db.select(db.messages).get();
    expect(rows.map((m) => m.role), containsAllInOrder(Role.values));

    // 存储层断言：落库值是 .value 字符串，而非枚举下标。
    final rawRoles = await db.customSelect('SELECT role FROM messages').get();
    expect(rawRoles.map((row) => row.data['role']), [
      'user',
      'assistant',
      'system',
    ]);
  });

  test('最小索引集存在于 sqlite_master', () async {
    final indexes = await sqliteMasterNames(db, 'index');
    expect(
      indexes,
      containsAll(<String>[
        'idx_characters_name',
        'idx_conversations_character_id',
        'idx_messages_conversation_id',
        'idx_messages_created_at',
        'idx_memory_entries_character_id',
        'idx_persona_revisions_character_id',
        'idx_relationship_states_character_id',
        'idx_proactive_plans_character_id',
        'idx_proactive_plans_conversation_id',
        'idx_proactive_plans_status',
        'idx_inner_thoughts_character_id',
        'idx_inner_thoughts_message_id',
        'idx_embedding_entries_character_id',
        'idx_embedding_entries_character_id_content_hash',
        'idx_semantic_hits_character_id',
        'idx_message_swipes_message_id',
        'idx_lorebook_entries_character_id',
      ]),
    );
  });

  test('settings 主键即 key，无额外索引', () async {
    final indexes = await sqliteMasterNames(db, 'index', table: 'settings');
    // TEXT 主键产生 sqlite_autoindex 主键索引，此外不应有显式索引。
    expect(indexes, everyElement(startsWith('sqlite_autoindex')));
  });

  test('beforeOpen 启用外键：孤儿对话插入被拒绝', () async {
    final now = DateTime.now();
    await expectLater(
      db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              characterId: 999999,
              createdAt: now,
              updatedAt: now,
            ),
          ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('FOREIGN KEY'),
        ),
      ),
    );
  });

  test('messages.active_swipe_index 默认 0（MS-01 列契约）', () async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '默认值',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final conversation = await db
        .into(db.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final message = await db
        .into(db.messages)
        .insertReturning(
          MessagesCompanion.insert(
            conversationId: conversation.id,
            role: Role.assistant,
            content: '你好',
            createdAt: now,
          ),
        );

    expect(message.activeSwipeIndex, 0, reason: 'spec §4.2 默认 0');
  });

  test('message_swipes 可写读 + (message_id, index) 唯一约束生效（MS-01）', () async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '候选',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final conversation = await db
        .into(db.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final message = await db
        .into(db.messages)
        .insertReturning(
          MessagesCompanion.insert(
            conversationId: conversation.id,
            role: Role.assistant,
            content: '原始回复',
            createdAt: now,
          ),
        );

    await db.into(db.messageSwipes).insert(
          MessageSwipesCompanion.insert(
            messageId: message.id,
            index: 0,
            content: '原始回复',
            createdAt: now,
          ),
        );
    final swipe = await db.into(db.messageSwipes).insertReturning(
          MessageSwipesCompanion.insert(
            messageId: message.id,
            index: 1,
            content: '候选一',
            createdAt: now,
          ),
        );
    expect(swipe.messageId, message.id);
    expect(swipe.index, 1);
    expect(swipe.content, '候选一');

    // 同消息重复 index → UNIQUE 约束拒绝。
    await expectLater(
      db.into(db.messageSwipes).insert(
            MessageSwipesCompanion.insert(
              messageId: message.id,
              index: 1,
              content: '重复',
              createdAt: now,
            ),
          ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('UNIQUE'),
        ),
      ),
    );

    // 不同消息相同 index 可共存（唯一键是 (message_id, index) 组合）。
    final other = await db
        .into(db.messages)
        .insertReturning(
          MessagesCompanion.insert(
            conversationId: conversation.id,
            role: Role.assistant,
            content: '另一消息',
            createdAt: now,
          ),
        );
    await db.into(db.messageSwipes).insert(
          MessageSwipesCompanion.insert(
            messageId: other.id,
            index: 1,
            content: '异消息同 index',
            createdAt: now,
          ),
        );
  });

  test('删消息 → message_swipes 级联清除（FK CASCADE 实测，SR-27）', () async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '级联',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final conversation = await db
        .into(db.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final message = await db
        .into(db.messages)
        .insertReturning(
          MessagesCompanion.insert(
            conversationId: conversation.id,
            role: Role.assistant,
            content: '原始回复',
            createdAt: now,
          ),
        );
    await db.into(db.messageSwipes).insert(
          MessageSwipesCompanion.insert(
            messageId: message.id,
            index: 0,
            content: '原始回复',
            createdAt: now,
          ),
        );

    await (db.delete(
      db.messages,
    )..where((t) => t.id.equals(message.id))).go();

    expect(await db.select(db.messageSwipes).get(), isEmpty);
  });

  test('lorebook_entries 可写读 + keys JSON 往返 + 默认值（WL-01）', () async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '世界书角色',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final created = await db.into(db.lorebookEntries).insertReturning(
          LorebookEntriesCompanion.insert(
            characterId: character.id,
            keys: const Value(['酒馆', 'tavern']),
            content: const Value('酒馆的老板是莉莉。'),
            order: const Value(55),
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(created.keys, ['酒馆', 'tavern'], reason: 'keys JSON 落库/读回数组');
    expect(created.title, '', reason: '缺省默认');
    expect(created.constant, isFalse);
    expect(created.probability, 100);
    expect(created.groupName, '');
    expect(created.groupWeight, 100);
    expect(created.matchMode, 'or');
    expect(created.position, 'world');
    expect(created.depth, 20);
    expect(created.source, 'manual');
    expect(created.enabled, isTrue);
  });

  test('lorebook_entries 孤儿角色写入被 FK 拒绝（WL-01，PRAGMA FK=ON 实测）',
      () async {
    final now = DateTime.now();
    await expectLater(
      db.into(db.lorebookEntries).insert(
            LorebookEntriesCompanion.insert(
              characterId: 999999,
              createdAt: now,
              updatedAt: now,
            ),
          ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('FOREIGN KEY'),
        ),
      ),
    );
  });

  test('characters.preset_dialogues 缺省 [] + JSON 往返（NPD-02 列契约）', () async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '预设对话角色',
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(character.presetDialogues, isEmpty, reason: '缺省 JSON []');

    await (db.update(db.characters)..where((t) => t.id.equals(character.id)))
        .write(
          CharactersCompanion(
            presetDialogues: const Value([
              {'name': '寒暄', 'content': '你好，请问怎么称呼？'},
              {'name': '告别', 'content': '下次再见。'},
            ]),
          ),
        );
    final stored = await db.select(db.characters).getSingle();
    expect(stored.presetDialogues, [
      {'name': '寒暄', 'content': '你好，请问怎么称呼？'},
      {'name': '告别', 'content': '下次再见。'},
    ]);
  });

  test('conversations.preset_dialogue 缺省 null + 快照写入（NPD-02 列契约）',
      () async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '快照角色',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final conversation = await db
        .into(db.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(conversation.presetDialogue, null, reason: '可空快照列缺省 null');

    await (db.update(db.conversations)
          ..where((t) => t.id.equals(conversation.id)))
        .write(
          ConversationsCompanion(
            presetDialogue:
                const Value('<START>\n{{user}}: 你好\n{{char}}: 欢迎'),
          ),
        );
    final stored = await db.select(db.conversations).getSingle();
    expect(stored.presetDialogue, '<START>\n{{user}}: 你好\n{{char}}: 欢迎');
  });
}
