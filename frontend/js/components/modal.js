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
 * 打开一个模态框
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
    };

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
];
