/// 世界书条目仓储（WL-01）— 角色作用域 CRUD + 全量替换 + ST character_book
/// 解析，语义与桌面 `services/lorebook.py` 逐字对齐（chat-polish spec §4.4）。
///
/// 协议表面（导出符号）：[LorebookEntryDraft] / [LorebookRepository] /
/// [parseCharacterBook]。
///
/// 对齐要点：
/// - listEntries 按 (order, id) 升序（确定性排序契约，桌面
///   `order_by(order.asc(), id.asc())` 逐字）；
/// - createEntry / replaceEntries 先守卫角色存在（抛
///   [CharacterNotFoundError]，桌面 404 语义，防 FK 违例裸错）；
/// - updateEntry 部分更新仅写显式字段 + updatedAt 前移（桌面
///   `exclude_unset` + ORM onupdate 对应物）；显式 null 视为未提供跳过
///   （NOT NULL 列防 IntegrityError、值不中毒，桌面 Falsify 修复锁）；
/// - deleteEntry 返回受影响与否（桌面抛 LorebookEntryNotFoundError，移动端
///   沿 character/message 仓库先例返回 bool，见 concerns/06.md §3）；
/// - replaceEntries 幂等：先删后插单事务，连续两次结果一致；
/// - character_id 级联删除由 FK CASCADE + `PRAGMA foreign_keys = ON` 承保
///   （本层零显式级联代码，测试实证）；
/// - parseCharacterBook 为纯函数（零 DB 零 IO）：ST character_book → 条目
///   草案，字段一一对应；畸形降级不抛（非 dict / entries 非 list → 空列表、
///   非 dict entry 跳过、缺失字段取默认、未知 position 回落 world、数值
///   越界裁剪），解析层裁剪、管理层拒绝的分界与桌面一致；
/// - created_at / updated_at 全部由本层赋值（drift 列无 DB 默认）。
library;

import 'package:drift/drift.dart';

import '../../services/llm/errors.dart' show CharacterNotFoundError;
import '../database/app_database.dart';

/// 世界书条目草案（落库前形态；对齐桌面 `LorebookEntryCreate`，字段一一对应）。
class LorebookEntryDraft {
  /// 构造世界书条目草案。
  ///
  /// 缺省字段与桌面 `LorebookEntryCreate` 默认一致：title 空串 / keys 空列表 /
  /// constant false / order 100 / probability 100 / group_name 空串 /
  /// group_weight 100 / match_mode or / position world / depth 20 /
  /// source manual / enabled true。
  const LorebookEntryDraft({
    this.title = '',
    this.keys = const <String>[],
    this.content = '',
    this.constant = false,
    this.order = 100,
    this.probability = 100,
    this.groupName = '',
    this.groupWeight = 100,
    this.matchMode = 'or',
    this.position = 'world',
    this.depth = 20,
    this.source = 'manual',
    this.enabled = true,
  });

  /// 条目标题（已截断 200）。
  final String title;

  /// 触发关键词（JSON 数组语义；空 keys 允许——constant 场景）。
  final List<String> keys;

  /// 命中后注入内容。
  final String content;

  /// 常驻（不判命中直接注入）。
  final bool constant;

  /// 命中条目排序（升序注入；域 [0,9999]）。
  final int order;

  /// 独立命中概率（域 [1,100]）。
  final int probability;

  /// 互斥组名（空=不分组）。
  final String groupName;

  /// 组内加权抽一权重（域 [1,100]）。
  final int groupWeight;

  /// 命中模式（or / and）。
  final String matchMode;

  /// 注入位置（world / before_char / after_char）。
  final String position;

  /// 参与命中的最近轮数（域 [0,20]；0=只看当前输入）。
  final int depth;

  /// 条目来源（manual / auto；记忆宫殿产出 auto）。
  final String source;

  /// 单条开关。
  final bool enabled;

