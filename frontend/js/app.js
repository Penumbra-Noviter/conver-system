/**
 * Conver System — 主入口
 *
 * 职责：
 *   1. 视图切换（侧栏导航）
 *   2. 全局状态管理
 *   3. 事件绑定
 */

import { characters, conversations, messages, chatStream, models, settings } from './api.js';
import { showCharacterForm } from './components/character-form.js';
import { showConfirm, showAlert } from './components/confirm-dialog.js';
import { escapeHtml, getInitials, formatTags, renderMarkdown } from './utils.js';

// ══════════════════════════════════════════════════
// 全局状态
// ══════════════════════════════════════════════════

const state = {
    currentView: 'chat',
    characters: [],
    conversations: [],
    currentConversationId: null,
    currentCharacterId: null,
    messages: [],
    isStreaming: false,
    models: { providers: [] },       // 可用模型列表
    defaultProvider: 'claude',
    defaultModel: 'claude-sonnet-4-20250514',
};

// ══════════════════════════════════════════════════
// DOM 引用
// ══════════════════════════════════════════════════

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

const dom = {
    // 视图
    views: $$('.view'),
    navBtns: $$('.nav-btn'),

    // 聊天
    conversationList: $('#conversation-list'),
    chatMessages: $('#chat-messages'),
    chatInput: $('#chat-input'),
    btnSend: $('#btn-send'),
    btnNewChat: $('#btn-new-chat'),
    chatHeader: $('#chat-header'),
    toggleStream: $('#toggle-stream'),
    // 移动端
    mobileNavBtns: $$('.mobile-nav-btn'),
    convListToggle: null, // 将在初始化时创建

    // 角色
    characterGrid: $('#character-grid'),
    btnCreateCharacter: $('#btn-create-character'),

    // 搜索
    searchInput: $('#search-input'),
    searchResults: $('#search-results'),
    btnSearchClear: $('#btn-search-clear'),

    // 设置
    btnSaveSettings: $('#btn-save-settings'),
    btnClearAllConvs: $('#btn-clear-all-convs'),
};

// ══════════════════════════════════════════════════
// 视图切换
// ══════════════════════════════════════════════════

function switchView(viewName) {
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
        refreshModelOptions();
        loadSettings();
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
let convListVisible = true;
function toggleConvList() {
    const sidebar = document.querySelector('.chat-sidebar');
    if (!sidebar) return;
    convListVisible = !convListVisible;
    sidebar.style.display = convListVisible ? '' : 'none';
}

// ══════════════════════════════════════════════════
// Toast 通知
// ══════════════════════════════════════════════════

function showError(message) {
    const toast = document.createElement('div');
    toast.className = 'toast toast-error';
    toast.textContent = message;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 5000);
}

function showSuccess(message) {
    const toast = document.createElement('div');
    toast.className = 'toast toast-success';
    toast.textContent = message;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 5000);
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
                ${c.tags && c.tags !== '[]' ? `<div class="detail-item"><span class="detail-label">标签:</span> ${escapeHtml(formatTags(c.tags))}</div>` : ''}
            </div>
            <div class="character-card-meta">
                <span class="meta-badge">🌡️ ${c.temperature?.toFixed(1) ?? '0.7'}</span>
                <span class="meta-badge">💬 ${c.conversation_count ?? 0}</span>
            </div>
            <div class="character-card-actions">
                <button class="btn-icon chat-with" title="开始对话">💬</button>
                <button class="btn-icon edit-char" title="编辑">✏️</button>
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
    showCharacterForm('create', null, () => loadCharacters());
});

/**
 * 显示模型选择对话框 — 创建对话时让用户选择 Provider 和模型
 * @param {string} characterName - 角色名称（用于展示）
 * @returns {Promise<{provider: string, model: string}|null>} 选择的配置，取消返回 null
 */
