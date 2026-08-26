/**
 * search-view 深模块测试（ARC-9 C1 从 app.js 提取的搜索视图）
 *
 * 覆盖：防抖（fake timers）+ 五态文案逐字断言（空输入 / 至少输入 2 个字符 /
 *   搜索中… / 未找到匹配的消息 / 搜索失败: <原因>）+ 结果渲染与点击跳转
 *   （经注入的 navigateToConversation 钩子）+ 清空 / Enter / Escape。
 *
 * 测试即新模块接口契约：__all__ 单一入口 initSearchView（绑定事件 + 注入跳转
 *   钩子），其余经 DOM 事件驱动（input/keydown/click）与 fetch mock 断言
 *   （api.js setFetch seam）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** 最小搜索视图 DOM — 与 index.html 的 id/class 契约一致（只读契约） */
const SEARCH_DOM_HTML = `
    <input type="text" id="search-input" class="search-input" autocomplete="off">
    <button class="btn-icon btn-search-clear" id="btn-search-clear" title="清空"></button>
    <div class="search-results" id="search-results">
        <p class="search-hint">输入关键词搜索所有对话中的消息</p>
    </div>
`;

// ── 五态文案（逐字 — 与 app.js 原实现一致，行为保持审计点）──
const HINT_HTML = '<p class="search-hint">输入关键词搜索所有对话中的消息</p>';
const TOO_SHORT_HTML = '<p class="search-status">至少输入 2 个字符</p>';
const SEARCHING_HTML = '<p class="search-status">搜索中…</p>';
const NOT_FOUND_HTML = '<p class="search-status">未找到匹配的消息</p>';

/** 加载全新 search-view + api 实例（DOM 先就位；返回 dom 引用 + 模块） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = SEARCH_DOM_HTML;
    const searchView = await import('../js/search-view.js');
    const api = await import('../js/api.js');
    return {
        searchView,
        api,
        input: document.querySelector('#search-input'),
        results: document.querySelector('#search-results'),
        clearBtn: document.querySelector('#btn-search-clear'),
    };
}

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

/** mock messages.search：记录调用，按 case 路由结果（返回 Response 形状 — api.js request 消费） */
function mockSearch({ results = [], fail = null, pending = null } = {}) {
    return vi.fn(async (url) => {
        if (pending) return pending.promise; // 挂起（断言「搜索中…」态）
        if (fail) throw fail;
        return mockJson(results);
    });
}

/** 输入触发 input 事件并推进防抖窗口 */
async function typeAndWait(env, text, ms = 300) {
    env.input.value = text;
    env.input.dispatchEvent(new Event('input', { bubbles: true }));
    await vi.advanceTimersByTimeAsync(ms);
}

