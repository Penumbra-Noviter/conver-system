/**
 * 消息级编辑重发 + 删除单条消息 前端契约锁（工单 03）
 *
 * 覆盖（spec message-edit-resend §前端契约）：
 *   1. api.js messages.edit → PUT /messages/{id} body {content}；messages.delete →
 *      DELETE /messages/{id}（204 → null）
 *   2. renderMessages 开启 canEdit/canDelete → 气泡按角色渲染 edit/delete 按钮，
 *      经 data-message-id 定位绑定
 *   3. editMessage：编辑弹窗 → showConfirm（danger 明示「删除该消息之后的所有对话」）
 *      → messages.edit → settleTurn 重载（同 regenerate）
 *   4. deleteMessage：showConfirm（danger，按 user/assistant 区分警示）→ messages.delete
 *      → 简单重载（messages.list + renderMessages，不套 settleTurn）
 *   5. 失败走既有错误条通道（renderSendError），不写进消息列表
 *
 * 挂载模式：jsdom + vi.resetModules() + 内联 chatDom + fetch mock（api.js setFetch
 * seam），与 chat.test.js 同构。断言纪律：优先 spy 调用参数与状态还原，DOM 断言
 * 仅关键文案。
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

// css 区 Mod 注入接线：mock 深模块（真实契约由 mod-css.test.js 锁定，本文件只测
// 编辑/删除行为，不关心 css 注入）
vi.mock('../js/mod-css.js', () => ({
    applyCharacterCss: vi.fn(),
    removeCharacterCss: vi.fn(),
    __all__: ['applyCharacterCss', 'removeCharacterCss'],
}));

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

/** 加载全新 chat + tabs + api + stream-session 实例（DOM 先就位） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM_HTML;
    const chat = await import('../js/chat.js');
    const tabs = await import('../js/tabs.js');
    const api = await import('../js/api.js');
    const ss = await import('../js/stream-session.js');
    return { chat, tabs, api, ss };
}

const msg = (id, role, content) => ({ id, role, content });

/**
 * fetch mock 路由（api.js doFetch seam 消费）
 * PUT/DELETE /api/messages/{id} → 编辑/删除；GET /api/conversations/{id}/messages → 列表
 */
function makeApiMock({
    editResult = null,
    editFail = false,
    deleteFail = false,
    messagesByConv = {},
} = {}) {
    return vi.fn(async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        const method = options.method || 'GET';
        const m = path.match(/^\/api\/messages\/(\d+)$/);
        if (m && method === 'PUT') {
            if (editFail) return mockJson({ detail: '编辑端点错误' }, 400);
            return mockJson(editResult ?? { reply: '新回复', message_id: 99, conversation_id: Number(m[1]) });
        }
        if (m && method === 'DELETE') {
            if (deleteFail) return mockJson({ detail: '删除端点错误' }, 500);
            return Promise.resolve({ ok: true, status: 204, json: async () => { throw new Error('不应调用 json()'); } });
        }
        const listMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
        if (listMatch && method === 'GET') {
            return mockJson(messagesByConv[Number(listMatch[1])] ?? []);
        }
        throw new Error(`未 mock 的请求: ${path}`);
    });
}

beforeEach(() => {
    vi.restoreAllMocks();
});

afterEach(() => {
    vi.restoreAllMocks();
    document.body.innerHTML = '';
});

describe('api.js messages.edit / messages.delete — 端点契约', () => {
    it('messages.edit(5, content) → PUT /api/messages/5 body {content}', async () => {
        const { api } = await loadModules();
        const fetchMock = vi.fn(async () => mockJson({ reply: 'r', message_id: 9, conversation_id: 1 }));
        api.setFetch(fetchMock);

        const data = await api.messages.edit(5, '新内容');

        const [url, options] = fetchMock.mock.calls[0];
        expect(url).toBe('/api/messages/5');
        expect(options.method).toBe('PUT');
        expect(JSON.parse(options.body)).toEqual({ content: '新内容' });
        expect(data).toEqual({ reply: 'r', message_id: 9, conversation_id: 1 });
    });

    it('messages.delete(5) → DELETE /api/messages/5，204 返回 null（不解析 JSON）', async () => {
        const { api } = await loadModules();
        const fetchMock = vi.fn(async () => ({ ok: true, status: 204, json: async () => { throw new Error('不应调用 json()'); } }));
        api.setFetch(fetchMock);

        const data = await api.messages.delete(5);

        expect(data).toBeNull();
        expect(fetchMock).toHaveBeenCalledWith('/api/messages/5', expect.objectContaining({ method: 'DELETE' }));
    });
});

