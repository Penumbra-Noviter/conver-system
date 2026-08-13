/**
 * Conver System — 聊天域
 *
 * 职责：
 *   1. 消息渲染（renderMessages / appendMessage / thinking / 头像 / 复制）
 *   2. 发送与流式交互（handleSend）
 *   3. 聊天域 DOM 引用（chatDom）
 *   4. 发送按钮两态（send/stop）— 由活动 tab 的 isStreaming 派生（refreshSendButton）
 *
 * P6.5 多 tab 语义：
 *   - 消息渲染读活动 tab 缓存（messages/characterId），无活动 tab → 空态
 *   - handleSend 发起时捕获 conversationId；onToken 按活动归属分流 —— 活动 tab
 *     走 DOM 增量追加 + 缓存同步，后台 tab 只累积 per-tab 缓存不碰 DOM
 *   - 流式生命周期（fullContent 累积 / streamSettled 终态守卫 / revision 守卫 /
 *     位置结算 / 失败位置感知写回）收口到 stream-session.js 深模块（零 DOM）；
 *     chat.js 只保留 DOM 增量渲染（气泡复用 / data-streaming-live / thinking）
 *   - onDone / onError 一律经 updateTab(捕获的 conversationId, …) 写回发起 tab，
 *     绝不读「当前活动」—— 防悬挂核心设计（发起 tab 可能已被关闭，
 *     updateTab 对不存在 id 幂等 no-op 兜底）
 *   - 停止（AbortError）写回 phase 'error'（警示标记；气泡保持「已停止」语义），
 *     正常完成写回 phase 'done'
 *
 * 依赖方向：chat.js → state.js / api.js / utils.js / format.js / tabs.js / stream-session.js；
 * app.js → chat.js
 * 不反向引用 app.js 私有函数 — 对话列表刷新通过 setConversationsRefresher 注入。
 */

import { chatStream, messages } from './api.js';
import { autoResizeInput } from './utils.js';
import { renderMarkdown } from './markdown.js';
import { buildMessagesHtml, assistantAvatarHtml, userAvatarHtml } from './format.js';
import { state } from './state.js';
import { getActiveTab, getTab, updateTab } from './tabs.js';
import { createStreamSession, settleTurn } from './stream-session.js';
import { iconHtml } from './icons.js';

// ══════════════════════════════════════════════════
// 聊天域 DOM 引用
// ══════════════════════════════════════════════════

const $ = (sel) => document.querySelector(sel);

export const chatDom = {
    chatMessages: $('#chat-messages'),
    chatInput: $('#chat-input'),
    btnSend: $('#btn-send'),
    toggleStream: $('#toggle-stream'),
    chatHeader: $('#chat-header'),
};

/** 无活动 tab 时的消息区空态（单一事实来源 — app.js showEmptyState 复用，禁止内联重复） */
export const EMPTY_STATE_HTML = '<div class="empty-state"><p>选择左侧对话或创建新对话开始聊天</p></div>';

/** 无会话时的头部空态文案（单一事实来源 — app.js renderChatHeader / 激活模块 showEmptyState 复用，禁止内联重复） */
export const EMPTY_HEADER_HTML = '<span class="chat-title">选择一个角色开始对话</span>';

// ── 对话列表刷新钩子（由 app.js 注入，避免反向依赖）──
let refreshConversations = () => {};
export function setConversationsRefresher(fn) {
    refreshConversations = typeof fn === 'function' ? fn : () => {};
}

// ── 非流式在途守卫（FIX-B）──
// 非流式请求在途的 conversationId 集合（per-tab 作用域）：Enter/按钮双击或重复提交
// 只发一次真实请求，完成/失败后经 finally 清除。流式连发语义不受影响 —— 流式由
// tab.isStreaming + StreamSession onDone 即时复位管理，本守卫只拦截非流式提交。
const nonStreamingInFlight = new Set();
const copyFeedbackTimers = new WeakMap();

// ══════════════════════════════════════════════════
// 消息渲染
// ══════════════════════════════════════════════════

