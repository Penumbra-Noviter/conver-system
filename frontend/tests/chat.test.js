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
 * POST /api/chats → 非流式消息发送；POST /api/conversations/{id}/regenerate → 重生成；
 * GET /api/conversations/{id}/messages → 消息列表
 */
function makeApiMock({ chatResult = null, messagesByConv = {}, regenerateResult = null } = {}) {
    return vi.fn(async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        const method = options.method || 'GET';
        if (path === '/api/chats' && method === 'POST') {
            return mockJson(chatResult ?? { reply: '回复' });
        }
        const regenMatch = path.match(/^\/api\/conversations\/(\d+)\/regenerate$/);
        if (regenMatch && method === 'POST') {
            return mockJson(
                regenerateResult ?? { reply: '新回复', message_id: 999, conversation_id: Number(regenMatch[1]) }
            );
        }
        const listMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
        if (listMatch && method === 'GET') {
            return mockJson(messagesByConv[Number(listMatch[1])] ?? []);
        }
        throw new Error(`未 mock 的请求: ${path}`);
    });
}

const msg = (id, role, content) => ({ id, role, content });

/**
 * 渲染聊天头部（已知会话）+ 注入列表标题同步钩子 + PUT 路由 mock
 * 供「聊天头部深模块」与「setChatHooks 方言契约」两组用例共用
 */
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
    env.chat.setChatHooks({ syncConversationListTitle: listSync });
    return { ...env, listSync };
}

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
        chat.setChatHooks({ refreshConversations: refresh });

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
        chat.setChatHooks({ refreshConversations: () => {} });

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

    it('失败：渲染错误条（不再写 system 失败消息）+ settleTurn 不调用 + 在途清除 + 刷新仍被调', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        const fetchSpy = makeApiMock({ chatResult: { reply: '回复' } });
        fetchSpy.mockImplementationOnce(async () => { throw new Error('网络错误'); }); // 首次发送失败
        api.setFetch(fetchSpy);
        const settleSpy = vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        const refresh = vi.fn();
        chat.setChatHooks({ refreshConversations: refresh });

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        // 消息列表不再写入 system 失败气泡 — 错误经 error-bar 深模块渲染（挂 #chat-messages 父级）
        expect(chat.chatDom.chatMessages.querySelector('.message.system')).toBeNull();
        expect(chat.chatDom.chatMessages.querySelector('.message.error')).toBeNull();
        const bar = chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
        expect(bar).not.toBeNull();
        expect(bar.textContent).toContain('网络错误');
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
        chat.setChatHooks({ refreshConversations: () => {} });

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
        chat.setChatHooks({ refreshConversations: () => {} });

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
        env.chat.setChatHooks({ refreshConversations: refresh });
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

    it('onError 接线：错误 → phase error + 错误条渲染（消息列表无错误）+ 按钮/列表刷新', async () => {
        const { chat, tabs, refresh, getCaptured } = await loadWithStreamHarness();

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();
        getCaptured().cbs.onError(new Error('模型超时'));

        expect(tabs.getTab(11).phase).toBe('error');
        expect(tabs.getTab(11).isStreaming).toBe(false);
        expect(tabs.getTab(11).messages.some((m) => m.error)).toBe(false);
        expect(chat.chatDom.chatMessages.textContent).not.toContain('[错误]');
        const bar = chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
        expect(bar).not.toBeNull();
        expect(bar.textContent).toContain('模型超时');
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
        chat.setChatHooks({ refreshConversations: refresh });

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
        chat.setChatHooks({ refreshConversations: () => {} });

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
        chat.setChatHooks({ refreshConversations: () => {} });

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        expect(fetchSpy).not.toHaveBeenCalled();
    });
});

