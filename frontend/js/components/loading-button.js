/**
 * Conver System — 按钮 loading 状态工具
 *
 * 职责：为异步操作按钮提供统一的「执行中」视觉反馈（禁用 + 内联 spinner +
 * 文字切换），恢复时按原 HTML 快照还原（含 SVG icon）。避免各调用方重复实现
 * 禁用/恢复/防双击。
 *
 * 用法（异步操作包一层 try/finally）：
 *   const restore = beginButtonLoading(btn, '保存中…');
 *   try {
 *       await doAsyncWork();
 *   } finally {
 *       restore();
 *   }
 *
 * 说明：
 *   - 快照为 `btn.innerHTML` 全文（按钮含 SVG icon 时也能完整还原，不丢图标）；
 *   - loading 态标记 `.is-loading` + `disabled`，样式见 style.css `.btn-spinner`；
 *   - 按钮已在 loading 态时重复调用 no-op（防 A/B 两个异步流互相覆盖）；
 *   - restore 幂等（重复调用无副作用）；按钮被重渲染（列表刷新换新节点）后
 *     调 restore 只作用于旧节点，无副作用。
 *
 * 协议表面（__all__）：beginButtonLoading / clearButtonLoading。
 */

import { escapeHtml } from '../utils.js';

/** 保存每个按钮的 restore 函数（不把闭包挂到 DOM 属性上） */
const restoreMap = new WeakMap();

/**
 * 将按钮置为 loading 态：禁用 + 内联 spinner + 文字切换（可选）。
 * @param {HTMLButtonElement} btn - 目标按钮
 * @param {string} [loadingText=''] - 加载中文字（spinner 后）；icon 按钮可传 '' 仅 spinner
 * @returns {function(): void} restore — 恢复按钮到调用前状态（幂等）
 */
export function beginButtonLoading(btn, loadingText = '') {
    if (btn.classList.contains('is-loading')) return () => {};

    const originalHtml = btn.innerHTML;
    const originalDisabled = btn.disabled;
    btn.classList.add('is-loading');
    btn.disabled = true;
    btn.innerHTML =
        `<span class="btn-spinner" aria-hidden="true"></span>${escapeHtml(loadingText)}`;

    const restore = () => {
        btn.classList.remove('is-loading');
        btn.disabled = originalDisabled;
        btn.innerHTML = originalHtml;
        restoreMap.delete(btn);
    };
    restoreMap.set(btn, restore);
    return restore;
}

/**
 * 将按钮从 loading 态恢复（若当前在 loading 态）。
 * 等价于 beginButtonLoading 返回的 restore，供「未持有 restore 引用」的场景使用。
 * @param {HTMLButtonElement} btn - 目标按钮
 */
export function clearButtonLoading(btn) {
    restoreMap.get(btn)?.();
}

export const __all__ = ['beginButtonLoading', 'clearButtonLoading'];