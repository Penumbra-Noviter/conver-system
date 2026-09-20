/// 应用数据库 — drift 数据库入口（schemaVersion=8，M0 冻结 + AC-01 升版 +
/// PS2-01 升版 + FD-05 升版 + VR-04 升版 + MS-01 升版 + WL-01 升版 +
/// NPD-02 升版）。
///
/// - 表注册：characters / conversations / messages / settings / memory_entries /
///   persona_revisions（定义见 `tables.dart`；前四表权威源为桌面端 ORM，
///   后两表为人机恋板块移动端先行）+ relationship_states / proactive_plans /
///   inner_thoughts（阶段 2 三表，spec §3）+ embedding_entries / semantic_hits
///   （阶段 3 两表，stage3-vector-recall spec §2 D2）+ message_swipes（MS-01
///   候选表，chat-polish spec §4.2）+ lorebook_entries（WL-01 世界书条目表，
///   chat-polish spec §4.4）
/// - NPD-02：characters.preset_dialogues + conversations.preset_dialogue 两列
///   （schemaVersion 7→8，chat-polish spec §4.5）
/// - 执行器构造注入：测试 seam，测试用 `AppDatabase(NativeDatabase.memory())`
///   在内存中打开真实 schema，不依赖设备
/// - 运行态连接经 [AppDatabase.open]（drift_flutter 惰性打开，内部即
///   LazyDatabase 包装，M0 不调用、不做任何真实查询；M1 起使用）
/// - 打开时启用 `PRAGMA foreign_keys = ON`，对齐桌面端 CASCADE 语义
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Conver System 移动端数据库。
@DriftDatabase(
  tables: [
    Characters,
    Conversations,
    Messages,
    Settings,
    MemoryEntries,
    PersonaRevisions,
    RelationshipStates,
    ProactivePlans,
    InnerThoughts,
    EmbeddingEntries,
    SemanticHits,
    MessageSwipes,
    LorebookEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 执行器注入构造（测试 seam / 自定义执行器）。
  AppDatabase(super.e);

  /// 运行态构造：drift_flutter 惰性打开（LazyDatabase），M0 不调用。
  factory AppDatabase.open() {
    return AppDatabase(driftDatabase(name: 'conver_system'));
  }

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // 对齐桌面端 CASCADE 删除语义（SQLite 默认关闭外键约束）。
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      // AC-01：schemaVersion 1→2 新增人机恋两表（memory_entries /
      // persona_revisions）。createTable 建表后以 raw SQL 补建 characterId
      // 外键索引（对齐 tables.dart 的 @TableIndex 注解；SQLite 不自动为 FK
      // 建索引）。索引名与列名用 drift 蛇形约定（表名/列名 snake_case）。
      if (from < 2) {
        await m.createTable(memoryEntries);
        await m.createTable(personaRevisions);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_memory_entries_character_id '
          'ON memory_entries (character_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_persona_revisions_character_id '
          'ON persona_revisions (character_id)',
        );
      }

      // PS2-01：schemaVersion 2→3 新增阶段 2 三表（relationship_states /
      // proactive_plans / inner_thoughts，spec §3）。沿 from < 2 先例：
      // createTable 建表 + raw SQL 补 FK 索引；relationship_states 的
      // character_id 为 UNIQUE（对齐 @TableIndex(unique: true)）。
      // drift onUpgrade 默认非事务（未显式包 transaction）：上述 DDL 逐条
      // 裸发、无自动 BEGIN/COMMIT 包裹。迁移正确性依赖三机制——CREATE
      // TABLE / CREATE INDEX 的 IF NOT EXISTS 幂等补建、user_version 迁移
      // 成功后回写、失败时库被锁无法打开直至重开重跑（重新触发
      // onUpgrade）。本实现不承诺原子性：引入显式事务包裹属行为变更，
      // 本票不做。
      if (from < 3) {
        await m.createTable(relationshipStates);
        await m.createTable(proactivePlans);
        await m.createTable(innerThoughts);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'idx_relationship_states_character_id '
          'ON relationship_states (character_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_proactive_plans_character_id '
          'ON proactive_plans (character_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_proactive_plans_conversation_id '
          'ON proactive_plans (conversation_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_proactive_plans_status '
          'ON proactive_plans (status)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_inner_thoughts_character_id '
          'ON inner_thoughts (character_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_inner_thoughts_message_id '
          'ON inner_thoughts (message_id)',
        );
      }

      // FD-05：schemaVersion 3→4 为 messages.created_at 补建单列索引
      // （对齐 tables.dart 新增的 @TableIndex；加速 latestMessageAt 的
      // join + ORDER BY created_at DESC LIMIT 1，不改存储精度——F-3
      // 已拍板 drift INTEGER 秒）。CREATE INDEX IF NOT EXISTS 幂等，
      // 中断残留重开时补建；user_version=4 由 drift 成功后回写，失败
      // 锁库重开重跑（F-78 幂等三机制延续）。
      if (from < 4) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_messages_created_at '
          'ON messages (created_at)',
        );
      }

      // VR-04：schemaVersion 4→5 新增阶段 3 两表（embedding_entries /
      // semantic_hits，spec §2 D2）。沿 from < 2/3 先例：createTable
      // 建表 + raw SQL 补 FK 索引；embedding_entries 的
      // (character_id, content_hash) 唯一索引为 SR-21 去重前提（对齐
      // tables.dart 的 @TableIndex(unique: true)）。drift onUpgrade
      // 非事务语义同上：本块 DDL 逐条裸发、无 BEGIN/COMMIT。迁移
      // 正确性依赖三机制——CREATE TABLE / CREATE INDEX 的 IF NOT
      // EXISTS 幂等补建、user_version=5 迁移成功后回写、失败时库被锁
      // 无法打开直至重开重跑（F-78 幂等三机制延续）。本块不引入显式
      // 事务包裹（对齐 F-78 结论：引事务属行为变更，本票不做）。
      if (from < 5) {
        await m.createTable(embeddingEntries);
        await m.createTable(semanticHits);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_embedding_entries_character_id '
          'ON embedding_entries (character_id)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'idx_embedding_entries_character_id_content_hash '
          'ON embedding_entries (character_id, content_hash)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_semantic_hits_character_id '
          'ON semantic_hits (character_id)',
        );
      }

      // MS-01：schemaVersion 5→6 新增候选表 message_swipes +
      // messages.active_swipe_index 列（chat-polish spec §4.2）。
      //
      // 列补建**不用** drift Migration.addColumn——它无 IF NOT EXISTS 语义，
      // 中断残留重开（列已补、后续 DDL 失败、user_version 未回写）时重复
      // 补列会 duplicate column 炸库。改走「PRAGMA table_info 探测缺列 →
      // ALTER TABLE ADD COLUMN」幂等补列（对齐桌面 database.py
      // `_ensure_messages_active_swipe_index` 探测补列先例），连续重跑
      // 无副作用。新表与 FK 索引用 CREATE TABLE / CREATE INDEX IF NOT
      // EXISTS 幂等补建（沿 from < 2/3/5 先例；drift 不自动为 FK 建索引，
      // raw SQL 补建对齐 tables.dart @TableIndex）。user_version=6 由
      // drift 成功后回写，失败锁库重开重跑（F-78 幂等三机制延续）。
      if (from < 6) {
        final columns = await customSelect('PRAGMA table_info(messages)').get();
        final hasActiveSwipeIndex = columns.any(
          (row) => row.data['name'] == 'active_swipe_index',
        );
        if (!hasActiveSwipeIndex) {
          await customStatement(
            'ALTER TABLE messages ADD COLUMN active_swipe_index '
            'INTEGER NOT NULL DEFAULT 0',
          );
        }
        await m.createTable(messageSwipes);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_message_swipes_message_id '
          'ON message_swipes (message_id)',
        );
      }

      // WL-01：schemaVersion 6→7 新增世界书条目表 lorebook_entries
      // （chat-polish spec §4.4，对齐桌面 models/lorebook.py）。沿
      // from < 2/3/5 先例：createTable 建表 + raw SQL 补 FK 索引
      // （drift 不自动为 FK 建索引，对齐 tables.dart 的 @TableIndex）。
      // CREATE TABLE / CREATE INDEX IF NOT EXISTS 幂等补建，中断残留重开
      // （表缺/索引缺、user_version 未回写）时补全；user_version=7 由
      // drift 成功后回写，失败锁库重开重跑（F-78 幂等三机制延续）。
      // 本块不含列变更，无需 PRAGMA table_info 探测补列。
      if (from < 7) {
        await m.createTable(lorebookEntries);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_lorebook_entries_character_id '
          'ON lorebook_entries (character_id)',
        );
      }

      // NPD-02：schemaVersion 7→8 新增 characters.preset_dialogues 列
      // （JSON 默认 '[]'）与 conversations.preset_dialogue 可空快照列
      // （chat-polish spec §4.5，对齐桌面 database.py
      // `_ensure_character_preset_dialogue_column` /
      // `_ensure_conversation_preset_dialogue` 探测补列先例）。
      //
      // 列补建**不用** drift Migration.addColumn——它无 IF NOT EXISTS 语义，
      // 中断残留重开（列已补、user_version 未回写）时重复补列会 duplicate
      // column 炸库。改走「PRAGMA table_info 探测缺列 → ALTER TABLE ADD
      // COLUMN」幂等补列（沿 from < 6 的 messages.active_swipe_index 先例）。
      // 本块不含新表/新索引，无需 CREATE IF NOT EXISTS。user_version=8 由
      // drift 成功后回写，失败锁库重开重跑（F-78 幂等三机制延续）。既有行
      // 默认值：characters → '[]'（preset_dialogues 非空默认）、
      // conversations → null（preset_dialogue 可空，零影响）。
      if (from < 8) {
        final charColumns = await customSelect('PRAGMA table_info(characters)')
            .get();
        final hasPresetDialogues = charColumns.any(
          (row) => row.data['name'] == 'preset_dialogues',
        );
        if (!hasPresetDialogues) {
          await customStatement(
            'ALTER TABLE characters ADD COLUMN preset_dialogues '
            "TEXT NOT NULL DEFAULT '[]'",
          );
        }
        final convColumns = await customSelect(
          'PRAGMA table_info(conversations)',
        ).get();
        final hasPresetDialogue = convColumns.any(
          (row) => row.data['name'] == 'preset_dialogue',
        );
        if (!hasPresetDialogue) {
          await customStatement(
            'ALTER TABLE conversations ADD COLUMN preset_dialogue TEXT',
          );
        }
      }
    },
  );
}
