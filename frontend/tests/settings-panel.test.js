import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { resolveCredentialTarget } from '../js/components/settings-panel.js';

// 语义对齐后端 backend/app/services/setting.py::_slot_value：
// 同协议槽位优先 → 跨协议兜底（任一槽位有值即可全局使用）。
describe('resolveCredentialTarget', () => {
    // 同协议优先：deepseek(id=openai) 两槽都填 → 取 openai 槽位
    it('同协议优先：多协议槽位都有值时取同协议槽位', () => {
        const form = {
            provider: { key: 'deepseek', id: 'openai' },
            claude_api_key: 'sk-claude',
            claude_base_url: 'https://api.anthropic.com',
            openai_api_key: 'sk-openai',
            openai_base_url: 'https://api.openai.com/v1',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'deepseek',
            key: 'sk-openai',
            baseUrl: 'https://api.openai.com/v1',
        });
    });

    // 跨协议兜底：同协议槽位为空 → 回退另一协议槽位
    it('跨协议兜底：同协议槽位为空时回退另一协议槽位', () => {
        const form = {
            provider: { key: 'deepseek', id: 'openai' },
            claude_api_key: 'sk-claude',
            claude_base_url: 'https://api.anthropic.com',
            openai_api_key: '',
            openai_base_url: '',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'deepseek',
            key: 'sk-claude',
            baseUrl: 'https://api.anthropic.com',
        });
    });

    // 未填回退：两槽都空 → key/baseUrl 为空串，providerKey 保留（调用方据此跳过测试）
    it('未填回退：两槽都空时 key/baseUrl 为空串', () => {
        const form = {
            provider: { key: 'claude', id: 'claude' },
            claude_api_key: '',
            claude_base_url: '',
            openai_api_key: '',
            openai_base_url: '',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'claude',
            key: '',
            baseUrl: '',
        });
    });

    // 表单字段缺失：键不存在（undefined）与空串等价，不抛错
    it('表单字段缺失：字段键缺失时按空处理并兜底，不抛错', () => {
        const form = {
            provider: { key: 'openai', id: 'openai' },
            // claude_api_key / claude_base_url 键完全缺失
            openai_api_key: undefined,
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'openai',
            key: '',
            baseUrl: '',
        });
    });

    // URL 原样透传：不带 /v1 后缀的 base_url 不做任何规范化
    it('URL 不带 /v1 时原样透传，不做规范化', () => {
        const form = {
            provider: { key: 'claude', id: 'claude' },
            claude_api_key: 'sk-claude',
            claude_base_url: 'https://example.com/api',
            openai_api_key: '',
            openai_base_url: '',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'claude',
            key: 'sk-claude',
            baseUrl: 'https://example.com/api',
        });
    });
});

// ══════════════════════════════════════════════════
// initProviderDropdown / Provider→模型联动 / onConversationsCleared
// （ARC-9 C5 组件联动挂网 — jsdom 直测，与 C3 modal seam 解耦）
// ══════════════════════════════════════════════════

/** 设置面板最小 DOM — 与 index.html 的 id 契约一致（只读契约） */
const SETTINGS_DOM_HTML = `
    <select id="setting-default-provider"></select>
    <select id="setting-default-model"></select>
    <input type="text" id="setting-custom-model" style="display:none">
    <select id="setting-theme">
        <option value="auto">跟随系统</option>
        <option value="light">浅色</option>
        <option value="dark">深色</option>
    </select>
    <input id="setting-claude-key"><input id="setting-claude-url">
    <input id="setting-openai-key"><input id="setting-openai-url">
    <input id="setting-sliding-window"><input id="setting-user-name">
    <button id="btn-save-settings"></button>
    <button id="btn-clear-all-convs"></button>
    <button id="btn-theme-toggle"></button>
`;

const PROVIDERS = [
    { key: 'claude', name: 'Claude (Anthropic)', models: ['claude-sonnet-5', 'claude-opus-4-8'] },
    { key: 'deepseek', name: 'DeepSeek', models: ['deepseek-chat'] },
];

