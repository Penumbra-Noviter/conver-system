/// PS2-01 / FD-05 / VR-04 / MS-01 / WL-01 / NPD-02 / NPD-04 / SP-01 迁移测试 —
/// schemaVersion
/// 2→10 / 1→10 / 4→10 / 5→10 / 6→10 / 7→10 / 8→10 / 9→10（阶段 2 三表 +
/// FD-05 messages.created_at
/// 索引 + 阶段 3 两表 + MS-01 message_swipes 表与 messages.active_swipe_index
/// 列 + WL-01 lorebook_entries 表与 FK 索引 + NPD-02 characters.preset_dialogues
/// 列与 conversations.preset_dialogue 列 + NPD-04 characters.prompt_mode /
/// characters.expert_prompt 两列 + SP-01 conversations.top_p /
/// presence_penalty / frequency_penalty / max_tokens 四列）；VR-04 追加 from<5
/// 幂等 / 中断自愈 /
/// 级联 / 唯一索引 / 无硬 FK 契约；MS-01 追加 from<6 幂等补列 / 中断自愈 /
/// (message_id, index) 唯一约束 / FK 级联；WL-01 追加 from<7 建表 / 中断自愈 /
/// FK 级联契约；NPD-02 追加 from<8 幂等补列 / 中断自愈 / 重复打开幂等契约；
/// NPD-04 追加 from<9 幂等补两列 / 中断自愈 / 重复打开幂等契约；SP-01 追加
/// from<10 幂等补四列 / 中断自愈 / 重复打开幂等契约。
///
/// 迁移路径用「降级夹具」构造旧版存量库：先在最新 schema 的文件库上插入旧
/// 数据，再 `DROP` 高版本对象 + `PRAGMA user_version = N`，关闭后重新打开 —
/// drift 检测 user_version=N < 5 会执行对应 `from < M` 分支，等价于真实
/// 存量库连续升级。重复打开幂等用同一文件再开验证；全新安装（无表直接建库）
/// 用内存库验证 schemaVersion 直接为最新、不跑 onUpgrade。
library;

import 'dart:io';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/db_meta.dart';

/// 阶段 2 三表名（drift 蛇形约定）。
const _stage2Tables = <String>[
  'relationship_states',
  'proactive_plans',
  'inner_thoughts',
];

/// VR-04 阶段 3 两表名（drift 蛇形约定）。
const _stage3Tables = <String>['embedding_entries', 'semantic_hits'];

/// MS-01 候选表名（drift 蛇形约定）。
const _ms01Tables = <String>['message_swipes'];

/// WL-01 世界书条目表名（drift 蛇形约定）。
const _wl01Tables = <String>['lorebook_entries'];

/// 迁移新增索引锚（snake_case 列名）：6 个阶段 2 FK 索引 + FD-05 的
/// messages.created_at 索引 + VR-04 的 3 个 embedding/semantic 索引 +
/// MS-01 的 message_swipes.message_id FK 索引 + WL-01 的
/// lorebook_entries.character_id FK 索引（drift 不自动为 FK 建索引，
/// raw SQL 补建，对齐 tables.dart @TableIndex）。
const _newIndexes = <String>[
  'idx_relationship_states_character_id',
  'idx_proactive_plans_character_id',
  'idx_proactive_plans_conversation_id',
  'idx_proactive_plans_status',
  'idx_inner_thoughts_character_id',
  'idx_inner_thoughts_message_id',
  'idx_messages_created_at',
  'idx_embedding_entries_character_id',
  'idx_embedding_entries_character_id_content_hash',
  'idx_semantic_hits_character_id',
  'idx_message_swipes_message_id',
  'idx_lorebook_entries_character_id',
];

/// 建一个「v2 存量库」：文件库上建最新 schema → 插旧数据 → 降级到 v2 形态。
///
/// 返回已迁移到 5 的 [AppDatabase] 与临时目录（供 tearDown 清理；db 需
/// 调用方 close）。
Future<(AppDatabase, Directory)> openV2UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('ps2_01_migration_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();

  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '艾莉亚', createdAt: now, updatedAt: now),
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
  await db
      .into(db.messages)
      .insert(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.assistant,
          content: '旅者，你来了。',
          createdAt: now,
        ),
      );
  await db
      .into(db.memoryEntries)
      .insert(
        MemoryEntriesCompanion.insert(
          characterId: character.id,
          kind: MemoryKind.personaFact,
          content: '喜欢旧书店的樟脑味',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.personaRevisions)
      .insert(
        PersonaRevisionsCompanion.insert(
          characterId: character.id,
          personalitySnapshot: '温柔而疏离',
          createdAt: now,
        ),
      );

  // 降级到 v2：标记版本 + 移除阶段 2 三表（索引随表删除）+ 移除
  // messages.created_at 索引（FD-05 属 v4 形态）+ 移除阶段 3 两表与索引
  // （VR-04 属 v5 形态）+ 移除 MS-01 候选表/索引与 active_swipe_index 列
  // （MS-01 属 v6 形态）+ 移除 WL-01 世界书表与索引（属 v7 形态；真实 v2
  // 存量库不含这些对象，保留会导致 `from < M` 分支的 CREATE 语句被
  // IF NOT EXISTS 幂等跳过，掩盖「旧库升级补建」的真实路径）+ 移除 NPD-02
  // 两列（preset_dialogues / preset_dialogue 属 v8 形态）+ 移除 NPD-04 两列
  // （prompt_mode / expert_prompt 属 v9 形态）。
  await db.customStatement('PRAGMA user_version = 2');
  await db.customStatement('DROP TABLE IF EXISTS inner_thoughts');
  await db.customStatement('DROP TABLE IF EXISTS proactive_plans');
  await db.customStatement('DROP TABLE IF EXISTS relationship_states');
  await db.customStatement('DROP TABLE IF EXISTS semantic_hits');
  await db.customStatement('DROP TABLE IF EXISTS embedding_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_messages_created_at');
  await db.customStatement('DROP TABLE IF EXISTS message_swipes');
  await db.customStatement('DROP INDEX IF EXISTS idx_message_swipes_message_id');
  await db.customStatement('ALTER TABLE messages DROP COLUMN active_swipe_index');
  await db.customStatement('DROP TABLE IF EXISTS lorebook_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_lorebook_entries_character_id');
  await db.customStatement('ALTER TABLE characters DROP COLUMN preset_dialogues');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN preset_dialogue');
  await db.customStatement('ALTER TABLE characters DROP COLUMN prompt_mode');
  await db.customStatement('ALTER TABLE characters DROP COLUMN expert_prompt');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v1 存量库」：文件库上建最新 schema → 插 v1 时代数据（无记忆表）→
/// 降级到 v1 形态（user_version=1 + DROP 记忆两表、阶段 2 三表、阶段 3 两表）。
///
/// 打开时 from=1：依次走 `from < 2`（重建记忆两表）、`from < 3`（阶段 2
/// 三表）、`from < 4`（FD-05 索引）、`from < 5`（阶段 3 两表）分支，等价于
/// 真实 v1 存量库连续升级。
Future<(AppDatabase, Directory)> openV1UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('ps2_01_migration_v1_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();

  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '旧识', createdAt: now, updatedAt: now),
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
  await db
      .into(db.messages)
      .insert(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.user,
          content: '从前有座山。',
          createdAt: now,
        ),
      );

  // 降级到 v1：user_version=1 + DROP 记忆两表、阶段 2 三表、阶段 3 两表、
  // MS-01 候选表/索引与 active_swipe_index 列、WL-01 世界书表/索引；
  // 同时移除 messages.created_at 索引（FD-05 属 v4 形态，真实 v1 存量库
  // 不含该索引）+ 移除 NPD-02 两列（属 v8 形态）+ 移除 NPD-04 两列
  // （prompt_mode / expert_prompt 属 v9 形态）。
  await db.customStatement('PRAGMA user_version = 1');
  await db.customStatement('DROP TABLE IF EXISTS inner_thoughts');
  await db.customStatement('DROP TABLE IF EXISTS proactive_plans');
  await db.customStatement('DROP TABLE IF EXISTS relationship_states');
  await db.customStatement('DROP TABLE IF EXISTS persona_revisions');
  await db.customStatement('DROP TABLE IF EXISTS memory_entries');
  await db.customStatement('DROP TABLE IF EXISTS semantic_hits');
  await db.customStatement('DROP TABLE IF EXISTS embedding_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_messages_created_at');
  await db.customStatement('DROP TABLE IF EXISTS message_swipes');
  await db.customStatement('DROP INDEX IF EXISTS idx_message_swipes_message_id');
  await db.customStatement('ALTER TABLE messages DROP COLUMN active_swipe_index');
  await db.customStatement('DROP TABLE IF EXISTS lorebook_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_lorebook_entries_character_id');
  await db.customStatement('ALTER TABLE characters DROP COLUMN preset_dialogues');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN preset_dialogue');
  await db.customStatement('ALTER TABLE characters DROP COLUMN prompt_mode');
  await db.customStatement('ALTER TABLE characters DROP COLUMN expert_prompt');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v4 存量库」：文件库上建最新 schema → 插 v4 时代全 9 表数据 →
