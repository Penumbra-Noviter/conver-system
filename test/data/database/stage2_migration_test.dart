/// PS2-01 迁移测试 — schemaVersion 2→4（三新表 + FK 索引 + 级联/FK 语义）；
/// FD-05 追加 messages.created_at 索引，迁移断言按 schemaVersion 4 语义。
///
/// 迁移路径用「降级夹具」构造 v2 存量库：先在最新 schema 的文件库上插入旧
/// 数据，再 `DROP` 三新表 + `PRAGMA user_version = 2`，关闭后重新打开 —
/// drift 检测 user_version=2 < 4 会执行 onUpgrade `from < 3` 与 `from < 4`
/// 分支，等价于真实 v2 存量库连续升级。重复打开幂等用同一文件再开验证；
/// 全新安装（无表直接建库）用内存库验证 schemaVersion 直接为最新、不跑
/// onUpgrade。
library;

import 'dart:io';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/db_meta.dart';

/// 迁移后的三表名（drift 蛇形约定）。
const _newTables = <String>[
  'relationship_states',
  'proactive_plans',
  'inner_thoughts',
];

/// 7 个迁移新增索引锚（snake_case 列名）：6 个 FK 索引 + FD-05 的
/// messages.created_at 索引。
const _newIndexes = <String>[
  'idx_relationship_states_character_id',
  'idx_proactive_plans_character_id',
  'idx_proactive_plans_conversation_id',
  'idx_proactive_plans_status',
  'idx_inner_thoughts_character_id',
  'idx_inner_thoughts_message_id',
  'idx_messages_created_at',
];

