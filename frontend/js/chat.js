/**
 * Conver System — 聊天域
 *
 * 职责：
 *   1. 消息渲染（renderMessages / appendMessage / thinking / 复制 — 气泡构建统一走
 *      format.js 参数化工厂，本模块只留 DOM 挂载与事件绑定）
 *   2. 发送与流式交互（handleSend）
 *   3. 聊天头部深模块（F4 收口：renderChatHeader / startRename / 标题同步；
 *      app.js 只留注入接线）
 *   4. 聊天域 DOM 引用（chatDom）
 *   5. 发送按钮两态（send/stop）— 由活动 tab 的 isStreaming 派生（refreshSendButton）
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
 * 依赖方向：chat.js → state.js / api.js / utils.js / format.js / tabs.js /
 *   stream-session.js / components/export-dialog.js；
 *   app.js → chat.js
 * 不反向引用 app.js 私有函数 — 对话列表刷新通过 setConversationsRefresher 注入，
 * 重命名后的列表标题同步经 setConversationListTitleSyncer 注入。
 */

import { chatStream, messages, conversations } from './api.js';
import { escapeHtml, autoResizeInput } from './utils.js';
import { providerDisplayName } from './utils/model-utils.js';
import { showExportDialog } from './components/export-dialog.js';
import { renderMarkdown } from './markdown.js';
import { buildMessagesHtml, messageBubbleHtml } from './format.js';
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

/** 无会话时的头部空态文案（单一事实来源 — chat.js renderChatHeader / 激活模块 showEmptyState 复用，禁止内联重复） */
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
    // 空态判定收口（F6）：无活动 tab 或消息为空 → 同一 EMPTY_STATE_HTML（单一来源，
    // 替代消息列表模板旧空态文案；format.js 不再承担空态分支）
    if (!tab || !tab.messages?.length) {
        container.innerHTML = EMPTY_STATE_HTML;
        return;
    }
    container.innerHTML = buildMessagesHtml(tab.messages, {
        characters: state.characters,
        currentCharacterId: tab.characterId,
    });

    // 复制按钮事件 + 复制数据补写（FE-1 数据通道单一化：复制内容不经 HTML 属性 —
    // escapeHtml 不实体化文本节点双引号，嵌 data-content 会解析截断 + 产生属性注入面；
    // dataset 赋值天然安全。按钮顺序与缓存中非 system 消息一一对应，system 无按钮）
    const copyMessages = tab.messages.filter((m) => m.role !== 'system');
    container.querySelectorAll('.btn-copy-message').forEach((btn, i) => {
        btn.dataset.content = copyMessages[i]?.content ?? '';
        attachCopyButton(btn);
    });

    // 缓存变体标记（stopped/error/streaming）由 buildMessagesHtml 经工厂透传还原 —
    // 切走再切回后停止/错误/流式语义保持一致（F1）；onToken 据此复用 live 气泡

    scrollToBottom();
}

/**
 * DOM 追加消息气泡；user/assistant 同步写入活动 tab 缓存（system 仅 DOM 提示，不落 tab 缓存）
 * 气泡构建统一走 format.js 参数化工厂（F1 — 三路径收口；system 无头像 + 无复制按钮）
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

    container.insertAdjacentHTML('beforeend', messageBubbleHtml(role, content, {
        characters: state.characters,
        currentCharacterId: getActiveTab()?.characterId ?? null,
        stopped: meta.stopped,
        error: meta.error,
    }));
    const bubble = container.lastElementChild;
    const copyBtn = bubble.querySelector('.btn-copy-message');
    if (copyBtn) {
        // FE-1：复制内容经 dataset 赋值（天然安全），不嵌 HTML 属性（见 renderMessages 注释）
        copyBtn.dataset.content = content;
        attachCopyButton(copyBtn);
    }

    scrollToBottom();

    // 缓存同步（仅活动 tab 的 DOM 追加会经过本函数；system 不落缓存）
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

// ── 复制按钮（气泡构建在 format.js 工厂；本处只做事件绑定）──

/**
 * 为消息复制按钮绑定点击事件（复制当前 data-content 到剪贴板并给出图标反馈）
 * 点击时读取 btn.dataset.content —— 流式气泡逐 token 更新 data-content 后
 * 复制行为仍正确（F1：骨架即含复制按钮，token 更新同步数据属性）
 * @param {HTMLButtonElement} btn - 复制按钮元素
 */
