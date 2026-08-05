/**
 * Conver System — 全局应用状态
 *
 * 职责：
 *   1. 全局 `state` 对象（应用级数据缓存，跨模块共享同一引用）
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
    defaultProviderName: 'Claude (Anthropic)',
    defaultModel: 'claude-sonnet-5',
    sidebarCollapsed: false,
    chatSidebarCollapsed: false,
};