function showModelSelector(characterName) {
    return new Promise((resolve) => {
        const existing = document.querySelector('.modal-overlay');
        if (existing) existing.remove();

        const providers = state.models.providers || [];
        const defaultProviderId = state.defaultProvider;
        const defaultModelName = state.defaultModel;

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';

        overlay.innerHTML = `
            <div class="modal model-selector-modal">
                <div class="modal-header">
                    <h3>开始对话 · ${escapeHtml(characterName)}</h3>
                    <button class="btn-icon modal-close" title="关闭">✕</button>
                </div>
                <div class="modal-body">
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
                </div>
                <div class="modal-footer">
                    <button class="btn-secondary ms-cancel">取消</button>
                    <button class="btn-primary ms-start">开始对话</button>
                </div>
            </div>
        `;

        document.body.appendChild(overlay);

        const providerSelect = overlay.querySelector('#ms-provider');
        const modelSelect = overlay.querySelector('#ms-model');

        // ── 填充模型下拉列表 ──
        function populateModels(providerId) {
            const provider = providers.find(p => p.id === providerId);
            if (!provider) return;
            modelSelect.innerHTML = provider.models
                .map(m => {
                    const selected = m === defaultModelName && providerId === defaultProviderId ? 'selected' : '';
                    return `<option value="${escapeHtml(m)}" ${selected}>${escapeHtml(m)}</option>`;
                })
                .join('');
        }
        populateModels(providerSelect.value);

        // Provider 切换时更新模型列表
        providerSelect.addEventListener('change', () => populateModels(providerSelect.value));

        const close = (result) => {
            overlay.remove();
            resolve(result);
        };

        overlay.querySelector('.modal-close').addEventListener('click', () => close(null));
        overlay.querySelector('.ms-cancel').addEventListener('click', () => close(null));
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) close(null);
        });

        overlay.querySelector('.ms-start').addEventListener('click', () => {
            const provider = providerSelect.value;
            const model = modelSelect.value;
            close({ provider, model });
        });

        overlay.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') close(null);
            if (e.key === 'Enter') {
                const provider = providerSelect.value;
                const model = modelSelect.value;
                close({ provider, model });
            }
        });

        setTimeout(() => overlay.querySelector('.ms-start').focus(), 50);
    });
}

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
            title: '新对话',
            model_provider: selection.provider,
            model_name: selection.model,
        });
        state.currentConversationId = conv.id;
        switchView('chat');
        await loadConversations();
        await loadMessages();
        dom.chatInput.focus();
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
// 消息 & 聊天
// ══════════════════════════════════════════════════

/**
 * 对话重命名 — 双击标题原地编辑
 * @param {object} conv - 对话对象
 */
