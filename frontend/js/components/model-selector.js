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

                // ── 填充模型下拉列表 ──
                const fillModels = () => {
                    const provider = providers.find(p => p.id === providerSelect.value);
                    if (!provider) return;
                    modelSelect.innerHTML = provider.models
                        .map(m => {
                            const selected = m === defaultModelName && providerSelect.value === defaultProviderId ? 'selected' : '';
                            return `<option value="${escapeHtml(m)}" ${selected}>${escapeHtml(m)}</option>`;
                        })
                        .join('');
                };
                fillModels();

                // Provider 切换时更新模型列表
                providerSelect.addEventListener('change', fillModels);

                // 读取当前选择
                const pick = () => close({ provider: providerSelect.value, model: modelSelect.value });
                overlay.querySelector('.ms-cancel').addEventListener('click', () => close(null));
                overlay.querySelector('.ms-start').addEventListener('click', pick);
                overlay.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') pick();
                });
            },
        });
    });
}
