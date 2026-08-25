/**
 * Conver System — 删除/通用确认对话框
 *
 * 替代原生 confirm()，支持自定义标题、消息、详情展示。
 * 基于通用模态框工厂 openModal 实现，对外 API 保持不变。
 */

import { escapeHtml } from '../utils.js';
import { openModal } from './modal.js';
import { iconHtml } from '../icons.js';

/**
 * 显示确认对话框
 * @param {object} options
 * @param {string} options.title - 弹窗标题
 * @param {string} options.message - 主要提示信息
 * @param {string} [options.detail] - 额外详情（例如"关联 N 个对话"）
 * @param {string} [options.confirmText] - 确认按钮文字（默认"确定"）
 * @param {string} [options.cancelText] - 取消按钮文字（默认"取消"）
 * @param {boolean} [options.danger] - 是否为危险操作（默认 false）
 * @returns {Promise<boolean>} - true 确认，false 取消
 */
export function showConfirm(options = {}) {
    return new Promise((resolve) => {
        const {
            title = '确认操作',
            message = '确定要执行此操作吗？',
            detail = '',
            confirmText = '确定',
            cancelText = '取消',
            danger = false,
        } = options;

        openModal({
            title,
            modalClass: 'confirm-modal',
            // 只清确认弹窗，避免误关其它模态框如角色表单
            removeExisting: '.confirm-modal',
            focusSelector: '.confirm-ok',
            cancelResult: false,
            onClose: resolve,
            body: `
                <div class="confirm-icon ${danger ? 'danger' : ''}">
                    ${iconHtml(danger ? 'warning' : 'info', { size: 22 })}
                </div>
                <p class="confirm-message">${escapeHtml(message)}</p>
                ${detail ? `<p class="confirm-detail">${escapeHtml(detail)}</p>` : ''}
            `,
            actions: `
                ${cancelText ? `<button class="btn-secondary confirm-cancel">${escapeHtml(cancelText)}</button>` : ''}
                <button class="btn-primary confirm-ok ${danger ? 'btn-danger' : ''}">${escapeHtml(confirmText)}</button>
            `,
            onOpen: (overlay, close) => {
                if (cancelText) {
                    overlay.querySelector('.confirm-cancel').addEventListener('click', () => close(false));
                }
                overlay.querySelector('.confirm-ok').addEventListener('click', () => close(true));
                overlay.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') close(true);
                });
            },
        });
    });
}

/**
 * 显示提示对话框（替代原生 alert）
 * @param {string} message - 提示内容
 * @returns {Promise<void>}
 */
export function showAlert(message) {
    return showConfirm({
        title: '提示',
        message,
        confirmText: '确定',
        cancelText: null,  // 隐藏取消按钮
        danger: false,
    }).then(() => {});  // 始终 resolve 为 undefined
}

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'showConfirm',
    'showAlert',
];
