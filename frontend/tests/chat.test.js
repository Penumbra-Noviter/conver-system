/**
 * chat.js 编排薄集成测试（ARC-9 C5 — C2 settleTurn seam 挂网）
 *
 * 覆盖 handleSend 双路径：
 *   - 非流式：settleTurn 委托链（settleIndex:-1 / content=result.reply / 不带 messageId —
 *     C2-D2 行为保持审计点）、in-flight 双击守卫只发一次、失败 system 气泡逐字、
 *     在途清除后可再发、refreshConversations 注入被调、头部标题同步
 *   - 流式：createStreamSession 委托链（phase thinking/isStreaming 写回、
 *     onToken/onDone/onError 接线 — 经 chatStream mock 捕获回调驱动真实 session）
 *   - Falsify：无活动 tab / 空输入 / 流式在途 tab → no-op 不请求
 *
 * 断言纪律：优先 spy 注入钩子/模块边界的调用序列与参数（settleTurn 的
 * settleIndex/anchor/content/messageId 语义、chatStream 的 callbacks 接线），
 * DOM 断言仅限关键文案（用户气泡 / system 失败气泡 / 流式 token 渲染）。
 * 非流式/流式内部结算细节（mergeFreshList 三分支等）由 stream-session.test.js
 * 直测钉住，本文件不重复 —— 只验证 chat.js 侧的委托与接线。
 *
 * 挂载模式：jsdom + vi.resetModules() + 内联 chatDom 五件套 + fetch mock
 * （api.js setFetch seam），与 conversation-activation.test.js 同构。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** chatDom 五件套 — 与 index.html 的 id 契约一致（只读契约） */
const CHAT_DOM_HTML = `
    <div id="chat-messages"></div>
    <textarea id="chat-input"></textarea>
    <button id="btn-send"></button>
    <input type="checkbox" id="toggle-stream" checked>
    <div id="chat-header"><span class="chat-title" id="chat-title-text"></span></div>
    <div class="chat-sidebar"></div>
`;

/** 加载全新 chat + tabs + api + stream-session 实例（DOM 先就位） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM_HTML;
    const chat = await import('../js/chat.js');
    const tabs = await import('../js/tabs.js');
    const state = (await import('../js/state.js')).state;
    const api = await import('../js/api.js');
    const ss = await import('../js/stream-session.js');
    return { chat, tabs, state, api, ss };
}

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

/**
 * fetch mock 路由（api.js doFetch seam 消费）
 * POST /api/chats → 非流式消息发送；GET /api/conversations/{id}/messages → 消息列表
 */
function makeApiMock({ chatResult = null, messagesByConv = {} } = {}) {
    return vi.fn(async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        const method = options.method || 'GET';
        if (path === '/api/chats' && method === 'POST') {
            return mockJson(chatResult ?? { reply: '回复' });
        }
        const listMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
        if (listMatch && method === 'GET') {
            return mockJson(messagesByConv[Number(listMatch[1])] ?? []);
        }
        throw new Error(`未 mock 的请求: ${path}`);
    });
}

const msg = (id, role, content) => ({ id, role, content });

