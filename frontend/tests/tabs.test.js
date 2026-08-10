import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import {
    openTab,
    activateTab,
    closeTab,
    closeAllTabs,
    closeTabs,
    getActiveTab,
    getTab,
    getTabs,
    getTabDisplay,
    updateTab,
    serialize,
    restore,
    restoreFromStorage,
    onTabsChanged,
    __all__,
} from '../js/tabs.js';

// ── 测试辅助 ──

/** 读取 sessionStorage 中的序列化 tab 集（键名由模块内部决定，只验证内容） */
function readStored() {
    const keys = Object.keys(sessionStorage);
    if (keys.length === 0) return null;
    return JSON.parse(sessionStorage.getItem(keys[0]));
}

beforeEach(() => {
    sessionStorage.clear();
    closeAllTabs();
});

describe('openTab', () => {
    it('新建 tab 为初始形态（含全部会话级字段）', () => {
        const tab = openTab(1);
        expect(tab).toEqual({
            conversationId: 1,
            characterId: null,
            title: '',
            messages: [],
            scrollTop: 0,
            draft: '',
            isStreaming: false,
            activeStream: null,
            phase: 'idle',
        });
        expect(getActiveTab()).toBe(tab);
    });

    it('按 conversationId 去重：已存在仅激活并返回既有对象', () => {
        const first = openTab(1);
        openTab(2);
        const again = openTab(1);
        expect(again).toBe(first);
        expect(getTabs()).toHaveLength(2);
        expect(getActiveTab()).toBe(first);
    });

    it('多个会话依次打开，最后打开的为活动 tab', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        expect(getTabs().map((t) => t.conversationId)).toEqual([1, 2, 3]);
        expect(getActiveTab().conversationId).toBe(3);
    });

    it('null/undefined 入参 no-op，不建 tab', () => {
        expect(openTab(null)).toBeNull();
        expect(openTab(undefined)).toBeNull();
        expect(getTabs()).toHaveLength(0);
    });
});

describe('activateTab', () => {
    it('切换活动 tab', () => {
        openTab(1);
        openTab(2);
        activateTab(1);
        expect(getActiveTab().conversationId).toBe(1);
    });

    it('目标不存在 → no-op，活动不变、不抛错', () => {
        openTab(1);
        activateTab(999);
        expect(getActiveTab().conversationId).toBe(1);
        expect(getTabs()).toHaveLength(1);
    });
});

describe('closeTab', () => {
    it('关闭活动 tab 后激活右邻居', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(1);
        closeTab(1);
        expect(getActiveTab().conversationId).toBe(2);
        expect(getTabs().map((t) => t.conversationId)).toEqual([2, 3]);
    });

    it('无右邻居时激活左邻居', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(3);
        closeTab(3);
        expect(getActiveTab().conversationId).toBe(2);
    });

    it('关闭非活动 tab 不影响活动 tab', () => {
        openTab(1);
        openTab(2);
        closeTab(2);
        expect(getActiveTab().conversationId).toBe(1);
    });

    it('关最后一个 tab → activeTab 为 null', () => {
        openTab(7);
        closeTab(7);
        expect(getActiveTab()).toBeNull();
        expect(getTabs()).toHaveLength(0);
    });

    it('关闭不存在的 tab → no-op，不抛错、无变更', () => {
        openTab(1);
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        closeTab(999);
        off();
        expect(fn).not.toHaveBeenCalled();
        expect(getTabs()).toHaveLength(1);
    });
});

describe('closeAllTabs', () => {
    it('清空全部 tab 与活动 tab', () => {
        openTab(1);
        openTab(2);
        closeAllTabs();
        expect(getTabs()).toHaveLength(0);
        expect(getActiveTab()).toBeNull();
    });
});

describe('closeTabs（批量原语 — ARC-2 级联收口）', () => {
    it('批量关闭指定 tab；关闭的是活动 tab 时右邻居顶上（无则左）', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(1);
        closeTabs([1, 3]);
        expect(getTabs().map((t) => t.conversationId)).toEqual([2]);
        expect(getActiveTab()?.conversationId).toBe(2);
    });

    it('批量含活动 tab：逐 tab 移除语义与多次 closeTab 一致（先右后左）', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(2);
        closeTabs([2, 3]);
        expect(getTabs().map((t) => t.conversationId)).toEqual([1]);
        expect(getActiveTab()?.conversationId).toBe(1);
    });

    it('关最后一个 → activeTab 为 null，存储同步为 { ids: [], activeId: null }', () => {
        openTab(7);
        closeTabs([7]);
        expect(getActiveTab()).toBeNull();
        expect(getTabs()).toHaveLength(0);
        expect(readStored()).toEqual({ ids: [], activeId: null });
    });

    it('整个批次只触发一次 onTabsChanged 通知（单次 commit），而非逐 tab N 次', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        closeTabs([1, 2, 3]);
        off();
        expect(fn).toHaveBeenCalledTimes(1);
    });

    it('空数组 / 不存在的 id → no-op 无通知；重复 id 幂等只关一次', () => {
        openTab(1);
        openTab(2);
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        closeTabs([]);
        closeTabs([999, 1000]);
        off();
        expect(fn).not.toHaveBeenCalled();
        expect(getTabs()).toHaveLength(2);
        closeTabs([1, 1, 1]);
        expect(getTabs().map((t) => t.conversationId)).toEqual([2]);
    });

    it('非数组入参（null / 数字 / 字符串）→ no-op 不抛错、不关任何 tab', () => {
        openTab(1);
        openTab(2);
        expect(() => closeTabs(null)).not.toThrow();
        expect(() => closeTabs(1)).not.toThrow();
        expect(() => closeTabs('all')).not.toThrow();
        expect(getTabs()).toHaveLength(2);
        expect(getActiveTab()?.conversationId).toBe(2);
    });
});

describe('closeTabs abort 全覆盖（批量关闭先中止每个在途流式 — ARC-2）', () => {
    it('批量关闭对每个持有 activeStream 的 tab 逐一 abort', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        const abort1 = vi.fn();
        const abort3 = vi.fn();
        updateTab(1, { activeStream: { abort: abort1 } });
        updateTab(3, { activeStream: { abort: abort3 } });
        closeTabs([1, 2, 3]);
        expect(abort1).toHaveBeenCalledTimes(1);
        expect(abort3).toHaveBeenCalledTimes(1);
        expect(getTabs()).toHaveLength(0);
        expect(getActiveTab()).toBeNull();
    });

    it('abort() 抛错静默忽略，批量关闭不中断', () => {
        openTab(1);
        openTab(2);
        updateTab(1, { activeStream: { abort: () => { throw new Error('已断开'); } } });
        expect(() => closeTabs([1, 2])).not.toThrow();
        expect(getTabs()).toHaveLength(0);
    });
});

describe('updateTab', () => {
    it('浅合并 patch（标题/流式阶段/消息缓存）', () => {
        const tab = openTab(1);
        updateTab(1, { title: '新标题', phase: 'streaming', isStreaming: true });
        expect(tab.title).toBe('新标题');
        expect(tab.phase).toBe('streaming');
        expect(tab.isStreaming).toBe(true);
        expect(tab.draft).toBe('');
    });

    it('对不存在的 conversationId 幂等 no-op（关流式中的 tab 后异步写回场景）', () => {
        openTab(1);
        expect(() => updateTab(999, { phase: 'done', messages: [{ role: 'assistant' }] }))
            .not.toThrow();
        expect(getTabs()).toHaveLength(1);
        expect(getTabs()[0].phase).toBe('idle');
    });

    it('conversationId 是身份键，不可经 patch 改写', () => {
        const tab = openTab(1);
        updateTab(1, { conversationId: 2, title: 'x' });
        expect(tab.conversationId).toBe(1);
        expect(getTab(1)).toBe(tab);
        expect(getTab(2)).toBeUndefined();
    });

    it('内容更新触发 onTabsChanged（tab 条状态指示随 phase 刷新）', () => {
        openTab(1);
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        updateTab(1, { phase: 'error' });
        off();
        expect(fn).toHaveBeenCalledTimes(1);
    });
});

