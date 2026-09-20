/// SillyTavern Character Card V2 — 角色卡转换层（桌面 `character_card.py` 全量移植）。
///
/// 深模块：协议表面仅两个公开函数（[toV2Card] / [fromV2Card]），实现内含
/// V2 信封 / 裸 data / 无 spec data 信封 / V1 旧卡四种格式识别、字段归一化、
/// 头像往返、extensions.conver_system 命名空间保真。纯 Dart 零平台依赖。
///
/// 语义锚点（共识 A3 + 工单 M3-03 验收 1-5 + NPD-02）：
/// - 导出映射：`version → data.character_version`；temperature 注入
///   `extensions.conver_system`；preset_dialogues 注入同一命名空间（不落 data
///   顶层）；base64 头像去前缀进 data.avatar、URL 头像进命名空间 avatar_url；
///   None 集合字段 → `[]` / `{}`；
/// - 导入四格式优先级：V2 信封 → 无 spec 的 data 信封 → V1 旧卡（char_name
///   等 8 字段归一）→ 裸 data；非法结构抛 [CardFormatException]（文案含格式
///   引导），缺失 / 纯空白 name 抛 [CardValidationException]（纯原因）；
/// - 类型容错：[_asList] / [_asDict] / [_inferMime] / [_toDataUri] /
///   [_clampTemperature] / name 截断 100 / version 截断 50；
/// - 预设对话（NPD-02）：[_normalizePresetDialogues] 桌面
///   `_normalize_preset_dialogues` 逐字——非 list → []、空字段过滤、
///   trim 同名去重、[presetDialogueMax]（10）截断；conver_system 命名空间往返。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show immutable;

import '../data/database/app_database.dart'
    show Character, CharactersCompanion;
import '../data/repositories/lorebook_repository.dart'
    show LorebookEntryDraft, parseCharacterBook;

/// 卡片格式错误——结构无法识别 / 不支持，文案含格式引导（对应桌面
/// `CardFormatError`；路由层转 422 友好报错的移动端等价物）。
class CardFormatException implements Exception {
  /// 用户可读的格式错误原因（含格式引导）。
  const CardFormatException(this.message);

  /// 错误原因文案。
  final String message;

  @override
  String toString() => 'CardFormatException: $message';
}

/// 卡片内容校验错误——结构合法但内容不符合校验（目前仅角色名称不能为空），
/// 文案纯原因、不含格式引导（对应桌面 `CardValidationError`）。
class CardValidationException implements Exception {
  /// 用户可读的校验错误原因（纯原因）。
  const CardValidationException(this.message);

  /// 错误原因文案。
  final String message;

  @override
  String toString() => 'CardValidationException: $message';
}

/// 预设对话条目最大数量（NPD-02；桌面
/// `schemas/character.py::PRESET_DIALOGUE_MAX == 10`，归一化超量截断单一来源，
/// 测试 `preset_dialogue_max_constant` 契约锁）。
const int presetDialogueMax = 10;

/// V2 卡解析 / 归一化后的角色字段快照（导入侧产出，供落库装配
/// `CharactersCompanion`）。
///
/// 字段与 drift `Characters` 表对齐（name/description/personality/scenario/
/// first_mes/mes_example/system_prompt/post_history_instructions/
/// alternate_greetings/tags/creator/version/creator_notes/extensions/avatar/
/// temperature），由 [fromV2Card] 产出后由控制器装配落库；[lorebookEntries]
/// 为 `extensions.conver_system.character_book` 解析出的世界书条目草案
/// （WL-01，独立表归 LorebookRepository），装配职责归导入路径
/// （characters_controller 接线随 WL 票后续）。
@immutable
class CharacterDraft {
  /// 构造角色字段快照。
  ///
  /// 缺省字段（[alternateGreetings] / [version] / [creatorNotes] /
  /// [extensions] / [creator] / [avatar] / [lorebookEntries]）有默认值，
  /// 装配点只传业务字段——缺省语义（对齐新建角色 / 桌面 CharacterBase）
  /// 单一归属本构造器；导入路径 [fromV2Card] 显式传全字段（归一化产物）
  /// 不受影响。
  const CharacterDraft({
    required this.name,
    required this.description,
    required this.personality,
    required this.scenario,
    required this.firstMes,
    required this.mesExample,
    required this.systemPrompt,
    required this.postHistoryInstructions,
    this.alternateGreetings = const <String>[],
    required this.tags,
    this.creator = '',
    this.version = '1.0',
    this.creatorNotes = const <String, dynamic>{},
    this.extensions = const <String, dynamic>{},
    this.avatar,
    required this.temperature,
    this.presetDialogues = const <Map<String, String>>[],
    this.promptMode = 'simple',
    this.expertPrompt = '',
    this.lorebookEntries = const <LorebookEntryDraft>[],
  });