describe('renderMessages — edit/delete 按钮渲染与绑定（data-message-id 定位）', () => {
    it('开启 canEdit/canDelete → user 气泡渲染编辑+删除、assistant 气泡仅删除', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '你好'), msg(2, 'assistant', '回复')] });

        chat.renderMessages();

        expect(chat.chatDom.chatMessages.querySelector('.message.user .btn-edit-message')).not.toBeNull();
        expect(chat.chatDom.chatMessages.querySelector('.message.user .btn-delete-message')).not.toBeNull();
        expect(chat.chatDom.chatMessages.querySelector('.message.assistant .btn-edit-message')).toBeNull();
        expect(chat.chatDom.chatMessages.querySelector('.message.assistant .btn-delete-message')).not.toBeNull();
    });

    it('无 id 的瞬时 user 消息（流式占位）→ 不渲染编辑/删除按钮', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ role: 'user', content: '在途' }, { role: 'assistant', content: '部分', streaming: true }] });

        chat.renderMessages();

        expect(chat.chatDom.chatMessages.querySelector('.btn-edit-message')).toBeNull();
        expect(chat.chatDom.chatMessages.querySelector('.btn-delete-message')).toBeNull();
    });
});

describe('editMessage — 编辑重发闭环', () => {
    /** 前置：缓存 [user(1), assistant(2), user(3)]，编辑 user(3)（非末条 assistant） */
    const EDIT_MSGS = [msg(1, 'user', '第一条'), msg(2, 'assistant', '旧回复'), msg(3, 'user', '要改的')];
    const EDIT_SERVER = [msg(1, 'user', '第一条'), msg(2, 'assistant', '旧回复'), msg(3, 'user', '新内容'), msg(99, 'assistant', '新回复')];

    it('编辑按钮点击 → 弹窗预填 → 二次确认（danger 明示删除其后所有对话）→ PUT messages.edit → settleTurn 重载', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: EDIT_MSGS });
        const fetchSpy = makeApiMock({
            editResult: { reply: '新回复', message_id: 99, conversation_id: 11 },
            messagesByConv: { 11: EDIT_SERVER },
        });
        api.setFetch(fetchSpy);
        const refresh = vi.fn();
        chat.setChatHooks({ refreshConversations: refresh });

        chat.renderMessages();
        const userBubbles = chat.chatDom.chatMessages.querySelectorAll('.message.user');
        expect(userBubbles).toHaveLength(2);
        userBubbles[1].querySelector('.btn-edit-message').click(); // 编辑 user(3)

        // 编辑弹窗：textarea 预填原内容
        await vi.waitFor(() => expect(document.querySelector('#edit-message-input')).not.toBeNull());
        expect(document.querySelector('#edit-message-input').value).toBe('要改的');
        document.querySelector('#edit-message-input').value = '新内容';
        document.querySelector('#edit-message-submit').click();

        // 二次确认（danger + 明示「删除该消息之后的所有对话」）
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        expect(document.querySelector('.confirm-modal .confirm-icon').classList.contains('danger')).toBe(true);
        expect(document.querySelector('.confirm-modal .confirm-message').textContent).toContain('删除该消息之后的所有对话');
        document.querySelector('.confirm-modal .confirm-ok').click();

        // 端点调用：PUT /api/messages/3 body {content: '新内容'}（data-message-id 定位到 user(3)）
        await vi.waitFor(() => {
            expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/messages/3') && o?.method === 'PUT')).toBe(true);
        });
        const editCall = fetchSpy.mock.calls.find(([u, o]) => String(u).endsWith('/api/messages/3') && o?.method === 'PUT');
        expect(JSON.parse(editCall[1].body)).toEqual({ content: '新内容' });

        // settleTurn 重载 → 缓存替换为新时间线（含新 assistant id=99）
        await vi.waitFor(() => {
            expect(tabs.getTab(11).messages).toEqual(EDIT_SERVER);
        });
        expect(chat.chatDom.chatMessages.textContent).toContain('新内容');
        expect(chat.chatDom.chatMessages.textContent).toContain('新回复');
        expect(refresh).toHaveBeenCalled();
    });

    it('二次确认取消 → 不调 messages.edit、缓存不变', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: EDIT_MSGS });
        const fetchSpy = makeApiMock({});
        api.setFetch(fetchSpy);
        chat.renderMessages();

        chat.chatDom.chatMessages.querySelector('.message.user .btn-edit-message').click();
        await vi.waitFor(() => expect(document.querySelector('#edit-message-input')).not.toBeNull());
        document.querySelector('#edit-message-submit').click();
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-cancel').click();

        await new Promise((r) => setTimeout(r, 0));
        expect(fetchSpy.mock.calls.some(([u, o]) => o?.method === 'PUT')).toBe(false);
        expect(tabs.getTab(11).messages).toEqual(EDIT_MSGS);
    });

    it('编辑内容为空（清空后保存）→ no-op（不弹确认、不请求、缓存不变）', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: EDIT_MSGS });
        const fetchSpy = makeApiMock({});
        api.setFetch(fetchSpy);
        chat.renderMessages();

        chat.chatDom.chatMessages.querySelector('.message.user .btn-edit-message').click();
        await vi.waitFor(() => expect(document.querySelector('#edit-message-input')).not.toBeNull());
        document.querySelector('#edit-message-input').value = '';
        document.querySelector('#edit-message-submit').click();

        await new Promise((r) => setTimeout(r, 0));
        expect(document.querySelector('.confirm-modal')).toBeNull(); // 空内容不进入二次确认
        expect(fetchSpy.mock.calls.some(([u, o]) => o?.method === 'PUT')).toBe(false);
        expect(tabs.getTab(11).messages).toEqual(EDIT_MSGS);
    });

    it('失败 → 错误条通道（不写消息列表）+ settleTurn 不调用 + 缓存不变', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: EDIT_MSGS });
        api.setFetch(makeApiMock({ editFail: true }));
        const settleSpy = vi.spyOn(ss, 'settleTurn');
        chat.renderMessages();

        chat.chatDom.chatMessages.querySelector('.message.user .btn-edit-message').click();
        await vi.waitFor(() => expect(document.querySelector('#edit-message-input')).not.toBeNull());
        document.querySelector('#edit-message-submit').click();
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-ok').click();

        await vi.waitFor(() => {
            const bar = chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
            expect(bar).not.toBeNull();
            expect(bar.textContent).toContain('编辑端点错误');
        });
        expect(tabs.getTab(11).messages).toEqual(EDIT_MSGS);
        expect(settleSpy).not.toHaveBeenCalled();
    });

    it('Falsify:无活动 tab → no-op 不请求', async () => {
        const { chat, api } = await loadModules();
        const editSpy = vi.spyOn(api.messages, 'edit');
        await chat.editMessage(5);
        expect(editSpy).not.toHaveBeenCalled();
    });

    it('Falsify:流式在途 tab（isStreaming）→ no-op 不请求', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: EDIT_MSGS, isStreaming: true });
        const editSpy = vi.spyOn(api.messages, 'edit');
        await chat.editMessage(3);
        expect(editSpy).not.toHaveBeenCalled();
    });
});