describe('setChatHooks — options-object 方言契约（C3 统一注入面）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('按 key 合并：注入 refreshConversations 后已注入的 syncConversationListTitle 不被覆盖（重命名仍走钩子）', async () => {
        const env = await setupHeader({});
        env.chat.setChatHooks({ refreshConversations: () => {} }); // 只注入另一键 — 合并语义

        env.chat.chatDom.chatHeader.querySelector('#chat-title-text')
            .dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = env.chat.chatDom.chatHeader.querySelector('.chat-title-input');
        input.value = '新标题';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        // 既有 syncConversationListTitle 钩子仍在（收到 (id, newTitle)）
        await vi.waitFor(() => expect(env.listSync).toHaveBeenCalledWith(11, '新标题'));
    });

    it('Falsify:键非函数不覆盖 → 既有函数钩子保留（重命名仍同步），非函数值不抛错', async () => {
        const env = await setupHeader({});
        env.chat.setChatHooks({ refreshConversations: 42, syncConversationListTitle: 'not-a-function' });

        env.chat.chatDom.chatHeader.querySelector('#chat-title-text')
            .dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = env.chat.chatDom.chatHeader.querySelector('.chat-title-input');
        input.value = '新标题';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        await vi.waitFor(() => expect(env.listSync).toHaveBeenCalledWith(11, '新标题'));
    });

    it('缺省默认 no-op 兜底：不注入 syncConversationListTitle → 重命名成功不抛错', async () => {
        const env = await loadModules();
        env.state.conversations = [{ id: 11, title: '旧标题', character_id: 1, model_name: 'm', model_provider: 'claude' }];
        env.state.models = { providers: [{ key: 'claude', name: 'Claude (Anthropic)', models: [] }] };
        env.tabs.openTab(11);
        env.tabs.updateTab(11, { title: '旧标题' });
        const fetchSpy = makeApiMock({});
        fetchSpy.mockImplementation((url, options = {}) => {
            if (String(url).endsWith('/api/conversations/11') && options?.method === 'PUT') {
                return mockJson({ id: 11, title: '新标题', character_id: 1 });
            }
            return makeApiMock({})(url, options);
        });
        env.api.setFetch(fetchSpy);
        env.chat.renderChatHeader(11);

        env.chat.chatDom.chatHeader.querySelector('#chat-title-text')
            .dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = env.chat.chatDom.chatHeader.querySelector('.chat-title-input');
        input.value = '新标题';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        // 未注入键走 no-op 兜底 — 保存链路正常完成
        await vi.waitFor(() => expect(env.tabs.getTab(11).title).toBe('新标题'));
        expect(env.chat.chatDom.chatHeader.querySelector('#chat-title-text').textContent).toBe('新标题');
    });

    it('Falsify:setChatHooks() 无参 / null / 非对象 → 不抛错，钩子保持缺省 no-op', async () => {
        const { chat } = await loadModules();
        expect(() => chat.setChatHooks()).not.toThrow();
        expect(() => chat.setChatHooks(null)).not.toThrow();
        expect(() => chat.setChatHooks('corrupt')).not.toThrow();
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

describe('首启引导卡 — 凭证协议 none 空态引导卡（T1）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('none 态空态渲染引导卡（含「前往设置」按钮）+ EMPTY_STATE_HTML 保留非 none 文案', async () => {
        const { chat, tabs, state } = await loadModules();
        state.credentialsProtocol = 'none';
        tabs.openTab(11); // 活动 tab 无消息 → 空态
        chat.renderMessages();
        const guideBtn = chat.chatDom.chatMessages.querySelector('.empty-state-guide-btn');
        expect(guideBtn).not.toBeNull();
        expect(chat.chatDom.chatMessages.textContent).toContain('先配置 AI 接口');
        // 引导卡不在非 none 态出现
        state.credentialsProtocol = 'openai';
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.querySelector('.empty-state-guide-btn')).toBeNull();
        expect(chat.chatDom.chatMessages.innerHTML).toBe(chat.EMPTY_STATE_HTML);
    });

    it('引导卡「前往设置」点击 → 调注入 navigateToSettings 钩子（复用视图切换）', async () => {
        const { chat, tabs, state } = await loadModules();
        state.credentialsProtocol = 'none';
        tabs.openTab(11);
        const nav = vi.fn();
        chat.setChatHooks({ navigateToSettings: nav });
        chat.renderMessages();
        chat.chatDom.chatMessages.querySelector('.empty-state-guide-btn').click();
        expect(nav).toHaveBeenCalledTimes(1);
    });

    it('EMPTY_STATE_HTML 常量保留非 none 文案（引导卡不覆盖常量）', async () => {
        const { chat } = await loadModules();
        expect(chat.EMPTY_STATE_HTML).toBe('<div class="empty-state"><p>选择左侧对话或创建新对话开始聊天</p></div>');
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

    it('Falsify:字符串 messages → 空态安全路径，不抛 TypeError（Array.isArray 守卫）', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: 'corrupt-cache-string' });
        expect(() => chat.renderMessages()).not.toThrow();
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

describe('T2 搜索定位 — renderMessages 高亮与定位（scrollIntoView / scrollTop 时序）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    const TARGET_MSGS = [
        { id: 101, role: 'user', content: '你好' },
        { id: 202, role: 'assistant', content: '好的' },
    ];

    /** 建活动 tab + 带 id 消息；jsdom 无 scrollHeight 语义 → 固定一个值以便检测滚动到底 */
    function setupTarget({ chat, tabs }, { scrollHeight = 1000 } = {}) {
        tabs.openTab(11);
        tabs.updateTab(11, { messages: TARGET_MSGS });
        Object.defineProperty(chat.chatDom.chatMessages, 'scrollHeight', { value: scrollHeight, configurable: true });
        return chat.chatDom.chatMessages;
    }

    /** jsdom 无 scrollIntoView → 在 Element.prototype 挂 mock（renderMessages 经原型链调用） */
    function mockScrollIntoView() {
        const fn = vi.fn();
        Object.defineProperty(Element.prototype, 'scrollIntoView', {
            value: fn, configurable: true, writable: true,
        });
        return fn;
    }

    it('携带 messageId → 目标气泡 scrollIntoView({block:"center"}) + search-highlight，且不被滚动到底覆盖', async () => {
        const { chat, tabs } = await loadModules();
        const container = setupTarget({ chat, tabs });
        const scrollIntoView = mockScrollIntoView();
        chat.renderMessages({ messageId: 202 });
        const target = container.querySelector('[data-message-id="202"]');
        expect(target).not.toBeNull();
        expect(scrollIntoView).toHaveBeenCalledWith({ block: 'center' });
        expect(target.classList.contains('search-highlight')).toBe(true);
        expect(container.scrollTop).not.toBe(container.scrollHeight); // 定位路径不滚动到底
    });

    it('无 messageId → 既有滚动到底保持（scrollTop 置 scrollHeight）', async () => {
        const { chat, tabs } = await loadModules();
        const container = setupTarget({ chat, tabs });
        chat.renderMessages();
        expect(container.scrollTop).toBe(container.scrollHeight);
    });

    it('search-highlight 约 3s 后自动清除', async () => {
        vi.useFakeTimers();
        const { chat, tabs } = await loadModules();
        const container = setupTarget({ chat, tabs });
        mockScrollIntoView();
        chat.renderMessages({ messageId: 202 });
        const target = container.querySelector('[data-message-id="202"]');
        expect(target.classList.contains('search-highlight')).toBe(true);
        vi.advanceTimersByTime(2999);
        expect(target.classList.contains('search-highlight')).toBe(true);
        vi.advanceTimersByTime(1);
        expect(target.classList.contains('search-highlight')).toBe(false);
        vi.useRealTimers();
    });

    it('Falsify:目标消息不存在（messageId 无匹配）→ 回落 scrollToBottom（不崩溃、不高亮、滚动到底）', async () => {
        const { chat, tabs } = await loadModules();
        const container = setupTarget({ chat, tabs });
        expect(() => chat.renderMessages({ messageId: 999 })).not.toThrow();
        expect(container.querySelectorAll('.search-highlight')).toHaveLength(0);
        expect(container.scrollTop).toBe(container.scrollHeight);
    });

    it('第二次定位清理旧定时器：旧 3s 定时器不误清除第二次定位的高亮', async () => {
        vi.useFakeTimers();
        const { chat, tabs } = await loadModules();
        const container = setupTarget({ chat, tabs });
        mockScrollIntoView();
        chat.renderMessages({ messageId: 101 }); // t=0 定位 101 → 定时器 0→3000
        expect(container.querySelector('[data-message-id="101"]').classList.contains('search-highlight')).toBe(true);
        vi.advanceTimersByTime(2500); // t=2500（旧定时器未到期）
        chat.renderMessages({ messageId: 202 }); // 第二次定位 → 清理旧定时器；新定时器 2500→5500
        const secondEl = container.querySelector('[data-message-id="202"]');
        expect(secondEl.classList.contains('search-highlight')).toBe(true);
        expect(container.querySelector('[data-message-id="101"]').classList.contains('search-highlight')).toBe(false);
        vi.advanceTimersByTime(500); // t=3000：旧定时器若未被清理将在此触发 → 误清除新高亮
        expect(secondEl.classList.contains('search-highlight')).toBe(true); // 新高亮保持
        vi.advanceTimersByTime(2500); // t=5500：新定时器到期
        expect(secondEl.classList.contains('search-highlight')).toBe(false);
        vi.useRealTimers();
    });

    it('渲染重建（消息重载）后：新 DOM 无残留 search-highlight，旧定时器触发不崩溃', async () => {
        vi.useFakeTimers();
        const { chat, tabs } = await loadModules();
        const container = setupTarget({ chat, tabs });
        mockScrollIntoView();
        chat.renderMessages({ messageId: 202 });
        expect(container.querySelector('[data-message-id="202"]').classList.contains('search-highlight')).toBe(true);
        // 消息重载触发完整重建（renderMessages 无 messageId）
        chat.renderMessages();
        expect(container.querySelector('[data-message-id="202"]').classList.contains('search-highlight')).toBe(false);
        // 旧的 3s 定时器触发（引用已卸载旧节点）→ 不崩溃，新 DOM 无残留
        expect(() => vi.advanceTimersByTime(4000)).not.toThrow();
        expect(container.querySelector('[data-message-id="202"]').classList.contains('search-highlight')).toBe(false);
        vi.useRealTimers();
    });
});