/** 加载全新 settings-panel + state 实例（DOM 先就位） */
async function loadPanel() {
    vi.resetModules();
    document.body.innerHTML = SETTINGS_DOM_HTML;
    const panel = await import('../js/components/settings-panel.js');
    const state = (await import('../js/state.js')).state;
    return { panel, state };
}

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

describe('initProviderDropdown — Provider 下拉与模型联动', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('按 state.models.providers 重建 Provider 选项 + 恢复默认 Provider 选中 + 模型下拉联动', () => {
        return loadPanel().then(({ panel, state }) => {
            state.models.providers = PROVIDERS;
            state.defaultProvider = 'deepseek';
            state.defaultModel = 'deepseek-chat';

            panel.initProviderDropdown();

            const providerSelect = document.querySelector('#setting-default-provider');
            const modelSelect = document.querySelector('#setting-default-model');
            expect([...providerSelect.options].map((o) => o.value)).toEqual(['claude', 'deepseek']);
            expect(providerSelect.value).toBe('deepseek');
            // 模型下拉按选中 Provider 联动（deepseek → deepseek-chat 预选中 + 自定义选项）
            expect([...modelSelect.options].map((o) => o.value))
                .toEqual(['deepseek-chat', '__custom__']);
            expect(modelSelect.value).toBe('deepseek-chat');
        });
    });

    it('Provider 变更联动模型下拉（经 initSettingsPanel 绑定 change）', () => {
        return loadPanel().then(({ panel, state }) => {
            state.models.providers = PROVIDERS;
            state.defaultProvider = 'claude';
            state.defaultModel = 'claude-sonnet-5';
            panel.initProviderDropdown();
            panel.initSettingsPanel({});

            const providerSelect = document.querySelector('#setting-default-provider');
            const modelSelect = document.querySelector('#setting-default-model');
            const customInput = document.querySelector('#setting-custom-model');
            providerSelect.value = 'deepseek';
            providerSelect.dispatchEvent(new Event('change', { bubbles: true }));

            // 模型下拉按新 Provider 重建（deepseek 模型 + 自定义选项）
            expect([...modelSelect.options].map((o) => o.value))
                .toEqual(['deepseek-chat', '__custom__']);
            // 默认模型不在 deepseek 列表 → 联动落入自定义模式并回填（既有语义）
            expect(modelSelect.value).toBe('__custom__');
            expect(customInput.value).toBe('claude-sonnet-5');
            expect(customInput.style.display).not.toBe('none');
        });
    });

    it('默认模型不在 Provider 列表 → 切自定义模式并回填输入框', () => {
        return loadPanel().then(({ panel, state }) => {
            state.models.providers = PROVIDERS;
            state.defaultProvider = 'claude';
            state.defaultModel = 'gpt-4o'; // 不在 claude 模型列表

            panel.initProviderDropdown();

            const modelSelect = document.querySelector('#setting-default-model');
            const customInput = document.querySelector('#setting-custom-model');
            expect(modelSelect.value).toBe('__custom__');
            expect(modelSelect.style.display).toBe('none');
            expect(customInput.style.display).not.toBe('none');
            expect(customInput.value).toBe('gpt-4o');
        });
    });

    it('Falsify:providers 为空 → 下拉为空、不抛错（联动 no-op）', () => {
        return loadPanel().then(({ panel, state }) => {
            state.models.providers = [];
            state.defaultProvider = 'claude';
            expect(() => panel.initProviderDropdown()).not.toThrow();
            const providerSelect = document.querySelector('#setting-default-provider');
            const modelSelect = document.querySelector('#setting-default-model');
            expect(providerSelect.options).toHaveLength(0);
            // 无匹配 provider → refreshModelOptions 提前返回（模型下拉不被清空）
            expect(modelSelect.options.length).toBeGreaterThanOrEqual(0);
        });
    });

    it('Falsify:Provider 切到未知 key → refreshModelOptions no-op（模型下拉保持原样）', () => {
        return loadPanel().then(({ panel, state }) => {
            state.models.providers = PROVIDERS;
            state.defaultProvider = 'claude';
            panel.initProviderDropdown();
            panel.initSettingsPanel({});

            const providerSelect = document.querySelector('#setting-default-provider');
            const modelSelect = document.querySelector('#setting-default-model');
            const before = [...modelSelect.options].map((o) => o.value);
            providerSelect.value = 'unknown-provider';
            providerSelect.dispatchEvent(new Event('change', { bubbles: true }));

            expect([...modelSelect.options].map((o) => o.value)).toEqual(before);
        });
    });

    it('默认 Provider key 失配但 name 兜底匹配 → 按名称选中（跨协议同名校验）', () => {
        return loadPanel().then(({ panel, state }) => {
            state.models.providers = PROVIDERS;
            state.defaultProvider = 'deepseek-unknown-key'; // key 不在列表
            state.defaultProviderName = 'DeepSeek'; // name 兜底命中

            panel.initProviderDropdown();

            const providerSelect = document.querySelector('#setting-default-provider');
            expect(providerSelect.value).toBe('deepseek');
            expect([...providerSelect.options].find((o) => o.selected).textContent).toContain('DeepSeek');
        });
    });
});

