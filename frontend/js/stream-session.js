/**
 * Conver System — 流式会话深模块(StreamSession,零 DOM)
 *
 * 职责:
 *   1. 一条流式请求的完整生命周期状态机:fullContent 累积、streamSettled 终态守卫、
 *      完成/错误/停止按发起时捕获的 conversationId 写回(防悬挂)
 *   2. 完成后的消息列表重载合并(mergeFreshList 纯函数三分支):
 *      fresh 整体替换 / stale 仅位置结算 / 失败按位置追加(不清并发流占位 — 根治 R2)
 *
 * P6.5 语义(chat.js 拆分后行为保持):
 *   - onToken:活动归属与 DOM 增量渲染(气泡复用 / data-streaming-live / thinking)
 *     保留 chat.js — 本模块 onToken 返回累积全文,由调用方决定是否渲染
 *   - onDone / onError 一律按发起时捕获的 conversationId 写回,绝不读「当前活动」;
 *     发起 tab 可能已被关闭 → getTab 缺失时 no-op(updateTab 幂等 no-op 兜底)
 *   - streamSettled 终态守卫:错误帧后 SSE 流关闭会再触发 onDone(null),必须拦截,
 *     防止 phase 'done' 覆盖错误写回;settled 后 onToken/onDone/onError 一律忽略
 *   - 停止(AbortError)写回 phase 'error'(警示标记;气泡保持「已停止」语义),
 *     正常完成写回 phase 'done';refreshSendButton 在写回后立即调用（消除停止态到发送态的
 *     UX 窗口;连发依赖此即时复位）
 *   - settleIndex:发起时刻尾消息位置(本流 streaming 占位位置),幂等 — 该位置仍
 *     streaming 才结算(stale 分支);失败写回改用 anchor(本流 user 消息对象引用,
 *     indexOf 定位不受插入漂移影响 — 回复永远插在自己的 user 之后,时间序不漂移)
 *     失败路径按位置写回本流内容,不清并发流占位
 *   - 占位归属代理:settleIndex 以「发起时刻尾位置」代理本流占位。正常时序下
 *     该位置即本流占位;极端多连发下本流占位可能已被更新流的 token 替换(位置
 *     失配 → 不结算/按位置插入,消息不丢失、并发占位保持)。消息不携带流身份,
 *     位置匹配是协议边界(与 FIX-A 同源决策)
 *
 * 依赖方向:stream-session.js → api.js(messages.list);chat.js → stream-session.js
 * 零 DOM:本模块不触碰 document;DOM 逻辑由 chat.js 经注入回调与 onToken 返回值驱动。
 */

import { messages } from './api.js';

// ══════════════════════════════════════════════════
// 内部工具
// ══════════════════════════════════════════════════

/**
 * 位置感知写回本流消息:移除本流 streaming 占位(幂等),把最终消息插入到发起位置。
 * 幂等规则:
 *   - 缓存已含同 id 消息(被并发流的 fresh 替换结算)→ 不动
 *   - anchor(本流 user 消息对象引用):位置 anchor 之后插入本流回复 — anchor 用
 *     对象引用 + indexOf 定位,插入/删除导致的索引漂移不影响定位(根治 R2,
 *     不清并发流占位;user 消息本身不被删除,引用永有效)
 * @param {object} tab - 会话 tab(getTab 返回的对象)
 * @param {object|null} anchor - 本流 user 消息对象引用;无 user 消息为 null(追加尾部)
 * @param {object} message - 要写回的消息(role: 'assistant', content, id?)
 * @returns {{messages: Array, render: boolean}} 新缓存与是否需活动渲染
 */
function settleByPosition(tab, anchor, message) {
    const next = [...tab.messages];
    // 幂等:缓存已含本流消息(带 id 匹配)— 已被并发流的 fresh 替换结算,不重复插入
    if (message.id != null && next.some((m) => m.id === message.id)) {
        return { messages: tab.messages, render: false };
    }
    const anchorIdx = anchor ? next.indexOf(anchor) : -1;
    const insertAt = anchorIdx >= 0 ? anchorIdx + 1 : next.length;
    if (next[insertAt]?.streaming) {
        next.splice(insertAt, 1, message); // 本流占位仍在 → 原位替换
    } else {
        next.splice(insertAt, 0, message); // 插入本流 user 之后(时间序)
    }
    return { messages: next, render: true };
}

