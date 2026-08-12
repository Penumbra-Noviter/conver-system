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
