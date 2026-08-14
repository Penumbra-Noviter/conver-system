/**
 * Conver System — fetch seam 单一来源（深模块，TD-51 / TD-55 / TD-60）
 *
 * 职责：全前端唯一的 fetch 注入点。api.js（统一 API 调用层）与 simulators.js
 *   （模拟器列表模块）各自删除本地 fetchImpl/setFetch/doFetch 副本，统一改为
 *   `export { setFetch } from './fetch-seam.js'` 并内部走本模块 doFetch ——
 *   测试里 setFetch(mock) 一次注入对两模块同时生效，两模块的 fetch 行为
 *   结构上不可能漂移（单源）。
 *
 * 语义契约（既有断言零漂移）：
 *   - setFetch(fn)：注入 fetch 兼容函数 (url, options) => Promise<Response>；
 *   - setFetch(null / 非函数)：恢复回落全局 fetch（globalThis.fetch）；
 *   - doFetch(...args)：优先注入实现，回落全局 fetch，参数原样透传
 *     （url + 可选 init 对象，如 { method, headers, body, signal }）。
 *
 * 协议表面（__all__）：fetchImpl / setFetch / doFetch。
 */

/** 测试注入的 fetch 实现（null → 回落全局 fetch；只经 setFetch 变更，导入方只读） */
export let fetchImpl = null;

/**
 * 注入自定义 fetch 实现（测试用，避免真实网络）。传 null/非函数恢复默认全局 fetch。
 * @param {Function|null} fn - fetch 兼容函数 (url, options) => Promise<Response>
 */
export function setFetch(fn) {
    fetchImpl = typeof fn === 'function' ? fn : null;
}

/**
 * 统一 fetch 执行入口：优先注入实现（fetchImpl），未注入回落全局 fetch。
 * 参数原样透传（url + 可选 init 对象）——调用方无需感知注入与否。
 * @param {...unknown} args - fetch 参数（url + 可选 init 对象）
 * @returns {Promise<Response>} fetch 返回的 Promise
 */
export function doFetch(...args) {
    return (fetchImpl ?? globalThis.fetch)(...args);
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些标识与 fetch-seam.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'fetchImpl',
    'setFetch',
    'doFetch',
];