function startRename(conv) {
    const titleEl = dom.chatHeader.querySelector('#chat-title-text');
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
        dom.chatMessages.innerHTML = '<div class="empty-state"><p>选择左侧对话或创建新对话开始聊天</p></div>';
        dom.chatHeader.textContent = '选择一个角色开始对话';
        return;
    }

    try {
        state.messages = await messages.list(state.currentConversationId);
        renderMessages();

        // 更新头部：对话标题 + 模型信息 + 双击重命名
        const conv = state.conversations.find((c) => c.id === state.currentConversationId);
        if (conv) {
            const modelLabel = conv.model_name || '';
            const providerLabel = conv.model_provider === 'openai' ? 'OpenAI' : 'Claude';
            dom.chatHeader.innerHTML = `
                <button class="btn-toggle-conv-list" id="btn-toggle-conv-list" title="切换对话列表">☰</button>
                <span class="chat-title" id="chat-title-text" title="双击重命名">${escapeHtml(conv.title)}</span>
                <span class="chat-model-badge">${escapeHtml(providerLabel)} · ${escapeHtml(modelLabel)}</span>
                <button class="btn-icon btn-export-conv" id="btn-export-conv" title="导出对话">📥</button>
            `;
            // 双击标题重命名
            const titleEl = dom.chatHeader.querySelector('#chat-title-text');
            titleEl.addEventListener('dblclick', () => startRename(conv));
            // 移动端切换对话列表
            const toggleBtn = dom.chatHeader.querySelector('#btn-toggle-conv-list');
            if (toggleBtn) {
                toggleBtn.addEventListener('click', () => {
                    const sidebar = document.querySelector('.chat-sidebar');
                    if (sidebar) {
                        const isHidden = sidebar.style.display === 'none';
                        sidebar.style.display = isHidden ? '' : 'none';
                    }
                });
            }
            // 导出按钮
            const exportBtn = dom.chatHeader.querySelector('#btn-export-conv');
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

function renderMessages() {
    const container = dom.chatMessages;
    if (state.messages.length === 0) {
        container.innerHTML = '<div class="empty-state"><p>开始一段对话吧</p></div>';
        return;
    }

    container.innerHTML = state.messages
        .map(
            (m) => `
        <div class="message ${m.role}">
            ${m.role === 'assistant' ? getAssistantAvatarHtml() : getUserAvatarHtml()}
            <div class="message-content">${m.role === 'assistant' ? renderMarkdown(m.content) : escapeHtml(m.content)}</div>
            <button class="btn-copy-message" title="复制消息" data-content="${escapeHtml(m.content)}">📋</button>
        </div>
    `
        )
        .join('');

    // 复制按钮事件
    container.querySelectorAll('.btn-copy-message').forEach(btn => {
        attachCopyButton(btn, btn.dataset.content);
    });

    scrollToBottom();
}

function appendMessage(role, content) {
    const container = dom.chatMessages;
    // 移除空状态
    const empty = container.querySelector('.empty-state');
    if (empty) empty.remove();
    // 移除 thinking 指示器
    const thinking = container.querySelector('.thinking-indicator');
    if (thinking) thinking.remove();

    const div = document.createElement('div');
    div.className = `message ${role}`;

    // 头像
    div.appendChild(createAvatarElement(role));

    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    if (role === 'assistant') {
        contentDiv.innerHTML = renderMarkdown(content);
    } else {
        contentDiv.textContent = content;
    }
    div.appendChild(contentDiv);

    // 复制按钮
    const copyBtn = document.createElement('button');
    copyBtn.className = 'btn-copy-message';
    copyBtn.title = '复制消息';
    copyBtn.textContent = '📋';
    copyBtn.dataset.content = content;
    attachCopyButton(copyBtn, content);
    div.appendChild(copyBtn);

    container.appendChild(div);
    scrollToBottom();
}

function showThinkingIndicator() {
    const container = dom.chatMessages;
    // 移除已有 thinking
    const existing = container.querySelector('.thinking-indicator');
    if (existing) existing.remove();

    const div = document.createElement('div');
    div.className = 'thinking-indicator';
    div.innerHTML = '<span class="dot-pulse"></span> 思考中…';
    container.appendChild(div);
    scrollToBottom();
}

function scrollToBottom() {
    dom.chatMessages.scrollTop = dom.chatMessages.scrollHeight;
}

// ══════════════════════════════════════════════════
// 对话导出
// ══════════════════════════════════════════════════

function showExportDialog(conversationId) {
    const overlay = document.getElementById('export-dialog-overlay');
    if (overlay) {
        overlay.classList.add('active');
        return;
    }
    createExportDialog(conversationId);
}

function createExportDialog(conversationId) {
    const overlay = document.createElement('div');
    overlay.id = 'export-dialog-overlay';
    overlay.className = 'modal-overlay';

    overlay.innerHTML = `
        <div class="modal export-modal">
            <div class="modal-header">
                <h3>导出对话</h3>
                <button class="btn-icon modal-close" title="关闭">✕</button>
            </div>
            <div class="modal-body">
                <p class="export-hint">选择导出格式：</p>
                <div class="export-options">
                    <button class="export-option-btn" data-format="markdown">
                        <span class="export-option-icon">📄</span>
                        <span class="export-option-label">Markdown (.md)</span>
                        <span class="export-option-desc">可读的纯文本格式，适合分享和查看</span>
                    </button>
                    <button class="export-option-btn" data-format="json">
                        <span class="export-option-icon">📋</span>
                        <span class="export-option-label">JSON (.json)</span>
                        <span class="export-option-desc">结构化数据格式，适合程序处理</span>
                    </button>
                </div>
            </div>
            <div class="modal-footer">
                <button class="btn-secondary export-cancel">取消</button>
            </div>
        </div>
    `;

    document.body.appendChild(overlay);

    const close = () => {
        overlay.remove();
    };

    overlay.querySelector('.modal-close').addEventListener('click', close);
    overlay.querySelector('.export-cancel').addEventListener('click', close);
    overlay.addEventListener('click', (e) => {
        if (e.target === overlay) close();
    });
    overlay.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') close();
    });

    overlay.querySelectorAll('.export-option-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const format = btn.dataset.format;
            close();
            downloadExport(conversationId, format);
        });
    });
}

function downloadExport(conversationId, format) {
    const url = `/api/conversations/${conversationId}/export/${format}`;
    fetch(url)
        .then(res => {
            if (!res.ok) throw new Error('导出失败');
            return res.blob();
        })
        .then(blob => {
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            const ext = format === 'markdown' ? '.md' : '.json';
            a.download = `conversation-${conversationId}${ext}`;
            a.click();
            URL.revokeObjectURL(a.href);
        })
        .catch(err => showError('导出失败: ' + err.message));
}

// ── 头像渲染 ──

