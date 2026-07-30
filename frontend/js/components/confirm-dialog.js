/**
 * Conver System — 删除/通用确认对话框
 *
 * 替代原生 confirm()，支持自定义标题、消息、详情展示。
 */

import { escapeHtml } from '../utils.js';

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

        // 移除已有模态框
        const existing = document.querySelector('.modal-overlay');
        if (existing) existing.remove();

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';

        overlay.innerHTML = `
            <div class="modal confirm-modal">
                <div class="modal-header">
                    <h3>${escapeHtml(title)}</h3>
                    <button class="btn-icon modal-close" title="关闭">✕</button>
                </div>
                <div class="modal-body">
                    <div class="confirm-icon ${danger ? 'danger' : ''}">
                        ${danger ? '⚠️' : 'ℹ️'}
                    </div>
                    <p class="confirm-message">${escapeHtml(message)}</p>
                    ${detail ? `<p class="confirm-detail">${escapeHtml(detail)}</p>` : ''}
                </div>
                <div class="modal-footer">
                    ${cancelText ? `<button class="btn-secondary confirm-cancel">${escapeHtml(cancelText)}</button>` : ''}
                    <button class="btn-primary confirm-ok ${danger ? 'btn-danger' : ''}">${escapeHtml(confirmText)}</button>
                </div>
            </div>
        `;

        document.body.appendChild(overlay);

        const close = (result) => {
            overlay.remove();
            resolve(result);
        };

        // 关闭事件
        overlay.querySelector('.modal-close').addEventListener('click', () => close(false));
        if (cancelText) {
            overlay.querySelector('.confirm-cancel').addEventListener('click', () => close(false));
        }
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) close(false);
        });

        // 确认事件
        overlay.querySelector('.confirm-ok').addEventListener('click', () => close(true));

        // 键盘事件
        overlay.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') close(false);
            if (e.key === 'Enter') close(true);
        });

        // 聚焦确认按钮
        setTimeout(() => overlay.querySelector('.confirm-ok').focus(), 50);
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
