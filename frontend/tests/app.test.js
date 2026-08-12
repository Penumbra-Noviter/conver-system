/**
 * app.js 编排薄集成测试（ARC-9 C5 — C1/C2 seam 挂网后的编排区接线）
 *
 * 覆盖：
 *   - init 接线序列：四路数据加载 → setActivationHooks → restoreFromStorage
 *     （无记录 → 空态；有记录 → activateConversation(saveCurrent:false)）→
 *     initProviderDropdown → initSettingsPanel（清空回调触发级联收口）
 *   - 视图切换刷新分发：characters→loadCharacters、chat→loadConversations、
 *     settings→loadSettings+initProviderDropdown、search→100ms 聚焦
 *   - 级联四入口触发：删角色 / 删对话 / 清空全部（settings）/ tab-bar 关最后 tab
 *     —— 均断言经注入钩子触发 closeConversationsAndResettle 的正确参数
 *   - 搜索视图接线：输入 → 防抖搜索 → 结果点击经激活流程打开会话
 *   - Falsify：删对话后列表重载失败 → 无 unhandled rejection + 错误 toast + tab 已关
 *
 * 断言纪律：优先 spy 模块边界/注入钩子的调用序列与参数（cascade 收口参数、
 * api 层调用、utils.showToast），DOM 断言仅限关键类名/文案（empty-hint /
 * 空态 / 弹窗确认按钮）。内部逻辑（防抖细节 / mergeFreshList / 激活编排）由
 * search-view/cascade/stream-session/conversation-activation 直测钉住，不重复。
 *
 * 挂载模式：jsdom + vi.resetModules() + 内联最小 DOM 子集（index.html id 契约）
 * + globalThis.fetch mock 路由；与 conversation-activation.test.js 同构。
 * 注意：app.js 模块求值即触发 init()（浮空 promise）—— 以 fetch 调用数等待其完成。
 */
import { describe, it, expect, vi, beforeEach, afterEach, beforeAll } from 'vitest';

/** 最小 DOM 子集 — 覆盖 app.js / chat.js / search-view.js / settings-panel.js /
 * tab-bar.js 在模块求值期绑定的全部 id/class 契约（只读契约，取自 index.html） */
