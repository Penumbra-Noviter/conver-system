/// 分支快照（BR-01）— 版本化导出/导入契约模型 + JSON 编解码 + 结构校验。
///
/// 语义锚点（只读，逐字对齐）：
/// `desktop/backend/app/schemas/branch.py`（SNAPSHOT_VERSION / BranchSnapshot
/// 及其子模型）与 `services/conversation_export.py::validate_branch_snapshot`
/// （版本缺失/不支持 → 明确异常；结构畸形 → 明确异常）。
///
/// 本文件纯 Dart 零 I/O（模型层）：[BranchSnapshot.toJson] 产出 spec §4.7
/// 载荷，[BranchSnapshot.fromJson] 做版本校验（SR-30）与字段结构校验
/// （messages / lorebook_entries / swipes 类型与取值域）——两错误类型与
/// 结构畸形严格分离：
/// - [BranchSnapshotUnsupportedVersionError]：version 缺失 / 未知（拒绝导入）；
/// - [InvalidBranchSnapshotError]：字段结构校验失败（类型 / 取值域）。
///
/// 结构校验只做**单体字段**约束（类型与取值域），跨字段不变量
/// （message_index < messages.length、active_swipe_index 在候选内、
/// content == 激活候选）由 `branch_service.dart::cloneFromSnapshot` 在
/// 重建时校验（同抛 [InvalidBranchSnapshotError]，桌面 clone 防御矩阵对应物）。
library;

import '../llm/errors.dart' show DomainError;

/// 当前快照版本（版本化导出/导入契约；未知版本拒绝导入，SR-30）。
///
/// 单一来源（对齐桌面 `schemas/branch.py::SNAPSHOT_VERSION`）。
const int snapshotVersion = 1;

/// 快照版本不支持 — version 缺失或未知时拒绝导入（SR-30 明确异常）。
///
/// 对应桌面 `BranchSnapshotError` 的「未知版本拒绝」分支；与结构畸形
/// （[InvalidBranchSnapshotError]）分离，供 UI 映射「快照版本不支持」文案
/// （BR-02）。
class BranchSnapshotUnsupportedVersionError extends DomainError {
  BranchSnapshotUnsupportedVersionError(super.message);
}

/// 快照结构无效 — 字段结构校验失败（类型 / 取值域）时抛（SR-30）。
///
/// 对应桌面 `BranchSnapshotError` 的「结构畸形」分支（pydantic
/// ValidationError 包装）；供 UI 映射「快照格式无效」文案（BR-02），不泄露
/// 解析细节。
class InvalidBranchSnapshotError extends DomainError {
  InvalidBranchSnapshotError(super.message);
}

/// 消息快照（role / content / created_at 往返保真；对齐桌面
/// `schemas/branch.py::BranchSnapshotMessage`）。
class BranchSnapshotMessage {
  const BranchSnapshotMessage({
    required this.role,
    required this.content,
    this.createdAt,
  });

  /// 消息角色（'user' / 'assistant' / 'system'，对齐桌面 Role.value）。
  final String role;

  /// 消息正文（恒为当前激活候选，桌面「content 跟随激活候选」不变量）。
  final String content;

  /// 创建时间（UTC；可空——缺省由重建方赋值，桌面 `datetime | None`）。
  final DateTime? createdAt;

  /// 序列化为快照 JSON 消息项（created_at 走 UTC ISO 字符串，可空）。
  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };
}

/// 消息候选快照（对齐桌面 `schemas/branch.py::BranchSnapshotSwipe`）。
///
/// [messageIndex] 指向快照内 messages 数组下标（截断后重新编号，重建按序
/// 填充——新会话重建后 id 变化，以序号锚定）；[swipes] 为 index 升序候选
/// content 列表；[activeSwipeIndex] 为激活候选序号（缺省 0）。
class BranchSnapshotSwipe {
  const BranchSnapshotSwipe({
    required this.messageIndex,
    this.swipes = const <String>[],
    this.activeSwipeIndex = 0,
  });

  /// 该候选归属消息在快照 messages 数组中的下标（≥0）。
  final int messageIndex;

