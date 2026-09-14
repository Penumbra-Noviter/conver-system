/**
 * PD-4 Prompt Debug 只读预览面板 契约锁（Vitest）
 *
 * 逐条覆盖工单 4 条验收标准：
 *   1. segments 渲染：来源 → 色标类名映射单一来源（SOURCE_CLASS 单一映射表，
 *      不散落 if/else；segmentHtml 色标类名直接取自该表）
 *   2. role 徽标与 content 转义（content 内 HTML 不注入，用 escapeHtml）
 *   3. 空 segments → 空态提示
 *   4. 来源枚举非法值 → 落入默认样式不抛错
 *
 * 挂载模式：纯函数直 import；showPromptDebug 集成用 vi.resetModules() + jsdom
 *   （真实 modal.js / api.js / fetch-seam），fetch mock 捕获请求 URL 与响应。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
    SOURCE_CLASS,
    SOURCE_DEFAULT_CLASS,
    sourceClass,
    segmentHtml,
    segmentsHtml,
    promptDebugBodyHtml,
} from '../js/components/prompt-debug.js';

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

describe('验收标准 1 — 来源 → 色标类名单一映射表', () => {
    it('SOURCE_CLASS 是单一映射表：6 个来源各一个独立色标类', () => {
        expect(Object.keys(SOURCE_CLASS).sort())
            .toEqual(['character', 'history', 'memory', 'mod', 'user', 'world']);
        const values = Object.values(SOURCE_CLASS);
        expect(new Set(values).size).toBe(6); // 各一色，无复用
        expect(values.every((v) => typeof v === 'string' && v.startsWith('pd-source-'))).toBe(true);
    });

    it('segmentHtml 色标类名直接取自 SOURCE_CLASS 表（非散落 if/else）', () => {
        for (const [source, cls] of Object.entries(SOURCE_CLASS)) {
            const html = segmentHtml({ role: 'system', content: 'x', source });
            expect(html).toContain(`class="pd-source-badge ${cls}"`);
        }
    });
});

describe('验收标准 2 — role 徽标与 content 转义', () => {
    it('content 内 HTML 被转义（不注入）', () => {
        const html = segmentHtml({
            role: 'user',
            content: '<img src=x onerror=alert(1)>',
            source: 'history',
        });
        expect(html).not.toContain('<img');
        expect(html).toContain('&lt;img');
        expect(html).toContain('&gt;');
    });

    it('content 内双引号也转义（escapeHtml 契约 — 属性上下文安全）', () => {
        const html = segmentHtml({ role: 'user', content: 'a"b', source: 'history' });
        expect(html).toContain('a&quot;b');
    });

    it('role 徽标渲染（转义后的 role 文本）', () => {
        const html = segmentHtml({ role: 'assistant', content: 'hi', source: 'character' });
        expect(html).toContain('pd-role-badge');
        expect(html).toContain('>assistant<');
    });

    it('role 畸形值也被转义（后端枚举外防御，不注入）', () => {
        const html = segmentHtml({ role: '<b>bad</b>', content: 'y', source: 'user' });
        expect(html).not.toContain('<b>');
        expect(html).toContain('&lt;b&gt;bad&lt;/b&gt;');
    });
});

describe('验收标准 3 — 空 segments 空态提示', () => {
    it('空数组 → 空态提示', () => {
        const html = segmentsHtml([]);
        expect(html).toContain('pd-empty');
        expect(html).toContain('无分段数据');
    });

    it('非数组 / null / undefined → 空态（Falsify）', () => {
        expect(segmentsHtml(undefined)).toContain('pd-empty');
        expect(segmentsHtml(null)).toContain('pd-empty');
        expect(segmentsHtml('not-array')).toContain('pd-empty');
        expect(segmentsHtml(42)).toContain('pd-empty');
    });

    it('非空数组 → 渲染对应数量分段', () => {
        const html = segmentsHtml([
            { role: 'system', content: 'a', source: 'character' },
            { role: 'user', content: 'b', source: 'user' },
        ]);
        expect(html.match(/pd-segment"/g)).toHaveLength(2);
        expect(html).not.toContain('pd-empty');
    });
});

describe('验收标准 4 — 来源非法值回落默认样式不抛错', () => {
    it('sourceClass 非法来源 → 默认样式类，不抛错', () => {
        expect(sourceClass('bogus')).toBe(SOURCE_DEFAULT_CLASS);
        expect(sourceClass(undefined)).toBe(SOURCE_DEFAULT_CLASS);
        expect(sourceClass(null)).toBe(SOURCE_DEFAULT_CLASS);
        expect(sourceClass(123)).toBe(SOURCE_DEFAULT_CLASS);
        expect(sourceClass({})).toBe(SOURCE_DEFAULT_CLASS);
        // 原型链污染键不得命中映射表（防 source='constructor'/'toString' 等）
        expect(sourceClass('__proto__')).toBe(SOURCE_DEFAULT_CLASS);
        expect(sourceClass('constructor')).toBe(SOURCE_DEFAULT_CLASS);
        expect(sourceClass('toString')).toBe(SOURCE_DEFAULT_CLASS);
    });

    it('segmentHtml 非法来源 → 渲染默认色标类 + 默认标签，不抛错', () => {
        const html = segmentHtml({ role: 'system', content: 'x', source: 'evil' });
        expect(html).toContain(`class="pd-source-badge ${SOURCE_DEFAULT_CLASS}"`);
        expect(html).toContain('未知');
    });
});

describe('Falsify — 纯函数空/畸形入参', () => {
    it('segmentHtml null / undefined / 空对象 → 不抛错，渲染空段', () => {
        for (const bad of [null, undefined, {}]) {
            expect(() => segmentHtml(bad)).not.toThrow();
            expect(segmentHtml(bad)).toContain('pd-segment');
        }
    });

    it('segmentsHtml 含畸形项（null）→ 不抛错', () => {
        const html = segmentsHtml([null, { role: 'user', content: 'x', source: 'user' }]);
        expect(html.match(/pd-segment"/g)).toHaveLength(2);
    });

    it('promptDebugBodyHtml 空 data / null → meta 空值渲染 + 空态', () => {
        for (const bad of [null, undefined, {}]) {
            const html = promptDebugBodyHtml(bad);
            expect(html).toContain('pd-meta');
            expect(html).toContain('pd-empty');
        }
    });

    it('promptDebugBodyHtml meta 字段含 HTML → 转义', () => {
        const html = promptDebugBodyHtml({
            character_name: '<b>角色</b>',
            model: 'openai/gpt-4',
            prompt_mode: 'simple',
            segments: [],
        });
        expect(html).toContain('&lt;b&gt;角色&lt;/b&gt;');
        expect(html).toContain('openai/gpt-4');
        expect(html).toContain('simple');
    });
});

describe('showPromptDebug 集成（openModal + fetch）', () => {
    beforeEach(() => { vi.restoreAllMocks(); document.body.innerHTML = ''; });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    async function loadModule() {
        vi.resetModules();
        document.body.innerHTML = '';
        return await import('../js/components/prompt-debug.js');
    }

    it('打开面板：GET /prompt-debug + 渲染 meta 与分段', async () => {
        const fetchSpy = vi.fn(async (url) => {
            expect(String(url)).toContain('/api/conversations/7/prompt-debug');
            return mockJson({
                conversation_id: 7,
                character_name: '角色A',
                model: 'openai/gpt-4',
                prompt_mode: 'simple',
                segments: [
                    { role: 'system', content: 'sys', source: 'character' },
                    { role: 'user', content: 'hi', source: 'user' },
                ],
            });
        });
        globalThis.fetch = fetchSpy;

        const { showPromptDebug } = await loadModule();
        await showPromptDebug(7);

        expect(fetchSpy).toHaveBeenCalledTimes(1);
        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        expect(overlay.textContent).toContain('角色A');
        expect(overlay.textContent).toContain('openai/gpt-4');
        expect(overlay.textContent).toContain('simple');
        expect(overlay.querySelectorAll('.pd-segment').length).toBe(2);
        expect(overlay.querySelector('.pd-source-character')).not.toBeNull();
        expect(overlay.querySelector('.pd-source-user')).not.toBeNull();
    });

    it('重复打开去重：已有面板时不再发请求', async () => {
        const fetchSpy = vi.fn(async () => mockJson({
            conversation_id: 7,
            character_name: 'A',
            model: 'm',
            prompt_mode: 'simple',
            segments: [],
        }));
        globalThis.fetch = fetchSpy;

        const { showPromptDebug } = await loadModule();
        await showPromptDebug(7);
        await showPromptDebug(7);

        expect(fetchSpy).toHaveBeenCalledTimes(1);
    });

    it('加载失败 → 错误态面板（不抛错）', async () => {
        globalThis.fetch = vi.fn(async () => {
            throw new Error('网络错误');
        });

        const { showPromptDebug } = await loadModule();
        await expect(showPromptDebug(7)).resolves.toBeUndefined();
        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        expect(overlay.textContent).toContain('加载失败');
    });
});
