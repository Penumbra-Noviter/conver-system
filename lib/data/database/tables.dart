/// drift 表定义 — 前四表与桌面端 ORM 逐字段对齐（schemaVersion=1 冻结）；
/// MemoryEntries / PersonaRevisions 为人机恋板块（ADR-0003）移动端先行表
/// （schemaVersion=2，桌面无对应物）；RelationshipStates / ProactivePlans /
/// InnerThoughts 为阶段 2 三表（schemaVersion=3，spec §3，桌面无对应物）；
/// Messages.created_at 单列索引为 FD-05（schemaVersion=4）；
/// EmbeddingEntries / SemanticHits 为阶段 3 两表（schemaVersion=5，
/// stage3-vector-recall spec §2 D2，桌面无对应物）；
/// MessageSwipes 候选表 + Messages.active_swipe_index 为 MS-01（schemaVersion=6，
/// chat-polish spec §4.2，对齐桌面 message.py::MessageSwipe）。
///
/// 权威源（只读，勿改）：
/// `desktop/backend/app/models/{character,conversation,message,setting}.py`
///
/// 派生规则（M0-T03 工单契约）：
/// - SQLAlchemy 列名 snake_case ↔ drift Dart getter camelCase（drift 默认转换）
/// - SQLAlchemy `Enum(Role, native_enum=False, values_callable=...)`：
///   Role 以 `.value`（user/assistant/system）字符串落库，兼容桌面端存量 VARCHAR
/// - SQLAlchemy `JSON` 列：TEXT 落库 + JSON 编解码 converter
/// - VARCHAR(n) 长度在 SQLite 桌面端本就不强制（SQLite 不校验 VARCHAR 长度），
///   因此移动端不生成更严格的 CHECK 长度约束，桌面端仍是长度语义的执行者
/// - created_at / updated_at 桌面端为 ORM 层客户端默认（datetime.now）+ SQL 层
///   server_default=func.now()；移动端列必填无 DB 默认，赋值为仓储层职责（M1）。
///   DateTime 表示差（drift 落 INTEGER（unix 秒），桌面落 TEXT ISO 字符串）——
///   F-3 方案 a 已处置：保持 drift INTEGER（unix 秒）不变，双端互迁 / ISO 口径
///   契约归 M4 导出 JSON 层；消息排序 created_at, id 兜底（同秒按 id 正序），
///   亚秒精度移交 M4 导出层处理（TECH_DEBT F-3 处置记录）
library;

import 'dart:convert';

import 'package:drift/drift.dart';

/// 消息角色枚举 — 与桌面端 `models/message.py::Role` 一一对应。
///
/// 落库值取 `.value`（user/assistant/system），与桌面端
/// `values_callable` 生成的存量 VARCHAR 语义兼容。
enum Role {
  user('user'),
  assistant('assistant'),
  system('system');

  const Role(this.value);

  /// 数据库存储值（桌面端 SQLAlchemy Enum 的 .value 语义）。
  final String value;
}

/// [Role] 的 drift 类型转换器 — 显式按 `.value` 落库。
///
/// 不依赖 drift 内置 EnumIndexConverter（按下标存 INTEGER），
/// 因为桌面端以字符串值落库且存量数据是 VARCHAR。
class RoleConverter extends TypeConverter<Role, String> {
  const RoleConverter();

  @override
  Role fromSql(String fromDb) {
    for (final role in Role.values) {
      if (role.value == fromDb) {
        return role;
      }
    }
    throw ArgumentError.value(fromDb, 'role', 'Unknown Role value in database');
  }

  @override
  String toSql(Role value) => value.value;
}

/// `List<String>` JSON 列转换器（characters.alternate_greetings / tags）。
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) {
      return const <String>[];
    }
    return (jsonDecode(fromDb) as List).cast<String>();
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// `Map<String, dynamic>` JSON 列转换器
/// （characters.creator_notes / extensions）。
class StringMapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const StringMapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) {
      return const <String, dynamic>{};
    }
    return (jsonDecode(fromDb) as Map).cast<String, dynamic>();
  }

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}

