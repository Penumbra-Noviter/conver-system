/**
 * MS-2 swipes 前端契约锁 — 候选控制条（‹ n/m ›）
 *
 * 覆盖（spec §MS-2）：
 *   1. 候选计数渲染：swipes.length > 1 → 控制条 + 计数（n/m）；单选不渲染控制条
 *   2. 切换调用参数：‹/› 点击 → messages.switchSwipe(messageId, index) 落库
 *   3. 失败回滚：switch-swipe 失败 → content/active 恢复原候选 + 错误条
 *   4. 边界：首/末候选点击不越界、无活动 tab / 单选防御 no-op
 *
 * 挂载模式：jsdom + vi.resetModules() + 内联 chatDom（与 chat.test.js 同构）+ fetch mock
 * （api.js setFetch seam）。断言纪律：优先 spy 调用参数与状态还原，DOM 断言仅关键文案。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

/** chatDom 五件套 — 与 index.html 的 id 契约一致（只读契约） */
const CHAT_DOM_HTML = `
    <div id="chat-messages"></div>
    <textarea id="chat-input"></textarea>
    <button id="btn-send"></button>
    <input type="checkbox" id="toggle-stream" checked>
    <div id="chat-header"><span class="chat-title" id="chat-title-text"></span></div>
    <div class="chat-sidebar"></div>
`;

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

/** fetch mock 路由（api.js doFetch seam 消费） */
function makeApiMock({ switchSwipe = null } = {}) {
    return vi.fn(async (url, options = {}) => {
        const path = String(url).replace(/^.*\/api/, '/api');
        const method = options.method || 'GET';
        const m = path.match(/^\/api\/messages\/(\d+)\/switch-swipe$/);
        if (m && method === 'POST') {
            if (switchSwipe === 'fail') return mockJson({ detail: '切换失败' }, 400);
            return mockJson({ id: Number(m[1]), content: '切换后', active_swipe_index: 1 });
        }
        return mockJson({ detail: '未匹配路由' }, 404);
    });
}

async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM_HTML;
    const chat = await import('../js/chat.js');
    const tabs = await import('../js/tabs.js');
    const api = await import('../js/api.js');
    return { chat, tabs, api };
}

function seedTab(tabs, messages) {
    // 克隆消息对象：共享常量 SWIPE_MSG 可能被乐观更新就地突变，防跨用例污染
    const cloned = messages.map((m) => ({ ...m, swipes: [...(m.swipes ?? [])] }));
    tabs.openTab(11);
    tabs.updateTab(11, { messages: cloned, characterId: 1 });
}

const SWIPE_MSG = {
    id: 5,
    role: 'assistant',
    content: '候选一',
    swipes: ['候选一', '候选二', '候选三'],
    active_swipe_index: 0,
};

beforeEach(() => {
    document.body.innerHTML = '';
});

describe('1. 候选计数渲染', () => {
    it('swipes > 1 → 渲染控制条 + 计数 n/m', async () => {
        const { chat, tabs } = await loadModules();
        seedTab(tabs, [SWIPE_MSG]);
        chat.renderMessages();
        const bar = document.querySelector('[data-swipe-bar]');
        expect(bar).not.toBeNull();
        expect(document.querySelector('[data-swipe-count]').textContent).toBe('1/3');
    });

    it('单选（swipes ≤ 1）→ 不渲染控制条', async () => {
        const { chat, tabs } = await loadModules();
        seedTab(tabs, [{ id: 5, role: 'assistant', content: '单选', swipes: ['单选'], active_swipe_index: 0 }]);
        chat.renderMessages();
        expect(document.querySelector('[data-swipe-bar]')).toBeNull();
    });

    it('无 swipes 字段（旧消息）→ 不渲染控制条', async () => {
        const { chat, tabs } = await loadModules();
        seedTab(tabs, [{ id: 5, role: 'assistant', content: '旧消息' }]);
        chat.renderMessages();
        expect(document.querySelector('[data-swipe-bar]')).toBeNull();
    });
});

