/// 模拟器 manifest 解析器（F-M5-01 数据底座）——parseManifest 宽容降级纯 Dart 移植。
///
/// 桌面权威源（只读，语义逐字锚点）：
/// `desktop/frontend/js/simulators.js`（parseManifest / normalizeSaveKeys）及其
/// 依赖 `desktop/frontend/js/save-key-meta.js`（SAVE_KEY_META_RE /
/// saveKeyIsValidPattern，TD-67/68 契约之家）。
///
/// 解析校验策略（spec Implementation Decisions 逐字锚桌面）：
/// - 结构性错误（畸形 JSON / 顶层非对象 / version ∉ {1,2} / simulators 缺失
///   或非数组 / 条目非对象 / id 缺失或重复 / file 缺失 / type 非法）→ 整体
///   失败（[ManifestParseResult.ok] = false，携带面向用户错误文案）；
/// - 条目级字段缺失（name / description / saveKeyPrefix / config / saveKeys /
///   endpointMode）→ 宽容降级：name/description 归一化为空串，其余非法类型
///   剔除或归一化，不整体失败；
/// - v1 数据兼容：条目无 saveKeys → 归一化条目无 saveKeys 属性（「无存档
///   管理」降级信号）；saveKeyPrefix 仅 v1 数据携带并透传，已退役不参与存档
///   语义；type 对 v1/v2 一律必填（桌面逐字，v1 不豁免）。
///
/// saveKeys 契约（U9-T1）：v2 条目声明存档键白名单，数组元素为字符串——不含
/// 正则元字符 = 精确键名；含正则元字符 = 锚定完整键名的正则模式。归一化分级：
/// - 结构非法（非数组 / 元素非字符串 / 模式自含 ^ $ 锚点）→ 条目级降级
///   （该游戏无 saveKeys 属性 = 「无存档管理」信号）；
/// - 模式无法编译 / 空串元素 → 元素级剔除（该项不进入白名单）；
/// - 清洗后为空数组时保留空数组（结构性合法，非降级信号）。
///
/// 协议表面（深模块：外部只通过这些符号与 manifest_parser 交互）：
/// `ManifestParseResult` / `parseManifest`。saveKeys 模式判定所需的
/// `saveKeyMetaRe` 单一来源为 `save_key_meta.dart`（契约之家）——F-26 收口：
/// 本模块不再持同名顶层常量，消除「multiple libraries define saveKeyMetaRe」
/// 的潜在 ambiguous import 编译面（本票 injection 系模块同时消费两模块）。
library;

import 'dart:convert';

import 'save_key_meta.dart' show saveKeyMetaRe;

/// manifest 解析结果：成功携带归一化游戏条目数组，失败携带面向用户的错误文案。
///
/// 语义对齐桌面 simulators.js `{ ok: true, games }` / `{ ok: false, error }`：
/// [ok] 成功恒 true；[games] 成功时非空（可为空数组），失败时为 null；
/// [error] 失败时非空，成功时为 null。
class ManifestParseResult {
  /// 解析成功（[games] 可为空数组——空列表是合法空态，非失败）。
  const ManifestParseResult.success(this.games) : error = null;

  /// 解析失败（结构性错误，[error] 为面向用户的原因文案）。
  const ManifestParseResult.failure(this.error) : games = null;

  /// 归一化游戏条目数组（成功时非空；失败时为 null）。
  final List<Map<String, dynamic>>? games;

  /// 失败原因文案（失败时非空；成功时为 null）。
  final String? error;

  /// 是否解析成功。
  bool get ok => error == null;
}

