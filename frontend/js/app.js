/**
 * Conver System — 主入口（协调层）
 *
 * 职责：
 *   1. 视图切换（侧栏导航，含 switchView 内 100ms 搜索框聚焦时序）
 *   2. 业务协调（角色 / 对话 / 删除确认弹窗与调用点 / 初始化接线）
 *   3. 事件绑定
 *
 * 模块结构：
 *   - ./state.js — 全局状态
 *   - ./chat.js  — 聊天域渲染与交互（renderMessages / handleSend / chatDom /
 *     聊天头部深模块 renderChatHeader / startRename — F4 收口）
 *   - ./format.js — 渲染/格式化纯函数（highlightText / buildMessagesHtml）
 *   - ./search-view.js — 搜索视图深模块（防抖 + 五态文案 + 渲染 + 结果跳转；
 *     ARC-9 C1 迁出，经 initSearchView 注入跳转钩子接线）
 *   - ./cascade.js — 级联关闭收口深模块（删角色/删对话/清空全部/关最后 tab
 *     四入口共用；ARC-9 C1 迁出，依赖经 setCascadeHooks 注入接线）
 *   - ./simulators.js — 模拟器列表视图深模块（manifest 解析 + 卡片网格 +
 *     类型筛选 + 四态；U7-T3，进入视图经 refreshSimulators 刷新，打开回调
 *     经 initSimulatorsView 注入）
 *   - ./simulator-view.js — 模拟器运行视图深模块（iframe 状态机 + AI 提示条
 *     + 返回；U7-T4，onOpenGame 接到 openSimulator，切走 simulators 视图时
 *     closeSimulator 销毁 iframe — Grilling 共识：状态全在游戏自身
 *     localStorage，避免后台游戏继续跑）
 *   - ./components/settings-panel.js — 设置面板（Provider 下拉、主题、侧栏、保存、清空）
 *   - ./components/ — 模态框相关组件（modal 工厂 / confirm / model-selector / export / character-form）
 */

import { characters, conversations, models } from './api.js';
import { showCharacterForm } from './components/character-form.js';
import { showCharacterWizard } from './components/character-wizard.js';
import { showConfirm, showAlert } from './components/confirm-dialog.js';
import { showModelSelector } from './components/model-selector.js';
import { initSettingsPanel, loadSettings, initProviderDropdown } from './components/settings-panel.js';
import { initTabBar } from './components/tab-bar.js';
import { showToast, downloadBlob, autoResizeInput } from './utils.js';
import { characterCardHtml, conversationItemHtml } from './format.js';
import { state } from './state.js';
import { chatDom, handleSend, refreshSendButton, setConversationsRefresher, setConversationListTitleSyncer } from './chat.js';
import { getActiveTab, getTabs, abortStream, restoreFromStorage } from './tabs.js';
import { activateConversation, showEmptyState, setActivationHooks } from './conversation-activation.js';
import { initSearchView } from './search-view.js';
import { closeConversationsAndResettle, setCascadeHooks } from './cascade.js';
import { initSimulatorsView, refreshSimulators } from './simulators.js';
import { initSimulatorRun, openSimulator, closeSimulator } from './simulator-view.js';

// ══════════════════════════════════════════════════
// DOM 引用
// ══════════════════════════════════════════════════

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

// 模块级状态（UI 实现细节，不属于全局应用状态）

const dom = {
    // 视图
    views: $$('.view'),
    navBtns: $$('.nav-btn'),

    // 聊天（聊天域 DOM 引用见 chat.js chatDom）
    conversationList: $('#conversation-list'),
    btnNewChat: $('#btn-new-chat'),
    // 移动端
    mobileNavBtns: $$('.mobile-nav-btn'),

    // 角色
    characterGrid: $('#character-grid'),
    btnCreateCharacter: $('#btn-create-character'),
    btnImportCharacter: $('#btn-import-character'),
    characterImportInput: $('#character-import-input'),
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
        // 聚焦时序（ARC-9 C1）：100ms 延迟聚焦留在编排区 — 搜索视图事件绑定
        // 与防抖逻辑在 search-view.js，本处只负责视图切换后的焦点引导
        setTimeout(() => document.querySelector('#search-input')?.focus(), 100);
    }
    // 模拟器视图：进入即刷新列表（懒加载 — 未进入不发请求；fetch 在
    // simulators.js 内部走 setFetch seam，协调层只负责触发）
    if (viewName === 'simulators') refreshSimulators();
    // 切走模拟器视图 → 销毁运行中的 iframe（Grilling 共识：状态全在游戏
    // 自身 localStorage，无丢失风险；避免后台游戏继续跑；closeSimulator
    // 未打开时 no-op）
    if (viewName !== 'simulators') closeSimulator();
}

