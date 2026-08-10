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
 * 轻量 Markdown 渲染（安全 — 先转义再解析标记）
 * 支持：代码块、内联代码、粗体、斜体、链接、无序/有序列表
 * @param {string} text - 原始文本
 * @returns {string} 渲染后的 HTML
 */
export function renderMarkdown(text) {
    if (typeof text !== 'string' || !text) return '';

    // 先转义 HTML，再解析 Markdown 标记
    let html = escapeHtml(text);

    // ── 代码块 (```...```) — 必须在其他标记之前处理 ──
    html = html.replace(/```(\w*)\n?([\s\S]*?)```/g, (_, lang, code) => {
        const langClass = lang ? ` class="lang-${escapeHtml(lang)}"` : '';
        return `<pre><code${langClass}>${code}</code></pre>`;
    });

    // ── 内联代码 `code` ──
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

    // ── 粗体 **text** ──
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

    // ── 斜体 *text* ──
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');

    // ── 链接 [text](url) ──
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

    // ── 列表（行级处理） — 将行首的 - / * / 1. 转为 HTML 列表 ──
    const lines = html.split('\n');
    const result = [];
    let inUl = false;
    let inOl = false;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // 处理水平分割线
        if (/^[-*_]{3,}$/.test(line.trim())) {
            if (inUl) { result.push('</ul>'); inUl = false; }
            if (inOl) { result.push('</ol>'); inOl = false; }
            result.push('<hr>');
            continue;
        }

        // 无序列表 - 或 *
        const ulMatch = line.match(/^(\s*)[*\-]\s+(.*)$/);
        if (ulMatch) {
            if (inOl) { result.push('</ol>'); inOl = false; }
            if (!inUl) { result.push('<ul>'); inUl = true; }
            result.push(`<li>${ulMatch[2]}</li>`);
            continue;
        }

        // 有序列表 1. 2.
        const olMatch = line.match(/^(\s*)\d+\.\s+(.*)$/);
        if (olMatch) {
            if (inUl) { result.push('</ul>'); inUl = false; }
            if (!inOl) { result.push('<ol>'); inOl = true; }
            result.push(`<li>${olMatch[2]}</li>`);
            continue;
        }

        // 关闭打开的列表
        if (inUl) { result.push('</ul>'); inUl = false; }
        if (inOl) { result.push('</ol>'); inOl = false; }

        // 空行 → 段落分隔
        if (line.trim() === '') {
            result.push('<p></p>');
        } else {
            result.push(line);
        }
    }

    if (inUl) result.push('</ul>');
    if (inOl) result.push('</ol>');

    html = result.join('\n');

    return html;
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
 * 解析 Provider 显示名（provider key → 展示名）
 *
 * 对话记录只存 provider key（如 'deepseek'），展示名来自 /api/models 的
 * providers 元数据（key/name 映射）。未匹配时回退为原始 key，避免硬编码
 * 二元映射导致 deepseek/qwen 等第三方 provider 被误显示为 Claude。
 *
 * @param {{providers?: Array<{key: string, name: string}>} | Array | null | undefined} modelData - 模型数据（state.models 或 providers 数组）
 * @param {string | null | undefined} providerKey - 对话记录中的 provider key
 * @returns {string} 显示名；providerKey 为空返回空串
 */
export function providerDisplayName(modelData, providerKey) {
    if (!providerKey) return '';
    const providers = Array.isArray(modelData) ? modelData : modelData?.providers;
    const found = (providers || []).find((p) => p && p.key === providerKey);
    return found?.name || providerKey;
}