describe('handleSend — 非流式（settleTurn 委托链）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('成功：settleTurn 收到 {settleIndex:-1, content:result.reply}（不带 messageId）+ 用户气泡 + 刷新注入被调', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        api.setFetch(makeApiMock({ chatResult: { reply: '好的' } }));
        const settleSpy = vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        const refresh = vi.fn();
        chat.setConversationsRefresher(refresh);

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        // 输入清空 + 用户气泡渲染
        expect(chat.chatDom.chatInput.value).toBe('');
        expect(chat.chatDom.chatMessages.textContent).toContain('你好');
        // settleTurn 委托参数（C2-D2：成功分支 content 透传、不带 messageId）
        expect(settleSpy).toHaveBeenCalledTimes(1);
        const call = settleSpy.mock.calls[0][0];
        expect(call.convId).toBe(11);
        expect(call.settleIndex).toBe(-1);
        expect(call.content).toBe('好的');
        expect(call).not.toHaveProperty('messageId');
        expect(call.revision).toBe(1); // 发起时捕获（appendMessage 后 1 条 user）
        // 注入的刷新钩子被调（发送流程末尾统一刷新列表）
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    it('成功且对话在列表中 → 头部标题同步为后端返回标题（P3.5 联动）', async () => {
        const { chat, tabs, state, api, ss } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        state.conversations = [{ id: 11, title: '与 角色A 的对话' }];
        api.setFetch(makeApiMock({ chatResult: { reply: '好的' } }));
        vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        chat.setConversationsRefresher(() => {});

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        expect(chat.chatDom.chatHeader.querySelector('#chat-title-text').textContent)
            .toBe('与 角色A 的对话');
        expect(tabs.getTab(11).title).toBe('与 角色A 的对话');
    });

    it('双击守卫：在途期间重复提交只发一次真实请求（草稿保留,不追加气泡）', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        let resolveChat;
        const fetchSpy = makeApiMock({ chatResult: { reply: '回复' } });
        fetchSpy.mockImplementationOnce(async () => new Promise((r) => { resolveChat = r; }));
        api.setFetch(fetchSpy);
        const settleSpy = vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);

        chat.chatDom.chatInput.value = '你好';
        const p1 = chat.handleSend(); // 在途（appendMessage 已同步完成 → 1 个用户气泡）
        chat.chatDom.chatInput.value = '再发'; // 用户快速重输
        const p2 = chat.handleSend(); // 守卫拦截 → 立即返回
        await p2;
        expect(settleSpy).not.toHaveBeenCalled();
        expect(chat.chatDom.chatInput.value).toBe('再发'); // 草稿保留（拒绝发生在清空之前）
        expect(chat.chatDom.chatMessages.querySelectorAll('.message')).toHaveLength(1); // 无第二次气泡

        resolveChat(mockJson({ reply: '回复' }));
        await p1;
        expect(fetchSpy).toHaveBeenCalledTimes(1); // 只发一次真实请求
        expect(settleSpy).toHaveBeenCalledTimes(1);

        // finally 清除在途标记 → 可再次发送
        chat.chatDom.chatInput.value = '再来';
        await chat.handleSend();
        expect(fetchSpy).toHaveBeenCalledTimes(2);
    });

    it('失败：system 气泡「发送失败: <原因>」逐字 + settleTurn 不调用 + 在途清除 + 刷新仍被调', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        const fetchSpy = makeApiMock({ chatResult: { reply: '回复' } });
        fetchSpy.mockImplementationOnce(async () => { throw new Error('网络错误'); }); // 首次发送失败
        api.setFetch(fetchSpy);
        const settleSpy = vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        const refresh = vi.fn();
        chat.setConversationsRefresher(refresh);

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        const sys = chat.chatDom.chatMessages.querySelector('.message.system');
        expect(sys).not.toBeNull();
        expect(sys.textContent).toContain('发送失败: 网络错误');
        // F1 产品微调：system 气泡统一无头像 + 无复制按钮（与其他 system 形态一致）
        expect(sys.querySelector('.msg-avatar')).toBeNull();
        expect(sys.querySelector('.btn-copy-message')).toBeNull();
        expect(settleSpy).not.toHaveBeenCalled();
        expect(refresh).toHaveBeenCalledTimes(1);

        // 在途标记已清除 → 再次发送可正常发起（settleTurn 委托链走通）
        chat.chatDom.chatInput.value = '重试';
        await chat.handleSend();
        expect(settleSpy).toHaveBeenCalledTimes(1);
    });

    it('真实 settleTurn 路径：reload→merge→写回→渲染（非流式成功,列表整体替换）', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        api.setFetch(makeApiMock({
            chatResult: { reply: '好的' },
            messagesByConv: { 11: [msg(1, 'user', '你好'), msg(2, 'assistant', '好的')] },
        }));
        chat.setConversationsRefresher(() => {});

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        expect(tabs.getTab(11).messages).toEqual([msg(1, 'user', '你好'), msg(2, 'assistant', '好的')]);
        expect(chat.chatDom.chatMessages.textContent).toContain('好的');
    });

    it('FE-1 复制数据不截断：renderMessages 全量重渲染含双引号缓存内容 → dataset.content 与原文一致', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ role: 'assistant', content: '他说 "你好" 和 "再见"' }] });
        chat.renderMessages();
        const copyBtn = chat.chatDom.chatMessages.querySelector('.message.assistant .btn-copy-message');
        expect(copyBtn.dataset.content).toBe('他说 "你好" 和 "再见"');
    });

    it('FE-1 复制数据不截断：appendMessage 追加含双引号用户消息 → dataset.content 与原文一致', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        api.setFetch(makeApiMock({ chatResult: { reply: '好的' } }));
        vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        chat.setConversationsRefresher(() => {});

        chat.chatDom.chatInput.value = '他说 "你好" 和 "再见"';
        await chat.handleSend();

        const userCopyBtn = chat.chatDom.chatMessages.querySelector('.message.user .btn-copy-message');
        expect(userCopyBtn).not.toBeNull();
        expect(userCopyBtn.dataset.content).toBe('他说 "你好" 和 "再见"');
    });
});

