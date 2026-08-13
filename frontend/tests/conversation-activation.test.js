/**
 * conversation-activation 深模块测试（ARC-6 从 app.js 提取的激活编排）
 * 覆盖:统一激活流程 / 草稿滚动保存恢复 / F-2 双 await 守卫 / 懒加载 / 空态 / hooks 注入
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const CHAT_DOM_HTML = `
    <div id="chat-messages"></div>
    <textarea id="chat-input"></textarea>
    <button id="btn-send"></button>
    <input type="checkbox" id="toggle-stream" checked>
    <div id="chat-header"><span class="chat-title" id="chat-title-text"></span></div>
`;

async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM_HTML;
    const activation = await import('../js/conversation-activation.js');
    const tabs = await import('../js/tabs.js');
    const chat = await import('../js/chat.js');
    const state = (await import('../js/state.js')).state;
    const api = await import('../js/api.js');
    return { activation, tabs, chat, state, api };
}

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

const msg = (id, role, content) => ({ id, role, content });

function makeMock({ conversations = [], messagesByConv = {} } = {}) {
    return async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        if (path === '/api/conversations' && (!options.method || options.method === 'GET')) {
            return mockJson(conversations);
        }
        const getMatch = path.match(/^\/api\/conversations\/(\d+)$/);
        if (getMatch && (!options.method || options.method === 'GET')) {
            const conv = conversations.find((c) => c.id === Number(getMatch[1]));
            return conv ? mockJson(conv) : mockJson({ detail: 'not found' }, 404);
        }
        const listMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
        if (listMatch) {
            return mockJson(messagesByConv[Number(listMatch[1])] ?? []);
        }
        throw new Error(`未 mock 的请求: ${path}`);
    };
}

describe('activateConversation — 统一激活流程', () => {
    beforeEach(() => { vi.restoreAllMocks(); });

    it('已知对话:openTab 去重 + 补全 title/characterId + 懒加载消息 + 头部渲染 + 发送按钮', async () => {
        const { activation, tabs, state, chat } = await loadModules();
        state.conversations = [
            { id: 11, title: '对话A', character_id: 1, model_name: 'm', model_provider: 'p' },
        ];
        globalThis.fetch = makeMock({ messagesByConv: { 11: [msg(1, 'user', 'hi')] } });
        const renderConv = vi.fn();
        const switchView = vi.fn();
        const showError = vi.fn();
        // F4 收口后头部渲染直 import chat.js — 经模块 spy 断言调用
        const renderHeader = vi.spyOn(chat, 'renderChatHeader');
        activation.setActivationHooks({ renderConversations: renderConv, switchView, showError });

        await activation.activateConversation(11);

        const tab = tabs.getTab(11);
        expect(tab).toBeDefined();
        expect(tab.title).toBe('对话A');
        expect(tab.characterId).toBe(1);
        expect(tab.messages).toEqual([msg(1, 'user', 'hi')]);
        expect(renderHeader).toHaveBeenCalledWith(11);
        expect(renderConv).toHaveBeenCalled();
        expect(tabs.getActiveTab()?.conversationId).toBe(11);
    });

    it('未知对话:经 conversations.get 补全;get 失败不抛错', async () => {
        const { activation, tabs, state } = await loadModules();
        state.conversations = [];
        globalThis.fetch = makeMock({
            conversations: [{ id: 99, title: '远程', character_id: 7, model_name: 'm', model_provider: 'p' }],
        });
        activation.setActivationHooks({});
        await activation.activateConversation(99);
        const tab = tabs.getTab(99);
        expect(tab.title).toBe('远程');
        expect(tab.characterId).toBe(7);
    });

    it('saveCurrent:false 时保存当前视图钩子不被调用(联动场景)', async () => {
        const { activation, tabs, state } = await loadModules();
        state.conversations = [{ id: 11, title: 'A', character_id: 1 }];
        globalThis.fetch = makeMock({});
        const spy = vi.spyOn(activation, 'saveTabViewState');
        await activation.activateConversation(11, { saveCurrent: false });
        expect(spy).not.toHaveBeenCalled();
    });

    it('F-2:conversations.get await 期间用户切走 → 放弃续体(不补全不渲染)', async () => {
        const { activation, tabs, state } = await loadModules();
        state.conversations = [];
        // 延迟 get,期间用户已切到另一个 tab
        let resolveGet;
        globalThis.fetch = async (url) => {
            const path = String(url);
            if (path.endsWith('/conversations/99')) {
                await new Promise((r) => { resolveGet = r; });
                return mockJson({ id: 99, title: '远程', character_id: 7 });
            }
            if (path.endsWith('/messages')) return mockJson([]);
            return mockJson({});
        };
        activation.setActivationHooks({ renderConversations: () => {}, switchView: () => {} });

        const p = activation.activateConversation(99);
        // 用户切走:激活另一个会话
        await activation.activateConversation(11);
        resolveGet();
        await p;

        expect(tabs.getTab(99).title).not.toBe('远程'); // 续体放弃,未补全
        expect(tabs.getActiveTab()?.conversationId).toBe(11);
    });

    it('F-2:await 期间该 tab 被关闭 → 无 TypeError 崩溃', async () => {
        const { activation, tabs, state } = await loadModules();
        state.conversations = [];
        let resolveGet;
        globalThis.fetch = async (url) => {
            if (String(url).endsWith('/conversations/99')) {
                await new Promise((r) => { resolveGet = r; });
                return mockJson({ id: 99, title: '远程', character_id: 7 });
            }
            if (String(url).endsWith('/messages')) return mockJson([]);
            return mockJson({});
        };
        activation.setActivationHooks({});
        const p = activation.activateConversation(99);
        tabs.closeTab(99); // await 期间关闭
        resolveGet();
        await expect(p).resolves.toBeUndefined(); // 无 unhandled rejection
    });
});

describe('loadTabMessages — 懒加载与活动校验', () => {
    it('缓存非空 → 不请求,直接渲染 + 恢复滚动位置', async () => {
        const { activation, tabs, chat } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [msg(1, 'user', 'cached')], scrollTop: 42 });
        const fetchSpy = vi.fn(makeMock({}));
        globalThis.fetch = fetchSpy;
        // F4 收口后头部渲染直 import chat.js — 经模块 spy 断言调用
        const renderHeader = vi.spyOn(chat, 'renderChatHeader');
        activation.setActivationHooks({ showError: () => {} });
        const renderSpy = vi.spyOn(chat, 'renderMessages');

        await activation.loadTabMessages(11);
        expect(fetchSpy).not.toHaveBeenCalled();
        expect(renderSpy).toHaveBeenCalled();
        expect(chat.chatDom.chatMessages.scrollTop).toBe(42);
        expect(renderHeader).toHaveBeenCalledWith(11);
    });

    it('缓存空 → 请求 + 写缓存 + 活动渲染;失败 → showError + 兜底渲染', async () => {
        const { activation, tabs, chat } = await loadModules();
        tabs.openTab(11);
        const showError = vi.fn();
        activation.setActivationHooks({ showError });

        // 成功路径
        globalThis.fetch = makeMock({ messagesByConv: { 11: [msg(1, 'user', 'fresh')] } });
        await activation.loadTabMessages(11);
        expect(tabs.getTab(11).messages).toEqual([msg(1, 'user', 'fresh')]);

        // 失败路径(新 tab)
        tabs.openTab(12);
        globalThis.fetch = async () => mockJson({ detail: 'boom' }, 500);
        await activation.loadTabMessages(12);
        expect(showError).toHaveBeenCalledWith('加载消息失败');
        expect(chat.chatDom.chatMessages.textContent).toContain('开始');
    });

    it('非活动 tab 的响应不渲染(后返回不覆盖先返回)', async () => {
        const { activation, tabs, chat } = await loadModules();
        tabs.openTab(11);
        tabs.openTab(12); // 12 活动
        let resolve11;
        globalThis.fetch = async (url) => {
            if (String(url).endsWith('/conversations/11/messages')) {
                await new Promise((r) => { resolve11 = r; });
                return mockJson([msg(1, 'user', 'late')]);
            }
            return mockJson([]);
        };
        activation.setActivationHooks({ showError: () => {} });
        const renderSpy = vi.spyOn(chat, 'renderMessages');

        const p = activation.loadTabMessages(11); // 非活动请求
        resolve11();
        await p;
        // 缓存写入了,但不渲染 11 的内容到视图
        expect(tabs.getTab(11).messages).toEqual([msg(1, 'user', 'late')]);
        expect(renderSpy).not.toHaveBeenCalled();
    });
});

describe('saveTabViewState / restoreTabViewState / showEmptyState', () => {
    it('保存草稿与滚动到活动 tab 缓存;恢复写回 DOM', async () => {
        const { activation, tabs, chat } = await loadModules();
        tabs.openTab(11);
        chat.chatDom.chatInput.value = '草稿内容';
        chat.chatDom.chatMessages.scrollTop = 123;
        activation.saveTabViewState();
        expect(tabs.getTab(11).draft).toBe('草稿内容');
        expect(tabs.getTab(11).scrollTop).toBe(123);

        chat.chatDom.chatInput.value = '';
        chat.chatDom.chatMessages.scrollTop = 0;
        activation.restoreTabViewState(tabs.getTab(11));
        expect(chat.chatDom.chatInput.value).toBe('草稿内容');
        expect(chat.chatDom.chatMessages.scrollTop).toBe(123);
    });

    it('restore 对已关闭 tab(undefined)no-op 不抛错', () => {
        return loadModules().then(({ activation }) => {
            expect(() => activation.restoreTabViewState(undefined)).not.toThrow();
        });
    });

    it('showEmptyState 渲染头部提示 + 共享空态常量', async () => {
        const { activation, chat } = await loadModules();
        activation.showEmptyState();
        expect(chat.chatDom.chatHeader.textContent).toContain('选择一个角色开始对话');
        expect(chat.chatDom.chatMessages.textContent).toContain('选择左侧对话或创建新对话开始聊天');
    });

    it('hooks 未注入时 activateConversation 全程 no-op 不抛错', async () => {
        const { activation, state } = await loadModules();
        state.conversations = [{ id: 11, title: 'A', character_id: 1 }];
        globalThis.fetch = makeMock({ messagesByConv: { 11: [] } });
        await expect(activation.activateConversation(11)).resolves.toBeUndefined();
    });
});
