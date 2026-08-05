/**
 * Conver System — 全局应用状态
 *
 * 职责：
 *   1. 全局 `state` 对象（应用级数据缓存，跨模块共享同一引用）
 *   2. 模块级状态（对话列表可见性 / 搜索防抖定时器）
 *
 * 依赖方向：state.js 不依赖任何模块；app.js / chat.js → state.js
 */

// ══════════════════════════════════════════════════
// 全局状态
// ══════════════════════════════════════════════════

export const state = {
    currentView: 'chat',
    characters: [],
    conversations: [],
    currentConversationId: null,
    currentCharacterId: null,
    messages: [],
    isStreaming: false,
    activeStream: null,            // 当前流式请求的 { abort, done } 句柄
    models: { providers: [] },       // 可用模型列表
    defaultProvider: 'claude',
    defaultModel: 'claude-sonnet-4-20250514',
    sidebarCollapsed: false,
    chatSidebarCollapsed: false,
};

// ══════════════════════════════════════════════════
// 模块级状态
// ══════════════════════════════════════════════════

// 对话列表可见性（移动端）
let convListVisible = true;

export function getConvListVisible() {
    return convListVisible;
}

export function setConvListVisible(visible) {
    convListVisible = visible;
}

// 搜索防抖定时器
let searchTimeout = null;

export function setSearchTimeout(timeoutId) {
    searchTimeout = timeoutId;
}

export function clearSearchTimeout() {
    clearTimeout(searchTimeout);
    searchTimeout = null;
}
