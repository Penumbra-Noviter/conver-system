/**
 * list-views 深模块测试（C4 — 角色/对话列表视图从 app.js 下沉）
 *
 * 覆盖（自 app.test.js 迁移，断言语义与文案逐字不变）：
 *   - 角色管理委托：chat-with（模型选择 → 创建 → 切视图 → 激活 → 聚焦）/
 *     取消 / 创建失败 / edit-char / edit 失败 / export-char / 删角色失败 /
 *     删对话失败 / btn-create-character + btn-new-chat（9 用例）
 *   - 级联删除入口：删角色入口（closeConversationsAndResettle 收到该角色
 *     全部会话 ids + reloadList:true）/ 删对话入口（ids:[11]）/
 *     Falsify:删对话后列表重载失败（真实级联 — 无 unhandled rejection +
 *     错误 toast + tab 已关）（3 用例）
 *   - 对话列表打开委托：点击会话项 → activateConversation（忽略删除按钮）
 *   - 导入接线：成功 / JSON 解析失败引导向导 / 导入 API 失败引导向导 /
 *     btn-import-character / 未选文件 no-op（5 用例）
 *   - 数据加载失败：角色列表加载失败 → 错误 toast（loadCharacters 不崩溃）
 *   - initListViews 幂等与契约破坏 Falsify（重复调用仅更新钩子；DOM 缺失 no-op）
 *
 * 挂载模式：search-view.test.js 先例 — 最小 DOM 子集 + 模块直 import +
 *   fetch mock 路由；注入接线（setActivationHooks / setChatHooks /
 *   setCascadeHooks / initListViews）镜像 app.js 模块级注入区（本模块在
 *   隔离测试中的 seam）。弹窗挂载于 document.body 即可。
 * 注意（C4 下沉 seam）：成功/失败 toast 由 utils.js 的 showSuccess/showError
 *   薄封装发出（同模块内调 showToast），跨模块 namespace spy 无法拦截 ——
 *   toast 断言改为断言渲染产物（.toast.toast-success/.toast-error 文本逐字），
 *   即公共行为 seam（文案与收口前逐字一致）。
 */
import { describe, it, expect, vi, beforeEach, afterEach, beforeAll } from 'vitest';

/** 最小 DOM 子集 — 覆盖 list-views 自身 DOM（#character-grid / 创建/导入按钮 /
 * 导入 input / #conversation-list / #btn-new-chat）+ chatDom 全部 id
 * （list-views 经 chat.js 模块级查询；startChatWithCharacter 聚焦 #chat-input） */
const LIST_VIEWS_DOM_HTML = `
    <div id="conversation-list"></div>
    <button id="btn-new-chat"></button>

    <div id="character-grid"></div>
    <button id="btn-create-character"></button>
    <button id="btn-import-character"></button>
    <input type="file" id="character-import-input" style="display:none">

    <div id="chat-messages"></div>
    <textarea id="chat-input"></textarea>
    <button id="btn-send"></button>
    <input type="checkbox" id="toggle-stream" checked>
    <div id="chat-header"><span class="chat-title" id="chat-title-text"></span></div>
`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

const PROVIDERS = [
    { key: 'claude', name: 'Claude (Anthropic)', models: ['claude-sonnet-5'] },
];

/**
 * fetch mock 路由（globalThis.fetch — api.js doFetch seam 消费）
 * @param {object} opts
 * @param {Array} [opts.characters] - GET /api/characters 返回
 * @param {boolean} [opts.charactersFail] - GET /api/characters 返回 500（loadCharacters 失败路径）
 * @param {object} [opts.characterGet] - GET /api/characters/{id} 返回（编辑委托）
 * @param {Array} [opts.conversations] - GET /api/conversations 返回
 * @param {object} [opts.createdConv] - POST /api/conversations 返回（chat-with 创建）
 * @param {Array} [opts.providers] - GET /api/models 返回的 providers
 * @param {object} [opts.messagesByConv] - 各会话消息列表
 * @param {object} [opts.importResult] - POST /api/characters/import 返回（成功）或 {fail: Error}
 * @param {boolean} [opts.failReloadAfterDelete] - 删除后列表重载（第 2 次 GET conversations）返回 500
 */
