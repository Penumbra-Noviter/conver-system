/**
 * Conver System — 全局应用状态
 *
 * 职责：
 *   1. 全局 `state` 对象（应用级数据缓存，跨模块共享同一引用）
 *
 * P6.5 契约收缩：会话级字段（currentConversationId / currentCharacterId / messages /
 * isStreaming / activeStream）已退役 —— 会话 UI 的单一事实来源改为「活动 tab」
 * （见 tabs.js）；本模块只保留全局配置与列表数据。
 * toggleStream 流式开关是全局偏好（DOM 复选框），保持现状、不随 tab。
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
    models: { providers: [] },       // 可用模型列表
    defaultProvider: 'claude',
    defaultProviderName: 'Claude (Anthropic)',
    defaultModel: 'claude-sonnet-5',
    sidebarCollapsed: false,
    chatSidebarCollapsed: false,
    // 凭证协议（T1 首启引导判定依据；app.js init 检测后缓存 —
    // 'openai' | 'claude' | 'none'；未检测/检测失败为 null）
    credentialsProtocol: null,
};

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'state',
];