  /// 候选 content 列表（index 升序；候选 0 = 消息原始内容）。
  final List<String> swipes;

  /// 激活候选序号（≥0；桌面 Field ge=0）。
  final int activeSwipeIndex;

  /// 序列化为快照 JSON 候选项。
  Map<String, dynamic> toJson() => {
    'message_index': messageIndex,
    'swipes': swipes,
    'active_swipe_index': activeSwipeIndex,
  };
}

/// 世界书条目快照（重建用全部内容字段；对齐桌面
/// `schemas/branch.py::BranchSnapshotLorebookEntry`，字段与
/// `LorebookEntryDraft` 一一对应——character_id 由导入方按新会话设置）。
class BranchSnapshotLorebookEntry {
  const BranchSnapshotLorebookEntry({
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

  /// 条目标题（桌面 String(200) 语义）。
  final String title;

  /// 触发关键词（JSON 数组语义）。
  final List<String> keys;

  /// 命中后注入内容。
  final String content;

  /// 常驻（不判命中直接注入）。
  final bool constant;

  /// 命中条目排序（域 [0,9999]）。
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

  /// 参与命中的最近轮数（域 [0,20]）。
  final int depth;

  /// 条目来源（manual / auto）。
  final String source;

  /// 单条开关。
  final bool enabled;

  /// 序列化为快照 JSON 世界书条目项。
  Map<String, dynamic> toJson() => {
    'title': title,
    'keys': keys,
    'content': content,
    'constant': constant,
    'order': order,
    'probability': probability,
    'group_name': groupName,
    'group_weight': groupWeight,
    'match_mode': matchMode,
    'position': position,
    'depth': depth,
    'source': source,
    'enabled': enabled,
  };
}

/// 分支快照（版本化导出/导入契约；BR-2 重建会话的唯一输入）。
///
/// 载荷（spec §4.7 / 桌面 BranchSnapshot 逐字段）：
/// `{version, character_id, model_provider, model_name, title, messages,
/// lorebook_entries, swipes}`。构建方（BranchService.buildBranchSnapshot）
/// 负责产出合法载荷；[BranchSnapshot.fromJson] 负责从外部 JSON 拒绝未知
/// 版本与畸形结构（SR-30）。
class BranchSnapshot {
  const BranchSnapshot({
    this.version = snapshotVersion,
    required this.characterId,
    this.modelProvider,
    this.modelName,
    this.title,
    this.messages = const <BranchSnapshotMessage>[],
    this.lorebookEntries = const <BranchSnapshotLorebookEntry>[],
    this.swipes = const <BranchSnapshotSwipe>[],
  });

  /// 快照版本（当前 [snapshotVersion]）。
  final int version;

  /// 快照角色 id（重建会话的 character_id）。
  final int characterId;

  /// 会话模型 provider（可空；重建时缺省走设置默认）。
  final String? modelProvider;

  /// 会话模型名（可空；重建时缺省走设置默认）。
  final String? modelName;

  /// 会话标题（可空；重建时缺省走角色占位标题）。
  final String? title;

  /// 消息快照（重建按序填充）。
  final List<BranchSnapshotMessage> messages;

  /// 世界书条目快照（重建复制为独立行，互不影响——BR-01 契约）。
  final List<BranchSnapshotLorebookEntry> lorebookEntries;

  /// 候选快照（message_index 指向本快照 messages 数组下标）。
  final List<BranchSnapshotSwipe> swipes;

  /// 序列化为快照 JSON（键序对齐桌面 `model_dump` 输出序）。
  Map<String, dynamic> toJson() => {
    'version': version,
    'character_id': characterId,
    'model_provider': modelProvider,
    'model_name': modelName,
    'title': title,
    'messages': [for (final message in messages) message.toJson()],
    'lorebook_entries': [for (final entry in lorebookEntries) entry.toJson()],
    'swipes': [for (final swipe in swipes) swipe.toJson()],
  };

  /// 从外部 JSON（jsonDecode 产物）解码并校验快照（SR-30）。
  ///
  /// - 非 JSON 对象 → [InvalidBranchSnapshotError]；
  /// - version 缺失 / 非 [snapshotVersion] → [BranchSnapshotUnsupportedVersionError]；
  /// - 字段结构校验失败（类型 / 取值域）→ [InvalidBranchSnapshotError]。
  ///
  /// 缺省语义对齐桌面 pydantic default_factory：messages / lorebook_entries /
  /// swipes 缺省空列表；model_provider / model_name / title 可空。
  factory BranchSnapshot.fromJson(Object? data) {
    if (data is! Map) {
      throw InvalidBranchSnapshotError('快照格式无效：应为 JSON 对象');
    }
    final raw = data.cast<String, Object?>();
    final version = raw['version'];
    if (version == null) {
      throw BranchSnapshotUnsupportedVersionError('快照缺少版本号（version 字段），无法识别格式');
    }
    if (version != snapshotVersion) {
      throw BranchSnapshotUnsupportedVersionError(
        '不支持的快照版本: $version（当前支持版本 $snapshotVersion）',
      );
    }
    return BranchSnapshot(
      version: snapshotVersion,
      characterId: _requireInt(raw, 'character_id'),
      modelProvider: _optionalString(raw, 'model_provider'),
      modelName: _optionalString(raw, 'model_name'),
      title: _optionalString(raw, 'title'),
      messages: _messageList(raw['messages']),
      lorebookEntries: _lorebookList(raw['lorebook_entries']),
      swipes: _swipeList(raw['swipes']),
    );
  }

  // ── 结构校验内部 ──

  /// 字段校验失败统一构造（含字段路径与原因，文案不泄露解析细节——仅错误
  /// 类型承载 UI 分类，SR-30）。
  static InvalidBranchSnapshotError _invalid(
    String field,
    Object? value,
    String reason,
  ) {
    return InvalidBranchSnapshotError('快照字段 $field 无效：$reason');
  }

  /// 必填整数（缺失 / 非 int → 校验失败）。
  static int _requireInt(Map<String, Object?> raw, String field) {
    final value = raw[field];
    if (value is! int) {
      throw _invalid(field, value, '应为整数');
    }
    return value;
  }

  /// 可空整数（非 int 显式值 → 校验失败）。
  static int? _optionalInt(Map<String, Object?> raw, String field) {
    final value = raw[field];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw _invalid(field, value, '应为整数');
    }
    return value;
  }

  /// 可空字符串（非 String 显式值 → 校验失败）。
  static String? _optionalString(Map<String, Object?> raw, String field) {
    final value = raw[field];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw _invalid(field, value, '应为字符串');
    }
    return value;
  }