describe('serialize / sessionStorage', () => {
    it('serialize 只返回 ids + activeId，不含消息/草稿等缓存', () => {
        openTab(1);
        openTab(2);
        updateTab(1, {
            messages: [{ role: 'user', content: 'hi' }],
            draft: '草稿内容',
            scrollTop: 42,
            isStreaming: true,
        });
        expect(serialize()).toEqual({ ids: [1, 2], activeId: 2 });
    });

    it('结构性变更写入 sessionStorage；updateTab 内容更新不写', () => {
        openTab(1);
        openTab(2);
        updateTab(2, { draft: '草稿', phase: 'thinking' });
        const stored = readStored();
        expect(stored).toEqual({ ids: [1, 2], activeId: 2 });
    });
});

describe('restore', () => {
    it('serialize → restore 往返一致（ids 与 activeId）', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(2);
        const snapshot = serialize();
        closeAllTabs();
        restore(snapshot, { isValidId: () => true });
        expect(serialize()).toEqual({ ids: [1, 2, 3], activeId: 2 });
    });

    it('经 isValidId 过滤已删除会话；activeId 失效回退首个有效', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(2);
        const snapshot = serialize(); // { ids: [1,2,3], activeId: 2 }
        closeAllTabs();
        restore(snapshot, { isValidId: (id) => id !== 2 });
        expect(serialize()).toEqual({ ids: [1, 3], activeId: 1 });
    });

    it('全失效 → 空集，activeTab 为 null', () => {
        openTab(1);
        const snapshot = serialize();
        closeAllTabs();
        const active = restore(snapshot, { isValidId: () => false });
        expect(active).toBeNull();
        expect(getTabs()).toHaveLength(0);
        expect(serialize()).toEqual({ ids: [], activeId: null });
    });

    it('恢复的 tab 一律非流式（phase idle、isStreaming false、activeStream null）', () => {
        openTab(1);
        updateTab(1, { phase: 'streaming', isStreaming: true, activeStream: { abort: () => {} } });
        const snapshot = serialize();
        closeAllTabs();
        restore(snapshot, { isValidId: () => true });
        const tab = getTab(1);
        expect(tab.phase).toBe('idle');
        expect(tab.isStreaming).toBe(false);
        expect(tab.activeStream).toBeNull();
        expect(tab.messages).toEqual([]);
        expect(tab.draft).toBe('');
    });

    it('serialized 非法（null / 非对象 / 缺 ids）→ 空集，不抛错', () => {
        expect(() => restore(null)).not.toThrow();
        expect(getTabs()).toHaveLength(0);
        expect(() => restore('garbage')).not.toThrow();
        expect(() => restore({ activeId: 1 })).not.toThrow();
        expect(getTabs()).toHaveLength(0);
    });

    it('serialized 中重复 id 去重', () => {
        restore({ ids: [1, 1, 2], activeId: 2 }, { isValidId: () => true });
        expect(serialize()).toEqual({ ids: [1, 2], activeId: 2 });
    });
});

describe('restoreFromStorage（init 刷新恢复集成辅助 — P6.5-4）', () => {
    it('有效存储记录 → 恢复 tab 集与活动 tab，且写回存储', () => {
        closeAllTabs(); // 清空内存与存储，模拟刷新后的空状态（先于种子写入，避免被覆盖）
        sessionStorage.setItem('conver.tabs.v1', JSON.stringify({ ids: [1, 2], activeId: 2 }));
        const active = restoreFromStorage({ isValidId: () => true });
        expect(active?.conversationId).toBe(2);
        expect(serialize()).toEqual({ ids: [1, 2], activeId: 2 });
        // 恢复写回存储（键内容与内存一致）
        const stored = Object.values(sessionStorage).map((v) => JSON.parse(v)).find((v) => v?.ids);
        expect(stored).toEqual({ ids: [1, 2], activeId: 2 });
    });

    it('isValidId 过滤已删会话；activeId 失效回退首个有效', () => {
        sessionStorage.setItem('conver.tabs.v1', JSON.stringify({ ids: [1, 2], activeId: 2 }));
        const active = restoreFromStorage({ isValidId: (id) => id === 1 });
        expect(active?.conversationId).toBe(1);
        expect(serialize()).toEqual({ ids: [1], activeId: 1 });
    });

    it('存储 JSON 损坏 → 空集，不抛错', () => {
        sessionStorage.setItem('conver.tabs.v1', '{broken json');
        expect(() => restoreFromStorage()).not.toThrow();
        expect(getTabs()).toHaveLength(0);
        expect(getActiveTab()).toBeNull();
    });

    it('无存储记录 → 空集，不抛错', () => {
        expect(() => restoreFromStorage()).not.toThrow();
        expect(getTabs()).toHaveLength(0);
        expect(getActiveTab()).toBeNull();
    });

    it('恢复的 tab 一律非流式（phase idle、isStreaming false、activeStream null）', () => {
        sessionStorage.setItem('conver.tabs.v1', JSON.stringify({ ids: [1], activeId: 1 }));
        restoreFromStorage({ isValidId: () => true });
        const tab = getTab(1);
        expect(tab.phase).toBe('idle');
        expect(tab.isStreaming).toBe(false);
        expect(tab.activeStream).toBeNull();
        expect(tab.messages).toEqual([]);
    });
});

describe('onTabsChanged', () => {
    it('结构性变更各触发一次通知；无变更操作不通知', () => {
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        openTab(1); // 开 → 1
        openTab(2); // 开 → 2
        openTab(1); // 已存在但非活动 → 激活 → 3
        openTab(1); // 已是活动 → 无变更
        activateTab(2); // → 4
        activateTab(2); // 已是活动 → 无变更
        closeTab(3); // 不存在 → 无变更
        closeTab(2); // → 5
        closeAllTabs(); // → 6
        restore({ ids: [1], activeId: 1 }, { isValidId: () => true }); // → 7
        off();
        expect(fn).toHaveBeenCalledTimes(7);
    });

    it('返回的取消订阅函数生效', () => {
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        off();
        openTab(1);
        expect(fn).not.toHaveBeenCalled();
    });
});

describe('协议表面', () => {
    it('__all__ 收口全部公开函数', () => {
        expect(__all__.sort()).toEqual([
            'abortStream',
            'activateTab',
            'closeAllTabs',
            'closeTab',
            'closeTabs',
            'getActiveTab',
            'getTab',
            'getTabDisplay',
            'getTabs',
            'onTabsChanged',
            'openTab',
            'restore',
            'restoreFromStorage',
            'serialize',
            'updateTab',
        ]);
    });
});

// ══════════════════════════════════════════════════════════════════
// P6.5 code-review 修复的复现测试（F-1 / F-2 竞态）
//
// 全部经公共 seam 驱动（chat.js handleSend / app.js 侧栏激活 / tabs.js 关闭），
// 断言用户可见行为（缓存内容 / DOM 渲染 / 按钮状态 / 无崩溃）。
// 模块实例隔离：动态 import + vi.resetModules，DOM 先于模块求值就位。
// ══════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ReadableStream } from 'node:stream/web';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(fn, timeout = 800) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
        if (fn()) return;
        await sleep(5);
    }
    throw new Error('waitFor 超时');
}

