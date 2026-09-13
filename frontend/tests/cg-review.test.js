/**
 * cg-review.js 剧情回顾视图契约测试（CG-3 / T5）
 *
 * 覆盖：
 *   CG-3 — cgImageUrl（本地路径 → /cg basename / URL 原样 / 空 → ''）、
 *     renderCgTimeline（null 角色空态 / 空列表空态 / 时间线条目渲染 + 转义）。
 *   T5 — 页签壳自建（幂等）/ 画廊网格（id 降序、锁定灰态不泄原图、hint、special）/
 *     解锁（确认/取消）/ 大图 / 录入表单（校验 + create + 刷新）/ 失败错误条 / 图标 seam。
 *
 * 挂载：jsdom + fetch mock（api.js setFetch seam）或 vi.spyOn(api.images.*)，
 *   tabs.js 真实实例注入活动角色（getActiveCharacterId 数据源）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

const CHAT_DOM = `
    <div id="cg-timeline" class="cg-timeline"></div>
`;

// T5 画廊视图 DOM 契约：与 index.html 现状一致（页签壳 + #cg-gallery 由 cg-review.js 自建）
const CG_DOM_HTML = `
    <section id="view-cg" class="view active">
        <div class="view-header"><h2>剧情回顾</h2></div>
        <div id="cg-timeline" class="cg-timeline"></div>
    </section>
`;

async function loadModule() {
    vi.resetModules();
    document.body.innerHTML = CHAT_DOM;
    const cg = await import('../js/cg-review.js');
    const api = await import('../js/api.js');
    return { cg, api };
}

async function loadGalleryModule() {
    vi.resetModules();
    document.body.innerHTML = CG_DOM_HTML;
    const cg = await import('../js/cg-review.js');
    const api = await import('../js/api.js');
    const tabs = await import('../js/tabs.js');
    tabs.closeAllTabs();
    return { cg, api, tabs };
}

/** 注入活动 tab 并赋予角色 id（getActiveCharacterId 数据源） */
function setActiveCharacter(tabs, characterId) {
    tabs.openTab(123);
    tabs.updateTab(123, { characterId });
}

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

const flush = () => new Promise((r) => setTimeout(r, 0));

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
        const captions = [...container.querySelectorAll('.cg-timeline-caption')].map((p) => p.textContent);
        expect(captions).toEqual(['第一段 <script>', '第二段']);
        expect(container.querySelector('script')).toBeNull();
    });

    it('加载失败 → 错误空态', async () => {
        const { cg, api } = await loadModule();
        api.setFetch(vi.fn(async () => { throw new Error('网络错误'); }));

        await cg.renderCgTimeline(7);

        expect(document.querySelector('#cg-timeline').textContent).toContain('回顾加载失败');
    });
});

