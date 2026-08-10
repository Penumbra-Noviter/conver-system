import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
    openTab,
    activateTab,
    closeTab,
    closeAllTabs,
    getActiveTab,
    getTab,
    getTabs,
    updateTab,
    serialize,
    restore,
    restoreFromStorage,
    onTabsChanged,
    __all__,
} from '../js/tabs.js';

// ── 测试辅助 ──

/** 读取 sessionStorage 中的序列化 tab 集（键名由模块内部决定，只验证内容） */
function readStored() {
    const keys = Object.keys(sessionStorage);
    if (keys.length === 0) return null;
    return JSON.parse(sessionStorage.getItem(keys[0]));
}

beforeEach(() => {
    sessionStorage.clear();
    closeAllTabs();
});

describe('openTab', () => {
    it('新建 tab 为初始形态（含全部会话级字段）', () => {
        const tab = openTab(1);
        expect(tab).toEqual({
            conversationId: 1,
            characterId: null,
            title: '',
            messages: [],
            scrollTop: 0,
            draft: '',
            isStreaming: false,
            activeStream: null,
            phase: 'idle',
        });
        expect(getActiveTab()).toBe(tab);
    });

    it('按 conversationId 去重：已存在仅激活并返回既有对象', () => {
        const first = openTab(1);
        openTab(2);
        const again = openTab(1);
        expect(again).toBe(first);
        expect(getTabs()).toHaveLength(2);
        expect(getActiveTab()).toBe(first);
    });

    it('多个会话依次打开，最后打开的为活动 tab', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        expect(getTabs().map((t) => t.conversationId)).toEqual([1, 2, 3]);
        expect(getActiveTab().conversationId).toBe(3);
    });

    it('null/undefined 入参 no-op，不建 tab', () => {
        expect(openTab(null)).toBeNull();
        expect(openTab(undefined)).toBeNull();
        expect(getTabs()).toHaveLength(0);
    });
});

describe('activateTab', () => {
    it('切换活动 tab', () => {
        openTab(1);
        openTab(2);
        activateTab(1);
        expect(getActiveTab().conversationId).toBe(1);
    });

    it('目标不存在 → no-op，活动不变、不抛错', () => {
        openTab(1);
        activateTab(999);
        expect(getActiveTab().conversationId).toBe(1);
        expect(getTabs()).toHaveLength(1);
    });
});

describe('closeTab', () => {
    it('关闭活动 tab 后激活右邻居', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(1);
        closeTab(1);
        expect(getActiveTab().conversationId).toBe(2);
        expect(getTabs().map((t) => t.conversationId)).toEqual([2, 3]);
    });

    it('无右邻居时激活左邻居', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(3);
        closeTab(3);
        expect(getActiveTab().conversationId).toBe(2);
    });

    it('关闭非活动 tab 不影响活动 tab', () => {
        openTab(1);
        openTab(2);
        closeTab(2);
        expect(getActiveTab().conversationId).toBe(1);
    });

    it('关最后一个 tab → activeTab 为 null', () => {
        openTab(7);
        closeTab(7);
        expect(getActiveTab()).toBeNull();
        expect(getTabs()).toHaveLength(0);
    });

    it('关闭不存在的 tab → no-op，不抛错、无变更', () => {
        openTab(1);
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        closeTab(999);
        off();
        expect(fn).not.toHaveBeenCalled();
        expect(getTabs()).toHaveLength(1);
    });
});

describe('closeAllTabs', () => {
    it('清空全部 tab 与活动 tab', () => {
        openTab(1);
        openTab(2);
        closeAllTabs();
        expect(getTabs()).toHaveLength(0);
        expect(getActiveTab()).toBeNull();
    });
});