// ══════════════════════════════════════════════════
// 协议表面
// ══════════════════════════════════════════════════

/**
 * 合并重载的消息列表到 tab 缓存(纯函数,三分支)
 * 调用方负责 updateTab 与活动渲染(本函数返回 render 标志)。
 *
 * 三分支(按优先级):
 *   - 失败(msgs === null):位置感知追加本流内容 — 移除发起位置的本流 streaming 占位
 *     (幂等:缓存已含同 id 消息 → 已被结算,不动),把最终消息插入到发起位置;
 *     不清并发流占位(根治 R2)
 *   - fresh(长度未变):整体替换为服务端列表(render: true)
 *   - stale(长度变了):仅按 settleIndex 位置结算本流 streaming 标记
 *     (幂等:该位置仍 streaming 才结算 — 新流 token 已把尾部换成自己的消息时位置
 *     失配 → 不误结算;本流消息已被结算过 → 不动)
 *
 * @param {object|null} tab - 会话 tab(getTab 返回的对象;null/无 messages 安全返回空结果)
 * @param {number} revision - 发起时刻缓存长度(list 前捕获)
 * @param {Array|null} msgs - 服务端消息列表;null 表示重载失败(走失败分支)
 * @param {object} opts
 * @param {number} [opts.settleIndex] - 发起时刻本流占位位置(stale 结算用);无占位为 -1
 * @param {object|null} [opts.anchor] - 本流 user 消息对象引用(失败写回用);无 user 为 null
 * @param {number|null} [opts.messageId] - 本流服务端消息 id
 * @param {string} [opts.content] - 本流累积全文(失败分支写回用)
 * @returns {{messages: Array, render: boolean}} 新缓存与是否需活动渲染
 */
export function mergeFreshList(tab, revision, msgs, { settleIndex = -1, anchor = null, messageId = null, content = '' } = {}) {
    if (!tab || !Array.isArray(tab.messages)) {
        return { messages: [], render: false };
    }
    // 失败分支:重载失败 — anchor 位置感知写回本流内容(插在本流 user 之后,不清并发流占位 — 根治 R2)
    if (msgs == null) {
        return settleByPosition(tab, anchor, {
            role: 'assistant',
            content,
            ...(messageId != null ? { id: messageId } : {}),
        });
    }
    // fresh:长度未变 → 整体替换 + 活动渲染
    if (tab.messages.length === revision) {
        return { messages: msgs, render: true };
    }
    // stale:长度变了 → 优先按位置结算本流 streaming 标记(幂等)
    if (settleIndex >= 0 && tab.messages[settleIndex]?.streaming) {
        return {
            messages: tab.messages.map((m, i) =>
                i === settleIndex
                    ? { ...m, streaming: false, ...(messageId != null ? { id: messageId } : {}) }
                    : m
            ),
            render: false,
        };
    }
    // 本流占位已不在(被并发流 token 清除)— 回退 anchor 位置写回本流内容:
    // 否则服务端列表(含本流最终消息)整体丢弃,「消息不丢失」承诺不成立。
    // 幂等:缓存已含同 id 消息 → settleByPosition no-op,不重复插入。
    if (anchor != null && content) {
        return settleByPosition(tab, anchor, {
            role: 'assistant',
            content,
            ...(messageId != null ? { id: messageId } : {}),
        });
    }
    return { messages: tab.messages, render: false };
}

