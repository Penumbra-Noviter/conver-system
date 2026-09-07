/// 存档键契约常量单一来源（对拍桌面 `desktop/frontend/js/save-key-meta.js`，
/// TD-67/68 契约之家，纯常量零副作用）。
///
/// 职责：存档键契约的「契约之家」—— 正则元字符集（saveKeys 精确键 /
/// 正则模式判定）、等价转义函数、wg_ 族游戏 id 集合三件套的单一来源。
///
/// saveKeys 契约（U9-T1）：v2 条目声明存档键白名单，数组元素为字符串 ——
/// 不含正则元字符的字符串 = 精确键名（`==` 匹配）；含正则元字符的字符串 =
/// 正则模式（锚定完整键名 `^…$` 匹配）。正则元字符集定义见
/// [saveKeyMetaRe]。
///
/// 协议表面（等价桌面 `__all__`）：[saveKeyMetaRe] / [escapeRegExp] /
/// [wgSessionOnlyIds] / [saveKeyIsPattern] / [saveKeyIsValidPattern] /
/// [saveKeyMatches]。
///
/// 纯 Dart 硬约束：零 flutter / 平台 import，仅语言内建（RegExp / Set /
/// String），宿主 `flutter test` 可直接单测。
library;

/// 正则元字符集：saveKeys 元素含任一字符即按正则模式处理（精确键名不得含
/// 这些字符）。源串与桌面 `/[.*+?^${}()|[\]\\]/` 逐字等价（无 flag；
/// Dart RegExp 无 lastIndex 状态，hasMatch 判定无副作用）。消费方不得
/// 改写本常量。
final RegExp saveKeyMetaRe = RegExp(r'[.*+?^${}()|[\]\\]');

/// 转义字符串中的正则元字符（与 [saveKeyMetaRe] 同源，逐字节等价于桌面
/// `str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')` —— 基于单一来源的
/// `new RegExp(SAVE_KEY_META_RE.source, 'g')` 形态）。
///
/// 非字符串输入按 `String()` 归一化（null → `'null'`）。返回字符串可安全
/// 用于 `RegExp` 拼接上下文，语义为字面量匹配。
String escapeRegExp(Object? str) {
  return str
      .toString()
      .replaceAllMapped(saveKeyMetaRe, (m) => '\\${m[0]}');
}

/// wg_ 族游戏 id 集（键形 `'wg_' + CFG.id + '_save'` 的小马宝莉 / 高中生
/// 模拟器 —— 注入仅会话内生效，存档面板与运行视图注记同源；新增该族游戏
/// 只改此处）。与桌面 `WG_SESSION_ONLY_IDS` 集合语义逐字一致。
const Set<String> wgSessionOnlyIds = {'my-little-pony', 'high-school-sim'};

// ══════════════════════════════════════════════════
// 匹配语义函数（U9-T1 saveKeys 白名单匹配 — 消费方联合收口）
// ══════════════════════════════════════════════════

/// 判定 saveKeys 条目是否为正则模式（含正则元字符）。
///
/// 不含正则元字符的字符串 = 精确键名（`==` 匹配）；含正则元字符的字符串 =
/// 正则模式（锚定完整键名 `^…$` 匹配）。桌面 `saveKeyIsPattern` 逐字。
bool saveKeyIsPattern(Object? entry) {
  if (entry is! String || entry.isEmpty) return false;
  return saveKeyMetaRe.hasMatch(entry);
}

/// 验证 saveKeys 条目是否为合法的可编译模式。
///
/// 精确键名（不含正则元字符）→ true（无需编译）；含正则元字符 + 可编译 →
/// true；不可编译 → false。桌面 `saveKeyIsValidPattern` 逐字。
bool saveKeyIsValidPattern(Object? entry) {
  if (entry is! String || entry.isEmpty) return false;
  if (!saveKeyMetaRe.hasMatch(entry)) return true; // 精确键名，无需编译
  try {
    RegExp('^$entry\$');
    return true;
  } on FormatException {
    return false;
  }
}

/// saveKeys 白名单条目是否匹配给定键名（锚定完整键名匹配）。
///
/// 精确键名 → `==` 匹配；正则模式 → `^…$` 锚定 `RegExp` 匹配。防御：
/// 非字符串 entry / 空串 / 不可编译模式 / 非字符串 keyName → false。
/// 桌面 `saveKeyMatches` 逐字。
bool saveKeyMatches(Object? entry, Object? keyName) {
  if (entry is! String || entry.isEmpty) return false;
  if (keyName is! String) return false;
  if (!saveKeyMetaRe.hasMatch(entry)) return entry == keyName;
  try {
    return RegExp('^$entry\$').hasMatch(keyName);
  } on FormatException {
    return false;
  }
}
