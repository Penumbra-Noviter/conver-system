/**
 * model-selector 组件联动测试（ARC-9 C5 — 创建对话时的 Provider/模型选择弹窗）
 *
 * 覆盖：打开（标题/Provider 选项/默认选中/模型下拉联动填充）、选择（.ms-start 回传
 *   {provider, model}）、取消（.ms-cancel / Escape → null）、自定义模型输入、
 *   Provider 切换联动模型下拉、Falsify（空 providers 列表 / 默认模型不在列表回填）。
 *
 * 基于通用模态框工厂 openModal（真实 modal.js），jsdom 直测；断言经 Promise
 * 结果与关键 DOM 文案（弹窗标题 / 下拉选项值），不钉弹窗内部结构。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

const PROVIDERS = [
    { key: 'claude', name: 'Claude (Anthropic)', models: ['claude-sonnet-5', 'claude-opus-4-8'] },
    { key: 'deepseek', name: 'DeepSeek', models: ['deepseek-chat'] },
];

/** 加载全新 model-selector + state 实例 */
async function loadSelector() {
    vi.resetModules();
    document.body.innerHTML = '';
    const selector = await import('../js/components/model-selector.js');
    const state = (await import('../js/state.js')).state;
    return { selector, state };
}

describe('showModelSelector — 打开 / 选择 / 取消', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('打开：标题含角色名 + Provider 选项 + 默认 Provider 预选中 + 模型下拉按默认模型联动', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = PROVIDERS;
        state.defaultProvider = 'claude';
        state.defaultModel = 'claude-sonnet-5';

        const promise = selector.showModelSelector('角色A');

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay.textContent).toContain('开始对话 · 角色A');
        const providerSelect = overlay.querySelector('#ms-provider');
        expect([...providerSelect.options].map((o) => o.value)).toEqual(['claude', 'deepseek']);
        expect(providerSelect.value).toBe('claude');
        const modelSelect = overlay.querySelector('#ms-model');
        expect([...modelSelect.options].map((o) => o.value))
            .toEqual(['claude-sonnet-5', 'claude-opus-4-8', '__custom__']);
        expect(modelSelect.value).toBe('claude-sonnet-5');
        promise.then(() => {});
    });

    it('选择模型 → resolve {provider, model} 且弹窗移除', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = PROVIDERS;
        state.defaultProvider = 'claude';
        state.defaultModel = 'claude-sonnet-5';

        const promise = selector.showModelSelector('角色A');
        const overlay = document.querySelector('.modal-overlay');
        overlay.querySelector('#ms-model').value = 'claude-opus-4-8';
        overlay.querySelector('.ms-start').click();

        await expect(promise).resolves.toEqual({ provider: 'claude', model: 'claude-opus-4-8' });
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('取消按钮 → resolve null 且弹窗移除', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = PROVIDERS;

        const promise = selector.showModelSelector('角色A');
        document.querySelector('.modal-overlay .ms-cancel').click();

        await expect(promise).resolves.toBeNull();
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('Escape → resolve null（通用关闭路径）', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = PROVIDERS;

        const promise = selector.showModelSelector('角色A');
        const overlay = document.querySelector('.modal-overlay');
        overlay.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));

        await expect(promise).resolves.toBeNull();
    });

    it('自定义模型：选「自定义模型」→ 输入框出现 → 提交回传输入值', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = PROVIDERS;
        state.defaultProvider = 'claude';
        state.defaultModel = 'claude-sonnet-5';

        const promise = selector.showModelSelector('角色A');
        const overlay = document.querySelector('.modal-overlay');
        const modelSelect = overlay.querySelector('#ms-model');
        const customInput = overlay.querySelector('#ms-custom-model');
        modelSelect.value = '__custom__';
        modelSelect.dispatchEvent(new Event('change', { bubbles: true }));
        expect(customInput.style.display).not.toBe('none');
        customInput.value = 'my-custom-model';
        overlay.querySelector('.ms-start').click();

        await expect(promise).resolves.toEqual({ provider: 'claude', model: 'my-custom-model' });
    });

    it('Provider 切换联动模型下拉（自定义输入值跨 Provider 保留）', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = PROVIDERS;
        state.defaultProvider = 'claude';
        state.defaultModel = 'claude-sonnet-5';

        const promise = selector.showModelSelector('角色A');
        const overlay = document.querySelector('.modal-overlay');
        const providerSelect = overlay.querySelector('#ms-provider');
        const modelSelect = overlay.querySelector('#ms-model');
        const customInput = overlay.querySelector('#ms-custom-model');
        // 先输入自定义值再切 Provider — 值应保留（fillModelSelect prevCustomVal 语义）
        modelSelect.value = '__custom__';
        modelSelect.dispatchEvent(new Event('change', { bubbles: true }));
        customInput.value = 'keep-me';
        providerSelect.value = 'deepseek';
        providerSelect.dispatchEvent(new Event('change', { bubbles: true }));

        expect([...modelSelect.options].map((o) => o.value)).toEqual(['deepseek-chat', '__custom__']);
        expect(modelSelect.value).toBe('__custom__');
        expect(customInput.value).toBe('keep-me');
        promise.then(() => {});
    });

    it('Falsify:默认模型不在 Provider 列表 → 打开即自定义模式并回填默认模型', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = PROVIDERS;
        state.defaultProvider = 'claude';
        state.defaultModel = 'gpt-4o';

        const promise = selector.showModelSelector('角色A');
        const overlay = document.querySelector('.modal-overlay');
        const modelSelect = overlay.querySelector('#ms-model');
        const customInput = overlay.querySelector('#ms-custom-model');
        expect(modelSelect.value).toBe('__custom__');
        expect(customInput.value).toBe('gpt-4o');
        promise.then(() => {});
    });

    it('Falsify:providers 为空列表 → 打开不抛错,取消返回 null', async () => {
        const { selector, state } = await loadSelector();
        state.models.providers = [];

        const promise = selector.showModelSelector('角色A');
        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        overlay.querySelector('.ms-cancel').click();

        await expect(promise).resolves.toBeNull();
    });
});
