/**
 * Conver System — 存档键契约常量单一来源（TD-67/68 深模块，纯常量零副作用）
 *
 * 职责：存档键契约的「契约之家」—— 正则元字符集（saveKeys 精确键 / 正则
 *   模式判定）、等价转义函数（吸收测试文件内联转义变体）、wg_ 族游戏 id
 *   集合（合并存档面板 / 运行视图双处硬编码语义）三件套的单一来源。
 *   五处消费点全部 import 本模块，不再各自持有字面量副本：
 *     - frontend/js/simulators.js      （列表解析归一化：正则元字符判定）
 *     - frontend/js/save-manager.js    （存档面板：白名单匹配 + wg_ 注记集合）
 *     - scripts/smoke-simulators.mjs   （冒烟脚本：存档面板种子键精确键判定）
 *     - frontend/tests/simulator-manifest.test.js（数据完整性：判定 + 溯源探针 +
 *       内联转义变体）
 *     - frontend/tests/save-key-meta.test.js（契约锁：常量断言 + 匹配语义函数矩阵）
 *   维护约定：新增 / 修改存档键契约常量只改本模块；各消费文件 docstring 的
 *   共享契约段指向本模块（不复制常量定义）。
 *
 * 硬约束（Node ESM 真实消费者兼容 — 冒烟脚本直接 import）：模块顶层零 DOM /
 *   零浏览器 API / 零副作用，仅语言内建（RegExp / Set / String.prototype）。
 *
 * 已知同字符类异语义例外（不并入本模块，防误迁移）：markdown.js 的
 *   escapeRegExp（TD-46 占位符还原域，其单一来源是 ECMAScript 语言定义）与
 *   第三方游戏资产 frontend/simulators/仿微.html 内联脚本（vendored，Out of
 *   Scope）——两处与存档键契约判定互不传导，改 SAVE_KEY_META_RE 不得联动。
 *
 * saveKeys 契约（U9-T1）：v2 条目声明存档键白名单，数组元素为字符串 ——
 *   不含正则元字符的字符串 = 精确键名（=== 匹配）；含正则元字符的字符串 =
 *   正则模式（锚定完整键名 ^…$ 匹配）。正则元字符集定义见 SAVE_KEY_META_RE。
 *
 * 协议表面（__all__）：SAVE_KEY_META_RE / escapeRegExp / WG_SESSION_ONLY_IDS /
 *   saveKeyIsPattern / saveKeyIsValidPattern / saveKeyMatches。
 */

// ══════════════════════════════════════════════════
// 常量（存档键契约 — 单一来源）
// ══════════════════════════════════════════════════

/** 正则元字符集：saveKeys 元素含任一字符即按正则模式处理（精确键名不得含这些字符）。
 *  无 flag（test() 判定无 lastIndex 状态）；消费点不得改写本常量。 */
export const SAVE_KEY_META_RE = /[.*+?^${}()|[\]\\]/;

/**
 * 转义字符串中的正则元字符（与 SAVE_KEY_META_RE 同源，逐字节等价于
 *   `str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')` —— 基于单一来源的
 *   `new RegExp(SAVE_KEY_META_RE.source, 'g')` 形态）。
 *
 * @param {string} str - 待转义字符串（非字符串输入按 String() 归一化）
 * @returns {string} 正则元字符全部加反斜杠转义后的字符串（可安全用于
 *   new RegExp / String.match 等正则上下文，语义为字面量匹配）
 */
export function escapeRegExp(str) {
    return String(str).replace(new RegExp(SAVE_KEY_META_RE.source, 'g'), '\\$&');
}

/** wg_ 族游戏 id 集（键形 'wg_' + CFG.id + '_save' 的小马宝莉 / 高中生模拟器
 *  —— 注入仅会话内生效，存档面板与运行视图注记同源；新增该族游戏只改此处） */
export const WG_SESSION_ONLY_IDS = new Set(['my-little-pony', 'high-school-sim']);

// ══════════════════════════════════════════════════
// 匹配语义函数（U9-T1 saveKeys 白名单匹配 — 三处消费方联合收口）
// ══════════════════════════════════════════════════

/**
 * 判定 saveKeys 条目是否为正则模式（含正则元字符）。
 *
 * 不含正则元字符的字符串 = 精确键名（=== 匹配）；含正则元字符的字符串 =
 * 正则模式（锚定完整键名 ^…$ 匹配）。
 *
 * @param {unknown} entry - saveKeys 白名单条目
 * @returns {boolean} 非字符串/空串 → false；含正则元字符 → true；否则 false
 */
export function saveKeyIsPattern(entry) {
    if (typeof entry !== 'string' || entry === '') return false;
    return SAVE_KEY_META_RE.test(entry);
}

/**
 * 验证 saveKeys 条目是否为合法的可编译模式。
 *
 * 精确键名（不含正则元字符）→ true（无需编译）；含正则元字符 + 可编译 →
 * true；不可编译 → false。
 *
 * @param {unknown} entry - saveKeys 白名单条目
 * @returns {boolean} 非字符串/空串 → false；精确键名 → true；可编译模式 → true；
 *   不可编译模式 → false
 */
export function saveKeyIsValidPattern(entry) {
    if (typeof entry !== 'string' || entry === '') return false;
    if (!SAVE_KEY_META_RE.test(entry)) return true; // 精确键名，无需编译
    try {
        new RegExp(`^${entry}$`);
        return true;
    } catch {
        return false;
    }
}

/**
 * saveKeys 白名单条目是否匹配给定键名（锚定完整键名匹配）。
 *
 * 精确键名 → === 匹配；正则模式 → ^…$ 锚定 RegExp 匹配。防御：非字符串
 * entry / 空串 / 不可编译模式 / 非字符串 keyName → false。
 *
 * @param {unknown} entry - saveKeys 白名单条目（精确键名或正则模式字符串）
 * @param {unknown} keyName - 待匹配的键名
 * @returns {boolean} 命中 → true；不命中 / 非法输入 → false
 */
export function saveKeyMatches(entry, keyName) {
    if (typeof entry !== 'string' || entry === '') return false;
    if (typeof keyName !== 'string') return false;
    if (!SAVE_KEY_META_RE.test(entry)) return entry === keyName;
    try {
        return new RegExp(`^${entry}$`).test(keyName);
    } catch {
        return false;
    }
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些符号与 save-key-meta.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'SAVE_KEY_META_RE',
    'escapeRegExp',
    'WG_SESSION_ONLY_IDS',
    'saveKeyIsPattern',
    'saveKeyIsValidPattern',
    'saveKeyMatches',
];