describe('handleSend — 流式（createStreamSession 委托链）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** 加载模块并 mock chatStream 捕获回调；返回驱动句柄 + refresh spy */
    async function loadWithStreamHarness() {
        const env = await loadModules();
        let captured = null;
        vi.spyOn(env.api, 'chatStream').mockImplementation((data, cbs) => {
            captured = { data, cbs };
            return { abort: vi.fn(), done: Promise.resolve() };
        });
        env.tabs.openTab(11);
        env.api.setFetch(makeApiMock({
            messagesByConv: { 11: [msg(1, 'user', '你好'), msg(2, 'assistant', '好的')] },
        }));
        const refresh = vi.fn();
        env.chat.setConversationsRefresher(refresh);
        return { ...env, refresh, getCaptured: () => captured };
    }

    it('委托链：phase thinking/isStreaming 写回 + chatStream 收到 data/callbacks + onToken 增量渲染 + onDone 写回', async () => {
        const { chat, tabs, api, refresh, getCaptured } = await loadWithStreamHarness();

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        // 发起即写回 thinking/isStreaming（发送按钮 stop 态派生依据）
        const tab = tabs.getTab(11);
        expect(tab.phase).toBe('thinking');
        expect(tab.isStreaming).toBe(true);
        // chatStream 委托链接线
        expect(api.chatStream).toHaveBeenCalledTimes(1);
        const { data, cbs } = getCaptured();
        expect(data).toEqual({ conversation_id: 11, content: '你好' });
        expect(typeof cbs.onToken).toBe('function');
        expect(typeof cbs.onDone).toBe('function');
        expect(typeof cbs.onError).toBe('function');

        // onToken 接线：session 累积 + 活动 DOM 增量渲染 + 缓存写回
        cbs.onToken('你');
        cbs.onToken('好');
        expect(chat.chatDom.chatMessages.textContent).toContain('你好');
        expect(tabs.getTab(11).messages).toEqual([
            { role: 'user', content: '你好' },
            { role: 'assistant', content: '你好', streaming: true },
        ]);

        // onDone 接线：正常完成（messageId 非 null）→ settleTurn 重载合并 → 终态写回 + 渲染
        await cbs.onDone(101);
        expect(tabs.getTab(11).phase).toBe('done');
        expect(tabs.getTab(11).isStreaming).toBe(false);
        expect(tabs.getTab(11).messages).toEqual([msg(1, 'user', '你好'), msg(2, 'assistant', '好的')]);
        expect(chat.chatDom.chatMessages.textContent).toContain('好的');
        // 刷新两次均为既有语义：session.onDone 内嵌 refreshList（C2 设计，refreshList 不并入
        // settleTurn）+ handleSend 发送流程末尾统一刷新
        expect(refresh).toHaveBeenCalledTimes(2);
    });

    it('onError 接线：错误 → phase error + 错误气泡渲染 + 按钮/列表刷新', async () => {
        const { chat, tabs, refresh, getCaptured } = await loadWithStreamHarness();

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();
        getCaptured().cbs.onError(new Error('模型超时'));

        expect(tabs.getTab(11).phase).toBe('error');
        expect(tabs.getTab(11).isStreaming).toBe(false);
        expect(chat.chatDom.chatMessages.textContent).toContain('[错误] 模型超时');
        // 同 onDone：session.onError 内嵌 refreshList + handleSend 末尾统一刷新
        expect(refresh).toHaveBeenCalledTimes(2);
    });

    it('F1 流式气泡骨架即含复制按钮：onToken 逐 token 同步 data-content，点击复制当前全文', async () => {
        const { chat, getCaptured } = await loadWithStreamHarness();
        const writeText = vi.fn().mockResolvedValue(undefined);
        Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();
        const { cbs } = getCaptured();

        // 首个 token 建泡 → 骨架含复制按钮（非 system 角色统一有复制按钮）
        cbs.onToken('你');
        const bubble = chat.chatDom.chatMessages.querySelector('.message.assistant');
        const copyBtn = bubble.querySelector('.btn-copy-message');
        expect(copyBtn).not.toBeNull();
        expect(copyBtn.dataset.content).toBe('你');

        // 流式 token 更新同步复制数据属性（复用既有挂载机制）
        cbs.onToken('好');
        expect(copyBtn.dataset.content).toBe('你好');

        // 复制行为正确：点击复制当前全文（读 dataset，非绑定时刻快照）
        copyBtn.click();
        await vi.waitFor(() => expect(writeText).toHaveBeenCalledWith('你好'));
    });

    it('FE-1 复制数据不截断：onToken 增量路径同步含双引号全文（dataset 赋值通道）', async () => {
        const { chat, getCaptured } = await loadWithStreamHarness();
        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();
        getCaptured().cbs.onToken('他说 "你好" 和 "再见"');
        const copyBtn = chat.chatDom.chatMessages.querySelector('.message.assistant .btn-copy-message');
        expect(copyBtn.dataset.content).toBe('他说 "你好" 和 "再见"');
    });

    it('F1 切回复用：renderMessages 重建 DOM 后 onToken 复用 live 气泡（不重复建泡）并同步 data-content', async () => {
        const { chat, getCaptured } = await loadWithStreamHarness();
        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();
        const { cbs } = getCaptured();

        cbs.onToken('你');
        expect(chat.chatDom.chatMessages.querySelectorAll('.message.assistant')).toHaveLength(1);

        // 切走再切回：renderMessages 从缓存重建 DOM（streaming 占位标记 live）
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.querySelectorAll('.message.assistant')).toHaveLength(1);
        expect(chat.chatDom.chatMessages.querySelector('.message[data-streaming-live="1"]')).not.toBeNull();

        // 旧 DOM 引用已失效 → 重新定位 live 气泡复用，不重复创建
        cbs.onToken('好');
        expect(chat.chatDom.chatMessages.querySelectorAll('.message.assistant')).toHaveLength(1);
        expect(chat.chatDom.chatMessages.textContent).toContain('你好');
        const asstCopyBtn = chat.chatDom.chatMessages.querySelector('.message.assistant .btn-copy-message');
        expect(asstCopyBtn.dataset.content).toBe('你好');
    });

    it('F1 复制反馈：点击后 check 图标 + copied 类，1.5s 后恢复 clipboard 图标', async () => {
        const { chat, getCaptured } = await loadWithStreamHarness();
        const writeText = vi.fn().mockResolvedValue(undefined);
        Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();
        getCaptured().cbs.onToken('你');
        const copyBtn = chat.chatDom.chatMessages.querySelector('.message.assistant .btn-copy-message');
        expect(copyBtn.dataset.content).toBe('你');

        vi.useFakeTimers();
        copyBtn.click();
        await Promise.resolve();
        await Promise.resolve();
        expect(writeText).toHaveBeenCalledWith('你');
        expect(copyBtn.classList.contains('copied')).toBe(true);
        expect(copyBtn.innerHTML).toContain('data-icon="check"');
        vi.advanceTimersByTime(1500);
        expect(copyBtn.classList.contains('copied')).toBe(false);
        expect(copyBtn.innerHTML).toContain('data-icon="clipboard"');
        vi.useRealTimers();
    });

    it('F1 Falsify:剪贴板不可用（writeText 拒绝）→ x 图标 + 无 copied 类（不崩溃）', async () => {
        const { chat, getCaptured } = await loadWithStreamHarness();
        const writeText = vi.fn().mockRejectedValue(new Error('denied'));
        Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();
        getCaptured().cbs.onToken('你');
        const copyBtn = chat.chatDom.chatMessages.querySelector('.message.assistant .btn-copy-message');

        vi.useFakeTimers();
        copyBtn.click();
        await Promise.resolve();
        await Promise.resolve();
        expect(writeText).toHaveBeenCalledWith('你');
        expect(copyBtn.classList.contains('copied')).toBe(false);
        expect(copyBtn.innerHTML).toContain('data-icon="x"');
        vi.useRealTimers();
    });
});

