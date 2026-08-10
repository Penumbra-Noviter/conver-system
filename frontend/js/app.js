/**
 * Conver System — 主入口（协调层）
 *
 * 职责：
 *   1. 视图切换（侧栏导航）
 *   2. 业务协调（角色 / 对话 / 搜索）
 *   3. 事件绑定
 *
 * 模块结构：
 *   - ./state.js — 全局状态
 *   - ./chat.js  — 聊天域渲染与交互（renderMessages / handleSend / chatDom）
 *   - ./format.js — 渲染/格式化纯函数（highlightText / buildMessagesHtml）
 *   - ./components/settings-panel.js — 设置面板（Provider 下拉、主题、侧栏、保存、清空）
 *   - ./components/ — 模态框相关组件（modal 工厂 / confirm / model-selector / export / character-form）
 */

import { characters, conversations, messages, models } from './api.js';
import { showCharacterForm } from './components/character-form.js';
import { showCharacterWizard } from './components/character-wizard.js';
import { showConfirm, showAlert } from './components/confirm-dialog.js';
import { showModelSelector } from './components/model-selector.js';
import { showExportDialog } from './components/export-dialog.js';
import { initSettingsPanel, loadSettings, initProviderDropdown } from './components/settings-panel.js';
import { initTabBar } from './components/tab-bar.js';
import { escapeHtml, getInitials, formatTags, showToast, downloadBlob, providerDisplayName } from './utils.js';
import { highlightText } from './format.js';
import { state } from './state.js';
import { chatDom, renderMessages, handleSend, refreshSendButton, setConversationsRefresher, EMPTY_STATE_HTML } from './chat.js';
import { openTab, closeTabs, getActiveTab, getTab, getTabs, updateTab, abortStream, restoreFromStorage } from './tabs.js';

// ══════════════════════════════════════════════════
// DOM 引用
// ══════════════════════════════════════════════════

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

// 模块级状态（UI 实现细节，不属于全局应用状态）
let searchTimeout = null;

const dom = {
    // 视图
    views: $$('.view'),
    navBtns: $$('.nav-btn'),

    // 聊天（聊天域 DOM 引用见 chat.js chatDom）
    conversationList: $('#conversation-list'),
    btnNewChat: $('#btn-new-chat'),
    // 移动端
    mobileNavBtns: $$('.mobile-nav-btn'),
    convListToggle: null, // 将在初始化时创建

    // 角色
    characterGrid: $('#character-grid'),
    btnCreateCharacter: $('#btn-create-character'),
    btnImportCharacter: $('#btn-import-character'),
    characterImportInput: $('#character-import-input'),

    // 搜索
    searchInput: $('#search-input'),
    searchResults: $('#search-results'),
    btnSearchClear: $('#btn-search-clear'),
};

// ══════════════════════════════════════════════════
// 视图切换
// ══════════════════════════════════════════════════

async function switchView(viewName) {
    state.currentView = viewName;

    dom.views.forEach((v) => v.classList.remove('active'));
    dom.navBtns.forEach((b) => b.classList.remove('active'));
    dom.mobileNavBtns.forEach((b) => b.classList.remove('active'));

    const view = $(`#view-${viewName}`);
    const btn = $(`.nav-btn[data-view="${viewName}"]`);
    const mobileBtn = $(`.mobile-nav-btn[data-view="${viewName}"]`);
    if (view) view.classList.add('active');
    if (btn) btn.classList.add('active');
    if (mobileBtn) mobileBtn.classList.add('active');

    // 进入视图时刷新数据
    if (viewName === 'characters') loadCharacters();
    if (viewName === 'chat') loadConversations();
    if (viewName === 'settings') {
        await loadSettings();
        initProviderDropdown();
    }
    if (viewName === 'search') {
        setTimeout(() => dom.searchInput?.focus(), 100);
    }
}

dom.navBtns.forEach((btn) => {
    btn.addEventListener('click', () => switchView(btn.dataset.view));
});

// 移动端导航事件
dom.mobileNavBtns.forEach((btn) => {
    btn.addEventListener('click', () => switchView(btn.dataset.view));
});

// 切换对话列表显示（移动端）
function toggleConvList() {
    const sidebar = document.querySelector('.chat-sidebar');
    if (!sidebar) return;
    sidebar.classList.toggle('mobile-expanded');
}