/// 解析并校验 manifest 原始 JSON 文本，归一化为游戏条目数组。
///
/// 结构性错误 → [ManifestParseResult.failure]（列表进错误态）；条目级缺陷 →
/// 宽容降级不整体失败。归一化语义见模块头 docstring。入参类型由 Dart 强类型
/// 保证恒为字符串（桌面「非字符串输入」检查在类型系统层面吸收）。
ManifestParseResult parseManifest(String rawJson) {
  final Object? data;
  try {
    data = json.decode(rawJson);
  } on FormatException {
    return const ManifestParseResult.failure('manifest 不是合法 JSON');
  }

  if (data is! Map<String, dynamic>) {
    return const ManifestParseResult.failure('manifest 顶层必须是对象');
  }
  final version = data['version'];
  if (version != 1 && version != 2) {
    return const ManifestParseResult.failure('manifest 版本不兼容');
  }
  final simulators = data['simulators'];
  if (simulators is! List<Object?>) {
    return const ManifestParseResult.failure('manifest 缺少 simulators 列表');
  }

  final seen = <String>{};
  final games = <Map<String, dynamic>>[];
  for (final entry in simulators) {
    if (entry is! Map<String, dynamic>) {
      return const ManifestParseResult.failure('manifest 条目必须是对象');
    }
    final id = entry['id'];
    if (id is! String || id.isEmpty || seen.contains(id)) {
      return const ManifestParseResult.failure('manifest 存在缺失或重复的 id');
    }
    final file = entry['file'];
    if (file is! String || file.isEmpty) {
      return const ManifestParseResult.failure('manifest 条目缺少 file 字段');
    }
    final type = entry['type'];
    if (type != 'ai' && type != 'local') {
      return const ManifestParseResult.failure('manifest 条目 type 非法');
    }
    seen.add(id);

    // 条目级宽容降级：name/description 缺失 → 空串（不渲染）；
    // saveKeyPrefix/config 非合法类型 → 剔除；source 白名单仅 imported /
    // generated 透传（T-02 决策 10，内置条目无此字段 → 无 badge）；
    // endpointMode 非 base/full → 剔除（注入时按不转换处理）。
    final game = <String, dynamic>{
      'id': id,
      'file': file,
      'name': entry['name'] is String ? entry['name'] as String : '',
      'type': type,
      'description': entry['description'] is String ? entry['description'] as String : '',
    };
    final source = entry['source'];
    if (source == 'imported' || source == 'generated') {
      game['source'] = source;
    }
    final saveKeyPrefix = entry['saveKeyPrefix'];
    if (saveKeyPrefix is String) {
      game['saveKeyPrefix'] = saveKeyPrefix;
    }
    final config = entry['config'];
    if (config is Map<String, dynamic>) {
      game['config'] = config;
    }
    final endpointMode = entry['endpointMode'];
    if (endpointMode == 'base' || endpointMode == 'full') {
      game['endpointMode'] = endpointMode;
    }
    final saveKeys = _normalizeSaveKeys(entry['saveKeys']);
    if (saveKeys != null) {
      game['saveKeys'] = saveKeys;
    }
    games.add(game);
  }

  return ManifestParseResult.success(games);
}

/// 归一化 saveKeys（U9-T1 v2 契约）——输出清洗后的字符串数组。
///
/// 降级分级见模块头 docstring：结构非法返回 null（条目级降级）；模式无法
/// 编译 / 空串元素 → 元素级剔除；清洗后空数组保留（结构性合法）。
List<String>? _normalizeSaveKeys(Object? value) {
  if (value is! List<Object?>) {
    return null;
  }
  final keys = <String>[];
  for (final item in value) {
    if (item is! String) {
      return null; // 元素类型非法 → 条目级降级
    }
    if (item.contains('^') || item.contains(r'$')) {
      return null; // 模式自锚定 → 条目级降级（锚定由匹配方统一加）
    }
    if (item.isEmpty) {
      continue; // 空串 → 元素级剔除
    }
    if (!_saveKeyIsValidPattern(item)) {
      continue; // 不可编译 → 元素级剔除
    }
    keys.add(item);
  }
  return keys;
}

/// saveKeys 条目是否为合法的可编译模式（桌面 saveKeyIsValidPattern 逐字）。
///
/// 精确键名（不含正则元字符）→ true（无需编译）；含正则元字符且 `^…$`
/// 锚定后可编译 → true；不可编译 → false。Dart RegExp 与 ECMAScript 同源，
/// 编译失败以 [FormatException] 形态对应桌面 SyntaxError。
bool _saveKeyIsValidPattern(String entry) {
  if (entry.isEmpty) {
    return false;
  }
  if (!saveKeyMetaRe.hasMatch(entry)) {
    return true; // 精确键名，无需编译
  }
  try {
    RegExp(r'^' + entry + r'$');
    return true;
  } on FormatException {
    return false;
  }
}
