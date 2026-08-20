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
 * 协议表面（__all__）：initSettingsPanel / loadSettings / initProviderDropdown /
 * resolveCredentialTarget（纯函数，供测试与复用，语义对齐后端 setting.py::_slot_value）。
 * 外部只需调用这几个函数，其余实现细节封装在内。
 */

import { state } from '../state.js';
import { settings, conversations } from '../api.js';
import { showAlert, showConfirm } from './confirm-dialog.js';
import { escapeHtml } from '../utils.js';
import { beginButtonLoading } from './loading-button.js';
import { fillModelSelect, createCustomModelHandler } from '../utils/model-utils.js';
import { iconHtml } from '../icons.js';

const $ = (sel) => document.querySelector(sel);

// ══════════════════════════════════════════════════
// Provider 下拉 & 模型选择
// ══════════════════════════════════════════════════

/**
 * 初始化 Provider 下拉列表（仅重建选项，不操作模型列表）
 * 在 settings 视图切换时调用
 * DOM 元素缺失（index.html 契约被破坏的极端场景）→ no-op 不抛错。
 */
export function initProviderDropdown() {
    const providerSelect = $('#setting-default-provider');
    if (!providerSelect) return;
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
    // 三元素任一缺失（index.html 契约被破坏的极端场景）→ no-op 早退，不抛 TypeError
    if (!providerSelect || !modelSelect || !customInput) return;

    const providers = state.models.providers || [];
    const selectedKey = providerSelect.value;
    const provider = providers.find(p => p.key === selectedKey);
    if (!provider) return;

    fillModelSelect(modelSelect, provider, state.defaultModel, customInput);
}

/**
 * 获取当前选中的模型名称（下拉或自定义输入）
 * 契约注记（TD-21）：调用方须经 save 回调入口守卫（TD-13 / TD-15）——本函数裸读
 * #setting-default-model / #setting-custom-model 两元素，守卫外调用可能抛 TypeError
 * （__custom__ 分支读 customInput.value 前无存在性检查）。
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
    const btn = $('#btn-theme-toggle');
    if (btn) btn.disabled = true;
    try {
        await settings.update({ theme_mode: next });
    } catch (err) {
        console.error('保存主题设置失败:', err);
    } finally {
        if (btn) btn.disabled = false;
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
        btn.innerHTML = iconHtml('sun');
        btn.title = '切换深色模式';
    } else {
        btn.innerHTML = iconHtml('moon');
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
        btn.innerHTML = iconHtml('chevronRight');
        btn.title = '展开侧栏';
        expandBtn.style.display = 'flex';
    } else {
        sidebar.classList.remove('sidebar-collapsed');
        btn.innerHTML = iconHtml('chevronLeft');
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
        btn.innerHTML = iconHtml('chevronRight');
        btn.title = '展开侧栏';
        expandBtn.style.display = 'flex';
    } else {
        sidebar.classList.remove('chat-sidebar-collapsed');
        btn.innerHTML = iconHtml('chevronLeft');
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
 * 解析设置表单中的凭证目标（纯函数，无 DOM/state 依赖）
 *
 * 语义与后端 backend/app/services/setting.py::_slot_value 一致：
 * 同协议槽位优先 → 跨协议兜底 —— 用户把 Key/URL 填在 claude 或 openai
 * 任一槽位，任意模型均可解析到可用凭证（全局使用）。
 *
 * 注意：新增协议槽位必须同步两处 —— 本函数与 setting.py::_CRED_SLOTS。
 *
 * @param {object} formFields - 设置表单数据
 * @param {object} formFields.provider - 默认 provider 对象（含 key / id）
 * @param {string} formFields.provider.key - provider key（如 'deepseek'）
 * @param {string} formFields.provider.id - 协议标识（'claude' | 'openai'）
 * @param {string} [formFields.claude_api_key] [formFields.claude_base_url]
 * @param {string} [formFields.openai_api_key] [formFields.openai_base_url]
 * @returns {{providerKey: string, key: string, baseUrl: string}}
 *   providerKey=默认 provider key（连接测试目标）；key/baseUrl=解析出的凭证，未填为空串
 */
