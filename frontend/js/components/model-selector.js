/**
 * Conver System — 模型选择对话框组件
 *
 * 创建对话时选择 Provider 与模型。基于通用模态框工厂 openModal 实现。
 */

import { openModal } from './modal.js';
import { escapeHtml } from '../utils.js';
import { state } from '../state.js';
import { fillModelSelect, createCustomModelHandler } from '../utils/model-utils.js';

/**
 * 显示模型选择对话框 — 创建对话时让用户选择 Provider 和模型
 * @param {string} characterName - 角色名称（用于展示）
 * @returns {Promise<{provider: string, model: string}|null>} 选择的配置，取消返回 null
 */
export function showModelSelector(characterName) {
    return new Promise((resolve) => {
        const providers = state.models.providers || [];
        const defaultProviderId = state.defaultProvider;
        const defaultModelName = state.defaultModel;

        openModal({
            title: `开始对话 · ${characterName}`,
            modalClass: 'model-selector-modal',
            removeExisting: '.modal-overlay',
            focusSelector: '.ms-start',
            cancelResult: null,
            onClose: resolve,
            body: `
                <p class="model-selector-hint">选择要使用的模型进行对话</p>
                <div class="form-field">
                    <label for="ms-provider">Provider</label>
                    <select id="ms-provider">
                        ${providers.map((p) =>
                            `<option value="${escapeHtml(p.key)}" ${p.key === defaultProviderId ? 'selected' : ''}>${escapeHtml(p.name)}</option>`
                        ).join('')}
                    </select>
                </div>
                <div class="form-field">
                    <label for="ms-model">模型</label>
                    <select id="ms-model"></select>
                    <input type="text" id="ms-custom-model" class="custom-model-input" style="display:none" placeholder="输入模型名称">
                </div>
                <div class="model-selector-info">
                    可在设置中修改默认值
                </div>
            `,
            actions: `
                <button class="btn-secondary ms-cancel">取消</button>
                <button class="btn-primary ms-start">开始对话</button>
            `,
            onOpen: (overlay, close) => {
                const providerSelect = overlay.querySelector('#ms-provider');
                const modelSelect = overlay.querySelector('#ms-model');
                const customInput = overlay.querySelector('#ms-custom-model');

                // 标记用户是否已切换到自定义模式（选中自定义 或 已有自定义输入值）
                let isCustomMode = false;

                // ── 填充模型下拉列表（含自定义选项） ──
                const fillModels = (initial) => {
                    // 用 key 精确查找当前选中的 provider
                    const selectedKey = providerSelect.value;
                    const provider = providers.find(p => p.key === selectedKey);
                    if (!provider) return;

                    // 保存当前自定义输入值，切换 provider 时保留
                    const prevCustomVal = customInput.value.trim();

                    isCustomMode = fillModelSelect(modelSelect, provider, defaultModelName, customInput, {
                        forceCustom: isCustomMode,
                        prevCustomVal,
                        focusCustom: initial,
                    });
                };
                fillModels(true);

                // Provider 切换时更新模型列表（保留自定义状态）
                providerSelect.addEventListener('change', () => fillModels(false));

                // 模型下拉切换时联动自定义输入框
                const modelChangeHandler = createCustomModelHandler(modelSelect, customInput);
                modelSelect.addEventListener('change', function () {
                    modelChangeHandler.call(this);
                    isCustomMode = this.value === '__custom__';
                });

                // 读取当前选择
                const pick = () => {
                    const model = modelSelect.value === '__custom__'
                        ? customInput.value.trim()
                        : modelSelect.value;
                    close({ provider: providerSelect.value, model });
                };
                overlay.querySelector('.ms-cancel').addEventListener('click', () => close(null));
                overlay.querySelector('.ms-start').addEventListener('click', pick);
                overlay.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') pick();
                });
            },
        });
    });
}

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'showModelSelector',
];