describe('聊天头部深模块（F4 收口 — renderChatHeader / startRename / 标题同步，自 app.test.js 随迁）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

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

    it('Falsify:startRename(undefined/null) → 静默返回不抛错（conv 守卫）', async () => {
        const { chat } = await loadModules();
        expect(() => chat.startRename(undefined)).not.toThrow();
        expect(() => chat.startRename(null)).not.toThrow();
        // 守卫后未进入编辑态（标题元素保持原状）
        expect(chat.chatDom.chatHeader.querySelector('.chat-title-input')).toBeNull();
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

describe('T3 对话内模型切换 — 头部徽标可点击 → 保存 → 同步', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** 已知会话 + 双 provider 模型表 + PUT 路由 mock；默认凭证 openai（无确认提示） */
    async function setupModelSwitch({ protocol = 'openai', putFail = false } = {}) {
        const env = await loadModules();
        env.state.conversations = [{ id: 11, title: '会话A', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }];
        env.state.models = {
            providers: [
                { key: 'claude', name: 'Claude (Anthropic)', models: ['claude-sonnet-5', 'claude-opus-4-8'] },
                { key: 'deepseek', name: 'DeepSeek', models: ['deepseek-chat'] },
            ],
        };
        env.state.credentialsProtocol = protocol;
        env.tabs.openTab(11);
        const refresh = vi.fn();
        env.chat.setChatHooks({ refreshConversations: refresh });
        const fetchSpy = makeApiMock({});
        fetchSpy.mockImplementation((url, options = {}) => {
            if (String(url).endsWith('/api/conversations/11') && options?.method === 'PUT') {
                const body = JSON.parse(options.body);
                return putFail ? mockJson({ detail: 'boom' }, 500) : mockJson({ id: 11, ...body });
            }
            return makeApiMock({})(url, options);
        });
        env.api.setFetch(fetchSpy);
        env.chat.renderChatHeader(11);
        return { ...env, refresh, fetchSpy };
    }

    /** 点徽标打开选择器 → 选 deepseek-chat → 点「开始对话」确认 */
    function pickDeepseek() {
        document.querySelector('.chat-model-badge').click();
        const overlay = document.querySelector('.modal-overlay');
        const prov = overlay.querySelector('#ms-provider');
        prov.value = 'deepseek';
        prov.dispatchEvent(new Event('change', { bubbles: true }));
        overlay.querySelector('#ms-model').value = 'deepseek-chat';
        overlay.querySelector('.ms-start').click();
    }

    it('.chat-model-badge 是可点击按钮；点击打开模型选择器并预选当前 conv 的 provider/model', async () => {
        const { chat } = await setupModelSwitch();
        const badge = chat.chatDom.chatHeader.querySelector('.chat-model-badge');
        expect(badge.tagName).toBe('BUTTON');
        badge.click();
        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        expect(overlay.querySelector('#ms-provider').value).toBe('claude'); // 预选当前 provider
        expect(overlay.querySelector('#ms-model').value).toBe('claude-sonnet-5'); // 预选当前 model
        overlay.querySelector('.ms-cancel').click();
    });

    it('确认切换 → PUT /api/conversations/11 请求体 {model_provider, model_name} + 头部徽标同步 + 列表刷新 + state 就地更新', async () => {
        const { chat, state, refresh, fetchSpy } = await setupModelSwitch();
        pickDeepseek();

        await vi.waitFor(() => {
            expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations/11') && o?.method === 'PUT')).toBe(true);
        });
        const putCall = fetchSpy.mock.calls.find(([u, o]) => String(u).endsWith('/api/conversations/11') && o?.method === 'PUT');
        expect(JSON.parse(putCall[1].body)).toEqual({ model_provider: 'deepseek', model_name: 'deepseek-chat' });
        // 头部徽标同步（重渲染基于 state.conversations 单一事实来源）
        expect(chat.chatDom.chatHeader.querySelector('.chat-model-badge').textContent).toContain('DeepSeek · deepseek-chat');
        // state 就地更新
        expect(state.conversations[0].model_provider).toBe('deepseek');
        expect(state.conversations[0].model_name).toBe('deepseek-chat');
        // 对话列表同步（复用注入钩子 refreshConversations）
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    it('取消切换 → 不发 PUT、state 与头部不变', async () => {
        const { chat, fetchSpy } = await setupModelSwitch();
        chat.chatDom.chatHeader.querySelector('.chat-model-badge').click();
        document.querySelector('.modal-overlay .ms-cancel').click();
        await new Promise((r) => setTimeout(r, 0));
        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations/11') && o?.method === 'PUT')).toBe(false);
        expect(chat.chatDom.chatHeader.querySelector('.chat-model-badge').textContent).toContain('Claude (Anthropic) · claude-sonnet-5');
    });

    it('Falsify:切换保存失败 → console.error、state 不污染、头部保持原模型、列表不刷新', async () => {
        const { chat, refresh, fetchSpy } = await setupModelSwitch({ putFail: true });
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        pickDeepseek();

        await vi.waitFor(() => expect(errorSpy).toHaveBeenCalledWith('切换模型失败:', expect.any(Error)));
        expect(chat.chatDom.chatHeader.querySelector('.chat-model-badge').textContent).toContain('Claude (Anthropic) · claude-sonnet-5');
        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations/11') && o?.method === 'PUT')).toBe(true);
        expect(refresh).not.toHaveBeenCalled();
        errorSpy.mockRestore();
    });
});

describe('T3 对话内模型切换 — 凭证不可用确认提示（none/claude 态）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** 复用 setupModelSwitch 的 PUT 路由（from 上一 describe 的 helper 逻辑内联） */
    async function setupSwitch({ protocol }) {
        const env = await loadModules();
        env.state.conversations = [{ id: 11, title: '会话A', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }];
        env.state.models = {
            providers: [
                { key: 'claude', name: 'Claude (Anthropic)', models: ['claude-sonnet-5'] },
                { key: 'deepseek', name: 'DeepSeek', models: ['deepseek-chat'] },
            ],
        };
        env.state.credentialsProtocol = protocol;
        env.tabs.openTab(11);
        env.chat.setChatHooks({ refreshConversations: vi.fn() });
        const fetchSpy = makeApiMock({});
        fetchSpy.mockImplementation((url, options = {}) => {
            if (String(url).endsWith('/api/conversations/11') && options?.method === 'PUT') {
                return mockJson({ id: 11, ...JSON.parse(options.body) });
            }
            return makeApiMock({})(url, options);
        });
        env.api.setFetch(fetchSpy);
        env.chat.renderChatHeader(11);
        return { ...env, fetchSpy };
    }

    const hasPut = (fetchSpy) => fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations/11') && o?.method === 'PUT');

    it('凭证 none 态：任意目标 provider 都弹确认提示，确认后仍保存', async () => {
        const { chat, fetchSpy } = await setupSwitch({ protocol: 'none' });
        chat.chatDom.chatHeader.querySelector('.chat-model-badge').click();
        document.querySelector('.modal-overlay .ms-start').click(); // 保持 claude → none 态也提示
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        expect(document.querySelector('.confirm-modal').textContent).toContain('尚未配置 API Key');
        document.querySelector('.confirm-modal .confirm-ok').click();
        await vi.waitFor(() => expect(hasPut(fetchSpy)).toBe(true));
    });

    it('凭证 none 态：确认弹窗点取消 → 不保存', async () => {
        const { chat, fetchSpy } = await setupSwitch({ protocol: 'none' });
        chat.chatDom.chatHeader.querySelector('.chat-model-badge').click();
        document.querySelector('.modal-overlay .ms-start').click();
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-cancel').click();
        await new Promise((r) => setTimeout(r, 0));
        expect(hasPut(fetchSpy)).toBe(false);
    });

    it('凭证 claude 态 + 目标 provider 非 claude → 弹确认提示，确认后保存', async () => {
        const { chat, fetchSpy } = await setupSwitch({ protocol: 'claude' });
        chat.chatDom.chatHeader.querySelector('.chat-model-badge').click();
        const overlay = document.querySelector('.modal-overlay');
        const prov = overlay.querySelector('#ms-provider');
        prov.value = 'deepseek';
        prov.dispatchEvent(new Event('change', { bubbles: true }));
        overlay.querySelector('#ms-model').value = 'deepseek-chat';
        overlay.querySelector('.ms-start').click();
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-ok').click();
        await vi.waitFor(() => expect(hasPut(fetchSpy)).toBe(true));
    });

    it('凭证 claude 态 + 目标 provider 为 claude → 直接保存无确认提示', async () => {
        const { chat, fetchSpy } = await setupSwitch({ protocol: 'claude' });
        chat.chatDom.chatHeader.querySelector('.chat-model-badge').click();
        document.querySelector('.modal-overlay .ms-start').click(); // 目标保持 claude
        await vi.waitFor(() => expect(hasPut(fetchSpy)).toBe(true));
        expect(document.querySelector('.confirm-modal')).toBeNull();
    });

    it('凭证 openai 态 → 直接保存无确认提示', async () => {
        const { chat, fetchSpy } = await setupSwitch({ protocol: 'openai' });
        chat.chatDom.chatHeader.querySelector('.chat-model-badge').click();
        document.querySelector('.modal-overlay .ms-start').click();
        await vi.waitFor(() => expect(hasPut(fetchSpy)).toBe(true));
        expect(document.querySelector('.confirm-modal')).toBeNull();
    });
});

describe('T3 对话内模型切换 — 在途流式不被切换打断', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('切换模型不中止在途流式句柄；模型保存后 state 更新（下一请求由后端读新模型）', async () => {
        const { chat, state, tabs } = await loadModules();
        tabs.openTab(11);
        const abort = vi.fn();
        tabs.updateTab(11, { isStreaming: true, activeStream: { abort } });
        state.conversations = [{ id: 11, title: '会话A', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }];
        state.models = {
            providers: [
                { key: 'claude', name: 'Claude (Anthropic)', models: ['claude-sonnet-5'] },
                { key: 'deepseek', name: 'DeepSeek', models: ['deepseek-chat'] },
            ],
        };
        state.credentialsProtocol = 'openai';
        const fetchSpy = makeApiMock({});
        fetchSpy.mockImplementation((url, options = {}) => {
            if (String(url).endsWith('/api/conversations/11') && options?.method === 'PUT') {
                return mockJson({ id: 11, ...JSON.parse(options.body) });
            }
            return makeApiMock({})(url, options);
        });
        // api 经 fetch 注入（无需显式 import — chat 模块已绑定 setFetch seam）
        const api = await import('../js/api.js');
        api.setFetch(fetchSpy);
        chat.setChatHooks({ refreshConversations: () => {} });
        chat.renderChatHeader(11);

        // 在途流式中触发模型切换（点徽标 → 选 deepseek → 确认）
        chat.chatDom.chatHeader.querySelector('.chat-model-badge').click();
        const overlay = document.querySelector('.modal-overlay');
        const prov = overlay.querySelector('#ms-provider');
        prov.value = 'deepseek';
        prov.dispatchEvent(new Event('change', { bubbles: true }));
        overlay.querySelector('#ms-model').value = 'deepseek-chat';
        overlay.querySelector('.ms-start').click();

        await vi.waitFor(() => {
            expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations/11') && o?.method === 'PUT')).toBe(true);
        });
        // 在途流式句柄未被 abort（切换不打断在途流）
        expect(abort).not.toHaveBeenCalled();
        // 会话模型已保存 → 下一发送由后端读取新模型
        expect(state.conversations[0].model_provider).toBe('deepseek');
        expect(state.conversations[0].model_name).toBe('deepseek-chat');
        // 在途流仍处于 streaming 态（未因切换被中断写回）
        expect(tabs.getTab(11).isStreaming).toBe(true);
    });
});

describe('T6 重生成 — 末条 assistant 气泡重生成闭环', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** 重生成前置：缓存 [user(1), assistant(2)]；服务端重生成后返回 [user(1), assistant(3)] */
    const REGEN_MSGS = [msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复')];
    const REGEN_SERVER = [msg(1, 'user', '你好'), msg(3, 'assistant', '新回复')];

    it('末条 assistant 气泡渲染重生成按钮；点击 → conversations.regenerate(11)（缺省无 message_id）→ settleTurn 重载渲染新回复且服务端消息 id 进缓存', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: REGEN_MSGS });
        const fetchSpy = makeApiMock({
            regenerateResult: { reply: '新回复', message_id: 3, conversation_id: 11 },
            messagesByConv: { 11: REGEN_SERVER },
        });
        api.setFetch(fetchSpy);
        const refresh = vi.fn();
        chat.setChatHooks({ refreshConversations: refresh });

        chat.renderMessages();

        // 末条 assistant 气泡携带重生成按钮
        const asstBubble = chat.chatDom.chatMessages.querySelector('.message.assistant');
        const regenBtn = asstBubble.querySelector('.btn-regenerate');
        expect(regenBtn).not.toBeNull();

        regenBtn.click();

        // 端点调用契约：POST /api/conversations/11/regenerate，无请求体（缺省末条 assistant）
        await vi.waitFor(() => {
            expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations/11/regenerate') && o?.method === 'POST')).toBe(true);
        });
        const regenCall = fetchSpy.mock.calls.find(([u, o]) => String(u).endsWith('/api/conversations/11/regenerate') && o?.method === 'POST');
        expect(regenCall[1].body).toBeUndefined();

        // 统一结算入口 settleTurn 重载 → 服务端列表整体进缓存（新消息携带服务端 message_id=3 — W2 增量审核 #2）
        await vi.waitFor(() => {
            expect(tabs.getTab(11).messages).toEqual(REGEN_SERVER);
        });
        // 新回复渲染、旧回复消失
        expect(chat.chatDom.chatMessages.textContent).toContain('新回复');
        expect(chat.chatDom.chatMessages.textContent).not.toContain('旧回复');
        // 重渲染后新气泡仍携带重生成按钮（重新绑定）
        expect(chat.chatDom.chatMessages.querySelector('.message.assistant .btn-regenerate')).not.toBeNull();
        // 发送流程末尾刷新勾子被调
        expect(refresh).toHaveBeenCalled();
    });

    it('在途守卫：进行中显示 thinking + 按钮禁用；同一对话重复触发被拦截（只发一次真实请求）', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: REGEN_MSGS });

        let resolveRegen;
        const regenSpy = vi.spyOn(api.conversations, 'regenerate')
            .mockReturnValue(new Promise((r) => { resolveRegen = r; }));
        const settleSpy = vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        chat.setChatHooks({ refreshConversations: () => {} });
        chat.renderMessages();
        const regenBtn = chat.chatDom.chatMessages.querySelector('.btn-regenerate');

        regenBtn.click(); // 第一次触发 — 在途

        // 进行中状态：thinking 指示器 + 重生成按钮禁用
        expect(chat.chatDom.chatMessages.querySelector('.thinking-indicator')).not.toBeNull();
        expect(regenBtn.disabled).toBe(true);

        // 在途守卫：重复触发（按钮点击 / 直接调用）被拦截 — 只发一次真实请求
        regenBtn.click();
        await chat.regenerateLastReply();
        expect(regenSpy).toHaveBeenCalledTimes(1);
        expect(settleSpy).not.toHaveBeenCalled();

        // 结算后：settle 委托参数带服务端新消息 id（messageId 透传）+ 进行中 UI 复原
        resolveRegen({ reply: '新回复', message_id: 3, conversation_id: 11 });
        await vi.waitFor(() => expect(settleSpy).toHaveBeenCalledTimes(1));
        const call = settleSpy.mock.calls[0][0];
        expect(call.convId).toBe(11);
        expect(call.messageId).toBe(3);
        expect(call.settleIndex).toBe(-1);
        await vi.waitFor(() => {
            expect(chat.chatDom.chatMessages.querySelector('.thinking-indicator')).toBeNull();
            expect(regenBtn.disabled).toBe(false);
        });

        // 在途清除 → 可再次触发
        await chat.regenerateLastReply();
        expect(regenSpy).toHaveBeenCalledTimes(2);
    });

    it('失败 → 走错误条通道（不写进消息列表）+ settleTurn 不调用 + thinking/按钮复原 + 在途清除', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: REGEN_MSGS });

        const regenSpy = vi.spyOn(api.conversations, 'regenerate').mockRejectedValue(new Error('重生成端点错误'));
        const settleSpy = vi.spyOn(ss, 'settleTurn');
        chat.setChatHooks({ refreshConversations: () => {} });
        chat.renderMessages();
        const regenBtn = chat.chatDom.chatMessages.querySelector('.btn-regenerate');

        regenBtn.click();

        await vi.waitFor(() => {
            // 错误经既有错误通道渲染（与 messages.chat 同一 catch 路径 — W2 增量审核 #1）
            const bar = chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
            expect(bar).not.toBeNull();
            expect(bar.textContent).toContain('重生成端点错误');
            // 不写进消息列表 — 缓存保持原状
            expect(tabs.getTab(11).messages).toEqual(REGEN_MSGS);
            expect(chat.chatDom.chatMessages.querySelector('.message')).not.toBeNull();
            expect(chat.chatDom.chatMessages.textContent).toContain('旧回复');
        });
        expect(settleSpy).not.toHaveBeenCalled();

        // 进行中 UI 复原：thinking 移除 + 按钮恢复可用
        expect(chat.chatDom.chatMessages.querySelector('.thinking-indicator')).toBeNull();
        expect(regenBtn.disabled).toBe(false);

        // 在途清除 → 可再次触发
        await chat.regenerateLastReply();
        expect(regenSpy).toHaveBeenCalledTimes(2);
    });

    it('Falsify:无活动 tab → no-op 不调 regenerate、不调刷新', async () => {
        const { chat, api } = await loadModules();
        const regenSpy = vi.spyOn(api.conversations, 'regenerate');
        const refresh = vi.fn();
        chat.setChatHooks({ refreshConversations: refresh });

        await chat.regenerateLastReply();

        expect(regenSpy).not.toHaveBeenCalled();
        expect(refresh).not.toHaveBeenCalled();
    });

    it('Falsify:流式在途 tab（isStreaming）→ no-op 不调 regenerate', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: REGEN_MSGS, isStreaming: true });
        const regenSpy = vi.spyOn(api.conversations, 'regenerate');

        await chat.regenerateLastReply();

        expect(regenSpy).not.toHaveBeenCalled();
    });

    it('Falsify:无末条 assistant（仅 user 消息）→ 不渲染重生成按钮', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '你好')] });
        chat.renderMessages();
        expect(chat.chatDom.chatMessages.querySelector('.btn-regenerate')).toBeNull();
    });
});