export function renderMessages() {
    const container = chatDom.chatMessages;
    const tab = getActiveTab();
    if (!tab) {
        container.innerHTML = EMPTY_STATE_HTML;
        return;
    }
    container.innerHTML = buildMessagesHtml(tab.messages, {
        characters: state.characters,
        currentCharacterId: tab.characterId,
    });

    // 复制按钮事件
    container.querySelectorAll('.btn-copy-message').forEach(btn => {
        attachCopyButton(btn, btn.dataset.content);
    });

    // 缓存渲染路径还原停止/错误标记（切走再切回后语义保持一致）
    const bubbles = container.querySelectorAll('.message');
    tab.messages.forEach((m, i) => {
        const bubble = bubbles[i];
        if (!bubble) return;
        if (m.stopped) markStopped(bubble);
        if (m.error) bubble.classList.add('message-error');
    });

    // 标记缓存中的流式中消息 — 切回后 onToken 复用该气泡继续增量渲染（不重复创建气泡）
    const lastMsg = tab.messages[tab.messages.length - 1];
    if (lastMsg?.streaming) {
        const liveBubble = bubbles[bubbles.length - 1];
        if (liveBubble) liveBubble.dataset.streamingLive = '1';
    }

    scrollToBottom();
}

/**
 * DOM 追加消息气泡；user/assistant 同步写入活动 tab 缓存（system 仅 DOM 提示，不落 tab 缓存）
 * @param {'user'|'assistant'|'system'} role - 消息角色
 * @param {string} content - 消息内容
 * @param {object} [meta] - 附加字段（如 { stopped: true, error: true }）
 */
function appendMessage(role, content, meta = {}) {
    const container = chatDom.chatMessages;
    // 移除空状态
    const empty = container.querySelector('.empty-state');
    if (empty) empty.remove();
    // 移除 thinking 指示器
    const thinking = container.querySelector('.thinking-indicator');
    if (thinking) thinking.remove();

    const div = document.createElement('div');
    div.className = `message ${role}`;

    // 头像
    div.appendChild(createAvatarElement(role));

    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    if (role === 'assistant') {
        contentDiv.innerHTML = renderMarkdown(content);
    } else {
        contentDiv.textContent = content;
    }
    div.appendChild(contentDiv);

    // 复制按钮
    const copyBtn = document.createElement('button');
    copyBtn.className = 'btn-copy-message';
    copyBtn.title = '复制消息';
    copyBtn.innerHTML = iconHtml('clipboard');
    copyBtn.dataset.content = content;
    attachCopyButton(copyBtn, content);
    div.appendChild(copyBtn);

    container.appendChild(div);
    scrollToBottom();

    // 缓存同步（仅活动 tab 的 DOM 追加会经过本函数）
    if (role !== 'system') {
        const tab = getActiveTab();
        if (tab) {
            updateTab(tab.conversationId, { messages: [...tab.messages, { role, content, ...meta }] });
        }
    }
}

function showThinkingIndicator() {
    const container = chatDom.chatMessages;
    // 移除已有 thinking
    const existing = container.querySelector('.thinking-indicator');
    if (existing) existing.remove();

    const div = document.createElement('div');
    div.className = 'thinking-indicator';
    div.innerHTML = '<span class="dot-pulse"></span> 思考中…';
    container.appendChild(div);
    scrollToBottom();
}

function scrollToBottom() {
    chatDom.chatMessages.scrollTop = chatDom.chatMessages.scrollHeight;
}

// ── 头像渲染 ──

/**
 * 获取当前活动 tab 对应角色的头像 HTML
 * @returns {string}
 */
function getAssistantAvatarHtml() {
    return assistantAvatarHtml(state.characters, getActiveTab()?.characterId ?? null);
}

/**
 * 获取默认用户头像 HTML
 * @returns {string}
 */
function getUserAvatarHtml() {
    return userAvatarHtml();
}

/**
 * 创建消息头像 DOM 元素（复用 HTML 字符串辅助函数）
 * @param {'assistant'|'user'} role - 消息角色
 * @returns {HTMLElement} 头像元素
 */
function createAvatarElement(role) {
    const wrapper = document.createElement('div');
    wrapper.innerHTML = role === 'assistant' ? getAssistantAvatarHtml() : getUserAvatarHtml();
    return wrapper.firstElementChild;
}

/**
 * 为消息复制按钮绑定点击事件（复制内容到剪贴板并给出图标反馈）
 * @param {HTMLButtonElement} btn - 复制按钮元素
 * @param {string} content - 要复制的消息内容
 */