describe('2. 切换调用参数（乐观 + 落库）', () => {
    it('点击下一候选 → 乐观切换渲染 + switchSwipe 调用参数正确', async () => {
        const { chat, tabs, api } = await loadModules();
        const fetchMock = makeApiMock();
        api.setFetch(fetchMock);
        seedTab(tabs, [SWIPE_MSG]);
        chat.renderMessages();

        document.querySelector('.swipe-next').click();
        await new Promise((r) => setTimeout(r, 0));

        // 乐观更新生效（content 跟随激活 + 计数更新）
        const msg = tabs.getTab(11).messages[0];
        expect(msg.content).toBe('候选二');
        expect(msg.active_swipe_index).toBe(1);
        expect(document.querySelector('[data-swipe-count]').textContent).toBe('2/3');
        // 落库调用参数：POST /api/messages/{id}/switch-swipe，body {index: 1}
        expect(fetchMock).toHaveBeenCalledWith(
            expect.stringContaining('/api/messages/5/switch-swipe'),
            expect.objectContaining({ method: 'POST', body: JSON.stringify({ index: 1 }) })
        );
    });

    it('边界：末候选点下一 → 不越界不调用', async () => {
        const { chat, tabs, api } = await loadModules();
        const fetchMock = makeApiMock();
        api.setFetch(fetchMock);
        seedTab(tabs, [{ ...SWIPE_MSG, active_swipe_index: 2 }]);
        chat.renderMessages();

        document.querySelector('.swipe-next').click();
        await new Promise((r) => setTimeout(r, 0));
        expect(fetchMock).not.toHaveBeenCalledWith(
            expect.stringContaining('/switch-swipe'), expect.anything()
        );
    });
});

describe('3. 失败回滚', () => {
    it('switch-swipe 失败 → content/active 恢复原候选', async () => {
        const { chat, tabs, api } = await loadModules();
        const fetchMock = makeApiMock({ switchSwipe: 'fail' });
        api.setFetch(fetchMock);
        seedTab(tabs, [SWIPE_MSG]);
        chat.renderMessages();

        document.querySelector('.swipe-next').click();
        await new Promise((r) => setTimeout(r, 0));
        await new Promise((r) => setTimeout(r, 0));

        // 失败 mock 确被调用（switch-swipe 请求真实发出）
        expect(fetchMock).toHaveBeenCalledWith(
            expect.stringContaining('/api/messages/5/switch-swipe'),
            expect.anything()
        );

        const msg = tabs.getTab(11).messages[0];
        expect(msg.content).toBe('候选一'); // 回滚
        expect(msg.active_swipe_index).toBe(0);
        expect(document.querySelector('[data-swipe-count]').textContent).toBe('1/3');
    });
});
describe('4. 重叠切换并发保护（generation token）', () => {
    it('旧调用失败但已有更新调用 → 不回滚（UI 与服务端一致）', async () => {
        const { chat, tabs, api } = await loadModules();
        // deferred mock：手动控制每个 switch-swipe 请求的 resolve/reject 时序
        const deferreds = [];
        const fetchMock = vi.fn((url) => {
            if (String(url).includes('/switch-swipe')) {
                return new Promise((resolve, reject) => {
                    deferreds.push({ resolve, reject });
                });
            }
            return Promise.resolve({ ok: true, status: 200, json: async () => ({}) });
        });
        api.setFetch(fetchMock);
        seedTab(tabs, [SWIPE_MSG]);
        chat.renderMessages();

        // 连点两次：调用 1（index 1）挂起 → 调用 2（index 2）挂起
        document.querySelector('.swipe-next').click(); // 乐观 → 候选二
        document.querySelector('.swipe-next').click(); // 乐观 → 候选三
        expect(deferreds.length).toBe(2);

        // 调用 2 成功（服务端确认候选三）→ 调用 1 失败（旧调用）
        deferreds[1].resolve({ ok: true, status: 200, json: async () => ({}) });
        await new Promise((r) => setTimeout(r, 0));
        deferreds[0].reject(new Error('旧调用失败'));
        await new Promise((r) => setTimeout(r, 0));

        // generation token：旧调用失败不回滚，UI 保持最新候选（与服务端一致）
        const msg = tabs.getTab(11).messages[0];
        expect(msg.content).toBe('候选三');
        expect(msg.active_swipe_index).toBe(2);
        expect(document.querySelector('[data-swipe-count]').textContent).toBe('3/3');
    });
});