// ════════════════════════════════════════════════════════════════════════
// T5 画廊页签 + 录入表单 + 锁定态交互
// ════════════════════════════════════════════════════════════════════════
describe('cg-review T5 — 画廊页签与网格（mock api.js + DOM）', () => {
    beforeEach(() => {
        vi.restoreAllMocks();
    });
    afterEach(() => {
        vi.restoreAllMocks();
    });

    it('renderCgTimeline 首次调用自建页签壳：默认时间线可见、画廊容器隐藏', async () => {
        const { cg, api } = await loadGalleryModule();
        vi.spyOn(api.images, 'cgTimeline').mockResolvedValue([]);

        await cg.renderCgTimeline(null);

        expect(document.querySelectorAll('.cg-tab').length).toBe(2);
        expect(document.querySelector('[data-cg-tab="timeline"]').classList.contains('active')).toBe(true);
        expect(document.querySelector('#cg-timeline').hidden).toBe(false);
        expect(document.querySelector('#cg-gallery')).not.toBeNull();
        expect(document.querySelector('#cg-gallery').hidden).toBe(true);
    });

    it('切到画廊 → images.list 按 id 降序渲染全量 CG；锁定项灰态不加载原图 + hint + special', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        const listSpy = vi.spyOn(api.images, 'list').mockResolvedValue([
            { id: 3, character_id: 7, url: '/cg/three.png', group_name: '高潮', weight: 100, unlock_hint: '提示三', is_special: true, unlocked: false, created_at: '2026-01-03' },
            { id: 2, character_id: 7, url: '/cg/two.png', group_name: '结尾', weight: 100, unlock_hint: '提示二', is_special: false, unlocked: true, created_at: '2026-01-02' },
            { id: 1, character_id: 7, url: '/cg/one.png', group_name: '开场', weight: 100, unlock_hint: '提示一', is_special: false, unlocked: true, created_at: '2026-01-01' },
        ]);

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();

        expect(listSpy).toHaveBeenCalledWith(7);
        expect(document.querySelector('[data-cg-tab="gallery"]').classList.contains('active')).toBe(true);
        const tiles = [...document.querySelectorAll('.cg-tile')];
        // 后端 id 降序契约：前端不重排，按返回序渲染
        expect(tiles.map((t) => t.dataset.cgId)).toEqual(['3', '2', '1']);

        // 锁定项（id 3）：灰态占位（无 img src，不泄原图），hint + special 标记
        const locked = tiles[0];
        expect(locked.classList.contains('cg-tile-locked')).toBe(true);
        expect(locked.querySelector('img')).toBeNull();
        expect(locked.querySelector('.cg-tile-placeholder')).not.toBeNull();
        expect(locked.querySelector('.cg-tile-hint').textContent).toBe('提示三');
        expect(locked.querySelector('.cg-tile-special')).not.toBeNull();

        // 已解锁项（id 2 / id 1）：加载原图
        expect(tiles[1].querySelector('img').getAttribute('src')).toBe('/cg/two.png');
        expect(tiles[2].classList.contains('cg-tile-locked')).toBe(false);
    });

    it('点击未解锁项 → 确认 → 调 unlock → 原地变为已解锁态', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockResolvedValue([
            { id: 3, character_id: 7, url: '/cg/three.png', group_name: '高潮', weight: 100, unlock_hint: '提示三', is_special: true, unlocked: false, created_at: '2026-01-03' },
        ]);
        const unlockSpy = vi.spyOn(api.images, 'unlock').mockResolvedValue({
            id: 3, character_id: 7, url: '/cg/three.png', group_name: '高潮', weight: 100, unlock_hint: '提示三', is_special: true, unlocked: true, created_at: '2026-01-03',
        });

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();
        document.querySelector('.cg-tile-locked .cg-tile-action').click();
        await flush();
        expect(document.querySelector('.confirm-modal')).not.toBeNull();
        document.querySelector('.confirm-ok').click();
        await flush();

        expect(unlockSpy).toHaveBeenCalledTimes(1);
        expect(unlockSpy).toHaveBeenCalledWith(3);
        const tile = document.querySelector('.cg-tile');
        expect(tile.classList.contains('cg-tile-locked')).toBe(false);
        expect(tile.querySelector('img')).not.toBeNull();
        expect(tile.querySelector('img').getAttribute('src')).toBe('/cg/three.png');
    });

    it('点击未解锁项 → 取消 → 不调用 unlock', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockResolvedValue([
            { id: 3, character_id: 7, url: '/cg/three.png', group_name: '高潮', weight: 100, unlock_hint: '提示三', is_special: true, unlocked: false, created_at: '2026-01-03' },
        ]);
        const unlockSpy = vi.spyOn(api.images, 'unlock').mockResolvedValue({});

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();
        document.querySelector('.cg-tile-locked .cg-tile-action').click();
        await flush();
        document.querySelector('.confirm-cancel').click();
        await flush();

        expect(unlockSpy).not.toHaveBeenCalled();
        expect(document.querySelector('.cg-tile').classList.contains('cg-tile-locked')).toBe(true);
    });

    it('点击已解锁项 → 大图展示（本地路径经 cgImageUrl 映射）', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockResolvedValue([
            { id: 1, character_id: 7, url: 'C:\\data\\cg\\one.png', group_name: '开场', weight: 100, unlock_hint: '', is_special: false, unlocked: true, created_at: '2026-01-01' },
        ]);

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();
        document.querySelector('.cg-tile-unlocked .cg-tile-action').click();

        const overlay = document.querySelector('.cg-lightbox');
        expect(overlay).not.toBeNull();
        expect(overlay.querySelector('img').getAttribute('src')).toBe('/cg/one.png');
        expect(overlay.querySelector('.cg-lightbox-close')).not.toBeNull();
    });

    it('点击已解锁项 → URL 形态原样展示（不映射 /cg）', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockResolvedValue([
            { id: 2, character_id: 7, url: 'https://example.com/cg/two.png', group_name: '结尾', weight: 100, unlock_hint: '', is_special: false, unlocked: true, created_at: '2026-01-02' },
        ]);

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();
        document.querySelector('.cg-tile-unlocked .cg-tile-action').click();

        const overlay = document.querySelector('.cg-lightbox');
        expect(overlay.querySelector('img').getAttribute('src')).toBe('https://example.com/cg/two.png');
    });

    it('录入表单合法提交 → create 端点 + 刷新画廊且新条目锁定态在最前', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        const listSpy = vi.spyOn(api.images, 'list')
            .mockResolvedValueOnce([
                { id: 1, character_id: 7, url: '/cg/one.png', group_name: '开场', weight: 100, unlock_hint: '', is_special: false, unlocked: true, created_at: '2026-01-01' },
            ])
            .mockResolvedValueOnce([
                { id: 4, character_id: 7, url: '/cg/new.png', group_name: '新场', weight: 100, unlock_hint: '', is_special: false, unlocked: false, created_at: '2026-01-04' },
                { id: 1, character_id: 7, url: '/cg/one.png', group_name: '开场', weight: 100, unlock_hint: '', is_special: false, unlocked: true, created_at: '2026-01-01' },
            ]);
        const createSpy = vi.spyOn(api.images, 'create').mockResolvedValue({
            id: 4, character_id: 7, url: '/cg/new.png', group_name: '新场', weight: 100, unlock_hint: '', is_special: false, unlocked: false, created_at: '2026-01-04',
        });

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();

        const form = document.querySelector('.cg-create-form');
        form.querySelector('[data-cg-field="url"]').value = '/cg/new.png';
        form.querySelector('[data-cg-field="group_name"]').value = '新场';
        form.querySelector('[data-cg-field="weight"]').value = '100';
        form.querySelector('[data-cg-field="unlock_hint"]').value = '';
        form.querySelector('[data-cg-field="is_special"]').checked = false;
        form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
        await flush();

        expect(createSpy).toHaveBeenCalledTimes(1);
        expect(createSpy).toHaveBeenCalledWith(7, {
            url: '/cg/new.png', group_name: '新场', weight: 100, unlock_hint: '', is_special: false,
        });
        expect(listSpy).toHaveBeenCalledTimes(2);

        const tiles = [...document.querySelectorAll('.cg-tile')];
        expect(tiles[0].dataset.cgId).toBe('4');
        expect(tiles[0].classList.contains('cg-tile-locked')).toBe(true);
    });

    it('录入表单 url 为空 → 校验拦截不出网', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockResolvedValue([]);
        const createSpy = vi.spyOn(api.images, 'create').mockResolvedValue({});

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();

        const form = document.querySelector('.cg-create-form');
        form.querySelector('[data-cg-field="group_name"]').value = '新场';
        form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
        await flush();

        expect(createSpy).not.toHaveBeenCalled();
        expect(document.querySelector('.cg-create-error').textContent).toBe('URL 不能为空');
        expect(document.querySelector('.chat-error-bar')).not.toBeNull();
    });

    it('录入 create 网络失败 → 错误条（不白屏）', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockResolvedValue([]);
        vi.spyOn(api.images, 'create').mockRejectedValue(new Error('录入失败: 网络错误'));

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();

        const form = document.querySelector('.cg-create-form');
        form.querySelector('[data-cg-field="url"]').value = '/cg/new.png';
        form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
        await flush();

        expect(document.querySelector('.chat-error-bar')).not.toBeNull();
        expect(document.querySelector('.chat-error-bar').textContent).toContain('网络错误');
    });

    it('list 网络失败 → 错误条 + 不白屏 + 页签仍可切换', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockRejectedValue(new Error('网络错误'));
        vi.spyOn(api.images, 'cgTimeline').mockResolvedValue([]);

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();

        expect(document.querySelector('#cg-gallery').textContent).toContain('画廊加载失败');
        expect(document.querySelector('.chat-error-bar')).not.toBeNull();
        expect(document.querySelector('.chat-error-bar').textContent).toContain('网络错误');

        // 页签仍可切回时间线
        document.querySelector('[data-cg-tab="timeline"]').click();
        await flush();
        expect(document.querySelector('#cg-timeline').hidden).toBe(false);
        expect(document.querySelector('#cg-gallery').hidden).toBe(true);
    });

    it('unlock 网络失败 → 错误条（不白屏）', async () => {
        const { cg, api, tabs } = await loadGalleryModule();
        setActiveCharacter(tabs, 7);
        vi.spyOn(api.images, 'list').mockResolvedValue([
            { id: 3, character_id: 7, url: '/cg/three.png', group_name: '高潮', weight: 100, unlock_hint: '', is_special: false, unlocked: false, created_at: '2026-01-03' },
        ]);
        vi.spyOn(api.images, 'unlock').mockRejectedValue(new Error('网络错误'));

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();
        document.querySelector('.cg-tile-locked .cg-tile-action').click();
        await flush();
        document.querySelector('.confirm-ok').click();
        await flush();

        expect(document.querySelector('.chat-error-bar')).not.toBeNull();
        expect(document.querySelector('.chat-error-bar').textContent).toContain('网络错误');
    });

    it('null 角色 → 画廊空态（不请求 /characters/null/cg）', async () => {
        const { cg, api } = await loadGalleryModule();
        const listSpy = vi.spyOn(api.images, 'list').mockResolvedValue([]);

        await cg.renderCgTimeline(null);
        document.querySelector('[data-cg-tab="gallery"]').click();
        await flush();

        expect(listSpy).not.toHaveBeenCalled();
        expect(document.querySelector('#cg-gallery').textContent).toContain('打开一个角色对话');
    });

    it('图标仅来自 iconHtml：锁定/查看/特殊标记均为已注册图标且渲染不抛错', async () => {
        const { cg, api } = await loadGalleryModule();
        vi.spyOn(api.images, 'list').mockResolvedValue([
            { id: 3, character_id: 7, url: '/cg/three.png', group_name: '高潮', weight: 100, unlock_hint: 'hint', is_special: true, unlocked: false, created_at: '2026-01-03' },
            { id: 1, character_id: 7, url: '/cg/one.png', group_name: '开场', weight: 100, unlock_hint: '', is_special: false, unlocked: true, created_at: '2026-01-01' },
        ]);

        // renderCgGallery 不抛错（未注册图标会 throw）
        await expect(cg.renderCgGallery(7)).resolves.toBeUndefined();

        const names = [...document.querySelectorAll('#cg-gallery svg[data-icon]')].map((i) => i.dataset.icon);
        expect(names).toContain('sparkles');
        expect(names).toContain('check');
        expect(names).toContain('search');
        expect(names).toContain('pin');
        expect(names).not.toContain('eye');
        expect(names).not.toContain('lock');
    });

    it('__all__ 收口全部公开符号', async () => {
        const { cg } = await loadGalleryModule();
        expect(cg.__all__.sort()).toEqual(['cgImageUrl', 'renderCgGallery', 'renderCgTimeline']);
    });
});