function makeRoute({ characters = [], characterGet = null,
    conversations = [], createdConv = null, providers = PROVIDERS,
    messagesByConv = {}, importResult = null,
    charactersFail = false, failReloadAfterDelete = false } = {}) {
    let convListCalls = 0;
    return async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        const method = options.method || 'GET';

        if (path === '/api/characters' && method === 'GET') {
            if (charactersFail) return mockJson({ detail: 'boom' }, 500);
            return mockJson(characters);
        }
        if (path === '/api/characters/import' && method === 'POST') {
            if (importResult?.fail) return mockJson({ detail: importResult.fail }, 400);
            return mockJson(importResult ?? { id: 9, name: '新角色' });
        }
        const charMatch = path.match(/^\/api\/characters\/(\d+)$/);
        if (charMatch) {
            if (method === 'DELETE') return mockJson(null, 204);
            if (characterGet === null) return mockJson({ detail: 'not found' }, 404);
            return mockJson(characterGet);
        }

        if (path === '/api/conversations' && method === 'GET') {
            convListCalls++;
            if (failReloadAfterDelete && convListCalls > 1) return mockJson({ detail: 'boom' }, 500);
            return mockJson(conversations);
        }
        if (path === '/api/conversations' && method === 'POST') return mockJson(createdConv);
        const convMatch = path.match(/^\/api\/conversations\/(\d+)$/);
        if (convMatch) {
            if (method === 'DELETE') return mockJson(null, 204);
            const conv = conversations.find((c) => c.id === Number(convMatch[1]));
            return conv ? mockJson(conv) : mockJson({ detail: 'not found' }, 404);
        }
        const listMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
        if (listMatch && method === 'GET') return mockJson(messagesByConv[Number(listMatch[1])] ?? []);
        if (path === '/api/models' && method === 'GET') return mockJson({ providers });
        throw new Error(`未 mock 的请求: ${path}`);
    };
}

/**
 * 加载全新 list-views 模块（DOM 先就位 + fetch 路由先注入）。
 * 注入接线镜像 app.js 模块级注入区：setActivationHooks / setChatHooks /
 *   setCascadeHooks / initListViews — 列表视图在隔离测试中的 seam。
 * @param {Function} route - fetch mock 路由
 * @param {object} [opts]
 * @param {boolean} [opts.loadLists=true] - 是否预载角色/对话列表（loadCharacters + loadConversations）
 */
async function loadModules(route, { loadLists = true } = {}) {
    vi.resetModules();
    sessionStorage.clear();
    document.body.innerHTML = LIST_VIEWS_DOM_HTML;
    const fetchSpy = vi.fn(route);
    globalThis.fetch = fetchSpy;

    const listViews = await import('../js/list-views.js');
    const chat = await import('../js/chat.js');
    const state = (await import('../js/state.js')).state;
    const tabs = await import('../js/tabs.js');
    const cascade = await import('../js/cascade.js');
    const api = await import('../js/api.js');
    const utils = await import('../js/utils.js');
    const activation = await import('../js/conversation-activation.js');

    activation.setActivationHooks({
        renderConversations: listViews.renderConversations,
        switchView: (viewName) => { state.currentView = viewName; },
        showError: utils.showError,
    });
    chat.setChatHooks({
        refreshConversations: listViews.loadConversations,
        syncConversationListTitle: listViews.syncConversationListTitle,
    });
    cascade.setCascadeHooks({
        renderConversations: listViews.renderConversations,
        loadConversations: listViews.loadConversations,
        activateConversation: activation.activateConversation,
        showEmptyState: activation.showEmptyState,
        refreshSendButton: chat.refreshSendButton,
    });
    listViews.initListViews({
        switchView: (viewName) => { state.currentView = viewName; },
    });

    if (loadLists) {
        await listViews.loadCharacters();
        await listViews.loadConversations();
    }
    return { listViews, chat, state, tabs, cascade, api, utils, activation, fetchSpy };
}

const msg = (id, role, content) => ({ id, role, content });

