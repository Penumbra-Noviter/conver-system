/**
 * character-submit 角色提交域深模块测试（ARC-10 C4）
 *
 * 覆盖：
 *   - splitTags：中英文逗号分割 / 空白过滤 / 空串 / null/undefined
 *   - buildCharacterPayload：11 字段集合 + 空值语义（avatar → null、creator 空串、
 *     temperature 数值类型、文本字段字符串、tags 数组）
 *   - 提交态状态机：beginSubmit（禁用 + 「保存中…」+ 清状态栏）、succeedSubmit
 *     （success class + 600ms 延时关窗 + onSuccess）、failSubmit（error class +
 *     原因 + 按钮恢复 restoreLabel）
 *   - 组件级：form（create POST / edit PUT）与 wizard（恒 create）提交后捕获
 *     请求体，断言 11 字段集与空值语义逐字（真实 modal.js + fetch 捕获）
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { splitTags, buildCharacterPayload, beginSubmit, succeedSubmit, failSubmit } from '../js/components/character-submit.js';

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

describe('splitTags — 中英文逗号分割单点', () => {
    it('英文逗号分割', () => {
        expect(splitTags('a,b,c')).toEqual(['a', 'b', 'c']);
    });

    it('中文逗号分割', () => {
        expect(splitTags('冒险，奇幻，可爱')).toEqual(['冒险', '奇幻', '可爱']);
    });

    it('中英文混合 + trim + 空项过滤', () => {
        expect(splitTags(' 冒险 , 奇幻，, 可爱')).toEqual(['冒险', '奇幻', '可爱']);
    });

    it('空串 / 纯分隔符 → []', () => {
        expect(splitTags('')).toEqual([]);
        expect(splitTags('   ,  ')).toEqual([]);
        expect(splitTags(',，')).toEqual([]);
    });

    it('null / undefined → []（不抛错）', () => {
        expect(splitTags(null)).toEqual([]);
        expect(splitTags(undefined)).toEqual([]);
    });
});

describe('buildCharacterPayload — 11 字段集 + 空值语义', () => {
    it('钉 11 字段集合（字段名逐字）', () => {
        const payload = buildCharacterPayload({
            name: 'A', description: 'd', personality: 'p', first_mes: 'f',
            scenario: 's', mes_example: 'm', system_prompt: 'sp',
            temperature: '1.5', avatar: 'http://x/a.png', creator: 'me', tags: ['t1'],
        });
        expect(Object.keys(payload).sort()).toEqual([
            'avatar', 'creator', 'description', 'first_mes', 'mes_example',
            'name', 'personality', 'scenario', 'system_prompt', 'tags', 'temperature',
        ].sort());
    });

    it('temperature 数值类型（字符串输入归一化为数字）', () => {
        expect(buildCharacterPayload({ temperature: '1.5' }).temperature).toBe(1.5);
        expect(buildCharacterPayload({ temperature: 0.7 }).temperature).toBe(0.7);
    });

    it('avatar 空 → null；有值 → 原值', () => {
        expect(buildCharacterPayload({ avatar: '' }).avatar).toBeNull();
        expect(buildCharacterPayload({ avatar: null }).avatar).toBeNull();
        expect(buildCharacterPayload({ avatar: 'http://x/y.png' }).avatar).toBe('http://x/y.png');
    });

    it('缺省字段：creator 空串 / 文本字段空串 / tags [] / temperature 0.7', () => {
        const payload = buildCharacterPayload({ name: 'A' });
        expect(payload.creator).toBe('');
        expect(payload.description).toBe('');
        expect(payload.personality).toBe('');
        expect(payload.first_mes).toBe('');
        expect(payload.tags).toEqual([]);
        expect(payload.temperature).toBe(0.7);
    });

    it('非数组 tags → []（不抛错）', () => {
        expect(buildCharacterPayload({ tags: 'not-array' }).tags).toEqual([]);
        expect(buildCharacterPayload({}).tags).toEqual([]);
    });

    it('空参数对象 → 11 字段全默认（不抛错）', () => {
        const payload = buildCharacterPayload();
        expect(Object.keys(payload)).toHaveLength(11);
    });
});

describe('提交态状态机', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

    it('beginSubmit：按钮禁用 + 「保存中…」+ 状态栏清空 + class 复位', () => {
        const btn = document.createElement('button');
        btn.textContent = '创建角色';
        const statusEl = document.createElement('span');
        statusEl.textContent = '旧状态';
        statusEl.className = 'form-status success';

        beginSubmit(btn, statusEl);

        expect(btn.disabled).toBe(true);
        expect(btn.textContent).toBe('保存中…');
        expect(statusEl.textContent).toBe('');
        expect(statusEl.className).toBe('form-status');
    });

    it('succeedSubmit：success class + 文案 HTML + 600ms 后关窗 + onSuccess（延时逐字）', () => {
        vi.useFakeTimers();
        const statusEl = document.createElement('span');
        const close = vi.fn();
        const onSuccess = vi.fn();

        succeedSubmit(statusEl, '<b>✓ 创建成功</b>', close, onSuccess);

        expect(statusEl.className).toBe('form-status success');
        expect(statusEl.innerHTML).toBe('<b>✓ 创建成功</b>');
        expect(close).not.toHaveBeenCalled();
        vi.advanceTimersByTime(599);
        expect(close).not.toHaveBeenCalled();
        vi.advanceTimersByTime(1);
        expect(close).toHaveBeenCalledTimes(1);
        expect(onSuccess).toHaveBeenCalledTimes(1);
    });

    it('succeedSubmit：onSuccess 缺省 → 关窗不抛错', () => {
        vi.useFakeTimers();
        const close = vi.fn();
        succeedSubmit(document.createElement('span'), 'ok', close);
        vi.advanceTimersByTime(600);
        expect(close).toHaveBeenCalledTimes(1);
    });

    it('failSubmit：error class + x 图标 + 原因转义 + 按钮恢复 enabled + restoreLabel', () => {
        const btn = document.createElement('button');
        btn.disabled = true;
        btn.textContent = '保存中…';
        const statusEl = document.createElement('span');

        failSubmit(btn, statusEl, new Error('网络错误'), '保存修改');

        expect(statusEl.className).toBe('form-status error');
        expect(statusEl.textContent).toContain('网络错误');
        expect(statusEl.querySelector('[data-icon="x"]')).not.toBeNull();
        expect(btn.disabled).toBe(false);
        expect(btn.textContent).toBe('保存修改');
    });

    it('failSubmit：错误消息 HTML 转义（防注入）', () => {
        const btn = document.createElement('button');
        const statusEl = document.createElement('span');
        failSubmit(btn, statusEl, new Error('<script>alert(1)</script>'), '创建角色');
        expect(statusEl.textContent).toContain('<script>alert(1)</script>');
        expect(statusEl.innerHTML).not.toContain('<script>alert(1)</script>');
    });
});

describe('组件级：form 提交请求体（真实 modal.js + fetch 捕获）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    async function loadForm() {
        vi.resetModules();
        document.body.innerHTML = '';
        const form = await import('../js/components/character-form.js');
        return { form };
    }

    it('create：POST /characters + 11 字段请求体逐字（全字段填齐）', async () => {
        const { form } = await loadForm();
        const calls = [];
        globalThis.fetch = vi.fn(async (url, opts) => {
            calls.push({ url: String(url), method: opts.method, body: JSON.parse(opts.body) });
            return mockJson({ id: 1, name: '角色A' });
        });

        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-description').value = '描述';
        overlay.querySelector('#cf-personality').value = '人格';
        overlay.querySelector('#cf-first-mes').value = '开场';
        overlay.querySelector('#cf-scenario').value = '场景';
        overlay.querySelector('#cf-mes-example').value = '范例';
        overlay.querySelector('#cf-system-prompt').value = '提示';
        overlay.querySelector('#cf-temperature').value = '1.25';
        overlay.querySelector('#cf-avatar').value = 'http://x/a.png';
        overlay.querySelector('#cf-creator').value = '作者';
        overlay.querySelector('#cf-tags').value = '甲，乙, 丙';
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => expect(calls).toHaveLength(1));
        expect(calls[0].method).toBe('POST');
        expect(calls[0].url).toContain('/api/characters');
        expect(calls[0].body).toEqual({
            name: '角色A', description: '描述', personality: '人格', first_mes: '开场',
            scenario: '场景', mes_example: '范例', system_prompt: '提示',
            temperature: 1.25, avatar: 'http://x/a.png', creator: '作者',
            tags: ['甲', '乙', '丙'],
        });
    });

    it('edit：PUT /characters/{id} + 空头像 → null / 空 creator → 空串', async () => {
        const { form } = await loadForm();
        const calls = [];
        globalThis.fetch = vi.fn(async (url, opts) => {
            calls.push({ url: String(url), method: opts.method, body: JSON.parse(opts.body) });
            return mockJson({ id: 7, name: '老角色' });
        });

        form.showCharacterForm('edit', { id: 7, name: '老角色' });
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '老角色';
        overlay.querySelector('#cf-personality').value = 'p';
        overlay.querySelector('#cf-first-mes').value = 'hi';
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => expect(calls).toHaveLength(1));
        expect(calls[0].method).toBe('PUT');
        expect(calls[0].url).toContain('/api/characters/7');
        expect(calls[0].body.avatar).toBeNull();
        expect(calls[0].body.creator).toBe('');
        expect(calls[0].body.temperature).toBe(0.7);
        expect(Object.keys(calls[0].body)).toHaveLength(11);
    });
});

describe('组件级：wizard 保存请求体（恒 create，creator 恒空）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('POST /characters + 11 字段请求体逐字', async () => {
        vi.resetModules();
        document.body.innerHTML = '';
        const wizard = await import('../js/components/character-wizard.js');
        const calls = [];
        globalThis.fetch = vi.fn(async (url, opts) => {
            calls.push({ url: String(url), method: opts.method, body: JSON.parse(opts.body) });
            return mockJson({ id: 1, name: '角色A' });
        });

        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        // manual → step3：填基本信息
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        const set = (id, value) => {
            const el = overlay.querySelector(`#${id}`);
            el.value = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
        };
        set('wiz-name', '角色A');
        set('wiz-desc', '描述');
        set('wiz-avatar', 'http://x/a.png');
        set('wiz-tags', '冒险，奇幻');
        overlay.querySelector('#wizard-next').click();
        // step4：人格设定
        set('wiz-personality', '人格');
        set('wiz-scenario', '场景');
        set('wiz-system-prompt', '提示');
        overlay.querySelector('#wizard-next').click();
        // step5：对话风格
        set('wiz-first-mes', '开场');
        set('wiz-mes-example', '范例');
        overlay.querySelector('#wizard-next').click();
        // step6：保存
        overlay.querySelector('#wizard-next').click();

        await vi.waitFor(() => expect(calls).toHaveLength(1));
        expect(calls[0].method).toBe('POST');
        expect(calls[0].url).toContain('/api/characters');
        expect(calls[0].body).toEqual({
            name: '角色A', description: '描述', personality: '人格', first_mes: '开场',
            scenario: '场景', mes_example: '范例', system_prompt: '提示',
            temperature: 0.7, avatar: 'http://x/a.png', creator: '',
            tags: ['冒险', '奇幻'],
        });
    });
});