/**
 * 获取当前角色的头像 HTML
 * @returns {string}
 */
function getAssistantAvatarHtml() {
    const char = state.characters.find(c => c.id === state.currentCharacterId);
    if (char?.avatar) {
        return `<div class="msg-avatar"><img src="${escapeHtml(char.avatar)}" alt="${escapeHtml(char.name || '角色')}" onerror="this.parentElement.innerHTML='<div class=\\'avatar-placeholder-xs\\'>${escapeHtml(getInitials(char.name || 'A'))}</div>'"></div>`;
    }
    const name = char?.name || 'AI';
    return `<div class="msg-avatar"><div class="avatar-placeholder-xs">${escapeHtml(getInitials(name))}</div></div>`;
}

/**
 * 获取默认用户头像 HTML
 * @returns {string}
 */
function getUserAvatarHtml() {
    return `<div class="msg-avatar user-avatar">👤</div>`;
}

/**
 * 创建消息头像 DOM 元素（复用 HTML 字符串辅助函数）
 * @param {'assistant'|'user'} role - 消息角色
 * @returns {HTMLElement} 头像元素
 */
function createAvatarElement(role) {
    const wrapper = document.createElement('div');
    wrapper.innerHTML = role === 'assistant' ? getAssistantAvatarHtml() : getUserAvatarHtml();
    return wrapper.firstElementChild;
}

/**
 * 为消息复制按钮绑定点击事件（复制内容到剪贴板并给出 ✅/❌ 反馈）
 * @param {HTMLButtonElement} btn - 复制按钮元素
 * @param {string} content - 要复制的消息内容
 */
function attachCopyButton(btn, content) {
    btn.addEventListener('click', async (e) => {
        e.stopPropagation();
        try {
            await navigator.clipboard.writeText(content);
            btn.textContent = '✅';
            btn.classList.add('copied');
            setTimeout(() => {
                btn.textContent = '📋';
                btn.classList.remove('copied');
            }, 1500);
        } catch {
            btn.textContent = '❌';
        }
    });
}

// ── 发送消息 ──

async function handleSend() {
    const content = dom.chatInput.value.trim();
    if (!content || !state.currentConversationId || state.isStreaming) return;

    dom.chatInput.value = '';
    dom.chatInput.style.height = 'auto';

    // 显示用户消息
    appendMessage('user', content);

    const useStream = dom.toggleStream.checked;

    if (useStream) {
        // 流式模式
        state.isStreaming = true;
        dom.btnSend.disabled = true;

        const assistantDiv = document.createElement('div');
        assistantDiv.className = 'message assistant';
        // 头像
        assistantDiv.appendChild(createAvatarElement('assistant'));
        const assistantContentDiv = document.createElement('div');
        assistantContentDiv.className = 'message-content';
        assistantDiv.appendChild(assistantContentDiv);
        dom.chatMessages.appendChild(assistantDiv);

        let fullContent = '';

        await chatStream(
            { conversation_id: state.currentConversationId, content },
            (token) => {
                fullContent += token;
                assistantContentDiv.innerHTML = renderMarkdown(fullContent);
                scrollToBottom();
            },
            (messageId) => {
                state.isStreaming = false;
                dom.btnSend.disabled = false;
                if (messageId) {
                    // 正常完成 — 保存完整消息
                    state.messages.push(
                        { role: 'user', content },
                        { role: 'assistant', content: fullContent, id: messageId }
                    );
                } else if (fullContent) {
                    // 流中断但已有部分内容
                    state.messages.push(
                        { role: 'user', content },
                        { role: 'assistant', content: fullContent }
                    );
                }
                // 刷新对话列表（更新消息数量）
                loadConversations();
            },
            (err) => {
                state.isStreaming = false;
                dom.btnSend.disabled = false;
                assistantDiv.querySelector('.message-content').textContent = `[错误] ${err.message}`;
                // 错误时也刷新对话列表（避免计数卡死）
                loadConversations();
            }
        );
    } else {
        // 非流式模式
        showThinkingIndicator();
        try {
            dom.btnSend.disabled = true;
            const result = await messages.chat({
                conversation_id: state.currentConversationId,
                content,
            });
            appendMessage('assistant', result.reply);
            state.messages.push(
                { role: 'user', content },
                { role: 'assistant', content: result.reply }
            );
        } catch (err) {
            appendMessage('system', `发送失败: ${err.message}`);
        } finally {
            dom.btnSend.disabled = false;
        }
    }

    // 刷新对话列表（更新消息数量）
    loadConversations();
}