describe('handleSend — Falsify（no-op 路径）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('无活动 tab → no-op 不请求、不调刷新', async () => {
        const { chat, api } = await loadModules();
        const fetchSpy = makeApiMock({});
        api.setFetch(fetchSpy);
        const refresh = vi.fn();
        chat.setConversationsRefresher(refresh);

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        expect(fetchSpy).not.toHaveBeenCalled();
        expect(refresh).not.toHaveBeenCalled();
    });

    it('空输入（含纯空白）→ no-op 不请求', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        const fetchSpy = makeApiMock({});
        api.setFetch(fetchSpy);
        chat.setConversationsRefresher(() => {});

        chat.chatDom.chatInput.value = '   ';
        await chat.handleSend();

        expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('流式在途 tab（isStreaming）→ no-op 不请求（发送按钮应为停止态）', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { isStreaming: true });
        const fetchSpy = makeApiMock({});
        api.setFetch(fetchSpy);
        chat.setConversationsRefresher(() => {});

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        expect(fetchSpy).not.toHaveBeenCalled();
    });
});

describe('EMPTY_HEADER_HTML — 空态头部文案单一来源（ARC-10 C7）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('常量值逐字：「选择一个角色开始对话」', async () => {
        const { chat } = await loadModules();
        expect(chat.EMPTY_HEADER_HTML).toBe('<span class="chat-title">选择一个角色开始对话</span>');
    });

    it('showEmptyState 头部渲染 EMPTY_HEADER_HTML 常量（与消息区空态同源）', async () => {
        const { chat } = await loadModules();
        const activation = await import('../js/conversation-activation.js');
        activation.showEmptyState();
        expect(chat.chatDom.chatHeader.innerHTML).toBe(chat.EMPTY_HEADER_HTML);
        expect(chat.chatDom.chatMessages.innerHTML).toBe(chat.EMPTY_STATE_HTML);
    });
});