function attachCopyButton(btn, content) {
    btn.addEventListener('click', async (e) => {
        e.stopPropagation();
        const pendingTimer = copyFeedbackTimers.get(btn);
        if (pendingTimer) clearTimeout(pendingTimer);

        let feedbackIcon = 'check';
        try {
            await navigator.clipboard.writeText(content);
            btn.classList.add('copied');
        } catch {
            feedbackIcon = 'x';
            btn.classList.remove('copied');
        }

        btn.innerHTML = iconHtml(feedbackIcon);
        const timer = setTimeout(() => {
            btn.innerHTML = iconHtml('clipboard');
            btn.classList.remove('copied');
            copyFeedbackTimers.delete(btn);
        }, 1500);
        copyFeedbackTimers.set(btn, timer);
    });
}

// ── 发送按钮 ──

/**
 * 发送按钮两态 — 由活动 tab 的 isStreaming 派生（单一事实来源）
 * 活动 tab 流式生成中 → stop 停止；否则 → send 发送。切 tab 时由激活流程调用刷新。
 */
export function refreshSendButton() {
    const btn = chatDom.btnSend;
    if (!btn) return;
    const streaming = getActiveTab()?.isStreaming ?? false;
    if (streaming) {
        btn.disabled = false;
        btn.innerHTML = iconHtml('stop');
        btn.title = '停止生成';
        btn.classList.add('btn-stop');
    } else {
        btn.disabled = false;
        btn.innerHTML = iconHtml('send');
        btn.title = '发送';
        btn.classList.remove('btn-stop');
    }
}

/**
 * 给停止的 assistant 气泡追加「（已停止）」标记 — 语义为用户主动停止，非错误（P3.5）
 * @param {HTMLElement} assistantDiv - assistant 消息元素
 */
function markStopped(assistantDiv) {
    const tag = document.createElement('div');
    tag.className = 'message-stop-tag';
    tag.textContent = '（已停止）';
    assistantDiv.appendChild(tag);
    scrollToBottom();
}

/**
 * 同步聊天头部标题 — 与对话列表保持一致（P3.5 标题联动）
 * 后端保存首条 user 消息后自动替换占位标题，发送完成后据此刷新头部标题，
 * 并同步活动 tab 缓存中的 title（tab 条随动）。
 */
function syncChatHeaderTitle() {
    const tab = getActiveTab();
    const titleEl = chatDom.chatHeader.querySelector('#chat-title-text');
    if (!titleEl || !tab) return;
    const conv = state.conversations.find((c) => c.id === tab.conversationId);
    if (conv) {
        titleEl.textContent = conv.title;
        updateTab(tab.conversationId, { title: conv.title });
    }
}

// ── 发送消息（流式防悬挂核心）──
//
// 流式生命周期已收口到 stream-session.js（createStreamSession）：fullContent 累积、
// streamSettled 终态守卫、按发起 tab 写回（防悬挂）、完成重载的 mergeFreshList
// 三分支（fresh 整体替换 / stale 仅位置结算 / 失败位置感知追加 — 根治 R2）；
// 流式 onDone 正常完成段与非流式完成分支（成功 + 失败兜底）都委托统一结算入口
// settleTurn（reload → mergeFreshList → 写回 → 条件渲染，内部 try/catch 双分支）。
// chat.js 只保留：DOM 增量渲染（气泡复用 / data-streaming-live / thinking）、
// 非流式特有交互（在途守卫 / 按钮禁用 / 失败气泡 / 按钮复位）、发送按钮两态与列表刷新注入。

