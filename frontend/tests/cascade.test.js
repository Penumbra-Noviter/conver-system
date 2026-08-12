/**
 * cascade 深模块测试（ARC-9 C1 从 app.js 提取的级联关闭收口）
 *
 * 覆盖：四入口（删角色 / 删对话 / 清空全部 / tab-bar 关最后 tab）共用的
 *   closeConversationsAndResettle 语义 ——
 *   closeTabs 收到预期 ids（经真实 tabs.js 状态断言）、wasActive 才重激活
 *   （activateConversation 收到 {saveCurrent:false}）、无剩余 tab → 空态（幂等）、
 *   活动 tab 未被关 → 不重激活、reloadList 分支、注入钩子调用序列。
 *
 * 测试即新模块接口契约：closeConversationsAndResettle 为唯一功能入口，
 * 依赖全部经 setCascadeHooks 注入（spy 断言调用序列与参数）。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

/** 加载全新 cascade + tabs 实例（tabs.js 是真实模块 — closeTabs 语义经其状态验证） */
async function loadModules() {
    vi.resetModules();
    const cascade = await import('../js/cascade.js');
    const tabs = await import('../js/tabs.js');
    return { cascade, tabs };
}

/** 构造已注入 spy 钩子的 cascade 实例；返回钩子 spy 集合 */
async function loadWithSpies() {
    const { cascade, tabs } = await loadModules();
    const hooks = {
        renderConversations: vi.fn(),
        loadConversations: vi.fn(),
        activateConversation: vi.fn(),
        showEmptyState: vi.fn(),
        refreshSendButton: vi.fn(),
    };
    cascade.setCascadeHooks(hooks);
    return { cascade, tabs, hooks };
}

/** 打开 n 个 tab（conversationId = 1..n），返回 ids */
function openTabs(tabs, n) {
    for (let i = 1; i <= n; i++) tabs.openTab(i);
    return Array.from({ length: n }, (_, i) => i + 1);
}

