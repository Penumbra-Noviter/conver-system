/**
 * Conver System — 模型选择工具函数
 *
 * 职责：提供模型下拉填充、自定义模型切换的共享函数，
 *       消除 app.js（settings-panel）与 model-selector.js 之间的重复。
 *
 * 协议表面（__all__）：fillModelSelect / createCustomModelHandler。
 */

import { escapeHtml } from '../utils.js';

/**
 * 填充模型下拉列表并管理自定义输入框的显示/隐藏
 *
 * 通用逻辑：重建选项 → 检查默认模型是否在列表中 → 决定显示下拉或自定义输入框。
 * 同时支持「设置面板」和「模型选择器对话框」两种场景。
 *
 * @param {HTMLSelectElement} selectEl - 模型 <select> 元素
 * @param {{ models: string[] }} provider - 当前 provider 对象（含 models 数组）
 * @param {string|null} defaultModel - 要预选的模型名（可能不在列表中）
 * @param {HTMLInputElement} customInputEl - 自定义模型 <input> 元素
 * @param {object} [options]
 * @param {boolean} [options.forceCustom=false] - 强制进入自定义模式（保留自定义输入值）
 * @param {string} [options.prevCustomVal=''] - 切换 provider 前已有的自定义输入值
 * @param {boolean} [options.focusCustom=false] - 首次填充时自动聚焦自定义输入框
 * @returns {boolean} 操作后是否处于自定义模式
 */
export function fillModelSelect(selectEl, provider, defaultModel, customInputEl, options = {}) {
    const { forceCustom = false, prevCustomVal = '', focusCustom = false } = options;

    // 重建模型下拉选项（含自定义选项）
    selectEl.innerHTML = provider.models
        .map(m => `<option value="${escapeHtml(m)}">${escapeHtml(m)}</option>`)
        .join('')
        + '<option value="__custom__">自定义模型</option>';

    let isCustom = false;

    if (forceCustom || prevCustomVal) {
        // 已处于自定义模式，或自定义输入框有值 → 保持
        isCustom = true;
        selectEl.value = '__custom__';
        customInputEl.style.display = '';
        selectEl.style.display = 'none';
    } else if (defaultModel && !provider.models.includes(defaultModel)) {
        // 默认模型不在当前 provider 列表中 → 切到自定义模式并回填
        isCustom = true;
        selectEl.value = '__custom__';
        customInputEl.value = defaultModel;
        customInputEl.style.display = '';
        selectEl.style.display = 'none';
        if (focusCustom) customInputEl.focus();
    } else if (defaultModel && provider.models.includes(defaultModel)) {
        // 默认模型在列表中 → 预选中
        selectEl.value = defaultModel;
        selectEl.style.display = '';
        customInputEl.style.display = 'none';
    } else {
        // 无默认模型
        selectEl.value = '';
        selectEl.style.display = '';
        customInputEl.style.display = 'none';
    }

    return isCustom;
}

/**
 * 创建「模型下拉切换自定义输入框」的事件处理器
 *
 * 当用户在下拉中选择 "__custom__" 时，隐藏下拉并显示输入框；
 * 选择具体模型时，隐藏输入框。
 *
 * @param {HTMLSelectElement} selectEl - 模型 <select> 元素
 * @param {HTMLInputElement} customInputEl - 自定义模型 <input> 元素
 * @returns {(this: HTMLSelectElement) => void} change 事件处理器
 */
export function createCustomModelHandler(selectEl, customInputEl) {
    return function () {
        if (this.value === '__custom__') {
            customInputEl.style.display = '';
            selectEl.style.display = 'none';
            customInputEl.focus();
        } else {
            customInputEl.style.display = 'none';
        }
    };
}