const APP_DOM_HTML = `
    <section id="view-chat" class="view active"></section>
    <section id="view-characters" class="view"></section>
    <section id="view-search" class="view"></section>
    <section id="view-settings" class="view"></section>
    <section id="view-guide" class="view"></section>

    <button class="nav-btn" data-view="chat"></button>
    <button class="nav-btn" data-view="characters"></button>
    <button class="nav-btn" data-view="search"></button>
    <button class="nav-btn" data-view="settings"></button>
    <button class="nav-btn" data-view="guide"></button>

    <button class="mobile-nav-btn" data-view="chat"></button>
    <button class="mobile-nav-btn" data-view="characters"></button>
    <button class="mobile-nav-btn" data-view="search"></button>
    <button class="mobile-nav-btn" data-view="settings"></button>
    <button class="mobile-nav-btn" data-view="guide"></button>

    <div id="conversation-list"></div>
    <button id="btn-new-chat"></button>

    <div id="character-grid"></div>
    <button id="btn-create-character"></button>
    <button id="btn-import-character"></button>
    <input type="file" id="character-import-input" style="display:none">

    <div id="chat-tabs" hidden></div>
    <div id="chat-messages"></div>
    <textarea id="chat-input"></textarea>
    <button id="btn-send"></button>
    <input type="checkbox" id="toggle-stream" checked>
    <div id="chat-header"><span class="chat-title" id="chat-title-text"></span></div>

    <input type="text" id="search-input" class="search-input" autocomplete="off">
    <button id="btn-search-clear"></button>
    <div id="search-results"></div>

    <select id="setting-default-provider"></select>
    <select id="setting-default-model"></select>
    <input type="text" id="setting-custom-model" style="display:none">
    <select id="setting-theme"></select>
    <input id="setting-claude-key"><input id="setting-claude-url">
    <input id="setting-openai-key"><input id="setting-openai-url">
    <input id="setting-sliding-window"><input id="setting-user-name">
    <button id="btn-save-settings"></button>
    <button id="btn-clear-all-convs"></button>
    <button id="btn-theme-toggle"></button>
    <button id="btn-collapse-sidebar"></button>
    <button id="btn-collapse-chat"></button>
    <button id="btn-expand-sidebar"></button>
    <button id="btn-expand-chat"></button>
    <div id="sidebar"></div>
    <div class="chat-sidebar"></div>
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
 * @param {boolean} [opts.charactersFail] - GET /api/characters 返回 500（init 加载失败路径）
 * @param {object} [opts.characterGet] - GET /api/characters/{id} 返回（编辑委托）
 * @param {Array} [opts.conversations] - GET /api/conversations 返回
 * @param {object} [opts.createdConv] - POST /api/conversations 返回（chat-with 创建）
 * @param {Array} [opts.providers] - GET /api/models 返回的 providers
 * @param {boolean} [opts.modelsFail] - GET /api/models 返回 500
 * @param {object} [opts.settings] - GET /api/settings 返回
 * @param {object} [opts.messagesByConv] - 各会话消息列表
 * @param {Array} [opts.searchResults] - GET /api/messages/search 返回
 * @param {object} [opts.importResult] - POST /api/characters/import 返回（成功）或 {fail: Error}
 * @param {boolean} [opts.failReloadAfterDelete] - 删除后列表重载（第 2 次 GET conversations）返回 500
 */
function makeRoute({ characters = [], characterGet = null,
    conversations = [], createdConv = null, providers = PROVIDERS,
    settings = {}, messagesByConv = {}, searchResults = [], importResult = null,
    failReloadAfterDelete = false } = {}) {
    let convListCalls = 0;
    return async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        const method = options.method || 'GET';

        if (path === '/api/characters' && method === 'GET') return mockJson(characters);
        if (path === '/api/characters' && method === 'POST') return mockJson({});
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
        if (path === '/api/conversations' && method === 'DELETE') return mockJson(null, 204);
        const convMatch = path.match(/^\/api\/conversations\/(\d+)$/);
        if (convMatch) {
            if (method === 'DELETE') return mockJson(null, 204);
            const conv = conversations.find((c) => c.id === Number(convMatch[1]));
            return conv ? mockJson(conv) : mockJson({ detail: 'not found' }, 404);
        }
        const listMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
        if (listMatch && method === 'GET') return mockJson(messagesByConv[Number(listMatch[1])] ?? []);
        if (path.startsWith('/api/messages/search') && method === 'GET') return mockJson(searchResults);
        if (path === '/api/models' && method === 'GET') return mockJson({ providers });
        if (path === '/api/settings' && method === 'GET') return mockJson(settings);
        throw new Error(`未 mock 的请求: ${path}`);
    };
}

/** 加载全新 app 模块（DOM 先就位 + fetch 路由先注入）并等待 init() 完成 */
async function loadApp(route, { seedStorage = null, setup = null, waitInit = true } = {}) {
    vi.resetModules();
    sessionStorage.clear();
    if (seedStorage) sessionStorage.setItem('conver.tabs.v1', JSON.stringify(seedStorage));
    document.body.innerHTML = APP_DOM_HTML;
    const fetchSpy = vi.fn(route);
    globalThis.fetch = fetchSpy;

    const app = await import('../js/app.js');
    const chat = await import('../js/chat.js');
    const state = (await import('../js/state.js')).state;
    const tabs = await import('../js/tabs.js');
    const cascade = await import('../js/cascade.js');
    const api = await import('../js/api.js');
    const utils = await import('../js/utils.js');

    // setup 钩子：init() 为模块级浮空 promise，其失败分支（showError/console.error）
    // 的续体在微任务队列中早于本函数返回 —— 需要捕获 init 期间调用的用例须配合
    // 路由 gate（挂起首个请求）使用，见「数据加载失败」块
    if (setup) setup({ app, chat, state, tabs, cascade, api, utils, fetchSpy });
    if (!waitInit) return { app, chat, state, tabs, cascade, api, utils, fetchSpy };

    // 等 4 路数据加载（characters/conversations/models/settings）完成 + 同步接线
    // 段（setActivationHooks/restore/initProviderDropdown/initSettingsPanel）执行完毕
    await vi.waitFor(() => {
        expect(fetchSpy.mock.calls.length).toBeGreaterThanOrEqual(4);
    });
    await sleep(10);
    return { app, chat, state, tabs, cascade, api, utils, fetchSpy };
}

const msg = (id, role, content) => ({ id, role, content });

describe('app.js init — 接线序列', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('空数据 init：四路加载 → 空态渲染 + Provider 下拉初始化（initProviderDropdown 接线）', async () => {
        const { state, fetchSpy } = await loadApp(makeRoute({}));

        // 四路数据加载（characters / conversations / models / settings）
        const paths = fetchSpy.mock.calls.map(([url]) => String(url).replace(/^.*\/api/, '/api'));
        expect(paths).toContain('/api/characters');
        expect(paths).toContain('/api/conversations');
        expect(paths).toContain('/api/models');
        expect(paths).toContain('/api/settings');

        // 角色/对话空态（renderCharacters / renderConversations 接线）
        expect(document.querySelector('#character-grid').innerHTML).toContain('暂无角色');
        expect(document.querySelector('#conversation-list').innerHTML).toContain('暂无对话');
        // 无恢复记录 → 聊天区空态（restoreFromStorage → showEmptyState 接线）
        expect(document.querySelector('#chat-messages').innerHTML).toContain('选择左侧对话或创建新对话开始聊天');
        expect(state.characters).toEqual([]);
        expect(state.conversations).toEqual([]);
        // initProviderDropdown 接线：Provider 下拉已按模型列表初始化
        const providerOptions = [...document.querySelector('#setting-default-provider').options]
            .map((o) => o.value);
        expect(providerOptions).toEqual(['claude']);
    });

    it('restoreFromStorage 接线：有会话记录且有效 → activateConversation(saveCurrent:false) 恢复', async () => {
        const { tabs, fetchSpy } = await loadApp(
            makeRoute({
                conversations: [{ id: 11, title: '会话A', character_id: 1, model_name: 'm', model_provider: 'claude' }],
                messagesByConv: { 11: [msg(1, 'user', '你好')] },
            }),
            { seedStorage: { ids: [11], activeId: 11 } },
        );

        // 恢复的 tab 被激活并补全（消息懒加载 + 头部渲染接线）
        await vi.waitFor(() => {
            expect(tabs.getTab(11)?.messages).toHaveLength(1);
        });
        expect(tabs.getActiveTab()?.conversationId).toBe(11);
        expect(tabs.getTab(11).title).toBe('会话A');
        expect(tabs.getTab(11).characterId).toBe(1);
        expect(document.querySelector('#chat-title-text').textContent).toBe('会话A');
        expect(document.querySelector('#chat-messages').textContent).toContain('你好');
        // 恢复后的消息加载走 GET messages
        expect(fetchSpy.mock.calls.some(([url]) => String(url).includes('/conversations/11/messages')))
            .toBe(true);
    });

    it('initSettingsPanel 接线：清空全部对话 → 经 onConversationsCleared 触发级联收口 {ids:"all",reloadList:false}', async () => {
        const { cascade, fetchSpy } = await loadApp(makeRoute({
            conversations: [{ id: 11, title: 'A', message_count: 2 }],
        }));
        const cascadeSpy = vi.spyOn(cascade, 'closeConversationsAndResettle').mockResolvedValue(undefined);

        document.querySelector('#btn-clear-all-convs').click();
        document.querySelector('.modal-overlay .confirm-ok').click();

        await vi.waitFor(() => expect(cascadeSpy).toHaveBeenCalledTimes(1));
        expect(cascadeSpy).toHaveBeenCalledWith({ ids: 'all', reloadList: false });
        expect(fetchSpy.mock.calls.some(([url, opts]) =>
            String(url).endsWith('/api/conversations') && opts?.method === 'DELETE')).toBe(true);
    });
});

describe('app.js 视图切换 — 刷新分发', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('characters → loadCharacters 刷新 + 视图 active 迁移', async () => {
        const { api, state } = await loadApp(makeRoute({}));
        const listSpy = vi.spyOn(api.characters, 'list');

        document.querySelector('.nav-btn[data-view="characters"]').click();

        expect(listSpy).toHaveBeenCalledTimes(1);
        expect(state.currentView).toBe('characters');
        expect(document.querySelector('#view-characters').classList.contains('active')).toBe(true);
        expect(document.querySelector('#view-chat').classList.contains('active')).toBe(false);
    });

    it('chat → loadConversations 刷新', async () => {
        const { api } = await loadApp(makeRoute({}));
        const listSpy = vi.spyOn(api.conversations, 'list');

        document.querySelector('.nav-btn[data-view="chat"]').click();

        expect(listSpy).toHaveBeenCalledTimes(1);
    });

    it('settings → loadSettings + initProviderDropdown 重建 Provider 选项', async () => {
        const { api, state } = await loadApp(makeRoute({}));
        const settingsSpy = vi.spyOn(api.settings, 'get');
        // 切换前模型列表已变化 → 下拉应重建为新 Provider 集
        state.models.providers = [
            { key: 'claude', name: 'Claude', models: ['m1'] },
            { key: 'deepseek', name: 'DeepSeek', models: ['d1'] },
        ];

        document.querySelector('.nav-btn[data-view="settings"]').click();

        await vi.waitFor(() => {
            expect([...document.querySelector('#setting-default-provider').options].map((o) => o.value))
                .toEqual(['claude', 'deepseek']);
        });
        expect(settingsSpy).toHaveBeenCalledTimes(1);
    });

    it('search → 100ms 后聚焦搜索框（switchView 聚焦时序接线）', async () => {
        const { state } = await loadApp(makeRoute({}));

        document.querySelector('.nav-btn[data-view="search"]').click();
        expect(state.currentView).toBe('search');

        await sleep(150);
        expect(document.activeElement).toBe(document.querySelector('#search-input'));
    });
});

describe('app.js 级联四入口 — 触发行为', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('删角色入口：确认后 closeConversationsAndResettle 收到该角色全部会话 ids + reloadList:true', async () => {
        const { cascade, tabs, fetchSpy } = await loadApp(makeRoute({
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
        const { cascade, fetchSpy } = await loadApp(makeRoute({
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

    it('tab-bar 关最后 tab：onActivate(null) → closeConversationsAndResettle 收到 {ids:[],reloadList:false}', async () => {
        const { cascade, tabs } = await loadApp(makeRoute({}));
        tabs.openTab(11);
        const cascadeSpy = vi.spyOn(cascade, 'closeConversationsAndResettle').mockResolvedValue(undefined);

        document.querySelector('#chat-tabs .tab-close').click();

        await vi.waitFor(() => expect(cascadeSpy).toHaveBeenCalledTimes(1));
        expect(cascadeSpy).toHaveBeenCalledWith({ ids: [], reloadList: false });
        expect(tabs.getTabs()).toHaveLength(0);
    });

    it('Falsify:删对话后列表重载失败 → 无 unhandled rejection + 错误 toast + tab 已关（真实级联）', async () => {
        const { utils, tabs, fetchSpy } = await loadApp(makeRoute({
            conversations: [{ id: 11, title: 'A', message_count: 2 }],
            failReloadAfterDelete: true,
        }));
        const toastSpy = vi.spyOn(utils, 'showToast');

        document.querySelector('#conversation-list .btn-delete-conv').click();
        document.querySelector('.modal-overlay .confirm-ok').click();

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalled());
        expect(toastSpy).toHaveBeenCalledWith('加载对话列表失败', 'error');
        // 真实级联收口已生效：tab 关闭（不依赖列表重载成功）
        expect(tabs.getTabs()).toHaveLength(0);
        // 删除本身已发出（列表重载失败发生在删除之后）
        expect(fetchSpy.mock.calls.some(([url, opts]) =>
            String(url).endsWith('/api/conversations/11') && opts?.method === 'DELETE')).toBe(true);
    });
});

describe('app.js 搜索接线 — 输入→防抖→结果跳转', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('搜索输入经防抖发请求；结果点击经 activateConversation 打开会话', async () => {
        const { tabs, fetchSpy } = await loadApp(makeRoute({
            conversations: [{ id: 11, title: '会话A', character_id: 1 }],
            searchResults: [{
                conversation_id: 11, message_id: 1, role: 'user', character_name: '',
                content_preview: '你好世界', conversation_title: '会话A',
            }],
        }));
        const input = document.querySelector('#search-input');
        input.value = '你好';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        await sleep(320); // 防抖 300ms

        expect(fetchSpy.mock.calls.some(([url]) => String(url).includes('/api/messages/search?q=')))
            .toBe(true);
        document.querySelector('#search-results .search-result-item').click();

        // 跳转钩子接线：activateConversation 打开会话 tab
        await vi.waitFor(() => expect(tabs.getTab(11)).toBeDefined());
        expect(tabs.getActiveTab()?.conversationId).toBe(11);
    });

    it('Falsify:结果跳转到未知会话（列表无此会话）→ 头部空态文案（renderChatHeader 未知名分支）', async () => {
        const { tabs } = await loadApp(makeRoute({
            searchResults: [{
                conversation_id: 99, message_id: 1, role: 'user', character_name: '',
                content_preview: 'hi', conversation_title: '远程',
            }],
        }));
        const input = document.querySelector('#search-input');
        input.value = 'hi';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        await sleep(320);
        document.querySelector('#search-results .search-result-item').click();

        await vi.waitFor(() => expect(tabs.getTab(99)).toBeDefined());
        // conversations.get 404 → conv 未补全 → 头部空态（不崩溃；
        // 未知名分支渲染 <span class="chat-title"> 无 id）
        expect(document.querySelector('#chat-header').textContent)
            .toContain('选择一个角色开始对话');
    });
});

describe('app.js 角色管理委托 — 四类按钮与失败兜底', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('chat-with 委托：模型选择器 → 创建对话 → 切 chat 视图 → 激活会话 + 输入聚焦', async () => {
        const { tabs, state, fetchSpy } = await loadApp(makeRoute({
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
        const { fetchSpy } = await loadApp(makeRoute({
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
        const { fetchSpy } = await loadApp(makeRoute({
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
        const { fetchSpy } = await loadApp(makeRoute({
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
        await loadApp(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
        }));
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');

        document.querySelector('#character-grid .edit-char').click();
        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledTimes(1));
        expect(alertSpy).toHaveBeenCalledWith(expect.stringContaining('加载角色信息失败'));
    });

    it('export-char 委托：downloadBlob 收到导出地址与文件名', async () => {
        const { utils } = await loadApp(makeRoute({
            characters: [{ id: 1, name: '角色A', conversation_count: 0 }],
        }));
        const downloadSpy = vi.spyOn(utils, 'downloadBlob');

        document.querySelector('#character-grid .export-char').click();

        expect(downloadSpy).toHaveBeenCalledWith('/api/characters/1/export', '角色A.json');
    });

    it('Falsify:删角色 API 失败 → showAlert「删除失败: <原因>」', async () => {
        const { fetchSpy } = await loadApp(makeRoute({
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
        const { fetchSpy } = await loadApp(makeRoute({
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
        const { state } = await loadApp(makeRoute({}));

        document.querySelector('#btn-create-character').click();
        await vi.waitFor(() => expect(document.querySelector('.wizard-modal')).not.toBeNull());

        document.querySelector('#btn-new-chat').click();
        expect(state.currentView).toBe('characters');
    });
});

describe('app.js 发送/输入接线', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('btn-send：流式在途 tab → abortStream；普通 tab → handleSend；无 tab → no-op', async () => {
        const { chat, tabs } = await loadApp(makeRoute({}));
        const handleSpy = vi.spyOn(chat, 'handleSend');

        // 无 tab → no-op
        document.querySelector('#btn-send').click();
        expect(handleSpy).not.toHaveBeenCalled();

        // 普通 tab → handleSend
        tabs.openTab(11);
        document.querySelector('#btn-send').click();
        expect(handleSpy).toHaveBeenCalledTimes(1);

        // 流式在途 → 停止（abortStream）
        const abortSpy = vi.spyOn(tabs, 'abortStream');
        tabs.openTab(12);
        tabs.updateTab(12, { isStreaming: true });
        document.querySelector('#btn-send').click();
        expect(abortSpy).toHaveBeenCalledWith(12);
        expect(handleSpy).toHaveBeenCalledTimes(1); // 未触发发送
    });

    it('chat-input Enter → handleSend；Shift+Enter 不触发', async () => {
        const { chat, tabs } = await loadApp(makeRoute({}));
        tabs.openTab(11);
        const handleSpy = vi.spyOn(chat, 'handleSend');
        const input = document.querySelector('#chat-input');

        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        expect(handleSpy).toHaveBeenCalledTimes(1);

        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', shiftKey: true, bubbles: true }));
        expect(handleSpy).toHaveBeenCalledTimes(1); // Shift+Enter 换行不发送
    });

    it('chat-input input → 高度自适应', () => {
        return loadApp(makeRoute({})).then(({}) => {
            const input = document.querySelector('#chat-input');
            input.style.height = '10px';
            input.dispatchEvent(new Event('input', { bubbles: true }));
            expect(input.style.height).not.toBe('10px');
            expect(input.style.height).toMatch(/px$/);
        });
    });
});

describe('app.js 重命名与头部接线', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('双击标题重命名：Enter 提交 → PUT → 列表/tab/头部同步', async () => {
        const { tabs, fetchSpy } = await loadApp(makeRoute({
            conversations: [{ id: 11, title: '旧标题', character_id: 1, message_count: 2 }],
        }));
        const activation = await import('../js/conversation-activation.js');
        await activation.activateConversation(11);
        await vi.waitFor(() => expect(tabs.getTab(11)?.messages).toBeDefined());

        // 双击标题 → 原地编辑输入框
        const titleEl = document.querySelector('#chat-title-text');
        titleEl.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = document.querySelector('.chat-title-input');
        expect(input).not.toBeNull();
        input.value = '新标题';
        // PUT 路由
        fetchSpy.mockImplementation((url, options = {}) => {
            if (String(url).endsWith('/api/conversations/11') && options?.method === 'PUT') {
                return Promise.resolve(mockJson({ id: 11, title: '新标题', character_id: 1 }));
            }
            return makeRoute({ conversations: [{ id: 11, title: '新标题', character_id: 1 }] })(url, options);
        });
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        await vi.waitFor(() => {
            expect(tabs.getTab(11).title).toBe('新标题');
        });
        expect(document.querySelector('#chat-title-text').textContent).toBe('新标题');
        expect(document.querySelector('#conversation-list .title').textContent).toBe('新标题');
    });

    it('头部按钮：移动端列表切换 + 导出弹窗', async () => {
        const { tabs } = await loadApp(makeRoute({
            conversations: [{ id: 11, title: 'A', character_id: 1, message_count: 2 }],
        }));
        const activation = await import('../js/conversation-activation.js');
        await activation.activateConversation(11);
        await vi.waitFor(() => expect(tabs.getTab(11)?.messages).toBeDefined());

        // 移动端切换对话列表
        document.querySelector('#btn-toggle-conv-list').click();
        expect(document.querySelector('.chat-sidebar').classList.contains('mobile-expanded')).toBe(true);
        // 导出弹窗
        document.querySelector('#btn-export-conv').click();
        await vi.waitFor(() => expect(document.querySelector('.export-modal')).not.toBeNull());
    });

    it('Escape 取消重命名 → 恢复原标题', async () => {
        const { tabs } = await loadApp(makeRoute({
            conversations: [{ id: 11, title: '旧标题', character_id: 1, message_count: 2 }],
        }));
        const activation = await import('../js/conversation-activation.js');
        await activation.activateConversation(11);
        await vi.waitFor(() => expect(tabs.getTab(11)?.messages).toBeDefined());

        document.querySelector('#chat-title-text').dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = document.querySelector('.chat-title-input');
        input.value = '不应生效';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        await new Promise((r) => setTimeout(r, 0));

        expect(tabs.getTab(11).title).toBe('旧标题');
    });

    it('Falsify:重命名保存失败 → console.error,输入框恢复但不污染 tab/列表', async () => {
        const { tabs, fetchSpy } = await loadApp(makeRoute({
            conversations: [{ id: 11, title: '旧标题', character_id: 1, message_count: 2 }],
        }));
        const activation = await import('../js/conversation-activation.js');
        await activation.activateConversation(11);
        await vi.waitFor(() => expect(tabs.getTab(11)?.messages).toBeDefined());
        // PUT 失败
        fetchSpy.mockImplementation((url, options = {}) => {
            if (String(url).endsWith('/api/conversations/11') && options?.method === 'PUT') {
                return Promise.resolve(mockJson({ detail: 'boom' }, 500));
            }
            return makeRoute({ conversations: [{ id: 11, title: '旧标题', character_id: 1 }] })(url, options);
        });
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

        document.querySelector('#chat-title-text').dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        const input = document.querySelector('.chat-title-input');
        input.value = '新标题';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        await vi.waitFor(() => expect(errorSpy).toHaveBeenCalledWith('重命名失败:', expect.any(Error)));
        // 失败不污染：tab 与列表保持旧标题；输入框恢复显示（显示输入值,既有语义）
        expect(tabs.getTab(11).title).toBe('旧标题');
        expect(document.querySelector('#conversation-list .title').textContent).toBe('旧标题');
        expect(document.querySelector('#chat-title-text').textContent).toBe('新标题');
        errorSpy.mockRestore();
    });
});

describe('app.js 导入接线', () => {
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
        const { utils, fetchSpy } = await loadApp(makeRoute({
            importResult: { id: 5, name: '新角色' },
        }));
        const toastSpy = vi.spyOn(utils, 'showToast');

        dispatchImportFile(JSON.stringify({ name: '新角色' }));

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('成功导入角色「新角色」', 'success'));
        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/characters/import') && o?.method === 'POST'))
            .toBe(true);
        expect(document.querySelector('#character-import-input').value).toBe(''); // finally 清空
    });

    it('Falsify:JSON 解析失败 → 错误 toast + 引导到创建向导', async () => {
        const { utils } = await loadApp(makeRoute({}));
        const toastSpy = vi.spyOn(utils, 'showToast');

        dispatchImportFile('not-json{{{');

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('不是有效的 JSON 文件', 'error'));
        // 引导弹窗 → 确认「打开向导」→ 创建向导弹窗
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(document.querySelector('.wizard-modal')).not.toBeNull());
    });

    it('Falsify:导入 API 失败 → 错误 toast（含后端原因）+ 引导到创建向导', async () => {
        const { utils } = await loadApp(makeRoute({
            importResult: { fail: '卡格式不受支持' },
        }));
        const toastSpy = vi.spyOn(utils, 'showToast');

        dispatchImportFile(JSON.stringify({ name: 'x' }));

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('卡格式不受支持', 'error'));
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(document.querySelector('.wizard-modal')).not.toBeNull());
    });

    it('btn-import-character 点击 → 触发文件选择器（no-op 不抛错）', () => {
        return loadApp(makeRoute({})).then(() => {
            expect(() => document.querySelector('#btn-import-character').click()).not.toThrow();
        });
    });
});

describe('app.js 数据加载失败 — Falsify 兜底', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('角色列表加载失败 → 错误 toast（init 不崩溃）', async () => {
        // 路由 gate：首个角色列表请求挂起 → setup 挂 spy → 放行触发失败续体
        let release;
        const gate = new Promise((r) => { release = r; });
        const base = makeRoute({});
        const gated = async (url, options = {}) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            if (path === '/api/characters' && (options.method || 'GET') === 'GET') {
                await gate;
                return mockJson({ detail: 'boom' }, 500);
            }
            return base(url, options);
        };
        let toastSpy = null;
        await loadApp(gated, {
            waitInit: false,
            setup: ({ utils }) => { toastSpy = vi.spyOn(utils, 'showToast'); },
        });
        release();

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('加载角色列表失败', 'error'));
    });

    it('模型列表加载失败 → console.error（init 不崩溃,Provider 下拉空）', async () => {
        let release;
        const gate = new Promise((r) => { release = r; });
        const base = makeRoute({});
        const gated = async (url, options = {}) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            if (path === '/api/models' && (options.method || 'GET') === 'GET') {
                await gate;
                return mockJson({ detail: 'boom' }, 500);
            }
            return base(url, options);
        };
        let errorSpy = null;
        const { state } = await loadApp(gated, {
            waitInit: false,
            setup: () => { errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {}); },
        });
        release();

        await vi.waitFor(() => expect(errorSpy).toHaveBeenCalledWith('加载模型列表失败:', expect.any(Error)));
        expect(state.models).toEqual({ providers: [] });
        errorSpy.mockRestore();
    });
});
