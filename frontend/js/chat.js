/**
 * Conver System — 聊天域
 *
 * 职责：
 *   1. 消息渲染（renderMessages / appendMessage / thinking / 复制 — 气泡构建统一走
 *      format.js 参数化工厂，本模块只留 DOM 挂载与事件绑定）
 *   2. 发送与流式交互（handleSend）
 *   3. 聊天头部深模块（F4 收口：renderChatHeader / startRename / 标题同步 / T3
 *      对话内模型切换 openModelSwitch；app.js 只留注入接线）
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
 * 不反向引用 app.js 私有函数 — 对话列表刷新（refreshConversations）与重命名后
 * 列表标题同步（syncConversationListTitle）经 setChatHooks 注入（options-object
 * 方言：按 key 合并、键非函数不覆盖、缺省默认 no-op 兜底）。
 */

import { chatStream, messages, conversations } from './api.js';
import { escapeHtml, autoResizeInput } from './utils.js';
import { providerDisplayName } from './utils/model-utils.js';
import { showExportDialog } from './components/export-dialog.js';
import { renderMarkdown } from './markdown.js';
import { buildMessagesHtml, messageBubbleHtml } from './format.js';
import { state } from './state.js';
import { getActiveTab, getTab, updateTab, onTabsChanged } from './tabs.js';
import { createStreamSession, settleTurn } from './stream-session.js';
import { renderErrorBar } from './error-bar.js';
import { iconHtml } from './icons.js';
import { showModelSelector } from './components/model-selector.js';
import { showConfirm } from './components/confirm-dialog.js';

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

/** 首启引导卡（T1 — 凭证协议 none 时空态渲染；「前往设置」按钮点击经注入
 *  navigateToSettings 钩子复用视图切换）。引导卡单一来源在聊天域（DOM 模块），
 *  conversation-activation.js showEmptyState 复用本分支（见 renderMessages）。 */
export const EMPTY_STATE_GUIDE_HTML = `
    <div class="empty-state empty-state-guide">
        <div class="empty-state-icon">
            <svg viewBox="0 0 22 22" fill="none">
                <path d="M3 5a2 2 0 012-2h12a2 2 0 012 2v8a2 2 0 01-2 2H8l-5 4V5z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
                <path d="M8 9h6M8 12h4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
            </svg>
        </div>
        <p class="empty-state-text">先配置 AI 接口，再开始对话</p>
        <p class="empty-state-hint">配置 API Key 后即可开始角色对话</p>
        <button class="empty-state-guide-btn">前往设置</button>
    </div>`;

// ── 注入钩子（app.js 注入，避免反向依赖 — options-object 方言：按 key 合并、
//    键非函数不覆盖、缺省默认 no-op 兜底）──
const hooks = {
    refreshConversations: () => {},
    syncConversationListTitle: () => {},
    navigateToSettings: () => {},
};

/**
 * 注入聊天域跨模块钩子（app.js 初始化时调用；按 key 合并，键非函数时不覆盖 —
 *   缺省默认 no-op 兜底，未接线时调用不抛错）
 * @param {object} h - 钩子集合（仅函数值键生效）
 * @param {Function} [h.refreshConversations] - 重新拉取对话列表（发送/停止后刷新消息数）
 * @param {Function} [h.syncConversationListTitle] - 重命名成功后同步对话列表项标题
 *   （只做 DOM 手术 — 更新匹配会话项 .title 文本，不重渲染列表）
 * @param {Function} [h.navigateToSettings] - 切到设置视图（T1 引导卡 / 错误条
 *   「前往设置」按钮点击调用；app.js 接线 switchView('settings')，复用视图切换）
 */
export function setChatHooks(h) {
    for (const [key, value] of Object.entries(h ?? {})) {
        if (typeof value === 'function') hooks[key] = value;
    }
}

// ── 非流式在途守卫（FIX-B）──
// 非流式请求在途的 conversationId 集合（per-tab 作用域）：Enter/按钮双击或重复提交
// 只发一次真实请求，完成/失败后经 finally 清除。流式连发语义不受影响 —— 流式由
// tab.isStreaming + StreamSession onDone 即时复位管理，本守卫只拦截非流式提交。
const nonStreamingInFlight = new Set();

/**
 * 清除已关闭 tab 的 stale 在途条目（F-2 自愈）
 * 在 handleSend / regenerateLastReply 入口调用，防止永不结算的请求导致
 * nonStreamingInFlight 永久锁定该会话的发送/重生成。
 */
