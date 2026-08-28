/// drift 表定义 — 与桌面端 ORM 逐字段对齐（schemaVersion=1 冻结）。
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
class StringMapConverter
    extends TypeConverter<Map<String, dynamic>, String> {
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
  TextColumn get alternateGreetings =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get tags =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();

  // ── 元数据 ──
  TextColumn get creator => text().withDefault(const Constant(''))();
  TextColumn get version => text().withDefault(const Constant('1.0'))();
  TextColumn get creatorNotes =>
      text().map(const StringMapConverter()).withDefault(const Constant('{}'))();
  TextColumn get extensions =>
      text().map(const StringMapConverter()).withDefault(const Constant('{}'))();

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
  IntColumn get characterId => integer().references(
        Characters,
        #id,
        onDelete: KeyAction.cascade,
      )();

  TextColumn get title => text().withDefault(const Constant('新对话'))();
  TextColumn get modelProvider => text().withDefault(const Constant('claude'))();
  TextColumn get modelName =>
      text().withDefault(const Constant('claude-sonnet-5'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// 消息表 — 对齐桌面端 `models/message.py::Message`。
@TableIndex(name: 'idx_messages_conversation_id', columns: {#conversationId})
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 必填外键 → conversations.id，桌面端 ondelete=CASCADE + index=True。
  IntColumn get conversationId => integer().references(
        Conversations,
        #id,
        onDelete: KeyAction.cascade,
      )();

  /// 必填枚举，TypeConverter 显式按 `.value`（user/assistant/system）落库。
  TextColumn get role => text().map(const RoleConverter())();

  /// 必填文本。
  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();
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