/** 最小聊天域 DOM — chat.js 模块求值需要这些元素（chatDom 捕获） */
const CHAT_DOM_HTML = `
    <div id="chat-messages"></div>
    <textarea id="chat-input"></textarea>
    <button id="btn-send"></button>
    <input type="checkbox" id="toggle-stream" checked>
    <div id="chat-header"><span class="chat-title" id="chat-title-text"></span></div>
`;

/** 动态加载 chat/tabs/api（全新实例；DOM 已就位） */
async function loadChatModules() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM_HTML;
    const chat = await import('../js/chat.js');
    const tabs = await import('../js/tabs.js');
    const api = await import('../js/api.js');
    return { chat, tabs, api };
}

/** 真实 index.html body + 全新 app.js 实例（init 自动执行，fetch 须先 mock） */
async function loadAppModules() {
    vi.resetModules();
    sessionStorage.clear();
    document.body.innerHTML = INDEX_BODY;
    const app = await import('../js/app.js');
    const tabs = await import('../js/tabs.js');
    const chat = await import('../js/chat.js');
    const state = (await import('../js/state.js')).state;
    return { app, tabs, chat, state };
}

const INDEX_HTML = readFileSync(join(process.cwd(), 'index.html'), 'utf8');
const INDEX_BODY = INDEX_HTML.match(/<body[^>]*>([\s\S]*?)<\/body>/i)?.[1] ?? '';

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

const sseFrame = (type, payload) => `data: ${JSON.stringify({ type, ...payload })}\n\n`;
const ENCODER = new TextEncoder();

/** 构造 app 级 fetch mock；deferGet: Map<convId, {promise, resolve}>；
 *  DELETE 处理器就地变更传入的数组（级联场景需要） */
function makeAppMock({ characters = [], conversations, messagesByConv, deferGet }) {
    return async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        const { method = 'GET' } = options;
        if (path === '/api/characters' && method === 'GET') return mockJson(characters);
        const charMatch = path.match(/^\/api\/characters\/(\d+)$/);
        if (charMatch && method === 'DELETE') {
            const i = characters.findIndex((c) => c.id === Number(charMatch[1]));
            if (i >= 0) characters.splice(i, 1);
            return mockJson(null, 204);
        }
        if (path === '/api/conversations' && method === 'GET') return mockJson(conversations);
        if (path === '/api/conversations' && method === 'DELETE') {
            conversations.length = 0;
            return mockJson(null, 204);
        }
        if (path === '/api/models' && method === 'GET') return mockJson({ providers: [{ key: 'claude', name: 'Claude (Anthropic)', id: 'claude', models: ['claude-sonnet-5'] }] });
        if (path === '/api/settings' && method === 'GET') return mockJson({});
        if (path === '/api/settings' && method === 'PUT') return mockJson({});
        const convMatch = path.match(/^\/api\/conversations\/(\d+)$/);
        if (convMatch && method === 'GET') {
            const id = Number(convMatch[1]);
            if (deferGet?.has(id)) return deferGet.get(id).promise;
            const conv = conversations.find((c) => c.id === id);
            return conv ? mockJson(conv) : mockJson({ detail: '会话不存在' }, 404);
        }
        if (convMatch && method === 'DELETE') {
            const i = conversations.findIndex((c) => c.id === Number(convMatch[1]));
            if (i >= 0) conversations.splice(i, 1);
            return mockJson(null, 204);
        }
        const msgsMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
        if (msgsMatch && method === 'GET') return mockJson(messagesByConv[Number(msgsMatch[1])] ?? []);
        throw new Error(`未 mock 的请求: ${method} ${path}`);
    };
}

const CONVS = [
    { id: 11, character_id: 1, title: '会话11', model_provider: 'claude', model_name: 'm1', message_count: 1 },
    { id: 12, character_id: 2, title: '会话12', model_provider: 'claude', model_name: 'm1', message_count: 1 },
];
const MSGS = {
    11: [{ id: 1, role: 'assistant', content: '消息11' }],
    12: [{ id: 2, role: 'assistant', content: '消息12' }],
};

