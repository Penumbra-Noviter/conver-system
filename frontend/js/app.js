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
import { escapeHtml, getInitials, formatTags, showToast, downloadBlob, providerDisplayName } from './utils.js';
import { highlightText } from './format.js';
import { state } from './state.js';
import { chatDom, renderMessages, handleSend, setConversationsRefresher } from './chat.js';

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
                <button class="btn-icon chat-with" title="开始对话">💬</button>
                <button class="btn-icon edit-char" title="编辑">✏️</button>
                <button class="btn-icon export-char" title="导出角色卡">📤</button>
                <button class="btn-icon delete-char" title="删除">🗑️</button>
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
        return;
    }

    try {
        const created = await characters.import(card);
        showSuccess(`成功导入角色「${created.name}」`);
        await loadCharacters();
    } catch (err) {
        // 后端 422 已带「导入失败：<原因>」前缀，直接展示避免重复
        showError(err.message);
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
    state.currentCharacterId = characterId;
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
        state.currentConversationId = conv.id;
        switchView('chat');
        await loadConversations();
        await loadMessages();
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

    list.innerHTML = state.conversations
        .map(
            (c) => `
        <div class="conversation-item ${c.id === state.currentConversationId ? 'active' : ''}"
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
            state.currentConversationId = parseInt(item.dataset.id);
            // 从对话数据获取 character_id
            const conv = state.conversations.find(c => c.id === state.currentConversationId);
            if (conv) state.currentCharacterId = conv.character_id;
            renderConversations();
            loadMessages();
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
                    if (state.currentConversationId === id) {
                        state.currentConversationId = null;
                        state.messages = [];
                        renderMessages();
                    }
                    await loadConversations();
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

async function loadMessages() {
    if (!state.currentConversationId) {
        chatDom.chatMessages.innerHTML = '<div class="empty-state"><p>选择左侧对话或创建新对话开始聊天</p></div>';
        chatDom.chatHeader.textContent = '选择一个角色开始对话';
        return;
    }

    try {
        state.messages = await messages.list(state.currentConversationId);
        renderMessages();

        // 更新头部：对话标题 + 模型信息 + 双击重命名
        const conv = state.conversations.find((c) => c.id === state.currentConversationId);
        if (conv) {
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
                    showExportDialog(state.currentConversationId);
                });
            }
        }
    } catch (err) {
        console.error('加载消息失败:', err);
        showError('加载消息失败');
    }
}

// ══════════════════════════════════════════════════
// 输入框事件（发送/停止逻辑见 chat.js handleSend）
// ══════════════════════════════════════════════════

chatDom.btnSend.addEventListener('click', () => {
    if (state.isStreaming) {
        // 流式生成中 → 点击为「停止生成」
        state.activeStream?.abort();
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
 * 跳转到指定对话
 * @param {number} conversationId
 */
async function navigateToConversation(conversationId) {
    state.currentConversationId = conversationId;
    // 先尝试从本地状态找
    let conv = state.conversations.find(c => c.id === conversationId);
    if (conv) {
        state.currentCharacterId = conv.character_id;
    } else {
        // 从 API 获取
        try {
            conv = await conversations.get(conversationId);
            if (conv) state.currentCharacterId = conv.character_id;
        } catch {
            // 忽略 — 至少尝试加载消息
        }
    }
    switchView('chat');
    renderConversations();
    await loadMessages();
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

    // 初始化 Provider 下拉 + 模型下拉选项（含自定义模型回填）
    initProviderDropdown();

    // 初始化设置面板事件绑定（主题、侧栏、保存、清空等）
    initSettingsPanel({
        onConversationsCleared: () => {
            renderConversations();
            loadMessages();
        },
    });
}

// 注入对话列表刷新钩子 — chat.js 在发送/停止后刷新对话列表（避免反向 import）
setConversationsRefresher(loadConversations);

init();
