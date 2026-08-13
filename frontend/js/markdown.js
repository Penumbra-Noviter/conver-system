/**
 * Conver System — 轻量 Markdown 渲染模块
 *
 * 职责：renderMarkdown 由 utils.js 迁出（FE-3），独立承载「文本 → HTML 字符串」
 *       的渲染映射；内部复用 utils.js 的 escapeHtml 保证先转义再解析（防 XSS）。
 *
 * 协议表面（__all__）：renderMarkdown。
 */

import { escapeHtml } from './utils.js';

// 允许的 URL scheme 白名单（Falsify 硬化：javascript: / data: / vbscript: 等注入 scheme 一律中和）
const SAFE_URL_SCHEMES = /^(https?|mailto|tel)$/i;

/**
 * 校验链接 URL 的 scheme（防 javascript: 等 XSS 注入）
 *
 * WHATWG URL 解析器在解析 scheme 前会剥离全部 ASCII tab/换行，并剔除首尾 C0 控制字符，
 * 因此 `java\tscript:foo` / `\x00javascript:foo` 等变体在浏览器中仍解析为 javascript:。
 * 这里先在 scheme 匹配前剔除 [\u0000-\u0020]（C0 控制字符 + 空格）再比对白名单，
 * 防止控制字符绕过；匹配通过时仍返回原始（trim 后）URL，正常 URL 逐字节不变。
 *
 * TD-42（属性注入面）：href 属性以双引号包裹，URL 内任何裸引号（" 或 '）均可击穿
 * 属性边界注入事件属性（`[x](" onmouseover="alert(1))` 实测产出 onmouseover 属性）。
 * escapeHtml 不转义引号（textContent→innerHTML 引号原样通过），故在 trim 后直接拒绝
 * 含引号 URL（返回 null → 调用方中和为纯文本）。单引号实测不击穿双引号属性边界
 * （jsdom DOM 解析验证），但 URL 安全性判定不应依赖渲染模板的属性引号风格
 * （防未来模板单引号化后静默复发），故一并拒绝；代价：RFC 3986 sub-delims 允许的
 * 含 ' URL（如 mailto:foo'bar@x.com）被中和为纯文本，本仓库无真实用例，可接受。
 *
 * @param {string} url - 原始链接地址（已 HTML 转义，可能含首尾空白）
 * @returns {string|null} 去首尾空白后的安全 URL；含引号或 scheme 不在白名单时返回 null（调用方渲染为纯文本）
 */
function sanitizeUrl(url) {
    const trimmed = url.trim();
    if (trimmed.includes('"') || trimmed.includes("'")) return null;
    const scheme = trimmed.replace(/[\u0000-\u0020]/g, '').match(/^([a-z][a-z0-9+.-]*):/i);
    if (scheme && !SAFE_URL_SCHEMES.test(scheme[1])) return null;
    return trimmed;
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
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, url) => {
        const href = sanitizeUrl(url);
        if (href === null) return label;
        return `<a href="${href}" target="_blank" rel="noopener noreferrer">${label}</a>`;
    });

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