// ══════════════════════════════════════════════════
// Toast 通知
// ══════════════════════════════════════════════════

function showError(message) {
    showToast(message, 'error');
}

function showSuccess(message) {
    showToast(message, 'success');
}

// ══════════════════════════════════════════════════
// 角色管理
// ══════════════════════════════════════════════════

async function loadCharacters() {
    try {
        state.characters = await characters.list();
        renderCharacters();
    } catch (err) {
        console.error('加载角色失败:', err);
        showError('加载角色列表失败');
    }
}

async function renderCharacters() {
    const grid = dom.characterGrid;
    if (state.characters.length === 0) {
        grid.innerHTML = '<p class="empty-hint">暂无角色，点击上方按钮创建</p>';
        return;
    }

    grid.innerHTML = state.characters
        .map(
            (c) => `
        <div class="character-card" data-id="${c.id}">
            <div class="character-card-header">
                <div class="character-avatar">
                    ${c.avatar
                        ? `<img src="${escapeHtml(c.avatar)}" alt="${escapeHtml(c.name)}" onerror="this.parentElement.innerHTML='<div class=\\'avatar-placeholder-sm\\'>${escapeHtml(getInitials(c.name))}</div>'">`
                        : `<div class="avatar-placeholder-sm">${escapeHtml(getInitials(c.name))}</div>`
                    }
                </div>
                <div class="character-card-info">
                    <div class="name">${escapeHtml(c.name)}</div>
                    <div class="subtitle">${escapeHtml(c.description || c.personality?.slice(0, 60) || '未设定')}</div>
                </div>
            </div>
            <div class="character-card-details">
                ${c.first_mes ? `<div class="detail-item"><span class="detail-label">开场白:</span> ${escapeHtml(c.first_mes.slice(0, 60))}${c.first_mes.length > 60 ? '…' : ''}</div>` : ''}
                ${c.tags && c.tags.length ? `<div class="detail-item"><span class="detail-label">标签:</span> ${escapeHtml(formatTags(c.tags))}</div>` : ''}
            </div>
            <div class="character-card-meta">
                <span class="meta-badge">🌡️ ${c.temperature?.toFixed(1) ?? '0.7'}</span>
                <span class="meta-badge">💬 ${c.conversation_count ?? 0}</span>
            </div>
            <div class="character-card-actions">
                <button class="btn-icon chat-with" title="开始对话">
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path d="M3 4.5A1.5 1.5 0 014.5 3h7A1.5 1.5 0 0113 4.5v4A1.5 1.5 0 0111.5 10H8l-3 2v-2H4.5A1.5 1.5 0 013 8.5v-4z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
                        <path d="M6 6.5h4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
                    </svg>
                </button>
                <button class="btn-icon edit-char" title="编辑">
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path d="M11.4 2.6a1.7 1.7 0 012.4 2.4L7.5 11.3 4 12l.7-3.5 6.7-5.9z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
                    </svg>
                </button>
                <button class="btn-icon export-char" title="导出角色卡">
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path d="M13.5 10v3.5a1 1 0 01-1 1h-9a1 1 0 01-1-1V10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M8 9.5V2.5M5.5 5L8 2.5 10.5 5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                    </svg>
                </button>
                <button class="btn-icon delete-char" title="删除">
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path d="M2.5 4.5h11" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
                        <path d="M12.7 4.5v9.3a1.3 1.3 0 01-1.3 1.3H4.6a1.3 1.3 0 01-1.3-1.3V4.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M6.6 4.5V3.4a.9.9 0 01.9-.9h1a.9.9 0 01.9.9v1.1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M6.6 7.5v4M9.4 7.5v4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
                    </svg>
                </button>
            </div>
        </div>
    `
        )
        .join('');

    // 事件委托：开始对话
    grid.querySelectorAll('.chat-with').forEach((btn) => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            const id = parseInt(btn.closest('.character-card').dataset.id);
            startChatWithCharacter(id);
        });
    });

    // 事件委托：编辑
    grid.querySelectorAll('.edit-char').forEach((btn) => {
        btn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const id = parseInt(btn.closest('.character-card').dataset.id);
            try {
                const char = await characters.get(id);
                showCharacterForm('edit', char, () => loadCharacters());
            } catch (err) {
                console.error('加载角色详情失败:', err);
                showAlert('加载角色信息失败: ' + err.message);
            }
        });
    });

    // 事件委托：导出角色卡（P2.5.5）
    grid.querySelectorAll('.export-char').forEach((btn) => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            const id = parseInt(btn.closest('.character-card').dataset.id);
            const char = state.characters.find((c) => c.id === id);
            downloadBlob(`/api/characters/${id}/export`, `${char?.name || 'character'}.json`);
        });
    });

    // 事件委托：删除
    grid.querySelectorAll('.delete-char').forEach((btn) => {
        btn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const id = parseInt(btn.closest('.character-card').dataset.id);
            const char = state.characters.find(c => c.id === id);
            const convCount = char?.conversation_count ?? 0;

            const confirmed = await showConfirm({
                title: '删除角色',
                message: `确定要删除角色「${char?.name || '未知'}」吗？`,
                detail: convCount > 0
                    ? `该角色关联了 ${convCount} 个对话，删除后所有相关对话和消息也将被删除。`
                    : '此操作不可撤销。',
                confirmText: '删除',
                cancelText: '取消',
                danger: true,
            });

            if (confirmed) {
                try {
                    await characters.delete(id);
                    await loadCharacters();
                    // 联动：角色删除级联删除其全部对话 — 统一收口关闭对应会话 tab
                    //（closeTabs 内部先 abort 在途流式；仅被删会话含活动 tab 才重定位视图）
                    const doomed = getTabs()
                        .filter((t) => t.characterId === id)
                        .map((t) => t.conversationId);
                    await closeConversationsAndResettle({ ids: doomed, reloadList: true });
                } catch (err) {
                    showAlert('删除失败: ' + err.message);
                }
            }
        });
    });
}