describe('list-views 角色管理委托 — 四类按钮与失败兜底', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('chat-with 委托：模型选择器 → 创建对话 → 切 chat 视图 → 激活会话 + 输入聚焦', async () => {
        const { tabs, state, fetchSpy } = await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
            conversations: [{ id: 21, title: '与 角色A 的对话', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }],
            createdConv: { id: 21, title: '与 角色A 的对话', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' },
        }));

        document.querySelector('#character-grid .chat-with').click();
        // 模型选择器（真实 modal）→ 默认选中 → 开始对话
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click();

        await vi.waitFor(() => expect(tabs.getTab(21)?.messages).toBeDefined());
        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations') && o?.method === 'POST'))
            .toBe(true);
        expect(state.currentView).toBe('chat');
        expect(tabs.getActiveTab()?.conversationId).toBe(21);
        expect(tabs.getTab(21).characterId).toBe(1);
        expect(document.activeElement).toBe(document.querySelector('#chat-input')); // 创建即聚焦
    });

    it('chat-with 取消模型选择 → 不创建对话（no-op）', async () => {
        const { fetchSpy } = await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
        }));
        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-cancel').click();
        await new Promise((r) => setTimeout(r, 0));

        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/conversations') && o?.method === 'POST'))
            .toBe(false);
    });

    it('Falsify:创建对话失败 → showAlert「创建对话失败: <原因>」', async () => {
        const { fetchSpy } = await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
        }));
        fetchSpy.mockImplementationOnce((url, options = {}) => {
            if (String(url).endsWith('/api/conversations') && options?.method === 'POST') {
                return Promise.resolve(mockJson({ detail: 'boom' }, 500));
            }
            return makeRoute({})(url, options);
        });
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');

        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click();

        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledWith('创建对话失败: boom'));
    });

    it('edit-char 委托：加载角色 → 打开编辑表单', async () => {
        const { fetchSpy } = await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
            characterGet: { id: 1, name: '角色A', personality: 'p' },
        }));

        document.querySelector('#character-grid .edit-char').click();
        await vi.waitFor(() => expect(document.querySelector('.character-form-modal')).not.toBeNull());
        expect(fetchSpy.mock.calls.some(([u]) => String(u).endsWith('/api/characters/1'))).toBe(true);
        expect(document.querySelector('.character-form-modal').textContent).toContain('编辑角色');
        document.querySelector('.character-form-modal .modal-close').click();
    });

    it('Falsify:edit-char 加载失败 → showAlert「加载角色信息失败」', async () => {
        await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
        }));
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');

        document.querySelector('#character-grid .edit-char').click();
        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledTimes(1));
        expect(alertSpy).toHaveBeenCalledWith(expect.stringContaining('加载角色信息失败'));
    });

    it('export-char 委托：downloadBlob 收到导出地址与文件名', async () => {
        const { utils } = await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
        }));
        const downloadSpy = vi.spyOn(utils, 'downloadBlob');

        document.querySelector('#character-grid .export-char').click();

        expect(downloadSpy).toHaveBeenCalledWith('/api/characters/1/export', '角色A.json');
    });

    it('Falsify:删角色 API 失败 → showAlert「删除失败: <原因>」', async () => {
        const { fetchSpy } = await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 1 }],
        }));
        fetchSpy.mockImplementationOnce((url) => {
            if (String(url).endsWith('/api/characters/1')) return Promise.resolve(mockJson({ detail: 'boom' }, 500));
            return Promise.resolve(mockJson([{ id: 1, name: '角色A', conversation_count: 1 }]));
        });
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');

        document.querySelector('#character-grid .delete-char').click();
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledTimes(1));

        expect(alertSpy).toHaveBeenCalledWith('删除失败: boom');
    });

    it('Falsify:删对话 API 失败 → showAlert「删除失败: <原因>」', async () => {
        const { fetchSpy } = await loadModules(makeRoute({
            conversations: [{ id: 11, title: 'A', message_count: 2 }],
        }));
        fetchSpy.mockImplementationOnce((url) => {
            if (String(url).endsWith('/api/conversations/11')) return Promise.resolve(mockJson({ detail: 'boom' }, 500));
            return Promise.resolve(mockJson([{ id: 11, title: 'A', message_count: 2 }]));
        });
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');

        document.querySelector('#conversation-list .btn-delete-conv').click();
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledTimes(1));

        expect(alertSpy).toHaveBeenCalledWith('删除失败: boom');
    });

    it('btn-create-character → 打开创建向导弹窗；btn-new-chat → 切到角色视图', async () => {
        const { state } = await loadModules(makeRoute({}));

        document.querySelector('#btn-create-character').click();
        await vi.waitFor(() => expect(document.querySelector('.wizard-modal')).not.toBeNull());

        document.querySelector('#btn-new-chat').click();
        expect(state.currentView).toBe('characters');
    });
});

