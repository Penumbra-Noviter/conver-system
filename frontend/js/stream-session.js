/**
 * Conver System — 流式会话深模块(StreamSession,零 DOM)
 *
 * 职责:
 *   1. 一条流式请求的完整生命周期状态机:fullContent 累积、streamSettled 终态守卫、
 *      完成/错误/停止按发起时捕获的 conversationId 写回(防悬挂)
 *   2. 完成后的消息列表重载合并(mergeFreshList 纯函数三分支):
 *      fresh 整体替换 / stale 仅位置结算 / 失败按位置追加(不清并发流占位 — 根治 R2)
 *   3. 统一结算入口(settleTurn):流式 onDone 正常完成段与非流式完成(成功/失败兜底)
 *      共用的 reload → mergeFreshList → 写回 → 条件渲染 段落,内部 try/catch 双分支
 *      (成功重载 / 失败位置感知写回兜底);不内嵌 refreshList(两端调用点现状不同)
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
 *   - T1 错误条化:普通(非 AbortError)流式错误不再写 `[错误] …` 进消息缓存 —
 *     错误经注入回调 deps.onError 上抛给聊天域(渲染独立错误条);已累积的部分
 *     内容保留为普通 assistant 消息(无错误标记);无内容则仅保留已发消息。
 *     本模块保持零 DOM,错误渲染完全在聊天域完成
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
 * 位置感知写回本流消息:移除本流 streaming 占位(幂等),把最终消息插入到发起位置;
 * 重生成失败兜底按被顶替旧消息身份(replaceId)原位替换,不尾部追加(F-58)。
 * 幂等规则:
 *   - 缓存已含同 id 消息(被并发流的 fresh 替换结算)→ 不动;
 *     F-66:messageId === replaceId(服务端复用被顶替旧回复 id)时跳过该早退 —
 *     缓存中被顶替旧回复 id === replaceId === messageId,幂等检查会误判「已结算」
 *     而吞掉新内容,顶替场景本体须继续走下方 replaceId 原位替换
 *   - replaceId(被顶替旧消息服务端 id,重生成路径):缓存含同 id 消息 → 原位替换
 *     (旧回复已截断、新回复顶替其位置 — 不落尾部追加,消「顶替」语义残留)
 *   - anchor(本流 user 消息对象引用):位置 anchor 之后插入本流回复 — anchor 用
 *     对象引用 + indexOf 定位,插入/删除导致的索引漂移不影响定位(根治 R2,
 *     不清并发流占位;user 消息本身不被删除,引用永有效)
 * @param {object} tab - 会话 tab(getTab 返回的对象)
 * @param {object|null} anchor - 本流 user 消息对象引用;无 user 消息为 null(追加尾部)
 * @param {object} message - 要写回的消息(role: 'assistant', content, id?)
 * @param {number|string|null} [replaceId] - 被顶替旧消息的服务端 id(F-58 重生成失败兜底);
 *   null 时回落 anchor/尾部路径
 * @returns {{messages: Array, render: boolean}} 新缓存与是否需活动渲染
 */