dom.navBtns.forEach((btn) => {
    btn.addEventListener('click', () => switchView(btn.dataset.view));
});

// 移动端导航事件
dom.mobileNavBtns.forEach((btn) => {
    btn.addEventListener('click', () => switchView(btn.dataset.view));
});

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

    grid.innerHTML = state.characters.map((c) => characterCardHtml(c)).join('');

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
        .map((c) => conversationItemHtml(c, { activeId: activeConvId }))
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
// 会话激活流程（ARC-6 移入 conversation-activation.js 深模块 —
//   激活编排 / 草稿滚动保存恢复 / 懒加载 / F-2 守卫 / 空态 均由该模块持有，
//   app.js 经 setActivationHooks 注入 DOM 渲染回调，本文件保留事件与协调；
//   聊天域渲染/发送/头部深模块见 chat.js — 头部 F4 已收口，app.js 只留注入接线）
// ══════════════════════════════════════════════════

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
    autoResizeInput(chatDom.chatInput);
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
// 初始化
// ══════════════════════════════════════════════════

async function init() {
    await loadCharacters();
    await loadConversations();
    await loadModels();
    await loadSettings();

    // ARC-6：激活编排模块的 DOM 渲染回调注入（renderConversations/视图切换/错误提示；
    // 头部渲染 F4 已收口 chat.js — conversation-activation 直 import，不再经 hooks）
    setActivationHooks({
        renderConversations,
        switchView: (viewName) => switchView(viewName),
        showError,
    });

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

// 注入重命名后的对话列表标题同步（F4 — 头部模块经钩子更新列表项标题，避免反向依赖；
// 只做 DOM 手术，不重渲染列表 — 与收口前行为一致）
setConversationListTitleSyncer((convId, newTitle) => {
    dom.conversationList.querySelectorAll('.conversation-item').forEach((item) => {
        if (parseInt(item.dataset.id) === convId) {
            const titleDiv = item.querySelector('.title');
            if (titleDiv) titleDiv.textContent = newTitle;
        }
    });
});

// 级联收口依赖注入（ARC-9 C1 — 删角色级联 / 删对话 / 清空全部 / tab-bar 关最后
// tab 四入口共用统一收口；依赖经注入而非互相 import，G7）
setCascadeHooks({
    renderConversations,
    loadConversations,
    activateConversation,
    showEmptyState,
    refreshSendButton,
});

// 搜索视图初始化（ARC-9 C1 — 防抖 + 五态文案 + 渲染 + 结果跳转收口在 search-view.js；
// 跳转钩子经注入走统一激活流程；100ms 聚焦时序在 switchView 内）
initSearchView({
    navigateToConversation: (conversationId) => activateConversation(conversationId),
});

// 模拟器列表视图初始化（U7-T3 — 挂载列表 UI 到 #simulator-list-panel；
// onOpenGame 接入 openSimulator：点击卡片 → 运行视图，U7-T4）
initSimulatorsView({ container: $('#simulator-list-panel'), onOpenGame: openSimulator });

// 模拟器运行视图初始化（U7-T4 — 绑定列表/运行两面板；iframe 状态机 +
// AI 提示条 + 返回收口在 simulator-view.js）
initSimulatorRun({
    listPanel: $('#simulator-list-panel'),
    runPanel: $('#simulator-run-panel'),
});

// 注入 tab 条激活处理器（P6.5-3）：组件内关闭按钮直接 closeTab（含 abort 流式），
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