dom.btnCreateCharacter.addEventListener('click', () => {
    showCharacterWizard(() => loadCharacters());
});

// ══════════════════════════════════════════════════
// 角色导入（P2.5.4）
// ══════════════════════════════════════════════════

/**
 * 导入失败后的引导：询问是否改用「创建角色」向导
 * （向导支持智能导入/内置模板/手动创建，比调试角色卡 JSON 更省力）
 */
async function promptUseWizardAfterImportFail() {
    const useWizard = await showConfirm({
        title: '导入失败',
        message: '是否改用「创建角色」向导？',
        detail: '向导支持智能导入（粘贴文档，AI 自动提取）、内置模板或手动创建。',
        confirmText: '打开向导',
        cancelText: '取消',
    });
    if (useWizard) showCharacterWizard();
}

/**
 * 处理导入角色文件：读取 → JSON.parse → POST /api/characters/import
 * JSON.parse 失败 → 前端直接提示，不发请求。
 */
async function handleCharacterImport() {
    const file = dom.characterImportInput.files?.[0];
    if (!file) return;

    let card;
    try {
        const text = await file.text();
        card = JSON.parse(text);
    } catch {
        showError('不是有效的 JSON 文件');
        dom.characterImportInput.value = '';
        await promptUseWizardAfterImportFail();
        return;
    }

    try {
        const created = await characters.import(card);
        showSuccess(`成功导入角色「${created.name}」`);
        await loadCharacters();
    } catch (err) {
        // 后端 422 已带「导入失败：<原因> + 支持格式说明」，直接展示避免重复
        showError(err.message);
        await promptUseWizardAfterImportFail();
    } finally {
        // 清空 input，允许重复选择同一文件
        dom.characterImportInput.value = '';
    }
}

dom.btnImportCharacter.addEventListener('click', () => {
    dom.characterImportInput.click();
});
dom.characterImportInput.addEventListener('change', handleCharacterImport);

// ══════════════════════════════════════════════════
// 模型选择 & 开始对话
// ══════════════════════════════════════════════════