describe('deleteMessage — 删除单条消息闭环（角色感知确认）', () => {
    it('删 user → danger 确认（明示连带删除其后所有对话）→ DELETE → 简单重载（不套 settleTurn）', async () => {
        const { chat, tabs, api, ss } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '原文'), msg(2, 'assistant', '回复')] });
        const fetchSpy = makeApiMock({ messagesByConv: { 11: [] } }); // 删 user 后整段清空
        api.setFetch(fetchSpy);
        const settleSpy = vi.spyOn(ss, 'settleTurn');
        const refresh = vi.fn();
        chat.setChatHooks({ refreshConversations: refresh });

        chat.renderMessages();
        chat.chatDom.chatMessages.querySelector('.message.user .btn-delete-message').click();

        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        expect(document.querySelector('.confirm-modal .confirm-icon').classList.contains('danger')).toBe(true);
        expect(document.querySelector('.confirm-modal .confirm-message').textContent).toContain('连带删除其后的所有对话');
        document.querySelector('.confirm-modal .confirm-ok').click();

        await vi.waitFor(() => {
            expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/messages/1') && o?.method === 'DELETE')).toBe(true);
        });
        await vi.waitFor(() => expect(tabs.getTab(11).messages).toEqual([]));
        expect(settleSpy).not.toHaveBeenCalled(); // 删除无 ChatResponse，不套 settleTurn
        expect(chat.chatDom.chatMessages.innerHTML).toBe(chat.EMPTY_STATE_HTML);
        expect(refresh).toHaveBeenCalled();
    });

    it('删 assistant → danger 确认（明示仅删除该条回复）→ DELETE → 重载保留触发它的 user', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '原文'), msg(2, 'assistant', '回复')] });
        const fetchSpy = makeApiMock({ messagesByConv: { 11: [msg(1, 'user', '原文')] } }); // 删 assistant 仅删该条
        api.setFetch(fetchSpy);
        chat.renderMessages();

        chat.chatDom.chatMessages.querySelector('.message.assistant .btn-delete-message').click();

        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        expect(document.querySelector('.confirm-modal .confirm-message').textContent).toContain('仅删除该条回复');
        document.querySelector('.confirm-modal .confirm-ok').click();

        await vi.waitFor(() => {
            expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/messages/2') && o?.method === 'DELETE')).toBe(true);
        });
        await vi.waitFor(() => expect(tabs.getTab(11).messages).toEqual([msg(1, 'user', '原文')]));
    });

    it('二次确认取消 → 不调 messages.delete、缓存不变', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '原文'), msg(2, 'assistant', '回复')] });
        const fetchSpy = makeApiMock({});
        api.setFetch(fetchSpy);
        chat.renderMessages();

        chat.chatDom.chatMessages.querySelector('.message.user .btn-delete-message').click();
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-cancel').click();

        await new Promise((r) => setTimeout(r, 0));
        expect(fetchSpy.mock.calls.some(([u, o]) => o?.method === 'DELETE')).toBe(false);
        expect(tabs.getTab(11).messages).toEqual([msg(1, 'user', '原文'), msg(2, 'assistant', '回复')]);
    });

    it('失败 → 错误条通道（不写消息列表）+ 缓存不变', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '原文'), msg(2, 'assistant', '回复')] });
        api.setFetch(makeApiMock({ deleteFail: true }));
        chat.renderMessages();

        chat.chatDom.chatMessages.querySelector('.message.user .btn-delete-message').click();
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-ok').click();

        await vi.waitFor(() => {
            const bar = chat.chatDom.chatMessages.parentElement.querySelector('.chat-error-bar');
            expect(bar).not.toBeNull();
            expect(bar.textContent).toContain('删除端点错误');
        });
        expect(tabs.getTab(11).messages).toEqual([msg(1, 'user', '原文'), msg(2, 'assistant', '回复')]);
    });

    it('Falsify:无活动 tab → no-op 不请求', async () => {
        const { chat, api } = await loadModules();
        const deleteSpy = vi.spyOn(api.messages, 'delete');
        await chat.deleteMessage(5);
        expect(deleteSpy).not.toHaveBeenCalled();
    });

    it('Falsify:流式在途 tab（isStreaming）→ no-op 不请求', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', '原文'), msg(2, 'assistant', '回复')], isStreaming: true });
        const deleteSpy = vi.spyOn(api.messages, 'delete');
        await chat.deleteMessage(1);
        expect(deleteSpy).not.toHaveBeenCalled();
    });
});