describe('closeConversationsAndResettle — 四入口统一收口语义', () => {
    beforeEach(() => { vi.restoreAllMocks(); });

    it('删角色入口:ids=[11,12] reloadList:true → closeTabs 生效 + wasActive 时重激活(saveCurrent:false) + loadConversations', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);
        tabs.activateTab(1); // 活动 tab = 1（被关集合内 → wasActive）

        await cascade.closeConversationsAndResettle({ ids: [1, 2], reloadList: true });

        // closeTabs 收到预期 ids：两个 tab 都被关闭
        expect(tabs.getTabs()).toHaveLength(0);
        expect(tabs.getActiveTab()).toBeNull();
        // wasActive → 无剩余 tab → 空态（不调 activateConversation）
        expect(hooks.activateConversation).not.toHaveBeenCalled();
        expect(hooks.showEmptyState).toHaveBeenCalledTimes(1);
        // 发送按钮刷新 + reloadList 分支
        expect(hooks.refreshSendButton).toHaveBeenCalledTimes(1);
        expect(hooks.loadConversations).toHaveBeenCalledTimes(1);
        expect(hooks.renderConversations).not.toHaveBeenCalled();
    });

    it('删对话入口:ids=[1] 活动 tab 被关 → 右邻居激活,activateConversation 收到 (2,{saveCurrent:false})', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);
        tabs.activateTab(1);

        await cascade.closeConversationsAndResettle({ ids: [1], reloadList: true });

        expect(tabs.getTabs().map((t) => t.conversationId)).toEqual([2]);
        expect(tabs.getActiveTab()?.conversationId).toBe(2);
        expect(hooks.activateConversation).toHaveBeenCalledTimes(1);
        expect(hooks.activateConversation).toHaveBeenCalledWith(2, { saveCurrent: false });
        expect(hooks.showEmptyState).not.toHaveBeenCalled();
        expect(hooks.loadConversations).toHaveBeenCalledTimes(1);
    });

    it('活动 tab 未被关 → 不重激活（视图停留原地）,仅刷新按钮 + 重渲染列表', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);
        tabs.activateTab(2); // 活动 tab = 2，不在被关集合

        await cascade.closeConversationsAndResettle({ ids: [1], reloadList: false });

        expect(tabs.getTabs().map((t) => t.conversationId)).toEqual([2]);
        expect(tabs.getActiveTab()?.conversationId).toBe(2);
        expect(hooks.activateConversation).not.toHaveBeenCalled();
        expect(hooks.showEmptyState).not.toHaveBeenCalled();
        expect(hooks.refreshSendButton).toHaveBeenCalledTimes(1);
        expect(hooks.renderConversations).toHaveBeenCalledTimes(1);
        expect(hooks.loadConversations).not.toHaveBeenCalled();
    });

    it('清空全部入口:ids="all" reloadList:false → 全部 tab 关闭 + 空态 + 仅重渲染列表', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);

        await cascade.closeConversationsAndResettle({ ids: 'all', reloadList: false });

        expect(tabs.getTabs()).toHaveLength(0);
        expect(hooks.showEmptyState).toHaveBeenCalledTimes(1);
        expect(hooks.activateConversation).not.toHaveBeenCalled();
        expect(hooks.refreshSendButton).toHaveBeenCalledTimes(1);
        expect(hooks.renderConversations).toHaveBeenCalledTimes(1);
        expect(hooks.loadConversations).not.toHaveBeenCalled();
    });

    it('tab-bar 关最后 tab 入口:ids=[] 已无 tab → 空态幂等,无 closeTabs 调用,无崩溃', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();

        await cascade.closeConversationsAndResettle({ ids: [], reloadList: false });
        await cascade.closeConversationsAndResettle({ ids: [], reloadList: false });

        expect(tabs.getTabs()).toHaveLength(0);
        expect(hooks.showEmptyState).toHaveBeenCalledTimes(2);
        expect(hooks.activateConversation).not.toHaveBeenCalled();
        expect(hooks.refreshSendButton).toHaveBeenCalledTimes(2);
        expect(hooks.renderConversations).toHaveBeenCalledTimes(2);
    });

    it('ids=[] 但仍有 tab（非活动被关集合为空）→ 不关任何 tab,不重激活,列表重渲染', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);

        await cascade.closeConversationsAndResettle({ ids: [], reloadList: false });

        expect(tabs.getTabs()).toHaveLength(2);
        expect(tabs.getActiveTab()?.conversationId).toBe(2);
        expect(hooks.activateConversation).not.toHaveBeenCalled();
        expect(hooks.showEmptyState).not.toHaveBeenCalled();
        expect(hooks.renderConversations).toHaveBeenCalledTimes(1);
    });

    it('ids="all" 展开为当前全部 tab 的 conversationId（closeTabs 逐 id 生效）', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 3);
        tabs.activateTab(2);

        await cascade.closeConversationsAndResettle({ ids: 'all', reloadList: true });

        expect(tabs.getTabs()).toHaveLength(0);
        expect(hooks.showEmptyState).toHaveBeenCalledTimes(1);
        expect(hooks.loadConversations).toHaveBeenCalledTimes(1);
    });

    it('调用顺序:重激活 → refreshSendButton → loadConversations/renderConversations', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);
        tabs.activateTab(1);

        await cascade.closeConversationsAndResettle({ ids: [1], reloadList: true });

        const order = hooks.activateConversation.mock.invocationCallOrder;
        expect(hooks.refreshSendButton.mock.invocationCallOrder[0]).toBeGreaterThan(order[0]);
        expect(hooks.loadConversations.mock.invocationCallOrder[0])
            .toBeGreaterThan(hooks.refreshSendButton.mock.invocationCallOrder[0]);
    });

    it('钩子未注入时(默认 no-op)调用不抛错 — 关 tab 本身仍生效', async () => {
        const { cascade, tabs } = await loadModules();
        openTabs(tabs, 2);
        tabs.activateTab(1);

        await expect(cascade.closeConversationsAndResettle({ ids: [1, 2], reloadList: true }))
            .resolves.toBeUndefined();
        expect(tabs.getTabs()).toHaveLength(0);
    });

    it('Falsify:ids 为非法类型(非 all 非数组,如数字) → 视为空集,不关任何 tab,不崩溃', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);

        await cascade.closeConversationsAndResettle({ ids: 42, reloadList: false });

        expect(tabs.getTabs()).toHaveLength(2);
        expect(hooks.activateConversation).not.toHaveBeenCalled();
        expect(hooks.showEmptyState).not.toHaveBeenCalled();
        expect(hooks.renderConversations).toHaveBeenCalledTimes(1);
    });

    it('Falsify:重激活目标在 await 前被并发关闭 → activateConversation 仍收到其 id(行为保持),不崩溃', async () => {
        const { cascade, tabs, hooks } = await loadWithSpies();
        openTabs(tabs, 2);
        tabs.activateTab(1);
        // 钩子内模拟并发:重激活期间另一个删除把剩余 tab 也关了
        hooks.activateConversation.mockImplementation(async () => {
            tabs.closeTabs([2]);
        });

        await expect(cascade.closeConversationsAndResettle({ ids: [1], reloadList: true }))
            .resolves.toBeUndefined();
        expect(hooks.activateConversation).toHaveBeenCalledWith(2, { saveCurrent: false });
    });
});