describe('F-1 同 tab 连发：陈旧 list 快照不覆盖（流式 finalizeStream）', () => {
    it('list 响应延迟返回期间连发新消息 → 旧快照不覆盖、done 后按钮即时复位', async () => {
        const { chat, tabs, api } = await loadChatModules();
        tabs.openTab(11);

        // list 第 1 次请求（finalizeStream 在途）延迟返回；后续请求立即返回服务端快照
        const staleList = {};
        staleList.promise = new Promise((resolve) => { staleList.resolve = resolve; });
        let listCalls = 0;
        let serverState = [];
        const streamCtrls = [];
        api.setFetch(async (url, options = {}) => {
            const path = String(url);
            if (path.endsWith('/api/chats/stream')) {
                let ctrl;
                const stream = new ReadableStream({ start(c) { ctrl = c; } });
                streamCtrls.push(ctrl);
                return Promise.resolve({ ok: true, status: 200, body: stream });
            }
            if (path.endsWith('/messages')) {
                listCalls += 1;
                if (listCalls === 1) return staleList.promise;
                return mockJson([...serverState]);
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });

        // 第一次发送（流式）→ 首个 token + done（finalizeStream 的 list 在途）
        chat.chatDom.chatInput.value = '第一条';
        chat.handleSend();
        await sleep(20);
        streamCtrls[0].enqueue(ENCODER.encode(sseFrame('token', { content: '你好' })));
        await sleep(10);
        streamCtrls[0].enqueue(ENCODER.encode(sseFrame('done', { message_id: 101 })));
        streamCtrls[0].close();
        await sleep(20);
        expect(listCalls).toBe(1);

        // done 后（list 未返回前）按钮即复位为发送态 — 无 ⏹→➤ UX 窗口
        expect(chat.chatDom.btnSend.textContent).toBe('➤');
        expect(chat.chatDom.btnSend.classList.contains('btn-stop')).toBe(false);

        // 同 tab 连发第二条（isStreaming 已 false → 允许发送）
        chat.chatDom.chatInput.value = '第二条';
        chat.handleSend();
        await sleep(20);
        expect(tabs.getTab(11).messages.some((m) => m.role === 'user' && m.content === '第二条')).toBe(true);

        // 旧 list 快照延迟返回（不含第二条的陈旧状态）
        staleList.resolve(mockJson([
            { id: 1, role: 'user', content: '第一条' },
            { id: 2, role: 'assistant', content: '你好' },
        ]));
        await sleep(20);

        // 核心断言：旧快照不覆盖连发的新消息；本流 streaming 标记被结算
        const msgs = tabs.getTab(11).messages;
        expect(msgs.some((m) => m.role === 'user' && m.content === '第二条')).toBe(true);
        expect(msgs.some((m) => m.role === 'user' && m.content === '第一条')).toBe(true);
        expect(msgs.filter((m) => m.streaming)).toEqual([]);
        expect(msgs.find((m) => m.role === 'assistant' && m.content === '你好')?.id).toBe(101);

        // 第二条流正常完成 → 最终与服务端一致
        serverState = [
            { id: 1, role: 'user', content: '第一条' },
            { id: 2, role: 'assistant', content: '你好' },
            { id: 3, role: 'user', content: '第二条' },
            { id: 4, role: 'assistant', content: '回复2' },
        ];
        streamCtrls[1].enqueue(ENCODER.encode(sseFrame('token', { content: '回复2' })));
        await sleep(10);
        streamCtrls[1].enqueue(ENCODER.encode(sseFrame('done', { message_id: 102 })));
        streamCtrls[1].close();
        await sleep(20);
        expect(tabs.getTab(11).messages).toEqual(serverState);
    });

    it('list 重载失败 + 期间连发 → 本地增量兜底，新消息保留、无 streaming 残留', async () => {
        const { chat, tabs, api } = await loadChatModules();
        tabs.openTab(11);

        const streamCtrls = [];
        api.setFetch(async (url) => {
            const path = String(url);
            if (path.endsWith('/api/chats/stream')) {
                let ctrl;
                const stream = new ReadableStream({ start(c) { ctrl = c; } });
                streamCtrls.push(ctrl);
                return Promise.resolve({ ok: true, status: 200, body: stream });
            }
            if (path.endsWith('/messages')) {
                // 本流与连发流的重载均失败（服务端故障）→ 走本地增量兜底
                return mockJson({ detail: '服务端故障' }, 500);
            }
            throw new Error(`未 mock 的请求: ${url}`);
        });

        chat.chatDom.chatInput.value = '第一条';
        chat.handleSend();
        await sleep(20);
        streamCtrls[0].enqueue(ENCODER.encode(sseFrame('token', { content: '你好' })));
        await sleep(10);
        streamCtrls[0].enqueue(ENCODER.encode(sseFrame('done', { message_id: 101 })));
        streamCtrls[0].close();
        await sleep(20);

        // 连发第二条（其重载同样失败）
        chat.chatDom.chatInput.value = '第二条';
        chat.handleSend();
        await sleep(20);
        streamCtrls[1].enqueue(ENCODER.encode(sseFrame('token', { content: '回复2' })));
        await sleep(10);
        streamCtrls[1].enqueue(ENCODER.encode(sseFrame('done', { message_id: 102 })));
        streamCtrls[1].close();
        await sleep(20);

        const msgs = tabs.getTab(11).messages;
        expect(msgs.some((m) => m.role === 'user' && m.content === '第一条')).toBe(true);
        expect(msgs.some((m) => m.role === 'user' && m.content === '第二条')).toBe(true);
        expect(msgs.filter((m) => m.streaming)).toEqual([]);
        expect(msgs.filter((m) => m.role === 'assistant')).toHaveLength(2);
    });
});

describe('FIX-A settle 按消息位置匹配：同字节双流不误结算', () => {
    it('两连发回复字节相同 + 旧 list 延迟返回 → 新流 streaming 消息不被旧流结算', async () => {
        const { chat, tabs, api } = await loadChatModules();
        tabs.openTab(11);

        // 流 1 的 finalizeStream 在途（list 延迟返回）；流 2 的 list 立即返回服务端快照
        const staleList = {};
        staleList.promise = new Promise((resolve) => { staleList.resolve = resolve; });
        let listCalls = 0;
        let serverState = [];
        const streamCtrls = [];
        api.setFetch(async (url, options = {}) => {
            const path = String(url);
            if (path.endsWith('/api/chats/stream')) {
                let ctrl;
                const stream = new ReadableStream({ start(c) { ctrl = c; } });
                streamCtrls.push(ctrl);
                return Promise.resolve({ ok: true, status: 200, body: stream });
            }
            if (path.endsWith('/messages')) {
                listCalls += 1;
                if (listCalls === 1) return staleList.promise;
                return mockJson([...serverState]);
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });

        // 流 1：回复字节「你好」
        chat.chatDom.chatInput.value = '第一条';
        chat.handleSend();
        await sleep(20);
        streamCtrls[0].enqueue(ENCODER.encode(sseFrame('token', { content: '你好' })));
        await sleep(10);
        streamCtrls[0].enqueue(ENCODER.encode(sseFrame('done', { message_id: 101 })));
        streamCtrls[0].close();
        await sleep(20);
        expect(listCalls).toBe(1); // 流 1 的 list 在途

        // 连发流 2 — 回复字节与流 1 完全相同
        chat.chatDom.chatInput.value = '第二条';
        chat.handleSend();
        await sleep(20);
        streamCtrls[1].enqueue(ENCODER.encode(sseFrame('token', { content: '你好' })));
        await sleep(10);

        // 此刻缓存尾部是流 2 的 streaming 消息（内容与流 1 相同 — 内容等值无法区分）
        let msgs = tabs.getTab(11).messages;
        expect(msgs.filter((m) => m.streaming)).toHaveLength(1);
        expect(msgs[msgs.length - 1].content).toBe('你好');

        // 旧 list 返回（只含流 1 的陈旧快照）→ 走陈旧分支
        staleList.resolve(mockJson([
            { id: 1, role: 'user', content: '第一条' },
            { id: 2, role: 'assistant', content: '你好' },
        ]));
        await sleep(20);

        // 核心断言：流 2 的 streaming 消息未被流 1 误结算（不得获得 101 的 id、仍 streaming）
        msgs = tabs.getTab(11).messages;
        const live = msgs.filter((m) => m.streaming);
        expect(live).toHaveLength(1);
        expect(live[0].content).toBe('你好');
        expect(live[0].id).toBeUndefined();
        // 期末 code-review finding 1 修复:stale 失配回退 anchor 写回 — 流 1 的最终
        // 消息(aA,id=101)以锚点插入保留(不误结算流 2 的同时兑现「消息不丢失」)
        expect(msgs.filter((m) => m.id === 101)).toHaveLength(1);
        expect(msgs.filter((m) => m.id === 101)[0].content).toBe('你好');

        // 流 2 正常完成 → 最终与服务端一致（其 finalize 的 list 返回完整快照）
        serverState = [
            { id: 1, role: 'user', content: '第一条' },
            { id: 2, role: 'assistant', content: '你好' },
            { id: 3, role: 'user', content: '第二条' },
            { id: 4, role: 'assistant', content: '你好' },
        ];
        streamCtrls[1].enqueue(ENCODER.encode(sseFrame('done', { message_id: 102 })));
        streamCtrls[1].close();
        await sleep(20);
        expect(tabs.getTab(11).messages).toEqual(serverState);
    });
});

describe('FIX-B 非流式双击连发守卫（原 F-1 非流式连发场景同步更新 — 连发被守卫拒绝）', () => {
    it('非流式请求在途时重复 handleSend 被拒绝：双击仅一次真实请求，草稿保留，完成后恢复', async () => {
        const { chat, tabs, api } = await loadChatModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;

        let chatCalls = 0;
        let serverState = [];
        const pendingLists = [];
        api.setFetch(async (url, options = {}) => {
            const path = String(url);
            if (path.endsWith('/api/chats')) {
                chatCalls += 1;
                const body = JSON.parse(options.body);
                serverState.push({ id: serverState.length + 1, role: 'user', content: body.content });
                serverState.push({ id: serverState.length + 1, role: 'assistant', content: `回复${body.content}` });
                return mockJson({ reply: `回复${body.content}` });
            }
            if (path.endsWith('/messages')) {
                const d = {};
                d.promise = new Promise((resolve) => { d.resolve = resolve; });
                pendingLists.push(d);
                return d.promise;
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });

        // 第一次提交（双击第 1 击）→ 真实请求在途（chat + list 挂起）
        chat.chatDom.chatInput.value = '第一条';
        chat.handleSend();
        await sleep(20);
        expect(chatCalls).toBe(1);
        expect(pendingLists).toHaveLength(1);

        // 双击第 2 击（输入框已有内容）→ 在途拒绝：不发请求、不清草稿、不追加消息
        chat.chatDom.chatInput.value = '第二条';
        chat.handleSend();
        await sleep(20);
        expect(chatCalls).toBe(1); // 仅一次真实请求
        expect(chat.chatDom.chatInput.value).toBe('第二条'); // 草稿保留（未清空）
        expect(tabs.getTab(11).messages.some((m) => m.role === 'user' && m.content === '第二条')).toBe(false);

        // 第一次完成（list 返回）→ 守卫清除 → 再次发送成功
        pendingLists[0].resolve(mockJson([...serverState]));
        await sleep(20);
        chat.chatDom.chatInput.value = '第三条';
        chat.handleSend();
        await sleep(20);
        expect(chatCalls).toBe(2);
        expect(tabs.getTab(11).messages.some((m) => m.role === 'user' && m.content === '第三条')).toBe(true);
        pendingLists[1].resolve(mockJson([...serverState]));
        await sleep(20);
        expect(tabs.getTab(11).messages).toEqual(serverState);
    });

    it('非流式请求失败后守卫清除 → 可再次发送', async () => {
        const { chat, tabs, api } = await loadChatModules();
        tabs.openTab(11);
        chat.chatDom.toggleStream.checked = false;

        let chatCalls = 0;
        api.setFetch(async (url, options = {}) => {
            const path = String(url);
            if (path.endsWith('/api/chats')) {
                chatCalls += 1;
                if (chatCalls === 1) return mockJson({ detail: '服务端故障' }, 500);
                return mockJson({ reply: '成功回复' });
            }
            if (path.endsWith('/messages')) {
                return mockJson([
                    { id: 1, role: 'user', content: '第二条' },
                    { id: 2, role: 'assistant', content: '成功回复' },
                ]);
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });

        // 第一次发送失败（chat 500）
        chat.chatDom.chatInput.value = '第一条';
        await chat.handleSend();
        expect(chatCalls).toBe(1);
        expect(document.querySelector('#chat-messages').textContent).toContain('发送失败');

        // 失败路径清除守卫 → 再次发送成功（第二次 list 返回完整快照）
        chat.chatDom.chatInput.value = '第二条';
        await chat.handleSend();
        expect(chatCalls).toBe(2);
        expect(tabs.getTab(11).messages).toEqual([
            { id: 1, role: 'user', content: '第二条' },
            { id: 2, role: 'assistant', content: '成功回复' },
        ]);
    });

    it('守卫按 tab 作用域：其他 tab 的非流式发送不被本 tab 在途请求阻塞', async () => {
        const { chat, tabs, api } = await loadChatModules();
        tabs.openTab(11);
        tabs.openTab(12); // openTab 自动激活 12 → 切回 11 作为首个发送 tab
        tabs.activateTab(11);
        chat.chatDom.toggleStream.checked = false;

        let chatCalls = 0;
        const pendingLists = [];
        api.setFetch(async (url, options = {}) => {
            const path = String(url);
            if (path.endsWith('/api/chats')) {
                chatCalls += 1;
                const body = JSON.parse(options.body);
                return mockJson({ reply: `回复${body.content}` });
            }
            if (path.endsWith('/messages')) {
                const d = {};
                d.promise = new Promise((resolve) => { d.resolve = resolve; });
                pendingLists.push(d);
                return d.promise;
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });

        // tab 11 非流式请求在途
        chat.chatDom.chatInput.value = 'tab11消息';
        chat.handleSend();
        await sleep(20);
        expect(chatCalls).toBe(1);

        // 切到 tab 12 发送 → 不被 11 的在途标记阻塞（per-tab 作用域）
        tabs.activateTab(12);
        chat.chatDom.chatInput.value = 'tab12消息';
        chat.handleSend();
        await sleep(20);
        expect(chatCalls).toBe(2);
        expect(tabs.getTab(12).messages.some((m) => m.role === 'user' && m.content === 'tab12消息')).toBe(true);

        // 收尾放行挂起的 list，避免悬挂请求
        pendingLists.forEach((d) => d.resolve(mockJson([])));
        await sleep(20);
    });
});

describe('FIX-C 热路径节流：通知分类（tab 条只订阅展示字段）', () => {
    it('messages/draft/scrollTop 纯内容 patch 不触发 onTabsChanged；title/phase 与结构性变更照常触发', async () => {
        vi.resetModules();
        const tabs = await import('../js/tabs.js');
        const fn = vi.fn();
        const off = tabs.onTabsChanged(fn);
        tabs.openTab(1); // 结构性 → 1
        tabs.updateTab(1, { messages: [{ role: 'user', content: 'x' }] }); // 纯内容 → 0
        tabs.updateTab(1, { draft: '草稿' }); // 纯内容 → 0
        tabs.updateTab(1, { scrollTop: 42 }); // 纯内容 → 0
        tabs.updateTab(1, { phase: 'streaming' }); // 展示 → 1
        tabs.updateTab(1, { title: '新标题' }); // 展示 → 1
        tabs.updateTab(1, { phase: 'done', messages: [{ role: 'assistant', content: 'y' }] }); // 混合（含展示）→ 1
        tabs.closeTab(1); // 结构性 → 1
        off();
        // 1(开) + 1(phase) + 1(title) + 1(混合含展示) + 1(关) = 5；纯内容 3 次均未通知
        expect(fn).toHaveBeenCalledTimes(5);
    });

    it('tab 条组件：messages/draft patch 不重建 innerHTML（节点引用不变）；phase/title patch 触发重建', async () => {
        vi.resetModules();
        document.body.innerHTML = CHAT_DOM_HTML;
        const tabs = await import('../js/tabs.js');
        const { initTabBar } = await import('../js/components/tab-bar.js');
        const container = document.createElement('div');
        container.id = 'chat-tabs';
        document.body.appendChild(container);
        initTabBar({ container, onActivate: () => {} });

        tabs.openTab(1);
        const firstNode = container.firstElementChild;
        expect(firstNode).not.toBeNull();
        expect(container.innerHTML).toContain('data-conv-id="1"');

        // 热路径：纯内容 patch（onToken 逐 token 的 messages 更新）→ 不重建
        tabs.updateTab(1, { messages: [{ role: 'assistant', content: 'x' }] });
        tabs.updateTab(1, { draft: '草稿' });
        expect(container.firstElementChild).toBe(firstNode);

        // 展示字段 patch → 重建（节点引用变化；生成中圆点出现）
        tabs.updateTab(1, { phase: 'streaming' });
        expect(container.firstElementChild).not.toBe(firstNode);
        expect(container.innerHTML).toContain('tab-dot');

        // 结构性变更（开新 tab）→ 重建
        tabs.openTab(2);
        expect(container.querySelectorAll('.chat-tab')).toHaveLength(2);

        // phase 归 done → 圆点消失
        tabs.updateTab(1, { phase: 'done' });
        expect(container.innerHTML).not.toContain('tab-dot');
    });
});

describe('F-2 activateConversation 无守卫异步续体（await 期间切走/关闭）', () => {
    const originalFetch = globalThis.fetch;

    afterEach(() => {
        globalThis.fetch = originalFetch;
    });

    it('conversations.get 在途时用户切走 → 旧续体不恢复草稿、不渲染错会话', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        globalThis.fetch = makeAppMock({
            conversations: [...CONVS],
            messagesByConv: MSGS,
            deferGet: new Map([[11, deferred]]),
        });
        const { tabs, state } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        const clickConv = (id) =>
            document.querySelector(`#conversation-list .conversation-item[data-id="${id}"]`).click();
        const chatInput = () => document.querySelector('#chat-input');

        // 打开 11 并输入草稿，再切到 12（11 的草稿入缓存）
        clickConv(11);
        await sleep(30);
        chatInput().value = '草稿A';
        clickConv(12);
        await sleep(30);
        expect(tabs.getTab(11)?.draft).toBe('草稿A');

        // 让 11 从已加载列表消失（如列表过期），再点 11 → 走 await conversations.get 续体
        state.conversations = state.conversations.filter((c) => c.id !== 11);
        clickConv(11);
        await sleep(30);
        // get 在途期间用户切回 12
        clickConv(12);
        await sleep(30);
        expect(tabs.getActiveTab()?.conversationId).toBe(12);

        // get 返回 → 旧续体不得恢复草稿/渲染 11
        deferred.resolve(mockJson({ ...CONVS[0] }));
        await sleep(30);

        expect(tabs.getActiveTab()?.conversationId).toBe(12);
        expect(document.querySelector('#chat-messages').textContent).toContain('消息12');
        expect(document.querySelector('#chat-messages').textContent).not.toContain('消息11');
        expect(document.querySelector('#chat-title-text').textContent).toBe('会话12');
    });

    it('conversations.get 在途时用户关闭该 tab → 无 TypeError 崩溃', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        globalThis.fetch = makeAppMock({
            conversations: [...CONVS],
            messagesByConv: MSGS,
            deferGet: new Map([[11, deferred]]),
        });
        const { tabs, state } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        const clickConv = (id) =>
            document.querySelector(`#conversation-list .conversation-item[data-id="${id}"]`).click();

        // 打开 11，让 11 从已加载列表消失，再点 11 → await conversations.get 在途
        clickConv(11);
        await sleep(30);
        state.conversations = state.conversations.filter((c) => c.id !== 11);
        clickConv(11);
        await sleep(30);
        // get 在途期间：切到 12 并关闭 11 的 tab
        clickConv(12);
        await sleep(30);
        tabs.closeTab(11);
        expect(tabs.getTab(11)).toBeUndefined();
        expect(tabs.getActiveTab()?.conversationId).toBe(12);

        // get 返回 → 旧续体必须安全退出（tab 已关：不抛 TypeError）
        const rejections = [];
        const onRejection = (reason) => rejections.push(reason);
        process.on('unhandledRejection', onRejection);
        deferred.resolve(mockJson({ ...CONVS[0] }));
        await sleep(50);
        process.off('unhandledRejection', onRejection);
        expect(rejections).toHaveLength(0);

        expect(tabs.getActiveTab()?.conversationId).toBe(12);
        expect(document.querySelector('#chat-messages').textContent).toContain('消息12');
        expect(document.querySelector('#chat-title-text').textContent).toBe('会话12');
    });

    it('conversations.get 失败（404）且在途时关闭 tab → 无崩溃、无错渲染', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        globalThis.fetch = makeAppMock({
            conversations: [...CONVS],
            messagesByConv: MSGS,
            deferGet: new Map([[11, deferred]]),
        });
        const { tabs, state } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        const clickConv = (id) =>
            document.querySelector(`#conversation-list .conversation-item[data-id="${id}"]`).click();

        clickConv(11);
        await sleep(30);
        state.conversations = state.conversations.filter((c) => c.id !== 11);
        clickConv(11);
        await sleep(30);
        clickConv(12);
        await sleep(30);
        tabs.closeTab(11);

        const rejections = [];
        const onRejection = (reason) => rejections.push(reason);
        process.on('unhandledRejection', onRejection);
        deferred.resolve(mockJson({ detail: '会话不存在' }, 404));
        await sleep(50);
        process.off('unhandledRejection', onRejection);
        expect(rejections).toHaveLength(0);

        expect(tabs.getActiveTab()?.conversationId).toBe(12);
        expect(document.querySelector('#chat-messages').textContent).toContain('消息12');
        expect(document.querySelector('#chat-title-text').textContent).toBe('会话12');
    });
});

// ══════════════════════════════════════════════════
// 低成本非阻断项（P6.5 code-review）
// ══════════════════════════════════════════════════

describe('abortStream（tabs.js 协议 — 停止/删除/关闭/清空统一中止入口）', () => {
    it('中止指定 tab 的在途流式句柄；无 tab / 无句柄 → no-op 不抛错', async () => {
        vi.resetModules();
        const tabs = await import('../js/tabs.js');
        const abort = vi.fn();
        tabs.openTab(1);
        tabs.openTab(2);
        tabs.updateTab(1, { activeStream: { abort } });
        tabs.abortStream(1);
        expect(abort).toHaveBeenCalledTimes(1);
        tabs.abortStream(2);   // 有 tab 无句柄
        tabs.abortStream(999); // 无 tab
        expect(abort).toHaveBeenCalledTimes(1);
    });

    it('abort() 抛错静默忽略（连接已断开等场景）', async () => {
        vi.resetModules();
        const tabs = await import('../js/tabs.js');
        tabs.openTab(1);
        tabs.updateTab(1, { activeStream: { abort: () => { throw new Error('已断开'); } } });
        expect(() => tabs.abortStream(1)).not.toThrow();
    });

    it('abortStream 收口进协议表面 __all__', async () => {
        vi.resetModules();
        const tabs = await import('../js/tabs.js');
        expect(tabs.__all__).toContain('abortStream');
    });
});

describe('EMPTY_STATE_HTML 共享常量（chat.js 导出，app.js 复用）', () => {
    it('chat.js 导出共享空态常量；无活动 tab 时 renderMessages 渲染它', async () => {
        const { chat, tabs } = await loadChatModules();
        expect(typeof chat.EMPTY_STATE_HTML).toBe('string');
        expect(chat.EMPTY_STATE_HTML).toContain('选择左侧对话或创建新对话开始聊天');
        chat.renderMessages();
        expect(document.querySelector('#chat-messages').innerHTML).toBe(chat.EMPTY_STATE_HTML);
        tabs.closeAllTabs();
        chat.renderMessages();
        expect(document.querySelector('#chat-messages').innerHTML).toBe(chat.EMPTY_STATE_HTML);
    });

    it('app 空态（无 tab）与共享常量逐字一致（无重复字面量）', async () => {
        globalThis.fetch = makeAppMock({ conversations: [], messagesByConv: {}, deferGet: new Map() });
        const { chat } = await loadAppModules();
        await sleep(50);
        expect(document.querySelector('#chat-messages').innerHTML).toBe(chat.EMPTY_STATE_HTML);
    });
});

describe('abort 流式三连复用 abortStream（app.js 停止按钮 / tab-bar ✕ / 删会话）+ 清空联动', () => {
    const originalFetch = globalThis.fetch;

    afterEach(() => {
        globalThis.fetch = originalFetch;
    });

    it('停止按钮：活动 tab 流式中点击 → 经 abortStream 中止', async () => {
        globalThis.fetch = makeAppMock({ conversations: [...CONVS], messagesByConv: MSGS, deferGet: new Map() });
        const { tabs } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        document.querySelector('#conversation-list .conversation-item[data-id="11"]').click();
        await sleep(30);
        const spy = vi.fn();
        tabs.updateTab(11, { isStreaming: true, activeStream: { abort: spy } });
        document.querySelector('#btn-send').click();
        await sleep(10);
        expect(spy).toHaveBeenCalledTimes(1);
        // 无流式句柄时点击回落到 handleSend（不误 abort）
        expect(() => document.querySelector('#btn-send').click()).not.toThrow();
    });

    it('tab 条 ✕：关闭流式中的 tab → 先 abort 再关，右邻居激活', async () => {
        globalThis.fetch = makeAppMock({ conversations: [...CONVS], messagesByConv: MSGS, deferGet: new Map() });
        const { tabs } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        const clickConv = (id) =>
            document.querySelector(`#conversation-list .conversation-item[data-id="${id}"]`).click();
        clickConv(11);
        await sleep(30);
        clickConv(12);
        await sleep(30);
        clickConv(11);
        await sleep(30);
        const spy = vi.fn();
        tabs.updateTab(11, { isStreaming: true, activeStream: { abort: spy } });
        document.querySelector('#chat-tabs .chat-tab[data-conv-id="11"] .tab-close').click();
        await sleep(30);
        expect(spy).toHaveBeenCalledTimes(1);
        expect(tabs.getTab(11)).toBeUndefined();
        expect(tabs.getActiveTab()?.conversationId).toBe(12);
    });

    it('tab 条 ✕ 关最后一个 tab → 统一收口：空态 + 发送按钮复位 + 列表高亮清除', async () => {
        globalThis.fetch = makeAppMock({ conversations: [...CONVS], messagesByConv: MSGS, deferGet: new Map() });
        const { tabs } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        // 只打开 11 一个 tab（活动）
        document.querySelector('#conversation-list .conversation-item[data-id="11"]').click();
        await sleep(30);
        expect(tabs.getTabs()).toHaveLength(1);

        document.querySelector('#chat-tabs .chat-tab[data-conv-id="11"] .tab-close').click();
        await sleep(30);

        expect(tabs.getTabs()).toHaveLength(0);
        expect(tabs.getActiveTab()).toBeNull();
        expect(document.querySelector('#chat-messages').innerHTML).toContain('选择左侧对话');
        expect(document.querySelector('#btn-send').textContent).toBe('➤');
        // 列表高亮清除：不再有 active 项
        expect(document.querySelectorAll('#conversation-list .conversation-item.active')).toHaveLength(0);
    });

    it('删除会话（开着流式）→ 先 abort 再关 tab，右邻居草稿不被污染', async () => {
        globalThis.fetch = makeAppMock({ conversations: [...CONVS], messagesByConv: MSGS, deferGet: new Map() });
        const { tabs } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        const clickConv = (id) =>
            document.querySelector(`#conversation-list .conversation-item[data-id="${id}"]`).click();
        const chatInput = () => document.querySelector('#chat-input');

        clickConv(11);
        await sleep(30);
        chatInput().value = '草稿A';
        clickConv(12);
        await sleep(30);
        chatInput().value = '草稿B';
        clickConv(11);
        await sleep(30);
        const spy = vi.fn();
        tabs.updateTab(11, { isStreaming: true, activeStream: { abort: spy } });

        document.querySelector('#conversation-list .conversation-item[data-id="11"] .btn-delete-conv').click();
        await sleep(10);
        document.querySelector('.confirm-ok').click();
        await sleep(50);

        expect(spy).toHaveBeenCalledTimes(1);
        expect(tabs.getTab(11)).toBeUndefined();
        expect(tabs.getActiveTab()?.conversationId).toBe(12);
        expect(tabs.getTab(12)?.draft).toBe('草稿B');
        expect(chatInput().value).toBe('草稿B');
        expect(document.querySelector('#chat-messages').textContent).toContain('消息12');
    });

    it('清空所有对话 → 先中止全部在途流式再关全部 tab', async () => {
        globalThis.fetch = makeAppMock({ conversations: [...CONVS], messagesByConv: MSGS, deferGet: new Map() });
        const { tabs } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        document.querySelector('#conversation-list .conversation-item[data-id="11"]').click();
        await sleep(30);
        document.querySelector('#conversation-list .conversation-item[data-id="12"]').click();
        await sleep(30);
        const spy = vi.fn();
        tabs.updateTab(11, { isStreaming: true, activeStream: { abort: spy } });

        document.querySelector('.nav-btn[data-view="settings"]').click();
        await sleep(30);
        document.querySelector('#btn-clear-all-convs').click();
        await sleep(10);
        document.querySelector('.confirm-ok').click();
        await sleep(50);

        expect(spy).toHaveBeenCalledTimes(1);
        expect(tabs.getTabs()).toHaveLength(0);
        expect(tabs.getActiveTab()).toBeNull();
        expect(document.querySelector('#chat-messages').innerHTML).toContain('选择左侧对话');
    });
});

describe('角色删除级联关 tab（app.js 角色删除路径）', () => {
    const originalFetch = globalThis.fetch;

    afterEach(() => {
        globalThis.fetch = originalFetch;
    });

    it('删除角色 → 其会话 tab 关闭（含在途流式中止），其他 tab 保留并激活', async () => {
        const characters = [
            { id: 1, name: '角色A', avatar: null },
            { id: 2, name: '角色B', avatar: null },
        ];
        const conversations = [
            { id: 11, character_id: 1, title: '会话11', model_provider: 'claude', model_name: 'm1', message_count: 1 },
            { id: 12, character_id: 2, title: '会话12', model_provider: 'claude', model_name: 'm1', message_count: 1 },
        ];
        const messagesByConv = {
            11: [{ id: 1, role: 'assistant', content: '消息11' }],
            12: [{ id: 2, role: 'assistant', content: '消息12' }],
        };
        globalThis.fetch = makeAppMock({ characters, conversations, messagesByConv, deferGet: new Map() });
        const { tabs } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);

        // 打开 11、12 两个 tab；11 挂上在途流式
        document.querySelector('#conversation-list .conversation-item[data-id="11"]').click();
        await sleep(30);
        document.querySelector('#conversation-list .conversation-item[data-id="12"]').click();
        await sleep(30);
        const spy = vi.fn();
        tabs.updateTab(11, { isStreaming: true, activeStream: { abort: spy } });

        // 角色视图删除角色A（其对话 11 级联删除）
        document.querySelector('.nav-btn[data-view="characters"]').click();
        await waitFor(() => document.querySelectorAll('.character-card').length === 2);
        document.querySelector('.character-card[data-id="1"] .delete-char').click();
        await sleep(10);
        document.querySelector('.confirm-ok').click();
        await sleep(60);

        expect(spy).toHaveBeenCalledTimes(1);
        expect(tabs.getTab(11)).toBeUndefined();
        expect(tabs.getTab(12)).toBeDefined();
        expect(tabs.getActiveTab()?.conversationId).toBe(12);
        expect(document.querySelector('#chat-messages').textContent).toContain('消息12');
    });

    it('被删角色的会话非活动 tab → 不再无条件重激活（停留角色视图、活动 tab 视图不重渲染）', async () => {
        const characters = [
            { id: 1, name: '角色A', avatar: null },
            { id: 2, name: '角色B', avatar: null },
        ];
        const conversations = [
            { id: 11, character_id: 1, title: '会话11', model_provider: 'claude', model_name: 'm1', message_count: 1 },
            { id: 12, character_id: 2, title: '会话12', model_provider: 'claude', model_name: 'm1', message_count: 1 },
        ];
        const messagesByConv = {
            11: [{ id: 1, role: 'assistant', content: '消息11' }],
            12: [{ id: 2, role: 'assistant', content: '消息12' }],
        };
        globalThis.fetch = makeAppMock({ characters, conversations, messagesByConv, deferGet: new Map() });
        const { tabs } = await loadAppModules();
        await waitFor(() => document.querySelectorAll('#conversation-list .conversation-item').length === 2);
        const clickConv = (id) =>
            document.querySelector(`#conversation-list .conversation-item[data-id="${id}"]`).click();

        // 打开 11、12（活动 tab 为 12 — 属角色B，不在被删角色名下）；记录消息 DOM 节点
        clickConv(11);
        await sleep(30);
        clickConv(12);
        await sleep(30);
        const msgNode = document.querySelector('#chat-messages').firstElementChild;

        // 角色视图删除角色A（其会话 11 非活动 tab）— 旧实现会无条件重激活活动 tab，
        // 副作用：切回聊天视图 + 重渲染消息区（DOM 节点重建）
        document.querySelector('.nav-btn[data-view="characters"]').click();
        await waitFor(() => document.querySelectorAll('.character-card').length === 2);
        document.querySelector('.character-card[data-id="1"] .delete-char').click();
        await sleep(10);
        document.querySelector('.confirm-ok').click();
        await sleep(60);

        // 不再无条件重激活：停留角色视图、活动 tab 12 不变、消息区未被重渲染
        expect(document.querySelector('#view-characters').classList.contains('active')).toBe(true);
        expect(document.querySelector('#view-chat').classList.contains('active')).toBe(false);
        expect(tabs.getTab(11)).toBeUndefined();
        expect(tabs.getActiveTab()?.conversationId).toBe(12);
        expect(document.querySelector('#chat-messages').firstElementChild).toBe(msgNode);
        expect(document.querySelector('#chat-messages').textContent).toContain('消息12');
    });
});

// 恢复：FIX-C 通知分类时误删的 Falsify 失败路径测试（error 帧 → handleStreamError 分支）
describe('流式 error 帧 → handleStreamError 错误分支（Falsify 失败路径补测）', () => {
    it('error 帧 → phase error + 错误气泡 + 按钮复位', async () => {
        const { chat, tabs, api } = await loadChatModules();
        tabs.openTab(11);

        api.setFetch(async (url) => {
            const path = String(url);
            if (path.endsWith('/api/chats/stream')) {
                let ctrl;
                const stream = new ReadableStream({ start(c) { ctrl = c; } });
                setTimeout(() => {
                    ctrl.enqueue(ENCODER.encode(sseFrame('error', { message: '模型超时' })));
                    ctrl.close();
                }, 0);
                return Promise.resolve({ ok: true, status: 200, body: stream });
            }
            throw new Error(`未 mock 的请求: ${path}`);
        });

        chat.chatDom.chatInput.value = '触发错误';
        await chat.handleSend();
        expect(tabs.getTab(11).phase).toBe('error');
        expect(tabs.getTab(11).isStreaming).toBe(false);
        expect(document.querySelector('#chat-messages').textContent).toContain('[错误] 模型超时');
        expect(chat.chatDom.btnSend.textContent).toBe('➤');
        expect(chat.chatDom.btnSend.classList.contains('btn-stop')).toBe(false);
    });
});

// ══════════════════════════════════════════════════
// ARC-5 展示契约：getTabDisplay（tabs.js 纯派生）＋ tab-bar 消费一致性
// ══════════════════════════════════════════════════

describe('getTabDisplay（展示契约派生 — ARC-5）', () => {
    it('纯派生：title 缺省「未命名会话」；generating=thinking|streaming；errored=error；不改输入；null 安全', () => {
        const tab = openTab(1);
        // 空 title → 缺省「未命名会话」；idle 无任何指示
        expect(getTabDisplay(tab)).toEqual({
            title: '未命名会话', phase: 'idle', generating: false, errored: false,
        });
        // 已设 title 原样透传
        updateTab(1, { title: '会话A' });
        expect(getTabDisplay(tab).title).toBe('会话A');
        // generating：thinking / streaming
        updateTab(1, { phase: 'thinking' });
        expect(getTabDisplay(tab)).toMatchObject({ generating: true, errored: false });
        updateTab(1, { phase: 'streaming' });
        expect(getTabDisplay(tab)).toMatchObject({ phase: 'streaming', generating: true, errored: false });
        // errored：error（生成中指示熄灭）
        updateTab(1, { phase: 'error' });
        expect(getTabDisplay(tab)).toMatchObject({ generating: false, errored: true });
        // done 与未知 phase → 均无指示、不抛错
        updateTab(1, { phase: 'done' });
        expect(getTabDisplay(tab)).toMatchObject({ generating: false, errored: false });
        updateTab(1, { phase: 'bogus' });
        expect(getTabDisplay(tab)).toMatchObject({ phase: 'bogus', generating: false, errored: false });
        // 纯函数：不修改输入、每次返回新对象
        const before = { ...tab };
        const a = getTabDisplay(tab);
        const b = getTabDisplay(tab);
        expect(tab).toEqual(before);
        expect(a).not.toBe(b);
        // null / undefined 入参安全：不抛错，返回缺省形态
        expect(getTabDisplay(null)).toEqual({
            title: '未命名会话', phase: 'idle', generating: false, errored: false,
        });
        expect(getTabDisplay(undefined)).toEqual({
            title: '未命名会话', phase: 'idle', generating: false, errored: false,
        });
    });
});

describe('tab-bar 消费 getTabDisplay（ARC-5 — 输出逐字节一致）', () => {
    it('渲染输出与既有行为逐字节一致：标题转义/脉冲点/警示标记/激活高亮', async () => {
        vi.resetModules();
        document.body.innerHTML = CHAT_DOM_HTML;
        const tabs = await import('../js/tabs.js');
        const { initTabBar } = await import('../js/components/tab-bar.js');
        const container = document.createElement('div');
        document.body.appendChild(container);
        initTabBar({ container, onActivate: () => {} });

        // 空 title → 缺省「未命名会话」；活动 tab 高亮（active class）
        tabs.openTab(7);
        expect(container.innerHTML).toBe(
            '\n            <div class="chat-tab active" data-conv-id="7" title="未命名会话">' +
            '\n                ' +
            '\n                ' +
            '\n                <span class="tab-title">未命名会话</span>' +
            '\n                <button class="tab-close" title="关闭会话">✕</button>' +
            '\n            </div>'
        );

        // 生成中（thinking）→ 标题前脉冲点
        tabs.updateTab(7, { title: '会话A', phase: 'thinking' });
        expect(container.innerHTML).toBe(
            '\n            <div class="chat-tab active" data-conv-id="7" title="会话A">' +
            '\n                <span class="tab-dot" title="生成中"></span>' +
            '\n                ' +
            '\n                <span class="tab-title">会话A</span>' +
            '\n                <button class="tab-close" title="关闭会话">✕</button>' +
            '\n            </div>'
        );

        // 出错（error）→ 警示标记
        tabs.updateTab(7, { phase: 'error' });
        expect(container.innerHTML).toBe(
            '\n            <div class="chat-tab active" data-conv-id="7" title="会话A">' +
            '\n                ' +
            '\n                <span class="tab-warn" title="生成出错/已停止">!</span>' +
            '\n                <span class="tab-title">会话A</span>' +
            '\n                <button class="tab-close" title="关闭会话">✕</button>' +
            '\n            </div>'
        );

        // 标题转义（< > &）；多 tab：激活高亮只落在活动 tab（8）
        tabs.updateTab(7, { title: '会话<A&B>', phase: 'done' });
        tabs.openTab(8);
        expect(container.innerHTML).toBe(
            '\n            <div class="chat-tab" data-conv-id="7" title="会话<A&amp;B>">' +
            '\n                ' +
            '\n                ' +
            '\n                <span class="tab-title">会话&lt;A&amp;B&gt;</span>' +
            '\n                <button class="tab-close" title="关闭会话">✕</button>' +
            '\n            </div>' +
            '\n            <div class="chat-tab active" data-conv-id="8" title="未命名会话">' +
            '\n                ' +
            '\n                ' +
            '\n                <span class="tab-title">未命名会话</span>' +
            '\n                <button class="tab-close" title="关闭会话">✕</button>' +
            '\n            </div>'
        );
    });
});