describe('updateTab', () => {
    it('浅合并 patch（标题/流式阶段/消息缓存）', () => {
        const tab = openTab(1);
        updateTab(1, { title: '新标题', phase: 'streaming', isStreaming: true });
        expect(tab.title).toBe('新标题');
        expect(tab.phase).toBe('streaming');
        expect(tab.isStreaming).toBe(true);
        expect(tab.draft).toBe('');
    });

    it('对不存在的 conversationId 幂等 no-op（关流式中的 tab 后异步写回场景）', () => {
        openTab(1);
        expect(() => updateTab(999, { phase: 'done', messages: [{ role: 'assistant' }] }))
            .not.toThrow();
        expect(getTabs()).toHaveLength(1);
        expect(getTabs()[0].phase).toBe('idle');
    });

    it('conversationId 是身份键，不可经 patch 改写', () => {
        const tab = openTab(1);
        updateTab(1, { conversationId: 2, title: 'x' });
        expect(tab.conversationId).toBe(1);
        expect(getTab(1)).toBe(tab);
        expect(getTab(2)).toBeUndefined();
    });

    it('内容更新触发 onTabsChanged（tab 条状态指示随 phase 刷新）', () => {
        openTab(1);
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        updateTab(1, { phase: 'error' });
        off();
        expect(fn).toHaveBeenCalledTimes(1);
    });
});

describe('serialize / sessionStorage', () => {
    it('serialize 只返回 ids + activeId，不含消息/草稿等缓存', () => {
        openTab(1);
        openTab(2);
        updateTab(1, {
            messages: [{ role: 'user', content: 'hi' }],
            draft: '草稿内容',
            scrollTop: 42,
            isStreaming: true,
        });
        expect(serialize()).toEqual({ ids: [1, 2], activeId: 2 });
    });

    it('结构性变更写入 sessionStorage；updateTab 内容更新不写', () => {
        openTab(1);
        openTab(2);
        updateTab(2, { draft: '草稿', phase: 'thinking' });
        const stored = readStored();
        expect(stored).toEqual({ ids: [1, 2], activeId: 2 });
    });
});

describe('restore', () => {
    it('serialize → restore 往返一致（ids 与 activeId）', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(2);
        const snapshot = serialize();
        closeAllTabs();
        restore(snapshot, { isValidId: () => true });
        expect(serialize()).toEqual({ ids: [1, 2, 3], activeId: 2 });
    });

    it('经 isValidId 过滤已删除会话；activeId 失效回退首个有效', () => {
        openTab(1);
        openTab(2);
        openTab(3);
        activateTab(2);
        const snapshot = serialize(); // { ids: [1,2,3], activeId: 2 }
        closeAllTabs();
        restore(snapshot, { isValidId: (id) => id !== 2 });
        expect(serialize()).toEqual({ ids: [1, 3], activeId: 1 });
    });

    it('全失效 → 空集，activeTab 为 null', () => {
        openTab(1);
        const snapshot = serialize();
        closeAllTabs();
        const active = restore(snapshot, { isValidId: () => false });
        expect(active).toBeNull();
        expect(getTabs()).toHaveLength(0);
        expect(serialize()).toEqual({ ids: [], activeId: null });
    });

    it('恢复的 tab 一律非流式（phase idle、isStreaming false、activeStream null）', () => {
        openTab(1);
        updateTab(1, { phase: 'streaming', isStreaming: true, activeStream: { abort: () => {} } });
        const snapshot = serialize();
        closeAllTabs();
        restore(snapshot, { isValidId: () => true });
        const tab = getTab(1);
        expect(tab.phase).toBe('idle');
        expect(tab.isStreaming).toBe(false);
        expect(tab.activeStream).toBeNull();
        expect(tab.messages).toEqual([]);
        expect(tab.draft).toBe('');
    });

    it('serialized 非法（null / 非对象 / 缺 ids）→ 空集，不抛错', () => {
        expect(() => restore(null)).not.toThrow();
        expect(getTabs()).toHaveLength(0);
        expect(() => restore('garbage')).not.toThrow();
        expect(() => restore({ activeId: 1 })).not.toThrow();
        expect(getTabs()).toHaveLength(0);
    });

    it('serialized 中重复 id 去重', () => {
        restore({ ids: [1, 1, 2], activeId: 2 }, { isValidId: () => true });
        expect(serialize()).toEqual({ ids: [1, 2], activeId: 2 });
    });
});