describe('search-view — 五态文案（逐字）与搜索流程', () => {
    beforeEach(() => {
        vi.restoreAllMocks();
        vi.useFakeTimers();
    });
    afterEach(() => {
        vi.useRealTimers();
        vi.restoreAllMocks();
    });

    it('空输入 → 提示文案逐字（search-hint）', async () => {
        const { searchView, api, input, results } = await loadModules();
        const fetchSpy = mockSearch({});
        api.setFetch(fetchSpy);
        searchView.initSearchView({ navigateToConversation: () => {} });

        await typeAndWait({ input }, '   '); // 全空白 → trim 后为空
        expect(results.innerHTML).toBe(HINT_HTML);
        expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('少于 2 个字符 → 「至少输入 2 个字符」逐字,不发请求', async () => {
        const { searchView, api, input, results } = await loadModules();
        const fetchSpy = mockSearch({});
        api.setFetch(fetchSpy);
        searchView.initSearchView({ navigateToConversation: () => {} });

        await typeAndWait({ input }, 'a');
        expect(results.innerHTML).toBe(TOO_SHORT_HTML);
        expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('搜索中 → 「搜索中…」逐字（请求挂起期间）', async () => {
        const { searchView, api, input, results } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        api.setFetch(mockSearch({ pending }));
        searchView.initSearchView({ navigateToConversation: () => {} });

        await typeAndWait({ input }, 'ab');
        expect(results.innerHTML).toBe(SEARCHING_HTML);
        // 挂起请求不 resolve：断言「搜索中…」态后结束（无未决断言）
    });

    it('成功有结果 → 计数 + 结果项渲染（复用 searchResultItemHtml）', async () => {
        const { searchView, api, input, results } = await loadModules();
        const hits = [
            { conversation_id: 11, message_id: 1, role: 'user', character_name: '', content_preview: '你好世界', conversation_title: '会话A' },
            { conversation_id: 12, message_id: 2, role: 'assistant', character_name: '角色B', content_preview: '回答', conversation_title: '会话B' },
        ];
        api.setFetch(mockSearch({ results: hits }));
        const nav = vi.fn();
        searchView.initSearchView({ navigateToConversation: nav });

        await typeAndWait({ input }, '世界');
        expect(results.innerHTML).toContain('<p class="search-count">共找到 2 条匹配消息</p>');
        expect(results.querySelectorAll('.search-result-item')).toHaveLength(2);
        expect(results.innerHTML).toContain('<mark class="search-highlight">世界</mark>');
    });

    it('结果点击 → 经注入的 navigateToConversation 钩子跳转（收到 conversationId + { messageId }）', async () => {
        const { searchView, api, input, results } = await loadModules();
        api.setFetch(mockSearch({
            results: [{ conversation_id: 11, message_id: 1, role: 'user', character_name: '', content_preview: 'hi', conversation_title: '会话A' }],
        }));
        const nav = vi.fn();
        searchView.initSearchView({ navigateToConversation: nav });

        await typeAndWait({ input }, 'hi');
        results.querySelector('.search-result-item').click();
        expect(nav).toHaveBeenCalledTimes(1);
        // T2：跳转钩子签名扩展为 (conversationId, { messageId }) — 消费 dataset.messageId
        expect(nav).toHaveBeenCalledWith(11, { messageId: 1 });
    });

    it('T2:结果 messageId 为 0/缺失 → 跳转仍调用（messageId 独立于 convId 守卫，透传 undefined）', async () => {
        const { searchView, api, input, results } = await loadModules();
        api.setFetch(mockSearch({
            results: [{ conversation_id: 11, message_id: 0, role: 'user', character_name: '', content_preview: 'hi', conversation_title: '会话A' }],
        }));
        const nav = vi.fn();
        searchView.initSearchView({ navigateToConversation: nav });

        await typeAndWait({ input }, 'hi');
        results.querySelector('.search-result-item').click();
        expect(nav).toHaveBeenCalledTimes(1);
        expect(nav).toHaveBeenCalledWith(11, { messageId: 0 });
    });

    it('结果点击 conversationId 为 0/空 → 不跳转（Falsify:parseInt 假值守卫）', async () => {
        const { searchView, api, input, results } = await loadModules();
        api.setFetch(mockSearch({
            results: [{ conversation_id: 0, message_id: 1, role: 'user', character_name: '', content_preview: 'hi', conversation_title: '会话A' }],
        }));
        const nav = vi.fn();
        searchView.initSearchView({ navigateToConversation: nav });

        await typeAndWait({ input }, 'hi');
        results.querySelector('.search-result-item').click();
        expect(nav).not.toHaveBeenCalled();
    });

    it('成功无结果 → 「未找到匹配的消息」逐字', async () => {
        const { searchView, api, input, results } = await loadModules();
        api.setFetch(mockSearch({ results: [] }));
        searchView.initSearchView({ navigateToConversation: () => {} });

        await typeAndWait({ input }, 'ab');
        expect(results.innerHTML).toBe(NOT_FOUND_HTML);
    });

    it('搜索失败 → 「搜索失败: <原因>」逐字 + 原因经 escapeHtml 转义', async () => {
        const { searchView, api, input, results } = await loadModules();
        const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
        api.setFetch(mockSearch({ fail: new Error('<b>网络错误</b>') }));
        searchView.initSearchView({ navigateToConversation: () => {} });

        await typeAndWait({ input }, 'ab');
        expect(results.innerHTML)
            .toBe('<p class="search-status search-error">搜索失败: &lt;b&gt;网络错误&lt;/b&gt;</p>');
        consoleError.mockRestore();
    });

    it('防抖连发：300ms 内多次输入只发一次请求,以最后一次输入为准', async () => {
        const { searchView, api, input } = await loadModules();
        const fetchSpy = mockSearch({ results: [] });
        api.setFetch(fetchSpy);
        searchView.initSearchView({ navigateToConversation: () => {} });

        await typeAndWait({ input }, 'a', 100);
        await typeAndWait({ input }, 'ab', 100);
        await typeAndWait({ input }, 'abc', 100);
        // 最后一次输入的防抖在 +300ms 触发（此前各次均已在前一输入时被清理）
        await vi.advanceTimersByTimeAsync(300);
        expect(fetchSpy).toHaveBeenCalledTimes(1);
        expect(fetchSpy.mock.calls[0][0]).toContain('q=abc');
    });

    it('防抖捕获输入时刻的查询（排定后修改 value 不影响已排定搜索）', async () => {
        const { searchView, api, input } = await loadModules();
        const fetchSpy = mockSearch({ results: [] });
        api.setFetch(fetchSpy);
        searchView.initSearchView({ navigateToConversation: () => {} });

        input.value = 'ab';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.value = 'zz'; // 程序化修改,不再触发 input 事件
        await vi.advanceTimersByTimeAsync(300);
        expect(fetchSpy).toHaveBeenCalledTimes(1);
        expect(fetchSpy.mock.calls[0][0]).toContain('q=ab');
    });

    it('防抖窗口：输入后 300ms 内不发起请求,超时后恰好请求一次', async () => {
        const { searchView, api, input } = await loadModules();
        const fetchSpy = mockSearch({ results: [] });
        api.setFetch(fetchSpy);
        searchView.initSearchView({ navigateToConversation: () => {} });

        input.value = 'ab';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        await vi.advanceTimersByTimeAsync(200);
        expect(fetchSpy).not.toHaveBeenCalled(); // 窗口内不请求
        await vi.advanceTimersByTimeAsync(100);
        expect(fetchSpy).toHaveBeenCalledTimes(1); // 超时后触发一次
        expect(fetchSpy.mock.calls[0][0]).toContain('q=ab');
        // 不再重复触发
        await vi.advanceTimersByTimeAsync(1000);
        expect(fetchSpy).toHaveBeenCalledTimes(1);
    });

    it('Enter → 立即搜索（不等防抖）且不重复', async () => {
        const { searchView, api, input } = await loadModules();
        const fetchSpy = mockSearch({ results: [] });
        api.setFetch(fetchSpy);
        searchView.initSearchView({ navigateToConversation: () => {} });

        input.value = 'ab';
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        expect(fetchSpy).toHaveBeenCalledTimes(1);
        expect(fetchSpy.mock.calls[0][0]).toContain('q=ab');
        await vi.advanceTimersByTimeAsync(300);
        expect(fetchSpy).toHaveBeenCalledTimes(1); // 防抖定时器已被 Enter 清理
    });

    it('Escape → 清空输入 + blur + 提示文案；已排定防抖不清理（原语义保持：仍会执行）', async () => {
        // 注意：原 app.js 的 Escape 分支只清输入不清理 searchTimeout（仅 Enter 清理），
        // 排定的防抖仍会在 300ms 后以输入时刻捕获的 query 执行 —— 行为保持，钉住原语义
        const { searchView, api, input, results } = await loadModules();
        const fetchSpy = mockSearch({ results: [] });
        api.setFetch(fetchSpy);
        const blurSpy = vi.spyOn(input, 'blur');
        searchView.initSearchView({ navigateToConversation: () => {} });

        input.value = 'ab';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        expect(input.value).toBe('');
        expect(blurSpy).toHaveBeenCalledTimes(1);
        expect(results.innerHTML).toBe(HINT_HTML);
        await vi.advanceTimersByTimeAsync(300);
        // 原语义：Escape 不清理防抖 → 已排定搜索仍执行（输入时刻捕获的 query）
        expect(fetchSpy).toHaveBeenCalledTimes(1);
        expect(fetchSpy.mock.calls[0][0]).toContain('q=ab');
    });

    it('清空按钮 → 清空输入 + focus + 提示文案', async () => {
        const { searchView, api, input, results, clearBtn } = await loadModules();
        api.setFetch(mockSearch({ results: [] }));
        const focusSpy = vi.spyOn(input, 'focus');
        searchView.initSearchView({ navigateToConversation: () => {} });

        await typeAndWait({ input }, 'ab');
        expect(results.innerHTML).toBe(NOT_FOUND_HTML);
        clearBtn.click();
        expect(input.value).toBe('');
        expect(focusSpy).toHaveBeenCalledTimes(1);
        expect(results.innerHTML).toBe(HINT_HTML);
    });

    it('Falsify:initSearchView 未注入跳转钩子 → 点击结果 no-op 不抛错', async () => {
        const { searchView, api, input, results } = await loadModules();
        api.setFetch(mockSearch({
            results: [{ conversation_id: 11, message_id: 1, role: 'user', character_name: '', content_preview: 'hi', conversation_title: '会话A' }],
        }));
        searchView.initSearchView({});

        await typeAndWait({ input }, 'hi');
        expect(() => results.querySelector('.search-result-item').click()).not.toThrow();
    });

    it('Falsify:DOM 契约被破坏(元素缺失) → initSearchView no-op 不抛错', async () => {
        vi.resetModules();
        document.body.innerHTML = ''; // 无 #search-input / #search-results / #btn-search-clear
        const searchView = await import('../js/search-view.js');
        expect(() => searchView.initSearchView({ navigateToConversation: () => {} }))
            .not.toThrow();
    });

    it('重复调用 initSearchView（ARC9-1）：不重复绑定事件 → 单次输入仅 1 次请求，且钩子更新为最新', async () => {
        const { searchView, api, input, results } = await loadModules();
        const fetchSpy = mockSearch({
            results: [{ conversation_id: 11, message_id: 1, role: 'user', character_name: '', content_preview: 'hi', conversation_title: '会话A' }],
        });
        api.setFetch(fetchSpy);
        const nav1 = vi.fn();
        const nav2 = vi.fn();
        searchView.initSearchView({ navigateToConversation: nav1 });
        searchView.initSearchView({ navigateToConversation: nav2 }); // 重复调用：仅更新钩子

        // 防抖路径：单次 input 输入推进防抖窗口 → 恰好 1 次请求
        await typeAndWait({ input }, 'hi');
        expect(fetchSpy).toHaveBeenCalledTimes(1);
        // Enter 立即搜索路径：单次按键 → 恰好 1 次请求（keydown 双绑定会双发 → 守卫缺失时红）
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        expect(fetchSpy).toHaveBeenCalledTimes(2);
        await vi.advanceTimersByTimeAsync(0); // 排空渲染微任务
        // 重复调用仍更新跳转钩子（幂等语义：钩子始终取最新注入值）
        results.querySelector('.search-result-item').click();
        expect(nav2).toHaveBeenCalledTimes(1);
        expect(nav1).not.toHaveBeenCalled();
    });
});
