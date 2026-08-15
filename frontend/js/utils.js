/**
 * Conver System — 共享工具函数
 */

import { requestBlob } from './api.js';

/**
 * HTML 转义（防 XSS）
 * @param {string} str
 * @returns {string}
 */
export function escapeHtml(str) {
    if (typeof str !== 'string') return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

/**
 * 显示 Toast 通知（自动 5 秒后消失）
 * @param {string} message - 提示内容
 * @param {'success'|'error'} type - 类型（影响样式）
 */
export function showToast(message, type = 'success') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 5000);
}

/**
 * 显示错误 Toast（C4 薄封装 — showToast(message, 'error')，语义单点）
 * @param {string} message - 提示内容
 */
export function showError(message) {
    showToast(message, 'error');
}

/**
 * 显示成功 Toast（C4 薄封装 — showToast(message, 'success')，语义单点）
 * @param {string} message - 提示内容
 */
export function showSuccess(message) {
    showToast(message, 'success');
}

/**
 * 通用 Blob 下载 — 委托 api.requestBlob（走 doFetch seam）→ blob → <a download> 触发浏览器保存
 * 对话导出与角色卡导出共用（P2.5.5）。签名与行为保持（app.js / export-dialog.js 调用点无需改）；
 * URL 策略单一来源：一律经 requestBlob 拼接（旧式 '/api' 前缀自动归一化）。
 * 下载文件名优先取服务端 Content-Disposition（RFC 5987 filename*），无则回退入参 filename。
 * @param {string} url - 导出 API 地址（如 /api/characters/1/export）
 * @param {string} filename - 下载文件名兜底（浏览器自动清洗非法字符）
 * @param {string} [errorPrefix='导出失败'] - 失败提示前缀
 */
export async function downloadBlob(url, filename, errorPrefix = '导出失败') {
    try {
        const { blob, filename: serverFilename } = await requestBlob(url);
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = serverFilename || filename;
        a.click();
        URL.revokeObjectURL(a.href);
    } catch (err) {
        showToast(`${errorPrefix}: ${err.message}`, 'error');
    }
}

/**
 * 获取角色名称首字母/首字
 * @param {string} name
 * @returns {string}
 */
export function getInitials(name) {
    if (!name) return '?';
    const trimmed = name.trim();
    // 中文取前两个字，英文取前两个字母
    if (/[一-鿿]/.test(trimmed)) {
        return trimmed.slice(0, 2);
    }
    return trimmed.slice(0, 2).toUpperCase();
}

/**
 * 格式化标签数组为可读字符串
 * @param {string[]} tags - 标签数组
 * @returns {string}
 */
export function formatTags(tags) {
    if (!Array.isArray(tags) || tags.length === 0) return '';
    return tags.slice(0, 3).join(', ');
}

/**
 * 输入框自动增高（ARC-10 C7 收口：app.js 输入事件 / 激活模块恢复视图 / chat.js 发送后复位）
 * 先复位 height='auto' 再按内容高度增高，上限 150px；调用时机差异留在调用方。
 * @param {HTMLElement} el - 目标输入框元素
 */
export function autoResizeInput(el) {
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 150) + 'px';
}