/**
 * 创建一条流式会话的生命周期控制器
 * @param {object} deps
 * @param {number|string} deps.convId - 发起时捕获的会话 id(防悬挂:后续写回一律按它定位)
 * @param {Function} deps.getTab - (convId) => tab|undefined,tabs.js 协议
 * @param {Function} deps.updateTab - (convId, patch) => void,tabs.js 协议(不存在 id 幂等 no-op)
 * @param {Function} [deps.isActiveStream] - () => boolean,当前是否仍为活动 tab 的流(决定是否渲染)
 * @param {Function} [deps.renderMessages] - 活动时消息区渲染回调(chat.js renderMessages)
 * @param {Function} [deps.refreshSendButton] - 发送按钮两态刷新回调(chat.js refreshSendButton)
 * @param {Function} [deps.refreshConversations] - 对话列表刷新回调(chat.js 注入)
 * @returns {{onToken: Function, onDone: Function, onError: Function, isSettled: Function}}
 *   - onToken(token) → string|null:应用 token 并返回累积全文(供调用方 DOM 增量渲染);
 *     settled 后忽略并返回 null
 *   - onDone(messageId) → Promise<void>:正常完成(messageId 非 null)或流中断(null)
 *   - onError(err) → void:错误/停止
 *   - isSettled() → boolean:是否已进入终态(完成/错误)
 */
