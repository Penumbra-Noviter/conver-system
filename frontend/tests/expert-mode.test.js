/**
 * PD-6 专家模式前端（基础/专家两态编辑）契约锁（Vitest）
 *
 * 逐条覆盖工单 4 条验收标准：
 *   1. 两态切换：基础态显示结构化字段，专家态显示单个大 textarea 直编
 *      expert_prompt、隐藏 personality/scenario/system_prompt；可逆切换不丢
 *      expert_prompt —— form 组件级（jsdom + 真实 modal.js）
 *   2. 「从当前字段生成」→ expert_prompt 预填（拼接顺序固定 system_prompt
 *      || personality + scenario + post_history_instructions）；「空白开始」
 *      → 清空 —— buildExpertPrompt 纯函数 + form 组件级按钮
 *   3. 保存 payload 含 prompt_mode + expert_prompt（字段名与后端 schema
 *      一致，缺省 simple / ''）—— buildCharacterPayload 纯函数 + form 组件级
 *   4. 编辑已有 expert 角色 → 重开面板还原 expert 态与文本 —— form edit 组件级
 *
 * 挂载模式：纯函数直 import；组件级用 vi.resetModules() + jsdom（真实
 *   modal.js / form），fetch mock 捕获请求体。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildCharacterPayload, buildExpertPrompt } from '../js/components/character-submit.js';

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

describe('验收标准 2 — buildExpertPrompt 拼接顺序（纯函数）', () => {
    it('system_prompt 优先，空则 personality；拼接顺序 system/scenario/post_history 固定', () => {
        expect(buildExpertPrompt({
            system_prompt: 'SP', personality: 'P', scenario: 'S', post_history_instructions: 'PH',
        })).toBe('SP\n\nS\n\nPH');
    });

    it('system_prompt 为空 → 回落 personality 作为首段', () => {
        expect(buildExpertPrompt({
            system_prompt: '', personality: 'P', scenario: 'S', post_history_instructions: 'PH',
        })).toBe('P\n\nS\n\nPH');
    });

    it('空字段被过滤，不产生多余分隔符', () => {
        expect(buildExpertPrompt({})).toBe('');
        expect(buildExpertPrompt({ system_prompt: 'SP' })).toBe('SP');
        expect(buildExpertPrompt({ personality: 'P', scenario: '', post_history_instructions: null })).toBe('P');
        expect(buildExpertPrompt({ system_prompt: '', personality: '', scenario: '', post_history_instructions: '' })).toBe('');
    });

    it('字段 trim（首尾空白去除）', () => {
        expect(buildExpertPrompt({
            system_prompt: '  SP  ', scenario: ' S ', post_history_instructions: ' PH ',
        })).toBe('SP\n\nS\n\nPH');
    });

    it('Falsify：非字符串/null/undefined 输入不抛错（视为空段）', () => {
        expect(buildExpertPrompt({ system_prompt: 123 })).toBe('');
        expect(buildExpertPrompt({ system_prompt: null, personality: null })).toBe('');
        expect(buildExpertPrompt({ scenario: undefined, post_history_instructions: {} })).toBe('');
        expect(buildExpertPrompt(null)).toBe('');
        expect(buildExpertPrompt('not-object')).toBe('');
    });
});

describe('验收标准 3 — 保存 payload 含 prompt_mode + expert_prompt（纯函数）', () => {
    it('缺省：prompt_mode = simple、expert_prompt = ""', () => {
        const payload = buildCharacterPayload({});
        expect(payload.prompt_mode).toBe('simple');
        expect(payload.expert_prompt).toBe('');
    });

    it('传入 expert + 整段 → 逐字段透传', () => {
        const payload = buildCharacterPayload({ prompt_mode: 'expert', expert_prompt: '整段 prompt' });
        expect(payload.prompt_mode).toBe('expert');
        expect(payload.expert_prompt).toBe('整段 prompt');
    });

    it('Falsify：prompt_mode 非法值归一为 simple（二值域收口）', () => {
        expect(buildCharacterPayload({ prompt_mode: 'bogus' }).prompt_mode).toBe('simple');
        expect(buildCharacterPayload({ prompt_mode: 'EXPERT' }).prompt_mode).toBe('simple');
        expect(buildCharacterPayload({ prompt_mode: null }).prompt_mode).toBe('simple');
    });

    it('Falsify：expert_prompt 非字符串归一为空串', () => {
        expect(buildCharacterPayload({ expert_prompt: null }).expert_prompt).toBe('');
        expect(buildCharacterPayload({ expert_prompt: undefined }).expert_prompt).toBe('');
    });
});

describe('PD-6 form 组件级（jsdom + 真实 modal.js）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    async function loadForm() {
        vi.resetModules();
        document.body.innerHTML = '';
        return await import('../js/components/character-form.js');
    }

    const field = (overlay, id) => overlay.querySelector(`#${id}`).closest('.form-field');

    describe('验收标准 1 — 两态切换 + 可逆不丢 expert_prompt', () => {
        it('基础态（默认）：结构化字段显示，expert 区隐藏', async () => {
            const form = await loadForm();
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            expect(overlay.querySelector('#cf-expert-area').hidden).toBe(true);
            expect(field(overlay, 'cf-personality').hidden).toBe(false);
            expect(field(overlay, 'cf-scenario').hidden).toBe(false);
            expect(field(overlay, 'cf-system-prompt').hidden).toBe(false);
        });

        it('切专家态：隐藏 personality/scenario/system_prompt，显示 expert 区，保留 mes_example', async () => {
            const form = await loadForm();
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-mode-expert').click();
            expect(overlay.querySelector('#cf-expert-area').hidden).toBe(false);
            expect(field(overlay, 'cf-personality').hidden).toBe(true);
            expect(field(overlay, 'cf-scenario').hidden).toBe(true);
            expect(field(overlay, 'cf-system-prompt').hidden).toBe(true);
            expect(field(overlay, 'cf-mes-example').hidden).toBe(false);
        });

        it('切回基础态：结构化字段恢复，expert 区隐藏', async () => {
            const form = await loadForm();
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-mode-expert').click();
            overlay.querySelector('#cf-mode-basic').click();
            expect(overlay.querySelector('#cf-expert-area').hidden).toBe(true);
            expect(field(overlay, 'cf-personality').hidden).toBe(false);
            expect(field(overlay, 'cf-scenario').hidden).toBe(false);
            expect(field(overlay, 'cf-system-prompt').hidden).toBe(false);
        });

        it('可逆切换不丢 expert_prompt（expert → basic → expert）', async () => {
            const form = await loadForm();
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-mode-expert').click();
            overlay.querySelector('#cf-expert-prompt').value = '整段 prompt';
            overlay.querySelector('#cf-mode-basic').click();
            overlay.querySelector('#cf-mode-expert').click();
            expect(overlay.querySelector('#cf-expert-prompt').value).toBe('整段 prompt');
        });
    });

    describe('验收标准 2 — 从当前字段生成 / 空白开始（组件级）', () => {
        it('从当前字段生成：system_prompt 优先拼接 + scenario', async () => {
            const form = await loadForm();
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-personality').value = '人格';
            overlay.querySelector('#cf-system-prompt').value = 'SP';
            overlay.querySelector('#cf-scenario').value = '场景';
            overlay.querySelector('#cf-mode-expert').click();
            overlay.querySelector('#cf-expert-generate').click();
            expect(overlay.querySelector('#cf-expert-prompt').value).toBe('SP\n\n场景');
        });

        it('从当前字段生成：system_prompt 空 → 回落 personality', async () => {
            const form = await loadForm();
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-personality').value = '人格';
            overlay.querySelector('#cf-scenario').value = '场景';
            overlay.querySelector('#cf-mode-expert').click();
            overlay.querySelector('#cf-expert-generate').click();
            expect(overlay.querySelector('#cf-expert-prompt').value).toBe('人格\n\n场景');
        });

        it('空白开始：清空 expert_prompt', async () => {
            const form = await loadForm();
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-mode-expert').click();
            overlay.querySelector('#cf-expert-prompt').value = '旧文本';
            overlay.querySelector('#cf-expert-clear').click();
            expect(overlay.querySelector('#cf-expert-prompt').value).toBe('');
        });
    });

    describe('验收标准 3 — 保存 payload 含 prompt_mode + expert_prompt（组件级）', () => {
        it('专家态保存 → payload 含 prompt_mode=expert + expert_prompt', async () => {
            const form = await loadForm();
            let captured = null;
            globalThis.fetch = vi.fn(async (url, opts) => {
                captured = JSON.parse(opts.body);
                return mockJson({ id: 1, name: '角色A' });
            });
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-name').value = '角色A';
            overlay.querySelector('#cf-personality').value = 'p';
            overlay.querySelector('#cf-first-mes').value = 'hi';
            overlay.querySelector('#cf-mode-expert').click();
            overlay.querySelector('#cf-expert-prompt').value = '整段 prompt';
            overlay.querySelector('#cf-submit').click();

            await vi.waitFor(() => expect(captured).not.toBeNull());
            expect(captured.prompt_mode).toBe('expert');
            expect(captured.expert_prompt).toBe('整段 prompt');
        });

        it('基础态保存 → prompt_mode=simple，expert_prompt 为空串', async () => {
            const form = await loadForm();
            let captured = null;
            globalThis.fetch = vi.fn(async (url, opts) => {
                captured = JSON.parse(opts.body);
                return mockJson({ id: 1, name: '角色A' });
            });
            form.showCharacterForm('create');
            const overlay = document.querySelector('.modal-overlay');
            overlay.querySelector('#cf-name').value = '角色A';
            overlay.querySelector('#cf-personality').value = 'p';
            overlay.querySelector('#cf-first-mes').value = 'hi';
            overlay.querySelector('#cf-submit').click();

            await vi.waitFor(() => expect(captured).not.toBeNull());
            expect(captured.prompt_mode).toBe('simple');
            expect(captured.expert_prompt).toBe('');
        });
    });

    describe('验收标准 4 — 编辑已有 expert 角色还原', () => {
        it('编辑 expert 角色 → 还原 expert 态与文本', async () => {
            const form = await loadForm();
            form.showCharacterForm('edit', {
                id: 1, name: 'x', prompt_mode: 'expert', expert_prompt: '整段 prompt',
            });
            const overlay = document.querySelector('.modal-overlay');
            expect(overlay.querySelector('#cf-expert-area').hidden).toBe(false);
            expect(overlay.querySelector('#cf-expert-prompt').value).toBe('整段 prompt');
            expect(field(overlay, 'cf-personality').hidden).toBe(true);
        });

        it('编辑 simple 角色 → 默认基础态（expert_prompt 仍回填但区隐藏）', async () => {
            const form = await loadForm();
            form.showCharacterForm('edit', {
                id: 1, name: 'x', prompt_mode: 'simple', expert_prompt: '已有专家文本',
            });
            const overlay = document.querySelector('.modal-overlay');
            expect(overlay.querySelector('#cf-expert-area').hidden).toBe(true);
            expect(overlay.querySelector('#cf-expert-prompt').value).toBe('已有专家文本');
        });

        it('编辑无 prompt_mode 字段的存量角色 → 默认 simple 不抛错', async () => {
            const form = await loadForm();
            form.showCharacterForm('edit', { id: 1, name: 'x' });
            const overlay = document.querySelector('.modal-overlay');
            expect(overlay.querySelector('#cf-expert-area').hidden).toBe(true);
            expect(overlay.querySelector('#cf-expert-prompt').value).toBe('');
        });
    });
});