function cleanupStaleInFlight() {
    // F-72：Array.from 快照迭代 — 迭代中删除 Set 元素虽在纯删除场景安全，但并发
    // re-add 时行为未定义；快照迭代保证确定语义。行为结果不变（清除已关闭会话 stale）。
    for (const convId of Array.from(nonStreamingInFlight)) {
        if (!getTab(convId)) nonStreamingInFlight.delete(convId);
    }
}
// tab 关闭即清理（closeTab 触发 onTabsChanged），覆盖「挂死请求 → 关 tab → 重开」后
// 下次发送时 getTab 已非空的场景（只靠入口自愈清不掉重开后的 stale 条目）
onTabsChanged(cleanupStaleInFlight);
const copyFeedbackTimers = new WeakMap();

// ══════════════════════════════════════════════════
// 消息渲染
// ══════════════════════════════════════════════════

/** T2 搜索定位：高亮气泡元素（模块级 — 二次定位/渲染重建时先清旧态，防串扰） */
let highlightEl = null;
/** T2 搜索定位：高亮清除定时器（约 3s） */
let highlightTimer = null;
/** T2 搜索定位：高亮持续时长（ms） */
const HIGHLIGHT_DURATION = 3000;

/**
 * 定位目标消息 + 应用 search-highlight + 约 3s 自动清除。
 * 与既有 scrollToBottom 互斥调用（调用方 messageId 存在时走本路径，跳过滚动到底），
 * 保证定位不被滚动到底覆盖。目标不存在（陈旧 messageId）→ 回落 scrollToBottom。
 * @param {number|string} messageId - 目标消息 id（匹配气泡 data-message-id）
 */
function locateAndHighlight(messageId) {
    if (highlightTimer) {
        clearTimeout(highlightTimer);
        highlightTimer = null;
    }
    if (highlightEl) {
        highlightEl.classList.remove('search-highlight');
        highlightEl = null;
    }
    // F-69：不再用 `[data-message-id="<raw>"]` 选择器裸插值（含引号/畸形 messageId 会抛
    // SyntaxError）—— 改为遍历气泡按 data-message-id 归一后精确比对。id 为 DB 数值
    // 不可达，此处为防御；无匹配回落 scrollToBottom 语义不变。
    const target = [...chatDom.chatMessages.children]
        .find((el) => el.dataset.messageId === String(messageId));
    if (!target) { scrollToBottom(); return; }
    target.scrollIntoView({ block: 'center' });
    target.classList.add('search-highlight');
    highlightEl = target;
    highlightTimer = setTimeout(() => {
        target.classList.remove('search-highlight');
        highlightTimer = null;
        highlightEl = null;
    }, HIGHLIGHT_DURATION);
}

/**
 * 渲染聊天区消息列表（读活动 tab 缓存）。
 * 空态判定收口（F6）；T2 搜索定位：传入 { messageId } 时渲染后定位目标消息到视口中央
 * + 短暂高亮，并跳过既有滚动到底（scrollToBottom 与定位互斥，定位不被覆盖）。
 * @param {object} [opts]
 * @param {number|string|null} [opts.messageId=null] - 目标消息 id（激活流程经
 *   conversation-activation 透传；无 id 时保持既有滚动到底语义）
 */