export function createStreamSession({ convId, getTab, updateTab, isActiveStream, renderMessages, refreshSendButton, refreshConversations }) {
    if (convId == null || typeof getTab !== 'function' || typeof updateTab !== 'function') {
        throw new TypeError('createStreamSession: 需要 convId 与 getTab/updateTab 函数');
    }
    const isActive = typeof isActiveStream === 'function' ? isActiveStream : () => false;
    const render = typeof renderMessages === 'function' ? renderMessages : () => {};
    const refreshBtn = typeof refreshSendButton === 'function' ? refreshSendButton : () => {};
    const refreshList = typeof refreshConversations === 'function' ? refreshConversations : () => {};

    /** @type {string} 已累积的 assistant 全文 */
    let fullContent = '';
    /** @type {boolean} 流已终结(完成/错误/停止)— 后续回调一律忽略(错误帧后流关闭
     *  补发 onDone(null) 必须拦截,防止 phase 'done' 覆盖错误写回) */
    let streamSettled = false;

    const isAbortError = (err) => err?.name === 'AbortError';

    /**
     * 捕获本流 user 消息对象引用(失败写回的插入锚点 — 对象引用 + indexOf 定位,
     * 插入/删除造成的索引漂移不影响定位;user 消息本身不被删除,引用永有效)
     * @returns {object|null} 最后一条 user 消息对象;无 user 消息为 null
     */
    function captureAnchor() {
        const tab = getTab(convId);
        if (!tab || !Array.isArray(tab.messages)) return null;
        let anchor = null;
        tab.messages.forEach((m) => { if (m?.role === 'user') anchor = m; });
        return anchor;
    }

    /** 本流 user 消息对象(构造时捕获 — handleSend 已完成 appendMessage('user')) */
    const anchor = captureAnchor();

    /**
     * 捕获发起时刻的尾消息位置(本流 streaming 占位位置;无占位为 -1)
     * @returns {number}
     */
    function captureSettleIndex() {
        const tab = getTab(convId);
        return tab && tab.messages.length > 0 && tab.messages[tab.messages.length - 1]?.streaming
            ? tab.messages.length - 1
            : -1;
    }

    /**
     * 流式 token — 累积全文 + per-tab 缓存同步(streaming 占位替换尾部)
     * DOM 增量渲染由调用方根据返回值驱动(气泡复用 / data-streaming-live / thinking
     * 保留 chat.js;活动归属由调用方判断)。
     * @param {string} token - 服务端下发的 token 片段
     * @returns {string|null} 已累积全文(供调用方渲染);流已 settled 时忽略并返回 null
     */
    function onToken(token) {
        if (streamSettled) return null;
        fullContent += token;

        // per-tab 缓存同步(活动/后台都写;streaming 标记的 assistant 消息每次替换,
        // 最终消息在 onDone/onError 以无标记形态写回)
        const t = getTab(convId);
        if (t) {
            const settledMsgs = t.messages.filter((m) => !m.streaming);
            updateTab(convId, { messages: [...settledMsgs, { role: 'assistant', content: fullContent, streaming: true }] });
        }
        if (t && t.phase !== 'streaming') {
            updateTab(convId, { phase: 'streaming' });
        }
        return fullContent;
    }

    /**
     * 完成/中断 — 按发起 tab 写回终态(防悬挂核心)
     * 正常完成(messageId 非 null)重载消息列表并经 mergeFreshList 三分支合并;
     * 流中断(null)且有部分内容时按位置写回。
     * @param {number|null} messageId - 服务端消息 id;流中断为 null
     * @returns {Promise<void>}
     */
    async function onDone(messageId) {
        if (streamSettled) return;
        streamSettled = true;

        updateTab(convId, { isStreaming: false, activeStream: null, phase: 'done' });
        // 立即复位发送按钮 — 不等 list 重载完成（消除停止态到发送态的 UX 窗口；连发依赖此即时复位）
        refreshBtn();

        if (messageId != null) {
            // 正常完成 — 重新从服务端加载消息列表(含角色开场白 greeting),保证 UI 与 DB 一致
            // list 前捕获缓存 revision + 本流 streaming 消息位置:await 期间同 tab 可能连发
            // 新消息(isStreaming 已 false),返回后经 mergeFreshList 三分支合并,防止陈旧
            // 快照覆盖新消息(F-1)与并发流占位被清除(R2)
            const revision = getTab(convId)?.messages.length ?? 0;
            const settleIndex = captureSettleIndex();
            try {
                const msgs = await messages.list(convId);
                const tab = getTab(convId);
                if (tab) {
                    const merged = mergeFreshList(tab, revision, msgs, { settleIndex, anchor, messageId, content: fullContent });
                    updateTab(convId, { messages: merged.messages });
                    if (merged.render && isActive()) render();
                }
            } catch (err) {
                // 重新加载失败 — 退化为本地位置感知写回,避免消息丢失(不清并发流占位)
                console.error('重新加载消息列表失败:', err);
                const tab = getTab(convId);
                if (tab) {
                    const merged = mergeFreshList(tab, revision, null, { anchor, messageId, content: fullContent });
                    updateTab(convId, { messages: merged.messages });
                    if (merged.render && isActive()) render();
                }
            }
        } else if (fullContent) {
            // 流中断但已有部分内容 — 位置感知写回(不清并发流占位)
            const tab = getTab(convId);
            if (tab) {
                const merged = mergeFreshList(tab, 0, null, { anchor, content: fullContent });
                updateTab(convId, { messages: merged.messages });
                if (merged.render && isActive()) render();
            }
        }
        // 刷新对话列表(更新消息数量)
        refreshList();
    }

    /**
     * 错误/停止 — 按发起 tab 写回终态(防悬挂核心)
     * 停止(AbortError)写回 phase 'error'(警示标记),气泡保持「已停止」语义;
     * 普通错误写回 phase 'error' 并渲染错误气泡。
     * @param {Error} err - 错误对象
     */
    function onError(err) {
        if (streamSettled) return;
        streamSettled = true;

        updateTab(convId, { isStreaming: false, activeStream: null, phase: 'error' });
        const tab = getTab(convId);
        const settled = tab ? tab.messages.filter((m) => !m.streaming) : [];

        if (isAbortError(err)) {
            // 用户主动停止 — 语义是「已停止」而非错误;后端已保存部分内容
            if (fullContent) {
                // 有部分内容 → 保留 + 停止标记;无内容 → 仅保留已发消息(与既有行为一致)
                updateTab(convId, { messages: [...settled, { role: 'assistant', content: fullContent, stopped: true }] });
            } else {
                updateTab(convId, { messages: settled });
            }
            if (isActive()) render();
        } else {
            // 错误发生 — 写入缓存(警示标记,渲染路径还原 message-error 样式)
            updateTab(convId, { messages: [...settled, { role: 'assistant', content: `[错误] ${err.message}`, error: true }] });
            if (isActive()) render();
        }
        // 错误/停止时也刷新按钮与对话列表(避免计数卡死)
        refreshBtn();
        refreshList();
    }

    /** 是否已进入终态(完成/错误) */
    function isSettled() {
        return streamSettled;
    }

    return { onToken, onDone, onError, isSettled };
}

// ══════════════════════════════════════════════════
// 协议表面收口(深模块:外部只通过这些函数与 stream-session.js 交互)
// ══════════════════════════════════════════════════

export const __all__ = [
    'createStreamSession',
    'mergeFreshList',
];
