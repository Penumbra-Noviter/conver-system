/**
 * PD-2 备用开场白编辑 + 开场白选择 契约锁（Vitest）
 *
 * 逐条覆盖工单 4 条验收标准：
 *   1. 备用开场白增删上限 10、空项去重（normalizeAlternateGreetings /
 *      addAlternateGreeting 纯函数 + form 组件级增删）
 *   2. 保存 payload 含 alternate_greetings（list 逐字段一致；非数组 → []）
 *   3. 新建对话「开场白」下拉选项 = first_mes（默认）+ alternate_greetings
 *      各项 + 「无开场白」；选项 → greeting 映射正确（默认=不传 / 备选=传该
 *      文本 / 无=传空）——buildGreetingOptions / resolveGreeting 纯函数 +
 *      startChatWithCharacter 组件级集成
 *   4. 编辑角色重开面板字段还原（含 alternate_greetings）——form edit 组件级
 *
 * 挂载模式：纯函数直 import；组件级用 vi.resetModules() + jsdom（真实
 *   modal.js / form / wizard / list-views），fetch mock 捕获请求体。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
    buildCharacterPayload,
    normalizeAlternateGreetings,
    addAlternateGreeting,
    alternateGreetingRowsHtml,
    MAX_ALTERNATE_GREETINGS,
    normalizePresetDialogues,
    addPresetDialogue,
    presetDialogueRowsHtml,
    MAX_PRESET_DIALOGUES,
} from '../js/components/character-submit.js';
import { buildGreetingOptions, resolveGreeting, buildPresetDialogueOptions, resolvePresetDialogue } from '../js/list-views.js';

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

describe('验收标准 1 — 备用开场白增删上限 10、空项去重', () => {
    it('MAX_ALTERNATE_GREETINGS 常量 = 10', () => {
        expect(MAX_ALTERNATE_GREETINGS).toBe(10);
    });

    it('addAlternateGreeting 正常追加（trim 后入列）', () => {
        expect(addAlternateGreeting([], ' 你好 ')).toEqual(['你好']);
        expect(addAlternateGreeting(['a'], ' b ')).toEqual(['a', 'b']);
    });

    it('addAlternateGreeting 空项不追加', () => {
        expect(addAlternateGreeting(['a'], '')).toEqual(['a']);
        expect(addAlternateGreeting(['a'], '   ')).toEqual(['a']);
        expect(addAlternateGreeting(['a'], null)).toEqual(['a']);
        expect(addAlternateGreeting(['a'], undefined)).toEqual(['a']);
    });

    it('addAlternateGreeting 重复项不追加（含 trim 后重复）', () => {
        expect(addAlternateGreeting(['a', 'b'], 'a')).toEqual(['a', 'b']);
        expect(addAlternateGreeting(['a'], ' a ')).toEqual(['a']);
    });

    it('addAlternateGreeting 上限 10：满 10 后再加不生效', () => {
        const full = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
        expect(addAlternateGreeting(full, '10')).toEqual(full);
        expect(addAlternateGreeting(full, '10')).toHaveLength(10);
    });

    it('addAlternateGreeting 非数组输入视作 []', () => {
        expect(addAlternateGreeting(null, 'a')).toEqual(['a']);
        expect(addAlternateGreeting(undefined, 'a')).toEqual(['a']);
        expect(addAlternateGreeting('not-array', 'a')).toEqual(['a']);
    });

    it('normalizeAlternateGreetings：trim + 去空 + 去重（保持首次顺序）+ 上限截断', () => {
        expect(normalizeAlternateGreetings([' a ', '', 'b', 'a', ' c '])).toEqual(['a', 'b', 'c']);
        expect(normalizeAlternateGreetings(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10']))
            .toHaveLength(10);
    });

    it('normalizeAlternateGreetings 非数组 / 空 → []', () => {
        expect(normalizeAlternateGreetings(null)).toEqual([]);
        expect(normalizeAlternateGreetings(undefined)).toEqual([]);
        expect(normalizeAlternateGreetings('not-array')).toEqual([]);
        expect(normalizeAlternateGreetings([])).toEqual([]);
    });

    it('normalizeAlternateGreetings 非字符串项被过滤', () => {
        expect(normalizeAlternateGreetings(['a', 1, null, 'b', {}])).toEqual(['a', 'b']);
    });

    it('alternateGreetingRowsHtml：非数组/空 → 空串；列表 → 行 HTML（含转义）', () => {
        expect(alternateGreetingRowsHtml(null)).toBe('');
        expect(alternateGreetingRowsHtml(undefined)).toBe('');
        expect(alternateGreetingRowsHtml('bad')).toBe('');
        expect(alternateGreetingRowsHtml([])).toBe('');
        const html = alternateGreetingRowsHtml(['备选一', '备选二']);
        expect(html.match(/alt-greeting-row/g)).toHaveLength(2);
        expect(html).toContain('value="备选一"');
        expect(html).toContain('data-icon="x"');
        expect(alternateGreetingRowsHtml(['<img>'])).toContain('&lt;img&gt;');
    });
});

describe('验收标准 2 — 保存 payload 含 alternate_greetings', () => {
    it('payload 含 alternate_greetings（list，逐字段一致）', () => {
        const payload = buildCharacterPayload({ name: 'A', alternate_greetings: ['备一', '备二'] });
        expect(payload.alternate_greetings).toEqual(['备一', '备二']);
    });

    it('非数组 → []（对齐 tags 归一化）', () => {
        expect(buildCharacterPayload({ alternate_greetings: 'not-array' }).alternate_greetings).toEqual([]);
        expect(buildCharacterPayload({ alternate_greetings: null }).alternate_greetings).toEqual([]);
        expect(buildCharacterPayload({}).alternate_greetings).toEqual([]);
    });
});

describe('验收标准 3 — 开场白下拉选项 + greeting 映射', () => {
    it('选项序列 = first_mes（默认）+ 各备用 + 无开场白', () => {
        const opts = buildGreetingOptions({
            first_mes: '你好呀',
            alternate_greetings: ['备选一', '备选二'],
        });
        expect(opts.map((o) => o.value)).toEqual(['__default__', '0', '1', '__none__']);
        expect(opts[0].label).toBe('默认：你好呀');
        expect(opts[1].label).toBe('备选一');
        expect(opts[2].label).toBe('备选二');
        expect(opts[3].label).toBe('无开场白');
    });

    it('无备用开场白 → 仅默认 + 无开场白', () => {
        const opts = buildGreetingOptions({ first_mes: '你好呀', alternate_greetings: [] });
        expect(opts.map((o) => o.value)).toEqual(['__default__', '__none__']);
    });

    it('first_mes 为空 → 默认项 label 回落「默认」', () => {
        const opts = buildGreetingOptions({ first_mes: '', alternate_greetings: [] });
        expect(opts[0].label).toBe('默认');
    });

    it('备用开场白为空项 → 跳过（索引仍与源数组对齐）', () => {
        const opts = buildGreetingOptions({ first_mes: 'x', alternate_greetings: ['', '备选二'] });
        expect(opts.map((o) => o.value)).toEqual(['__default__', '1', '__none__']);
        expect(opts[1].label).toBe('备选二');
    });

    it('resolveGreeting：默认 → {}（不传 greeting，走 first_mes 现状）', () => {
        expect(resolveGreeting('__default__', { first_mes: '你好呀' })).toEqual({});
    });

    it('resolveGreeting：备选索引 → { greeting: 该文本 }', () => {
        const char = { alternate_greetings: ['备选一', '备选二'] };
        expect(resolveGreeting('0', char)).toEqual({ greeting: '备选一' });
        expect(resolveGreeting('1', char)).toEqual({ greeting: '备选二' });
    });

    it('resolveGreeting：无开场白 → { greeting: "" }', () => {
        expect(resolveGreeting('__none__', {})).toEqual({ greeting: '' });
    });

    it('resolveGreeting Falsify：非法 value（越界索引/未知标记/非数字）→ {} 不抛错', () => {
        const char = { alternate_greetings: ['a'] };
        expect(resolveGreeting('99', char)).toEqual({});
        expect(resolveGreeting('bogus', char)).toEqual({});
        expect(resolveGreeting('', char)).toEqual({});
    });
});

describe('验收标准 4 — 编辑角色重开面板字段还原（form）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    async function loadForm() {
        vi.resetModules();
        document.body.innerHTML = '';
        return await import('../js/components/character-form.js');
    }

    it('edit 模式备用开场白列表回填', async () => {
        const form = await loadForm();
        form.showCharacterForm('edit', {
            id: 1, name: 'x', alternate_greetings: ['备选一', '备选二'],
        });
        const rows = document.querySelectorAll('#cf-alt-greetings-list .alt-greeting-row');
        expect(rows).toHaveLength(2);
        expect(rows[0].querySelector('.alt-greeting-input').value).toBe('备选一');
        expect(rows[1].querySelector('.alt-greeting-input').value).toBe('备选二');
    });

    it('edit 模式非数组/空 alternate_greetings → 空列表不抛错', async () => {
        const form = await loadForm();
        form.showCharacterForm('edit', { id: 1, name: 'x', alternate_greetings: 'bad' });
        expect(document.querySelectorAll('#cf-alt-greetings-list .alt-greeting-row')).toHaveLength(0);
    });

    it('添加/删除：上限 + 空项去重 + 删除（组件级）', async () => {
        const form = await loadForm();
        form.showCharacterForm('create');
        const list = document.querySelector('#cf-alt-greetings-list');
        const input = document.querySelector('#cf-alt-greetings-input');
        const addBtn = document.querySelector('#cf-alt-greetings-add');

        input.value = '备选一';
        addBtn.click();
        expect(list.querySelectorAll('.alt-greeting-row')).toHaveLength(1);

        input.value = '备选一';
        addBtn.click(); // 重复
        expect(list.querySelectorAll('.alt-greeting-row')).toHaveLength(1);

        input.value = '   ';
        addBtn.click(); // 空项
        expect(list.querySelectorAll('.alt-greeting-row')).toHaveLength(1);

        input.value = '备选二';
        addBtn.click();
        expect(list.querySelectorAll('.alt-greeting-row')).toHaveLength(2);

        list.querySelector('.alt-greeting-remove').click(); // 删除第一行
        expect(list.querySelectorAll('.alt-greeting-row')).toHaveLength(1);
        expect(list.querySelector('.alt-greeting-input').value).toBe('备选二');
    });

    it('保存 payload 收集 alternate_greetings（form create）', async () => {
        const form = await loadForm();
        let captured = null;
        globalThis.fetch = vi.fn(async (url, opts) => {
            captured = JSON.parse(opts.body);
            return mockJson({ id: 1, name: 'x' });
        });
        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-personality').value = 'p';
        overlay.querySelector('#cf-first-mes').value = 'hi';
        const input = overlay.querySelector('#cf-alt-greetings-input');
        input.value = '备选一';
        overlay.querySelector('#cf-alt-greetings-add').click();
        input.value = '备选二';
        overlay.querySelector('#cf-alt-greetings-add').click();
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => expect(captured).not.toBeNull());
        expect(captured.alternate_greetings).toEqual(['备选一', '备选二']);
    });
});

describe('验收标准 4 — 向导备用开场白编辑 + 保存', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('wizard step5 备用开场白添加 → 保存 payload 含 alternate_greetings', async () => {
        vi.resetModules();
        document.body.innerHTML = '';
        const wizard = await import('../js/components/character-wizard.js');
        let captured = null;
        globalThis.fetch = vi.fn(async (url, opts) => {
            captured = JSON.parse(opts.body);
            return mockJson({ id: 1, name: 'x' });
        });
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        const set = (id, value) => {
            const el = overlay.querySelector('#' + id);
            el.value = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
        };
        set('wiz-name', '角色A');
        overlay.querySelector('#wizard-next').click(); // → step4
        overlay.querySelector('#wizard-next').click(); // → step5
        const input = overlay.querySelector('#wiz-alt-greetings-input');
        input.value = '备选一';
        overlay.querySelector('#wiz-alt-greetings-add').click();
        overlay.querySelector('#wizard-next').click(); // → step6
        overlay.querySelector('#wizard-next').click(); // 保存

        await vi.waitFor(() => expect(captured).not.toBeNull());
        expect(captured.alternate_greetings).toEqual(['备选一']);
    });
});

describe('预设对话归一化 + payload（PD-4 前端镜像）', () => {
    it('MAX_PRESET_DIALOGUES 常量 = 10', () => {
        expect(MAX_PRESET_DIALOGUES).toBe(10);
    });

    it('normalizePresetDialogues：trim + 过滤空 name/content + 按 name 去重 + 截断 10', () => {
        expect(normalizePresetDialogues([
            { name: ' 寒暄 ', content: ' 你好 ' },
            { name: '寒暄', content: '重复的第二个' },
            { name: '', content: '有空名' },
            { name: '有空内容', content: '' },
            { name: '有效', content: '正文' },
        ])).toEqual([{ name: '寒暄', content: '你好' }, { name: '有效', content: '正文' }]);
    });

    it('normalizePresetDialogues 非数组/非对象项 → 过滤（对齐后端）', () => {
        expect(normalizePresetDialogues(null)).toEqual([]);
        expect(normalizePresetDialogues('bad')).toEqual([]);
        expect(normalizePresetDialogues([{ name: 'x', content: 'y' }, 'str', 1, null])).toEqual([{ name: 'x', content: 'y' }]);
    });

    it('normalizePresetDialogues 截断到 10（去重前）', () => {
        const list = Array.from({ length: 12 }, (_, i) => ({ name: `示范${i}`, content: `内容${i}` }));
        expect(normalizePresetDialogues(list)).toHaveLength(10);
        expect(normalizePresetDialogues(list)[9]).toEqual({ name: '示范9', content: '内容9' });
    });

    it('addPresetDialogue：正常追加 / 空 name或content 不追加 / name 重复不追加 / 上限', () => {
        expect(addPresetDialogue([], '寒暄', '你好')).toEqual([{ name: '寒暄', content: '你好' }]);
        expect(addPresetDialogue([{ name: 'a', content: 'b' }], '', 'c')).toEqual([{ name: 'a', content: 'b' }]);
        expect(addPresetDialogue([{ name: 'a', content: 'b' }], 'a', 'c')).toEqual([{ name: 'a', content: 'b' }]);
        const full = Array.from({ length: 10 }, (_, i) => ({ name: `n${i}`, content: `c${i}` }));
        expect(addPresetDialogue(full, 'x', 'y')).toHaveLength(10);
    });

    it('presetDialogueRowsHtml：非数组→空串；行 HTML 含 name+content 双字段 + 转义', () => {
        expect(presetDialogueRowsHtml(null)).toBe('');
        expect(presetDialogueRowsHtml('bad')).toBe('');
        expect(presetDialogueRowsHtml([])).toBe('');
        const html = presetDialogueRowsHtml([{ name: '寒暄', content: '你好<世界>' }]);
        expect(html.match(/preset-dialogue-row/g)).toHaveLength(1);
        expect(html).toContain('value="寒暄"');
        expect(html).toContain('你好&lt;世界&gt;');
        expect(html).toContain('data-icon="x"');
    });

    it('buildCharacterPayload 含 preset_dialogues（数组透传 / 非数组 → []）', () => {
        expect(buildCharacterPayload({ preset_dialogues: [{ name: 'a', content: 'b' }] }).preset_dialogues)
            .toEqual([{ name: 'a', content: 'b' }]);
        expect(buildCharacterPayload({ preset_dialogues: 'bad' }).preset_dialogues).toEqual([]);
        expect(buildCharacterPayload({}).preset_dialogues).toEqual([]);
    });
});

describe('预设对话下拉选项 + preset_dialogue 映射', () => {
    it('buildPresetDialogueOptions：选项序列 = 无预设对话 + 各 name（空 name/content 跳过）', () => {
        const opts = buildPresetDialogueOptions({
            preset_dialogues: [
                { name: '寒暄', content: '你好。' },
                { name: '', content: '空标题' },
                { name: '空内容', content: '' },
                { name: '告别', content: '再见。' },
            ],
        });
        expect(opts.map((o) => o.value)).toEqual(['__none__', '0', '3']);
        expect(opts[0].label).toBe('无预设对话');
        expect(opts[1].label).toBe('寒暄');
        expect(opts[2].label).toBe('告别');
    });

    it('buildPresetDialogueOptions：无预设对话 → 仅「无预设对话」', () => {
        const opts = buildPresetDialogueOptions({ preset_dialogues: [] });
        expect(opts.map((o) => o.value)).toEqual(['__none__']);
    });

    it('resolvePresetDialogue：无预设对话 → {}（不传 preset_dialogue）', () => {
        expect(resolvePresetDialogue('__none__', {})).toEqual({});
    });

    it('resolvePresetDialogue：选中索引 → { preset_dialogue: content }', () => {
        const char = { preset_dialogues: [{ name: '寒暄', content: '你好。' }, { name: '告别', content: '再见。' }] };
        expect(resolvePresetDialogue('0', char)).toEqual({ preset_dialogue: '你好。' });
        expect(resolvePresetDialogue('1', char)).toEqual({ preset_dialogue: '再见。' });
    });

    it('resolvePresetDialogue Falsify：非法 value（越界/未知标记/非数字/空）→ {} 不抛错', () => {
        const char = { preset_dialogues: [{ name: 'a', content: 'b' }] };
        expect(resolvePresetDialogue('99', char)).toEqual({});
        expect(resolvePresetDialogue('bogus', char)).toEqual({});
        expect(resolvePresetDialogue('', char)).toEqual({});
    });
});

describe('预设对话编辑（form）—— 增删归一化 + 保存', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    async function loadForm() {
        vi.resetModules();
        document.body.innerHTML = '';
        return await import('../js/components/character-form.js');
    }

    it('edit 模式预设对话列表回填（name+content 双字段）', async () => {
        const form = await loadForm();
        form.showCharacterForm('edit', {
            id: 1, name: 'x',
            preset_dialogues: [{ name: '寒暄', content: '你好。' }, { name: '告别', content: '再见。' }],
        });
        const rows = document.querySelectorAll('#cf-preset-dialogues-list .preset-dialogue-row');
        expect(rows).toHaveLength(2);
        expect(rows[0].querySelector('.preset-dialogue-name').value).toBe('寒暄');
        expect(rows[0].querySelector('.preset-dialogue-content').value).toBe('你好。');
        expect(rows[1].querySelector('.preset-dialogue-name').value).toBe('告别');
        expect(rows[1].querySelector('.preset-dialogue-content').value).toBe('再见。');
    });

    it('edit 模式非数组/空 preset_dialogues → 空列表不抛错', async () => {
        const form = await loadForm();
        form.showCharacterForm('edit', { id: 1, name: 'x', preset_dialogues: 'bad' });
        expect(document.querySelectorAll('#cf-preset-dialogues-list .preset-dialogue-row')).toHaveLength(0);
    });

    it('添加/删除：空 name或content 不添加 / name 重复不添加 / 删除（组件级）', async () => {
        const form = await loadForm();
        form.showCharacterForm('create');
        const list = document.querySelector('#cf-preset-dialogues-list');
        const nameInput = document.querySelector('#cf-preset-dialogues-name');
        const contentInput = document.querySelector('#cf-preset-dialogues-content');
        const addBtn = document.querySelector('#cf-preset-dialogues-add');

        nameInput.value = '寒暄';
        contentInput.value = '你好。';
        addBtn.click();
        expect(list.querySelectorAll('.preset-dialogue-row')).toHaveLength(1);

        nameInput.value = '';
        contentInput.value = '有内容';
        addBtn.click(); // 空 name
        expect(list.querySelectorAll('.preset-dialogue-row')).toHaveLength(1);

        nameInput.value = '有标题';
        contentInput.value = '';
        addBtn.click(); // 空 content
        expect(list.querySelectorAll('.preset-dialogue-row')).toHaveLength(1);

        nameInput.value = '寒暄';
        contentInput.value = '重复的第二个';
        addBtn.click(); // name 重复
        expect(list.querySelectorAll('.preset-dialogue-row')).toHaveLength(1);

        nameInput.value = '告别';
        contentInput.value = '再见。';
        addBtn.click();
        expect(list.querySelectorAll('.preset-dialogue-row')).toHaveLength(2);

        list.querySelector('.preset-dialogue-remove').click(); // 删除第一行
        expect(list.querySelectorAll('.preset-dialogue-row')).toHaveLength(1);
        expect(list.querySelector('.preset-dialogue-name').value).toBe('告别');
    });

    it('保存 payload 收集 preset_dialogues（form create，含归一化）', async () => {
        const form = await loadForm();
        let captured = null;
        globalThis.fetch = vi.fn(async (url, opts) => {
            captured = JSON.parse(opts.body);
            return mockJson({ id: 1, name: 'x' });
        });
        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-personality').value = 'p';
        overlay.querySelector('#cf-first-mes').value = 'hi';
        const nameInput = overlay.querySelector('#cf-preset-dialogues-name');
        const contentInput = overlay.querySelector('#cf-preset-dialogues-content');
        const addBtn = overlay.querySelector('#cf-preset-dialogues-add');
        nameInput.value = '寒暄';
        contentInput.value = '你好。';
        addBtn.click();
        nameInput.value = '告别';
        contentInput.value = '再见。';
        addBtn.click();
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => expect(captured).not.toBeNull());
        expect(captured.preset_dialogues).toEqual([
            { name: '寒暄', content: '你好。' },
            { name: '告别', content: '再见。' },
        ]);
    });
});

describe('验收标准 3 — 新建对话开场白选择集成（list-views）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    const LIST_VIEWS_DOM_HTML = `
        <div id="conversation-list"></div>
        <button id="btn-new-chat"></button>
        <div id="character-grid"></div>
        <button id="btn-create-character"></button>
        <button id="btn-import-character"></button>
        <input type="file" id="character-import-input" style="display:none">
        <div id="chat-messages"></div>
        <textarea id="chat-input"></textarea>
        <button id="btn-send"></button>
        <input type="checkbox" id="toggle-stream" checked>
        <div id="chat-header"><span class="chat-title" id="chat-title-text"></span></div>
    `;

    const PROVIDERS = [{ key: 'claude', name: 'Claude', models: ['claude-sonnet-5'] }];

    async function loadListViews({ characters = [], conversations = [], createdConv = null } = {}) {
        vi.resetModules();
        sessionStorage.clear();
        document.body.innerHTML = LIST_VIEWS_DOM_HTML;
        const route = async (url, options = {}) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            const method = options.method || 'GET';
            if (path === '/api/characters' && method === 'GET') return mockJson(characters);
            if (path === '/api/conversations' && method === 'GET') return mockJson(conversations);
            if (path === '/api/conversations' && method === 'POST') return mockJson(createdConv);
            const convMatch = path.match(/^\/api\/conversations\/(\d+)\/messages$/);
            if (convMatch && method === 'GET') return mockJson([]);
            if (path === '/api/models' && method === 'GET') return mockJson({ providers: PROVIDERS });
            throw new Error('未 mock 的请求: ' + path);
        };
        const fetchSpy = vi.fn(route);
        globalThis.fetch = fetchSpy;

        const listViews = await import('../js/list-views.js');
        const chat = await import('../js/chat.js');
        const state = (await import('../js/state.js')).state;
        const tabs = await import('../js/tabs.js');
        const cascade = await import('../js/cascade.js');
        const api = await import('../js/api.js');
        const utils = await import('../js/utils.js');
        const activation = await import('../js/conversation-activation.js');

        activation.setActivationHooks({
            renderConversations: listViews.renderConversations,
            switchView: (viewName) => { state.currentView = viewName; },
            showError: utils.showError,
        });
        chat.setChatHooks({
            refreshConversations: listViews.loadConversations,
            syncConversationListTitle: listViews.syncConversationListTitle,
        });
        cascade.setCascadeHooks({
            renderConversations: listViews.renderConversations,
            loadConversations: listViews.loadConversations,
            activateConversation: activation.activateConversation,
            showEmptyState: activation.showEmptyState,
            refreshSendButton: chat.refreshSendButton,
        });
        listViews.initListViews({ switchView: (viewName) => { state.currentView = viewName; } });
        await listViews.loadCharacters();
        await listViews.loadConversations();
        return { listViews, tabs, fetchSpy, api };
    }

    it('有备用开场白的角色 → 弹开场白下拉 → 选备选 → POST body 含 greeting', async () => {
        const { fetchSpy } = await loadListViews({
            characters: [{
                id: 1, name: '角色A', conversation_count: 0,
                first_mes: '默认开场', alternate_greetings: ['备选一', '备选二'],
            }],
            conversations: [{ id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }],
            createdConv: { id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' },
        });

        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click(); // 模型选择 → 开场白选择

        await vi.waitFor(() => expect(document.querySelector('.greeting-selector-modal')).not.toBeNull());
        const select = document.querySelector('#gs-greeting');
        const optionValues = [...select.options].map((o) => o.value);
        expect(optionValues).toEqual(['__default__', '0', '1', '__none__']);

        select.value = '1'; // 选「备选二」
        document.querySelector('.gs-start').click();

        await vi.waitFor(() => {
            const post = fetchSpy.mock.calls.find(([u, o]) =>
                String(u).endsWith('/api/conversations') && o?.method === 'POST');
            expect(post).toBeTruthy();
            expect(JSON.parse(post[1].body).greeting).toBe('备选二');
        });
    });

    it('有备用开场白的角色 → 选「无开场白」→ POST body greeting = ""', async () => {
        const { fetchSpy } = await loadListViews({
            characters: [{
                id: 1, name: '角色A', conversation_count: 0,
                first_mes: '默认开场', alternate_greetings: ['备选一'],
            }],
            conversations: [{ id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }],
            createdConv: { id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' },
        });

        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click();
        await vi.waitFor(() => expect(document.querySelector('.greeting-selector-modal')).not.toBeNull());
        document.querySelector('#gs-greeting').value = '__none__';
        document.querySelector('.gs-start').click();

        await vi.waitFor(() => {
            const post = fetchSpy.mock.calls.find(([u, o]) =>
                String(u).endsWith('/api/conversations') && o?.method === 'POST');
            expect(post).toBeTruthy();
            expect(JSON.parse(post[1].body).greeting).toBe('');
        });
    });

    it('无备用开场白的角色 → 跳过开场白下拉 → POST body 不含 greeting 字段', async () => {
        const { fetchSpy } = await loadListViews({
            characters: [{ id: 1, name: '角色A', conversation_count: 0, first_mes: '默认开场' }],
            conversations: [{ id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }],
            createdConv: { id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' },
        });

        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click();

        await vi.waitFor(() => {
            const post = fetchSpy.mock.calls.find(([u, o]) =>
                String(u).endsWith('/api/conversations') && o?.method === 'POST');
            expect(post).toBeTruthy();
            expect('greeting' in JSON.parse(post[1].body)).toBe(false);
        });
        expect(document.querySelector('.greeting-selector-modal')).toBeNull();
    });

    it('开场白选择取消 → 不创建对话', async () => {
        const { fetchSpy } = await loadListViews({
            characters: [{
                id: 1, name: '角色A', conversation_count: 0,
                first_mes: '默认开场', alternate_greetings: ['备选一'],
            }],
            conversations: [],
        });

        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click();
        await vi.waitFor(() => expect(document.querySelector('.greeting-selector-modal')).not.toBeNull());
        document.querySelector('.gs-cancel').click();
        await new Promise((r) => setTimeout(r, 0));

        expect(fetchSpy.mock.calls.some(([u, o]) =>
            String(u).endsWith('/api/conversations') && o?.method === 'POST')).toBe(false);
    });

    it('仅存在预设对话（无备用开场白）→ 弹双选 → 选预设对话 → POST body 含 preset_dialogue', async () => {
        const { fetchSpy } = await loadListViews({
            characters: [{
                id: 1, name: '角色A', conversation_count: 0,
                first_mes: '默认开场', preset_dialogues: [{ name: '寒暄', content: '你好，久等了。' }],
            }],
            conversations: [{ id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }],
            createdConv: { id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' },
        });

        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click();

        await vi.waitFor(() => expect(document.querySelector('.greeting-selector-modal')).not.toBeNull());
        const presetSelect = document.querySelector('#gs-preset-dialogue');
        const optionValues = [...presetSelect.options].map((o) => o.value);
        expect(optionValues).toEqual(['__none__', '0']);

        presetSelect.value = '0'; // 选「寒暄」
        document.querySelector('.gs-start').click();

        await vi.waitFor(() => {
            const post = fetchSpy.mock.calls.find(([u, o]) =>
                String(u).endsWith('/api/conversations') && o?.method === 'POST');
            expect(post).toBeTruthy();
            expect(JSON.parse(post[1].body).preset_dialogue).toBe('你好，久等了。');
        });
    });

    it('选「无预设对话」→ POST body 不含 preset_dialogue 字段', async () => {
        const { fetchSpy } = await loadListViews({
            characters: [{
                id: 1, name: '角色A', conversation_count: 0,
                first_mes: '默认开场', preset_dialogues: [{ name: '寒暄', content: '你好。' }],
            }],
            conversations: [{ id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' }],
            createdConv: { id: 21, title: 't', character_id: 1, model_name: 'claude-sonnet-5', model_provider: 'claude' },
        });

        document.querySelector('#character-grid .chat-with').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .ms-start').click();
        await vi.waitFor(() => expect(document.querySelector('.greeting-selector-modal')).not.toBeNull());
        // 默认已是「无预设对话」，直接开始
        document.querySelector('.gs-start').click();

        await vi.waitFor(() => {
            const post = fetchSpy.mock.calls.find(([u, o]) =>
                String(u).endsWith('/api/conversations') && o?.method === 'POST');
            expect(post).toBeTruthy();
            expect('preset_dialogue' in JSON.parse(post[1].body)).toBe(false);
        });
    });
});