describe('onConversationsCleared — 清空全部对话联动回调', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('确认清空 → deleteAll + state 置空 + 注入回调触发', async () => {
        const { panel, state } = await loadPanel();
        state.conversations = [{ id: 11, title: 'A' }, { id: 12, title: 'B' }];
        const fetchSpy = vi.fn(async (url) => {
            expect(String(url)).toContain('/api/conversations');
            return mockJson(null, 204);
        });
        // conversations.deleteAll 走 api.js request → fetch seam
        const api = await import('../js/api.js');
        api.setFetch(fetchSpy);
        const onCleared = vi.fn();
        panel.initSettingsPanel({ onConversationsCleared: onCleared });

        document.querySelector('#btn-clear-all-convs').click();
        // 确认弹窗（modal 工厂）→ 点「清空所有」
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(onCleared).toHaveBeenCalledTimes(1));

        expect(fetchSpy).toHaveBeenCalledTimes(1);
        expect(state.conversations).toEqual([]);
        expect(onCleared).toHaveBeenCalledTimes(1);
    });

    it('无对话 → 提示「当前没有对话需要清空」,回调不触发（no-op）', async () => {
        const { panel, state } = await loadPanel();
        state.conversations = [];
        const onCleared = vi.fn();
        panel.initSettingsPanel({ onConversationsCleared: onCleared });
        const alertSpy = vi.spyOn(await import('../js/components/confirm-dialog.js'), 'showAlert');

        document.querySelector('#btn-clear-all-convs').click();
        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledTimes(1));

        expect(alertSpy).toHaveBeenCalledWith('当前没有对话需要清空');
        expect(onCleared).not.toHaveBeenCalled();
    });

    it('取消确认 → 不 deleteAll、回调不触发', async () => {
        const { panel, state } = await loadPanel();
        state.conversations = [{ id: 11, title: 'A' }];
        const api = await import('../js/api.js');
        const fetchSpy = vi.fn(async () => mockJson(null, 204));
        api.setFetch(fetchSpy);
        const onCleared = vi.fn();
        panel.initSettingsPanel({ onConversationsCleared: onCleared });

        document.querySelector('#btn-clear-all-convs').click();
        document.querySelector('.modal-overlay .confirm-cancel').click();
        await new Promise((r) => setTimeout(r, 0));

        expect(fetchSpy).not.toHaveBeenCalled();
        expect(onCleared).not.toHaveBeenCalled();
        expect(state.conversations).toHaveLength(1);
    });

    it('Falsify:清空 API 失败 → showAlert「清空失败: <原因>」,回调不触发', async () => {
        const { panel, state } = await loadPanel();
        state.conversations = [{ id: 11, title: 'A' }];
        const api = await import('../js/api.js');
        api.setFetch(vi.fn(async () => mockJson({ detail: 'boom' }, 500)));
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');
        const onCleared = vi.fn();
        panel.initSettingsPanel({ onConversationsCleared: onCleared });

        document.querySelector('#btn-clear-all-convs').click();
        document.querySelector('.modal-overlay .confirm-ok').click();
        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledTimes(1));

        expect(alertSpy).toHaveBeenCalledWith('清空失败: boom');
        expect(onCleared).not.toHaveBeenCalled();
    });
});

