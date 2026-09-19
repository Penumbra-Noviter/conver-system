/// LorebookEditorController — 世界书编辑器页的状态机（WL-04）。
///
/// 职责：角色世界书条目 CRUD（经 [LorebookRepository]）+ 列表搜索过滤 +
/// 条目开关切换 + 表单校验/归一化。纯编排：业务判定（泛词、chips、数值边界）
/// 收敛为顶层纯函数核（对齐桌面 `frontend/js/components/lorebook-editor.js`
/// `__all__`：isGenericKey / addKeyChip / removeKeyChip / validateLorebookEntry /
/// buildLorebookPayload / CONTENT_MAX_LENGTH / GENERIC_KEYS），view 只做展示
/// 编排。
///
/// 层级：ChangeNotifier 视图模型，依赖 [LorebookRepository]（数据层）+
/// [LorebookEntryDraft]（落库前形态）。不触碰具体 UI 与平台存储。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart'
    show LorebookEntriesCompanion, LorebookEntry;
import '../../data/repositories/lorebook_repository.dart'
    show LorebookEntryDraft, LorebookRepository;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 characters_controller.dart 既有惯例）。
// ignore_for_file: prefer_initializing_formals

/// 单条内容长度上限（桌面 CONTENT_MAX_LENGTH=20000 逐字；WL-04 表单拦截）。
const int contentMaxLength = 20000;

/// 高频泛词黑名单：单字符或多字符无信息量虚词/标点 → 泛词告警。
///
/// 与桌面 `lorebook-editor.js::GENERIC_KEYS` 逐字一致（含空格与空串；
/// [isGenericKey] 对 trim 后 ≤1 字符的键恒告警，空串走长度分支）。
const Set<String> genericKeys = {
  '你', '我', '他', '她', '它', '的', '了', '是', '在', '有', '这', '那',
  '。', '，', '！', '？', '、', '；', '：', ' ', '',
};

/// 数值域边界（桌面 BOUNDS 逐字；与 WL-01 表注释域一致：
/// order [0,9999] / probability [1,100] / group_weight [1,100] / depth [0,20]）。
const Map<String, ({int min, int max})> numericBounds = {
  'order': (min: 0, max: 9999),
  'probability': (min: 1, max: 100),
  'groupWeight': (min: 1, max: 100),
  'depth': (min: 0, max: 20),
};

/// 泛词判定：trim 后长度 ≤1 或在 [genericKeys] 中 → 告警。
///
/// 对齐桌面 `isGenericKey`：`trim()` 先归一化，再走长度/黑名单两路。
bool isGenericKey(String key) {
  final k = key.trim();
  return k.length <= 1 || genericKeys.contains(k);
}

/// 关键词 chips 录入：trim 后追加；空输入 / 重复键 → 返回原列表（保序）。
///
/// 对齐桌面 `addKeyChip`（去重/裁剪/空拒）。
List<String> addKeyChip(List<String> keys, String key) {
  final k = key.trim();
  if (k.isEmpty || keys.contains(k)) {
    return keys;
  }
  return [...keys, k];
}

/// 关键词 chips 删除：移除全部与 [key] 等价的键。
///
/// 对齐桌面 `removeKeyChip`（filter 语义；chips 不变量下等价于删单个）。
List<String> removeKeyChip(List<String> keys, String key) {
  return [for (final k in keys) if (k != key) k];
}

/// 关键词输入解析（移动端增强，工单「keys 逗号分隔解析」）：按逗号分隔、
/// trim、去空段、去重保序。支持一次粘贴「猫, 狗, 鸟」。
List<String> parseKeyInput(String input) {
  final seen = <String>{};
  return [
    for (final part in input.split(','))
      if (part.trim().isNotEmpty && seen.add(part.trim())) part.trim(),
  ];
}

/// 条目表单校验：返回字段 → 内联错误文案的 map；空 map = 校验通过。
///
/// 对齐桌面 `validateLorebookEntry` 三路：内容超上限（[contentMaxLength]）、
/// 关键词为空且非常驻、数值空输入 / 非 int / 越界（[numericBounds]）。
/// 空数值不得静默落 0（桌面 Falsify 修复锁）。
Map<String, String> validateLorebookEntry({
  required String content,
  required List<String> keys,
  required bool constant,
  required String order,
  required String probability,
  required String groupWeight,
  required String depth,
}) {
  final errors = <String, String>{};
  if (content.length > contentMaxLength) {
    errors['content'] = '内容过长（上限 $contentMaxLength 字符）';
  }
  if (keys.isEmpty && !constant) {
    errors['keys'] = '至少填写一个触发关键词（或勾选「常驻」）';
  }
  const labels = {
    'order': '排序',
    'probability': '命中概率',
    'groupWeight': '组内权重',
    'depth': '记忆深度',
  };
  for (final entry in numericBounds.entries) {
    final field = entry.key;
    final raw = switch (field) {
      'order' => order,
      'probability' => probability,
      'groupWeight' => groupWeight,
      _ => depth,
    }.trim();
    if (raw.isEmpty) {
      errors[field] = '请填写${labels[field]}';
      continue;
    }
    final value = int.tryParse(raw);
    if (value == null) {
      errors[field] = '${labels[field]}需为整数';
      continue;
    }
    final bounds = entry.value;
    if (value < bounds.min || value > bounds.max) {
      errors[field] =
          '${labels[field]}需在 ${bounds.min}-${bounds.max} 之间';
    }
  }
  return errors;
}