export async function handleSend() {
    const content = chatDom.chatInput.value.trim();
    const tab = getActiveTab();
    if (!content || !tab || tab.isStreaming) return;
    const convId = tab.conversationId; // 发起时捕获 — 防悬挂核心
    const useStream = chatDom.toggleStream.checked;
    // FIX-B：非流式在途守卫 — 同 tab 非流式请求在途时拒绝重复提交（双击只发一次真实请求；
    // 拒绝发生在清空输入之前，草稿保留）。流式提交不受影响（isStreaming 已拦并发）。
    if (!useStream && nonStreamingInFlight.has(convId)) return;
    // 该请求是否归属当前活动 tab（DOM 增量只给活动 tab；后台只累积缓存）
    const isActiveStream = () => getActiveTab()?.conversationId === convId;

    chatDom.chatInput.value = '';
    autoResizeInput(chatDom.chatInput);

    // 显示用户消息（DOM + 活动 tab 缓存同步）
    appendMessage('user', content);

    if (useStream) {
        // 流式模式 — 生命周期收口到 StreamSession 深模块（fullContent 累积 /
        // streamSettled 终态守卫 / revision 守卫 / 位置结算 / 失败位置感知写回）
        updateTab(convId, { phase: 'thinking', isStreaming: true });
        refreshSendButton();
        showThinkingIndicator();

        const session = createStreamSession({
            convId,
            getTab,
            updateTab,
            isActiveStream,
            renderMessages,
            refreshSendButton,
            refreshConversations,
        });

        let assistantDiv = null;
        let assistantContentDiv = null;

        const stream = chatStream(
            { conversation_id: convId, content },
            {
                onToken: (token) => {
                    // 累积 + per-tab 缓存同步在 StreamSession；返回累积全文供 DOM 渲染。
                    // null = 流已 settled，忽略。
                    const content = session.onToken(token);
                    if (content === null || !isActiveStream()) return;

                    // DOM 增量渲染保留 chat.js（气泡复用 / data-streaming-live / thinking）
                    // DOM 被 renderMessages 重建（切走再切回）→ 旧引用失效，重新定位本流气泡
                    if (assistantDiv && !assistantDiv.isConnected) {
                        assistantDiv = null;
                        assistantContentDiv = null;
                    }
                    if (!assistantDiv) {
                        // 复用 renderMessages 标记的 live 气泡（切回场景，避免重复气泡）；
                        // 无则新建（首个 token 替换 thinking 指示器）
                        const live = chatDom.chatMessages.querySelector('.message[data-streaming-live="1"]');
                        if (live) {
                            assistantDiv = live;
                            assistantContentDiv = live.querySelector('.message-content');
                        } else {
                            const thinking = chatDom.chatMessages.querySelector('.thinking-indicator');
                            if (thinking) thinking.remove();

                            assistantDiv = document.createElement('div');
                            assistantDiv.className = 'message assistant';
                            assistantDiv.appendChild(createAvatarElement('assistant'));
                            assistantContentDiv = document.createElement('div');
                            assistantContentDiv.className = 'message-content';
                            assistantDiv.appendChild(assistantContentDiv);
                            chatDom.chatMessages.appendChild(assistantDiv);
                        }
                    }
                    assistantContentDiv.innerHTML = renderMarkdown(content);
                    scrollToBottom();
                },
                onDone: (messageId) => session.onDone(messageId),
                onError: (err) => session.onError(err),
            }
        );
        updateTab(convId, { activeStream: stream });
        await stream.done;
    } else {
        // 非流式模式 — 置在途标记（FIX-B：双击连发守卫，finally 清除）
        nonStreamingInFlight.add(convId);
        showThinkingIndicator();
        try {
            chatDom.btnSend.disabled = true;
            const result = await messages.chat({
                conversation_id: convId,
                content,
            });
            // 非流式完成 — 统一结算入口 settleTurn（reload → merge → 写回 → 条件渲染，内部
            // try/catch 双分支：成功重载 / 失败位置感知写回兜底）。settleIndex=-1 无占位可结算；
            // content 供失败兜底写回（成功分支不使用）；防悬挂按发起时捕获的 convId 写回。
            const revision = getTab(convId)?.messages.length ?? 0;
            await settleTurn({
                convId, getTab, updateTab, isActive: isActiveStream, render: renderMessages,
                revision, settleIndex: -1, content: result.reply,
            });
        } catch (err) {
            appendMessage('system', `发送失败: ${err.message}`);
        } finally {
            // 完成/失败均清除在途标记 — 之后可再次发送
            nonStreamingInFlight.delete(convId);
            refreshSendButton();
        }
    }

    // 刷新对话列表（更新消息数量）
    await refreshConversations();
    // 首条 user 消息后后端已自动替换占位标题 → 同步头部标题（P3.5 标题联动）
    syncChatHeaderTitle();
}