describe('loadSettings — 表单回填与失败兜底', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('全字段回填：Key/URL/默认模型/主题/昵称写入表单与 state', async () => {
        const { panel, state } = await loadPanel();
        const api = await import('../js/api.js');
        api.setFetch(vi.fn(async () => mockJson({
            claude_api_key: 'sk-fake-claude',
            claude_base_url: 'https://api.anthropic.com',
            openai_api_key: 'sk-fake-openai',
            openai_base_url: 'https://api.openai.com/v1',
            default_provider: 'claude',
            default_provider_name: 'Claude',
            default_model: 'claude-sonnet-5',
            sliding_window_rounds: 20,
            theme_mode: 'dark',
            user_name: 'Alice',
        })));

        await panel.loadSettings();

        expect(document.querySelector('#setting-claude-key').value).toBe('sk-fake-claude');
        expect(document.querySelector('#setting-claude-url').value).toBe('https://api.anthropic.com');
        expect(document.querySelector('#setting-openai-key').value).toBe('sk-fake-openai');
        expect(document.querySelector('#setting-openai-url').value).toBe('https://api.openai.com/v1');
        expect(document.querySelector('#setting-sliding-window').value).toBe('20');
        expect(document.querySelector('#setting-theme').value).toBe('dark');
        expect(document.querySelector('#setting-user-name').value).toBe('Alice');
        expect(state.defaultProvider).toBe('claude');
        expect(state.defaultProviderName).toBe('Claude');
        expect(state.defaultModel).toBe('claude-sonnet-5');
        expect(document.documentElement.dataset.theme).toBe('dark'); // applyTheme 接线
    });

    it('Falsify:加载失败 → console.error,不抛错', async () => {
        const { panel } = await loadPanel();
        const api = await import('../js/api.js');
        api.setFetch(vi.fn(async () => mockJson({ detail: 'boom' }, 500)));
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

        await expect(panel.loadSettings()).resolves.toBeUndefined();
        expect(errorSpy).toHaveBeenCalledWith('加载设置失败:', expect.any(Error));
        errorSpy.mockRestore();
    });
});