function settleByPosition(tab, anchor, message, replaceId = null) {
    const next = [...tab.messages];
    // 幂等:缓存已含本流消息(带 id 匹配)— 已被并发流的 fresh 替换结算,不重复插入。
    // F-66:当 messageId === replaceId(服务端复用被顶替旧回复 id)时,缓存中的被顶替
    // 旧回复 id === replaceId === messageId,幂等检查会误判「已结算」而吞掉新内容 —
    // 顶替场景本体须跳过幂等早退,继续走下方 replaceId 原位替换。
    const isReplacementScenario = replaceId != null && replaceId === message.id;
    if (!isReplacementScenario && message.id != null && next.some((m) => m.id === message.id)) {
        return { messages: tab.messages, render: false };
    }
    // F-58:重生成失败兜底 — 按被顶替旧消息身份原位替换(后端已截断旧回复,顶替而非尾部追加)。
    // 缓存中无该 id(旧消息已被并发结算移除)→ 落到 anchor/尾部常规路径。
    if (replaceId != null) {
        const replaceIdx = next.findIndex((m) => m.id === replaceId);
        if (replaceIdx >= 0) {
            next[replaceIdx] = message;
            return { messages: next, render: true };
        }
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
 *     失配 → 不误结算;本流消息已被结算过 → 不动);位置失配且无 anchor 时按
 *     F-60/F-68 兜底:有 messageId 即按 id 定位写回或渲染服务端权威列表 —
 *     守卫不查 content(空回复不被静默丢弃,与 fresh 分支行为一致)
 *
 * @param {object|null} tab - 会话 tab(getTab 返回的对象;null/无 messages 安全返回空结果)
 * @param {number} revision - 发起时刻缓存长度(list 前捕获)
 * @param {Array|null} msgs - 服务端消息列表;null 表示重载失败(走失败分支)
 * @param {object} opts
 * @param {number} [opts.settleIndex] - 发起时刻本流占位位置(stale 结算用);无占位为 -1
 * @param {object|null} [opts.anchor] - 本流 user 消息对象引用(失败写回用);无 user 为 null
 * @param {number|null} [opts.messageId] - 本流服务端消息 id
 * @param {string} [opts.content] - 本流累积全文(失败分支写回用)
 * @param {number|string|null} [opts.replaceId] - 被顶替旧消息服务端 id(F-58 重生成失败兜底:
 *   失败分支按此 id 原位替换,不尾部追加)
 * @returns {{messages: Array, render: boolean}} 新缓存与是否需活动渲染
 */
export function mergeFreshList(tab, revision, msgs, { settleIndex = -1, anchor = null, messageId = null, content = '', replaceId = null } = {}) {
    if (!tab || !Array.isArray(tab.messages)) {
        return { messages: [], render: false };
    }
    // 失败分支:重载失败 — 按身份/位置写回本流内容。
    // F-58:replaceId(被顶替旧消息)提供时按 id 原位替换,不尾部追加(重生成失败兜底 —
    // 后端已截断旧回复,顶替而非追加);无 replaceId 时回退 anchor 位置感知写回
    // (插在本流 user 之后,不清并发流占位 — 根治 R2)
    if (msgs == null) {
        return settleByPosition(tab, anchor, {
            role: 'assistant',
            content,
            ...(messageId != null ? { id: messageId } : {}),
        }, replaceId);
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
        }, replaceId);
    }
    // F-60:stale + anchor=null — 重生成/并发漂移结果不得静默丢弃。
    // F-68:有 messageId 即按 id 定位写回 — 守卫不查 content(与 fresh 分支一致,
    // 空回复不被静默丢弃):命中 → 原位替换 content + 清 streaming(幂等);
    // 找不到同 id(重生成场景,本地仍是被顶替的旧回复)→ 至少渲染服务端列表(权威)。
    if (messageId != null) {
        const matchIdx = tab.messages.findIndex((m) => m.id === messageId);
        if (matchIdx >= 0) {
            const next = [...tab.messages];
            next[matchIdx] = { ...next[matchIdx], content, streaming: false };
            return { messages: next, render: true };
        }
        return { messages: msgs, render: true };
    }
    return { messages: tab.messages, render: false };
}

/**
 * 统一结算入口 — 完成后的消息列表重载合并写回（流式 onDone 正常完成段与非流式
 * 完成分支共用）。内部完整复刻两端同构段：重新从服务端加载消息列表 → mergeFreshList
 * 三分支合并 → updateTab(按发起时捕获的 convId 写回) → 条件渲染；try/catch 双分支 —
 * 成功重载 / 失败以本地位置感知写回兜底（console.error 记录保持，消息不丢失、
 * 不清并发流占位 — 根治 R2）。
 * 防悬挂：只接受发起时捕获的 convId + getTab/updateTab 注入，绝不读「当前活动」；
 * 发起 tab 已关闭（getTab 返回 undefined）→ 无异常无渲染（updateTab 幂等 no-op 兜底）。
 * 不内嵌 refreshList —— 两端调用点现状不同（onDone 内嵌 / 非流式在发送流程末尾统一调用）。
 * @param {object} opts
 * @param {number|string} opts.convId - 发起时捕获的会话 id（防悬挂）
 * @param {Function} opts.getTab - (convId) => tab|undefined，tabs.js 协议
 * @param {Function} opts.updateTab - (convId, patch) => void，tabs.js 协议（不存在 id 幂等 no-op）
 * @param {Function} [opts.isActive] - () => boolean，当前是否仍为活动 tab（决定是否渲染）
 * @param {Function} [opts.render] - 活动时消息区渲染回调
 * @param {number} opts.revision - 发起时刻缓存长度（list 前捕获；防止陈旧快照覆盖连发新消息 F-1）
 * @param {number} [opts.settleIndex] - 发起时刻本流占位位置（stale 结算用）；无占位为 -1
 * @param {object|null} [opts.anchor] - 本流 user 消息对象引用（失败/漂移写回用）；无 user 为 null
 * @param {number|null} [opts.messageId] - 本流服务端消息 id（非流式失败兜底不带 — C2-D2 行为保持）
 * @param {string} [opts.content] - 本流累积全文/回复内容（失败分支写回用）
 * @param {number|string|null} [opts.replaceId] - 被顶替旧消息服务端 id（F-58 重生成失败兜底：
 *   失败分支按此 id 原位替换，不尾部追加）；非重生成路径缺省 null
 * @returns {Promise<void>}
 */
