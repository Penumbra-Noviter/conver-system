/// 存档契约层（对拍桌面 `desktop/frontend/js/save-manager.js`，纯 Dart 深模块）。
///
/// 职责：存档键收集 / 导出载荷 / 导入校验（整包拒绝）/ 写前快照尽力回滚 /
/// 删除 / 文件名净化 / 5MB 上限 —— 全部为同步纯函数，storage 经 [SaveStorage]
/// seam 注入（生产由读写层 F-M5-06 经 runJavaScript 实现；测试注入假件）。
/// 白名单匹配语义（精确 `==` / 正则 `^…$` 锚定）单一来源见
/// `save_key_meta.dart`，本模块不复制常量。
///
/// 排除面（spec 决策 E）：cfg 键（含 API Key）与主应用自身键由 saveKeys
/// 白名单天然排除 —— 导出导不出来、导入写不进去。
///
/// 导入文件大小守卫上限 [maxImportBytes] = 5MB；校验失败文案列出全部问题
/// 至多 10 条，超出截断计数。
///
/// 协议表面（等价桌面 `__all__`）：[SaveStorage] / [collectGameKeys] /
/// [buildExportPayload] / [validateImportPayload] / [applyImportPayload] /
/// [deleteGameKeys] / [sanitizeFilename] / [maxImportBytes]。
///
/// 纯 Dart 硬约束：零 flutter / 平台 import，仅语言内建（RegExp / Set /
/// Map / dart:convert），宿主 `flutter test` 可直接单测。
library;

import 'dart:convert';

import 'package:conver_system_mobile/services/simulator/save_key_meta.dart';

/// localStorage 兼容 seam（Storage 子集，桌面 `window.localStorage` 语义）：
/// 可枚举（length / key(i)）、读（getItem）、写（setItem）、删（removeItem）。
/// 生产实现由 F-M5-06 读写层提供（runJavaScript 双向）；测试注入假件。
abstract interface class SaveStorage {
  /// 键数量（枚举范围）。
  int get length;

  /// 第 [index] 个键名；越界返回 null。
  String? key(int index);

  /// 键 [key] 的值；不存在返回 null。
  String? getItem(String key);

  /// 写入键 [key]（同键替换）；实现可抛异常（配额等）。
  void setItem(String key, String value);

  /// 移除键 [key]（不存在为 no-op）。
  void removeItem(String key);
}

/// 导入文件大小守卫上限（字节；localStorage 同源总量约 5MB，单文件不超此限）。
const int maxImportBytes = 5 * 1024 * 1024;

// ══════════════════════════════════════════════════
// 内部工具：白名单匹配（收集/导出/校验/应用共用同一语义）
// ══════════════════════════════════════════════════

/// saveKeys 白名单是否命中给定键名（锚定完整键名匹配）。
///
/// 条目语义与 `saveKeyMatches` 契约一致（精确 `==` / 正则 `^…$` 锚定）。
/// 防御：条目非字符串 / 模式不可编译 → 前一语义层返回 false（防直接调用方
/// 传入原始数据）。任一命中即 true。
bool _whitelistHits(Object? saveKeys, String keyName) {
  if (saveKeys is! List) return false;
  for (final Object? entry in saveKeys) {
    if (saveKeyMatches(entry, keyName)) return true;
  }
  return false;
}

// ══════════════════════════════════════════════════
// 纯函数：键收集 / 导出 / 校验 / 应用 / 删除
// ══════════════════════════════════════════════════

/// 收集游戏中命中 saveKeys 白名单且当前存在的 storage 键（存档键收集）。
///
/// 枚举 storage 全部键名（[SaveStorage.length] / [SaveStorage.key] 协议），
/// 按白名单匹配语义（精确 `==` / 正则 `^…$` 锚定）筛选；cfg 键（含 API Key）
/// 与主应用自身键不在白名单内 → 天然排除。saveKeys 缺失 / 空数组 → 空收集
/// （即「无存档管理」降级信号）。返回排序去重后的键名数组（不依赖枚举顺序）。
///
/// 防御：game 非 Map / storage 缺失 → 空数组（桌面 `collectGameKeys` 逐字）。
List<String> collectGameKeys(Object? game, SaveStorage? storage) {
  if (game is! Map || storage == null) return [];
  final saveKeys = game['saveKeys'];
  if (saveKeys is! List) return [];
  final Set<String> hit = {};
  for (var i = 0; i < storage.length; i++) {
    final String? name = storage.key(i);
    if (name == null) continue;
    if (_whitelistHits(saveKeys, name)) hit.add(name);
  }
  return hit.toList()..sort();
}