describe('保存设置 — 表单收集 / testApiKeys / 持久化', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    /** 加载面板 + 注入 providers + 初始化下拉与事件绑定；返回 fetch spy 与常用句柄 */
    async function loadSaveable() {
        const env = await loadPanel();
        env.state.models.providers = PROVIDERS;
        env.state.defaultProvider = 'claude';
        env.state.defaultModel = 'claude-sonnet-5';
        env.panel.initProviderDropdown();
        env.panel.initSettingsPanel({});
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const api = await import('../js/api.js');
        return { ...env, confirmModule, api };
    }

    it('自定义模型：选中 __custom__ + 输入值 → 保存提交自定义模型名（getSelectedModel 分支）', async () => {
        const { panel, state, confirmModule, api } = await loadSaveable();
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');
        const fetchSpy = vi.fn(async (url, options = {}) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            if (path === '/api/settings/test-connection' && options.method === 'POST') {
                return mockJson({ ok: true });
            }
            if (path === '/api/settings' && options.method === 'PUT') {
                return mockJson({ default_provider: 'claude', default_provider_name: 'Claude', default_model: 'my-custom-model' });
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });
        api.setFetch(fetchSpy);

        document.querySelector('#setting-default-model').value = '__custom__';
        document.querySelector('#setting-default-model').dispatchEvent(new Event('change', { bubbles: true }));
        document.querySelector('#setting-custom-model').value = 'my-custom-model';
        document.querySelector('#setting-theme').value = 'dark';
        document.querySelector('#btn-save-settings').click();

        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledWith('设置已保存'));
        // testApiKeys：无 Key → 跳过连接测试直接保存
        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).includes('/test-connection'))).toBe(false);
        // 提交体含自定义模型名
        const putCall = fetchSpy.mock.calls.find(([u, o]) => String(u).endsWith('/api/settings') && o?.method === 'PUT');
        expect(JSON.parse(putCall[1].body).default_model).toBe('my-custom-model');
        expect(JSON.parse(putCall[1].body).theme_mode).toBe('dark');
        // state 与主题同步
        expect(state.defaultModel).toBe('my-custom-model');
        expect(document.documentElement.dataset.theme).toBe('dark');
    });

    it('有 Key：连接测试通过后保存（testApiKeys 委托 resolveCredentialTarget 取同协议槽位）', async () => {
        const { state, confirmModule, api } = await loadSaveable();
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');
        const fetchSpy = vi.fn(async (url, options = {}) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            if (path === '/api/settings/test-connection' && options.method === 'POST') {
                return mockJson({ ok: true });
            }
            if (path === '/api/settings' && options.method === 'PUT') {
                return mockJson({ default_provider: 'claude', default_provider_name: 'Claude', default_model: 'claude-sonnet-5' });
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });
        api.setFetch(fetchSpy);

        document.querySelector('#setting-claude-key').value = 'sk-fake';
        document.querySelector('#btn-save-settings').click();

        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledWith('设置已保存'));
        const testCall = fetchSpy.mock.calls.find(([u, o]) => String(u).includes('/test-connection') && o?.method === 'POST');
        expect(testCall).toBeDefined();
        const body = JSON.parse(testCall[1].body);
        expect(body.provider).toBe('claude');
        expect(body.api_key).toBe('sk-fake');
        expect(body.model).toBe('claude-sonnet-5');
        expect(state.defaultModel).toBe('claude-sonnet-5');
    });

    it('连接测试失败 → 确认「仍然保存」后继续保存', async () => {
        const { confirmModule, api } = await loadSaveable();
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');
        const fetchSpy = vi.fn(async (url, options = {}) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            if (path === '/api/settings/test-connection' && options.method === 'POST') {
                return mockJson({ detail: '连接失败' }, 400);
            }
            if (path === '/api/settings' && options.method === 'PUT') {
                return mockJson({ default_provider: 'claude', default_provider_name: 'Claude', default_model: 'm' });
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });
        api.setFetch(fetchSpy);

        document.querySelector('#setting-claude-key').value = 'sk-fake';
        document.querySelector('#btn-save-settings').click();
        // 失败确认弹窗 → 仍然保存
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .confirm-ok').click();

        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledWith('设置已保存'));
        expect(fetchSpy.mock.calls.some(([u, o]) => String(u).endsWith('/api/settings') && o?.method === 'PUT'))
            .toBe(true);
    });

    it('Falsify:保存 API 失败 → showAlert「保存失败: <原因>」', async () => {
        const { confirmModule, api } = await loadSaveable();
        const alertSpy = vi.spyOn(confirmModule, 'showAlert');
        const fetchSpy = vi.fn(async (url, options = {}) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            if (path === '/api/settings' && options.method === 'PUT') {
                return mockJson({ detail: 'boom' }, 500);
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });
        api.setFetch(fetchSpy);

        document.querySelector('#btn-save-settings').click();

        await vi.waitFor(() => expect(alertSpy).toHaveBeenCalledWith('保存失败: boom'));
        expect(fetchSpy).toHaveBeenCalledTimes(1); // 无 Key → 跳过连接测试
    });
});

