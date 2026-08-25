/**
 * Conver System — 对话导出对话框组件
 *
 * 选择导出格式（Markdown / JSON）并触发下载。基于通用模态框工厂 openModal 实现。
 */

import { openModal } from './modal.js';
import { downloadBlob, showToast } from '../utils.js';
import { iconHtml } from '../icons.js';

/**
 * 显示对话导出对话框
 * @param {number} conversationId - 对话 ID
 */
export function showExportDialog(conversationId) {
    // 已存在导出弹窗则不重复创建（旧行为保持）
    if (document.getElementById('export-dialog-overlay')) return;

    openModal({
        title: '导出对话',
        modalClass: 'export-modal',
        overlayId: 'export-dialog-overlay',
        body: `
            <p class="export-hint">选择导出格式：</p>
            <div class="export-options">
                <button class="export-option-btn" data-format="markdown">
                    <span class="export-option-icon">${iconHtml('fileText')}</span>
                    <span class="export-option-label">Markdown (.md)</span>
                    <span class="export-option-desc">可读的纯文本格式，适合分享和查看</span>
                </button>
                <button class="export-option-btn" data-format="json">
                    <span class="export-option-icon">${iconHtml('fileJson')}</span>
                    <span class="export-option-label">JSON (.json)</span>
                    <span class="export-option-desc">结构化数据格式，适合程序处理</span>
                </button>
            </div>
        `,
        actions: `
            <button class="btn-secondary export-cancel">取消</button>
        `,
        onOpen: (overlay, close) => {
            overlay.querySelector('.export-cancel').addEventListener('click', () => close());
            overlay.querySelectorAll('.export-option-btn').forEach(btn => {
                btn.addEventListener('click', () => {
                    const format = btn.dataset.format;
                    close();
                    downloadExport(conversationId, format);
                });
            });
        },
    });
}

/**
 * 按导出格式触发 Blob 下载（异步导出期间显示进度提示）
 * @param {number} conversationId - 对话 ID
 * @param {'markdown'|'json'} format - 导出格式
 */
async function downloadExport(conversationId, format) {
    showToast('正在导出对话…', 'info');
    const ext = format === 'markdown' ? '.md' : '.json';
    await downloadBlob(
        `/api/conversations/${conversationId}/export/${format}`,
        `conversation-${conversationId}${ext}`
    );
}

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'showExportDialog',
];
