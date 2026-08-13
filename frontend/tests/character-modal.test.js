/**
 * character-form / character-wizard 骨架级测试（ARC-10 C3-DEFER 兑现）
 *
 * ARC-10 C3 收口后，form/wizard 的遮罩创建、关闭按钮、遮罩点击关闭、Escape
 * 全部由通用模态框工厂 openModal 承担；本文件用真实 modal.js + jsdom 钉住骨架行为：
 *   - form 打开（创建/编辑标题、关键字段存在）、关闭三路径（close 按钮/取消/
 *     遮罩自身点击——内部点击不关闭）、Escape、Escape 关闭后重开、
 *     提交冒烟（成功 → POST /characters → success 状态 → 600ms 延时关窗 + onSuccess）
 *   - wizard 打开 + headerExtra 渲染（进度条/步骤指示器位于 header 与 body 之间）、
 *     点 manual 卡跳 step 3、步骤导航、关闭路径、removeExisting 移除旧弹窗
 *   - openModal 工厂契约：headerExtra 默认空串（既有调用方零影响）
 *
 * 挂载模式：jsdom + vi.resetModules() + 真实 modal.js 工厂（不手搓 DOM 夹具）；
 * 断言走「DOM 存在性 + 关闭后 overlay 移除」。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { TEMP_SLIDER } from '../js/components/character-submit.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

/** 加载全新 form + wizard + modal 实例（模块求值不触 DOM，body 清空顺序无关） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = '';
    const form = await import('../js/components/character-form.js');
    const wizard = await import('../js/components/character-wizard.js');
    const modal = await import('../js/components/modal.js');
    return { form, wizard, modal };
}

describe('showCharacterForm — 骨架级（真实 modal.js）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('打开（创建）：标题「创建新角色」+ 提交按钮「创建角色」+ 关键字段存在', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        expect(overlay.querySelector('.modal.character-form-modal')).not.toBeNull();
        expect(overlay.querySelector('.modal-header h3').textContent).toBe('创建新角色');
        expect(overlay.querySelector('#cf-submit').textContent).toBe('创建角色');
        for (const id of ['cf-name', 'cf-description', 'cf-personality', 'cf-first-mes',
            'cf-scenario', 'cf-mes-example', 'cf-temperature', 'cf-avatar', 'cf-tags', 'cf-creator']) {
            expect(overlay.querySelector(`#${id}`)).not.toBeNull();
        }
    });

    it('打开（编辑）：标题「编辑角色」+ 提交按钮「保存修改」+ 字段回填', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('edit', { id: 7, name: '老角色', personality: 'p' });

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay.querySelector('.modal-header h3').textContent).toBe('编辑角色');
        expect(overlay.querySelector('#cf-submit').textContent).toBe('保存修改');
        expect(overlay.querySelector('#cf-name').value).toBe('老角色');
        expect(overlay.querySelector('#cf-personality').value).toBe('p');
    });

    it('关闭路径 1：.modal-close 点击 → overlay 从 document 移除', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');
        document.querySelector('.modal-close').click();
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('关闭路径 2：.modal-cancel 点击 → overlay 移除', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');
        document.querySelector('.modal-cancel').click();
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('关闭路径 3：遮罩自身点击 → 移除；点击 modal 内部不关闭（遮罩目标误判防护）', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');

        document.querySelector('.modal-body').click(); // 内部点击 → 不关闭
        expect(document.querySelector('.modal-overlay')).not.toBeNull();

        document.querySelector('.modal-overlay').click(); // 遮罩自身 → 关闭
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('Escape：对 overlay 派发 keydown Escape → 移除', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');
        document.querySelector('.modal-overlay').dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
        );
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('Falsify:Escape 关闭后再打开 → 新 overlay 正常打开且可再次关闭', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');
        document.querySelector('.modal-overlay').dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
        );
        expect(document.querySelector('.modal-overlay')).toBeNull();

        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        overlay.click(); // 遮罩自身 → 关闭
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('提交冒烟：填齐三项提交 → POST /characters → success 状态 → 600ms 延时关窗 + onSuccess', async () => {
        const { form } = await loadModules();
        const fetchSpy = vi.fn(async () => mockJson({ id: 1, name: '角色A' }));
        globalThis.fetch = fetchSpy;
        const onSuccess = vi.fn();

        form.showCharacterForm('create', null, onSuccess);
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-personality').value = 'p';
        overlay.querySelector('#cf-first-mes').value = 'hi';
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => {
            expect(overlay.querySelector('#cf-status').classList.contains('success')).toBe(true);
        });
        expect(overlay.querySelector('#cf-status').textContent).toContain('创建成功');
        expect(fetchSpy).toHaveBeenCalledTimes(1);
        const [url, opts] = fetchSpy.mock.calls[0];
        expect(String(url)).toContain('/api/characters');
        expect(opts.method).toBe('POST');

        await sleep(700); // 600ms 延时关窗（逐字保持）
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(onSuccess).toHaveBeenCalledTimes(1);
    });
});

describe('showCharacterWizard — 骨架级（真实 modal.js + headerExtra）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('打开：wizard-modal 存在 + 标题「创建新角色」+ 初始为 step 1（创建方式卡片）', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay.querySelector('.modal.wizard-modal')).not.toBeNull();
        expect(overlay.querySelector('.modal-header h3').textContent).toBe('创建新角色');
        expect(overlay.querySelector('.wizard-mode-card[data-mode="manual"]')).not.toBeNull();
        expect(overlay.querySelector('#wizard-next').textContent).toBe('下一步');
    });

    it('headerExtra：进度条 + 步骤指示器渲染于 modal-header 之后、modal-body 之前', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay.querySelector('.modal-header + .wizard-progress')).not.toBeNull();
        expect(overlay.querySelector('.wizard-progress + .wizard-step-indicators')).not.toBeNull();
        expect(overlay.querySelector('.wizard-step-indicators + .modal-body')).not.toBeNull();
        expect(overlay.querySelectorAll('.wizard-step-dot')).toHaveLength(6);
        expect(overlay.querySelectorAll('.wizard-step-dot.active')).toHaveLength(1);
    });

    it('点 manual 卡 → 跳到 step 3：#wiz-name 出现 + 步骤点 active 数 = 3', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();

        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        expect(overlay.querySelector('#wiz-name')).not.toBeNull();
        expect(overlay.querySelectorAll('.wizard-step-dot.active')).toHaveLength(3);
    });

    it('步骤导航：填名后下一步 → step4 人格 → step5 对话风格 → step6 预览保存（按钮「保存角色」）', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();

        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        const nameInput = overlay.querySelector('#wiz-name');
        nameInput.value = '角色A';
        nameInput.dispatchEvent(new Event('input', { bubbles: true }));

        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wiz-personality')).not.toBeNull();
        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wiz-first-mes')).not.toBeNull();
        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wiz-temp')).not.toBeNull();
        expect(overlay.querySelector('#wizard-next').textContent).toBe('保存角色');
    });

    it('关闭路径：.modal-close 点击 → 移除；Escape → 移除；.modal-cancel → 移除', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        document.querySelector('.modal-close').click();
        expect(document.querySelector('.modal-overlay')).toBeNull();

        wizard.showCharacterWizard();
        document.querySelector('.modal-overlay').dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
        );
        expect(document.querySelector('.modal-overlay')).toBeNull();

        wizard.showCharacterWizard();
        document.querySelector('.modal-cancel').click();
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('removeExisting：form 已打开时打开 wizard → 旧 overlay 移除，仅剩 wizard', async () => {
        const { form, wizard } = await loadModules();
        form.showCharacterForm('create');
        wizard.showCharacterWizard();

        expect(document.querySelectorAll('.modal-overlay')).toHaveLength(1);
        expect(document.querySelector('.wizard-modal')).not.toBeNull();
        expect(document.querySelector('.character-form-modal')).toBeNull();
    });
});

describe('showCharacterForm — 字段交互与提交路径（组件级）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('温度滑块 input → 数值实时两位小数显示', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');
        const slider = document.querySelector('#cf-temperature');
        const value = document.querySelector('#cf-temp-value');
        slider.value = '1.25';
        slider.dispatchEvent(new Event('input', { bubbles: true }));
        expect(value.textContent).toBe('1.25');
    });

    it('温度初始显示统一 toFixed(2)：缺省 0.70 + 滑块 min/max/step 与 TEMP_SLIDER 一致', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');
        const slider = document.querySelector('#cf-temperature');
        expect(document.querySelector('#cf-temp-value').textContent).toBe('0.70');
        expect(slider.getAttribute('min')).toBe(String(TEMP_SLIDER.min));
        expect(slider.getAttribute('max')).toBe(String(TEMP_SLIDER.max));
        expect(slider.getAttribute('step')).toBe(String(TEMP_SLIDER.step));

        // 编辑模式带温度 → 同样两位小数显示
        form.showCharacterForm('edit', { id: 1, name: 'x', temperature: 1 });
        expect(document.querySelector('#cf-temp-value').textContent).toBe('1.00');
    });

    it('头像预览：输入 URL → img 渲染；清空 → 「无头像」', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('create');
        const avatarInput = document.querySelector('#cf-avatar');
        const preview = document.querySelector('#cf-avatar-preview');

        avatarInput.value = 'http://x/a.png';
        avatarInput.dispatchEvent(new Event('input', { bubbles: true }));
        expect(preview.querySelector('img[alt="头像预览"]')).not.toBeNull();

        avatarInput.value = '';
        avatarInput.dispatchEvent(new Event('input', { bubbles: true }));
        expect(preview.textContent).toContain('无头像');
    });

    it('头像预览初始回填：编辑模式带头像 → img + 加载失败回退（共享纯函数语义）', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('edit', { id: 1, name: 'x', avatar: 'http://x/a.png' });
        const preview = document.querySelector('#cf-avatar-preview');
        expect(preview.querySelector('img[alt="头像预览"]')).not.toBeNull();
        expect(preview.innerHTML).toContain('图片加载失败');
    });

    it('提交校验：名称为空 → 「角色名称不能为空」+ 不发请求', async () => {
        const { form } = await loadModules();
        const fetchSpy = vi.fn();
        globalThis.fetch = fetchSpy;
        form.showCharacterForm('create');

        document.querySelector('#cf-submit').click();
        expect(document.querySelector('#cf-name-error').textContent).toBe('角色名称不能为空');
        expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('完整性软确认：缺人格/开场白 → 确认框；取消 → 不提交', async () => {
        const { form } = await loadModules();
        const fetchSpy = vi.fn();
        globalThis.fetch = fetchSpy;
        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-submit').click();

        // 确认框出现（真实 confirm-dialog）→ 取消
        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-cancel').click();
        await sleep(20);
        expect(fetchSpy).not.toHaveBeenCalled();
        expect(document.querySelector('.character-form-modal')).not.toBeNull(); // 表单仍在
    });

    it('完整性软确认：确认 → 继续提交成功', async () => {
        const { form } = await loadModules();
        const fetchSpy = vi.fn(async () => mockJson({ id: 1, name: '角色A' }));
        globalThis.fetch = fetchSpy;
        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => expect(document.querySelector('.confirm-modal')).not.toBeNull());
        document.querySelector('.confirm-modal .confirm-ok').click();
        await vi.waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
        expect(overlay.querySelector('#cf-status').textContent).toContain('创建成功');
    });

    it('编辑提交成功：PUT /characters/{id} + 「更新成功」+ 600ms 延时关窗', async () => {
        const { form } = await loadModules();
        const fetchSpy = vi.fn(async () => mockJson({ id: 7, name: '老角色' }));
        globalThis.fetch = fetchSpy;
        const onSuccess = vi.fn();
        form.showCharacterForm('edit', { id: 7, name: '老角色' }, onSuccess);
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '老角色';
        overlay.querySelector('#cf-personality').value = 'p';
        overlay.querySelector('#cf-first-mes').value = 'hi';
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => {
            expect(overlay.querySelector('#cf-status').classList.contains('success')).toBe(true);
        });
        expect(overlay.querySelector('#cf-status').textContent).toContain('更新成功');
        const [url, opts] = fetchSpy.mock.calls[0];
        expect(String(url)).toContain('/api/characters/7');
        expect(opts.method).toBe('PUT');

        await sleep(700);
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(onSuccess).toHaveBeenCalledTimes(1);
    });

    it('提交失败：error 状态 + 按钮/文案恢复（创建模式）', async () => {
        const { form } = await loadModules();
        globalThis.fetch = vi.fn(async () => mockJson({ detail: 'boom' }, 500));
        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-personality').value = 'p';
        overlay.querySelector('#cf-first-mes').value = 'hi';
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => {
            expect(overlay.querySelector('#cf-status').classList.contains('error')).toBe(true);
        });
        expect(overlay.querySelector('#cf-status').textContent).toContain('boom');
        const submitBtn = overlay.querySelector('#cf-submit');
        expect(submitBtn.disabled).toBe(false);
        expect(submitBtn.textContent).toBe('创建角色');
        expect(document.querySelector('.modal-overlay')).not.toBeNull(); // 不关窗
    });

    it('编辑模式 tags 数组回填为逗号字符串', async () => {
        const { form } = await loadModules();
        form.showCharacterForm('edit', { id: 1, name: 'x', tags: ['冒险', '奇幻'] });
        expect(document.querySelector('#cf-tags').value).toBe('冒险, 奇幻');
    });

    it('提交时 tags 中英文逗号分割（含 trim/空项过滤）', async () => {
        const { form } = await loadModules();
        let capturedBody = null;
        globalThis.fetch = vi.fn(async (url, opts) => {
            capturedBody = JSON.parse(opts.body);
            return mockJson({ id: 1, name: '角色A' });
        });
        form.showCharacterForm('create');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#cf-name').value = '角色A';
        overlay.querySelector('#cf-personality').value = 'p';
        overlay.querySelector('#cf-first-mes').value = 'hi';
        overlay.querySelector('#cf-tags').value = ' 冒险 , 奇幻，, 可爱';
        overlay.querySelector('#cf-submit').click();

        await vi.waitFor(() => expect(capturedBody).not.toBeNull());
        expect(capturedBody.tags).toEqual(['冒险', '奇幻', '可爱']);
        expect(capturedBody.avatar).toBeNull(); // 空头像 → null
        expect(capturedBody.creator).toBe(''); // 未填 creator → 空串
        expect(capturedBody.temperature).toBe(0.7); // 数值类型
    });
});

describe('showCharacterWizard — 步骤流程（step2-6 / 解析 / 模板 / 保存）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    /** 走到指定步骤：manual 卡 → step3；填名后连续下一步 */
    async function walkToStep(wizard, targetStep) {
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click(); // → step 3
        const nameInput = overlay.querySelector('#wiz-name');
        nameInput.value = '角色A';
        nameInput.dispatchEvent(new Event('input', { bubbles: true }));
        let step = 3;
        while (step < targetStep) {
            overlay.querySelector('#wizard-next').click();
            step++;
        }
        return overlay;
    }

    it('下一步未选创建方式 → 状态栏「请选择一种创建方式」+ error 类', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#wizard-next').click();
        const status = overlay.querySelector('#wizard-status');
        expect(status.textContent).toBe('请选择一种创建方式');
        expect(status.classList.contains('error')).toBe(true);
    });

    it('import 卡 → 选中；下一步 → step2 导入 UI；空文本解析 → 「请先粘贴文档内容」', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="import"]').click();
        expect(overlay.querySelector('.wizard-mode-card[data-mode="import"]').classList.contains('selected')).toBe(true);
        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wizard-import-text')).not.toBeNull();
        expect(overlay.querySelector('#wizard-parse-btn')).not.toBeNull();

        overlay.querySelector('#wizard-parse-btn').click();
        await vi.waitFor(() => {
            expect(overlay.querySelector('.wizard-parse-error')).not.toBeNull();
        });
        expect(overlay.querySelector('.wizard-parse-error').textContent).toContain('请先粘贴文档内容');
    });

    it('导入解析成功：POST /characters/parse-document → 「已提取 2 个字段」+ 字段应用', async () => {
        const { wizard } = await loadModules();
        let parseCalled = false;
        globalThis.fetch = vi.fn(async (url, opts) => {
            if (String(url).includes('/parse-document')) {
                parseCalled = true;
                expect(opts.method).toBe('POST');
                return mockJson({
                    parsed_fields: ['name', 'description'],
                    name: '小红',
                    description: '森林里的小狐狸',
                    personality: '活泼开朗',
                });
            }
            return mockJson({});
        });
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="import"]').click();
        overlay.querySelector('#wizard-next').click();
        overlay.querySelector('#wizard-import-text').value = '小红是一只住在森林里的小狐狸';
        overlay.querySelector('#wizard-import-text').dispatchEvent(new Event('input', { bubbles: true }));
        overlay.querySelector('#wizard-parse-btn').click();

        await vi.waitFor(() => expect(parseCalled).toBe(true));
        await vi.waitFor(() => {
            expect(overlay.querySelector('.wizard-parse-success')).not.toBeNull();
        });
        expect(overlay.querySelector('.wizard-parse-success').textContent).toContain('已提取 2 个字段');
        // 解析字段已应用 → 下一步到 step3 可见回填
        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wiz-name').value).toBe('小红');
        expect(overlay.querySelector('#wiz-desc').value).toBe('森林里的小狐狸');
    });

    it('导入解析失败：API 500 → parseError 展示原因', async () => {
        const { wizard } = await loadModules();
        globalThis.fetch = vi.fn(async () => mockJson({ detail: '解析服务不可用' }, 500));
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="import"]').click();
        overlay.querySelector('#wizard-next').click();
        overlay.querySelector('#wizard-import-text').value = '一些文档';
        overlay.querySelector('#wizard-import-text').dispatchEvent(new Event('input', { bubbles: true }));
        overlay.querySelector('#wizard-parse-btn').click();

        await vi.waitFor(() => {
            expect(overlay.querySelector('.wizard-parse-error')).not.toBeNull();
        });
        expect(overlay.querySelector('.wizard-parse-error').textContent).toContain('解析服务不可用');
    });

    it('template 卡 → 模板网格；点模板 → 选中 + 字段应用；未选模板下一步 → 错误', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="template"]').click();
        overlay.querySelector('#wizard-next').click();
        const firstCard = overlay.querySelector('.template-card[data-template-id="senpai"]');
        expect(firstCard).not.toBeNull();
        expect(firstCard.textContent).toContain('知性学姐');

        // 未选模板 → 下一步报错
        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wizard-status').textContent).toBe('请选择一个模板');

        // 选中模板 → 字段应用 → 下一步到 step3 可见回填
        firstCard.click();
        expect(overlay.querySelector('.template-card.selected')).not.toBeNull();
        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wiz-name').value).toBe('知性学姐');
        expect(overlay.querySelector('#wiz-tags').value).toContain('校园');
    });

    it('上一步导航：step3 → step2（手动占位）→ step1（创建方式卡片）', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        expect(overlay.querySelector('#wiz-name')).not.toBeNull();
        overlay.querySelector('#wizard-prev').click();
        // 手动模式跳步后上一步回到 step2 占位页
        expect(overlay.querySelector('#wiz-name')).toBeNull();
        overlay.querySelector('#wizard-prev').click();
        expect(overlay.querySelector('.wizard-mode-card[data-mode="manual"]')).not.toBeNull();
    });

    it('step3 空名称下一步 → 「角色名称不能为空」+ 聚焦名称输入框', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        overlay.querySelector('#wizard-next').click();
        expect(overlay.querySelector('#wizard-status').textContent).toBe('角色名称不能为空');
        expect(document.activeElement).toBe(overlay.querySelector('#wiz-name'));
    });

    it('step3 头像 URL 输入 → 预览 img 渲染；清空 → 「无头像」；tags 输入中英文逗号分割', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        const avatarInput = overlay.querySelector('#wiz-avatar');
        const preview = overlay.querySelector('#wiz-avatar-preview');

        avatarInput.value = 'http://x/a.png';
        avatarInput.dispatchEvent(new Event('input', { bubbles: true }));
        expect(preview.querySelector('img[alt="头像预览"]')).not.toBeNull();

        avatarInput.value = '';
        avatarInput.dispatchEvent(new Event('input', { bubbles: true }));
        expect(preview.textContent).toContain('无头像');

        // tags 输入 → state.tags 分割（中英文逗号 + 空白过滤）→ step6 摘要回显
        const tagsInput = overlay.querySelector('#wiz-tags');
        tagsInput.value = ' 冒险 , 奇幻，, 可爱';
        tagsInput.dispatchEvent(new Event('input', { bubbles: true }));
        const nameInput = overlay.querySelector('#wiz-name');
        nameInput.value = '角色A';
        nameInput.dispatchEvent(new Event('input', { bubbles: true }));
        overlay.querySelector('#wizard-next').click(); // → step4
        overlay.querySelector('#wizard-next').click(); // → step5
        overlay.querySelector('#wizard-next').click(); // → step6
        expect(overlay.querySelector('.wizard-summary').textContent).toContain('冒险');
        expect(overlay.querySelector('.wizard-summary').textContent).toContain('可爱');
    });

    it('step4/5 字段输入经 state 保留；step6 摘要回显（人格/开场白/温度滑块联动）', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = await walkToStep(wizard, 4);

        overlay.querySelector('#wiz-personality').value = '冷静理性';
        overlay.querySelector('#wiz-personality').dispatchEvent(new Event('input', { bubbles: true }));
        overlay.querySelector('#wiz-scenario').value = '图书馆';
        overlay.querySelector('#wiz-scenario').dispatchEvent(new Event('input', { bubbles: true }));
        overlay.querySelector('#wiz-system-prompt').value = '自定义提示';
        overlay.querySelector('#wiz-system-prompt').dispatchEvent(new Event('input', { bubbles: true }));

        overlay.querySelector('#wizard-next').click(); // → step 5
        overlay.querySelector('#wiz-first-mes').value = '你好呀';
        overlay.querySelector('#wiz-first-mes').dispatchEvent(new Event('input', { bubbles: true }));
        overlay.querySelector('#wiz-mes-example').value = '{{char}}: 示例';
        overlay.querySelector('#wiz-mes-example').dispatchEvent(new Event('input', { bubbles: true }));

        overlay.querySelector('#wizard-next').click(); // → step 6
        expect(overlay.querySelector('.wizard-summary').textContent).toContain('冷静理性');
        expect(overlay.querySelector('.wizard-summary').textContent).toContain('图书馆');
        expect(overlay.querySelector('.wizard-summary').textContent).toContain('你好呀');

        // 温度滑块联动
        const tempSlider = overlay.querySelector('#wiz-temp');
        tempSlider.value = '1.5';
        tempSlider.dispatchEvent(new Event('input', { bubbles: true }));
        expect(overlay.querySelector('#wiz-temp-value').textContent).toBe('1.50');
    });

    it('step6 温度初始显示统一 toFixed(2)：0.70 + 滑块 min/max/step 与 TEMP_SLIDER 一致', async () => {
        const { wizard } = await loadModules();
        wizard.showCharacterWizard();
        const overlay = await walkToStep(wizard, 6);
        const slider = overlay.querySelector('#wiz-temp');
        expect(overlay.querySelector('#wiz-temp-value').textContent).toBe('0.70');
        expect(slider.getAttribute('min')).toBe(String(TEMP_SLIDER.min));
        expect(slider.getAttribute('max')).toBe(String(TEMP_SLIDER.max));
        expect(slider.getAttribute('step')).toBe(String(TEMP_SLIDER.step));
    });

    it('step6 保存成功：POST /characters → success → 600ms 延时关窗 + onSuccess', async () => {
        const { wizard } = await loadModules();
        let capturedBody = null;
        globalThis.fetch = vi.fn(async (url, opts) => {
            capturedBody = JSON.parse(opts.body);
            return mockJson({ id: 1, name: '角色A' });
        });
        const onSuccess = vi.fn();
        wizard.showCharacterWizard(onSuccess);
        const overlay = await walkToStep(wizard, 6);

        overlay.querySelector('#wizard-next').click(); // 「保存角色」
        await vi.waitFor(() => {
            expect(overlay.querySelector('#wizard-status').classList.contains('success')).toBe(true);
        });
        expect(overlay.querySelector('#wizard-status').textContent).toContain('创建成功');
        const [url, opts] = globalThis.fetch.mock.calls[0];
        expect(String(url)).toContain('/api/characters');
        expect(opts.method).toBe('POST');
        expect(capturedBody.creator).toBe(''); // wizard 恒 create + creator 恒空
        expect(capturedBody.temperature).toBe(0.7);

        await sleep(700);
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(onSuccess).toHaveBeenCalledTimes(1);
    });

    it('step6 保存失败：error 状态 + 按钮恢复「保存角色」', async () => {
        const { wizard } = await loadModules();
        globalThis.fetch = vi.fn(async () => mockJson({ detail: 'boom' }, 500));
        wizard.showCharacterWizard();
        const overlay = await walkToStep(wizard, 6);

        overlay.querySelector('#wizard-next').click();
        await vi.waitFor(() => {
            expect(overlay.querySelector('#wizard-status').classList.contains('error')).toBe(true);
        });
        expect(overlay.querySelector('#wizard-status').textContent).toContain('boom');
        const nextBtn = overlay.querySelector('#wizard-next');
        expect(nextBtn.disabled).toBe(false);
        expect(nextBtn.textContent).toBe('保存角色');
        expect(document.querySelector('.modal-overlay')).not.toBeNull(); // 不关窗
    });
});

describe('openModal 工厂契约 — headerExtra（T-11 新增 API 面）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('默认空串：header 后直接 modal-body，无额外节点（既有调用方零影响）', async () => {
        const { modal } = await loadModules();
        modal.openModal({ title: '测试' });

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay.querySelector('.modal-header + .modal-body')).not.toBeNull();
        expect(overlay.querySelector('.modal-header + *:not(.modal-body)')).toBeNull();
    });

    it('传入 headerExtra：渲染于 header 与 body 之间', async () => {
        const { modal } = await loadModules();
        modal.openModal({ title: '测试', headerExtra: '<div class="x-extra">extra</div>' });

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay.querySelector('.modal-header + .x-extra')).not.toBeNull();
        expect(overlay.querySelector('.x-extra + .modal-body')).not.toBeNull();
    });
});
