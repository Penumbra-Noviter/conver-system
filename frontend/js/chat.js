/**
 * Conver System — 聊天域
 *
 * 职责：
 *   1. 消息渲染（renderMessages / appendMessage / thinking / 头像 / 复制）
 *   2. 发送与流式交互（handleSend）
 *   3. 聊天域 DOM 引用（chatDom）
 *
 * 依赖方向：chat.js → state.js / api.js / utils.js；app.js → chat.js
 * 不反向引用 app.js 私有函数 — 对话列表刷新通过 setConversationsRefresher 注入。
 */

import { chatStream, messages } from './api.js';
import { escapeHtml, renderMarkdown } from './utils.js';
import { buildMessagesHtml, assistantAvatarHtml, userAvatarHtml } from './format.js';
import { state } from './state.js';

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

// ── 对话列表刷新钩子（由 app.js 注入，避免反向依赖）──
let refreshConversations = () => {};
export function setConversationsRefresher(fn) {
    refreshConversations = typeof fn === 'function' ? fn : () => {};
}

// ══════════════════════════════════════════════════
// 消息渲染
// ══════════════════════════════════════════════════

export function renderMessages() {
    const container = chatDom.chatMessages;
    container.innerHTML = buildMessagesHtml(state.messages, {
        characters: state.characters,
        currentCharacterId: state.currentCharacterId,
    });

    // 复制按钮事件
    container.querySelectorAll('.btn-copy-message').forEach(btn => {
        attachCopyButton(btn, btn.dataset.content);
    });

    scrollToBottom();
}

function appendMessage(role, content) {
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
    copyBtn.textContent = '📋';
    copyBtn.dataset.content = content;
    attachCopyButton(copyBtn, content);
    div.appendChild(copyBtn);

    container.appendChild(div);
    scrollToBottom();
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
 * 获取当前角色的头像 HTML
 * @returns {string}
 */
function getAssistantAvatarHtml() {
    return assistantAvatarHtml(state.characters, state.currentCharacterId);
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
 * 为消息复制按钮绑定点击事件（复制内容到剪贴板并给出 ✅/❌ 反馈）
 * @param {HTMLButtonElement} btn - 复制按钮元素
 * @param {string} content - 要复制的消息内容
 */
function attachCopyButton(btn, content) {
    btn.addEventListener('click', async (e) => {
        e.stopPropagation();
        try {
            await navigator.clipboard.writeText(content);
            btn.textContent = '✅';
            btn.classList.add('copied');
            setTimeout(() => {
                btn.textContent = '📋';
                btn.classList.remove('copied');
            }, 1500);
        } catch {
            btn.textContent = '❌';
        }
    });
}

// ── 发送消息 ──

/**
 * 发送按钮两态 — 流式生成中变身停止按钮（P3.5）
 * @param {'send'|'stop'} mode - 'stop': ⏹ 停止生成；'send': ➤ 发送
 */
function setSendButtonState(mode) {
    const btn = chatDom.btnSend;
    if (mode === 'stop') {
        btn.disabled = false;
        btn.textContent = '⏹';
        btn.title = '停止生成';
        btn.classList.add('btn-stop');
    } else {
        btn.disabled = false;
        btn.textContent = '➤';
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
 * 后端保存首条 user 消息后自动替换占位标题，发送完成后据此刷新头部标题。
 */
function syncChatHeaderTitle() {
    const titleEl = chatDom.chatHeader.querySelector('#chat-title-text');
    if (!titleEl || !state.currentConversationId) return;
    const conv = state.conversations.find((c) => c.id === state.currentConversationId);
    if (conv) titleEl.textContent = conv.title;
}

export async function handleSend() {
    const content = chatDom.chatInput.value.trim();
    if (!content || !state.currentConversationId || state.isStreaming) return;

    chatDom.chatInput.value = '';
    chatDom.chatInput.style.height = 'auto';

    // 显示用户消息
    appendMessage('user', content);

    const useStream = chatDom.toggleStream.checked;

    if (useStream) {
        // 流式模式
        state.isStreaming = true;
        setSendButtonState('stop');
        showThinkingIndicator();

        let fullContent = '';
        let assistantDiv = null;
        let assistantContentDiv = null;
        const isAbortError = (err) => err?.name === 'AbortError';

        const stream = chatStream(
            { conversation_id: state.currentConversationId, content },
            {
                onToken: (token) => {
                    // 第一个 token 到达时，替换 thinking 指示器为真正的 assistant 气泡
                    if (!assistantDiv) {
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
                    fullContent += token;
                    assistantContentDiv.innerHTML = renderMarkdown(fullContent);
                    scrollToBottom();
                },
                onDone: (messageId) => {
                    state.isStreaming = false;
                    state.activeStream = null;
                    setSendButtonState('send');
                    if (messageId) {
                        // 正常完成 — 保存完整消息
                        state.messages.push(
                            { role: 'user', content },
                            { role: 'assistant', content: fullContent, id: messageId }
                        );
                    } else if (fullContent) {
                        // 流中断但已有部分内容
                        state.messages.push(
                            { role: 'user', content },
                            { role: 'assistant', content: fullContent }
                        );
                    }
                    // 刷新对话列表（更新消息数量）
                    refreshConversations();
                },
                onError: (err) => {
                    state.isStreaming = false;
                    state.activeStream = null;
                    setSendButtonState('send');
                    // 移除 thinking 指示器（如果还在）
                    const thinking = chatDom.chatMessages.querySelector('.thinking-indicator');
                    if (thinking) thinking.remove();

                    if (isAbortError(err)) {
                        // 用户主动停止 — 语义是「已停止」而非错误；后端已保存部分内容
                        if (fullContent && assistantContentDiv) {
                            assistantContentDiv.innerHTML = renderMarkdown(fullContent);
                        }
                        if (assistantDiv) {
                            markStopped(assistantDiv);
                        }
                        state.messages.push(
                            { role: 'user', content },
                            { role: 'assistant', content: fullContent }
                        );
                    } else {
                        // 错误发生 — 如果还没有 assistant 气泡，创建一个显示错误
                        if (!assistantDiv) {
                            assistantDiv = document.createElement('div');
                            assistantDiv.className = 'message assistant';
                            assistantDiv.appendChild(createAvatarElement('assistant'));
                            assistantContentDiv = document.createElement('div');
                            assistantContentDiv.className = 'message-content';
                            assistantDiv.appendChild(assistantContentDiv);
                            chatDom.chatMessages.appendChild(assistantDiv);
                        }
                        assistantContentDiv.textContent = `[错误] ${err.message}`;
                    }
                    // 错误/停止时也刷新对话列表（避免计数卡死）
                    refreshConversations();
                },
            }
        );
        state.activeStream = stream;
        await stream.done;
    } else {
        // 非流式模式
        showThinkingIndicator();
        try {
            chatDom.btnSend.disabled = true;
            const result = await messages.chat({
                conversation_id: state.currentConversationId,
                content,
            });
            appendMessage('assistant', result.reply);
            state.messages.push(
                { role: 'user', content },
                { role: 'assistant', content: result.reply }
            );
        } catch (err) {
            appendMessage('system', `发送失败: ${err.message}`);
        } finally {
            chatDom.btnSend.disabled = false;
        }
    }

    // 刷新对话列表（更新消息数量）
    await refreshConversations();
    // 首条 user 消息后后端已自动替换占位标题 → 同步头部标题（P3.5 标题联动）
    syncChatHeaderTitle();
}
