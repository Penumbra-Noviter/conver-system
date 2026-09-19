/// 世界书激活引擎（WL-02）— 纯函数，零数据库 / 零 IO / 零第三方依赖。
///
/// 协议表面（导出符号）：[LorebookEntryData] / [activateLorebookEntries] /
/// [buildWorldInjection] / [collectScanText]，另附带注入段容器
/// [InjectedSegment] 与来源常量 [sourceWorld] / [sourceMemory]。命中判定、
/// 概率/互斥组抽取、按 position 分组构建注入块全部无副作用；RNG 注入
/// （[Random] 同种子）可复现（同种子两次调用结果一致）。
///
/// 语义对齐 SillyTavern World Info（spec §WL-2，桌面
/// `lorebook_engine.py` 逐字移植）：
/// - constant=true 直进（不判命中）；or/and 子串匹配，大小写不敏感，
///   空白 key 剔除、key 周边空白 trim 后参与；
/// - depth 由 [collectScanText] 落实（0..20，>20 裁剪，<0 视为 0；
///   system 指令不计轮）；
/// - probability：0 必弃 / 100 必进（均不消耗 RNG）/ 中间值掷点；
/// - group_name 非空：同组按 group_weight 加权抽一（权重兜底 ≥1）；
///   无组条目全部入选；
/// - 输出按 (order, id) 升序（确定性锁定）。
///
/// 与桌面差异（仅一处，工单验收 8 要求）：[buildWorldInjection] 对模板
/// 替换后为空的 content 做过滤，不产生空注入段；桌面原实现原样保留空段。
/// 详见 `chat-polish-aigs/concerns/07.md`。
library;

import 'dart:math';

import 'package:conver_system_mobile/services/template_vars.dart';

/// depth 上限（spec：0..20）。
const int maxDepth = 20;

/// 注入段来源标记：世界书手动条目（world）。
const String sourceWorld = 'world';

/// 注入段来源标记：记忆宫殿 auto 条目（memory）。
const String sourceMemory = 'memory';

/// 带来源的注入分段（世界书/记忆注入项，来源追溯）。
///
/// 对齐桌面 `prompt.py::InjectedSegment`：content 为经模板变量替换后的注入
/// 内容；source 取值 [sourceWorld] 或 [sourceMemory]，默认 world。
class InjectedSegment {
  const InjectedSegment({
    required this.content,
    this.source = sourceWorld,
  });

  /// 注入内容（已做过模板变量替换）。
  final String content;

  /// 来源（world=世界书手动条目 / memory=记忆宫殿 auto 条目）。
  final String source;

  @override
  bool operator ==(Object other) {
    return other is InjectedSegment &&
        other.content == content &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(content, source);
}

/// 引擎输入条目（纯数据容器，与 ORM 解耦，不可变风格）。
///
/// 对齐桌面 `lorebook_engine.py::LorebookEntryData`，字段一一对应：
/// [id] 为输出稳定排序的同序决胜键；[keys] 为触发关键词（or/and 子串
/// 匹配，空 key 不参与，视为只读、调用方不得修改）；[content] 为命中后
/// 注入内容；[constant] 常驻（不判命中直接入选）；[order] 输出排序（升序）；
/// [probability] 独立命中概率（0 必弃 / 100 必进）；[groupName] 互斥组名
/// （空=不分组）；[groupWeight] 组内加权抽一权重；[matchMode] or（任一
/// key）/ and（全部 key）；[position] 注入位置（world / before_char /
/// after_char）；[enabled] 单条开关（false 不参与）。
class LorebookEntryData {
  const LorebookEntryData({
    required this.id,
    this.keys = const <String>[],
    this.content = '',
    this.constant = false,
    this.order = 100,
    this.probability = 100,
    this.groupName = '',
    this.groupWeight = 100,
    this.matchMode = 'or',
    this.position = 'world',
    this.enabled = true,
  });

  /// 条目主键（输出稳定排序的同序决胜键）。
  final int id;

  /// 触发关键词（or/and 子串匹配；空 key 不参与；调用方应视为只读）。
  final List<String> keys;

  /// 命中后注入内容（buildWorldInjection 输出源）。
  final String content;

  /// 常驻（不判命中直接入选）。
  final bool constant;

  /// 输出排序（升序）。
  final int order;

  /// 独立命中概率（0 必弃 / 100 必进）。
  final int probability;

  /// 互斥组名（空=不分组）。
  final String groupName;

  /// 组内加权抽一权重。
  final int groupWeight;

  /// 命中模式：or（任一 key）/ and（全部 key）。
  final String matchMode;

