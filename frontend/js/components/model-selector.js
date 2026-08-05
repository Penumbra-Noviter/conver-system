/**
 * Conver System — 模型选择对话框组件
 *
 * 创建对话时选择 Provider 与模型。基于通用模态框工厂 openModal 实现。
 */

import { openModal } from './modal.js';
import { escapeHtml } from '../utils.js';
import { state } from '../state.js';

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
                        ${providers.map(p =>
                            `<option value="${escapeHtml(p.id)}" ${p.id === defaultProviderId ? 'selected' : ''}>${escapeHtml(p.name)}</option>`
                        ).join('')}
                    </select>
                </div>
                <div class="form-field">
                    <label for="ms-model">模型</label>
                    <select id="ms-model"></select>
                    <input type="text" id="ms-custom-model" class="custom-model-input" style="display:none" placeholder="输入模型名称">
                </div>
                <div class="model-selector-info">
                    ⚡ 可在设置中修改默认值
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

                // ── 填充模型下拉列表（含自定义选项） ──
                const fillModels = () => {
                    const provider = providers.find(p => p.id === providerSelect.value);
                    if (!provider) return;
                    const isCustom = modelSelect.value === '__custom__';
                    modelSelect.innerHTML = provider.models
                        .map(m => {
                            const selected = m === defaultModelName && providerSelect.value === defaultProviderId ? 'selected' : '';
                            return `<option value="${escapeHtml(m)}" ${selected}>${escapeHtml(m)}</option>`;
                        })
                        .join('')
                        + '<option value="__custom__">✏️ 自定义模型</option>';

                    // 如果默认模型不在当前 provider 列表中，自动切到自定义
                    const exists = defaultModelName && provider.models.includes(defaultModelName) && providerSelect.value === defaultProviderId;
                    if (exists) {
                        modelSelect.value = defaultModelName;
                        customInput.style.display = 'none';
                    } else if (isCustom || (defaultModelName && !provider.models.includes(defaultModelName) && providerSelect.value === defaultProviderId)) {
                        modelSelect.value = '__custom__';
                        customInput.value = defaultModelName || '';
                        customInput.style.display = '';
                        modelSelect.style.display = 'none';
                        customInput.focus();
                    } else {
                        modelSelect.value = '';
                        customInput.style.display = 'none';
                        modelSelect.style.display = '';
                    }
                };
                fillModels();

                // Provider 切换时更新模型列表
                providerSelect.addEventListener('change', fillModels);

                // 模型下拉切换时联动自定义输入框
                modelSelect.addEventListener('change', function () {
                    if (this.value === '__custom__') {
                        customInput.style.display = '';
                        this.style.display = 'none';
                        customInput.focus();
                    } else {
                        customInput.style.display = 'none';
                        this.style.display = '';
                    }
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