/// 降级到 v4 形态（user_version=4 + DROP 阶段 3 两表与 3 索引）。
///
/// 打开时 from=4：仅走 `from < 5` 分支，等价于真实 v4 存量库单步升级；
/// 零回归保证 —— from<1/2/3/4 分支不触发（其幂等性由 v1/v2 夹具承载）。
Future<(AppDatabase, Directory)> openV4UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('vr04_migration_v4_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  await seedV4LegacyRows(db);

  // 降级到 v4：user_version=4 + DROP 阶段 3 两表与其 3 索引（v4 形态不含）
  // + DROP MS-01 候选表/索引与 active_swipe_index 列（MS-01 属 v6 形态）
  // + DROP WL-01 世界书表/索引（属 v7 形态）+ DROP NPD-02 两列（属 v8 形态）
  // + DROP NPD-04 两列（prompt_mode / expert_prompt 属 v9 形态）。
  await db.customStatement('PRAGMA user_version = 4');
  await db.customStatement('DROP TABLE IF EXISTS semantic_hits');
  await db.customStatement('DROP TABLE IF EXISTS embedding_entries');
  await db.customStatement('DROP TABLE IF EXISTS message_swipes');
  await db.customStatement('DROP INDEX IF EXISTS idx_message_swipes_message_id');
  await db.customStatement('ALTER TABLE messages DROP COLUMN active_swipe_index');
  await db.customStatement('DROP TABLE IF EXISTS lorebook_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_lorebook_entries_character_id');
  await db.customStatement('ALTER TABLE characters DROP COLUMN preset_dialogues');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN preset_dialogue');
  await db.customStatement('ALTER TABLE characters DROP COLUMN prompt_mode');
  await db.customStatement('ALTER TABLE characters DROP COLUMN expert_prompt');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v5 存量库」：文件库上建最新 schema → 插 v5 时代全 10 表数据 →
/// 降级到 v5 形态（user_version=5 + DROP message_swipes 表与 FK 索引 +
/// DROP messages.active_swipe_index 列）。
///
/// 打开时 from=5：仅走 `from < 6` 分支（MS-01），等价于真实 v5 存量库单步
/// 升级；零回归保证 —— from<1/2/3/4/5 分支不触发（其幂等性由 v1/v2/v4
/// 夹具承载）。
Future<(AppDatabase, Directory)> openV5UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('ms01_migration_v5_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();
  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '渡鸦', createdAt: now, updatedAt: now),
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
  await db
      .into(db.messages)
      .insertReturning(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.assistant,
          content: '夜航星图，从这里开始。',
          createdAt: now,
        ),
      );

  // 降级到 v5：user_version=5 + DROP message_swipes 表/索引 + DROP
  // active_swipe_index 列（真实 v5 存量库无这些对象；不降列会导致
  // from<6 的补列探测发现列已存在而跳过，掩盖「真实补列」路径）
  // + DROP WL-01 世界书表/索引（属 v7 形态）+ DROP NPD-02 两列（属 v8 形态）
  // + DROP NPD-04 两列（prompt_mode / expert_prompt 属 v9 形态）。
  await db.customStatement('PRAGMA user_version = 5');
  await db.customStatement('DROP TABLE IF EXISTS message_swipes');
  await db.customStatement('DROP INDEX IF EXISTS idx_message_swipes_message_id');
  await db.customStatement('ALTER TABLE messages DROP COLUMN active_swipe_index');
  await db.customStatement('DROP TABLE IF EXISTS lorebook_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_lorebook_entries_character_id');
  await db.customStatement('ALTER TABLE characters DROP COLUMN preset_dialogues');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN preset_dialogue');
  await db.customStatement('ALTER TABLE characters DROP COLUMN prompt_mode');
  await db.customStatement('ALTER TABLE characters DROP COLUMN expert_prompt');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v6 存量库」：文件库上建最新 schema → 插 v6 时代数据 →降级到 v6
/// 形态（user_version=6 + DROP lorebook_entries 表与 FK 索引）。
///
/// 打开时 from=6：仅走 `from < 7` 分支（WL-01），等价于真实 v6 存量库单步
/// 升级；零回归保证 —— from<1/2/3/4/5/6 分支不触发（其幂等性由 v1/v2/v4/v5
/// 夹具承载）。
Future<(AppDatabase, Directory)> openV6UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('wl01_migration_v6_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();
  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '星语', createdAt: now, updatedAt: now),
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
  await db
      .into(db.messages)
      .insertReturning(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.assistant,
          content: '星轨之上，无问西东。',
          createdAt: now,
        ),
      );
  // v6 时代可写一条候选（message_swipes 属 v6 形态，须保留覆盖「升级时
  // 候选行原样保留」）。
  await db
      .into(db.messageSwipes)
      .insertReturning(
        MessageSwipesCompanion.insert(
          messageId: (await db.select(db.messages).getSingle()).id,
          index: 0,
          content: '星轨之上，无问西东。',
          createdAt: now,
        ),
      );

  // 降级到 v6：user_version=6 + DROP WL-01 世界书表/索引（真实 v6 存量库
  // 无这些对象；不 DROP 会导致 from<7 的建表被 IF NOT EXISTS 幂等跳过，
  // 掩盖「旧库升级补建」的真实路径）+ DROP NPD-02 两列（属 v8 形态）
  // + DROP NPD-04 两列（prompt_mode / expert_prompt 属 v9 形态）。
  await db.customStatement('PRAGMA user_version = 6');
  await db.customStatement('DROP TABLE IF EXISTS lorebook_entries');
  await db.customStatement('DROP INDEX IF EXISTS idx_lorebook_entries_character_id');
  await db.customStatement('ALTER TABLE characters DROP COLUMN preset_dialogues');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN preset_dialogue');
  await db.customStatement('ALTER TABLE characters DROP COLUMN prompt_mode');
  await db.customStatement('ALTER TABLE characters DROP COLUMN expert_prompt');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v7 存量库」：文件库上建最新 schema → 插 v7 时代数据 → 降级到 v7