  /// 角色名称（已 strip + 截断 100，非空由 [fromV2Card] 保证）。
  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final String mesExample;
  final String systemPrompt;
  final String postHistoryInstructions;
  final List<String> alternateGreetings;
  final List<String> tags;
  final String creator;
  final String version;
  final Map<String, dynamic> creatorNotes;
  final Map<String, dynamic> extensions;

  /// 头像 data URI / URL（无则 null）。
  final String? avatar;
  final double temperature;

  /// 预设对话列表（NPD-02；`extensions.conver_system.preset_dialogues` 读回后经
  /// [_normalizePresetDialogues] 归一化的 `{name, content}` 列表）。
  final List<Map<String, String>> presetDialogues;

  /// 组装模式（simple/expert，缺省 simple；NPD-04，桌面 PD-5）。
  final String promptMode;

  /// 专家模式整段 system prompt（缺省空串；NPD-04，桌面 PD-5）。
  final String expertPrompt;

  /// `extensions.conver_system.character_book` 解析出的世界书条目草案
  /// （WL-01；畸形/缺失 → 空列表，不阻断导入）。
  final List<LorebookEntryDraft> lorebookEntries;

  /// 转换为此角色字段对应的落库 `CharactersCompanion`（导入装配用）。
  ///
  /// 字段映射与 [CharacterDraft] 定义同位单一来源；`avatar` 为 null 时使用
  /// `Value.absent()`（保持列默认 null），其余字段显式给值。
  CharactersCompanion toCompanion() {
    return CharactersCompanion(
      name: Value(name),
      description: Value(description),
      personality: Value(personality),
      scenario: Value(scenario),
      firstMes: Value(firstMes),
      mesExample: Value(mesExample),
      systemPrompt: Value(systemPrompt),
      postHistoryInstructions: Value(postHistoryInstructions),
      alternateGreetings: Value(alternateGreetings),
      tags: Value(tags),
      creator: Value(creator),
      version: Value(version),
      creatorNotes: Value(creatorNotes),
      extensions: Value(extensions),
      avatar: avatar == null ? const Value.absent() : Value(avatar!),
      temperature: Value(temperature),
      presetDialogues: Value(presetDialogues),
      promptMode: Value(promptMode),
      expertPrompt: Value(expertPrompt),
    );
  }
}

// V2 信封标识（桌面 `character_card.py` SPEC / SPEC_VERSION 逐字）。
const _spec = 'chara_card_v2';
const _specVersion = '2.0';

// Conver System 私有命名空间：承载 temperature / URL 头像 / lorebook 等非
// V2 标准字段（桌面 `_NS`）。
const _nsKey = 'conver_system';

// V1 旧卡字段名 → V2/DB 字段名映射（8 项，桌面 `character_fields.py`
// V1_TO_V2_MAP 逐字）。
const _v1ToV2Map = <String, String>{
  'char_name': 'name',
  'char_persona': 'personality',
  'char_greeting': 'first_mes',
  'example_dialogue': 'mes_example',
  'world_scenario': 'scenario',
  'creatorcomment': 'creator_notes',
  'char_version': 'character_version',
  'description': 'description',
};