async function startChatWithCharacter(characterId) {
    const char = state.characters.find(c => c.id === characterId);
    const charName = char?.name || '未知角色';

    // 弹出模型选择器
    const selection = await showModelSelector(charName);
    if (!selection) return; // 用户取消

    try {
        const conv = await conversations.create({
            character_id: characterId,
            model_provider: selection.provider,
            model_name: selection.model,
            // 标题不传：后端默认「与 {角色名} 的对话」，首条消息后自动替换（P3.5）
        });
        switchView('chat');
        await loadConversations();
        // 创建即打开 tab（激活流程会以已知对话数据补全 title/characterId）
        await activateConversation(conv.id);
        chatDom.chatInput.focus();
    } catch (err) {
        showAlert('创建对话失败: ' + err.message);
    }
}

// ══════════════════════════════════════════════════
// 对话列表
// ══════════════════════════════════════════════════

async function loadConversations() {
    try {
        state.conversations = await conversations.list();
        renderConversations();
    } catch (err) {
        console.error('加载对话列表失败:', err);
        showError('加载对话列表失败');
    }
}

function renderConversations() {
    const list = dom.conversationList;
    if (state.conversations.length === 0) {
        list.innerHTML = '<p class="empty-hint">暂无对话</p>';
        return;
    }

    // 列表高亮按活动 tab 判定（单一事实来源）
    const activeConvId = getActiveTab()?.conversationId ?? null;

    list.innerHTML = state.conversations
        .map(
            (c) => `
        <div class="conversation-item ${c.id === activeConvId ? 'active' : ''}"
             data-id="${c.id}">
            <div class="title">${escapeHtml(c.title)}</div>
            <div class="meta">${c.message_count} 条消息 · ${escapeHtml(c.model_name || c.model_provider)}</div>
            <button class="btn-icon btn-delete-conv" title="删除对话">✕</button>
        </div>
    `
        )
        .join('');

    list.querySelectorAll('.conversation-item').forEach((item) => {
        item.addEventListener('click', (e) => {
            // 忽略删除按钮点击
            if (e.target.closest('.btn-delete-conv')) return;
            // 打开或激活对应会话 tab（统一激活流程）
            activateConversation(parseInt(item.dataset.id));
        });
    });

    // 删除对话事件
    list.querySelectorAll('.btn-delete-conv').forEach((btn) => {
        btn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const id = parseInt(btn.closest('.conversation-item').dataset.id);
            const conv = state.conversations.find(c => c.id === id);
            const confirmed = await showConfirm({
                title: '删除对话',
                message: `确定要删除对话「${conv?.title || '未知'}」吗？`,
                detail: `该对话共 ${conv?.message_count ?? 0} 条消息，删除后不可恢复。`,
                confirmText: '删除',
                danger: true,
            });
            if (confirmed) {
                try {
                    await conversations.delete(id);
                    // 联动：统一收口（closeTabs 内部先中止在途流式再关 tab；
                    // 被删 tab 为活动时才重定位渲染 — saveCurrent:false；
                    // 被删会话的 tab 缓存（草稿/滚动）随关闭一并销毁 — 无需预先保存）
                    await closeConversationsAndResettle({ ids: [id], reloadList: true });
                } catch (err) {
                    showAlert('删除失败: ' + err.message);
                }
            }
        });
    });
}

dom.btnNewChat.addEventListener('click', () => {
    // 切换到角色视图让用户选角色
    switchView('characters');
});

// ══════════════════════════════════════════════════
// 消息 & 聊天（协调层 — 聊天域渲染/发送见 chat.js）
// ══════════════════════════════════════════════════

/**
 * 对话重命名 — 双击标题原地编辑
 * @param {object} conv - 对话对象
 */
function startRename(conv) {
    const titleEl = chatDom.chatHeader.querySelector('#chat-title-text');
    if (!titleEl) return;

    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'chat-title-input';
    input.value = conv.title;
    input.maxLength = 200;

    titleEl.replaceWith(input);
    input.focus();
    input.select();

    async function save() {
        const newTitle = input.value.trim() || conv.title;
        try {
            await conversations.update(conv.id, { title: newTitle });
            conv.title = newTitle;
            // P6.5-4 标题联动：同步对应 tab 的 title（tab 条随动；onTabsChanged 驱动重渲染）
            updateTab(conv.id, { title: newTitle });
            // 更新对话列表中的标题
            const items = dom.conversationList.querySelectorAll('.conversation-item');
            items.forEach(item => {
                if (parseInt(item.dataset.id) === conv.id) {
                    const titleDiv = item.querySelector('.title');
                    if (titleDiv) titleDiv.textContent = newTitle;
                }
            });
        } catch (err) {
            console.error('重命名失败:', err);
        }
        // 恢复标题显示
        const span = document.createElement('span');
        span.className = 'chat-title';
        span.id = 'chat-title-text';
        span.textContent = newTitle;
        span.title = '双击重命名';
        input.replaceWith(span);
        span.addEventListener('dblclick', () => startRename(conv));
    }

    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            input.blur();
        }
        if (e.key === 'Escape') {
            input.value = conv.title;
            input.blur();
        }
    });

    input.addEventListener('blur', save);
}