// ── 输入框事件 ──

dom.btnSend.addEventListener('click', handleSend);

dom.chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
    }
});

dom.chatInput.addEventListener('input', () => {
    dom.chatInput.style.height = 'auto';
    dom.chatInput.style.height = Math.min(dom.chatInput.scrollHeight, 150) + 'px';
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

/**
 * 刷新设置面板中的模型下拉选项
 * 在 settings 视图切换或 provider 变更时调用
 */
function refreshModelOptions() {
    const providerSelect = $('#setting-default-provider');
    const modelSelect = $('#setting-default-model');
    const provider = state.models.providers?.find(p => p.id === providerSelect.value);
    if (!provider) return;
    modelSelect.innerHTML = provider.models
        .map(m => `<option value="${escapeHtml(m)}">${escapeHtml(m)}</option>`)
        .join('');
}

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

async function loadSettings() {
    try {
        const s = await settings.get();
        if (s.claude_api_key) $('#setting-claude-key').value = s.claude_api_key;
        if (s.openai_api_key) $('#setting-openai-key').value = s.openai_api_key;
        if (s.openai_base_url) $('#setting-openai-url').value = s.openai_base_url;
        if (s.default_provider) {
            $('#setting-default-provider').value = s.default_provider;
            state.defaultProvider = s.default_provider;
        }
        if (s.default_model) {
            $('#setting-default-model').value = s.default_model;
            state.defaultModel = s.default_model;
        }
        if (s.sliding_window_rounds) $('#setting-sliding-window').value = s.sliding_window_rounds;
        if (s.theme_mode) {
            $('#setting-theme').value = s.theme_mode;
            applyTheme(s.theme_mode);
        }
        if (s.user_name) $('#setting-user-name').value = s.user_name;
    } catch (err) {
        console.error('加载设置失败:', err);
    }
}

dom.btnSaveSettings.addEventListener('click', async () => {
    const data = {
        claude_api_key: $('#setting-claude-key').value,
        openai_api_key: $('#setting-openai-key').value,
        openai_base_url: $('#setting-openai-url').value,
        default_provider: $('#setting-default-provider').value,
        default_model: $('#setting-default-model').value,
        sliding_window_rounds: $('#setting-sliding-window').value,
        theme_mode: $('#setting-theme').value,
        user_name: $('#setting-user-name').value,
    };

    try {
        const result = await settings.update(data);
        // 更新本地状态
        state.defaultProvider = result.default_provider || data.default_provider;
        state.defaultModel = result.default_model || data.default_model;
        // 应用主题
        applyTheme(data.theme_mode || 'auto');
        showAlert('设置已保存');
    } catch (err) {
        showAlert('保存失败: ' + err.message);
    }
});

// ── 清空所有对话 ──
dom.btnClearAllConvs.addEventListener('click', async () => {
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
            renderConversations();
            loadMessages();
            showAlert(`已清空 ${convCount} 个对话`);
        } catch (err) {
            showAlert('清空失败: ' + err.message);
        }
    }
});

// ══════════════════════════════════════════════════
// 搜索
// ══════════════════════════════════════════════════

let searchTimeout = null;

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
 * 高亮文本中的关键词
 * @param {string} text - 已转义的文本
 * @param {string} keyword - 已转义的关键词
 * @returns {string} HTML
 */
function highlightText(text, keyword) {
    if (!keyword) return text;
    const idx = text.toLowerCase().indexOf(keyword.toLowerCase());
    if (idx === -1) return text;
    return text.slice(0, idx)
        + '<mark class="search-highlight">' + text.slice(idx, idx + keyword.length) + '</mark>'
        + text.slice(idx + keyword.length);
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
    const q = dom.searchInput.value;
    // 延迟搜索，避免每输入一个字就请求
    searchTimeout = setTimeout(() => performSearch(q), 300);
});

dom.searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        e.preventDefault();
        clearTimeout(searchTimeout);
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
// 工具函数 — 已迁移至 utils.js
// ══════════════════════════════════════════════════

// ══════════════════════════════════════════════════
// 初始化
// ══════════════════════════════════════════════════

async function init() {
    await loadCharacters();
    await loadConversations();
    await loadModels();
    await loadSettings();

    // Provider 切换时动态更新模型列表
    $('#setting-default-provider').addEventListener('change', refreshModelOptions);
}

init();