describe('错误条会话隔离（F-50 — renderSendError 透传会话身份）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** 构造恒失败的 fetch（任意 chat 请求都 throw） */
    function failFetch() {
        const spy = makeApiMock({ chatResult: { reply: 'x' } });
        spy.mockImplementation(async () => { throw new Error('boom'); });
        return spy;
    }

    it('非流式失败 → 错误条携带 data-conv=会话id（renderSendError 透传 conversationId）', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;
        api.setFetch(failFetch());
        vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        chat.setChatHooks({ refreshConversations: () => {} });

        chat.chatDom.chatInput.value = '你好';
        await chat.handleSend();

        const bar = chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
        expect(bar).not.toBeNull();
        expect(bar.dataset.conv).toBe('11');
    });

    it('流式 onError → 错误条携带 data-conv=会话id（renderSendError 透传 conversationId）', async () => {
        const env = await loadModules();
        let captured = null;
        vi.spyOn(env.api, 'chatStream').mockImplementation((data, cbs) => {
            captured = { data, cbs };
            return { abort: vi.fn(), done: Promise.resolve() };
        });
        env.tabs.openTab(11);
        env.api.setFetch(makeApiMock({ messagesByConv: { 11: [msg(1, 'user', '你好'), msg(2, 'assistant', '好的')] } }));
        env.chat.setChatHooks({ refreshConversations: () => {} });

        env.chat.chatDom.chatInput.value = '你好';
        await env.chat.handleSend();
        captured.cbs.onError(new Error('模型超时'));

        const bar = env.chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
        expect(bar).not.toBeNull();
        expect(bar.textContent).toContain('模型超时');
        expect(bar.dataset.conv).toBe('11');
    });

    it('重生成失败 → 错误条携带 data-conv=会话id', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复')] });
        vi.spyOn(api.conversations, 'regenerate').mockRejectedValue(new Error('重生成端点错误'));
        vi.spyOn(ss, 'settleTurn');
        chat.setChatHooks({ refreshConversations: () => {} });

        chat.renderMessages();
        chat.chatDom.chatMessages.querySelector('.btn-regenerate').click();
        await vi.waitFor(() => {
            const bar = chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
            expect(bar).not.toBeNull();
            expect(bar.dataset.conv).toBe('11');
        });
    });

    it('并发：不同会话连续失败 → 两个错误条并存（各自 data-conv）', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        chat.chatDom.toggleStream.checked = false;
        api.setFetch(failFetch());
        vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        chat.setChatHooks({ refreshConversations: () => {} });

        tabs.openTab(11);
        chat.chatDom.chatInput.value = '会话A';
        await chat.handleSend();

        tabs.openTab(22);
        chat.chatDom.chatInput.value = '会话B';
        await chat.handleSend();

        const bars = chat.chatDom.chatMessages.parentElement.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(2);
        expect([...bars].map((b) => b.dataset.conv).sort()).toEqual(['11', '22']);
    });

    it('并发：同会话连续两次失败 → 仅一条错误条（data-conv 幂等替换）', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        chat.chatDom.toggleStream.checked = false;
        api.setFetch(failFetch());
        vi.spyOn(ss, 'settleTurn').mockResolvedValue(undefined);
        chat.setChatHooks({ refreshConversations: () => {} });

        tabs.openTab(11);
        chat.chatDom.chatInput.value = '第一次';
        await chat.handleSend();
        chat.chatDom.chatInput.value = '第二次';
        await chat.handleSend();

        const bars = chat.chatDom.chatMessages.parentElement.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(1);
        expect(bars[0].dataset.conv).toBe('11');
    });
});
