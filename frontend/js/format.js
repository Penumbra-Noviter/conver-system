/**
 * Conver System — 渲染/格式化纯函数
 *
 * 与 DOM 操作分离的可独立测试函数：文本高亮、消息/头像 HTML 构造。
 * 只做「数据 → HTML 字符串」的映射，不接触 DOM（appendChild / innerHTML 写入留在调用方）。
 */

import { escapeHtml, getInitials, renderMarkdown } from './utils.js';

/**
 * 高亮文本中的关键词（不区分大小写，只高亮第一个命中）
 * @param {string} text - 已转义的文本
 * @param {string} keyword - 已转义的关键词
 * @returns {string} HTML
 */
export function highlightText(text, keyword) {
    if (!keyword) return text;
    const idx = text.toLowerCase().indexOf(keyword.toLowerCase());
    if (idx === -1) return text;
    return text.slice(0, idx)
        + '<mark class="search-highlight">' + text.slice(idx, idx + keyword.length) + '</mark>'
        + text.slice(idx + keyword.length);
}

/**
 * 构造助手消息头像 HTML
 * @param {Array} characters - 角色列表
 * @param {number|null} currentCharacterId - 当前角色 id
 * @returns {string}
 */
export function assistantAvatarHtml(characters, currentCharacterId) {
    const char = (characters || []).find(c => c.id === currentCharacterId);
    if (char?.avatar) {
        return `<div class="msg-avatar"><img src="${escapeHtml(char.avatar)}" alt="${escapeHtml(char.name || '角色')}" onerror="this.parentElement.innerHTML='<div class=\\'avatar-placeholder-xs\\'>${escapeHtml(getInitials(char.name || 'A'))}</div>'"></div>`;
    }
    const name = char?.name || 'AI';
    return `<div class="msg-avatar"><div class="avatar-placeholder-xs">${escapeHtml(getInitials(name))}</div></div>`;
}

/**
 * 构造用户消息头像 HTML
 * @returns {string}
 */
export function userAvatarHtml() {
    return `<div class="msg-avatar user-avatar">👤</div>`;
}

/**
 * 构造消息列表 HTML（纯函数，不操作 DOM）
 * @param {Array} messages - 消息数组
 * @param {object} [context]
 * @param {Array} [context.characters=[]] - 角色列表（用于 assistant 头像）
 * @param {number|null} [context.currentCharacterId=null] - 当前角色 id
 * @returns {string} 消息区域 HTML（空列表返回 empty-state）
 */
export function buildMessagesHtml(messages, context = {}) {
    const { characters = [], currentCharacterId = null } = context;
    if (!Array.isArray(messages) || messages.length === 0) {
        return '<div class="empty-state"><p>开始一段对话吧</p></div>';
    }
    return messages.map((m) => `
        <div class="message ${m.role}">
            ${m.role === 'assistant' ? assistantAvatarHtml(characters, currentCharacterId) : userAvatarHtml()}
            <div class="message-content">${m.role === 'assistant' ? renderMarkdown(m.content) : escapeHtml(m.content)}</div>
            <button class="btn-copy-message" title="复制消息" data-content="${escapeHtml(m.content)}">📋</button>
        </div>
    `).join('');
}