// ══════════════════════════════════════════════════
// 会话激活流程（P6.5 收敛为单一内部函数 — 三入口与 tab 条共用）
// ══════════════════════════════════════════════════

/**
 * 保存当前活动 tab 的输入草稿与滚动位置到 tab 缓存（切换前调用）
 */
function saveActiveTabViewState() {
    const tab = getActiveTab();
    if (!tab) return;
    updateTab(tab.conversationId, {
        draft: chatDom.chatInput.value,
        scrollTop: chatDom.chatMessages.scrollTop,
    });
}

/**
 * 恢复指定 tab 的输入草稿与滚动位置到 DOM
 * @param {object|undefined} tab - 目标 tab（已关闭/不存在 → no-op，防御 F-2 竞态）
 */
function restoreTabViewState(tab) {
    if (!tab) return;
    chatDom.chatInput.value = tab.draft ?? '';
    chatDom.chatInput.style.height = 'auto';
    chatDom.chatInput.style.height = Math.min(chatDom.chatInput.scrollHeight, 150) + 'px';
    chatDom.chatMessages.scrollTop = tab.scrollTop ?? 0;
}

/**
 * 渲染聊天头部（标题 + 模型 badge + 导出/列表切换按钮 + 双击重命名绑定）
 * 按活动 tab 派生；对话数据以 conversations 列表为准（持久事实来源）
 * @param {number|string} conversationId - 活动 tab 的会话 id
 */
function renderChatHeader(conversationId) {
    const conv = state.conversations.find((c) => c.id === conversationId);
    if (!conv) {
        chatDom.chatHeader.innerHTML = '<span class="chat-title">选择一个角色开始对话</span>';
        return;
    }
    const modelLabel = conv.model_name || '';
    const providerLabel = providerDisplayName(state.models, conv.model_provider);
    chatDom.chatHeader.innerHTML = `
        <button class="btn-toggle-conv-list" id="btn-toggle-conv-list" title="切换对话列表">☰</button>
        <span class="chat-title" id="chat-title-text" title="双击重命名">${escapeHtml(conv.title)}</span>
        <span class="chat-model-badge">${escapeHtml(providerLabel)} · ${escapeHtml(modelLabel)}</span>
        <button class="btn-icon btn-export-conv" id="btn-export-conv" title="导出对话">📥</button>
    `;
    // 双击标题重命名
    const titleEl = chatDom.chatHeader.querySelector('#chat-title-text');
    titleEl.addEventListener('dblclick', () => startRename(conv));
    // 移动端切换对话列表
    const toggleBtn = chatDom.chatHeader.querySelector('#btn-toggle-conv-list');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', () => {
            const sidebar = document.querySelector('.chat-sidebar');
            if (sidebar) {
                sidebar.classList.toggle('mobile-expanded');
            }
        });
    }
    // 导出按钮
    const exportBtn = chatDom.chatHeader.querySelector('#btn-export-conv');
    if (exportBtn) {
        exportBtn.addEventListener('click', () => {
            showExportDialog(conversationId);
        });
    }
}

/**
 * 无活动 tab 时的空态（聊天区 + 头部提示）
 * 聊天区复用 chat.js 导出的共享常量（单一事实来源）
 */
function showEmptyState() {
    chatDom.chatHeader.innerHTML = '<span class="chat-title">选择一个角色开始对话</span>';
    chatDom.chatMessages.innerHTML = EMPTY_STATE_HTML;
}