describe('list-views 级联删除入口 — 删角色 / 删对话', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('删角色入口：确认后 closeConversationsAndResettle 收到该角色全部会话 ids + reloadList:true', async () => {
        const { cascade, tabs, fetchSpy } = await loadModules(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 1 }],
        }));
        tabs.openTab(11);
        tabs.updateTab(11, { characterId: 1 });
        const cascadeSpy = vi.spyOn(cascade, 'closeConversationsAndResettle').mockResolvedValue(undefined);

        document.querySelector('#character-grid .delete-char').click();
        document.querySelector('.modal-overlay .confirm-ok').click();

        await vi.waitFor(() => expect(cascadeSpy).toHaveBeenCalledTimes(1));
        expect(cascadeSpy).toHaveBeenCalledWith({ ids: [11], reloadList: true });
        expect(fetchSpy.mock.calls.some(([url, opts]) =>
            String(url).endsWith('/api/characters/1') && opts?.method === 'DELETE')).toBe(true);
    });

    it('删对话入口：确认后 closeConversationsAndResettle 收到 {ids:[11],reloadList:true}', async () => {
        const { cascade, fetchSpy } = await loadModules(makeRoute({
            conversations: [{ id: 11, title: 'A', message_count: 2 }],
        }));
        const cascadeSpy = vi.spyOn(cascade, 'closeConversationsAndResettle').mockResolvedValue(undefined);

        document.querySelector('#conversation-list .btn-delete-conv').click();
        document.querySelector('.modal-overlay .confirm-ok').click();

        await vi.waitFor(() => expect(cascadeSpy).toHaveBeenCalledTimes(1));
        expect(cascadeSpy).toHaveBeenCalledWith({ ids: [11], reloadList: true });
        expect(fetchSpy.mock.calls.some(([url, opts]) =>
            String(url).endsWith('/api/conversations/11') && opts?.method === 'DELETE')).toBe(true);
    });

    it('Falsify:删对话后列表重载失败 → 无 unhandled rejection + 错误 toast + tab 已关（真实级联）', async () => {
        const { tabs, fetchSpy } = await loadModules(makeRoute({
            conversations: [{ id: 11, title: 'A', message_count: 2 }],
            failReloadAfterDelete: true,
        }));

        document.querySelector('#conversation-list .btn-delete-conv').click();
        document.querySelector('.modal-overlay .confirm-ok').click();

        // 错误 toast（utils.showError → showToast 同模块调用，断言渲染产物 —
        //   C4 下沉后 toast 语义在 utils.js 薄封装内，DOM 即公共行为 seam）
        await vi.waitFor(() => {
            const toast = document.querySelector('.toast.toast-error');
            expect(toast).not.toBeNull();
            expect(toast.textContent).toBe('加载对话列表失败');
        });
        // 真实级联收口已生效：tab 关闭（不依赖列表重载成功）
        expect(tabs.getTabs()).toHaveLength(0);
        // 删除本身已发出（列表重载失败发生在删除之后）
        expect(fetchSpy.mock.calls.some(([url, opts]) =>
            String(url).endsWith('/api/conversations/11') && opts?.method === 'DELETE')).toBe(true);
    });
});

describe('list-views 对话列表打开委托', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('点击会话项 → activateConversation 打开 tab（忽略删除按钮点击）', async () => {
        const { tabs } = await loadModules(makeRoute({
            conversations: [{ id: 11, title: 'A', message_count: 2 }],
        }));

        document.querySelector('#conversation-list .conversation-item').click();

        await vi.waitFor(() => expect(tabs.getTab(11)).toBeDefined());
        expect(tabs.getActiveTab()?.conversationId).toBe(11);
    });
});