/// 建一个「v2 存量库」：文件库上建最新 schema → 插旧数据 → 降级到 v2 形态。
///
/// 返回已迁移到 4 的 [AppDatabase] 与临时目录（供 tearDown 清理；db 需
/// 调用方 close）。
Future<(AppDatabase, Directory)> openV2UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('ps2_01_migration_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();

  final character = await db.into(db.characters).insertReturning(
        CharactersCompanion.insert(name: '艾莉亚', createdAt: now, updatedAt: now),
      );
  final conversation = await db.into(db.conversations).insertReturning(
        ConversationsCompanion.insert(
          characterId: character.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db.into(db.messages).insert(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.assistant,
          content: '旅者，你来了。',
          createdAt: now,
        ),
      );
  await db.into(db.memoryEntries).insert(
        MemoryEntriesCompanion.insert(
          characterId: character.id,
          kind: MemoryKind.personaFact,
          content: '喜欢旧书店的樟脑味',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db.into(db.personaRevisions).insert(
        PersonaRevisionsCompanion.insert(
          characterId: character.id,
          personalitySnapshot: '温柔而疏离',
          createdAt: now,
        ),
      );

  // 降级到 v2：标记版本 + 移除阶段 2 三表（索引随表删除）+ 移除
  // messages.created_at 索引（FD-05 属 v4 形态；真实 v2 存量库不含该索引，
  // 保留会导致 from < 4 分支的 CREATE INDEX 被 IF NOT EXISTS 幂等跳过，
  // 掩盖「旧库升级补建索引」的真实路径）。
  await db.customStatement('PRAGMA user_version = 2');
  await db.customStatement('DROP TABLE IF EXISTS inner_thoughts');
  await db.customStatement('DROP TABLE IF EXISTS proactive_plans');
  await db.customStatement('DROP TABLE IF EXISTS relationship_states');
  await db.customStatement('DROP INDEX IF EXISTS idx_messages_created_at');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v1 存量库」：文件库上建最新 schema → 插 v1 时代数据（无记忆表）→
/// 降级到 v1 形态（user_version=1 + DROP 记忆两表与阶段 2 三表）。
///
/// 打开时 from=1：先走 `from < 2` 分支（重建记忆两表），再走 `from < 3`
/// 分支（建阶段 2 三表），等价于真实 v1 存量库连续升级。
Future<(AppDatabase, Directory)> openV1UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('ps2_01_migration_v1_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();

  final character = await db.into(db.characters).insertReturning(
        CharactersCompanion.insert(name: '旧识', createdAt: now, updatedAt: now),
      );
  final conversation = await db.into(db.conversations).insertReturning(
        ConversationsCompanion.insert(
          characterId: character.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db.into(db.messages).insert(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.user,
          content: '从前有座山。',
          createdAt: now,
        ),
      );

  // 降级到 v1：user_version=1 + DROP 记忆两表与阶段 2 三表；同时移除
  // messages.created_at 索引（FD-05 属 v4 形态，真实 v1 存量库不含该索引）。
  await db.customStatement('PRAGMA user_version = 1');
  await db.customStatement('DROP TABLE IF EXISTS inner_thoughts');
  await db.customStatement('DROP TABLE IF EXISTS proactive_plans');
  await db.customStatement('DROP TABLE IF EXISTS relationship_states');
  await db.customStatement('DROP TABLE IF EXISTS persona_revisions');
  await db.customStatement('DROP TABLE IF EXISTS memory_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_messages_created_at');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

Future<int> userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.data['user_version'] as int;
}

/// 插入角色→对话→消息链，并挂上三新表各一行，返回相关 id。
Future<({int characterId, int conversationId, int messageId})> seedFullChain(
  AppDatabase db,
) async {
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
  final message = await db.into(db.messages).insertReturning(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.user,
          content: '你还好吗？',
          createdAt: now,
        ),
      );

  await db.into(db.relationshipStates).insert(
        RelationshipStatesCompanion.insert(
          characterId: character.id,
          stage: RelationshipStage.acquainted,
          affinity: const Value(20),
          updatedAt: now,
        ),
      );
  await db.into(db.proactivePlans).insert(
        ProactivePlansCompanion.insert(
          characterId: character.id,
          conversationId: conversation.id,
          content: '今晚月色很好。',
          scheduledAt: now.add(const Duration(hours: 8)),
          sentAt: const Value(null),
          status: ProactivePlanStatus.scheduled,
          messageId: Value(message.id),
        ),
      );
  await db.into(db.innerThoughts).insert(
        InnerThoughtsCompanion.insert(
          characterId: character.id,
          messageId: message.id,
          content: '他说「你还好吗」时，声音有点抖。',
          createdAt: now,
        ),
      );

  return (
    characterId: character.id,
    conversationId: conversation.id,
    messageId: message.id,
  );
}

void main() {
  group('schemaVersion 4 契约（全新安装）', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('AppDatabase.schemaVersion == 4', () {
      expect(db.schemaVersion, 4);
    });

    test('全新安装直接建 9 表 + 7 迁移新增索引（含唯一索引）', () async {
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
          ..._newTables,
        ]),
      );

      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, containsAll(_newIndexes));

      // characterId 唯一索引：raw SQL 与 @TableIndex(unique: true) 均为 UNIQUE。
      final uniqueSql = await db.customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_relationship_states_character_id'",
      ).getSingle();
      expect(uniqueSql.data['sql'] as String, contains('UNIQUE'));
    });
  });

  group('schemaVersion 2→4 迁移', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV2UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('旧行保留 + 三表/7 索引存在于 sqlite_master + user_version=4', () async {
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      expect(await db.select(db.messages).get().then((r) => r.length), 1);
      expect(await db.select(db.memoryEntries).get().then((r) => r.length), 1);
      expect(await db.select(db.personaRevisions).get().then((r) => r.length), 1);

      final tables = await sqliteMasterNames(db, 'table');
      expect(tables, containsAll(_newTables));

      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, containsAll(_newIndexes));

      expect(await userVersion(db), 4);
    });

    test('三表可读写 + converter 字符串落库（stage 五值 / status 四值）', () async {
      final now = DateTime.now();

      for (final stage in RelationshipStage.values) {
        final character = await db.into(db.characters).insertReturning(
              CharactersCompanion.insert(
                name: 'stage-${stage.value}',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db.into(db.relationshipStates).insert(
              RelationshipStatesCompanion.insert(
                characterId: character.id,
                stage: stage,
                affinity: const Value(30),
                updatedAt: now,
              ),
            );
      }

      final conversation = await db.select(db.conversations).getSingle();
      final characterId = conversation.characterId;
      final messageId = (await db.select(db.messages).getSingle()).id;
      for (final status in ProactivePlanStatus.values) {
        await db.into(db.proactivePlans).insert(
              ProactivePlansCompanion.insert(
                characterId: characterId,
                conversationId: conversation.id,
                content: 'plan-${status.value}',
                scheduledAt: now,
                sentAt: const Value(null),
                status: status,
                messageId: const Value(null),
              ),
            );
      }
      await db.into(db.innerThoughts).insert(
            InnerThoughtsCompanion.insert(
              characterId: characterId,
              messageId: messageId,
              content: '想说的话',
              createdAt: now,
            ),
          );

      final states = await db.select(db.relationshipStates).get();
      expect(
        states.map((s) => s.stage),
        containsAllInOrder(RelationshipStage.values),
      );
      final plans = await db.select(db.proactivePlans).get();
      expect(
        plans.map((p) => p.status),
        containsAllInOrder(ProactivePlanStatus.values),
      );
      expect((await db.select(db.innerThoughts).getSingle()).content, '想说的话');

      // 存储层断言：落库值为 .value 字符串（而非枚举下标整数）。
      // 显式 ORDER BY id，避免无 ORDER BY 查询的物理扫描顺序不确定性。
      final rawStages = await db.customSelect(
        'SELECT stage FROM relationship_states ORDER BY id',
      ).get();
      expect(
        rawStages.map((row) => row.data['stage']),
        RelationshipStage.values.map((s) => s.value),
      );
      final rawStatuses = await db.customSelect(
        'SELECT status FROM proactive_plans ORDER BY id',
      ).get();
      expect(
        rawStatuses.map((row) => row.data['status']),
        ProactivePlanStatus.values.map((s) => s.value),
      );
    });

    test('relationship_states 唯一索引拒绝重复角色行', () async {
      final now = DateTime.now();
      final character = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(name: '唯一', createdAt: now, updatedAt: now),
          );
      await db.into(db.relationshipStates).insert(
            RelationshipStatesCompanion.insert(
              characterId: character.id,
              stage: RelationshipStage.stranger,
              updatedAt: now,
            ),
          );

      await expectLater(
        db.into(db.relationshipStates).insert(
              RelationshipStatesCompanion.insert(
                characterId: character.id,
                stage: RelationshipStage.familiar,
                updatedAt: now,
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
    });

    test('删角色 → conversations/messages 与三表级联清空', () async {
      final ids = await seedFullChain(db);

      await (db.delete(db.characters)..where((t) => t.id.equals(ids.characterId)))
          .go();

      // fixture 自带角色艾莉亚及其对话/消息保留；诺克斯的对话/消息与
      // 阶段 2 三表数据全部级联清空。
      expect(await db.select(db.characters).get(), hasLength(1));
      expect(await db.select(db.conversations).get(), hasLength(1));
      expect(await db.select(db.messages).get(), hasLength(1));
      expect(await db.select(db.relationshipStates).get(), isEmpty);
      expect(await db.select(db.proactivePlans).get(), isEmpty);
      expect(await db.select(db.innerThoughts).get(), isEmpty);
    });

    test('删消息 → proactive_plans.messageId 置空、inner_thoughts 级联删除', () async {
      final ids = await seedFullChain(db);

      await (db.delete(db.messages)..where((t) => t.id.equals(ids.messageId)))
          .go();

      final plan = await db.select(db.proactivePlans).getSingle();
      expect(plan.messageId, isNull);
      expect(plan.status, ProactivePlanStatus.scheduled);
      expect(await db.select(db.innerThoughts).get(), isEmpty);
    });

    test('中断残留重开自愈：部分建表落盘即关闭 → 重开幂等补全且旧行保留', () async {
      // 模拟迁移中途被杀留下的残留态：仅 relationship_states 表与其唯一
      // 索引落盘（onUpgrade 顺序中已执行到 createTable 之后、后续两表
      // 之前），其余两表及 5 个索引缺失，user_version 未提升（仍为 2）。
      await db.customStatement('DROP TABLE IF EXISTS proactive_plans');
      await db.customStatement('DROP TABLE IF EXISTS inner_thoughts');
      await db.customStatement('PRAGMA user_version = 2');

      // 前置断言：确认残留态真实存在，否则「重开自愈」无从谈起。
      final residualTables = await sqliteMasterNames(db, 'table');
      expect(residualTables, contains('relationship_states'));
      expect(residualTables, isNot(contains('proactive_plans')));
      expect(residualTables, isNot(contains('inner_thoughts')));
      final residualIndexes = await sqliteMasterNames(db, 'index');
      expect(
        residualIndexes,
        contains('idx_relationship_states_character_id'),
      );
      expect(
        residualIndexes,
        isNot(contains('idx_proactive_plans_character_id')),
      );
      expect(await userVersion(db), 2);

      // 重开：drift 检测 user_version=2 < 4 重跑 from < 3 与 from < 4 分支，
      // IF NOT EXISTS 幂等补建缺失的表/索引；成功后再把 user_version
      // 回写为 4。
      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 4);
      expect(await sqliteMasterNames(db, 'table'), containsAll(_newTables));
      expect(await sqliteMasterNames(db, 'index'), containsAll(_newIndexes));

      // 残留唯一索引原样保留（IF NOT EXISTS 跳过而非重建）。
      final uniqueSql = await db.customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_relationship_states_character_id'",
      ).getSingle();
      expect(uniqueSql.data['sql'] as String, contains('UNIQUE'));

      // 旧行保留：v2 时代五张表数据均可读。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      expect(await db.select(db.messages).get().then((r) => r.length), 1);
      expect(await db.select(db.memoryEntries).get().then((r) => r.length), 1);
      expect(await db.select(db.personaRevisions).get().then((r) => r.length), 1);
    });

    test('重复打开幂等：同文件重开不重跑迁移，三表与数据仍在', () async {
      // 当前 db 已迁移到 4；写入一行标识数据后关闭再重开。
      final now = DateTime.now();
      await db.into(db.relationshipStates).insert(
            RelationshipStatesCompanion.insert(
              characterId:
                  (await db.select(db.characters).getSingle()).id,
              stage: RelationshipStage.stranger,
              updatedAt: now,
            ),
          );
      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 4);
      expect(await sqliteMasterNames(db, 'table'), containsAll(_newTables));
      expect(await sqliteMasterNames(db, 'index'), containsAll(_newIndexes));
      expect(await db.select(db.relationshipStates).get(), hasLength(1));
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
    });
  });

  group('schemaVersion 1→4 连续迁移', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV1UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v1 存量库连续升级：记忆两表重建 + 三新表 + 旧行保留 + user_version=4', () async {
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.messages).get().then((r) => r.length), 1);

      final tables = await sqliteMasterNames(db, 'table');
      expect(tables, containsAll([
        'memory_entries',
        'persona_revisions',
        ..._newTables,
      ]));
      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, containsAll(_newIndexes));
      expect(await userVersion(db), 4);
    });
  });

  group('converter 边界（Falsify）', () {
    test('RelationshipStageConverter 未知字符串抛 ArgumentError', () {
      const converter = RelationshipStageConverter();
      for (final stage in RelationshipStage.values) {
        expect(converter.toSql(stage), stage.value);
        expect(converter.fromSql(stage.value), stage);
      }
      expect(() => converter.fromSql('acquaintted'), throwsArgumentError);
    });

    test('ProactivePlanStatusConverter 未知字符串抛 ArgumentError', () {
      const converter = ProactivePlanStatusConverter();
      for (final status in ProactivePlanStatus.values) {
        expect(converter.toSql(status), status.value);
        expect(converter.fromSql(status.value), status);
      }
      expect(() => converter.fromSql('sent_at'), throwsArgumentError);
    });

    test('MemoryKindConverter 未知字符串抛 ArgumentError（既有表回归）', () {
      const converter = MemoryKindConverter();
      expect(() => converter.fromSql('unknown'), throwsArgumentError);
    });
  });
}