/**
 * 懒加载指定会话消息并写入其 tab 缓存；仅当该 tab 仍为活动 tab 时才渲染
 * （快速连续切 tab 时各响应写各自 tab 缓存，后返回的响应不覆盖先返回的；
 * 缓存分支同样须校验活动性 —— F-2：await 期间切走时旧续体不得把 A 渲染进 B 的视图）
 * @param {number|string} conversationId - 会话 id
 */
async function loadTabMessages(conversationId) {
    const tab = getTab(conversationId);
    if (!tab) return;
    // 已有缓存（含流式中断后的部分内容）→ 不重复请求，直接渲染
    if (tab.messages.length > 0) {
        if (getActiveTab()?.conversationId === conversationId) {
            renderMessages();
            // renderMessages 内部 scrollToBottom — 此处恢复缓存中的滚动位置（切 tab 恢复）
            chatDom.chatMessages.scrollTop = tab.scrollTop ?? 0;
            renderChatHeader(conversationId);
        }
        return;
    }
    try {
        const msgs = await messages.list(conversationId);
        updateTab(conversationId, { messages: msgs });
        if (getActiveTab()?.conversationId === conversationId) {
            renderMessages();
            renderChatHeader(conversationId);
        }
    } catch (err) {
        console.error('加载消息失败:', err);
        showError('加载消息失败');
        if (getActiveTab()?.conversationId === conversationId) {
            renderMessages();
            renderChatHeader(conversationId);
        }
    }
}

/**
 * 切到某会话的统一激活流程（三入口与 tab 条共用）：
 *   openTab/activateTab + 以已知对话数据补全 tab 的 title/characterId（未知则经 API 获取）
 *   + 懒加载消息 + 草稿/滚动保存恢复 + 刷新发送按钮两态 + 列表高亮 + 视图切换
 * @param {number|string} conversationId - 会话 id
 * @param {object} [options]
 * @param {boolean} [options.saveCurrent=true] - 切换前保存当前活动 tab 的草稿/滚动。
 *   删除会话联动场景调用方已预先保存，传 false 防止旧视图 DOM 状态污染新活动 tab 缓存。
 */
async function activateConversation(conversationId, { saveCurrent = true } = {}) {
    // 1) 保存当前活动 tab 的草稿与滚动位置（切换前）
    if (saveCurrent) saveActiveTabViewState();
    // 2) 打开/激活 tab（已存在仅激活，不重复开）
    const tab = openTab(conversationId);
    if (!tab) return;
    // 3) 补全 tab 的 title/characterId：已知对话数据直接取；未知经 API 获取
    let conv = state.conversations.find((c) => c.id === conversationId);
    if (!conv) {
        try {
            conv = await conversations.get(conversationId);
        } catch {
            // 忽略 — 至少尝试加载消息
        }
        // await 期间用户可能已切走或关闭该 tab — 放弃续体（F-2）：
        // 否则恢复旧草稿覆盖新活动输入框、缓存分支把本会话渲染进错误视图
        if (getActiveTab()?.conversationId !== conversationId) return;
    }
    if (conv) {
        updateTab(conversationId, { title: conv.title, characterId: conv.character_id });
    }
    // 4) 恢复新 tab 的草稿与滚动位置
    restoreTabViewState(getTab(conversationId));
    // 5) 懒加载消息（缓存为空才请求）+ 头部渲染
    await loadTabMessages(conversationId);
    if (getActiveTab()?.conversationId !== conversationId) return;
    // 6) 刷新发送按钮两态 + 列表高亮 + 视图（已在聊天视图则跳过 switchView 的重复 loadConversations）
    refreshSendButton();
    renderConversations();
    if (state.currentView !== 'chat') switchView('chat');
}