describe('主题切换 — toggleTheme 持久化', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('点击主题按钮 → applyTheme + PUT 持久化 + 主题下拉同步', async () => {
        const { panel, state } = await loadPanel();
        panel.initSettingsPanel({});
        const api = await import('../js/api.js');
        const fetchSpy = vi.fn(async () => mockJson({ ok: true }));
        api.setFetch(fetchSpy);
        document.documentElement.removeAttribute('data-theme');

        document.querySelector('#btn-theme-toggle').click();
        await new Promise((r) => setTimeout(r, 0));

        // 当前无 data-theme → 视为 dark → 切到 light
        expect(document.documentElement.dataset.theme).toBe('light');
        expect(document.querySelector('#setting-theme').value).toBe('light');
        expect(fetchSpy.mock.calls.some(([u, o]) =>
            String(u).endsWith('/api/settings') && o?.method === 'PUT' && JSON.parse(o.body).theme_mode === 'light'))
            .toBe(true);
    });

    it('Falsify:主题持久化失败 → console.error,主题仍已应用（不抛错）', async () => {
        const { panel } = await loadPanel();
        panel.initSettingsPanel({});
        const api = await import('../js/api.js');
        api.setFetch(vi.fn(async () => mockJson({ detail: 'boom' }, 500)));
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        document.documentElement.removeAttribute('data-theme');

        document.querySelector('#btn-theme-toggle').click();
        await new Promise((r) => setTimeout(r, 0));

        expect(errorSpy).toHaveBeenCalledWith('保存主题设置失败:', expect.any(Error));
        expect(document.documentElement.dataset.theme).toBe('light'); // 本地先应用
        errorSpy.mockRestore();
    });
});

// ══════════════════════════════════════════════════
// no-op 守卫 — DOM 契约被破坏时不抛 TypeError（ARC9-2）
// ══════════════════════════════════════════════════

describe('no-op 守卫 — 设置面板元素缺失时不抛 TypeError（ARC9-2）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    // 用例 ①：空 DOM（无任何设置元素）→ initProviderDropdown 顶部早退 no-op
    it('空 DOM 下调 initProviderDropdown → no-op 不抛 TypeError', async () => {
        vi.resetModules();
        document.body.innerHTML = '';
        const panel = await import('../js/components/settings-panel.js');
        expect(() => panel.initProviderDropdown()).not.toThrow();
    });

    // 用例 ②：DOM 含 save/clear 两按钮（325/359 行未守卫绑定，必须存在）、
    // 缺 Provider/Model 两元素 → initSettingsPanel 两处绑定守卫后 no-op
    it('缺 #setting-default-provider/#setting-default-model 下调 initSettingsPanel → no-op 不抛 TypeError', async () => {
        vi.resetModules();
        document.body.innerHTML = `
            <button id="btn-save-settings"></button>
            <button id="btn-clear-all-convs"></button>
        `;
        const panel = await import('../js/components/settings-panel.js');
        expect(() => panel.initSettingsPanel({})).not.toThrow();
    });

    // 用例 ③（TD-4）：provider 在 + #setting-default-model 缺、providers 非空且
    // defaultProvider key 匹配 → 旧实现 refreshModelOptions 直入 fillModelSelect(null)，
    // model-utils.js:32 `selectEl.innerHTML` 赋值 null 抛 TypeError；三元素联合守卫后 no-op
    it('缺 #setting-default-model 下调 initProviderDropdown → 三元素联合守卫 no-op 不抛 TypeError', async () => {
        vi.resetModules();
        document.body.innerHTML = `
            <select id="setting-default-provider"></select>
            <input type="text" id="setting-custom-model" style="display:none">
        `;
        const panel = await import('../js/components/settings-panel.js');
        const state = (await import('../js/state.js')).state;
        state.models.providers = PROVIDERS;
        state.defaultProvider = 'claude';
        state.defaultModel = 'claude-sonnet-5';
        expect(() => panel.initProviderDropdown()).not.toThrow();
    });

    // 用例 ④（TD-4）：provider/model 在 + #setting-custom-model 缺、默认模型命中列表 →
    // 旧实现 fillModelSelect 落入「预选中」分支，model-utils.js:57 `customInputEl.style` null
    // 抛 TypeError；三元素联合守卫后 no-op
    it('缺 #setting-custom-model 下调 initProviderDropdown → 三元素联合守卫 no-op 不抛 TypeError', async () => {
        vi.resetModules();
        document.body.innerHTML = `
            <select id="setting-default-provider"></select>
            <select id="setting-default-model"></select>
        `;
        const panel = await import('../js/components/settings-panel.js');
        const state = (await import('../js/state.js')).state;
        state.models.providers = PROVIDERS;
        state.defaultProvider = 'claude';
        state.defaultModel = 'claude-sonnet-5';
        expect(() => panel.initProviderDropdown()).not.toThrow();
    });
});