describe('restoreFromStorage（init 刷新恢复集成辅助 — P6.5-4）', () => {
    it('有效存储记录 → 恢复 tab 集与活动 tab，且写回存储', () => {
        closeAllTabs(); // 清空内存与存储，模拟刷新后的空状态（先于种子写入，避免被覆盖）
        sessionStorage.setItem('conver.tabs.v1', JSON.stringify({ ids: [1, 2], activeId: 2 }));
        const active = restoreFromStorage({ isValidId: () => true });
        expect(active?.conversationId).toBe(2);
        expect(serialize()).toEqual({ ids: [1, 2], activeId: 2 });
        // 恢复写回存储（键内容与内存一致）
        const stored = Object.values(sessionStorage).map((v) => JSON.parse(v)).find((v) => v?.ids);
        expect(stored).toEqual({ ids: [1, 2], activeId: 2 });
    });

    it('isValidId 过滤已删会话；activeId 失效回退首个有效', () => {
        sessionStorage.setItem('conver.tabs.v1', JSON.stringify({ ids: [1, 2], activeId: 2 }));
        const active = restoreFromStorage({ isValidId: (id) => id === 1 });
        expect(active?.conversationId).toBe(1);
        expect(serialize()).toEqual({ ids: [1], activeId: 1 });
    });

    it('存储 JSON 损坏 → 空集，不抛错', () => {
        sessionStorage.setItem('conver.tabs.v1', '{broken json');
        expect(() => restoreFromStorage()).not.toThrow();
        expect(getTabs()).toHaveLength(0);
        expect(getActiveTab()).toBeNull();
    });

    it('无存储记录 → 空集，不抛错', () => {
        expect(() => restoreFromStorage()).not.toThrow();
        expect(getTabs()).toHaveLength(0);
        expect(getActiveTab()).toBeNull();
    });

    it('恢复的 tab 一律非流式（phase idle、isStreaming false、activeStream null）', () => {
        sessionStorage.setItem('conver.tabs.v1', JSON.stringify({ ids: [1], activeId: 1 }));
        restoreFromStorage({ isValidId: () => true });
        const tab = getTab(1);
        expect(tab.phase).toBe('idle');
        expect(tab.isStreaming).toBe(false);
        expect(tab.activeStream).toBeNull();
        expect(tab.messages).toEqual([]);
    });
});

describe('onTabsChanged', () => {
    it('结构性变更各触发一次通知；无变更操作不通知', () => {
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        openTab(1); // 开 → 1
        openTab(2); // 开 → 2
        openTab(1); // 已存在但非活动 → 激活 → 3
        openTab(1); // 已是活动 → 无变更
        activateTab(2); // → 4
        activateTab(2); // 已是活动 → 无变更
        closeTab(3); // 不存在 → 无变更
        closeTab(2); // → 5
        closeAllTabs(); // → 6
        restore({ ids: [1], activeId: 1 }, { isValidId: () => true }); // → 7
        off();
        expect(fn).toHaveBeenCalledTimes(7);
    });

    it('返回的取消订阅函数生效', () => {
        const fn = vi.fn();
        const off = onTabsChanged(fn);
        off();
        openTab(1);
        expect(fn).not.toHaveBeenCalled();
    });
});

describe('协议表面', () => {
    it('__all__ 收口全部公开函数', () => {
        expect(__all__.sort()).toEqual([
            'activateTab',
            'closeAllTabs',
            'closeTab',
            'getActiveTab',
            'getTab',
            'getTabs',
            'onTabsChanged',
            'openTab',
            'restore',
            'restoreFromStorage',
            'serialize',
            'updateTab',
        ]);
    });
});