export async function settleTurn({ convId, getTab, updateTab, isActive, render, revision, settleIndex = -1, anchor = null, messageId = null, content = '', replaceId = null }) {
    const active = typeof isActive === 'function' ? isActive : () => false;
    const doRender = typeof render === 'function' ? render : () => {};
    try {
        const msgs = await messages.list(convId);
        const tab = getTab(convId);
        if (tab) {
            const merged = mergeFreshList(tab, revision, msgs, { settleIndex, anchor, messageId, content, replaceId });
            updateTab(convId, { messages: merged.messages });
            if (merged.render && active()) doRender();
        }
    } catch (err) {
        // 重新加载失败 — 退化为本地位置/身份感知写回,避免消息丢失(不清并发流占位;
        // F-58 重生成失败按 replaceId 原位替换,不尾部追加)
        console.error('重新加载消息列表失败:', err);
        const tab = getTab(convId);
        if (tab) {
            const merged = mergeFreshList(tab, revision, null, { settleIndex, anchor, messageId, content, replaceId });
            updateTab(convId, { messages: merged.messages });
            if (merged.render && active()) doRender();
        }
    }
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
 * @param {Function} [deps.onError] - 普通(非 AbortError)流式错误上抛回调(T1 —
 *   chat.js 用它渲染错误条;错误不写入消息缓存,本模块保持零 DOM;
 *   未注入时 no-op 兜底)
 * @returns {{onToken: Function, onDone: Function, onError: Function, isSettled: Function}}
 *   - onToken(token) → string|null:应用 token 并返回累积全文(供调用方 DOM 增量渲染);
 *     settled 后忽略并返回 null
 *   - onDone(messageId) → Promise<void>:正常完成(messageId 非 null)或流中断(null)
 *   - onError(err) → void:错误/停止(普通错误经 deps.onError 上抛,不写缓存)
 *   - isSettled() → boolean:是否已进入终态(完成/错误)
 */
export function createStreamSession({ convId, getTab, updateTab, isActiveStream, renderMessages, refreshSendButton, refreshConversations, onError: errorSink }) {
    if (convId == null || typeof getTab !== 'function' || typeof updateTab !== 'function') {
        throw new TypeError('createStreamSession: 需要 convId 与 getTab/updateTab 函数');
    }
    const isActive = typeof isActiveStream === 'function' ? isActiveStream : () => false;
    const render = typeof renderMessages === 'function' ? renderMessages : () => {};
    const refreshBtn = typeof refreshSendButton === 'function' ? refreshSendButton : () => {};
    const refreshList = typeof refreshConversations === 'function' ? refreshConversations : () => {};
    /** 普通流式错误上抛回调（T1 — chat.js 用它渲染错误条；未注入时 no-op）。
     *  注意：必须用更名绑定 errorSink —— 本函数体内另有 function onError 声明，
     *  同名参数会被函数声明遮蔽（JS 函数声明提升覆盖参数绑定）。 */
    const surfaceError = typeof errorSink === 'function' ? errorSink : () => {};

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
            // 正常完成 — 统一结算入口 settleTurn:重新从服务端加载消息列表(含角色开场白
            // greeting),保证 UI 与 DB 一致;内部 try/catch 双分支(成功重载 / 失败本地
            // 位置感知写回兜底)。revision 在 list 前捕获:await 期间同 tab 可能连发新消息
            // (isStreaming 已 false),返回后经 mergeFreshList 三分支合并,防止陈旧快照
            // 覆盖新消息(F-1)与并发流占位被清除(R2)
            const revision = getTab(convId)?.messages.length ?? 0;
            const settleIndex = captureSettleIndex();
            await settleTurn({
                convId, getTab, updateTab, isActive, render,
                revision, settleIndex, anchor, messageId, content: fullContent,
            });
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
     * 普通错误(T1)不再写 `[错误]` 进消息缓存 — 经注入回调 surfaceError 上抛给
     * 聊天域渲染错误条(本模块保持零 DOM);已累积的部分内容保留为普通 assistant
     * 消息(无错误标记),无内容则仅保留已发消息。
     * F-51 顺序契约:普通错误分支 surfaceError(err) 先于 render() 调用 —
     * 渲染抛错(活动 tab DOM 缺陷)不吞错误条;停止路径(AbortError)不调用 surfaceError。
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
            // 普通错误 — 错误经回调上抛,不写入消息缓存(错误条由聊天域渲染)。
            // 已累积的部分内容保留为普通 assistant 消息(无错误标记);无内容则仅保留已发消息
            const next = fullContent ? [...settled, { role: 'assistant', content: fullContent }] : settled;
            updateTab(convId, { messages: next });
            // F-51:surfaceError 必须先于 render — 渲染抛错(活动 tab DOM 缺陷)不应吞掉错误条。
            // 契约锁:错误上抛回调先行,渲染异常只影响 DOM 画面,错误条保证出现。
            surfaceError(err);
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
    'settleTurn',
];
