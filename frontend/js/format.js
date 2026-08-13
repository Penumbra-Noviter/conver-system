/**
 * Conver System — 渲染/格式化纯函数
 *
 * 与 DOM 操作分离的可独立测试函数：文本高亮、消息/头像 HTML 构造。
 * 只做「数据 → HTML 字符串」的映射，不接触 DOM（appendChild / innerHTML 写入留在调用方）。
 */

import { escapeHtml, getInitials, formatTags } from './utils.js';
import { renderMarkdown } from './markdown.js';
import { iconHtml } from './icons.js';

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
 * 头像 img HTML（ARC-10 C7 收口：加载失败回退参数化复用）
 *
 * 产出 `<img src=… alt=… onerror="this.parentElement.innerHTML='…'">`；
 * onerror 内嵌单引号按 `\'` 转义形态生成（行为等价 — 触发后父元素 innerHTML
 * 替换为 fallbackHtml）。fallback 内的双引号转义为 &quot; 保证属性不中断。
 *
 * @param {string} src - 头像地址（自动 HTML 转义）
 * @param {string} alt - 替代文本（自动 HTML 转义）
 * @param {string} fallbackHtml - 加载失败回退 HTML（调用方传，如 initials 占位或「图片加载失败」）
 * @returns {string} img HTML
 */
export function avatarImgHtml(src, alt, fallbackHtml) {
    const onErrorJs = `this.parentElement.innerHTML='${fallbackHtml
        .replace(/\\/g, '\\\\')
        .replace(/'/g, "\\'")
        .replace(/"/g, '&quot;')}'`;
    return `<img src="${escapeHtml(src)}" alt="${escapeHtml(alt)}" onerror="${onErrorJs}">`;
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
        return `<div class="msg-avatar">${avatarImgHtml(char.avatar, char.name || '角色', `<div class='avatar-placeholder-xs'>${escapeHtml(getInitials(char.name || 'A'))}</div>`)}</div>`;
    }
    const name = char?.name || 'AI';
    return `<div class="msg-avatar"><div class="avatar-placeholder-xs">${escapeHtml(getInitials(name))}</div></div>`;
}

/**
 * 构造用户消息头像 HTML
 * @returns {string}
 */
export function userAvatarHtml() {
    return `<div class="msg-avatar user-avatar">${iconHtml('user', { size: 18 })}</div>`;
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
            <button class="btn-copy-message" title="复制消息" data-content="${escapeHtml(m.content)}">${iconHtml('clipboard')}</button>
        </div>
    `).join('');
}

// ══════════════════════════════════════════════════
// 视图渲染模板纯函数（ARC-6 从 app.js 迁移）
// ══════════════════════════════════════════════════

/**
 * 角色卡片 HTML（character-grid 渲染模板，事件绑定留在调用方）
 * @param {object} c - 角色对象（id/name/avatar/description/personality/first_mes/tags/temperature/conversation_count）
 * @returns {string} 角色卡片 HTML
 */
export function characterCardHtml(c) {
    return `
        <div class="character-card" data-id="${c.id}">
            <div class="character-card-header">
                <div class="character-avatar">
                    ${c.avatar
                        ? avatarImgHtml(c.avatar, c.name, `<div class='avatar-placeholder-sm'>${escapeHtml(getInitials(c.name))}</div>`)
                        : `<div class="avatar-placeholder-sm">${escapeHtml(getInitials(c.name))}</div>`
                    }
                </div>
                <div class="character-card-info">
                    <div class="name">${escapeHtml(c.name)}</div>
                    <div class="subtitle">${escapeHtml(c.description || c.personality?.slice(0, 60) || '未设定')}</div>
                </div>
            </div>
            <div class="character-card-details">
                ${c.first_mes ? `<div class="detail-item"><span class="detail-label">开场白:</span> ${escapeHtml(c.first_mes.slice(0, 60))}${c.first_mes.length > 60 ? '…' : ''}</div>` : ''}
                ${c.tags && c.tags.length ? `<div class="detail-item"><span class="detail-label">标签:</span> ${escapeHtml(formatTags(c.tags))}</div>` : ''}
            </div>
            <div class="character-card-meta">
                <span class="meta-badge">${iconHtml('temperature', { size: 14 })} ${c.temperature?.toFixed(1) ?? '0.7'}</span>
                <span class="meta-badge">${iconHtml('messages', { size: 14 })} ${c.conversation_count ?? 0}</span>
            </div>
            <div class="character-card-actions">
                <button class="btn-icon chat-with" title="开始对话">${iconHtml('chat')}</button>
                <button class="btn-icon edit-char" title="编辑">${iconHtml('edit')}</button>
                <button class="btn-icon export-char" title="导出角色卡">${iconHtml('export')}</button>
                <button class="btn-icon delete-char" title="删除">${iconHtml('trash')}</button>
            </div>
        </div>
    `;
}

/**
 * 对话列表项 HTML（conversation-list 渲染模板；激活高亮由调用方以活动 tab 判定传入）
 * @param {object} c - 对话对象（id/title/message_count/model_name/model_provider）
 * @param {object} [opts]
 * @param {number|null} [opts.activeId=null] - 活动 tab 的会话 id（匹配则高亮）
 * @returns {string} 对话列表项 HTML
 */
export function conversationItemHtml(c, { activeId = null } = {}) {
    return `
        <div class="conversation-item ${c.id === activeId ? 'active' : ''}"
             data-id="${c.id}">
            <div class="title">${escapeHtml(c.title)}</div>
            <div class="meta">${c.message_count} 条消息 · ${escapeHtml(c.model_name || c.model_provider)}</div>
            <button class="btn-icon btn-delete-conv" title="删除对话">${iconHtml('x', { size: 14 })}</button>
        </div>
    `;
}

/**
 * 搜索结果项 HTML（search-results 渲染模板；关键词高亮）
 * @param {object} r - 搜索结果（role/character_name/created_at/content_preview/conversation_id/message_id/conversation_title）
 * @param {string} query - 原始查询（用于高亮）
 * @returns {string} 搜索结果项 HTML
 */
export function searchResultItemHtml(r, query) {
    const roleLabel = r.role === 'user' ? '你' : escapeHtml(r.character_name);
    const roleIcon = iconHtml(r.role === 'user' ? 'user' : 'character', { size: 14 });
    const time = r.created_at ? new Date(r.created_at).toLocaleString('zh-CN') : '';
    const escapedQuery = escapeHtml(query);
    const highlighted = highlightText(escapeHtml(r.content_preview), escapedQuery);
    return `
        <div class="search-result-item" data-conversation-id="${r.conversation_id}" data-message-id="${r.message_id}">
            <div class="search-result-header">
                <span class="search-result-role">${roleIcon} ${escapeHtml(roleLabel)}</span>
                <span class="search-result-conv">${iconHtml('messages', { size: 14 })} ${escapeHtml(r.conversation_title || '未命名对话')}</span>
            </div>
            <div class="search-result-preview">${highlighted}</div>
            <div class="search-result-time">${escapeHtml(time)}</div>
        </div>
    `;
}

export const __all__ = [
    'highlightText', 'avatarImgHtml', 'assistantAvatarHtml', 'userAvatarHtml', 'buildMessagesHtml',
    'characterCardHtml', 'conversationItemHtml', 'searchResultItemHtml',
];