describe('list-views 导入接线', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** jsdom 26 未实现 Blob.text()/File.text()（真实浏览器标准 API）—
     *  经 FileReader 补齐，使 handleCharacterImport 的 file.text() 路径可测 */
    beforeAll(() => {
        if (!window.File.prototype.text) {
            window.File.prototype.text = function () {
                return new Promise((resolve, reject) => {
                    const reader = new FileReader();
                    reader.onload = () => resolve(reader.result);
                    reader.onerror = () => reject(reader.error);
                    reader.readAsText(this);
                });
            };
        }
    });

    /** 构造 File 并注入 #character-import-input.files 后派发 change */
    function dispatchImportFile(content, name = 'card.json') {
        const file = new File([content], name, { type: 'application/json' });
        const input = document.querySelector('#character-import-input');
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    it('导入成功：JSON 卡 → POST import → toast 成功 + 列表刷新 + 输入清空', async () => {
        const { fetchSpy } = await loadModules(makeRoute({
            importResult: { id: 5, name: '新角色' },
        }));

        dispatchImportFile(JSON.stringify({ name: '新角色' }));

        // 成功 toast（渲染产物断言 — C4 后 showSuccess 为 utils.js 内薄封装）
        await vi.waitFor(() => {
            const toast = document.querySelector('.toast.toast-success');
            expect(toast).not.toBeNull();
            expect(toast.textContent).toBe('成功导入角色「新角色」');
        });
        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/characters/import') && o?.method === 'POST'))
            .toBe(true);
        expect(document.querySelector('#character-import-input').value).toBe(''); // finally 清空
    });

    it('Falsify:JSON 解析失败 → 错误 toast + 引导到创建向导', async () => {
        await loadModules(makeRoute({}));

        dispatchImportFile('not-json{{{');

        await vi.waitFor(() => {
            const toast = document.querySelector('.toast.toast-error');
            expect(toast).not.toBeNull();
            expect(toast.textContent).toBe('不是有效的 JSON 文件');
        });
        // 引导弹窗 → 确认「打开向导」→ 创建向导弹窗
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(document.querySelector('.wizard-modal')).not.toBeNull());
    });

    it('Falsify:导入 API 失败 → 错误 toast（含后端原因）+ 引导到创建向导', async () => {
        await loadModules(makeRoute({
            importResult: { fail: '卡格式不受支持' },
        }));

        dispatchImportFile(JSON.stringify({ name: 'x' }));

        await vi.waitFor(() => {
            const toast = document.querySelector('.toast.toast-error');
            expect(toast).not.toBeNull();
            expect(toast.textContent).toBe('卡格式不受支持');
        });
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(document.querySelector('.wizard-modal')).not.toBeNull());
    });

    it('btn-import-character 点击 → 触发文件选择器（no-op 不抛错）', () => {
        return loadModules(makeRoute({})).then(() => {
            expect(() => document.querySelector('#btn-import-character').click()).not.toThrow();
        });
    });

    it('Falsify:未选文件（files 为空）→ 导入 no-op 不抛错', () => {
        return loadModules(makeRoute({})).then(({ fetchSpy }) => {
            document.querySelector('#character-import-input').dispatchEvent(new Event('change', { bubbles: true }));

            expect(document.querySelector('.toast')).toBeNull();
            expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/characters/import'))).toBe(false);
        });
    });
});

describe('list-views 数据加载失败 — Falsify 兜底', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('角色列表加载失败 → 错误 toast（loadCharacters 不崩溃）', async () => {
        const { listViews } = await loadModules(makeRoute({ charactersFail: true }), { loadLists: false });

        await listViews.loadCharacters();

        const toast = document.querySelector('.toast.toast-error');
        expect(toast).not.toBeNull();
        expect(toast.textContent).toBe('加载角色列表失败');
    });
});

describe('list-views initListViews — 幂等与契约破坏 Falsify', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('重复调用 initListViews：不重复绑定事件，钩子更新为最新（btn-new-chat 用最新 switchView）', async () => {
        const env = await loadModules(makeRoute({}), { loadLists: false });
        // 重新注入新 switchView 钩子 → btn-new-chat 走新钩子（幂等：仅更新钩子不重复绑定）
        const latestSwitch = vi.fn((v) => { env.state.currentView = v; });
        env.listViews.initListViews({ switchView: latestSwitch });

        document.querySelector('#btn-new-chat').click();
        expect(latestSwitch).toHaveBeenCalledWith('characters');
        expect(env.state.currentView).toBe('characters');
    });

    it('Falsify:DOM 契约被破坏(元素缺失) → initListViews no-op 不抛错', async () => {
        vi.resetModules();
        sessionStorage.clear();
        document.body.innerHTML = ''; // 无列表/角色 DOM 契约
        const listViews = await import('../js/list-views.js');
        expect(() => listViews.initListViews({ switchView: () => {} })).not.toThrow();
    });
});
