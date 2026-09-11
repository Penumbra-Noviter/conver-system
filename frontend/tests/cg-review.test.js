/**
 * cg-review.js 剧情回顾视图契约测试（CG-3）
 *
 * 覆盖：cgImageUrl（本地路径 → /cg basename / URL 原样 / 空 → ''）、
 *   renderCgTimeline（null 角色空态 / 空列表空态 / 时间线条目渲染 + 转义）。
 *
 * 挂载：jsdom + fetch mock（api.js setFetch seam），与 chat.test.js 同构。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

const CHAT_DOM = `
    <div id="cg-timeline" class="cg-timeline"></div>
`;

async function loadModule() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM;
    const cg = await import('../js/cg-review.js');
    const api = await import('../js/api.js');
    return { cg, api };
}

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

describe('cgImageUrl — 本地路径映射 /cg 静态挂载', () => {
    it('本地绝对路径 → /cg/<basename>', async () => {
        const { cg } = await loadModule();
        expect(cg.cgImageUrl('C:\\data\\cg\\cg_20260911_001.png')).toBe('/cg/cg_20260911_001.png');
        expect(cg.cgImageUrl('/data/cg/cg_002.png')).toBe('/cg/cg_002.png');
    });

    it('http(s) URL 原样返回', async () => {
        const { cg } = await loadModule();
        expect(cg.cgImageUrl('https://example.com/a.png')).toBe('https://example.com/a.png');
    });

    it('空/缺失 → 空串', async () => {
        const { cg } = await loadModule();
        expect(cg.cgImageUrl('')).toBe('');
        expect(cg.cgImageUrl(null)).toBe('');
        expect(cg.cgImageUrl(undefined)).toBe('');
    });
});

describe('renderCgTimeline — 时间线三态', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('null 角色 → 空态提示（不请求）', async () => {
        const { cg, api } = await loadModule();
        const spy = vi.fn();
        api.setFetch(spy);

        await cg.renderCgTimeline(null);

        expect(spy).not.toHaveBeenCalled();
        expect(document.querySelector('#cg-timeline').textContent).toContain('打开一个角色对话');
    });

    it('空列表 → 空态提示', async () => {
        const { cg, api } = await loadModule();
        api.setFetch(vi.fn(async (url) => mockJson([], 200)));
        // 路由：GET /characters/{id}/cg-timeline 返回 []
        api.setFetch(vi.fn(async () => mockJson([])));

        await cg.renderCgTimeline(7);

        expect(document.querySelector('#cg-timeline').textContent).toContain('暂无已解锁');
    });

    it('时间线条目按后端序渲染 + 内容转义 + img 映射 /cg', async () => {
        const { cg, api } = await loadModule();
        const items = [
            { cg_id: 1, url: 'C:\\data\\cg\\a.png', group_name: 'g', message_content: '第一段 <script>', message_created_at: '2024-01-01' },
            { cg_id: 2, url: 'C:\\data\\cg\\b.png', group_name: 'g', message_content: '第二段', message_created_at: '2024-02-01' },
        ];
        api.setFetch(vi.fn(async () => mockJson(items)));

        await cg.renderCgTimeline(7);

        const container = document.querySelector('#cg-timeline');
        const images = [...container.querySelectorAll('img.cg-timeline-image')];
        expect(images.map((i) => i.getAttribute('src'))).toEqual(['/cg/a.png', '/cg/b.png']);
        // 顺序 = 后端序（消息时间升序），前端不重排
        const captions = [...container.querySelectorAll('.cg-timeline-caption')].map((p) => p.textContent);
        expect(captions).toEqual(['第一段 <script>', '第二段']);
        // 转义：<script> 作为文本存在（无注入元素）
        expect(container.querySelector('script')).toBeNull();
    });

    it('加载失败 → 错误空态', async () => {
        const { cg, api } = await loadModule();
        api.setFetch(vi.fn(async () => { throw new Error('网络错误'); }));

        await cg.renderCgTimeline(7);

        expect(document.querySelector('#cg-timeline').textContent).toContain('回顾加载失败');
    });
});