/// 角色 ORM → V2 信封 Map（导出用）。
///
/// 非 V2 标准字段（temperature / URL 头像 / preset_dialogues / lorebook 等）
/// 经 `extensions.conver_system` 命名空间保真，保证导出→导入往返不丢数据。
///
/// 返回 V2 信封 Map（spec + spec_version + data）；不抛异常。
Map<String, dynamic> toV2Card(Character char) {
  final extensions = _asDict(char.extensions);
  final ns = _converSystem(extensions);

  // temperature：以 DB 实时值为准写入命名空间。
  ns['temperature'] = char.temperature;

  // NPD-02 预设对话：写入 conver_system 命名空间（不落 data 顶层，与
  // temperature/avatar_url 同归类）；空列表不写（对齐桌面
  // `if char.preset_dialogues` 语义——空态导出不产生伪键）。
  if (char.presetDialogues.isNotEmpty) {
    ns['preset_dialogues'] = char.presetDialogues;
  }

  // PD-5 专家模式：非默认值写入命名空间（对齐桌面 `if char.prompt_mode ==
  // "expert"` / `if char.expert_prompt` 语义）——默认 simple / 空串不落卡；
  // expert + 空 prompt 时 mode 保真、空 prompt 不落卡（验收 6）。
  if (char.promptMode == 'expert') {
    ns['prompt_mode'] = char.promptMode;
  }
  if (char.expertPrompt.isNotEmpty) {
    ns['expert_prompt'] = char.expertPrompt;
  }

  // 头像：base64 data URI → data.avatar（去前缀，ST 兼容）；URL → 命名空间
  // avatar_url；无头像两者皆缺。
  final avatar = char.avatar;
  String? dataAvatar;
  if (avatar != null && _isDataUri(avatar)) {
    dataAvatar = _extractRawBase64(avatar);
    ns.remove('avatar_url');
  } else if (avatar != null && avatar.isNotEmpty) {
    ns['avatar_url'] = avatar;
  }

  extensions[_nsKey] = ns;

  return <String, dynamic>{
    'spec': _spec,
    'spec_version': _specVersion,
    'data': <String, dynamic>{
      'name': char.name,
      'description': char.description,
      'personality': char.personality,
      'scenario': char.scenario,
      'first_mes': char.firstMes,
      'mes_example': char.mesExample,
      'system_prompt': char.systemPrompt,
      'post_history_instructions': char.postHistoryInstructions,
      'alternate_greetings': char.alternateGreetings,
      'tags': char.tags,
      'creator': char.creator,
      'character_version': char.version,
      'creator_notes': char.creatorNotes,
      'avatar': dataAvatar,
      'extensions': extensions,
    },
  };
}

/// 角色卡 JSON（任意类型）→ 可落库的角色字段快照（导入用）。
///
/// 识别优先级：
///   1. V2 信封（spec == "chara_card_v2"，取 data）
///   2. 无 spec 的 data 信封（宽容：顶层含 data 且 data 含 name）
///   3. V1 旧卡（顶层含 char_name，字段归一化）
///   4. 裸 data（顶层含 name）
/// 无法识别 → 抛 [CardFormatException]；内容不合法（名称空）→ 抛
/// [CardValidationException]。
///
/// 入参为 `dynamic`：JSON 解码结果可能是任意类型（list / 字符串 / 数字等），
/// 非 Map 一律按「角色卡必须是 JSON 对象」格式错处理（桌面 422 语义）。
CharacterDraft fromV2Card(dynamic card) {
  if (card is! Map) {
    throw const CardFormatException('角色卡必须是 JSON 对象');
  }

  final spec = card['spec'];
  final Map<String, dynamic> data;
  if (spec == _spec) {
    final rawData = card['data'];
    if (rawData is! Map) {
      throw const CardFormatException('角色卡缺少 data 字段');
    }
    data = _stringKeyedMap(rawData);
  } else if (spec != null) {
    throw CardFormatException('不支持的卡片规格: $spec');
  } else if (card['data'] is Map && (card['data']! as Map).containsKey('name')) {
    data = _stringKeyedMap(card['data']! as Map);
  } else if (card.containsKey('char_name')) {
    data = _normalizeV1(card);
  } else if (card.containsKey('name')) {
    data = _stringKeyedMap(card);
  } else {
    throw const CardFormatException('无法识别的角色卡格式');
  }

  return _buildCreate(data);
}

/// V1 旧卡字段名 → V2/DB 字段名（映射单一来源 [_v1ToV2Map]）。
Map<String, dynamic> _normalizeV1(Map card) {
  final result = <String, dynamic>{};
  for (final entry in _v1ToV2Map.entries) {
    final v1 = entry.key;
    final v2 = entry.value;
    final value = card[v1];
    if (value != null) {
      result[v2] = value;
    }
  }
  return result;
}