  /// 可空布尔（非 bool 显式值 → 校验失败；'true'/'1' 等字符串不隐式转换）。
  static bool? _optionalBool(Map<String, Object?> raw, String field) {
    final value = raw[field];
    if (value == null) {
      return null;
    }
    if (value is! bool) {
      throw _invalid(field, value, '应为布尔值');
    }
    return value;
  }

  /// 可空 ISO 时间字符串（不可解析 → 校验失败）。
  static DateTime? _optionalDateTime(Map<String, Object?> raw, String field) {
    final value = raw[field];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw _invalid(field, value, '应为 ISO 时间字符串');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw _invalid(field, value, '应为可解析的 ISO 时间字符串');
    }
    return parsed;
  }

  /// 字符串列表（null → 空列表；非列表 / 非字符串元素 → 校验失败）。
  static List<String> _stringList(Object? value, String field) {
    if (value == null) {
      return const <String>[];
    }
    if (value is! List) {
      throw _invalid(field, value, '应为字符串列表');
    }
    return value.map((item) {
      if (item is! String) {
        throw _invalid(field, item, '应为字符串元素');
      }
      return item;
    }).toList();
  }

  /// messages 列表解析（null → 空列表；非列表 → 校验失败）。
  static List<BranchSnapshotMessage> _messageList(Object? value) {
    if (value == null) {
      return const <BranchSnapshotMessage>[];
    }
    if (value is! List) {
      throw _invalid('messages', value, '应为列表');
    }
    return [for (final item in value) _parseMessage(item)];
  }

  /// 单条消息解析：role 必填且 ∈ {user, assistant, system}、content 必填、
  /// created_at 可空 ISO。
  static BranchSnapshotMessage _parseMessage(Object? item) {
    if (item is! Map) {
      throw _invalid('messages[].entry', item, '应为 JSON 对象');
    }
    final raw = item.cast<String, Object?>();
    final role = _optionalString(raw, 'role');
    if (role == null || !_validRoles.contains(role)) {
      throw _invalid('messages[].role', role, '非法角色（应为 user/assistant/system）');
    }
    final content = _optionalString(raw, 'content');
    if (content == null) {
      throw _invalid('messages[].content', null, '必填');
    }
    return BranchSnapshotMessage(
      role: role,
      content: content,
      createdAt: _optionalDateTime(raw, 'created_at'),
    );
  }

  /// lorebook_entries 列表解析（null → 空列表；非列表 → 校验失败）。
  static List<BranchSnapshotLorebookEntry> _lorebookList(Object? value) {
    if (value == null) {
      return const <BranchSnapshotLorebookEntry>[];
    }
    if (value is! List) {
      throw _invalid('lorebook_entries', value, '应为列表');
    }
    return [for (final item in value) _parseLorebookEntry(item)];
  }

  /// 单条世界书条目解析：全部字段可选（对齐桌面默认），显式值类型严格。
  static BranchSnapshotLorebookEntry _parseLorebookEntry(Object? item) {
    if (item is! Map) {
      throw _invalid('lorebook_entries[].entry', item, '应为 JSON 对象');
    }
    final raw = item.cast<String, Object?>();
    return BranchSnapshotLorebookEntry(
      title: _optionalString(raw, 'title') ?? '',
      keys: _stringList(raw['keys'], 'lorebook_entries[].keys'),
      content: _optionalString(raw, 'content') ?? '',
      constant: _optionalBool(raw, 'constant') ?? false,
      order: _optionalInt(raw, 'order') ?? 100,
      probability: _optionalInt(raw, 'probability') ?? 100,
      groupName: _optionalString(raw, 'group_name') ?? '',
      groupWeight: _optionalInt(raw, 'group_weight') ?? 100,
      matchMode: _optionalString(raw, 'match_mode') ?? 'or',
      position: _optionalString(raw, 'position') ?? 'world',
      depth: _optionalInt(raw, 'depth') ?? 20,
      source: _optionalString(raw, 'source') ?? 'manual',
      enabled: _optionalBool(raw, 'enabled') ?? true,
    );
  }

  /// swipes 列表解析（null → 空列表；非列表 → 校验失败）。
  static List<BranchSnapshotSwipe> _swipeList(Object? value) {
    if (value == null) {
      return const <BranchSnapshotSwipe>[];
    }
    if (value is! List) {
      throw _invalid('swipes', value, '应为列表');
    }
    return [for (final item in value) _parseSwipe(item)];
  }

  /// 单条候选解析：message_index 必填整数 ≥0、active_swipe_index ≥0、
  /// swipes 为字符串列表（跨数组下标校验在重建时，见类 docstring）。
  static BranchSnapshotSwipe _parseSwipe(Object? item) {
    if (item is! Map) {
      throw _invalid('swipes[].entry', item, '应为 JSON 对象');
    }
    final raw = item.cast<String, Object?>();
    final messageIndex = _requireInt(raw, 'message_index');
    if (messageIndex < 0) {
      throw _invalid('swipes[].message_index', messageIndex, '不得为负');
    }
    final active = _optionalInt(raw, 'active_swipe_index') ?? 0;
    if (active < 0) {
      throw _invalid('swipes[].active_swipe_index', active, '不得为负');
    }
    return BranchSnapshotSwipe(
      messageIndex: messageIndex,
      swipes: _stringList(raw['swipes'], 'swipes[].swipes'),
      activeSwipeIndex: active,
    );
  }
}

/// 合法消息角色集合（对齐桌面 `Role` 枚举 .value 集合）。
const Set<String> _validRoles = {'user', 'assistant', 'system'};
