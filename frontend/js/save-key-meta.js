/**
 * Conver System — 存档键契约常量单一来源（TD-67/68 深模块，纯常量零副作用）
 *
 * 职责：存档键契约的「契约之家」—— 正则元字符集（saveKeys 精确键 / 正则
 *   模式判定）、等价转义函数（吸收测试文件内联转义变体）、wg_ 族游戏 id
 *   集合（合并存档面板 / 运行视图双处硬编码语义）三件套的单一来源。
 *   五处消费点全部 import 本模块，不再各自持有字面量副本：
 *     - frontend/js/simulators.js      （列表解析归一化：正则元字符判定）
 *     - frontend/js/save-manager.js    （存档面板：白名单匹配 + wg_ 注记集合）
 *     - frontend/js/simulator-view.js  （运行视图：wg_ 会话注记集合）
 *     - scripts/smoke-simulators.mjs   （冒烟脚本：存档面板种子键精确键判定）
 *     - frontend/tests/simulator-manifest.test.js（数据完整性：判定 + 溯源探针 +
 *       内联转义变体）
 *   维护约定：新增 / 修改存档键契约常量只改本模块；各消费文件 docstring 的
 *   共享契约段指向本模块（不复制常量定义）。
 *
 * 硬约束（Node ESM 真实消费者兼容 — 冒烟脚本直接 import）：模块顶层零 DOM /
 *   零浏览器 API / 零副作用，仅语言内建（RegExp / Set / String.prototype）。
 *
 * saveKeys 契约（U9-T1）：v2 条目声明存档键白名单，数组元素为字符串 ——
 *   不含正则元字符的字符串 = 精确键名（=== 匹配）；含正则元字符的字符串 =
 *   正则模式（锚定完整键名 ^…$ 匹配）。正则元字符集定义见 SAVE_KEY_META_RE。
 *
 * 协议表面（__all__）：SAVE_KEY_META_RE / escapeRegExp / WG_SESSION_ONLY_IDS。
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
// 协议表面收口（深模块：外部只通过这些符号与 save-key-meta.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'SAVE_KEY_META_RE',
    'escapeRegExp',
    'WG_SESSION_ONLY_IDS',
];