/// 表单原始值 → [LorebookEntryDraft]（字段名映射单一来源）。
///
/// 对齐桌面 `buildLorebookPayload`：与 WL-01 表字段逐字段一致；数值已由
/// [validateLorebookEntry] 保证可解析（调用方先校验后构建）。title / groupName
/// trim；source 固定 manual（手动编辑产出，记忆宫殿 auto 由服务层写）。
LorebookEntryDraft buildLorebookDraft({
  required String title,
  required List<String> keys,
  required String content,
  required bool constant,
  required String order,
  required String probability,
  required String groupName,
  required String groupWeight,
  required String matchMode,
  required String position,
  required String depth,
  required bool enabled,
}) {
  return LorebookEntryDraft(
    title: title.trim(),
    keys: keys,
    content: content,
    constant: constant,
    order: int.parse(order),
    probability: int.parse(probability),
    groupName: groupName.trim(),
    groupWeight: int.parse(groupWeight),
    matchMode: matchMode,
    position: position,
    depth: int.parse(depth),
    source: 'manual',
    enabled: enabled,
  );
}

/// 世界书编辑器控制器。
class LorebookEditorController extends ChangeNotifier {
  /// [lorebookRepository] 数据源；[characterId] 目标角色。
  LorebookEditorController({
    required LorebookRepository lorebookRepository,
    required int characterId,
  })  : _lorebookRepository = lorebookRepository,
        _characterId = characterId;

  final LorebookRepository _lorebookRepository;
  final int _characterId;

  bool _loading = false;
  List<LorebookEntry> _entries = const [];
  String _searchQuery = '';
  String? _snackMessage;
  String? _notice;

  /// 加载中（首次加载 spinner）。
  bool get loading => _loading;

  /// 世界书条目列表（(order, id) 升序，仓储契约）。
  List<LorebookEntry> get entries => _entries;

  /// 搜索过滤后的条目（标题 / 关键词子串，大小写不敏感）。
  List<LorebookEntry> get filteredEntries => _entries
      .where((e) => _matchesQuery(e, _searchQuery))
      .toList();

  /// 当前搜索关键字。
  String get searchQuery => _searchQuery;

  /// 一次性 SnackBar 消息（新增/更新/删除成功）；view 经
  /// [consumeSnackMessage] 取后消费。
  String? get snackMessage => _snackMessage;

  /// 非阻塞提示（加载失败、操作失败等）；null 无。
  String? get notice => _notice;

  /// 拉取世界书条目（首次进入 / 增删改后刷新）。
  ///
  /// 失败 → [notice] 且保留既有列表（不崩溃，验收 8）。
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _entries = await _lorebookRepository.listEntries(_characterId);
      _notice = null;
    } catch (e) {
      _notice = '加载世界书失败: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 更新搜索关键字（触发 [filteredEntries] 重算）。
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// 切换条目开关（部分更新 enabled，桌面 toggle 语义）。
  Future<void> toggleEnabled(LorebookEntry entry) async {
    try {
      await _lorebookRepository.updateEntry(
        entry.id,
        LorebookEntriesCompanion(enabled: Value(!entry.enabled)),
      );
      await load();
    } catch (e) {
      // 失败不触发 load：避免「切换失败」被 load 的「加载失败」覆盖，且
      // 未落库无需刷新。
      _notice = '切换失败: $e';
      notifyListeners();
    }
  }

  /// 新增条目（[draft] 为校验后的落库前形态）。
  Future<void> createEntry(LorebookEntryDraft draft) async {
    try {
      await _lorebookRepository.createEntry(_characterId, draft);
      _snackMessage = '已新增条目';
      await load();
    } catch (e) {
      _notice = '新增失败: $e';
      notifyListeners();
    }
  }

  /// 更新条目（全字段写回，payload 字段映射单一来源 [buildLorebookDraft]）。
  Future<void> updateEntry(int entryId, LorebookEntryDraft draft) async {
    try {
      await _lorebookRepository.updateEntry(
        entryId,
        LorebookEntriesCompanion(
          title: Value(draft.title),
          keys: Value(draft.keys),
          content: Value(draft.content),
          constant: Value(draft.constant),
          order: Value(draft.order),
          probability: Value(draft.probability),
          groupName: Value(draft.groupName),
          groupWeight: Value(draft.groupWeight),
          matchMode: Value(draft.matchMode),
          position: Value(draft.position),
          depth: Value(draft.depth),
          enabled: Value(draft.enabled),
        ),
      );
      _snackMessage = '已保存修改';
      await load();
    } catch (e) {
      _notice = '保存失败: $e';
      notifyListeners();
    }
  }

  /// 删除条目；失败 → [notice]（验收 7：仓库抛错降级不崩溃）。
  Future<void> deleteEntry(int entryId) async {
    try {
      await _lorebookRepository.deleteEntry(entryId);
      _snackMessage = '已删除条目';
      await load();
    } catch (e) {
      _notice = '删除失败: $e';
      notifyListeners();
    }
  }

  /// 关闭当前非阻塞提示。
  void dismissNotice() {
    if (_notice == null) {
      return;
    }
    _notice = null;
    notifyListeners();
  }

  /// 消费一次性 SnackBar 消息（view 弹出后调用，置 null）。
  void consumeSnackMessage() {
    if (_snackMessage == null) {
      return;
    }
    _snackMessage = null;
    notifyListeners();
  }

  /// 搜索匹配判定：query trim 后为空 → 全量；否则标题或任一关键词含子串
  /// （大小写不敏感，对齐桌面 `renderList` filter）。
  bool _matchesQuery(LorebookEntry entry, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return true;
    }
    return entry.title.toLowerCase().contains(q) ||
        entry.keys.any((k) => k.toLowerCase().contains(q));
  }
}
