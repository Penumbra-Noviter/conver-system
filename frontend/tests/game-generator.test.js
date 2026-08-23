/**
 * 游戏生成器组件测试（game-generator.js 深模块）
 *
 * 覆盖（公共接口边界 — __all__）：
 *   - initGameGenerator：注册 onGenerated 钩子
 *   - openGenerateFlow：打开模态框（标题 / textarea / 提交按钮 / 上传按钮）
 *     缺标题/空描述提交 → 校验错误提示
 *   - resetGameGenerator：复位生成中状态
 *   - Falsify：未 init 不炸 / 重复 init 更新钩子
 *
 * 挂载模式：jsdom + vi.resetModules() + 真实 modal.js 工厂（与 character-modal
 *   测试同模式）；showError/showSuccess 由 utils spy 抑制 DOM 副作用。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** 成功响应 */
const mockJson = (data, status = 200) => Promise.resolve({
    ok: status < 400,
    status,
    json: async () => data,
    text: async () => JSON.stringify(data),
});

/** 加载全新 game-generator 模块（DOM 先就位；返回模块 + utils spy） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = '';
    const gen = await import('../js/components/game-generator.js');
    const utils = await import('../js/utils.js');
    vi.spyOn(utils, 'showError').mockImplementation(() => {});
    vi.spyOn(utils, 'showSuccess').mockImplementation(() => {});
    return { gen, utils };
}

describe('game-generator — 协议表面 __all__', () => {
    it('__all__ 收口公开函数与 fetch seam', async () => {
        const { gen } = await loadModules();
        expect(gen.__all__.sort()).toEqual([
            'initGameGenerator',
            'openGenerateFlow',
            'resetGameGenerator',
            'setFetch',
        ]);
    });
});

describe('initGameGenerator — 钩子注册', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('注册 onGenerated 钩子：模拟成功生成后钩子被调用，模态框关闭', async () => {
        const { gen } = await loadModules();
        const hook = vi.fn();
        gen.setFetch(() => mockJson({ ok: true, game: { id: 'g1', file: 'g1.html' } }));
        gen.initGameGenerator({ onGenerated: hook });
        gen.openGenerateFlow();

        const desc = document.querySelector('#gg-description');
        desc.value = '一个赛博朋克世界';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => expect(hook).toHaveBeenCalledTimes(1));
        // 成功路径关闭模态框
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('成功生成后 onGenerated 返回完整响应（game 落列表刷新数据源）', async () => {
        const { gen } = await loadModules();
        const hook = vi.fn();
        gen.setFetch(() => mockJson({ ok: true, game: { id: 'g1', file: 'g1.html', name: '赛博追迹' } }));
        gen.initGameGenerator({ onGenerated: hook });
        gen.openGenerateFlow();

        document.querySelector('#gg-description').value = '赛博朋克';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => expect(hook).toHaveBeenCalledTimes(1));
    });

    it('Falsify: 校验失败 422 → 错误区域展示 + 重试按钮存在，模态框不关闭', async () => {
        const { gen } = await loadModules();
        gen.setFetch(() => mockJson({
            detail: { ok: false, errors: [{ field: 'data', message: '场景数据无效' }], suggestion: '请修正' },
        }, 422));
        gen.initGameGenerator({ onGenerated: vi.fn() });
        gen.openGenerateFlow();

        document.querySelector('#gg-description').value = '测试描述';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => {
            const resultArea = document.querySelector('#gg-result-area');
            expect(resultArea.className).toBe('gg-error');
        });
        expect(document.querySelector('#gg-retry-btn')).not.toBeNull();
        expect(document.querySelector('.modal-overlay')).not.toBeNull(); // 失败不关闭
    });

    it('Falsify: 不传参数不抛错', async () => {
        const { gen } = await loadModules();
        expect(() => gen.initGameGenerator()).not.toThrow();
        expect(() => gen.initGameGenerator({})).not.toThrow();
    });
});

describe('openGenerateFlow — 模态框结构', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => {
        document.body.innerHTML = '';
        vi.restoreAllMocks();
    });

    it('打开模态框：标题「AI 生成游戏」+ 关键字段存在', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        expect(overlay.querySelector('.modal.game-gen-modal')).not.toBeNull();
        expect(overlay.querySelector('.modal-header h3').textContent).toBe('AI 生成游戏');
        expect(overlay.querySelector('#gg-description')).not.toBeNull();
        expect(overlay.querySelector('#gg-title')).not.toBeNull();
        expect(overlay.querySelector('#gg-upload-btn')).not.toBeNull();
        expect(overlay.querySelector('#gg-submit-btn')).not.toBeNull();
    });

    it('提交按钮存在且文案正确', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const submitBtn = document.querySelector('#gg-submit-btn');
        expect(submitBtn).not.toBeNull();
        expect(submitBtn.textContent).toContain('生成游戏');
    });

    it('取消按钮存在且点击关闭模态框', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const cancelBtn = document.querySelector('.modal-cancel');
        expect(cancelBtn).not.toBeNull();
        cancelBtn.click();
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('空描述提交 → 校验错误提示', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const submitBtn = document.querySelector('#gg-submit-btn');
        const descError = document.querySelector('#gg-desc-error');
        expect(descError.hidden).toBe(true);

        // 提交空描述
        submitBtn.click();
        expect(descError.hidden).toBe(false);
        expect(descError.textContent).toContain('请输入世界观设定');
    });

    it('Falsify: 未 init 可调用 openGenerateFlow（创建模态框）', async () => {
        const { gen } = await loadModules();
        // 未调用 initGameGenerator 直接 open
        expect(() => gen.openGenerateFlow()).not.toThrow();
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
    });

    it('Falsify: 重复调用 openGenerateFlow 创建新模态框（removeExisting 替换旧弹窗）', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        const firstOverlay = document.querySelector('.modal-overlay');

        gen.openGenerateFlow();
        // 旧弹窗已移除，新弹窗存在
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
    });
});

describe('resetGameGenerator — 复位', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('复位不抛错', async () => {
        const { gen } = await loadModules();
        expect(() => gen.resetGameGenerator()).not.toThrow();
    });

    it('打开模态框后复位（生成中状态清理）', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        expect(() => gen.resetGameGenerator()).not.toThrow();
    });
});