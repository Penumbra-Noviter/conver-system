/**
 * Conver System — 角色/对话列表视图（深模块，C4 从 app.js 下沉）
 *
 * 职责：角色与对话两个列表视图的全部逻辑收口 —— 角色网格渲染与四类按钮
 *   事件委托（开始对话 / 编辑 / 导出 / 删除）、角色导入（读取 → 解析 →
 *   导入 → 失败引导创建向导）、开始对话全流程（模型选择 → 创建 → 切视图 →
 *   激活 → 聚焦）、对话列表渲染与打开/删除委托、创建/导入/新聊天按钮事件、
 *   列表标题同步 DOM 手术（只更新匹配会话项 .title 文本，不重渲染列表）。
 *   协调层（app.js）退化为纯编排 —— 视图切换、数据加载序列、注入接线；
 *   本模块只经单钩子面 { switchView } 依赖协调层（startChatWithCharacter
 *   创建对话后切 chat 视图 / btnNewChat 切角色视图）。
 *
 * DOM 契约：本模块持有自身 DOM 引用（#character-grid / #btn-create-character /
 *   #btn-import-character / #character-import-input / #conversation-list /
 *   #btn-new-chat），index.html id/class 零变更；模块求值于 DOM 就位之后
 *   （type=module 延迟执行）。
 *
 * 依赖方向：list-views.js → api.js / format.js / tabs.js / cascade.js /
 *   conversation-activation.js / components/*（character-form /
 *   character-wizard / confirm-dialog / model-selector）/ utils.js / chat.js
 *   （chatDom，仅聚焦 #chat-input）。全部单向直 import 下层模块，禁止反向
 *   import app.js —— 无循环依赖（协调层 → list-views → 下层模块）。
 *
 * 错误/成功提示（showError / showSuccess）为 utils.js 薄封装（C4 与 showToast
 *   同域，语义单点）。加载失败路径沿用原语义：console.error + 错误 toast。
 *
 * 协议表面（__all__）：loadCharacters / loadConversations /
 *   renderConversations / syncConversationListTitle / initListViews。
 */

import { characters, conversations } from './api.js';
import { showCharacterForm } from './components/character-form.js';
import { showCharacterWizard } from './components/character-wizard.js';
import { showConfirm, showAlert } from './components/confirm-dialog.js';
import { showModelSelector } from './components/model-selector.js';
import { downloadBlob, showError, showSuccess } from './utils.js';
import { characterCardHtml, conversationItemHtml } from './format.js';
import { state } from './state.js';
import { chatDom } from './chat.js';
import { getActiveTab, getTabs } from './tabs.js';
import { activateConversation } from './conversation-activation.js';
import { closeConversationsAndResettle } from './cascade.js';

// ══════════════════════════════════════════════════
// DOM 引用（本视图深模块持有 — index.html id 契约只读）
// ══════════════════════════════════════════════════

const $ = (sel) => document.querySelector(sel);

const dom = {
    // 角色
    characterGrid: $('#character-grid'),
    btnCreateCharacter: $('#btn-create-character'),
    btnImportCharacter: $('#btn-import-character'),
    characterImportInput: $('#character-import-input'),
    // 对话
    conversationList: $('#conversation-list'),
    btnNewChat: $('#btn-new-chat'),
};

// ── 协调层钩子（app.js 注入；缺省 no-op 兜底 — 未接线时调用不抛错）──
let switchView = () => {};

/** 事件绑定守卫：首次 initListViews 绑定后置位，重复调用仅更新钩子 */
let bound = false;

// ══════════════════════════════════════════════════
// 角色管理
// ══════════════════════════════════════════════════

/**
 * 加载角色列表（视图切换刷新 / init 数据加载共用）
 * 失败路径：console.error + 错误 toast（沿用收口前语义）。
 */
export async function loadCharacters() {
    if (!dom.characterGrid) return; // DOM 契约被破坏 → no-op（Falsify 兜底）
    try {
        state.characters = await characters.list();
        renderCharacters();
    } catch (err) {
        console.error('加载角色失败:', err);
        showError('加载角色列表失败');
    }
}