/// 归一化后的 data Map → [CharacterDraft]（含类型容错与边界裁剪）。
CharacterDraft _buildCreate(Map<String, dynamic> data) {
  final name = (data['name']?.toString() ?? '').trim();
  if (name.isEmpty) {
    throw const CardValidationException('角色名称不能为空');
  }
  final trimmedName = _truncate(name, 100);

  final extensions = _asDict(data['extensions']);
  final ns = _converSystem(extensions);

  // 头像：data.avatar（base64 / data URI / URL）优先，其次命名空间 avatar_url。
  final rawAvatar = data['avatar'];
  final String? avatarValue;
  if (rawAvatar is String && rawAvatar.isNotEmpty) {
    avatarValue = _toDataUri(rawAvatar);
  } else {
    avatarValue = ns['avatar_url']?.toString();
  }

  // temperature：命名空间优先，其次裸 data 顶层（容错），无则默认 0.7，并
  // 裁剪到 [0, 2] 合法区间。
  final temperature = _clampTemperature(ns['temperature'] ?? data['temperature'] ?? 0.7);

  // WL-01：character_book 解析为世界书条目草案（畸形降级不抛，SR-26）；
  // extensions 原始 character_book 保持原样（保真零回归，见库文档）。
  final lorebookEntries = parseCharacterBook(ns['character_book']);

  // NPD-02 预设对话：conver_system 命名空间读回并归一化（桌面
  // `_normalize_preset_dialogues` 逐字；None/非 list/标量 → []、空字段过滤、
  // trim 同名去重、超 10 截断——SR-26，脏数据收敛不阻断导入）。
  final presetDialogues = _normalizePresetDialogues(ns['preset_dialogues']);

  // PD-5 专家模式：conver_system 命名空间往返（对齐桌面
  // `prompt_mode = str(ns.get("prompt_mode") or "simple")` /
  // `expert_prompt = str(ns.get("expert_prompt") or "")` 的 falsy 归默认语义；
  // 非默认值具备 int → str 化保留的容错——[CharacterDraft] 构造默认值兜底）。
  final promptMode = _nsField(ns['prompt_mode'], 'simple');
  final expertPrompt = _nsField(ns['expert_prompt'], '');

  final version = _truncate(
    (data['character_version'] ?? data['version'] ?? '1.0').toString(),
    50,
  );

  return CharacterDraft(
    name: trimmedName,
    description: data['description']?.toString() ?? '',
    personality: data['personality']?.toString() ?? '',
    scenario: data['scenario']?.toString() ?? '',
    firstMes: data['first_mes']?.toString() ?? '',
    mesExample: data['mes_example']?.toString() ?? '',
    systemPrompt: data['system_prompt']?.toString() ?? '',
    postHistoryInstructions: data['post_history_instructions']?.toString() ?? '',
    alternateGreetings: _asList(data['alternate_greetings']),
    tags: _asList(data['tags']),
    creator: data['creator']?.toString() ?? '',
    version: version,
    creatorNotes: _asDict(data['creator_notes']),
    extensions: extensions,
    avatar: avatarValue,
    temperature: temperature,
    presetDialogues: presetDialogues,
    promptMode: promptMode,
    expertPrompt: expertPrompt,
    lorebookEntries: lorebookEntries,
  );
}

// ── 内部辅助 ──