  /// 注入位置（world / before_char / after_char）。
  final String position;

  /// 单条开关（false 不参与）。
  final bool enabled;

  @override
  bool operator ==(Object other) {
    return other is LorebookEntryData &&
        other.id == id &&
        _listEquals(other.keys, keys) &&
        other.content == content &&
        other.constant == constant &&
        other.order == order &&
        other.probability == probability &&
        other.groupName == groupName &&
        other.groupWeight == groupWeight &&
        other.matchMode == matchMode &&
        other.position == position &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(
        id,
        Object.hashAll(keys),
        content,
        constant,
        order,
        probability,
        groupName,
        groupWeight,
        matchMode,
        position,
        enabled,
      );
}

/// 命中判定 + 概率/互斥组抽取 + 排序（纯函数，主入口）。
///
/// 流程（顺序即语义，与桌面逐字一致）：
/// 1. enabled=false 剔除；
/// 2. constant 直进；否则 keys 对匹配文本做子串匹配（大小写不敏感，
///    or=任一 key 命中 / and=全部 key 命中；空白 key 剔除、trim 后参与）；
/// 3. 概率闸：>=100 必进、<=0 必弃（均不消耗 RNG）、中间值掷点
///    （[rng.nextDouble] * 100 < probability）；
/// 4. 互斥组：同 [LorebookEntryData.groupName] 按
///    [LorebookEntryData.groupWeight] 加权抽一（每组合计一次 RNG）；
/// 5. 输出按 (order, id) 升序。
///
/// 输入先按 (order, id) 规范化：RNG 消耗序列（概率掷点 + 组抽签）随规范
/// 序，同种子可复现性不随调用方传入顺序漂移（桌面 Falsify 修复锁）。
///
/// 返回命中的条目列表（按 (order, id) 升序）；空 entries / 空匹配文本 →
/// 空列表（零异常）。
List<LorebookEntryData> activateLorebookEntries(
  List<LorebookEntryData> entries,
  String scanText, {
  String currentInput = '',
  Random? rng,
}) {
  final r = rng ?? Random();
  final matchText = scanText.isNotEmpty ? scanText : currentInput;

  final ordered = entries.toList()..sort(_compareOrderId);

  final candidates = <LorebookEntryData>[];
  for (final entry in ordered) {
    if (!entry.enabled) {
      continue;
    }
    if (!entry.constant && !_keysMatch(entry, matchText)) {
      continue;
    }
    if (!_probabilityGate(entry, r)) {
      continue;
    }
    candidates.add(entry);
  }

  final resolved = _resolveGroups(candidates, r);
  resolved.sort(_compareOrderId);
  return resolved;
}

/// 按 position 分组构建带来源注入块（纯函数）。
///
/// 返回 `{system: [...], before_char: [...], after_char: [...]}`：组内按
/// (order, id) 升序；[content] 经 `{{user}}` / `{{char}}` 模板替换（复用
/// `services/template_vars.dart::applyTemplateVars`，与角色字段模板变量
/// 同 seam）。未知 position 回落 world（system 块），不静默丢弃。模板
/// 替换后为空的 content 被过滤，不产生空注入段（工单验收 8；桌面原实现
/// 保留空段，为本模块唯一语义差异）。
///
/// source 标注（PD-3 来源保真）：来源经 entry.id 反查传入的 [sourceById]，
/// [LorebookEntryData] 自身零 source 契约不变——值为 `"auto"` 时标
/// [sourceMemory]，其余（缺省键或非 auto 值）标 [sourceWorld]。
///
/// 空激活集 → system / before_char / after_char 三空键（零异常）。
Map<String, List<InjectedSegment>> buildWorldInjection(
  List<LorebookEntryData> activated, {
  String userName = 'User',
  String charName = 'Character',
  Map<int, String>? sourceById,
}) {
  final blocks = <String, List<InjectedSegment>>{
    'system': <InjectedSegment>[],
    'before_char': <InjectedSegment>[],
    'after_char': <InjectedSegment>[],
  };
  final ordered = activated.toList()..sort(_compareOrderId);
  for (final entry in ordered) {
    final key = _positionKey(entry.position);
    final content = applyTemplateVars(
      entry.content,
      userName: userName,
      charName: charName,
    );
    if (content.isEmpty) {
      continue; // 空注入段过滤（验收 8；桌面差异见库文档）。
    }
    final source = (sourceById ?? const <int, String>{})[entry.id] == 'auto'
        ? sourceMemory
        : sourceWorld;
    blocks[key]!.add(InjectedSegment(content: content, source: source));
  }
  return blocks;
}

/// 构建命中扫描窗口文本（纯函数）。
///
/// depth 语义（spec §WL-2）：0 → 仅 [currentInput]；N → 最近 N 轮 =
/// 2N 条「对话消息」（system 指令不计轮，角色经 [roleOf] 提取，取值
/// `user` / `assistant` 计入窗口）的 content 以换行连接 + [currentInput]。
/// 越界裁剪：>20 → 20；<0 → 0（仅输入）。
///
/// [contentOf] 负责从消息对象提取注入文本（桌面 `getattr(msg,
/// "content", "")` 的强类型等价）；空历史 + 空输入 → 空字符串（零异常）。
String collectScanText<T>(
  List<T> history,
  String currentInput,
  int depth, {
  required String Function(T message) roleOf,
  required String Function(T message) contentOf,
}) {
  final clipped = min(max(depth, 0), maxDepth);
  if (clipped == 0) {
    return currentInput;
  }
  final dialogue = history.where((m) => _dialogueRoles.contains(roleOf(m))).toList();
  final windowLength = 2 * clipped;
  final window = dialogue.length <= windowLength
      ? dialogue
      : dialogue.sublist(dialogue.length - windowLength);
  final parts = <String>[];
  for (final message in window) {
    parts.add(contentOf(message));
  }
  parts.add(currentInput);
  return parts.join('\n');
}

// ── 内部实现 ──

/// 计入「轮」窗口的角色（system 指令是上下文而非对话）。
const Set<String> _dialogueRoles = {'user', 'assistant'};

/// position → 注入块键（未知 position 回落 world → system）。
String _positionKey(String position) {
  switch (position) {
    case 'world':
    case 'before_char':
    case 'after_char':
      return position == 'world' ? 'system' : position;
    default:
      return 'system';
  }
}

/// 子串命中判定：or=任一 key、and=全部 key；空白 key 剔除；大小写不敏感。
///
/// 匹配前去除 key 周边空白（与「空白即剔除」语义一致，桌面 Falsify
/// 修复锁）。keys 有效集合为空 → 永不命中（or 的 any([]) / and 的
/// all([]) 陷阱守卫）。
bool _keysMatch(LorebookEntryData entry, String text) {
  final keys = <String>[];
  for (final key in entry.keys) {
    final stripped = key.trim();
    if (stripped.isNotEmpty) {
      keys.add(stripped);
    }
  }
  if (keys.isEmpty) {
    return false;
  }
  final lowered = text.toLowerCase();
  if (entry.matchMode == 'and') {
    return keys.every((k) => lowered.contains(k.toLowerCase()));
  }
  return keys.any((k) => lowered.contains(k.toLowerCase()));
}

/// 独立概率闸：0 必弃 / 100 必进（均不消耗 RNG）/ 中间值掷点。
bool _probabilityGate(LorebookEntryData entry, Random rng) {
  if (entry.probability >= 100) {
    return true;
  }
  if (entry.probability <= 0) {
    return false;
  }
  return rng.nextDouble() * 100 < entry.probability.toDouble();
}

/// 互斥组解析：同组按 group_weight 加权抽一；无组条目全部保留。
List<LorebookEntryData> _resolveGroups(
  List<LorebookEntryData> candidates,
  Random rng,
) {
  final groups = <String, List<LorebookEntryData>>{};
  final singles = <LorebookEntryData>[];
  for (final entry in candidates) {
    if (entry.groupName.isNotEmpty) {
      groups.putIfAbsent(entry.groupName, () => <LorebookEntryData>[]).add(entry);
    } else {
      singles.add(entry);
    }
  }

  final result = List<LorebookEntryData>.from(singles);
  for (final group in groups.values) {
    result.add(_weightedPick(group, rng));
  }
  return result;
}

/// 按 group_weight 加权抽一（权重兜底 ≥1，非空组恒可抽）。
LorebookEntryData _weightedPick(List<LorebookEntryData> group, Random rng) {
  final weights = [for (final e in group) max(e.groupWeight, 1)];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final target = rng.nextDouble() * total;
  var cumulative = 0;
  for (var i = 0; i < group.length; i++) {
    cumulative += weights[i];
    if (target < cumulative.toDouble()) {
      return group[i];
    }
  }
  return group.last;
}

/// 输出/规范化排序键：order 升序、同 order 按 id 升序（确定性锁定）。
int _compareOrderId(LorebookEntryData a, LorebookEntryData b) {
  final byOrder = a.order.compareTo(b.order);
  return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
}

/// keys 列表逐元素相等（Dart List 无内置值比较）。
bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}