describe('renderMessages — 空态判定收口（F6 单一来源，format 两用例随迁）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('空数组（活动 tab 无消息）→ EMPTY_STATE_HTML（替代消息列表模板旧空态文案）', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.innerHTML).toBe(chat.EMPTY_STATE_HTML);
    });

    it('非数组消息 → EMPTY_STATE_HTML 不崩溃', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: null });
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.innerHTML).toBe(chat.EMPTY_STATE_HTML);
    });

    it('无活动 tab → EMPTY_STATE_HTML（既有 no-op 分支保持）', async () => {
        const { chat } = await loadModules();
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.innerHTML).toBe(chat.EMPTY_STATE_HTML);
    });

    it('有消息 → 渲染气泡不显示空态', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ role: 'user', content: '你好' }] });
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.innerHTML).not.toContain('empty-state');
        expect(chat.chatDom.chatMessages.textContent).toContain('你好');
    });
});

describe('renderMessages — 缓存变体标记还原（F1 工厂变体透传，切走再切回语义保持）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('stopped 缓存消息 → 「（已停止）」标记还原', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ role: 'assistant', content: '部分内容', stopped: true }] });
        chat.renderMessages();
        const bubble = chat.chatDom.chatMessages.querySelector('.message.assistant');
        expect(bubble.querySelector('.message-stop-tag').textContent).toBe('（已停止）');
    });

    it('error 缓存消息 → message-error 类还原', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ role: 'assistant', content: '[错误] x', error: true }] });
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.querySelector('.message.assistant').classList.contains('message-error')).toBe(true);
    });

    it('streaming 缓存消息 → data-streaming-live 标记（切回后 onToken 复用该气泡）', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ role: 'user', content: 'hi' }, { role: 'assistant', content: '部分', streaming: true }] });
        chat.renderMessages();
        const live = chat.chatDom.chatMessages.querySelector('.message[data-streaming-live="1"]');
        expect(live).not.toBeNull();
        expect(live.textContent).toContain('部分');
    });
});