/** 渲染角色网格 + 四类按钮事件委托（开始对话 / 编辑 / 导出 / 删除） */
function renderCharacters() {
    const grid = dom.characterGrid;
    if (!grid) return;
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

// ══════════════════════════════════════════════════
// 模型选择 & 开始对话
// ══════════════════════════════════════════════════

/**
 * 开始与角色对话：模型选择 → 创建对话 → 切 chat 视图 → 激活会话 → 聚焦输入
 * @param {number} characterId - 角色 id
 */
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

/**
 * 加载对话列表（视图切换刷新 / init 数据加载 / 级联收口 reloadList 共用）
 * 失败路径：console.error + 错误 toast（沿用收口前语义）。
 */
export async function loadConversations() {
    if (!dom.conversationList) return; // DOM 契约被破坏 → no-op（Falsify 兜底）
    try {
        state.conversations = await conversations.list();
        renderConversations();
    } catch (err) {
        console.error('加载对话列表失败:', err);
        showError('加载对话列表失败');
    }
}

/**
 * 渲染对话列表（激活高亮按活动 tab 判定 — 单一事实来源）+ 打开/删除委托。
 * 供 activation / cascade / chat 钩子注入（renderConversations）。
 */
export function renderConversations() {
    const list = dom.conversationList;
    if (!list) return;
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

// ══════════════════════════════════════════════════
// 列表标题同步（DOM 手术 — 随 conversationList 归属迁入）
// ══════════════════════════════════════════════════

/**
 * 同步对话列表项标题（重命名成功后的 DOM 手术 — 只更新匹配会话项 .title
 * 文本，不重渲染列表；经 setChatHooks 注入给 chat.js 重命名回调调用，
 * 避免反向依赖）
 * @param {number|string} convId - 会话 id
 * @param {string} newTitle - 新标题
 */
export function syncConversationListTitle(convId, newTitle) {
    if (!dom.conversationList) return;
    dom.conversationList.querySelectorAll('.conversation-item').forEach((item) => {
        if (parseInt(item.dataset.id) === convId) {
            const titleDiv = item.querySelector('.title');
            if (titleDiv) titleDiv.textContent = newTitle;
        }
    });
}

// ══════════════════════════════════════════════════
// 对外入口
// ══════════════════════════════════════════════════

/** 绑定按钮事件（创建角色向导 / 导入文件选择 / 导入 change / 新聊天切角色视图） */
function bindEvents() {
    dom.btnCreateCharacter?.addEventListener('click', () => {
        showCharacterWizard(() => loadCharacters());
    });
    dom.btnImportCharacter?.addEventListener('click', () => {
        dom.characterImportInput?.click();
    });
    dom.characterImportInput?.addEventListener('change', handleCharacterImport);
    dom.btnNewChat?.addEventListener('click', () => {
        // 切换到角色视图让用户选角色
        switchView('characters');
    });
}

/**
 * 初始化列表视图：绑定按钮事件。幂等：重复调用仅更新 switchView 钩子、
 * 不重复绑定事件（search-view 先例）。DOM 契约被破坏（元素缺失）→ no-op
 * 不抛错（Falsify 兜底）。列表加载不发请求 —— 由协调层 init() / 视图切换
 * 调 loadCharacters / loadConversations 触发（懒加载语义保持）。
 * @param {object} [options]
 * @param {Function} [options.switchView] - (viewName) => void；开始对话创建
 *   对话后切 chat 视图、btnNewChat 切角色视图（未注入时 no-op 不抛错）
 */
export function initListViews({ switchView: sw } = {}) {
    if (typeof sw === 'function') switchView = sw;
    if (bound) return; // 幂等守卫：已绑定则早退（钩子已在上方更新）
    bindEvents();
    bound = true;
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 list-views.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'loadCharacters',
    'loadConversations',
    'renderConversations',
    'syncConversationListTitle',
    'initListViews',
];
