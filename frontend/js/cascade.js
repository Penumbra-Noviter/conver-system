/**
 * Conver System — 级联关闭收口（深模块，ARC-9 C1 从 app.js 提取）
 *
 * 职责：删角色级联 / 删会话 / 清空全部对话 / tab-bar 关最后 tab 四入口共用
 *   的「关 tab → 重定位 → 空态 → 刷新」统一收口。编排区（app.js）只保留
 *   调用点与接线，本模块持有唯一的级联语义实现。
 *
 * 统一语义（ARC-2，逐行迁入保持）：
 *   - closeTabs 批量关闭（tabs.js 原语：内部先 abort 各在途流式，单次 commit/notify）
 *   - 仅当被关集合含活动 tab（wasActive）才重激活视图（saveCurrent:false —
 *     被关 tab 的 DOM 草稿/滚动不得污染新活动 tab 缓存）；无剩余 tab → 空态
 *   - 活动 tab 未被关 → 不重激活，视图停留原地（消除删角色路径无条件重激活分歧）
 *   - 已无任何 tab（tab-bar 已关最后 tab / 空集清空）→ 空态兜底（幂等）
 *   - reloadList 时 loadConversations（删会话/删角色路径）；否则仅重渲染列表
 *     （清空路径调用方已置空 state.conversations）
 *
 * 依赖方向：cascade.js → tabs.js（getTabs/closeTabs/getActiveTab，只读消费）；
 *   其余依赖（renderConversations / loadConversations / activateConversation /
 *   showEmptyState / refreshSendButton）经 setCascadeHooks 注入 —— 避免反向
 *   import 编排区（G7 注入钩子模式，与 setActivationHooks / setConversationsRefresher
 *   同构）。注入钩子默认 no-op 兜底：未接线时调用不抛错，关 tab 本身仍生效。
 *
 * 协议表面（__all__）：setCascadeHooks / closeConversationsAndResettle。
 */

import { closeTabs, getActiveTab, getTabs } from './tabs.js';

// ── 编排区注入钩子（app.js 接线时注入；缺失时 no-op 兜底）──
let hooks = {
    renderConversations: () => {},
    loadConversations: async () => {},
    activateConversation: async () => {},
    showEmptyState: () => {},
    refreshSendButton: () => {},
};

/**
 * 注入级联收口的编排区依赖（app.js 初始化时调用；部分注入按 key 合并）
 * @param {object} h - 钩子集合
 * @param {Function} [h.renderConversations] - 重渲染对话列表（高亮/空态）
 * @param {Function} [h.loadConversations] - 重新拉取对话列表（reloadList 分支）
 * @param {Function} [h.activateConversation] - 重激活活动 tab（saveCurrent:false 语义见上）
 * @param {Function} [h.showEmptyState] - 无剩余 tab 时的空态渲染
 * @param {Function} [h.refreshSendButton] - 发送按钮两态刷新
 */
export function setCascadeHooks(h) {
    hooks = { ...hooks, ...h };
}

/**
 * 级联关闭会话 tab 的统一收口（删角色 / 删会话 / 清空全部 / tab-bar 关最后 tab 共用）：
 *   closeTabs 批量关闭（内部先 abort 各在途流式，单次 commit/notify）
 *   → 重定位活动 tab 视图 → refreshSendButton → reloadList 时 loadConversations
 *   （否则仅重渲染列表高亮/空态）。
 * 统一语义：仅当被关集合含活动 tab（wasActive）才重激活视图（saveCurrent:false —
 *   被关 tab 的 DOM 草稿/滚动不得污染新活动 tab 缓存；无剩余 tab → 空态）；
 *   活动 tab 未被关 → 不重激活，视图停留原地；已无任何 tab → 空态兜底（幂等）。
 * @param {object} [options]
 * @param {Array<number|string>|'all'} [options.ids='all'] - 要关闭的会话 id 列表；
 *   'all' 为当前全部 tab；非数组且非 'all' 视为空集
 * @param {boolean} [options.reloadList=false] - 关闭后是否重新拉取对话列表
 *   （删会话/删角色路径；清空路径调用方已置空 state.conversations，仅重渲染即可）
 */
export async function closeConversationsAndResettle({ ids = 'all', reloadList = false } = {}) {
    const doomed = ids === 'all'
        ? getTabs().map((t) => t.conversationId)
        : (Array.isArray(ids) ? ids : []);
    const activeBefore = getActiveTab()?.conversationId ?? null;
    const wasActive = activeBefore !== null && doomed.includes(activeBefore);
    if (doomed.length > 0) closeTabs(doomed);
    if (wasActive || getTabs().length === 0) {
        const active = getActiveTab();
        if (active) {
            await hooks.activateConversation(active.conversationId, { saveCurrent: false });
        } else {
            hooks.showEmptyState();
        }
    }
    hooks.refreshSendButton();
    if (reloadList) {
        await hooks.loadConversations();
    } else {
        hooks.renderConversations();
    }
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 cascade.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'setCascadeHooks',
    'closeConversationsAndResettle',
];