/// 前 [max] 个 UTF-16 码元（中文 BMP 字符单码元，等价桌面 `[:max]` 截断）。
String _truncate(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

/// 是否为 `data:image/...;base64,` 形式的头像（桌面 `_is_data_uri`）。
bool _isDataUri(String value) => value.startsWith('data:image/');

/// 从 data URI 提取原始 base64（去 `data:image/...;base64,` 前缀）。
String _extractRawBase64(String value) {
  const prefix = ';base64,';
  final index = value.indexOf(prefix);
  return index < 0 ? value : value.substring(index + prefix.length);
}

/// 按 base64 解码后的魔数推断 MIME 类型，失败默认 png。
///
/// 对齐桌面 `_infer_mime`：解码前 32 字符（不足则全串）；解码失败（非法
/// base64）或魔数未知一律回退 `png`，不使导入请求失败。
String _inferMime(String rawBase64) {
  final headText = rawBase64.length <= 32 ? rawBase64 : rawBase64.substring(0, 32);
  List<int> head;
  try {
    head = base64Decode(headText);
  } catch (_) {
    // dart:convert 对非法 base64 抛 FormatException；与桌面 binascii.Error/
    // ValueError 容错哲学一致——脏头像默认 png，不阻断导入。
    return 'png';
  }
  if (head.length >= 4 && head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4e && head[3] == 0x47) {
    return 'png';
  }
  if (head.length >= 2 && head[0] == 0xff && head[1] == 0xd8) {
    return 'jpeg';
  }
  if (head.length >= 4 &&
      head[0] == 0x47 && head[1] == 0x49 && head[2] == 0x46 && head[3] == 0x38) {
    return 'gif';
  }
  if (head.length >= 12 &&
      head[0] == 0x52 && head[1] == 0x49 && head[2] == 0x46 && head[3] == 0x46 &&
      head[8] == 0x57 && head[9] == 0x45 && head[10] == 0x42 && head[11] == 0x50) {
    return 'webp';
  }
  return 'png';
}

/// 头像 → data URI（已含前缀或为 URL 则原样保留；裸 base64 则包装）。
String _toDataUri(String avatar) {
  if (_isDataUri(avatar) ||
      avatar.startsWith('http://') ||
      avatar.startsWith('https://')) {
    return avatar;
  }
  return 'data:image/${_inferMime(avatar)};base64,$avatar';
}

/// 容忍脏数据：None → []，list → str 化列表，其它 → 单值包裹。
List<String> _asList(Object? value) {
  if (value == null || value == '') {
    return const [];
  }
  if (value is List) {
    return [for (final v in value) v.toString()];
  }
  return [value.toString()];
}

/// 容忍脏数据：None → {}，Map → 原样，纯文本 → `{"text": value}`（V1
/// creatorcomment）。
Map<String, dynamic> _asDict(Object? value) {
  if (value == null) {
    return <String, dynamic>{};
  }
  if (value is Map) {
    return _stringKeyedMap(value);
  }
  if (value is String && value.trim().isNotEmpty) {
    return <String, dynamic>{'text': value};
  }
  return <String, dynamic>{};
}

/// 取 extensions 中的 conver_system 命名空间（不存在 / 非 Map 返回空 Map）。
Map<String, dynamic> _converSystem(Map<String, dynamic> extensions) {
  final ns = extensions[_nsKey];
  return ns is Map ? _stringKeyedMap(ns) : <String, dynamic>{};
}

/// 预设对话归一化：非 list → []；逐项 name/content trim 非空；按 name 去重
/// 保留首个；截断至 [presetDialogueMax]。
///
/// NPD-02（桌面 `character_card.py::_normalize_preset_dialogues` 逐字移植）：
/// PD-4 预设对话导入侧容错——脏数据（None / 非 list / 空字段 / 同名重复 /
/// 超量）全部收敛为「干净 list[dict]」，再交落库装配（SR-26 解析失败降级
/// 不阻断导入）。
List<Map<String, String>> _normalizePresetDialogues(Object? value) {
  if (value is! List) {
    return const <Map<String, String>>[];
  }
  final result = <Map<String, String>>[];
  final seen = <String>{};
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final name = _presetField(item['name']);
    final content = _presetField(item['content']);
    if (name.isEmpty || content.isEmpty) {
      continue;
    }
    if (!seen.add(name)) {
      continue;
    }
    result.add(<String, String>{'name': name, 'content': content});
    if (result.length >= presetDialogueMax) {
      break;
    }
  }
  return result;
}

/// 预设对话字段 str()（含 falsy 归一）——桌面 `str(item.get(k) or "")` 的 Dart
/// 等价：null / 空串 / 假值（false / 0）→ 空串，其余 `toString()` 后 trim。
///
/// 逐字对齐桌面 `_normalize_preset_dialogues` 的 `or ""` 判定（Python falsy
/// 语义：None / '' / False / 0 归空；非零数值与 truthy 布尔经 str() 保留——
/// 桌面契约锁用例 `int → "123"` 即由此保证）。
String _presetField(Object? value) {
  if (value == null || value == '' || value == false || value == 0) {
    return '';
  }
  return value.toString().trim();
}

/// 专家模式命名空间字段 str()（falsy 归默认）——桌面
/// `str(ns.get("prompt_mode") or "simple")` / `str(ns.get("expert_prompt") or "")`
/// 的 Dart 等价：null / 空串 / 假值（false / 0）→ [fallback]，其余
/// `toString()` **原样不 trim**（对齐桌面 str() 无 trim；`int → "123"` 容错）。
String _nsField(Object? value, String fallback) {
  if (value == null || value == '' || value == false || value == 0) {
    return fallback;
  }
  return value.toString();
}

/// 温度值裁剪到 [0, 2] 合法区间，非法值回退默认 0.7（桌面 `_clamp_temperature`）。
double _clampTemperature(Object? value) {
  if (value == null) {
    return 0.7;
  }
  final temp = double.tryParse(value.toString());
  // Falsify：JSON 字面量 NaN 被 jsonDecode 宽容接受，double.tryParse 返回
  // NaN（非 null）——NaN.clamp 仍 NaN 会在导出 jsonEncode 抛错 / debug Slider
  // 断言，故显式 isNaN 归回默认。
  if (temp == null || temp.isNaN) {
    return 0.7;
  }
  return temp.clamp(0.0, 2.0).toDouble();
}

/// Map 键统一转 String（JSON 解码结果 / 字面量均为 String 键，防御性转换）。
Map<String, dynamic> _stringKeyedMap(Map map) =>
    <String, dynamic>{for (final entry in map.entries) entry.key.toString(): entry.value};
