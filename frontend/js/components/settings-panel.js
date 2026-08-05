/**
 * Conver System — 设置面板组件
 *
 * 职责：
 *   1. 设置表单的加载/回填/保存
 *   2. Provider 下拉与模型下拉的联动
 *   3. 主题切换（持久化到后端）
 *   4. 侧栏展开/收起（布局控制）
 *   5. API Key 连接测试
 *   6. 清空所有对话
 *
 * 协议表面（__all__）：initSettingsPanel / loadSettings / initProviderDropdown。
 * 外部只需调用这三个函数，其余实现细节封装在内。
 */

import { state } from '../state.js';
import { settings, conversations } from '../api.js';
import { showAlert, showConfirm } from './confirm-dialog.js';
import { escapeHtml } from '../utils.js';
import { fillModelSelect, createCustomModelHandler } from '../utils/model-utils.js';

const $ = (sel) => document.querySelector(sel);

// ══════════════════════════════════════════════════
// Provider 下拉 & 模型选择
// ══════════════════════════════════════════════════

/**
 * 初始化 Provider 下拉列表（仅重建选项，不操作模型列表）
 * 在 settings 视图切换时调用
 */
export function initProviderDropdown() {
    const providerSelect = $('#setting-default-provider');
    const providers = state.models.providers || [];

    providerSelect.innerHTML = providers
        .map(p => `<option value="${escapeHtml(p.key)}">${escapeHtml(p.name)}</option>`)
        .join('');

    // 恢复已保存的 provider：按 key 精确匹配（优先）→ 按 name 兜底
    let matched = false;
    if (state.defaultProvider) {
        const byKey = providerSelect.querySelector(`option[value="${state.defaultProvider}"]`);
        if (byKey) { byKey.selected = true; matched = true; }
    }
    if (!matched && state.defaultProviderName) {
        for (const opt of providerSelect.options) {
            const p = providers.find(pr => pr.key === opt.value);
            if (p && p.name === state.defaultProviderName) {
                opt.selected = true;
                break;
            }
        }
    }

    refreshModelOptions();
}

/**
 * 刷新设置面板中的模型下拉选项
 * 在 settings 视图切换或 provider 变更时调用
 * 注意：不复位 Provider 下拉，只更新模型列表
 */
function refreshModelOptions() {
    const providerSelect = $('#setting-default-provider');
    const modelSelect = $('#setting-default-model');
    const customInput = $('#setting-custom-model');

    const providers = state.models.providers || [];
    const selectedKey = providerSelect.value;
    const provider = providers.find(p => p.key === selectedKey);
    if (!provider) return;

    fillModelSelect(modelSelect, provider, state.defaultModel, customInput);
}

/**
 * 获取当前选中的模型名称（下拉或自定义输入）
 * @returns {string}
 */
function getSelectedModel() {
    const modelSelect = $('#setting-default-model');
    const customInput = $('#setting-custom-model');
    if (modelSelect.value === '__custom__') {
        return customInput.value.trim();
    }
    return modelSelect.value;
}

// ══════════════════════════════════════════════════
// 主题
// ══════════════════════════════════════════════════

/**
 * 应用主题模式到 DOM
 * @param {string} mode - 'auto' | 'light' | 'dark'
 */
function applyTheme(mode) {
    const root = document.documentElement;
    if (mode === 'auto' || !mode) {
        root.removeAttribute('data-theme');
    } else {
        root.dataset.theme = mode;
    }
}

/**
 * 切换主题（深色 ⇄ 浅色循环）
 * 从当前主题切换到另一种，并持久化到后端
 */
async function toggleTheme() {
    const root = document.documentElement;
    const current = root.getAttribute('data-theme') || 'dark';
    const next = current === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    try {
        await settings.update({ theme_mode: next });
    } catch (err) {
        console.error('保存主题设置失败:', err);
    }
    // 更新主题按钮图标
    updateThemeToggleIcon(next);
    // 同步设置页面下拉框
    $('#setting-theme').value = next;
}

/**
 * 更新主题切换按钮的图标
 * @param {string} mode - 'light' | 'dark' | 'auto'
 */
function updateThemeToggleIcon(mode) {
    const btn = $('#btn-theme-toggle');
    if (!btn) return;
    if (mode === 'light') {
        btn.textContent = '☀️';
        btn.title = '切换深色模式';
    } else {
        btn.textContent = '🌙';
        btn.title = '切换浅色模式';
    }
}

