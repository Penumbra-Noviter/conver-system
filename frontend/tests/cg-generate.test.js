/**
 * CG-3 对话内出图三态渲染契约测试
 *
 * 覆盖（spec §CG-3 契约锁 1/2）：
 *   1. 三态渲染：生成中（「图片生成中…（需 10-30 秒）」+ sparkles）/
 *      成功（<img src=/cg/...>）/ 失败（「图片生成失败」）
 *   2. 失败不破坏对话：failed 态 + 错误条复用 error-bar seam，消息缓存不变
 *   3. 轮询（pollImageTask）：succeeded/failed 驱动终态渲染
 *
 * 挂载：jsdom + fetch mock（api.js setFetch seam）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

const CHAT_DOM_HTML = `
    <div class="chat-main">
        <div id="chat-messages"></div>
    </div>
    <textarea id="chat-input"></textarea>
    <button id="btn-send"></button>
    <button id="btn-gen-image"></button>
    <input type="checkbox" id="toggle-stream" checked>
    <div id="chat-header"><span class="chat-title"></span></div>
`;

async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM_HTML;
    const chat = await import('../js/chat.js');
    const tabs = await import('../js/tabs.js');
    const state = (await import('../js/state.js')).state;
    const api = await import('../js/api.js');
    return { chat, tabs, state, api };
}

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

describe('CG-3 出图三态渲染', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('pending 态：sparkles 图标 + 「需 10-30 秒」提示文案', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ id: 1, role: 'user', content: '你好' }] });

        chat.renderCgTaskState(11, 101, 'pending');

        const el = document.querySelector('[data-cg-task-id="101"]');
        expect(el).not.toBeNull();
        expect(el.textContent).toContain('图片生成中');
        expect(el.textContent).toContain('10-30 秒');
        expect(el.querySelector('[data-icon="sparkles"]')).not.toBeNull();
    });

    it('succeeded 态：<img> 映射 /cg 静态挂载', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [] });

        chat.renderCgTaskState(11, 101, 'succeeded', { resultUrl: 'C:\\data\\cg\\cg_001.png' });

        const img = document.querySelector('[data-cg-task-id="101"] img.cg-task-image');
        expect(img).not.toBeNull();
        expect(img.getAttribute('src')).toBe('/cg/cg_001.png');
    });

    it('failed 态：渲染「图片生成失败」文案', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [] });

        chat.renderCgTaskState(11, 101, 'failed', { error: 'boom' });

        expect(document.querySelector('[data-cg-task-id="101"]').textContent).toContain('图片生成失败');
    });

    it('会话隔离：非活动 tab 不渲染（返回 null）', async () => {
        const { chat, tabs } = await loadModules();
        tabs.openTab(11);
        tabs.openTab(22); // 活动 = 22
        tabs.updateTab(11, { messages: [] });

        const el = chat.renderCgTaskState(11, 101, 'pending');

        expect(el).toBeNull();
        expect(document.querySelector('[data-cg-task-id="101"]')).toBeNull();
    });
});

describe('CG-3 出图轮询', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('轮询 succeeded → 终态渲染成功图', async () => {
        const { chat, tabs, api } = await loadModules();
        tabs.openTab(11);
        tabs.updateTab(11, { messages: [{ id: 1, role: 'user', content: '你好' }] });
        const getTask = vi.fn(async () => mockJson({ id: 101, status: 'succeeded', result_url: 'C:\\data\\cg\\ok.png' }));
        api.setFetch(getTask);
        const pendingEl = chat.renderCgTaskState(11, 101, 'pending');

        await chat.pollImageTask(101, pendingEl, 11, 0);

        const img = document.querySelector('[data-cg-task-id="101"] img.cg-task-image');
        expect(img).not.toBeNull();
        expect(img.getAttribute('src')).toBe('/cg/ok.png');
    });

    it('轮询 failed → 失败态 + 错误条（不破坏对话——消息缓存不变）', async () => {
        const { chat, tabs, api } = await loadModules();
        const msgs = [{ id: 1, role: 'user', content: '你好' }];
        tabs.openTab(11);
        tabs.updateTab(11, { messages: msgs });
        const getTask = vi.fn(async () => mockJson({ id: 101, status: 'failed', error: '后端挂了' }));
        api.setFetch(getTask);
        const pendingEl = chat.renderCgTaskState(11, 101, 'pending');

        await chat.pollImageTask(101, pendingEl, 11, 0);

        expect(document.querySelector('[data-cg-task-id="101"]').textContent).toContain('图片生成失败');
        // 错误条复用现有 seam
        const bar = document.querySelector('.chat-main .chat-error-bar');
        expect(bar).not.toBeNull();
        expect(bar.textContent).toContain('后端挂了');
        // 消息缓存不变（失败不破坏对话）
        expect(tabs.getTab(11).messages).toEqual(msgs);
    });
});