export function resolveCredentialTarget(formFields) {
    const proto = formFields.provider.id; // 'claude' | 'openai'
    const other = proto === 'claude' ? 'openai' : 'claude';
    return {
        providerKey: formFields.provider.key,
        key: formFields[`${proto}_api_key`] || formFields[`${other}_api_key`] || '',
        baseUrl: formFields[`${proto}_base_url`] || formFields[`${other}_base_url`] || '',
    };
}

/**
 * 保存设置前测试「默认 Provider + 默认模型」连接（P4.3）
 *
 * 测试目标 = 用户实际对话将使用的配置（默认 Provider 的 key/url/模型），
 * 而非逐个协议测试 —— 通用凭证解析下，用户填任一字段的 key/url 即可全局使用，
 * 因此测默认配置一个就足够且最准确。
 *
 * Key/URL 取值：委托 resolveCredentialTarget（同协议优先 → 跨协议兜底，与后端 _slot_value 一致）。
 * @param {object} data - 设置表单数据
 * @returns {Promise<boolean>} true=可继续保存；false=用户选择取消保存
 */
async function testApiKeys(data) {
    const provider = (state.models.providers || []).find(p => p.key === state.defaultProvider);
    if (!provider) return true;

    // 通用凭证解析：同协议槽位优先 → 跨协议兜底（与后端 _slot_value 一致）
    const { providerKey, key, baseUrl } = resolveCredentialTarget({ ...data, provider });

    // 未填任何 Key → 跳过测试直接保存（Key 可在后续补）
    if (!key) return true;

    // 用当前默认模型测试（用户配置的模型名，而非硬编码默认）
    const model = getSelectedModel() || null;

    try {
        await settings.testConnection({ provider: providerKey, api_key: key, base_url: baseUrl || null, model });
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
 * Provider/模型下拉、自定义输入元素或 save/clear 按钮缺失（index.html 契约被破坏的极端场景）→ 对应绑定 no-op 不抛错。
 * save 回调另有入口统一守卫（TD-13 / TD-15）：守卫收集 10 个表单元素变量
 * （9 个表单字段 + #setting-custom-model，后者条件化——仅自定义模型模式
 * （modelSelect.value === '__custom__'）要求，与 getSelectedModel 裸读分支对齐；
 * 非自定义模式该元素缺失不早退）任一缺失 → console.warn + 早退 no-op
 * （不执行保存、不发 fetch、不抛 TypeError）；第 11 次 DOM 读取
 * （default_provider_name 的 option:checked）由 `?.` 收口，不参与缺失收集。
 *
 * @param {object} [options]
 * @param {function} [options.onConversationsCleared] - 清空所有对话后的回调（刷新列表等）
 */
export function initSettingsPanel({ onConversationsCleared } = {}) {
    // Provider 切换时动态更新模型列表
    $('#setting-default-provider')?.addEventListener('change', refreshModelOptions);

    // 模型下拉切换时联动自定义输入框（缺一不绑定：两元素任一缺失 → 该绑定 no-op 不抛错）
    const modelSelect = $('#setting-default-model');
    const customInput = $('#setting-custom-model');
    if (modelSelect && customInput) {
        modelSelect.addEventListener('change', createCustomModelHandler(modelSelect, customInput));
    }

    // 主题切换按钮（全局 header）
    $('#btn-theme-toggle')?.addEventListener('click', toggleTheme);

    // 侧栏收起按钮
    $('#btn-collapse-sidebar')?.addEventListener('click', toggleSidebar);
    $('#btn-collapse-chat')?.addEventListener('click', toggleChatSidebar);

    // 侧栏展开按钮（收起时浮动显示）
    $('#btn-expand-sidebar')?.addEventListener('click', toggleSidebar);
    $('#btn-expand-chat')?.addEventListener('click', toggleChatSidebar);

    // ── 保存设置（按钮缺失 → 绑定 no-op 不抛错）──
    $('#btn-save-settings')?.addEventListener('click', async () => {
        // ── 入口统一守卫（TD-13 / TD-15）：10 个元素变量任一缺失 → console.warn + 早退 no-op ──
        // 9 个表单字段读取 + #setting-custom-model（条件化：仅 modelSelect.value === '__custom__'
        // 时收集，与 getSelectedModel 裸读分支对齐——非自定义模式该元素缺失不早退）。
        // 第 11 次 DOM 读取（default_provider_name 的 option:checked）由 `?.` 收口为空串，
        // 不参与缺失收集。守卫在数据收集前拦截：不执行保存、不发 fetch、无 rejection、无 TypeError。
        const claudeKeyInput = $('#setting-claude-key');
        const claudeUrlInput = $('#setting-claude-url');
        const openaiKeyInput = $('#setting-openai-key');
        const openaiUrlInput = $('#setting-openai-url');
        const providerSelect = $('#setting-default-provider');
        const slidingWindowInput = $('#setting-sliding-window');
        const themeSelect = $('#setting-theme');
        const userNameInput = $('#setting-user-name');
        const modelSelect = $('#setting-default-model');
        const customModelInput = $('#setting-custom-model');
        const missing = [
            ['#setting-claude-key', claudeKeyInput],
            ['#setting-claude-url', claudeUrlInput],
            ['#setting-openai-key', openaiKeyInput],
            ['#setting-openai-url', openaiUrlInput],
            ['#setting-default-provider', providerSelect],
            ['#setting-sliding-window', slidingWindowInput],
            ['#setting-theme', themeSelect],
            ['#setting-user-name', userNameInput],
            ['#setting-default-model', modelSelect],
        ];
        // TD-15：custom-model 缺失检查条件化——仅在自定义模型模式要求（与 getSelectedModel
        // 裸读分支 modelSelect.value === '__custom__' 精确对齐）；modelSelect 自身缺失
        // 已在数组内照常收集早退，此处不兜底。
        if (modelSelect && modelSelect.value === '__custom__') {
            missing.push(['#setting-custom-model', customModelInput]);
        }
        const missingSels = missing.filter(([, el]) => !el).map(([sel]) => sel);
        if (missingSels.length > 0) {
            console.warn('设置面板元素缺失，跳过保存:', missingSels.join(', '));
            return;
        }

        const data = {
            claude_api_key: claudeKeyInput.value,
            claude_base_url: claudeUrlInput.value,
            openai_api_key: openaiKeyInput.value,
            openai_base_url: openaiUrlInput.value,
            default_provider: providerSelect.value,
            default_provider_name: providerSelect.querySelector('option:checked')?.textContent.trim() ?? '',
            default_model: getSelectedModel(),
            sliding_window_rounds: slidingWindowInput.value,
            theme_mode: themeSelect.value,
            user_name: userNameInput.value,
        };

        const btn = $('#btn-save-settings');
        const restore = beginButtonLoading(btn, '保存中…');
        try {
            // P4.3：保存前测试已填写的 API Key 连接，失败由用户确认是否继续
            const canSave = await testApiKeys(data);
            if (!canSave) return; // finally 恢复按钮

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
        } finally {
            restore();
        }
    });

    // ── 清空所有对话（按钮缺失 → 绑定 no-op 不抛错）──
    $('#btn-clear-all-convs')?.addEventListener('click', async () => {
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
            const btn = $('#btn-clear-all-convs');
            const restore = beginButtonLoading(btn, '清空中…');
            try {
                await conversations.deleteAll();
                state.conversations = [];
                // 会话级字段（currentConversationId/messages 等）P6.5 已退役 —
                // tab 清理由 app.js 的 onConversationsCleared 回调完成（closeAllTabs + 空态）
                if (onConversationsCleared) onConversationsCleared();
                showAlert(`已清空 ${convCount} 个对话`);
            } catch (err) {
                showAlert('清空失败: ' + err.message);
            } finally {
                restore();
            }
        }
    });
}
export const __all__ = ['initSettingsPanel', 'loadSettings', 'initProviderDropdown', 'resolveCredentialTarget'];