// ══════════════════════════════════════════════════
// 侧栏展开/收起
// ══════════════════════════════════════════════════

/**
 * 切换左侧导航栏的展开/收起
 */
function toggleSidebar() {
    state.sidebarCollapsed = !state.sidebarCollapsed;
    const sidebar = $('#sidebar');
    const btn = $('#btn-collapse-sidebar');
    const expandBtn = $('#btn-expand-sidebar');
    if (state.sidebarCollapsed) {
        sidebar.classList.add('sidebar-collapsed');
        btn.textContent = '▶';
        btn.title = '展开侧栏';
        expandBtn.style.display = 'flex';
    } else {
        sidebar.classList.remove('sidebar-collapsed');
        btn.textContent = '◀';
        btn.title = '收起侧栏';
        expandBtn.style.display = 'none';
    }
}

/**
 * 切换对话列表栏的展开/收起
 */
function toggleChatSidebar() {
    state.chatSidebarCollapsed = !state.chatSidebarCollapsed;
    const sidebar = document.querySelector('.chat-sidebar');
    const btn = $('#btn-collapse-chat');
    const expandBtn = $('#btn-expand-chat');
    if (state.chatSidebarCollapsed) {
        sidebar.classList.add('chat-sidebar-collapsed');
        btn.textContent = '▶';
        btn.title = '展开侧栏';
        expandBtn.style.display = 'flex';
    } else {
        sidebar.classList.remove('chat-sidebar-collapsed');
        btn.textContent = '◀';
        btn.title = '收起侧栏';
        expandBtn.style.display = 'none';
    }
}

// ══════════════════════════════════════════════════
// 设置加载 & 保存
// ══════════════════════════════════════════════════

/**
 * 从后端加载设置并回填表单
 */
export async function loadSettings() {
    try {
        const s = await settings.get();
        if (s.claude_api_key) $('#setting-claude-key').value = s.claude_api_key;
        if (s.claude_base_url) $('#setting-claude-url').value = s.claude_base_url;
        if (s.openai_api_key) $('#setting-openai-key').value = s.openai_api_key;
        if (s.openai_base_url) $('#setting-openai-url').value = s.openai_base_url;
        if (s.default_provider) {
            state.defaultProvider = s.default_provider;
        }
        if (s.default_provider_name) {
            state.defaultProviderName = s.default_provider_name;
        }
        if (s.default_model) {
            $('#setting-default-model').value = s.default_model;
            state.defaultModel = s.default_model;
        }
        if (s.sliding_window_rounds) $('#setting-sliding-window').value = s.sliding_window_rounds;
        if (s.theme_mode) {
            $('#setting-theme').value = s.theme_mode;
            applyTheme(s.theme_mode);
            updateThemeToggleIcon(s.theme_mode || 'dark');
        }
        if (s.user_name) $('#setting-user-name').value = s.user_name;
    } catch (err) {
        console.error('加载设置失败:', err);
    }
}

/**
 * 保存设置前测试「默认 Provider + 默认模型」连接（P4.3）
 *
 * 测试目标 = 用户实际对话将使用的配置（默认 Provider 的 key/url/模型），
 * 而非逐个协议测试 —— 通用凭证解析下，用户填任一字段的 key/url 即可全局使用，
 * 因此测默认配置一个就足够且最准确。
 *
 * Key/URL 取值：表单中同协议字段优先，跨协议兜底（与后端 _slot_value 一致）。
 * @param {object} data - 设置表单数据
 * @returns {Promise<boolean>} true=可继续保存；false=用户选择取消保存
 */