/// 形态（user_version=7 + DROP characters.preset_dialogues 列与
/// conversations.preset_dialogue 列 + DROP prompt_mode / expert_prompt 两列
/// ——NPD-04 两列属 v9 形态）。
///
/// 打开时 from=7：走 `from < 8`（NPD-02）与 `from < 9`（NPD-04）分支，
/// 等价于真实 v7 存量库连续升级到 9。
Future<(AppDatabase, Directory)> openV7UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('npd02_migration_v7_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();
  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '夜莺', createdAt: now, updatedAt: now),
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
  await db
      .into(db.messages)
      .insertReturning(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.assistant,
          content: '夜莺的歌，只在黎明前唱。',
          createdAt: now,
        ),
      );

  // 降级到 v7：user_version=7 + DROP 两列（真实 v7 存量库无 preset_dialogues /
  // preset_dialogue；不 DROP 会导致 from<8 的补列探测发现列已存在而跳过，
  // 掩盖「真实补列」路径）+ DROP NPD-04 两列（属 v9 形态）。
  await db.customStatement('PRAGMA user_version = 7');
  await db.customStatement('ALTER TABLE characters DROP COLUMN preset_dialogues');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN preset_dialogue');
  await db.customStatement('ALTER TABLE characters DROP COLUMN prompt_mode');
  await db.customStatement('ALTER TABLE characters DROP COLUMN expert_prompt');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v8 存量库」：文件库上建最新 schema → 插 v8 时代数据 → 降级到 v8
/// 形态（user_version=8 + DROP characters.prompt_mode / expert_prompt 两列）。
///
/// 打开时 from=8：仅走 `from < 9` 分支（NPD-04），等价于真实 v8 存量库单步
/// 升级；零回归保证 —— from<1/2/3/4/5/6/7/8 分支不触发（其幂等性由 v1/v2/v4/
/// v5/v6/v7 夹具承载）。
Future<(AppDatabase, Directory)> openV8UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('npd04_migration_v8_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();
  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '剑侍', createdAt: now, updatedAt: now),
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
  await db
      .into(db.messages)
      .insertReturning(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.assistant,
          content: '剑出鞘，月如霜。',
          createdAt: now,
        ),
      );

  // 降级到 v8：user_version=8 + DROP 两列（真实 v8 存量库无 prompt_mode /
  // expert_prompt；不 DROP 会导致 from<9 的补列探测发现列已存在而跳过，
  // 掩盖「真实补列」路径）。
  await db.customStatement('PRAGMA user_version = 8');
  await db.customStatement('ALTER TABLE characters DROP COLUMN prompt_mode');
  await db.customStatement('ALTER TABLE characters DROP COLUMN expert_prompt');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 建一个「v9 存量库」：文件库上建最新 schema → 插 v9 时代数据 → 降级到 v9
/// 形态（user_version=9 + DROP conversations.top_p / presence_penalty /
/// frequency_penalty / max_tokens 四列——SP-01 四列属 v10 形态）。
///
/// 打开时 from=9：仅走 `from < 10` 分支（SP-01），等价于真实 v9 存量库单步
/// 升级；零回归保证 —— from<1..9 分支不触发（其幂等性由 v1/v2/v4/v5/v6/v7/v8
/// 夹具承载）。
Future<(AppDatabase, Directory)> openV9UpgradedFixture() async {
  final dir = await Directory.systemTemp.createTemp('sp01_migration_v9_');
  final file = File('${dir.path}${Platform.pathSeparator}test.db');

  var db = AppDatabase(NativeDatabase(file));
  final now = DateTime.now();
  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '星萤', createdAt: now, updatedAt: now),
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
  await db
      .into(db.messages)
      .insertReturning(
        MessagesCompanion.insert(
          conversationId: conversation.id,
          role: Role.assistant,
          content: '星火落处，萤光自明。',
          createdAt: now,
        ),
      );

  // 降级到 v9：user_version=9 + DROP 四列（真实 v9 存量库无 SP-01 四列；
  // 不 DROP 会导致 from<10 的补列探测发现列已存在而跳过，掩盖「真实补列」
  // 路径）。
  await db.customStatement('PRAGMA user_version = 9');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN top_p');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN presence_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN frequency_penalty');
  await db.customStatement('ALTER TABLE conversations DROP COLUMN max_tokens');
  await db.close();

  return (AppDatabase(NativeDatabase(file)), dir);
}

/// 在最新 schema 库上插入 v4 时代 8 张有行表各一行（settings 为空表），
/// 返回 characterId（供级联/唯一约束用例复用）。
Future<int> seedV4LegacyRows(AppDatabase db) async {
  final now = DateTime.now();
  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '阿卡', createdAt: now, updatedAt: now),
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
          content: '风的方向，就是路的方向。',
          createdAt: now,
        ),
      );
  await db
      .into(db.memoryEntries)
      .insert(
        MemoryEntriesCompanion.insert(
          characterId: character.id,
          kind: MemoryKind.episodic,
          content: '在旧都塔顶看过一次日出',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.personaRevisions)
      .insert(
        PersonaRevisionsCompanion.insert(
          characterId: character.id,
          personalitySnapshot: '沉默的向导',
          createdAt: now,
        ),
      );
  await db
      .into(db.relationshipStates)
      .insert(
        RelationshipStatesCompanion.insert(
          characterId: character.id,
          stage: RelationshipStage.acquainted,
          affinity: const Value(35),
          updatedAt: now,
        ),
      );
  await db
      .into(db.proactivePlans)
      .insert(
        ProactivePlansCompanion.insert(
          characterId: character.id,
          conversationId: conversation.id,
          content: '明晨山口见。',
          scheduledAt: now.add(const Duration(hours: 8)),
          sentAt: const Value(null),
          status: ProactivePlanStatus.scheduled,
          messageId: Value(message.id),
        ),
      );
  await db
      .into(db.innerThoughts)
      .insert(
        InnerThoughtsCompanion.insert(
          characterId: character.id,
          messageId: message.id,
          content: '她终于问起塔顶的事了。',
          createdAt: now,
        ),
      );
  return character.id;
}

Future<int> userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.data['user_version'] as int;
}

/// 表列名列表（NPD-02 补列契约断言辅助，按 PRAGMA table_info 行序）。
Future<List<String>> tableColumns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return [for (final row in rows) row.data['name'] as String];
}