  /// 转换为此条目对应的落库 `LorebookEntriesCompanion`（导入装配用）。
  ///
  /// [characterId] 为归属角色；[now] 为创建/更新时间戳（本层赋值职责）。
  LorebookEntriesCompanion toCompanion({
    required int characterId,
    required DateTime now,
  }) {
    return LorebookEntriesCompanion.insert(
      characterId: characterId,
      title: Value(title),
      keys: Value(keys),
      content: Value(content),
      constant: Value(constant),
      order: Value(order),
      probability: Value(probability),
      groupName: Value(groupName),
      groupWeight: Value(groupWeight),
      matchMode: Value(matchMode),
      position: Value(position),
      depth: Value(depth),
      source: Value(source),
      enabled: Value(enabled),
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// 世界书条目仓储 — 表面与桌面 lorebook 服务对应
/// （list_entries / create_entry / update_entry / delete_entry /
/// replace_entries；parse_character_book 见顶层函数）。
class LorebookRepository {
  /// [now] 为时间戳来源注入点（测试确定性用），缺省 [DateTime.now]。
  LorebookRepository(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// 角色的全部世界书条目，按 (order, id) 升序（桌面 list_entries 契约）。
  ///
  /// keys 已反序列化为 list；空集返回空列表（零异常）。
  Future<List<LorebookEntry>> listEntries(int characterId) {
    return (_db.select(_db.lorebookEntries)
          ..where(($LorebookEntriesTable t) =>
              t.characterId.equals(characterId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.order),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// 创建世界书条目（单次插入提交）。
  ///
  /// 角色不存在抛 [CharacterNotFoundError]（防 FK 违例裸错，桌面 404 语义）；
  /// created_at / updated_at 由本层赋值。
  Future<LorebookEntry> createEntry(
    int characterId,
    LorebookEntryDraft draft,
  ) async {
    await _requireCharacter(characterId);
    return _db.into(_db.lorebookEntries).insertReturning(
          draft.toCompanion(characterId: characterId, now: _now()),
        );
  }

  /// 部分更新：仅写 [data] 中显式提供的字段（`Value.absent()` 之外），并
  /// 前移 updated_at。
  ///
  /// 条目不存在返回 null；[data] 无任何显式字段时不产生 UPDATE 语句
  /// （no-op 返回原行）。桌面「显式 null 视为未提供」语义由 Dart 类型系统
  /// 等价表达：本表全为非空列，companion 参数类型 `Value<T>`（非可空）
  /// 在编译期拒绝 `Value(null)`，无需运行期 null 过滤（见 concerns/06.md §2）。
  Future<LorebookEntry?> updateEntry(
    int entryId,
    LorebookEntriesCompanion data,
  ) async {
    final existing = await _entryOrNull(entryId);
    if (existing == null) {
      return null;
    }
    if (data.toColumns(false).isEmpty) {
      return existing;
    }
    await (_db.update(_db.lorebookEntries)
          ..where(($LorebookEntriesTable t) => t.id.equals(entryId)))
        .write(data.copyWith(updatedAt: Value(_now())));
    return _entryOrNull(entryId);
  }

  /// 删除世界书条目；返回是否确有条目被删（不存在 → false 且零副作用）。
  Future<bool> deleteEntry(int entryId) async {
    final affected = await (_db.delete(_db.lorebookEntries)
          ..where(($LorebookEntriesTable t) => t.id.equals(entryId)))
        .go();
    return affected > 0;
  }

  /// 全量替换角色的世界书条目（先删后插，单事务；桌面 replace_entries）。
  ///
  /// 幂等（契约锁锁定）：连续两次以相同输入调用，两次均落库为相同条目集合，
  /// 返回计数一致。常用于「角色卡 character_book 解析结果一键落库」；
  /// [drafts] 为空列表 = 清空该角色全部条目。角色不存在抛
  /// [CharacterNotFoundError]。
  ///
  /// 返回新条目数量。
  Future<int> replaceEntries(
    int characterId,
    List<LorebookEntryDraft> drafts,
  ) {
    return _db.transaction(() async {
      await _requireCharacter(characterId);
      await (_db.delete(_db.lorebookEntries)
            ..where(($LorebookEntriesTable t) =>
                t.characterId.equals(characterId)))
          .go();
      final now = _now();
      for (final draft in drafts) {
        await _db.into(_db.lorebookEntries).insert(
              draft.toCompanion(characterId: characterId, now: now),
            );
      }
      return drafts.length;
    });
  }

  /// 守卫：角色必须存在，否则抛 [CharacterNotFoundError]（防 FK 违例）。
  Future<void> _requireCharacter(int characterId) async {
    final exists = await (_db.select(_db.characters)
          ..where(($CharactersTable t) => t.id.equals(characterId)))
        .getSingleOrNull();
    if (exists == null) {
      throw CharacterNotFoundError(characterId);
    }
  }

  /// 条目行定位（不存在返回 null；updateEntry 容错面）。
  Future<LorebookEntry?> _entryOrNull(int entryId) {
    return (_db.select(_db.lorebookEntries)
          ..where(($LorebookEntriesTable t) => t.id.equals(entryId)))
        .getSingleOrNull();
  }
}

/// ST character_book 中本模型不承载的 position 值（如 in_chat）统一回落
/// world（桌面 `_KNOWN_ST_POSITIONS` 逐字）。
const Set<String> _knownStPositions = {'before_char', 'after_char'};

/// 解析层数值边界（与桌面 schema Field 约束一致；解析层裁剪、API 层拒绝）。
const int _depthDefault = 20;

/// 角色卡 character_book → 世界书条目草案列表（纯函数，零 DB 零 IO）。
///
/// 消费 `extensions.conver_system.character_book`（形如
/// `{"entries": [...]}`，与 ST character_book 顶层结构一致）。逐条映射
/// （桌面 `lorebook.py::parse_character_book` 逐字）：
///   keys/content/constant/insertion_order（或 order）→ order/probability/
///   group → group_name/group_weight/position/depth/enabled/name → title
/// 一一对应；position 仅 before_char/after_char 保留，in_chat 等本模型不
/// 承载值回落 world；match_mode 由 ST selective + secondary_keys 推得
/// （and/or）。
///
/// 脏数据容错（导入场景不抛）：None / 非 dict / 缺 entries 键 / entries
/// 非 list → 空列表；非 dict entry 跳过；缺失字段取默认值；数值越界裁剪
/// （解析层裁剪、API 层拒绝的分界与桌面一致）。
List<LorebookEntryDraft> parseCharacterBook(Object? book) {
  if (book is! Map) {
    return const <LorebookEntryDraft>[];
  }
  final rawEntries = book['entries'];
  if (rawEntries is! List) {
    return const <LorebookEntryDraft>[];
  }
  return [
    for (final raw in rawEntries)
      if (raw is Map) _entryFromSt(_stringKeyedMap(raw)),
  ];
}

/// 单条 ST entry Map → [LorebookEntryDraft]（数值裁剪、列表/布尔容错；
/// 桌面 `_entry_from_st` 逐字）。
LorebookEntryDraft _entryFromSt(Map<String, dynamic> raw) {
  final position = _knownStPositions.contains(raw['position'])
      ? raw['position'] as String
      : 'world';
  // ST selective 语义：启用 secondary_keys 时全部关键词须命中 → and；否则 or。
  final selective = _asBool(raw['selective'], false);
  final secondary = _asStrList(raw['secondary_keys']);
  final matchMode = selective && secondary.isNotEmpty ? 'and' : 'or';

  return LorebookEntryDraft(
    title: _truncate(raw['name']?.toString() ?? '', 200),
    keys: _asStrList(raw['keys']),
    content: raw['content']?.toString() ?? '',
    constant: _asBool(raw['constant'], false),
    // 桌面 raw.get("insertion_order", raw.get("order", 100)) 语义：键存在
    // （含 null）即不查 order；null → _clampInt 回落默认 100。
    order: raw.containsKey('insertion_order')
        ? _clampInt(raw['insertion_order'], 0, 9999, 100)
        : _clampInt(raw['order'] ?? 100, 0, 9999, 100),
    probability: _clampInt(raw['probability'] ?? 100, 1, 100, 100),
    groupName: _truncate(raw['group']?.toString() ?? '', 100),
    groupWeight: _clampInt(raw['group_weight'] ?? 100, 1, 100, 100),
    matchMode: matchMode,
    position: position,
    depth: _clampInt(raw['depth'] ?? _depthDefault, 0, 20, _depthDefault),
    source: 'manual',
    enabled: _asBool(raw['enabled'], true),
  );
}

/// 布尔容错：字符串按字面求值（'false'/'0'/'no'/'off'/空 → false，
/// 'true'/'1'/'yes'/'on' → true），数值按非零，其它（含 null）→ 默认。
///
/// 杜绝 `'false'` 被误判为 true 的语义反转（桌面 Falsify 修复锁逐字）。
bool _asBool(Object? value, bool fallback) {
  if (value is String) {
    final lowered = value.trim().toLowerCase();
    if (const {'false', '0', 'no', 'off', ''}.contains(lowered)) {
      return false;
    }
    if (const {'true', '1', 'yes', 'on'}.contains(lowered)) {
      return true;
    }
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  return fallback;
}

/// 容忍脏数据：null / 空串 → []，list → str 化列表，其它 → 单值包裹。
///
/// 对齐桌面 `text_utils.as_str_list`（keys / secondary_keys 共用）。
List<String> _asStrList(Object? value) {
  if (value == null || value == '') {
    return const <String>[];
  }
  if (value is List) {
    return [for (final v in value) v.toString()];
  }
  return [value.toString()];
}

/// 数值裁剪：非法/缺失 → 默认；越界 → 裁剪到 [lo, hi]。
///
/// 对齐桌面 `_clamp_int`：str 可解析走 int 截断（失败 → 默认）、num 走
/// toInt 截断、bool → 1/0（对齐 Python `int(True)`）。
int _clampInt(Object? value, int lo, int hi, int fallback) {
  final numValue = value is bool
      ? (value ? 1 : 0)
      : (value is num ? value.toInt() : int.tryParse(value?.toString() ?? ''));
  if (numValue == null) {
    return fallback;
  }
  return numValue.clamp(lo, hi);
}

/// 前 [max] 个 UTF-16 码元（中文 BMP 字符单码元，等价桌面 `[:max]` 截断）。
String _truncate(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

/// Map 键统一转 String（JSON 解码结果 / 字面量均为 String 键，防御性转换）。
Map<String, dynamic> _stringKeyedMap(Map map) =>
    <String, dynamic>{for (final entry in map.entries) entry.key.toString(): entry.value};