describe('聊天头部深模块（F4 收口 — renderChatHeader / startRename / 标题同步，自 app.test.js 随迁）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** 渲染头部（已知会话）+ 注入列表标题同步钩子 + PUT 路由 mock */
    async function setupHeader({ title = '旧标题', putFail = false } = {}) {
        const env = await loadModules();
        env.state.conversations = [{ id: 11, title, character_id: 1, model_name: 'm', model_provider: 'claude' }];
        env.state.models = { providers: [{ key: 'claude', name: 'Claude (Anthropic)', models: [] }] };
        env.tabs.openTab(11);
        env.tabs.updateTab(11, { title });
        const fetchSpy = makeApiMock({});
        fetchSpy.mockImplementation((url, options = {}) => {
            if (String(url).endsWith('/api/conversations/11') && options?.method === 'PUT') {
                return putFail
                    ? mockJson({ detail: 'boom' }, 500)
                    : mockJson({ id: 11, title: '新标题', character_id: 1 });
            }
            return makeApiMock({})(url, options);
        });
        env.api.setFetch(fetchSpy);
        env.chat.renderChatHeader(11);
        const listSync = vi.fn();
        env.chat.setConversationListTitleSyncer(listSync);
        return { ...env, listSync };
    }

    it('renderChatHeader：标题 + 模型 badge + 列表切换/导出按钮（按 conversations 列表派生）', async () => {
        const { chat } = await setupHeader();
        const header = chat.chatDom.chatHeader;
        expect(header.querySelector('#chat-title-text').textContent).toBe('旧标题');
        expect(header.querySelector('.chat-model-badge').textContent).toContain('Claude (Anthropic) · m');
        expect(header.querySelector('#btn-toggle-conv-list')).not.toBeNull();
        expect(header.querySelector('#btn-export-conv')).not.toBeNull();
    });

    it('Falsify:renderChatHeader 未知名会话 → EMPTY_HEADER_HTML（不崩溃）', async () => {
        const { chat } = await loadModules();
        chat.renderChatHeader(99);
        expect(chat.chatDom.chatHeader.innerHTML).toBe(chat.EMPTY_HEADER_HTML);
    });

    it('双击标题重命名：Enter 提交 → PUT → 头部/tab 同步 + 列表同步钩子收到 (id, title)', async () => {
        const { chat, tabs, listSync } = await setupHeader();
        chat.chatDom.chatHeader.querySelector('#chat-title-text')
            .dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = chat.chatDom.chatHeader.querySelector('.chat-title-input');
        expect(input).not.toBeNull();
        input.value = '新标题';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        await vi.waitFor(() => expect(tabs.getTab(11).title).toBe('新标题'));
        expect(chat.chatDom.chatHeader.querySelector('#chat-title-text').textContent).toBe('新标题');
        expect(listSync).toHaveBeenCalledWith(11, '新标题');
    });

    it('头部按钮：移动端列表切换 + 导出弹窗', async () => {
        const { chat } = await setupHeader();
        chat.chatDom.chatHeader.querySelector('#btn-toggle-conv-list').click();
        expect(document.querySelector('.chat-sidebar').classList.contains('mobile-expanded')).toBe(true);
        chat.chatDom.chatHeader.querySelector('#btn-export-conv').click();
        await vi.waitFor(() => expect(document.querySelector('.export-modal')).not.toBeNull());
    });

    it('Escape 取消重命名 → 恢复原标题', async () => {
        const { chat, tabs } = await setupHeader();
        chat.chatDom.chatHeader.querySelector('#chat-title-text')
            .dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = chat.chatDom.chatHeader.querySelector('.chat-title-input');
        input.value = '不应生效';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        await new Promise((r) => setTimeout(r, 0));

        expect(tabs.getTab(11).title).toBe('旧标题');
    });

    it('Falsify:重命名保存失败 → console.error，tab 不污染、列表钩子不调、头部恢复输入值', async () => {
        const { chat, tabs, listSync } = await setupHeader({ putFail: true });
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        chat.chatDom.chatHeader.querySelector('#chat-title-text')
            .dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = chat.chatDom.chatHeader.querySelector('.chat-title-input');
        input.value = '新标题';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        await vi.waitFor(() => expect(errorSpy).toHaveBeenCalledWith('重命名失败:', expect.any(Error)));
        expect(tabs.getTab(11).title).toBe('旧标题');
        expect(listSync).not.toHaveBeenCalled();
        expect(chat.chatDom.chatHeader.querySelector('#chat-title-text').textContent).toBe('新标题');
        errorSpy.mockRestore();
    });
});