/// 构建单游戏导出 JSON 载荷（导出文件内容契约）。
///
/// 形状：`{game_id, game_name, saved_at, keys:{键:值}}`。收录规则：
/// - 仅收录 keyNames 中命中 saveKeys 白名单（防御：直接传入的 cfg 键名
///   不收录 — 「导出导不出来」）且当前存在于 storage 的键；
/// - 值取 storage 原文（Storage 值恒为字符串）。
/// [now] 可注入（纯函数确定性；生产不传，默认当前 ISO8601 UTC 时间）。
///
/// 防御（桌面 `buildExportPayload` 逐字）：game 非 Map → game_id/game_name
/// 空串；keyNames 非 List / storage 缺失 → keys 为空对象。
Map<String, Object?> buildExportPayload(
  Object? game,
  Object? keyNames,
  SaveStorage? storage, {
  String? now,
}) {
  final Map<Object?, Object?> g = game is Map ? game : const {};
  final Map<String, String> keys = {};
  final Object? saveKeys = g['saveKeys'];
  if (keyNames is List && storage != null && saveKeys is List) {
    for (final Object? name in keyNames) {
      if (name is! String) continue;
      if (!_whitelistHits(saveKeys, name)) continue; // 白名单防御：cfg 键不导出
      final String? value = storage.getItem(name);
      if (value == null) continue; // 只导出存在的键
      keys[name] = value;
    }
  }
  return {
    'game_id': g['id'] is String ? g['id'] : '',
    'game_name': g['name'] is String ? g['name'] : '',
    'saved_at': now ?? DateTime.now().toUtc().toIso8601String(),
    'keys': keys,
  };
}

/// 导入载荷校验结果（不可变值对象；等价桌面 `{ok:true, keys}` /
/// `{ok:false, error}` 判别联合）。
class ValidateResult {
  const ValidateResult.ok(this.keys) : ok = true, error = null;

  const ValidateResult.reject(this.error) : ok = false, keys = const {};

  /// 是否全部合法。
  final bool ok;

  /// 合法键（白名单命中且值为可解析 JSON 字符串）；仅 [ok] 时有意义。
  final Map<String, String> keys;

  /// 拒绝原因文案（列出全部问题，至多 10 条 + 超出截断计数）；仅非 [ok] 时有意义。
  final String? error;
}

/// 导入校验失败文案列出问题条数上限（超出截断并计数；桌面
/// MAX_REPORTED_ISSUES 逐字）。
const int _maxReportedIssues = 10;

/// 值是否 string 且 JSON 可解析（`''` / 非 JSON 文本 → false）。
bool _isJsonString(Object? value) {
  if (value is! String) return false;
  try {
    jsonDecode(value);
    return true;
  } on FormatException {
    return false;
  }
}

/// 校验导入载荷（键名白名单 + 值类型，任一问题整包拒绝）。
///
/// 契约（spec 决策 H）：键名须命中该游戏 saveKeys 白名单（匹配语义与
/// 收集一致 — 正则模式条目按锚定正则判定，键名本身含正则元字符不按字面
/// 放行）；值仅校验 string + JSON 可解析（`jsonDecode` 不抛错，含 `''`
/// 拒绝）。任一问题 → [ValidateResult.reject]（列出全部问题，至多 10 条，
/// 超出截断计数），调用方不得写入任何键；全部合法 →
/// [ValidateResult.ok]。game_id / game_name / saved_at 为元数据不校验
/// （白名单是安全边界）。keys 缺失 / 非对象 → 拒绝；keys 为空对象 →
/// 合法空包（应用 no-op）。game 无 saveKeys → 整体拒绝（「无存档管理」
/// 游戏不可导入）。`__proto__` 键：Dart Map 天然为普通自有键（等价桌面
/// TD-70 无原型累积器）—— 白名单命中即可完整写出。
ValidateResult validateImportPayload(Object? payload, Object? game) {
  if (payload is! Map) {
    return const ValidateResult.reject('存档文件格式无效：顶层必须是对象');
  }
  if (!payload.containsKey('keys')) {
    return const ValidateResult.reject('存档文件缺少 keys 字段');
  }
  final Object? payloadKeys = payload['keys'];
  if (payloadKeys is! Map) {
    return const ValidateResult.reject('存档文件 keys 字段必须是对象');
  }
  final Object? saveKeys = game is Map ? game['saveKeys'] : null;
  if (saveKeys is! List) {
    return const ValidateResult.reject(
        '该游戏无存档管理（saveKeys 未声明），无法导入');
  }

  final List<String> problems = [];
  final Map<String, String> valid = {};
  payloadKeys.forEach((Object? key, Object? value) {
    if (key is! String) return;
    if (!_whitelistHits(saveKeys, key)) {
      problems.add('键「$key」不在该游戏存档键白名单内');
      return;
    }
    if (!_isJsonString(value)) {
      problems.add('键「$key」的值不是合法 JSON 字符串');
      return;
    }
    valid[key] = value as String;
  });
  if (problems.isNotEmpty) {
    final shown = problems.take(_maxReportedIssues).join('；');
    final suffix = problems.length > _maxReportedIssues
        ? '；…等共 ${problems.length} 个问题（仅列出前 $_maxReportedIssues 个）'
        : '';
    return ValidateResult.reject('存档文件校验失败：$shown$suffix');
  }
  return ValidateResult.ok(valid);
}

