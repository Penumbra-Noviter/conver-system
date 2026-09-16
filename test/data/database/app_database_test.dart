/// G0.2c 冒烟测试 — drift 4 表 schema 与桌面 ORM 逐字段对齐。
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

  test('schemaVersion 冻结为 3', () {
    expect(db.schemaVersion, 3);
  });

  test('内存执行器打开成功，9 表可定位', () async {
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
      ]),
    );
  });

  test('4 表可写入读取（含列默认值，角色→对话→消息链）', () async {
    final now = DateTime.now();

    final character = await db.into(db.characters).insertReturning(
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

    final conversation = await db.into(db.conversations).insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(conversation.title, '新对话');
    expect(conversation.modelProvider, 'claude');
    expect(conversation.modelName, 'claude-sonnet-5');

    final message = await db.into(db.messages).insertReturning(
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
        .insert(SettingsCompanion.insert(key: 'theme', value: const Value('dark')));
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
    final character = await db.into(db.characters).insertReturning(
          CharactersCompanion.insert(name: '诺克斯', createdAt: now, updatedAt: now),
        );
    final conversation = await db.into(db.conversations).insertReturning(
          ConversationsCompanion.insert(
            characterId: character.id,
            createdAt: now,
            updatedAt: now,
          ),
        );

    for (final role in Role.values) {
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: conversation.id,
              role: role,
              content: 'msg-${role.value}',
              createdAt: now,
            ),
          );
    }

    final rows = await db.select(db.messages).get();
    expect(
      rows.map((m) => m.role),
      containsAllInOrder(Role.values),
    );

    // 存储层断言：落库值是 .value 字符串，而非枚举下标。
    final rawRoles = await db.customSelect('SELECT role FROM messages').get();
    expect(
      rawRoles.map((row) => row.data['role']),
      ['user', 'assistant', 'system'],
    );
  });

  test('最小索引集存在于 sqlite_master', () async {
    final indexes = await sqliteMasterNames(db, 'index');
    expect(indexes, containsAll(<String>[
      'idx_characters_name',
      'idx_conversations_character_id',
      'idx_messages_conversation_id',
      'idx_memory_entries_character_id',
      'idx_persona_revisions_character_id',
      'idx_relationship_states_character_id',
      'idx_proactive_plans_character_id',
      'idx_proactive_plans_conversation_id',
      'idx_proactive_plans_status',
      'idx_inner_thoughts_character_id',
      'idx_inner_thoughts_message_id',
    ]));
  });

  test('settings 主键即 key，无额外索引', () async {
    final indexes = await sqliteMasterNames(db, 'index', table: 'settings');
    // TEXT 主键产生 sqlite_autoindex 主键索引，此外不应有显式索引。
    expect(indexes, everyElement(startsWith('sqlite_autoindex')));
  });

  test('beforeOpen 启用外键：孤儿对话插入被拒绝', () async {
    final now = DateTime.now();
    await expectLater(
      db.into(db.conversations).insert(
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
}