/**
 * 级联关闭会话 tab 的统一收口（ARC-2 — 删角色级联 / 删会话 / 清空全部 /
 * tab-bar 关最后 tab 回调共用）：
 *   closeTabs 批量关闭（内部先 abort 各在途流式，单次 commit/notify）
 *   → 重定位活动 tab 视图 → refreshSendButton → reloadList 时 loadConversations
 *   （否则仅重渲染列表高亮/空态）。
 * 统一语义：仅当被关集合含活动 tab（wasActive）才重激活视图（saveCurrent:false —
 *   被关 tab 的 DOM 草稿/滚动不得污染新活动 tab 缓存；无剩余 tab → 空态）；
 *   活动 tab 未被关 → 不重激活，视图停留原地（消除删角色路径无条件重激活分歧）。
 *   已无任何 tab（tab-bar 已关最后 tab / 空集清空）→ 空态兜底（幂等）。
 * @param {object} [options]
 * @param {Array<number|string>|'all'} [options.ids='all'] - 要关闭的会话 id 列表；
 *   'all' 为当前全部 tab
 * @param {boolean} [options.reloadList=false] - 关闭后是否重新拉取对话列表
 *   （删会话/删角色路径；清空路径调用方已置空 state.conversations，仅重渲染即可）
 */
async function closeConversationsAndResettle({ ids = 'all', reloadList = false } = {}) {
    const doomed = ids === 'all'
        ? getTabs().map((t) => t.conversationId)
        : (Array.isArray(ids) ? ids : []);
    const activeBefore = getActiveTab()?.conversationId ?? null;
    const wasActive = activeBefore !== null && doomed.includes(activeBefore);
    if (doomed.length > 0) closeTabs(doomed);
    if (wasActive || getTabs().length === 0) {
        const active = getActiveTab();
        if (active) {
            await activateConversation(active.conversationId, { saveCurrent: false });
        } else {
            showEmptyState();
        }
    }
    refreshSendButton();
    if (reloadList) {
        await loadConversations();
    } else {
        renderConversations();
    }
}

// ══════════════════════════════════════════════════
// 输入框事件（发送/停止逻辑见 chat.js handleSend）
// ══════════════════════════════════════════════════

chatDom.btnSend.addEventListener('click', () => {
    const tab = getActiveTab();
    if (!tab) return;
    if (tab.isStreaming) {
        // 流式生成中 → 点击为「停止生成」（停止活动 tab 的流式句柄；经 tabs.js 协议统一）
        abortStream(tab.conversationId);
    } else {
        handleSend();
    }
});

chatDom.chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
    }
});

chatDom.chatInput.addEventListener('input', () => {
    chatDom.chatInput.style.height = 'auto';
    chatDom.chatInput.style.height = Math.min(chatDom.chatInput.scrollHeight, 150) + 'px';
});

// ══════════════════════════════════════════════════
// 模型列表
// ══════════════════════════════════════════════════

async function loadModels() {
    try {
        state.models = await models.list();
    } catch (err) {
        console.error('加载模型列表失败:', err);
    }
}

// ══════════════════════════════════════════════════
// 搜索
// ══════════════════════════════════════════════════

/**
 * 执行搜索并渲染结果
 * @param {string} query - 搜索关键词
 */
async function performSearch(query) {
    const resultsEl = dom.searchResults;
    query = query.trim();

    if (!query) {
        resultsEl.innerHTML = '<p class="search-hint">输入关键词搜索所有对话中的消息</p>';
        return;
    }

    if (query.length < 2) {
        resultsEl.innerHTML = '<p class="search-status">至少输入 2 个字符</p>';
        return;
    }

    resultsEl.innerHTML = '<p class="search-status">搜索中…</p>';

    try {
        const results = await messages.search(query);
        renderSearchResults(results, query);
    } catch (err) {
        console.error('搜索失败:', err);
        resultsEl.innerHTML = `<p class="search-status search-error">搜索失败: ${escapeHtml(err.message)}</p>`;
    }
}

/**
 * 渲染搜索结果列表
 * @param {Array} results - 搜索结果数组
 * @param {string} query - 原始查询（用于高亮）
 */
