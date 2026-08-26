/**
 * Conver System — 会话激活编排（深模块，ARC-6 从 app.js 提取）
 *
 * 职责：把「切到某会话」收敛为单一可测流程 — 三入口（侧栏点击 / 角色开始对话 /
 * 搜索跳转）与 tab 条激活共用：
 *   openTab 去重 → 补全 title/characterId（已知对话直接取，未知经 API 获取）
 *   → 草稿/滚动保存恢复 → 懒加载消息 → 刷新发送按钮两态 → 列表高亮 → 视图切换。
 *
 * P6.5 语义（拆分后行为保持）：
 *   - F-2 守卫：每次 await 后重查活动性 — await 期间用户切走/关闭该 tab 时
 *     放弃续体（否则旧草稿覆盖新活动输入框、缓存分支把本会话渲染进错误视图）
 *   - saveCurrent=false：删除会话/清空联动时调用方已预先保存视图状态，
 *     跳过保存防止被关会话的 DOM 草稿/滚动污染新活动 tab 缓存
 *   - 加载消息：缓存非空不重复请求；缓存为空才走 API（懒加载）；渲染前
 *     一律校验活动性（后返回的响应不覆盖先返回的）
 *
 * 依赖方向：conversation-activation.js → chat.js（chatDom/renderMessages/
 *   refreshSendButton/renderChatHeader/EMPTY_STATE_HTML）/ tabs.js / state.js / api.js；
 *   app.js → conversation-activation.js（经 setActivationHooks 注入 DOM 渲染回调，
 *   避免反向依赖 — 与 setChatHooks 同模式）。
 *   F4 收口后头部渲染直 import chat.js renderChatHeader（依赖方向不变 — 本模块
 *   本就依赖 chat.js；头部深模块归位 chat.js，无需再经 hooks 注入）。
 */

import { chatDom, renderMessages, refreshSendButton, renderChatHeader, EMPTY_HEADER_HTML } from './chat.js';
import { autoResizeInput } from './utils.js';
import { state } from './state.js';
import { conversations, messages } from './api.js';
import { openTab, getTab, getActiveTab, updateTab } from './tabs.js';

// ── DOM 渲染回调钩子（app.js 注入；缺失时 no-op 兜底）──
let hooks = {
    renderConversations: () => {},
    switchView: () => {},
    showError: () => {},
};
export function setActivationHooks(h) {
    hooks = { ...hooks, ...h };
}

/**
 * 保存当前活动 tab 的输入草稿与滚动位置到 tab 缓存（切换前调用）
 */
export function saveTabViewState() {
    const tab = getActiveTab();
    if (!tab) return;
    updateTab(tab.conversationId, {
        draft: chatDom.chatInput.value,
        scrollTop: chatDom.chatMessages.scrollTop,
    });
}

/**
 * 恢复指定 tab 的输入草稿与滚动位置到 DOM
 * @param {object|undefined} tab - 目标 tab（已关闭/不存在 → no-op，防御 F-2 竞态）
 */
export function restoreTabViewState(tab) {
    if (!tab) return;
    chatDom.chatInput.value = tab.draft ?? '';
    autoResizeInput(chatDom.chatInput);
    chatDom.chatMessages.scrollTop = tab.scrollTop ?? 0;
}

/**
 * 无活动 tab 时的空态（聊天区 + 头部提示）
 * 聊天区委托 renderMessages（chat.js 单一来源）：空态判定 + T1 首启引导卡
 * （凭证协议 none 时渲染引导卡）均由 renderMessages 收口，本处不内联重复。
 */
export function showEmptyState() {
    chatDom.chatHeader.innerHTML = EMPTY_HEADER_HTML;
    renderMessages();
}

/**
 * 懒加载指定会话消息并写入其 tab 缓存；仅当该 tab 仍为活动 tab 时才渲染
 * （快速连续切 tab 时各响应写各自 tab 缓存，后返回的响应不覆盖先返回的；
 * 缓存分支同样须校验活动性 —— F-2：await 期间切走时旧续体不得把 A 渲染进 B 的视图）
 * @param {number|string} conversationId - 会话 id
 */
export async function loadTabMessages(conversationId) {
    const tab = getTab(conversationId);
    if (!tab) return;
    // 已有缓存（含流式中断后的部分内容）→ 不重复请求，直接渲染
    if (tab.messages.length > 0) {
        if (getActiveTab()?.conversationId === conversationId) {
            renderMessages();
            // renderMessages 内部 scrollToBottom — 此处恢复缓存中的滚动位置（切 tab 恢复）
            chatDom.chatMessages.scrollTop = tab.scrollTop ?? 0;
            renderChatHeader(conversationId);
        }
        return;
    }
    try {
        const msgs = await messages.list(conversationId);
        updateTab(conversationId, { messages: msgs });
        if (getActiveTab()?.conversationId === conversationId) {
            renderMessages();
            renderChatHeader(conversationId);
        }
    } catch (err) {
        console.error('加载消息失败:', err);
        hooks.showError('加载消息失败');
        if (getActiveTab()?.conversationId === conversationId) {
            renderMessages();
            renderChatHeader(conversationId);
        }
    }
}

/**
 * 切到某会话的统一激活流程（三入口与 tab 条共用）：
 *   openTab/activateTab + 以已知对话数据补全 tab 的 title/characterId（未知则经 API 获取）
 *   + 懒加载消息 + 草稿/滚动保存恢复 + 刷新发送按钮两态 + 列表高亮 + 视图切换
 * @param {number|string} conversationId - 会话 id
 * @param {object} [options]
 * @param {boolean} [options.saveCurrent=true] - 切换前保存当前活动 tab 的草稿/滚动。
 *   删除会话联动场景调用方已预先保存，传 false 防止旧视图 DOM 状态污染新活动 tab 缓存。
 */
export async function activateConversation(conversationId, { saveCurrent = true } = {}) {
    // 1) 保存当前活动 tab 的草稿与滚动位置（切换前）
    if (saveCurrent) saveTabViewState();
    // 2) 打开/激活 tab（已存在仅激活，不重复开）
    const tab = openTab(conversationId);
    if (!tab) return;
    // 3) 补全 tab 的 title/characterId：已知对话数据直接取；未知经 API 获取
    let conv = state.conversations.find((c) => c.id === conversationId);
    if (!conv) {
        try {
            conv = await conversations.get(conversationId);
        } catch {
            // 忽略 — 至少尝试加载消息
        }
        // await 期间用户可能已切走或关闭该 tab — 放弃续体（F-2）：
        // 否则恢复旧草稿覆盖新活动输入框、缓存分支把本会话渲染进错误视图
        if (getActiveTab()?.conversationId !== conversationId) return;
    }
    if (conv) {
        updateTab(conversationId, { title: conv.title, characterId: conv.character_id });
    }
    // 4) 恢复新 tab 的草稿与滚动位置
    restoreTabViewState(getTab(conversationId));
    // 5) 懒加载消息（缓存为空才请求）+ 头部渲染
    await loadTabMessages(conversationId);
    if (getActiveTab()?.conversationId !== conversationId) return;
    // 6) 刷新发送按钮两态 + 列表高亮 + 视图（已在聊天视图则跳过 switchView 的重复 loadConversations）
    refreshSendButton();
    hooks.renderConversations();
    if (state.currentView !== 'chat') hooks.switchView('chat');
}

export const __all__ = [
    'setActivationHooks', 'saveTabViewState', 'restoreTabViewState', 'showEmptyState',
    'loadTabMessages', 'activateConversation',
];