export function renderMessages({ messageId } = {}) {
    const container = chatDom.chatMessages;
    const tab = getActiveTab();
    // 空态判定收口（F6）：无活动 tab 或消息为空 → 同一 EMPTY_STATE_HTML（单一来源，
    // 替代消息列表模板旧空态文案；format.js 不再承担空态分支）。
    // T1 首启引导：凭证协议为 none 时渲染引导卡（「前往设置」按钮点击经注入
    // navigateToSettings 钩子复用视图切换；引导卡单一来源在聊天域）。EMPTY_STATE_HTML
    // 保留为非 none 态文案。
    // Array.isArray 守卫（TD-36）：字符串有 length 会误过空态判定，随后 .filter 抛 TypeError
    if (!tab || !Array.isArray(tab.messages) || !tab.messages.length) {
        const showGuide = state.credentialsProtocol === 'none';
        container.innerHTML = showGuide ? EMPTY_STATE_GUIDE_HTML : EMPTY_STATE_HTML;
        if (showGuide) {
            const guideBtn = container.querySelector('.empty-state-guide-btn');
            if (guideBtn) guideBtn.addEventListener('click', () => hooks.navigateToSettings());
        }
        return;
    }
    container.innerHTML = buildMessagesHtml(tab.messages, {
        characters: state.characters,
        currentCharacterId: tab.characterId,
        // T6 重生成：渲染消息列表时开启 — 仅末条已结算 assistant 气泡渲染重生成操作
        canRegenerate: true,
    });

    // 复制按钮事件 + 复制数据补写（FE-1 数据通道单一化：复制内容不经 HTML 属性 —
    // escapeHtml 不实体化文本节点双引号，嵌 data-content 会解析截断 + 产生属性注入面；
    // dataset 赋值天然安全。按钮顺序与缓存中非 system 消息一一对应，system 无按钮）
    const copyMessages = tab.messages.filter((m) => m.role !== 'system');
    container.querySelectorAll('.btn-copy-message').forEach((btn, i) => {
        btn.dataset.content = copyMessages[i]?.content ?? '';
        attachCopyButton(btn);
    });

    // T6 重生成按钮事件（末条 assistant 气泡；chat 域绑定 → regenerateLastReply）
    container.querySelectorAll('.btn-regenerate').forEach((btn) => {
        btn.addEventListener('click', () => regenerateLastReply());
    });

    // 缓存变体标记（stopped/error/streaming）由 buildMessagesHtml 经工厂透传还原 —
    // 切走再切回后停止/错误/流式语义保持一致（F1）；onToken 据此复用 live 气泡

    // T2 搜索定位：messageId 存在 → 定位 + 高亮，跳过滚动到底（互斥，定位不被覆盖）
    if (messageId !== undefined && messageId !== null) {
        locateAndHighlight(messageId);
    } else {
        scrollToBottom();
    }
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
    // 移除 thinking 指示器（F-59 会话隔离：只移除本会话（活动 tab）的指示器 —
    // 不误删其他会话在途指示器；无活动 tab 时回落移除全部 — 与既有行为一致）
    const activeConvId = getActiveTab()?.conversationId;
    if (activeConvId != null) {
        removeThinkingIndicator(container, activeConvId);
    } else {
        container.querySelectorAll('.thinking-indicator').forEach((el) => el.remove());
    }

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

/**
 * 移除容器内属于指定会话的 thinking 指示器（F-59 会话隔离 — 只删匹配 data-conv-id 的，
 * 不误删其他会话在途指示器）
 * @param {HTMLElement} container - 目标容器（消息区 DOM）
 * @param {string|number} convId - 会话身份（与指示器 data-conv-id 比对）
 */
function removeThinkingIndicator(container, convId) {
    container.querySelectorAll('.thinking-indicator').forEach((el) => {
        if (el.dataset.convId === String(convId)) el.remove();
    });
}

/**
 * 显示会话 thinking 指示器（F-59 会话隔离：指示器携带 data-conv-id 属性，
 * 创建前仅移除本会话已有的指示器，不触碰其他会话在途指示器）
 * @param {string|number} convId - 会话身份（写入指示器 data-conv-id 属性）
 */
function showThinkingIndicator(convId) {
    const container = chatDom.chatMessages;
    // 移除本会话已有 thinking（防重复创建 — 只针对同会话，F-59 会话隔离）
    removeThinkingIndicator(container, convId);

    const div = document.createElement('div');
    div.className = 'thinking-indicator';
    div.dataset.convId = String(convId);
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
        <button class="chat-model-badge" id="chat-model-badge" title="切换模型">${escapeHtml(providerLabel)} · ${escapeHtml(modelLabel)}</button>
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
    // T3 模型切换：模型徽标 → 打开模型选择器（预选当前 provider/model）
    const badge = chatDom.chatHeader.querySelector('#chat-model-badge');
    if (badge) {
        badge.addEventListener('click', () => openModelSwitch(conv));
    }
}

/**
 * 会话模型切换前判定凭证是否可能不可用（需要确认提示）。
 * T3 语义（spec）：凭证协议三态为唯一事实来源 — none（无任何 Key）恒提示；
 * claude（仅 Claude Key）且目标 provider 非 claude（OpenAI 兼容族）→ 提示；
 * openai（仅 OpenAI 兼容 Key）且目标 provider 为 claude → 提示（F-54 对称化）；
 * openai 态切向其他 Provider 无提示。返回提示原因（'none' | 'claude' | 'openai' |
 * 'unknown'），无需提示返回 null。
 * F-71：未知/异常 credentialsProtocol 由 fail-open（return null 静默放行）改为
 * fail-closed —— default 返回 'unknown' 提示原因，交由 openModelSwitch 弹不可用提示，
 * 不再无提示静默保存。
 * @param {string} selectedProvider - 目标 provider key
 * @returns {'none'|'claude'|'openai'|'unknown'|null}
 */
function credentialWarnReason(selectedProvider) {
    switch (state.credentialsProtocol) {
        case 'none':
            return 'none';
        case 'claude':
            return selectedProvider !== 'claude' ? 'claude' : null;
        case 'openai':
            return selectedProvider === 'claude' ? 'openai' : null;
        default:
            // F-71 fail-closed：未知协议 → 返回提示原因（不静默放行保存）
            return 'unknown';
    }
}

/**
 * 对话内模型切换（T3 — .chat-model-badge 点击入口；P3 前部）：
 *   1. 打开模型选择器并预选当前 conv 的 provider/model（showModelSelector 扩展签名）
 *   2. 凭证不可用（none 恒提示 / claude 切非 claude / openai 切 claude）→ showConfirm 确认提示但允许保存
 *   3. 确认后 conversations.update(convId, { model_provider, model_name })（PUT 已存在）
 *   4. 保存成功 → 就地更新 state.conversations（头部/列表渲染单一事实来源）+
 *      重渲染头部徽标（活动 tab 同步）+ 经注入钩子 refreshConversations 同步对话列表
 *      （刷新失败独立记录，不影响已成功的保存 — F-53 语义分离）
 *
 * 切换只影响后续发送：在途流式由后端在请求时捕获 provider/model，天然免疫 ——
 * 本函数不触碰任何流式句柄（不 abort / 不终止），见 chat.test.js 在途流式场景。
 * @param {object} conv - 对话对象（state.conversations 中的引用或等价物）
 */
export async function openModelSwitch(conv) {
    if (!conv) return;
    const selection = await showModelSelector(conv.title || '', {
        preselected: { provider: conv.model_provider, model: conv.model_name },
        title: '切换模型',
    });
    if (!selection) return; // 用户取消

    // 凭证不可用确认（none 恒提示 / claude 切非 claude / openai 切 claude）— 确认后仍允许保存
    const warnReason = credentialWarnReason(selection.provider);
    if (warnReason) {
        const confirmed = await showConfirm({
            title: '模型可能不可用',
            message: warnReason === 'none'
                ? '尚未配置 API Key，发送消息可能失败。仍要切换模型吗？'
                : warnReason === 'openai'
                    ? '当前仅配置了 OpenAI 兼容 Key，所选 Claude Provider 可能不可用。仍要切换吗？'
                    : warnReason === 'unknown'
                        ? '凭证协议状态未知，所选模型可能不可用。仍要切换吗？'
                        : '当前仅配置了 Claude Key，所选 Provider 可能不可用。仍要切换吗？',
            detail: `目标：${selection.model}（${selection.provider}）`,
            confirmText: '仍要切换',
            cancelText: '取消',
        });
        if (!confirmed) return; // 确认取消 → 不保存
    }

    // F-70：conversations.update（PUT）为唯一「保存」步骤 — PUT 成功即保存成功。
    // state 就地更新与 renderChatHeader 移出 save try（独立 try）—— 二者抛错仅记录
    // 更新侧日志（「更新失败」），不归因「切换模型失败」，也不阻断后续列表刷新。
    try {
        await conversations.update(conv.id, {
            model_provider: selection.provider,
            model_name: selection.model,
        });
    } catch (err) {
        console.error('切换模型失败:', err);
        return; // 保存失败 → 不继续列表刷新
    }
    // 保存成功 → 就地更新 state.conversations（单一事实来源 — 头部徽标 / 对话列表渲染共用）
    // + 同步聊天头部徽标（重渲染基于 state，活动 tab 数据同步）；独立 try：更新侧失败
    // 仅记日志，不影响「保存成功」语义，也不阻断 refreshConversations。
    try {
        const stored = state.conversations.find((c) => c.id === conv.id);
        if (stored) {
            stored.model_provider = selection.provider;
            stored.model_name = selection.model;
        }
        renderChatHeader(conv.id);
    } catch (err) {
        console.error('更新失败:', err);
    }
    // 对话列表同步（F-53 语义分离：独立 try/catch — 刷新失败记录独立日志，不干扰已成功的保存）
    try {
        await hooks.refreshConversations();
    } catch (err) {
        console.error('刷新对话列表失败:', err);
    }
}

/**
 * 对话重命名 — 双击标题原地编辑
 * 保存成功后：更新对话对象 / tab 标题（P6.5-4 标题联动）+ 经注入钩子同步对话列表标题
 * @param {object} conv - 对话对象
 */
export function startRename(conv) {
    // TD-37 守卫：无对话对象（畸形调用）→ 静默返回（内部调用点恒传非空，防御性修复）
    if (!conv) return;
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
            hooks.syncConversationListTitle(conv.id, newTitle);
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

// ── 错误条渲染（T1 — 发送失败统一经 error-bar 深模块承载，不写进消息列表）──

/**
 * 错误条挂载容器：取 #chat-messages 的父级（.chat-main）— 不随 renderMessages /
 * appendMessage 的 innerHTML 重建而消失；父级缺失（畸形 DOM）回落 document.body。
 * @returns {HTMLElement}
 */
function errorBarContainer() {
    return chatDom.chatMessages?.parentElement ?? document.body;
}

/**
 * 渲染发送失败错误条（非流式 catch / 流式 onError 上抛 / 重生成 catch 共用）。
 * 文案/协议分流与「前往设置」导航收口在 error-bar.js 深模块（error-bar 单一来源）。
 * 会话身份（conversationId）由调用上下文捕获并透传 — 错误条按会话隔离
 * （F-50：同会话幂等替换、跨会话并存，并发多 tab 出错互不覆盖）。
 * 所有调用点均在「发起时已捕获 convId」作用域内，故恒有会话身份可传。
 * @param {Error|{message?: string}|null} err - 原始错误
 * @param {string} fallback - 错误信息缺失时的兜底文案
 * @param {string|number|null|undefined} conversationId - 会话身份（发起时捕获，
 *   透传给 renderErrorBar 做数据-会话寻址）
 */
function renderSendError(err, fallback, conversationId) {
    renderErrorBar({
        container: errorBarContainer(),
        message: (err && err.message) || fallback,
        protocol: state.credentialsProtocol,
        onNavigateSettings: hooks.navigateToSettings,
        conversationId,
    });
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
    // FIX-B + F-57：在途守卫 — 同会话非流式请求 / 重生成在途时拒绝任何提交（非流式发送与
    // 重生成共用此集合：重生成进行中 isStreaming 未置位，若流式发送不查本集合，同一会话将
    // 并发双请求，违反「同对话互斥」承诺。统一在此拦截；不复用 isStreaming，避免发送按钮
    // 误变「停止」态）。流式自身在途由 tab.isStreaming 拦并发（发送按钮为「停止」态）。
    // 拒绝发生在清空输入之前，草稿保留。
    cleanupStaleInFlight();
    if (nonStreamingInFlight.has(convId)) return;
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
        showThinkingIndicator(convId);

        const session = createStreamSession({
            convId,
            getTab,
            updateTab,
            isActiveStream,
            renderMessages,
            refreshSendButton,
            refreshConversations: hooks.refreshConversations,
            onError: (err) => renderSendError(err, '流式回复失败', convId),
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
                            // F-59 会话隔离第三路径（W4 审核 F-1）：只移除本会话的 thinking，
                            // 不误删其他会话在途指示器（双指示器共存态由 F-59 测试确立为合法）
                            removeThinkingIndicator(chatDom.chatMessages, convId);

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
        showThinkingIndicator(convId);
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
            // T1：发送失败不再写入 system 失败消息 — 渲染独立错误条（可关闭 /
            // 约 8s 自动消失 /「前往设置」；none 态文案引导配 Key）
            renderSendError(err, '发送失败', convId);
        } finally {
            // 完成/失败均清除在途标记 — 之后可再次发送
            nonStreamingInFlight.delete(convId);
            refreshSendButton();
        }
    }

    // 刷新对话列表（更新消息数量）
    await hooks.refreshConversations();
    // 首条 user 消息后后端已自动替换占位标题 → 同步头部标题（P3.5 标题联动）
    syncChatHeaderTitle();
}

// ── 重生成（T6 — 末条 assistant 气泡重生成，MVP 非流式）──

/**
 * 末条 AI 回复重生成（T6 — 末条 assistant 气泡「重生成」按钮触发，MVP 非流式）
 *
 * 调 `conversations.regenerate(convId)`（无 message_id = 后端缺省取末条 assistant，
 * 时间线截断后按既有非流式路径重发），成功后经统一结算入口 `settleTurn` 从服务端
 * 重载消息列表并渲染新回复 —— fresh 整体替换使**新消息携带服务端 message_id 进入
 * tab 缓存**（W2 增量审核 #2；失败兜底位置感知写回同样携带 messageId 透传）。
 * F-58：发起前捕获被顶替旧回复的服务端 id（lastAssistantId）随 `settleTurn` 一并传递
 * —— 失败兜底按身份原位替换（顶替语义，不尾部追加）；本地缓存无旧 id 时回落既有
 * 位置/追加路径。
 * 失败走既有错误条通道（`renderSendError` — 与 `messages.chat` 同一 catch 路径，
 * 不各自为政），**不写进消息列表**。
 *
 * 在途守卫与 `handleSend` 非流式一致（共享同一 `nonStreamingInFlight` 集合 ——
 * 同对话的非流式发送/重生成互斥，重复触发只发一次真实请求）；进行中状态 = 末条
 * assistant 气泡重生成按钮禁用 + thinking 指示器（DOM 手术，不动缓存 — 失败语义
 * 「不写消息列表」要求缓存保持原状）。
 * 防悬挂：只接受发起时捕获的 convId + isActive 活动归属判定，不读「当前活动」。
 */
export async function regenerateLastReply() {
    const tab = getActiveTab();
    if (!tab || tab.isStreaming) return;
    const convId = tab.conversationId; // 发起时捕获 — 防悬挂核心
    const isActive = () => getActiveTab()?.conversationId === convId;
    // FIX-B 同源在途守卫：非流式发送 / 重生成共用 — 同一对话重复触发只发一次真实请求
    cleanupStaleInFlight();
    if (nonStreamingInFlight.has(convId)) return;

    // F-58：发起前捕获被顶替旧回复（末条 assistant 消息）的服务端 id — 失败兜底按身份原位
    // 替换，不尾部追加。无 id（本地暂存消息）回落既有追加语义。
    const lastAssistant = Array.isArray(tab.messages)
        ? [...tab.messages].reverse().find((m) => m?.role === 'assistant')
        : null;
    const replaceId = lastAssistant?.id ?? null;

    nonStreamingInFlight.add(convId);

    // 进行中状态：末条 assistant 气泡重生成按钮禁用 + thinking 指示器（不动缓存 —
    // 失败语义「不写消息列表」要求缓存保持原状，成功由 settleTurn 重建 DOM）
    const assistantBubbles = chatDom.chatMessages.querySelectorAll('.message.assistant');
    const regenButton = assistantBubbles[assistantBubbles.length - 1]?.querySelector('.btn-regenerate') ?? null;
    if (regenButton) regenButton.disabled = true;
    showThinkingIndicator(convId);

    try {
        const result = await conversations.regenerate(convId);
        // 成功 — 统一结算入口 settleTurn：从服务端重载截断后的新时间线（含角色开场白
        //   greeting 与新回复 id）→ fresh 整体替换 tab 缓存 + 活动渲染。messageId 透传
        //   服务端新消息 id（W2 增量审核 #2：新消息带服务端 id 进缓存 / 失败兜底写回同样携带）
        const revision = getTab(convId)?.messages.length ?? 0;
        await settleTurn({
            convId, getTab, updateTab, isActive, render: renderMessages,
            revision, settleIndex: -1, messageId: result.message_id, content: result.reply,
            replaceId,  // F-58:被顶替旧回复身份 — 失败兜底按此 id 原位替换(不尾部追加)
        });
    } catch (err) {
        // 失败 — 与 messages.chat 同一错误通道（T1 错误条）：不写进消息列表
        renderSendError(err, '重生成失败', convId);
    } finally {
        // 完成/失败均清除在途标记；恢复按钮与 thinking（成功路径 settle 已重建 DOM —
        //   旧引用 isConnected 兜底跳过；失败路径复原）。F-59 会话隔离：只移除本会话
        //   （convId）的 thinking 指示器 — 不误删其他会话在途指示器
        nonStreamingInFlight.delete(convId);
        if (regenButton && regenButton.isConnected) regenButton.disabled = false;
        removeThinkingIndicator(chatDom.chatMessages, convId);
        refreshSendButton();
    }

    // 刷新对话列表（更新消息数量）
    await hooks.refreshConversations();
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 chat.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'chatDom',
    'EMPTY_STATE_HTML',
    'EMPTY_STATE_GUIDE_HTML',
    'EMPTY_HEADER_HTML',
    'setChatHooks',
    'renderMessages',
    'refreshSendButton',
    'renderChatHeader',
    'startRename',
    'openModelSwitch',
    'handleSend',
    'regenerateLastReply',
];