async function testApiKeys(data) {
    const provider = (state.models.providers || []).find(p => p.key === state.defaultProvider);
    if (!provider) return true;

    // 按 provider 协议选表单字段（同协议优先 → 跨协议兜底）
    const proto = provider.id; // 'claude' | 'openai'
    const other = proto === 'claude' ? 'openai' : 'claude';
    const apiKey = data[`${proto}_api_key`] || data[`${other}_api_key`];
    const baseUrl = data[`${proto}_base_url`] || data[`${other}_base_url`];

    // 未填任何 Key → 跳过测试直接保存（Key 可在后续补）
    if (!apiKey) return true;

    // 用当前默认模型测试（用户配置的模型名，而非硬编码默认）
    const model = getSelectedModel() || null;

    try {
        await settings.testConnection({ provider: provider.key, api_key: apiKey, base_url: baseUrl || null, model });
        return true;
    } catch (err) {
        const confirmed = await showConfirm({
            title: 'API Key 连接测试未通过',
            message: `${provider.name} 连接测试失败`,
            detail: `${err.message}\n\n仍然保存吗？（若 Key 或模型名无误，可继续保存）`,
            confirmText: '仍然保存',
            cancelText: '取消',
        });
        return confirmed;
    }
}

// ══════════════════════════════════════════════════
// 初始化 — 绑定所有事件
// ══════════════════════════════════════════════════

/**
 * 初始化设置面板：绑定所有事件监听器
 *
 * @param {object} [options]
 * @param {function} [options.onConversationsCleared] - 清空所有对话后的回调（刷新列表等）
 */
export function initSettingsPanel({ onConversationsCleared } = {}) {
    // Provider 切换时动态更新模型列表
    $('#setting-default-provider').addEventListener('change', refreshModelOptions);

    // 模型下拉切换时联动自定义输入框
    $('#setting-default-model').addEventListener('change', createCustomModelHandler(
        $('#setting-default-model'), $('#setting-custom-model'),
    ));

    // 主题切换按钮（全局 header）
    $('#btn-theme-toggle')?.addEventListener('click', toggleTheme);

    // 侧栏收起按钮
    $('#btn-collapse-sidebar')?.addEventListener('click', toggleSidebar);
    $('#btn-collapse-chat')?.addEventListener('click', toggleChatSidebar);

    // 侧栏展开按钮（收起时浮动显示）
    $('#btn-expand-sidebar')?.addEventListener('click', toggleSidebar);
    $('#btn-expand-chat')?.addEventListener('click', toggleChatSidebar);

    // ── 保存设置 ──
    $('#btn-save-settings').addEventListener('click', async () => {
        const data = {
            claude_api_key: $('#setting-claude-key').value,
            claude_base_url: $('#setting-claude-url').value,
            openai_api_key: $('#setting-openai-key').value,
            openai_base_url: $('#setting-openai-url').value,
            default_provider: $('#setting-default-provider').value,
            default_provider_name: $('#setting-default-provider option:checked').textContent.trim(),
            default_model: getSelectedModel(),
            sliding_window_rounds: $('#setting-sliding-window').value,
            theme_mode: $('#setting-theme').value,
            user_name: $('#setting-user-name').value,
        };

        // P4.3：保存前测试已填写的 API Key 连接，失败由用户确认是否继续
        const canSave = await testApiKeys(data);
        if (!canSave) return;

        try {
            const result = await settings.update(data);
            // 更新本地状态
            state.defaultProvider = result.default_provider || data.default_provider;
            state.defaultProviderName = result.default_provider_name || data.default_provider_name || state.defaultProviderName;
            state.defaultModel = result.default_model || data.default_model;
            // 应用主题
            applyTheme(data.theme_mode || 'auto');
            updateThemeToggleIcon(data.theme_mode || 'dark');
            showAlert('设置已保存');
        } catch (err) {
            showAlert('保存失败: ' + err.message);
        }
    });

    // ── 清空所有对话 ──
    $('#btn-clear-all-convs').addEventListener('click', async () => {
        const convCount = state.conversations.length;
        if (convCount === 0) {
            showAlert('当前没有对话需要清空');
            return;
        }

        const confirmed = await showConfirm({
            title: '清空所有对话',
            message: `确定要清空全部 ${convCount} 个对话吗？`,
            detail: '此操作将删除所有对话和消息记录，不可撤销。',
            confirmText: '清空所有',
            cancelText: '取消',
            danger: true,
        });

        if (confirmed) {
            try {
                await conversations.deleteAll();
                state.conversations = [];
                state.currentConversationId = null;
                state.currentCharacterId = null;
                state.messages = [];
                if (onConversationsCleared) onConversationsCleared();
                showAlert(`已清空 ${convCount} 个对话`);
            } catch (err) {
                showAlert('清空失败: ' + err.message);
            }
        }
    });
}