function renderSearchResults(results, query) {
    const resultsEl = dom.searchResults;

    if (!results || results.length === 0) {
        resultsEl.innerHTML = '<p class="search-status">未找到匹配的消息</p>';
        return;
    }

    const escapedQuery = escapeHtml(query);

    resultsEl.innerHTML = `
        <p class="search-count">共找到 ${results.length} 条匹配消息</p>
        <div class="search-result-list">
            ${results.map(r => {
                const roleLabel = r.role === 'user' ? '你' : escapeHtml(r.character_name);
                const roleIcon = r.role === 'user' ? '👤' : '🎭';
                const time = r.created_at ? new Date(r.created_at).toLocaleString('zh-CN') : '';

                // 高亮关键词
                const highlighted = highlightText(escapeHtml(r.content_preview), escapedQuery);

                return `
                    <div class="search-result-item" data-conversation-id="${r.conversation_id}" data-message-id="${r.message_id}">
                        <div class="search-result-header">
                            <span class="search-result-role">${roleIcon} ${escapeHtml(roleLabel)}</span>
                            <span class="search-result-conv">💬 ${escapeHtml(r.conversation_title || '未命名对话')}</span>
                        </div>
                        <div class="search-result-preview">${highlighted}</div>
                        <div class="search-result-time">${escapeHtml(time)}</div>
                    </div>
                `;
            }).join('')}
        </div>
    `;

    // 点击结果跳转到对应对话
    resultsEl.querySelectorAll('.search-result-item').forEach(item => {
        item.addEventListener('click', () => {
            const convId = parseInt(item.dataset.conversationId);
            if (convId) {
                navigateToConversation(convId);
            }
        });
    });
}

/**
 * 跳转到指定对话（搜索结果点击）— 与侧栏点击/创建对话共用统一激活流程
 * @param {number} conversationId
 */
async function navigateToConversation(conversationId) {
    await activateConversation(conversationId);
}

// ── 搜索输入事件 ──

dom.searchInput.addEventListener('input', () => {
    clearTimeout(searchTimeout);
    searchTimeout = null;
    const q = dom.searchInput.value;
    // 延迟搜索，避免每输入一个字就请求
    searchTimeout = setTimeout(() => performSearch(q), 300);
});

dom.searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        e.preventDefault();
        clearTimeout(searchTimeout);
        searchTimeout = null;
        performSearch(dom.searchInput.value);
    }
    if (e.key === 'Escape') {
        dom.searchInput.value = '';
        dom.searchInput.blur();
        performSearch('');
    }
});

dom.btnSearchClear.addEventListener('click', () => {
    dom.searchInput.value = '';
    dom.searchInput.focus();
    performSearch('');
});

// ══════════════════════════════════════════════════
// 初始化
// ══════════════════════════════════════════════════

async function init() {
    await loadCharacters();
    await loadConversations();
    await loadModels();
    await loadSettings();

    // P6.5-4 恢复时序契约：conversations 加载完成后才 restore；
    // isValidId 以已加载列表判定（过滤已删会话）；恢复的 tab 一律非流式，
    // 消息在激活时懒加载（走统一激活流程）
    restoreFromStorage({
        isValidId: (id) => state.conversations.some((c) => c.id === id),
    });
    const restored = getActiveTab();
    if (restored) {
        await activateConversation(restored.conversationId, { saveCurrent: false });
    } else {
        // 无记录 / 全部失效 → 现有空态（无空 tab 残留、不报错）
        showEmptyState();
    }

    // 初始化 Provider 下拉 + 模型下拉选项（含自定义模型回填）
    initProviderDropdown();

    // 初始化设置面板事件绑定（主题、侧栏、保存、清空等）
    initSettingsPanel({
        onConversationsCleared: () => {
            // 「清空所有对话」联动：统一收口（abort 全部在途流式 + closeTabs 全关 +
            // 空态 + 发送按钮）；settings-panel 已置空 state.conversations → 仅重渲染列表
            closeConversationsAndResettle({ ids: 'all', reloadList: false });
        },
    });
}

// 注入对话列表刷新钩子 — chat.js 在发送/停止后刷新对话列表（避免反向 import）
setConversationsRefresher(loadConversations);

// 注入 tab 条激活处理器（P6.5-3）：组件内 ✕ 直接 closeTab（含 abort 流式），
// 激活/联动一律经此回调走 P6.5-2 收敛的统一激活流程
initTabBar({
    container: $('#chat-tabs'),
    onActivate: async (convId, { saveCurrent = true } = {}) => {
        if (convId == null) {
            // 关闭最后一个 tab → 统一收口（tab-bar 已关 tab；settle 走空态 +
            // 发送按钮 + 列表高亮/空态重渲染）
            await closeConversationsAndResettle({ ids: [], reloadList: false });
            return;
        }
        await activateConversation(convId, { saveCurrent });
    },
});

init();
