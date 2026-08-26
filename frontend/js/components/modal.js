/**
 * Conver System — 通用模态框工厂
 *
 * 收敛三类弹窗（确认 / 模型选择 / 导出）共有的骨架与通用行为：
 * 遮罩挂载、标题转义、body/actions 注入，以及通用关闭路径
 * （关闭按钮 / 点击遮罩 / Escape）与结果回传。
 * 调用方通过 body/actions 提供自定义 HTML，在 onOpen 中绑定专属事件。
 */

import { escapeHtml } from '../utils.js';
import { iconHtml } from '../icons.js';

/**
 * 焦点陷阱可聚焦元素选择器（T4 — Tab 循环不跳出框）。
 * 覆盖 button/input/select/textarea/a[href]/显式 tabindex；disabled 在收集后
 * 过滤（css 无法表达 :not([disabled]) 组合与 hidden 判断，统一在收集时过滤）。
 */
export const FOCUSABLE_SELECTOR = 'button, input, select, textarea, a[href], [tabindex]:not([tabindex="-1"])';

/**
 * 收集模态框内可聚焦元素（过滤 disabled / hidden / aria-hidden — jsdom 友好，
 * 不依赖 offsetParent/getClientRects 布局度量）。
 * @param {HTMLElement} overlay - 模态框遮罩
 * @returns {HTMLElement[]}
 */
function collectFocusables(overlay) {
    return [...overlay.querySelectorAll(FOCUSABLE_SELECTOR)].filter((el) => {
        if (el.disabled) return false;
        if (el.closest('[hidden]') !== null) return false;
        if (el.getAttribute('aria-hidden') === 'true') return false;
        return true;
    });
}

/**
 * 打开一个模态框
 *
 * T4 快赢（焦点卫生）：打开时记录 `document.activeElement`；框内
 *   Tab/Shift+Tab 焦点循环（不跳出框，可聚焦元素见 FOCUSABLE_SELECTOR，
 *   hidden/disabled 过滤）；三条关闭路径（关闭按钮/遮罩/Escape）关闭后
 *   焦点还原到打开前元素（该元素已脱离 DOM 则跳过还原）。
 * @param {object} options
 * @param {string} [options.title] - 弹窗标题（自动 HTML 转义）
 * @param {string} [options.modalClass] - 附加到 .modal 的 class（如 'confirm-modal'）
 * @param {string} [options.headerExtra=''] - 渲染在 modal-header 之后、modal-body 之前的
 *   额外 HTML（如向导的进度条/步骤指示器；调用方自行转义）
 * @param {string} [options.body=''] - modal-body 内容（原始 HTML，调用方自行转义）
 * @param {string} [options.actions=''] - modal-footer 内容（原始 HTML）
 * @param {string|null} [options.overlayId] - 遮罩元素 id（用于按 id 查重/定位）
 * @param {string|null} [options.removeExisting] - 打开前移除已存在的弹窗：
 *   - CSS 选择器：移除「首个匹配项所在」的 .modal-overlay
 *   - null：不移除任何已存在弹窗
 * @param {string|null} [options.focusSelector] - 打开后 50ms 聚焦的元素选择器
 * @param {boolean} [options.closeOnEscape=true] - 按 Escape 关闭
 * @param {boolean} [options.closeOnBackdrop=true] - 点击遮罩关闭
 * @param {*} [options.cancelResult] - 关闭按钮/遮罩/Escape 关闭时传给 onClose 的结果
 * @param {function|null} [options.onOpen] - 打开后回调 (overlay, close) => void
 *   close(result) 关闭弹窗并把 result 传给 onClose
 * @param {function|null} [options.onClose] - 关闭回调 (result) => void
 * @returns {HTMLElement} 遮罩元素
 */
export function openModal(options = {}) {
    const {
        title = '',
        modalClass = '',
        headerExtra = '',
        body = '',
        actions = '',
        overlayId = null,
        removeExisting = null,
        focusSelector = null,
        closeOnEscape = true,
        closeOnBackdrop = true,
        cancelResult = undefined,
        onOpen = null,
        onClose = null,
    } = options;

    // T4 — 记录打开前焦点元素（关闭后还原）
    const previouslyFocused = document.activeElement;

    // 移除已存在的弹窗（按选择器定位首个匹配项所在的遮罩）
    if (removeExisting) {
        const existing = document.querySelector(removeExisting);
        if (existing) {
            (existing.closest('.modal-overlay') || existing).remove();
        }
    }

    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    if (overlayId) overlay.id = overlayId;

    overlay.innerHTML = `
        <div class="modal ${modalClass}">
            <div class="modal-header">
                <h3>${escapeHtml(title)}</h3>
                <button class="btn-icon modal-close" title="关闭">${iconHtml('x')}</button>
            </div>
            ${headerExtra}
            <div class="modal-body">${body}</div>
            <div class="modal-footer">${actions}</div>
        </div>
    `;

    document.body.appendChild(overlay);

    const close = (result = cancelResult) => {
        overlay.remove();
        if (onClose) onClose(result);
        // T4 — 关闭后焦点还原到打开前元素（已脱离 DOM 则跳过）
        if (previouslyFocused && typeof previouslyFocused.focus === 'function' && previouslyFocused.isConnected) {
            previouslyFocused.focus();
        }
    };

    // T4 — 焦点陷阱：Tab / Shift+Tab 在框内循环（不跳出框）。
    // focusables 在按键时收集（动态内容安全 — onOpen 中新增/移除控件也能正确循环）。
    overlay.addEventListener('keydown', (e) => {
        if (e.key !== 'Tab') return;
        const focusables = collectFocusables(overlay);
        if (focusables.length === 0) {
            e.preventDefault();
            return;
        }
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        const active = document.activeElement;
        if (e.shiftKey) {
            if (active === first || !focusables.includes(active)) {
                e.preventDefault();
                last.focus();
            }
        } else {
            if (active === last || !focusables.includes(active)) {
                e.preventDefault();
                first.focus();
            }
        }
    });

    // 通用关闭路径：关闭按钮 / 点击遮罩 / Escape
    overlay.querySelector('.modal-close').addEventListener('click', () => close());
    if (closeOnBackdrop) {
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) close();
        });
    }
    if (closeOnEscape) {
        overlay.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') close();
        });
    }

    if (onOpen) onOpen(overlay, close);

    if (focusSelector) {
        setTimeout(() => overlay.querySelector(focusSelector)?.focus(), 50);
    }

    return overlay;
}

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'openModal',
    'FOCUSABLE_SELECTOR',
];