function attachCopyButton(btn) {
    btn.addEventListener('click', async (e) => {
        e.stopPropagation();
        const pendingTimer = copyFeedbackTimers.get(btn);
        if (pendingTimer) clearTimeout(pendingTimer);

        let feedbackIcon = 'check';
        try {
            await navigator.clipboard.writeText(btn.dataset.content ?? '');
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

// ══════════════════════════════════════════════════
// 聊天头部深模块（F4 收口：渲染 / 重命名 / 标题同步 — 单一模块持有，
// app.js 只留注入接线；会话列表标题更新经注入钩子，避免反向依赖）
// ══════════════════════════════════════════════════

/** 会话列表标题同步钩子（app.js 注入 — 重命名成功后手动更新列表项标题） */
let syncConversationListTitle = () => {};
export function setConversationListTitleSyncer(fn) {
    syncConversationListTitle = typeof fn === 'function' ? fn : () => {};
}

/**
 * 渲染聊天头部（标题 + 模型 badge + 导出/列表切换按钮 + 双击重命名绑定）
 * 按活动 tab 派生；对话数据以 conversations 列表为准（持久事实来源）
 * @param {number|string} conversationId - 活动 tab 的会话 id
 */
export function renderChatHeader(conversationId) {
    const conv = state.conversations.find((c) => c.id === conversationId);
    if (!conv) {
        chatDom.chatHeader.innerHTML = EMPTY_HEADER_HTML;
        return;
    }
    const modelLabel = conv.model_name || '';
    const providerLabel = providerDisplayName(state.models, conv.model_provider);
    chatDom.chatHeader.innerHTML = `
        <button class="btn-toggle-conv-list" id="btn-toggle-conv-list" title="切换对话列表">${iconHtml('menu')}</button>
        <span class="chat-title" id="chat-title-text" title="双击重命名">${escapeHtml(conv.title)}</span>
        <span class="chat-model-badge">${escapeHtml(providerLabel)} · ${escapeHtml(modelLabel)}</span>
        <button class="btn-icon btn-export-conv" id="btn-export-conv" title="导出对话">${iconHtml('download')}</button>
    `;
    // 双击标题重命名
    const titleEl = chatDom.chatHeader.querySelector('#chat-title-text');
    titleEl.addEventListener('dblclick', () => startRename(conv));
    // 移动端切换对话列表
    const toggleBtn = chatDom.chatHeader.querySelector('#btn-toggle-conv-list');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', () => {
            const sidebar = document.querySelector('.chat-sidebar');
            if (sidebar) {
                sidebar.classList.toggle('mobile-expanded');
            }
        });
    }
    // 导出按钮
    const exportBtn = chatDom.chatHeader.querySelector('#btn-export-conv');
    if (exportBtn) {
        exportBtn.addEventListener('click', () => {
            showExportDialog(conversationId);
        });
    }
}

/**
 * 对话重命名 — 双击标题原地编辑
 * 保存成功后：更新对话对象 / tab 标题（P6.5-4 标题联动）+ 经注入钩子同步对话列表标题
 * @param {object} conv - 对话对象
 */
export function startRename(conv) {
    const titleEl = chatDom.chatHeader.querySelector('#chat-title-text');
    if (!titleEl) return;

    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'chat-title-input';
    input.value = conv.title;
    input.maxLength = 200;

    titleEl.replaceWith(input);
    input.focus();
    input.select();

    async function save() {
        const newTitle = input.value.trim() || conv.title;
        try {
            await conversations.update(conv.id, { title: newTitle });
            conv.title = newTitle;
            // P6.5-4 标题联动：同步对应 tab 的 title（tab 条随动；onTabsChanged 驱动重渲染）
            updateTab(conv.id, { title: newTitle });
            // 会话列表标题更新经注入钩子（app.js 接线 — 避免反向依赖）
            syncConversationListTitle(conv.id, newTitle);
        } catch (err) {
            console.error('重命名失败:', err);
        }
        // 恢复标题显示
        const span = document.createElement('span');
        span.className = 'chat-title';
        span.id = 'chat-title-text';
        span.textContent = newTitle;
        span.title = '双击重命名';
        input.replaceWith(span);
        span.addEventListener('dblclick', () => startRename(conv));
    }

    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            input.blur();
        }
        if (e.key === 'Escape') {
            input.value = conv.title;
            input.blur();
        }
    });

    input.addEventListener('blur', save);
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
        let assistantCopyBtn = null;

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
                        assistantCopyBtn = null;
                    }
                    if (!assistantDiv) {
                        // 复用 renderMessages 标记的 live 气泡（切回场景，避免重复气泡）；
                        // 无则新建（首个 token 替换 thinking 指示器）— 骨架统一走工厂，
                        // 即含复制按钮（F1：流式气泡骨架即有复制按钮）
                        const live = chatDom.chatMessages.querySelector('.message[data-streaming-live="1"]');
                        if (live) {
                            assistantDiv = live;
                            assistantContentDiv = live.querySelector('.message-content');
                            assistantCopyBtn = live.querySelector('.btn-copy-message');
                        } else {
                            const thinking = chatDom.chatMessages.querySelector('.thinking-indicator');
                            if (thinking) thinking.remove();

                            chatDom.chatMessages.insertAdjacentHTML('beforeend', messageBubbleHtml('assistant', content, {
                                streaming: true,
                                characters: state.characters,
                                currentCharacterId: getActiveTab()?.characterId ?? null,
                            }));
                            assistantDiv = chatDom.chatMessages.lastElementChild;
                            assistantContentDiv = assistantDiv.querySelector('.message-content');
                            assistantCopyBtn = assistantDiv.querySelector('.btn-copy-message');
                            if (assistantCopyBtn) attachCopyButton(assistantCopyBtn);
                        }
                    }
                    assistantContentDiv.innerHTML = renderMarkdown(content);
                    // F1：流式 token 更新同步复制数据属性（点击时读 dataset.content）
                    if (assistantCopyBtn) assistantCopyBtn.dataset.content = content;
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