/// 角色表 — 对齐桌面端 `models/character.py::Character`
/// （SillyTavern Character Card V2 全字段）。
@TableIndex(name: 'idx_characters_name', columns: {#name})
class Characters extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填，桌面端 String(100) + index=True。
  TextColumn get name => text()();

  // ── V2 核心字段 ──
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get personality => text().withDefault(const Constant(''))();
  TextColumn get scenario => text().withDefault(const Constant(''))();
  TextColumn get firstMes => text().withDefault(const Constant(''))();
  TextColumn get mesExample => text().withDefault(const Constant(''))();

  // ── V2 高级字段 ──
  TextColumn get systemPrompt => text().withDefault(const Constant(''))();
  TextColumn get postHistoryInstructions =>
      text().withDefault(const Constant(''))();
  TextColumn get alternateGreetings => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get tags => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();

  // ── 元数据 ──
  TextColumn get creator => text().withDefault(const Constant(''))();
  TextColumn get version => text().withDefault(const Constant('1.0'))();
  TextColumn get creatorNotes => text()
      .map(const StringMapConverter())
      .withDefault(const Constant('{}'))();
  TextColumn get extensions => text()
      .map(const StringMapConverter())
      .withDefault(const Constant('{}'))();

  // ── 项目原有字段 ──
  TextColumn get avatar => text().nullable()();
  RealColumn get temperature => real().withDefault(const Constant(0.7))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// 对话表 — 对齐桌面端 `models/conversation.py::Conversation`。
@TableIndex(name: 'idx_conversations_character_id', columns: {#characterId})
class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，桌面端 ondelete=CASCADE + index=True。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  TextColumn get title => text().withDefault(const Constant('新对话'))();
  TextColumn get modelProvider =>
      text().withDefault(const Constant('claude'))();
  TextColumn get modelName =>
      text().withDefault(const Constant('claude-sonnet-5'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// 消息表 — 对齐桌面端 `models/message.py::Message`。
///
/// `created_at` 单列索引（FD-05，schemaVersion=4）：加速
/// `latestMessageAt` 的 join + `ORDER BY created_at DESC LIMIT 1`；
/// 不改变 createdAt 秒级存储精度（F-3 已拍板，见文件头注释）。
@TableIndex(name: 'idx_messages_conversation_id', columns: {#conversationId})
@TableIndex(name: 'idx_messages_created_at', columns: {#createdAt})
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → conversations.id，桌面端 ondelete=CASCADE + index=True。
  IntColumn get conversationId =>
      integer().references(Conversations, #id, onDelete: KeyAction.cascade)();

  /// 必填枚举，TypeConverter 显式按 `.value`（user/assistant/system）落库。
  TextColumn get role => text().map(const RoleConverter())();

  /// 必填文本。
  TextColumn get content => text()();

  /// 当前激活候选序号（MS-01；spec §4.2 默认 0）。`messages.content` 恒为
  /// 当前激活候选——切换/追加候选时由仓储层同步覆写（对齐桌面
  /// `models/message.py::Message.active_swipe_index`，server_default '0'）。
  IntColumn get activeSwipeIndex => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
}

/// 消息候选表 — 对齐桌面端 `models/message.py::MessageSwipe`（MS-1）。
///
/// 序号 `index` 0 起（候选 0 = 消息原始内容，首次 addSwipe 播种）、
/// `(message_id, index)` 唯一（对齐桌面 `uq_message_swipes_message_index`）；
/// 删除消息级联删候选（FK CASCADE）。FK 索引由迁移 raw SQL 补建
/// （drift 不自动为 FK 建索引，对齐 @TableIndex 注解）。
@DataClassName('MessageSwipe')
@TableIndex(name: 'idx_message_swipes_message_id', columns: {#messageId})
class MessageSwipes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → messages.id，桌面端 ondelete=CASCADE + index=True。
  IntColumn get messageId =>
      integer().references(Messages, #id, onDelete: KeyAction.cascade)();

  /// 候选序号（0 起；必填整数）。
  IntColumn get index => integer()();

  /// 候选正文（必填文本）。
  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();

  /// `(message_id, index)` 唯一约束（对齐桌面 UniqueConstraint
  /// uq_message_swipes_message_index；SQLite 生成 autoindex 实现）。
  @override
  List<Set<Column>> get uniqueKeys => [
        {messageId, index},
      ];
}

/// 设置表（键值对）— 对齐桌面端 `models/setting.py::Setting`。
///
/// 主键即 key（TEXT 主键），SQLite 会生成 sqlite_autoindex 主键索引，
/// 不另建显式索引。
class Settings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {key};
}

/// 记忆条目类型 — 单表 `MemoryEntries` 以 [kind] 区分两类记忆（ADR-0003）。
///
/// - [personaFact]：人格事实（Profile 语义，LangMem Profile）——身份/喜好/
///   性格等稳定事实，抗 OOC 每轮重注入。
/// - [episodic]：情景记忆（LangMem Episodic）——对话经历/关键事件，做
///   少数次注入（不每轮）。
///
/// 落库值取 `.value`（persona_fact / episodic），无桌面锚点（移动端先行）。
enum MemoryKind {
  personaFact('persona_fact'),
  episodic('episodic');

  const MemoryKind(this.value);

  /// 数据库存储值。
  final String value;
}

/// [MemoryKind] 的 drift 类型转换器 — 显式按 `.value` 落库（对齐 [RoleConverter]
/// 的字符串落库惯例，不按下标 INTEGER）。
class MemoryKindConverter extends TypeConverter<MemoryKind, String> {
  const MemoryKindConverter();

  @override
  MemoryKind fromSql(String fromDb) {
    for (final kind in MemoryKind.values) {
      if (kind.value == fromDb) {
        return kind;
      }
    }
    throw ArgumentError.value(
      fromDb,
      'kind',
      'Unknown MemoryKind value in database',
    );
  }

  @override
  String toSql(MemoryKind value) => value.value;
}

/// 记忆条目表 — 人机恋板块独立记忆（ADR-0003 方案A：单表 + kind 区分）。
///
/// 挂角色名下（`characterId` FK，删除角色时级联清除），单条文本条目；
/// `importance` 供排序（高者优先注入），`content` 为记忆正文。
@DataClassName('MemoryEntry')
@TableIndex(name: 'idx_memory_entries_character_id', columns: {#characterId})
class MemoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 必填枚举（persona_fact / episodic），TypeConverter 显式按 `.value` 落库。
  TextColumn get kind => text().map(const MemoryKindConverter())();

  /// 记忆正文（必填文本）。
  TextColumn get content => text()();

  /// 重要性（整数，缺省 0；高者优先注入）。
  IntColumn get importance => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// 人设演化版本表 — 记录每次人设演化的快照（ADR-0003：版本化 + 用户确认闸门）。
///
/// `personalitySnapshot` 为演化时点的角色人格全文快照，`reason` 为演化动机
/// （LLM 反思产出 / 用户备注），供审阅与回滚。
@DataClassName('PersonaRevision')
@TableIndex(name: 'idx_persona_revisions_character_id', columns: {#characterId})
class PersonaRevisions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 演化时点的角色人格全文快照（必填文本）。
  TextColumn get personalitySnapshot => text()();

  /// 演化动机 / 备注（缺省空串）。
  TextColumn get reason => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime()();
}

/// 关系阶段枚举 — 人机恋关系状态机五段（spec §3 / P4）。
///
/// 落库值取 `.value`（stranger/acquainted/familiar/intimate/soulmate），
/// 沿 [RoleConverter] / [MemoryKindConverter] 字符串落库惯例。
enum RelationshipStage {
  stranger('stranger'),
  acquainted('acquainted'),
  familiar('familiar'),
  intimate('intimate'),
  soulmate('soulmate');

  const RelationshipStage(this.value);

  /// 数据库存储值。
  final String value;
}

/// [RelationshipStage] 的 drift 类型转换器 — 显式按 `.value` 落库
/// （对齐 [RoleConverter]，不按下标 INTEGER）。
class RelationshipStageConverter
    extends TypeConverter<RelationshipStage, String> {
  const RelationshipStageConverter();

  @override
  RelationshipStage fromSql(String fromDb) {
    for (final stage in RelationshipStage.values) {
      if (stage.value == fromDb) {
        return stage;
      }
    }
    throw ArgumentError.value(
      fromDb,
      'stage',
      'Unknown RelationshipStage value in database',
    );
  }

  @override
  String toSql(RelationshipStage value) => value.value;
}

/// 关系状态表 — 每角色一行（`characterId` 唯一索引，spec §3 / P4）。
///
/// `affinity` 0-100 由仓储/服务层 clamp（无 DB CHECK 先例）；`stage` 为
/// 五段枚举字符串落库；无行时首回合不注入（判定⑧）。
@DataClassName('RelationshipState')
@TableIndex(
  name: 'idx_relationship_states_character_id',
  columns: {#characterId},
  unique: true,
)
class RelationshipStates extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）；每角色至多一行。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 必填枚举（stranger/acquainted/familiar/intimate/soulmate），字符串落库。
  TextColumn get stage => text().map(const RelationshipStageConverter())();

  /// 亲密度 0-100（仓储/服务层 clamp，DB 不设 CHECK 约束）。
  IntColumn get affinity => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime()();
}

/// 主动消息计划状态 — 排程生命周期四态（spec §3 / 判定⑥）。
///
/// - [scheduled]：已排程未发送（在途）。
/// - [sent]：已发送并落 assistant 消息（`messageId` 指向该消息）。
/// - [expired]：到点未发送（通知失败/错过时机），服务侧核对置位。
/// - [dropped]：被放弃（如重生成截断使 `messageId` 置空后核对置位）。
enum ProactivePlanStatus {
  scheduled('scheduled'),
  sent('sent'),
  expired('expired'),
  dropped('dropped');

  const ProactivePlanStatus(this.value);

  /// 数据库存储值。
  final String value;
}

/// [ProactivePlanStatus] 的 drift 类型转换器 — 显式按 `.value` 落库。
class ProactivePlanStatusConverter
    extends TypeConverter<ProactivePlanStatus, String> {
  const ProactivePlanStatusConverter();

  @override
  ProactivePlanStatus fromSql(String fromDb) {
    for (final status in ProactivePlanStatus.values) {
      if (status.value == fromDb) {
        return status;
      }
    }
    throw ArgumentError.value(
      fromDb,
      'status',
      'Unknown ProactivePlanStatus value in database',
    );
  }

  @override
  String toSql(ProactivePlanStatus value) => value.value;
}

/// 主动消息计划表 — 预生成文案 + 排程（spec §3 / P1~P3）。
///
/// `sentAt` 为每日 6 次 / 冷却 6h 的口径单一来源（判定③）；`messageId`
/// 指向已落库的 assistant 消息，重生成截断删消息时 FK setNull（判定⑥）。
@TableIndex(name: 'idx_proactive_plans_character_id', columns: {#characterId})
@TableIndex(
  name: 'idx_proactive_plans_conversation_id',
  columns: {#conversationId},
)
@TableIndex(name: 'idx_proactive_plans_status', columns: {#status})
class ProactivePlans extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 必填外键 → conversations.id，ondelete=CASCADE（随对话删除）。
  IntColumn get conversationId =>
      integer().references(Conversations, #id, onDelete: KeyAction.cascade)();

  /// 预生成文案（必填文本）。
  TextColumn get content => text()();

  /// 计划发送时间（必填）。
  DateTimeColumn get scheduledAt => dateTime()();

  /// 实际发送时间（可空；置 sent 时写，计数/冷却口径单一来源）。
  DateTimeColumn get sentAt => dateTime().nullable()();

  /// 必填枚举（scheduled/sent/expired/dropped），字符串落库。
  TextColumn get status => text().map(const ProactivePlanStatusConverter())();

  /// 已发送消息 id（可空）；消息删除时 FK setNull（重生成截断场景）。
  IntColumn get messageId => integer().nullable().references(
    Messages,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// 内心独白表 — 剥离的 `<thought>` 内容（spec §3 / P5）。
///
/// 不污染 messages/搜索/导出；`messageId` CASCADE 随消息删除级联清空。
@TableIndex(name: 'idx_inner_thoughts_character_id', columns: {#characterId})
@TableIndex(name: 'idx_inner_thoughts_message_id', columns: {#messageId})
class InnerThoughts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 必填外键 → messages.id，ondelete=CASCADE（thought 随消息删除级联）。
  IntColumn get messageId =>
      integer().references(Messages, #id, onDelete: KeyAction.cascade)();

  /// 独白正文（必填文本）。
  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();
}

/// 向量条目表 — 远端 embedding 检索的本地向量存储（spec §2 D2）。
///
/// `(characterId, contentHash)` 唯一索引为 SR-21 去重前提；text 快照截断
/// 上限 2000 由仓储层负责（表层不设 CHECK）；`entryId` 为普通 int 逻辑
/// 回指 memory_entries（不建硬 FK，避免记忆变更/删除时的引用约束耦合）；
/// `model`/`dims` 为模型指纹，检索按当前指纹过滤（指纹变更标脏重嵌由
/// 仓储/服务层处理）。
@DataClassName('EmbeddingEntry')
@TableIndex(name: 'idx_embedding_entries_character_id', columns: {#characterId})
@TableIndex(
  name: 'idx_embedding_entries_character_id_content_hash',
  columns: {#characterId, #contentHash},
  unique: true,
)
class EmbeddingEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除清向量）。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 逻辑回指 memory_entries.id（普通 int，不建硬 FK）。
  IntColumn get entryId => integer()();

  /// 补嵌时点的文本快照（截断上限 2000 由仓储层负责，SR-21）。
  TextColumn get contentSnapshot => text()();

  /// 向量 blob = float32 LE 打包（1536 维 ≈ 6144 字节，无压缩）。
  BlobColumn get vector => blob()();

  /// 模型指纹（如 text-embedding-3-small）。
  TextColumn get model => text()();

  /// 向量维度指纹。
  IntColumn get dims => integer()();

  /// SHA-256 hex（内容 hash，SR-21 去重键组成部分）。
  TextColumn get contentHash => text()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// 语义命中队列表 — `<search:>` 语义兜底命中的延迟注入队列（spec §2 D2）。
///
/// 命中入队后由注入装配读取消费（仓储级去重，注入前删除）；`query` 为
/// 检索 query 快照。
@DataClassName('SemanticHit')
@TableIndex(name: 'idx_semantic_hits_character_id', columns: {#characterId})
class SemanticHits extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 逻辑回指 memory_entries.id（普通 int，同 [EmbeddingEntries.entryId]）。
  IntColumn get entryId => integer()();

  /// 检索 query 快照（必填文本）。
  TextColumn get query => text()();

  DateTimeColumn get createdAt => dateTime()();
}

/// 世界书条目表 — 对齐桌面端 `models/lorebook.py::LorebookEntry`
/// （WL-1；chat-polish spec §4.4 七件套 + 扩展字段）。
///
/// `keys` 承载触发关键词 JSON 数组（复用 [StringListConverter] 落库语义）；
/// order/probability/group_weight/depth 表层不设 CHECK 约束（沿 F-76 先例：
/// 仓储/服务层裁剪，解析层对 ST 脏数据裁剪、管理层拒绝语义由契约锁锁定）；
/// 数值域：order [0,9999] / probability [1,100] / group_weight [1,100] /
/// depth [0,20]。删除角色级联删条目（FK CASCADE）；FK 索引由迁移 raw SQL
/// 补建（drift 不自动为 FK 建索引，对齐 @TableIndex 注解）。
@DataClassName('LorebookEntry')
@TableIndex(name: 'idx_lorebook_entries_character_id', columns: {#characterId})
class LorebookEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → characters.id，桌面端 ondelete=CASCADE + index=True。
  IntColumn get characterId =>
      integer().references(Characters, #id, onDelete: KeyAction.cascade)();

  /// 条目标题（可空/缺省空串，桌面 String(200)）。
  TextColumn get title => text().withDefault(const Constant(''))();

  /// 触发关键词（JSON 数组；桌面《JsonList》 TypeDecorator 语义）。
  TextColumn get keys => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();

  /// 命中后注入内容（必填文本）。
  TextColumn get content => text().withDefault(const Constant(''))();

  /// 常驻（不判命中直接注入；缺省 false）。
  BoolColumn get constant => boolean().withDefault(const Constant(false))();

  /// 命中条目排序（升序注入；域 [0,9999]，缺省 100）。
  IntColumn get order => integer().withDefault(const Constant(100))();

  /// 独立命中概率（域 [1,100]，缺省 100）。
  IntColumn get probability => integer().withDefault(const Constant(100))();

  /// 互斥组名（空=不分组；桌面 String(100)）。
  TextColumn get groupName => text().withDefault(const Constant(''))();

  /// 组内权重（同组随机抽一；域 [1,100]，缺省 100）。
  IntColumn get groupWeight => integer().withDefault(const Constant(100))();

  /// 命中模式（or / and；缺省 or）。
  TextColumn get matchMode => text().withDefault(const Constant('or'))();

  /// 注入位置（world / before_char / after_char；缺省 world）。
  TextColumn get position => text().withDefault(const Constant('world'))();

  /// 参与命中的最近轮数（域 [0,20]，缺省 20；0=只看当前输入）。
  IntColumn get depth => integer().withDefault(const Constant(20))();

  /// 条目来源（manual / auto；记忆宫殿产出为 auto，缺省 manual）。
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// 单条开关（缺省 true）。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