/// 插入角色→对话→消息链，并挂上三新表各一行，返回相关 id。
Future<({int characterId, int conversationId, int messageId})> seedFullChain(
  AppDatabase db,
) async {
  final now = DateTime.now();
  final character = await db
      .into(db.characters)
      .insertReturning(
        CharactersCompanion.insert(name: '诺克斯', createdAt: now, updatedAt: now),
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
          role: Role.user,
          content: '你还好吗？',
          createdAt: now,
        ),
      );

  await db
      .into(db.relationshipStates)
      .insert(
        RelationshipStatesCompanion.insert(
          characterId: character.id,
          stage: RelationshipStage.acquainted,
          affinity: const Value(20),
          updatedAt: now,
        ),
      );
  await db
      .into(db.proactivePlans)
      .insert(
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
  await db
      .into(db.innerThoughts)
      .insert(
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

/// 插入一行 embedding + 一行 semantic hit（挂 [characterId]），返回
/// embedding 行的 (id, contentHash) 与 semantic 行 id。
Future<({int embeddingId, String contentHash, int semanticHitId})>
seedVectorRows(AppDatabase db, int characterId) async {
  final now = DateTime.now();
  final embeddingId = await db
      .into(db.embeddingEntries)
      .insertReturning(
        EmbeddingEntriesCompanion.insert(
          characterId: characterId,
          entryId: 7,
          contentSnapshot: '喜欢旧书店的樟脑味',
          vector: Uint8List.fromList(const [0, 0]),
          model: 'text-embedding-3-small',
          dims: 1536,
          contentHash: 'a' * 64,
          createdAt: now,
          updatedAt: now,
        ),
      );
  final semanticHitId = await db
      .into(db.semanticHits)
      .insertReturning(
        SemanticHitsCompanion.insert(
          characterId: characterId,
          entryId: 7,
          query: '去过哪些地方',
          createdAt: now,
        ),
      );
  return (
    embeddingId: embeddingId.id,
    contentHash: embeddingId.contentHash,
    semanticHitId: semanticHitId.id,
  );
}

void main() {
  group('schemaVersion 10 契约（全新安装）', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('AppDatabase.schemaVersion == 10', () {
      expect(db.schemaVersion, 10);
    });

    test('全新安装直接建 13 表 + 12 迁移新增索引（含两个唯一索引）+ NPD-02 '
        '两列 + NPD-04 两列 + SP-01 四列',
        () async {
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
          ..._stage2Tables,
          ..._stage3Tables,
          ..._ms01Tables,
          ..._wl01Tables,
        ]),
      );

      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, containsAll(_newIndexes));

      // NPD-02 两列（schemaVersion 8 形态）：characters.preset_dialogues
      // （JSON 默认 '[]'）+ conversations.preset_dialogue（可空快照）。
      expect(
        await tableColumns(db, 'characters'),
        contains('preset_dialogues'),
      );
      expect(
        await tableColumns(db, 'conversations'),
        contains('preset_dialogue'),
      );

      // NPD-04 两列（schemaVersion 9 形态）：characters.prompt_mode +
      // characters.expert_prompt。
      expect(
        await tableColumns(db, 'characters'),
        containsAll(['prompt_mode', 'expert_prompt']),
      );

      // SP-01 四列（schemaVersion 10 形态）：conversations.top_p /
      // presence_penalty / frequency_penalty / max_tokens。
      expect(
        await tableColumns(db, 'conversations'),
        containsAll(
          ['top_p', 'presence_penalty', 'frequency_penalty', 'max_tokens'],
        ),
      );

      // 两个唯一索引：阶段 2 relationship_states.character_id 与阶段 3
      // embedding_entries (character_id, content_hash)（SR-21 去重前提）。
      for (final name in [
        'idx_relationship_states_character_id',
        'idx_embedding_entries_character_id_content_hash',
      ]) {
        final uniqueSql = await db
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'index' "
              "AND name = '$name'",
            )
            .getSingle();
        expect(
          uniqueSql.data['sql'] as String,
          contains('UNIQUE'),
          reason: '$name 应为唯一索引',
        );
      }
    });
  });

  group('schemaVersion 2→6 迁移', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV2UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('旧行保留 + 13 表/12 索引存在于 sqlite_master + user_version=7', () async {
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      expect(await db.select(db.messages).get().then((r) => r.length), 1);
      expect(await db.select(db.memoryEntries).get().then((r) => r.length), 1);
      expect(
        await db.select(db.personaRevisions).get().then((r) => r.length),
        1,
      );

      final tables = await sqliteMasterNames(db, 'table');
      expect(tables, containsAll([..._stage2Tables, ..._stage3Tables, ..._wl01Tables]));

      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, containsAll(_newIndexes));

      expect(await userVersion(db), 10);
    });

    test('三表可读写 + converter 字符串落库（stage 五值 / status 四值）', () async {
      final now = DateTime.now();

      for (final stage in RelationshipStage.values) {
        final character = await db
            .into(db.characters)
            .insertReturning(
              CharactersCompanion.insert(
                name: 'stage-${stage.value}',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.relationshipStates)
            .insert(
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
        await db
            .into(db.proactivePlans)
            .insert(
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
      await db
          .into(db.innerThoughts)
          .insert(
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
      final rawStages = await db
          .customSelect('SELECT stage FROM relationship_states ORDER BY id')
          .get();
      expect(
        rawStages.map((row) => row.data['stage']),
        RelationshipStage.values.map((s) => s.value),
      );
      final rawStatuses = await db
          .customSelect('SELECT status FROM proactive_plans ORDER BY id')
          .get();
      expect(
        rawStatuses.map((row) => row.data['status']),
        ProactivePlanStatus.values.map((s) => s.value),
      );
    });

    test('relationship_states 唯一索引拒绝重复角色行', () async {
      final now = DateTime.now();
      final character = await db
          .into(db.characters)
          .insertReturning(
            CharactersCompanion.insert(
              name: '唯一',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.relationshipStates)
          .insert(
            RelationshipStatesCompanion.insert(
              characterId: character.id,
              stage: RelationshipStage.stranger,
              updatedAt: now,
            ),
          );

      await expectLater(
        db
            .into(db.relationshipStates)
            .insert(
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

      await (db.delete(
        db.characters,
      )..where((t) => t.id.equals(ids.characterId))).go();

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

      await (db.delete(
        db.messages,
      )..where((t) => t.id.equals(ids.messageId))).go();

      final plan = await db.select(db.proactivePlans).getSingle();
      expect(plan.messageId, isNull);
      expect(plan.status, ProactivePlanStatus.scheduled);
      expect(await db.select(db.innerThoughts).get(), isEmpty);
    });

    test('中断残留重开自愈：部分建表落盘即关闭 → 重开幂等补全且旧行保留', () async {
      // 模拟迁移中途被杀留下的残留态：仅 relationship_states 表与其唯一
      // 索引落盘（onUpgrade 顺序中已执行到 createTable 之后、后续两表
      // 之前），其余表/索引缺失，user_version 未提升（仍为 2）。
      await db.customStatement('DROP TABLE IF EXISTS proactive_plans');
      await db.customStatement('DROP TABLE IF EXISTS inner_thoughts');
      await db.customStatement('DROP TABLE IF EXISTS semantic_hits');
      await db.customStatement('DROP TABLE IF EXISTS embedding_entries');
      await db.customStatement('PRAGMA user_version = 2');

      // 前置断言：确认残留态真实存在，否则「重开自愈」无从谈起。
      final residualTables = await sqliteMasterNames(db, 'table');
      expect(residualTables, contains('relationship_states'));
      expect(residualTables, isNot(contains('proactive_plans')));
      expect(residualTables, isNot(contains('inner_thoughts')));
      expect(residualTables, isNot(contains('embedding_entries')));
      expect(residualTables, isNot(contains('semantic_hits')));
      final residualIndexes = await sqliteMasterNames(db, 'index');
      expect(residualIndexes, contains('idx_relationship_states_character_id'));
      expect(
        residualIndexes,
        isNot(contains('idx_proactive_plans_character_id')),
      );
      expect(await userVersion(db), 2);

      // 重开：drift 检测 user_version=2 < 5 重跑 from < 3/4/5 分支，
      // IF NOT EXISTS 幂等补建缺失的表/索引；成功后再把 user_version
      // 回写为 5。
      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await sqliteMasterNames(db, 'table'),
        containsAll([..._stage2Tables, ..._stage3Tables]),
      );
      expect(await sqliteMasterNames(db, 'index'), containsAll(_newIndexes));

      // 残留唯一索引原样保留（IF NOT EXISTS 跳过而非重建）。
      final uniqueSql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_relationship_states_character_id'",
          )
          .getSingle();
      expect(uniqueSql.data['sql'] as String, contains('UNIQUE'));

      // 旧行保留：v2 时代五张表数据均可读。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      expect(await db.select(db.messages).get().then((r) => r.length), 1);
      expect(await db.select(db.memoryEntries).get().then((r) => r.length), 1);
      expect(
        await db.select(db.personaRevisions).get().then((r) => r.length),
        1,
      );
    });

    test('重复打开幂等：同文件重开不重跑迁移，表与数据仍在', () async {
      // 当前 db 已迁移到 5；写入一行标识数据后关闭再重开。
      final now = DateTime.now();
      await db
          .into(db.relationshipStates)
          .insert(
            RelationshipStatesCompanion.insert(
              characterId: (await db.select(db.characters).getSingle()).id,
              stage: RelationshipStage.stranger,
              updatedAt: now,
            ),
          );
      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await sqliteMasterNames(db, 'table'),
        containsAll([..._stage2Tables, ..._stage3Tables]),
      );
      expect(await sqliteMasterNames(db, 'index'), containsAll(_newIndexes));
      expect(await db.select(db.relationshipStates).get(), hasLength(1));
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
    });
  });

  group('schemaVersion 1→6 连续迁移', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV1UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v1 存量库连续升级：记忆两表重建 + 三新表 + 两新表 + 世界书表 + 旧行保留 + user_version=7', () async {
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.messages).get().then((r) => r.length), 1);

      final tables = await sqliteMasterNames(db, 'table');
      expect(
        tables,
        containsAll([
          'memory_entries',
          'persona_revisions',
          ..._stage2Tables,
          ..._stage3Tables,
        ]),
      );
      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, containsAll(_newIndexes));
      expect(await userVersion(db), 10);
    });
  });

  group('schemaVersion 4→6 迁移（VR-04）', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV4UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v4 存量库升级四要素：两表/3 索引存在 + user_version=7 + 旧行保留', () async {
      // 旧行保留：v4 时代 8 张有行表各自数据完整可读。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      expect(await db.select(db.messages).get().then((r) => r.length), 1);
      expect(await db.select(db.memoryEntries).get().then((r) => r.length), 1);
      expect(
        await db.select(db.personaRevisions).get().then((r) => r.length),
        1,
      );
      expect(
        await db.select(db.relationshipStates).get().then((r) => r.length),
        1,
      );
      expect(await db.select(db.proactivePlans).get().then((r) => r.length), 1);
      expect(await db.select(db.innerThoughts).get().then((r) => r.length), 1);

      final tables = await sqliteMasterNames(db, 'table');
      expect(tables, containsAll(_stage3Tables));

      final indexes = await sqliteMasterNames(db, 'index');
      expect(
        indexes,
        containsAll([
          'idx_embedding_entries_character_id',
          'idx_embedding_entries_character_id_content_hash',
          'idx_semantic_hits_character_id',
        ]),
      );

      expect(await userVersion(db), 10);
    });

    test(
      '两表可读写：vector blob 往返 + model/dims/contentHash 指纹 + query 快照',
      () async {
        final characterId = (await db.select(db.characters).getSingle()).id;
        final now = DateTime.now();

        final embedding = await db
            .into(db.embeddingEntries)
            .insertReturning(
              EmbeddingEntriesCompanion.insert(
                characterId: characterId,
                entryId: 11,
                contentSnapshot: '在旧都塔顶看过一次日出',
                vector: Uint8List.fromList(const [64, 0, 0, 0]),
                model: 'text-embedding-3-small',
                dims: 1536,
                contentHash: 'b' * 64,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.semanticHits)
            .insert(
              SemanticHitsCompanion.insert(
                characterId: characterId,
                entryId: 11,
                query: '看过日出吗',
                createdAt: now,
              ),
            );

        final stored = await db.select(db.embeddingEntries).getSingle();
        expect(stored.entryId, 11);
        expect(stored.contentSnapshot, '在旧都塔顶看过一次日出');
        expect(stored.vector, Uint8List.fromList(const [64, 0, 0, 0]));
        expect(stored.model, 'text-embedding-3-small');
        expect(stored.dims, 1536);
        expect(stored.contentHash, 'b' * 64);
        expect(stored.id, embedding.id);

        final hit = await db.select(db.semanticHits).getSingle();
        expect(hit.entryId, 11);
        expect(hit.query, '看过日出吗');
        expect(hit.characterId, characterId);
      },
    );

    test('(characterId, contentHash) 唯一索引拒绝同角色同内容重复行（SR-21）', () async {
      final characterId = (await db.select(db.characters).getSingle()).id;
      final now = DateTime.now();

      await seedVectorRows(db, characterId);

      await expectLater(
        db
            .into(db.embeddingEntries)
            .insert(
              EmbeddingEntriesCompanion.insert(
                characterId: characterId,
                entryId: 8,
                contentSnapshot: '与首行相同 hash 的另一快照',
                vector: Uint8List.fromList(const [0, 0]),
                model: 'text-embedding-3-small',
                dims: 1536,
                contentHash: 'a' * 64,
                createdAt: now,
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

      // 同 hash 不同角色可共存（唯一键是 (characterId, contentHash) 组合）。
      final other = await db
          .into(db.characters)
          .insertReturning(
            CharactersCompanion.insert(
              name: '另一角色',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.embeddingEntries)
          .insert(
            EmbeddingEntriesCompanion.insert(
              characterId: other.id,
              entryId: 8,
              contentSnapshot: '同 hash 其他角色',
              vector: Uint8List.fromList(const [0, 0]),
              model: 'text-embedding-3-small',
              dims: 1536,
              contentHash: 'a' * 64,
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    test('entryId 无硬 FK：悬空 memory_entries id 可插入（逻辑回指）', () async {
      final characterId = (await db.select(db.characters).getSingle()).id;
      final now = DateTime.now();

      await expectLater(
        db
            .into(db.embeddingEntries)
            .insert(
              EmbeddingEntriesCompanion.insert(
                characterId: characterId,
                entryId: 999999,
                contentSnapshot: '悬空 entryId',
                vector: Uint8List.fromList(const [1, 2]),
                model: 'text-embedding-3-small',
                dims: 1536,
                contentHash: 'c' * 64,
                createdAt: now,
                updatedAt: now,
              ),
            ),
        completes,
      );
      final row = await db.select(db.embeddingEntries).getSingle();
      expect(row.entryId, 999999);
      expect(row.contentSnapshot, '悬空 entryId');
    });

    test('删角色 → embedding_entries 与 semantic_hits 级联清空（FK=ON 实测）', () async {
      final characterId = (await db.select(db.characters).getSingle()).id;
      await seedVectorRows(db, characterId);

      expect(await db.select(db.embeddingEntries).get(), hasLength(1));
      expect(await db.select(db.semanticHits).get(), hasLength(1));

      await (db.delete(
        db.characters,
      )..where((t) => t.id.equals(characterId))).go();

      // beforeOpen `PRAGMA foreign_keys = ON` 生效：级联删除实测断言。
      expect(await db.select(db.embeddingEntries).get(), isEmpty);
      expect(await db.select(db.semanticHits).get(), isEmpty);
      expect(await db.select(db.memoryEntries).get(), isEmpty);
      expect(await db.select(db.relationshipStates).get(), isEmpty);
    });

    test('中断残留重开自愈：embedding 表落盘即中断 → 重开补全四要素', () async {
      // 模拟 from<5 迁移中途被杀留下的残留态：仅 embedding_entries 表与其
      // character_id 索引落盘（onUpgrade 顺序中已执行到 createTable 与首个
      // 索引之后、semantic_hits 建表与其他索引之前），唯一索引缺失、
      // semantic_hits 缺失、user_version 未提升（仍为 4）。
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_embedding_entries_character_id_content_hash',
      );
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_semantic_hits_character_id',
      );
      await db.customStatement('DROP TABLE IF EXISTS semantic_hits');
      await db.customStatement('PRAGMA user_version = 4');

      // 前置断言：确认残留态真实存在。
      final residualTables = await sqliteMasterNames(db, 'table');
      expect(residualTables, contains('embedding_entries'));
      expect(residualTables, isNot(contains('semantic_hits')));
      final residualIndexes = await sqliteMasterNames(db, 'index');
      expect(residualIndexes, contains('idx_embedding_entries_character_id'));
      expect(
        residualIndexes,
        isNot(contains('idx_embedding_entries_character_id_content_hash')),
      );
      expect(
        residualIndexes,
        isNot(contains('idx_semantic_hits_character_id')),
      );
      expect(await userVersion(db), 4);

      // 重开：drift 检测 user_version=4 < 5 重跑 from < 5 分支，IF NOT
      // EXISTS 幂等补建缺失的表/索引；成功后把 user_version 回写为 5。
      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(await sqliteMasterNames(db, 'table'), containsAll(_stage3Tables));
      expect(
        await sqliteMasterNames(db, 'index'),
        containsAll([
          'idx_embedding_entries_character_id',
          'idx_embedding_entries_character_id_content_hash',
          'idx_semantic_hits_character_id',
        ]),
      );

      // 补建的唯一索引真是 UNIQUE（IF NOT EXISTS 恢复完整语义）。
      final uniqueSql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_embedding_entries_character_id_content_hash'",
          )
          .getSingle();
      expect(uniqueSql.data['sql'] as String, contains('UNIQUE'));

      // 旧行保留：v4 时代数据仍完整。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.memoryEntries).get().then((r) => r.length), 1);
      expect(await db.select(db.proactivePlans).get().then((r) => r.length), 1);
    });

    test('幂等二跑：迁移完成后同文件重开不重跑迁移、数据仍在', () async {
      final characterId = (await db.select(db.characters).getSingle()).id;
      final now = DateTime.now();
      await db
          .into(db.embeddingEntries)
          .insert(
            EmbeddingEntriesCompanion.insert(
              characterId: characterId,
              entryId: 21,
              contentSnapshot: '二跑标识行',
              vector: Uint8List.fromList(const [9, 9]),
              model: 'text-embedding-3-small',
              dims: 1536,
              contentHash: 'd' * 64,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(await sqliteMasterNames(db, 'table'), containsAll(_stage3Tables));
      expect(await sqliteMasterNames(db, 'index'), containsAll(_newIndexes));
      final stored = await db.select(db.embeddingEntries).getSingle();
      expect(stored.contentSnapshot, '二跑标识行');
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
    });
  });

  group('schemaVersion 5→6 迁移（MS-01）', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV5UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v5 存量库升级四要素：表 + 列 + FK 索引存在 + user_version=7 + 旧行保留',
        () async {
      // 旧行保留：v5 时代行仍完整可读（messages.content 原样，未被迁移改写）。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      final message = await db.select(db.messages).getSingle();
      expect(message.content, '夜航星图，从这里开始。');
      // 存量消息补列后 active_swipe_index = 0（桌面 server_default '0' 语义）。
      expect(message.activeSwipeIndex, 0);

      final tables = await sqliteMasterNames(db, 'table');
      expect(tables, contains('message_swipes'));

      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, contains('idx_message_swipes_message_id'));

      expect(await userVersion(db), 10);
    });

    test('message_swipes 可写读 + (message_id, index) 唯一约束生效（SR-27）', () async {
      final message = await db.select(db.messages).getSingle();
      final now = DateTime.now();

      await db.into(db.messageSwipes).insert(
            MessageSwipesCompanion.insert(
              messageId: message.id,
              index: 0,
              content: message.content,
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
      expect(swipe.content, '候选一');

      await expectLater(
        db.into(db.messageSwipes).insert(
              MessageSwipesCompanion.insert(
                messageId: message.id,
                index: 1,
                content: '重复 index',
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
    });

    test('删消息 → message_swipes 级联清除（FK=ON 实测）', () async {
      final message = await db.select(db.messages).getSingle();
      final now = DateTime.now();
      await db.into(db.messageSwipes).insert(
            MessageSwipesCompanion.insert(
              messageId: message.id,
              index: 0,
              content: message.content,
              createdAt: now,
            ),
          );
      expect(await db.select(db.messageSwipes).get(), hasLength(1));

      await (db.delete(
        db.messages,
      )..where((t) => t.id.equals(message.id))).go();

      expect(await db.select(db.messageSwipes).get(), isEmpty);
    });

    test('中断残留重开自愈：列已补、表未建 → 重开幂等补全且旧行保留（SR-25）',
        () async {
      // 模拟 from<6 迁移中途被杀残留态：active_swipe_index 列已补（ALTER
      // 成功），message_swipes 表与其索引未落盘（后续 DDL 未执行），
      // user_version 未提升（仍为 5）。重开时补列探测发现列已存在 →
      // 幂等跳过（不 duplicate column），IF NOT EXISTS 补建表与索引。
      await db.customStatement('PRAGMA user_version = 5');
      await db.customStatement('DROP TABLE IF EXISTS message_swipes');
      await db.customStatement('DROP INDEX IF EXISTS idx_message_swipes_message_id');

      // 前置断言：确认残留态真实存在。
      final residualTables = await sqliteMasterNames(db, 'table');
      expect(residualTables, isNot(contains('message_swipes')));
      final residualIndexes = await sqliteMasterNames(db, 'index');
      expect(
        residualIndexes,
        isNot(contains('idx_message_swipes_message_id')),
      );
      expect(await userVersion(db), 5);
      final columns = await db.customSelect('PRAGMA table_info(messages)').get();
      expect(
        columns.any((row) => row.data['name'] == 'active_swipe_index'),
        isTrue,
        reason: '残留态应含已补列，否则未覆盖「补列后中断」路径',
      );

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await sqliteMasterNames(db, 'table'),
        contains('message_swipes'),
      );
      expect(
        await sqliteMasterNames(db, 'index'),
        contains('idx_message_swipes_message_id'),
      );
      // 旧行保留 + 补列值默认 0。
      final message = await db.select(db.messages).getSingle();
      expect(message.content, '夜航星图，从这里开始。');
      expect(message.activeSwipeIndex, 0);
    });

    test('重复打开幂等：同文件重开不重跑迁移，表/列/数据仍在', () async {
      final message = await db.select(db.messages).getSingle();
      final now = DateTime.now();
      await db.into(db.messageSwipes).insert(
            MessageSwipesCompanion.insert(
              messageId: message.id,
              index: 0,
              content: message.content,
              createdAt: now,
            ),
          );

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await sqliteMasterNames(db, 'table'),
        contains('message_swipes'),
      );
      expect(
        await sqliteMasterNames(db, 'index'),
        contains('idx_message_swipes_message_id'),
      );
      final stored = await db.select(db.messageSwipes).getSingle();
      expect(stored.content, '夜航星图，从这里开始。');
    });
  });

  group('schemaVersion 6→7 迁移（WL-01）', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV6UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v6 存量库升级四要素：世界书表 + FK 索引存在 + user_version=7 + 旧行保留',
        () async {
      // 旧行保留：v6 时代消息与候选行仍完整可读，未被迁移改写。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      final message = await db.select(db.messages).getSingle();
      expect(message.content, '星轨之上，无问西东。');
      final swipe = await db.select(db.messageSwipes).getSingle();
      expect(swipe.content, '星轨之上，无问西东。');

      final tables = await sqliteMasterNames(db, 'table');
      expect(tables, contains('lorebook_entries'));

      final indexes = await sqliteMasterNames(db, 'index');
      expect(indexes, contains('idx_lorebook_entries_character_id'));

      expect(await userVersion(db), 10);
    });

    test('lorebook_entries 可写读 + keys JSON 数组往返', () async {
      final characterId = (await db.select(db.characters).getSingle()).id;
      final now = DateTime.now();
      final created = await db.into(db.lorebookEntries).insertReturning(
            LorebookEntriesCompanion.insert(
              characterId: characterId,
              keys: const Value(['酒馆', 'tavern']),
              content: const Value('酒馆的老板是莉莉。'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect(created.keys, ['酒馆', 'tavern']);
      expect(created.position, 'world', reason: '缺省默认');
      expect(created.enabled, isTrue);
    });

    test('删角色 → lorebook_entries 级联清除（FK=ON 实测，SR-26）', () async {
      final characterId = (await db.select(db.characters).getSingle()).id;
      final now = DateTime.now();
      await db.into(db.lorebookEntries).insert(
            LorebookEntriesCompanion.insert(
              characterId: characterId,
              title: const Value('条目1'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.lorebookEntries).insert(
            LorebookEntriesCompanion.insert(
              characterId: characterId,
              title: const Value('条目2'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect(await db.select(db.lorebookEntries).get(), hasLength(2));

      await (db.delete(
        db.characters,
      )..where((t) => t.id.equals(characterId))).go();

      expect(await db.select(db.lorebookEntries).get(), isEmpty);
    });

    test('中断残留重开自愈：表缺 + 索引缺 → 重开幂等补全且旧行保留（SR-25）',
        () async {
      // 模拟 from<7 迁移中途被杀残留态：user_version 未提升（仍为 6），
      // lorebook_entries 表与其索引未落盘（DDL 未执行）。
      await db.customStatement('PRAGMA user_version = 6');
      await db.customStatement('DROP TABLE IF EXISTS lorebook_entries');
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_lorebook_entries_character_id',
      );

      // 前置断言：确认残留态真实存在。
      final residualTables = await sqliteMasterNames(db, 'table');
      expect(residualTables, isNot(contains('lorebook_entries')));
      final residualIndexes = await sqliteMasterNames(db, 'index');
      expect(
        residualIndexes,
        isNot(contains('idx_lorebook_entries_character_id')),
      );
      expect(await userVersion(db), 6);

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await sqliteMasterNames(db, 'table'),
        contains('lorebook_entries'),
      );
      expect(
        await sqliteMasterNames(db, 'index'),
        contains('idx_lorebook_entries_character_id'),
      );
      // 旧行保留：v6 时代消息原样可读。
      final message = await db.select(db.messages).getSingle();
      expect(message.content, '星轨之上，无问西东。');
    });

    test('重复打开幂等：同文件重开不重跑迁移，表/索引/数据仍在', () async {
      final characterId = (await db.select(db.characters).getSingle()).id;
      final now = DateTime.now();
      await db.into(db.lorebookEntries).insert(
            LorebookEntriesCompanion.insert(
              characterId: characterId,
              title: const Value('唯一条目'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await sqliteMasterNames(db, 'table'),
        contains('lorebook_entries'),
      );
      expect(
        await sqliteMasterNames(db, 'index'),
        contains('idx_lorebook_entries_character_id'),
      );
      final stored = await db.select(db.lorebookEntries).getSingle();
      expect(stored.title, '唯一条目');
    });
  });

  group('schemaVersion 7→8 迁移（NPD-02）', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV7UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v7 存量库升级四要素：两列存在 + user_version=8 + 旧行保留 + 新列默认',
        () async {
      // 旧行保留：v7 时代行原样可读，未被迁移改写。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      final message = await db.select(db.messages).getSingle();
      expect(message.content, '夜莺的歌，只在黎明前唱。');

      // 两列存在。
      expect(
        await tableColumns(db, 'characters'),
        contains('preset_dialogues'),
      );
      expect(
        await tableColumns(db, 'conversations'),
        contains('preset_dialogue'),
      );

      // 存量行新列默认：characters.preset_dialogues = []（JSON '[]'），
      // conversations.preset_dialogue = null（既有行 NULL 零影响）。
      final character = await db.select(db.characters).getSingle();
      expect(character.presetDialogues, isEmpty);
      final conversation = await db.select(db.conversations).getSingle();
      expect(conversation.presetDialogue, isNull);

      expect(await userVersion(db), 10);
    });

    test('两列可写读：preset_dialogues JSON 往返 + preset_dialogue 快照', () async {
      final character = await db.select(db.characters).getSingle();
      final conversation = await db.select(db.conversations).getSingle();

      await (db.update(db.characters)..where((t) => t.id.equals(character.id)))
          .write(
            CharactersCompanion(
              presetDialogues: const Value([
                {'name': '寒暄', 'content': '你好。'},
              ]),
            ),
          );
      final storedChar = await db.select(db.characters).getSingle();
      expect(storedChar.presetDialogues, [
        {'name': '寒暄', 'content': '你好。'},
      ]);

      await (db.update(db.conversations)
            ..where((t) => t.id.equals(conversation.id)))
          .write(
            ConversationsCompanion(
              presetDialogue: const Value('<START>\n{{user}}: 你好\n{{char}}: 欢迎'),
            ),
          );
      final storedConv = await db.select(db.conversations).getSingle();
      expect(storedConv.presetDialogue, '<START>\n{{user}}: 你好\n{{char}}: 欢迎');
      expect(conversation.presetDialogue, isNull, reason: '更新前快照为空');
    });

    test('中断残留重开自愈：一列已补、一列未补 → 重开幂等补全且旧行保留（SR-25）',
        () async {
      // 模拟 from<8 迁移中途被杀残留态：characters.preset_dialogues 列已补
      // （ALTER 成功），conversations.preset_dialogue 未补（后续 DDL 未执行），
      // user_version 未提升（仍为 7）。重开时补列探测发现 preset_dialogues
      // 已存在 → 幂等跳过（不 duplicate column），补上 preset_dialogue。
      await db.customStatement(
        'ALTER TABLE conversations DROP COLUMN preset_dialogue',
      );
      await db.customStatement('PRAGMA user_version = 7');

      // 前置断言：确认残留态真实存在。
      final residualCharColumns = await tableColumns(db, 'characters');
      expect(residualCharColumns, contains('preset_dialogues'));
      final residualConvColumns = await tableColumns(db, 'conversations');
      expect(residualConvColumns, isNot(contains('preset_dialogue')));
      expect(await userVersion(db), 7, reason: '残留态 user_version 未提升');

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(await tableColumns(db, 'characters'), contains('preset_dialogues'));
      expect(await tableColumns(db, 'conversations'), contains('preset_dialogue'));
      // 旧行保留 + 存量行新列默认。
      final character = await db.select(db.characters).getSingle();
      expect(character.presetDialogues, isEmpty);
      final conversation = await db.select(db.conversations).getSingle();
      expect(conversation.presetDialogue, isNull);
      expect(
        (await db.select(db.messages).getSingle()).content,
        '夜莺的歌，只在黎明前唱。',
      );
    });

    test('重复打开幂等：同文件重开不重跑迁移，列/数据仍在（验收 7）', () async {
      final character = await db.select(db.characters).getSingle();
      await (db.update(db.characters)..where((t) => t.id.equals(character.id)))
          .write(
            CharactersCompanion(
              presetDialogues: const Value([
                {'name': '唯一', 'content': '内容'},
              ]),
            ),
          );

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(await tableColumns(db, 'characters'), contains('preset_dialogues'));
      expect(await tableColumns(db, 'conversations'), contains('preset_dialogue'));
      final stored = await db.select(db.characters).getSingle();
      expect(stored.presetDialogues, [
        {'name': '唯一', 'content': '内容'},
      ]);
    });
  });

  group('schemaVersion 8→9 迁移（NPD-04）', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV8UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v8 存量库升级四要素：两列存在 + user_version=9 + 旧行保留 + 新列默认',
        () async {
      // 旧行保留：v8 时代行原样可读，未被迁移改写。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      final message = await db.select(db.messages).getSingle();
      expect(message.content, '剑出鞘，月如霜。');

      // 两列存在。
      expect(
        await tableColumns(db, 'characters'),
        containsAll(['prompt_mode', 'expert_prompt']),
      );

      // 存量行新列默认：prompt_mode = 'simple'（验收 1 既有行默认 simple），
      // expert_prompt = ''。
      final character = await db.select(db.characters).getSingle();
      expect(character.promptMode, 'simple');
      expect(character.expertPrompt, '');

      expect(await userVersion(db), 10);
    });

    test('两列可写读：prompt_mode / expert_prompt 往返（prompt_mode=expert + '
        '非空 expert_prompt）', () async {
      final character = await db.select(db.characters).getSingle();

      await (db.update(db.characters)..where((t) => t.id.equals(character.id)))
          .write(
            CharactersCompanion(
              promptMode: const Value('expert'),
              expertPrompt: const Value('你是{{char}}，月下剑客。'),
            ),
          );
      final stored = await db.select(db.characters).getSingle();
      expect(stored.promptMode, 'expert');
      expect(stored.expertPrompt, '你是{{char}}，月下剑客。');
    });

    test('中断残留重开自愈：一列已补、一列未补 → 重开幂等补全且旧行保留（SR-25）',
        () async {
      // 模拟 from<9 迁移中途被杀残留态：prompt_mode 列已补（ALTER 成功），
      // expert_prompt 未补（后续 DDL 未执行），user_version 未提升（仍为 8）。
      // 重开时补列探测发现 prompt_mode 已存在 → 幂等跳过（不 duplicate
      // column），补上 expert_prompt。
      await db.customStatement(
        'ALTER TABLE characters DROP COLUMN expert_prompt',
      );
      await db.customStatement('PRAGMA user_version = 8');

      // 前置断言：确认残留态真实存在。
      final residualColumns = await tableColumns(db, 'characters');
      expect(residualColumns, contains('prompt_mode'));
      expect(residualColumns, isNot(contains('expert_prompt')));
      expect(await userVersion(db), 8, reason: '残留态 user_version 未提升');

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await tableColumns(db, 'characters'),
        containsAll(['prompt_mode', 'expert_prompt']),
      );
      // 旧行保留 + 存量行新列默认。
      final character = await db.select(db.characters).getSingle();
      expect(character.promptMode, 'simple');
      expect(character.expertPrompt, '');
      expect(
        (await db.select(db.messages).getSingle()).content,
        '剑出鞘，月如霜。',
      );
    });

    test('重复打开幂等：同文件重开不重跑迁移，列/数据仍在（验收 8）', () async {
      final character = await db.select(db.characters).getSingle();
      await (db.update(db.characters)..where((t) => t.id.equals(character.id)))
          .write(
            CharactersCompanion(
              promptMode: const Value('expert'),
              expertPrompt: const Value('整段提示'),
            ),
          );

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await tableColumns(db, 'characters'),
        containsAll(['prompt_mode', 'expert_prompt']),
      );
      final stored = await db.select(db.characters).getSingle();
      expect(stored.promptMode, 'expert');
      expect(stored.expertPrompt, '整段提示');
    });
  });

  group('schemaVersion 9→10 迁移（SP-01）', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      (db, dir) = await openV9UpgradedFixture();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('v9 存量库升级四要素：四列存在 + user_version=10 + 旧行保留 + 存量行新列 NULL',
        () async {
      // 旧行保留：v9 时代行原样可读，未被迁移改写。
      expect(await db.select(db.characters).get().then((r) => r.length), 1);
      expect(await db.select(db.conversations).get().then((r) => r.length), 1);
      final message = await db.select(db.messages).getSingle();
      expect(message.content, '星火落处，萤光自明。');

      // 四列存在（snake_case 名）。
      expect(
        await tableColumns(db, 'conversations'),
        containsAll(
          ['top_p', 'presence_penalty', 'frequency_penalty', 'max_tokens'],
        ),
      );

      // 存量行新列 = NULL（可空列无默认 → 既有行 NULL 零影响，NULL = 不覆盖
      // provider 默认）。
      final conversation = await db.select(db.conversations).getSingle();
      expect(conversation.topP, isNull);
      expect(conversation.presencePenalty, isNull);
      expect(conversation.frequencyPenalty, isNull);
      expect(conversation.maxTokens, isNull);

      expect(await userVersion(db), 10);
    });

    test('四列可写读：top_p / presence_penalty / frequency_penalty / max_tokens 往返',
        () async {
      final conversation = await db.select(db.conversations).getSingle();

      await (db.update(db.conversations)
            ..where((t) => t.id.equals(conversation.id)))
          .write(
            ConversationsCompanion(
              topP: const Value(0.35),
              presencePenalty: const Value(-1.0),
              frequencyPenalty: const Value(1.75),
              maxTokens: const Value(768),
            ),
          );
      final stored = await db.select(db.conversations).getSingle();
      expect(stored.topP, 0.35);
      expect(stored.presencePenalty, -1.0);
      expect(stored.frequencyPenalty, 1.75);
      expect(stored.maxTokens, 768);
    });

    test('中断残留重开自愈：一列已补、其余未补 → 重开幂等补全且旧行保留（SR-25）',
        () async {
      // 模拟 from<10 迁移中途被杀残留态：top_p 列已补（ALTER 成功），
      // presence_penalty / frequency_penalty / max_tokens 未补（后续 DDL
      // 未执行），user_version 未提升（仍为 9）。重开时补列探测发现 top_p
      // 已存在 → 幂等跳过（不 duplicate column），补齐其余三列。
      await db.customStatement(
        'ALTER TABLE conversations DROP COLUMN presence_penalty',
      );
      await db.customStatement(
        'ALTER TABLE conversations DROP COLUMN frequency_penalty',
      );
      await db.customStatement(
        'ALTER TABLE conversations DROP COLUMN max_tokens',
      );
      await db.customStatement('PRAGMA user_version = 9');

      // 前置断言：确认残留态真实存在。
      final residualColumns = await tableColumns(db, 'conversations');
      expect(residualColumns, contains('top_p'));
      expect(residualColumns, isNot(contains('presence_penalty')));
      expect(residualColumns, isNot(contains('frequency_penalty')));
      expect(residualColumns, isNot(contains('max_tokens')));
      expect(await userVersion(db), 9, reason: '残留态 user_version 未提升');

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await tableColumns(db, 'conversations'),
        containsAll(
          ['top_p', 'presence_penalty', 'frequency_penalty', 'max_tokens'],
        ),
      );
      // 旧行保留 + 存量行新列默认 NULL。
      final conversation = await db.select(db.conversations).getSingle();
      expect(conversation.topP, isNull);
      expect(conversation.maxTokens, isNull);
      expect(
        (await db.select(db.messages).getSingle()).content,
        '星火落处，萤光自明。',
      );
    });

    test('重复打开幂等：同文件重开不重跑迁移，列/数据仍在（验收 8）', () async {
      final conversation = await db.select(db.conversations).getSingle();
      await (db.update(db.conversations)
            ..where((t) => t.id.equals(conversation.id)))
          .write(
            ConversationsCompanion(
              topP: const Value(0.9),
              maxTokens: const Value(4096),
            ),
          );

      await db.close();
      db = AppDatabase(
        NativeDatabase(File('${dir.path}${Platform.pathSeparator}test.db')),
      );

      expect(await userVersion(db), 10);
      expect(
        await tableColumns(db, 'conversations'),
        containsAll(
          ['top_p', 'presence_penalty', 'frequency_penalty', 'max_tokens'],
        ),
      );
      final stored = await db.select(db.conversations).getSingle();
      expect(stored.topP, 0.9);
      expect(stored.maxTokens, 4096);
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