/// 应用导入载荷：白名单键同名替换写回 storage（spec 决策 H）。
///
/// 防御（导出/导入排除面收口）：仅写入命中 saveKeys 白名单的键 — 直接
/// 调用本函数传入非白名单键也不写入（「导入写不进去」）；值非字符串
/// 跳过。validateImportPayload 是 UI 边界的整包拒绝闸门，本函数为应用层
/// 防御。空对象 / 无 saveKeys / storage 缺失 → no-op 返回 0。
///
/// 失败回滚（TD-63 裁定修法 = 写前快照，非容量预检 — localStorage 无剩余
/// 容量 API）：每个待写键先记录快照 `{key, prev}` 再 setItem；任一键写入
/// 抛异常 → 已写键逆序尽力回滚（prev 为 null → removeItem，否则 setItem
/// 还原原值）→ 异常上抛（复用 `rethrow` 保留原始异常同一性，调用方可
/// 安全提示用户）。回滚为尽力而为（TD-73）：单个键还原失败（如存储仍
/// 不可写）不中断循环 — 继续尝试还原其余键，失败键残留新值；循环结束
/// 统一抛原始 err（回滚异常不遮蔽写入异常）。抛错键本身未写入（setItem
/// 原子性），无需回滚该键。快照仅覆盖实际写入路径（白名单命中且值为
/// 字符串的键），守卫先行、被跳过键不触碰 storage。
///
/// 返回实际写入的键数；写入失败时尽力回滚并抛原始异常（不返回）。
int applyImportPayload(Object? game, Object? keys, SaveStorage? storage) {
  if (game is! Map) return 0;
  final Object? saveKeys = game['saveKeys'];
  if (saveKeys is! List) return 0;
  if (keys is! Map) return 0;
  if (storage == null) return 0;

  /// 已成功写入键的快照（`{key, prev}` — 回滚依据；prev null = 写前不存在）。
  final List<({String key, String? prev})> written = [];
  try {
    keys.forEach((Object? key, Object? value) {
      if (key is! String) return;
      if (!_whitelistHits(saveKeys, key)) return; // 防御：非白名单不写入
      if (value is! String) return;
      final String? prev = storage.getItem(key); // 写前快照（TD-63）
      storage.setItem(key, value);
      written.add((key: key, prev: prev));
    });
  } catch (err) {
    // 尽力而为回滚（TD-73）：已写键逆序逐个还原（新增键移除 / 旧值还原）。
    // 单个键还原失败（如存储仍不可写）不中断循环、不遮蔽原始 err — 其余
    // 键继续尝试还原；循环结束统一抛原始异常（同一性保留）。
    for (var i = written.length - 1; i >= 0; i--) {
      final entry = written[i];
      try {
        final String? prev = entry.prev;
        if (prev == null) {
          storage.removeItem(entry.key);
        } else {
          storage.setItem(entry.key, prev);
        }
      } catch (_) {
        // 单个键还原失败 → 继续尝试其余键（尽力而为，失败键残留新值）
      }
    }
    rethrow;
  }
  return written.length;
}

/// 删除游戏全部命中 saveKeys 白名单且存在的键（确认由 UI 层负责）。
///
/// 与 [collectGameKeys] 同语义；主应用自身键与 cfg 键不在白名单内 →
/// 不误伤。game / storage 缺失 → 空结果 no-op。返回实际被删除的键名列表
/// （供提示「已删除 N 个存档键」）。
List<String> deleteGameKeys(Object? game, SaveStorage? storage) {
  final List<String> keyNames = collectGameKeys(game, storage);
  if (keyNames.isEmpty || storage == null) return const [];
  for (final name in keyNames) {
    storage.removeItem(name);
  }
  return keyNames;
}

/// 导出文件名净化（TD-65）：控制字符（`\x00-\x1f\x7f`）/ 引号 / 反斜杠 /
/// 正斜杠 / 冒号 / 星号 / 问号 / 尖括号 / 竖线 / 百分号 → `_`；修剪尾部点
/// 与空格；空结果兜底 `game`。正常 id 经净化后不变（既有契约
/// `<gameId>-saves.json` 保持）。桌面 `sanitizeFilename` 逐字。
String sanitizeFilename(Object? name) {
  if (name is! String) return 'game';
  final cleaned = name
      .replaceAll(RegExp(r'[\x00-\x1f\x7f"\\/:*?<>|%]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  return cleaned.isEmpty ? 'game' : cleaned;
}
