import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createStreamSession, mergeFreshList, settleTurn, __all__ } from '../js/stream-session.js';
import { messages } from '../js/api.js';

// ══════════════════════════════════════════════════════════════════
// StreamSession 深模块单测 — 全部经公共 seam(createStreamSession /
// mergeFreshList)驱动,断言模块状态与缓存写回,不触碰内部实现。
// 行为对齐 P6.5 决策:revision 守卫 / settleIndex 位置结算 / 终态守卫 /
// R2 失败路径不清并发流占位。
// ══════════════════════════════════════════════════════════════════

/** 构造服务端消息(带 id 的 settled 消息) */
const msg = (id, role, content, extra = {}) => ({ id, role, content, ...extra });
/** 构造流式占位消息(客户端 streaming 标记) */
const streaming = (content) => ({ role: 'assistant', content, streaming: true });

// ══════════════════════════════════════════════════
// mergeFreshList 纯函数三分支(fresh / stale / 失败)
// ══════════════════════════════════════════════════

describe('mergeFreshList — fresh 分支(长度未变 → 整体替换 + 活动渲染)', () => {
    it('长度未变 → 整体替换为服务端列表,render: true', () => {
        const tab = { messages: [msg(1, 'user', 'hi'), streaming('你好')] };
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const result = mergeFreshList(tab, 2, fresh, { settleIndex: 1, messageId: 101 });
        expect(result.render).toBe(true);
        expect(result.messages).toBe(fresh); // 直接采用服务端数组(引用)
    });

    it('fresh 分支与 settleIndex 无关:即使 settleIndex 位置仍 streaming 也整体替换', () => {
        const tab = { messages: [msg(1, 'user', 'hi'), streaming('你好')] };
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const result = mergeFreshList(tab, 2, fresh, { settleIndex: 1, messageId: 101 });
        expect(result.messages).toEqual(fresh);
        expect(result.messages.filter((m) => m.streaming)).toEqual([]);
    });
});

describe('mergeFreshList — stale 分支(长度变了 → 仅按位置结算 streaming 标记)', () => {
    it('settleIndex 位置仍 streaming → 仅该位置结算(streaming:false + id),其余不动,render: false', () => {
        const tab = {
            messages: [msg(1, 'user', 'hi'), streaming('你好'), msg(3, 'user', 'again')],
        };
        const result = mergeFreshList(tab, 2, [], { settleIndex: 1, messageId: 101 });
        expect(result.render).toBe(false);
        expect(result.messages).toHaveLength(3);
        expect(result.messages[1]).toEqual({ role: 'assistant', content: '你好', streaming: false, id: 101 });
        expect(result.messages[0]).toBe(tab.messages[0]); // 其余消息引用不动
        expect(result.messages[2]).toBe(tab.messages[2]);
        expect(result.messages.filter((m) => m.streaming)).toEqual([]);
    });

    it('位置失配(FIX-A 同字节双流):settleIndex 位置已非本流占位 → 不误结算,新流 streaming 占位保持', () => {
        // settleIndex=1 处是 user 消息(本流占位已被新流 token 替换);缓存无同 id 消息
        const tab = {
            messages: [msg(1, 'user', '第一条'), msg(3, 'user', '第二条'), streaming('你好')],
        };
        const result = mergeFreshList(tab, 2, [], { settleIndex: 1, messageId: 101 });
        expect(result.render).toBe(false);
        expect(result.messages).toBe(tab.messages); // 原样,不结算
        expect(result.messages.filter((m) => m.streaming)).toHaveLength(1);
        expect(result.messages.some((m) => m.id === 101)).toBe(false);
    });

    it('幂等:settleIndex=-1(无本流占位)→ 不动,不结算不追加', () => {
        const tab = { messages: [msg(1, 'user', 'hi')] };
        // revision 0 ≠ 长度 1 → 走 stale 分支;settleIndex=-1 → 无占位可结算
        const result = mergeFreshList(tab, 0, [], { settleIndex: -1, messageId: 101 });
        expect(result.render).toBe(false);
        expect(result.messages).toBe(tab.messages);
    });

    it('settleIndex 越界(缓存被替换后缩短)→ 不抛错、不动', () => {
        const tab = { messages: [msg(1, 'user', 'hi')] };
        expect(() => mergeFreshList(tab, 3, [], { settleIndex: 2, messageId: 101 })).not.toThrow();
        const result = mergeFreshList(tab, 3, [], { settleIndex: 2, messageId: 101 });
        expect(result.messages).toBe(tab.messages);
        expect(result.render).toBe(false);
    });

    // ── S-09（F-60）并发漂移不静默丢弃（stale + settleIndex=-1 + anchor=null 兜底）──

    it('F-60:stale + settleIndex=-1 + anchor=null + messageId/content → 渲染服务端列表（不静默丢弃）', () => {
        // 重生成场景：并发使本地缓存长度变化（stale，revision 2 → 长度 3），本流无占位可结算
        // （settleIndex=-1）且无 user anchor（重生成路径）。服务端列表含新回复(3)与并发消息(4)
        // — 必须写回渲染，不得静默丢弃。
        const tab = {
            messages: [msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复'), msg(4, 'user', '并发')],
        };
        const server = [
            msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复'),
            msg(4, 'user', '并发'), msg(3, 'assistant', '新回复'),
        ];
        const result = mergeFreshList(tab, 2, server, {
            settleIndex: -1, anchor: null, messageId: 3, content: '新回复',
        });
        expect(result.render).toBe(true);
        expect(result.messages).toBe(server); // 服务端列表权威
    });

    it('F-60:stale + messageId 本地已存在 → 原位替换 content + 清除 streaming（幂等）', () => {
        // 并发流已把新回复以 streaming 形态写入缓存（同 id 不同位置）→ 按 messageId 原位收尾。
        const tab = {
            messages: [
                msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复'),
                { role: 'assistant', content: '新回复', id: 3, streaming: true },
            ],
        };
        const server = [msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复'), msg(4, 'user', '并发')];
        const result = mergeFreshList(tab, 2, server, {
            settleIndex: -1, anchor: null, messageId: 3, content: '新回复改',
        });
        expect(result.render).toBe(true);
        expect(result.messages).toEqual([
            msg(1, 'user', '你好'),
            msg(2, 'assistant', '旧回复'),
            { role: 'assistant', content: '新回复改', id: 3, streaming: false },
        ]);
        expect(result.messages.filter((m) => m.streaming)).toEqual([]);
    });
});

describe('mergeFreshList — 失败分支(msgs=null → 位置感知追加,不清并发流占位 — 根治 R2)', () => {
    it('本流占位仍在 settleIndex → 移除占位 + 原位插入最终消息(id),render: true', () => {
        const tab = { messages: [msg(1, 'user', 'hi'), streaming('你好')] };
        const result = mergeFreshList(tab, 2, null, { anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(result.render).toBe(true);
        expect(result.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', id: 101 },
        ]);
        expect(result.messages.filter((m) => m.streaming)).toEqual([]);
    });

    it('并发流占位(其他位置)不被清除 — 根治 R2', () => {
        const tab = {
            messages: [msg(1, 'user', 'hi'), streaming('你好'), msg(3, 'user', 'again'), streaming('回复2')],
        };
        const result = mergeFreshList(tab, 2, null, { anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(result.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', id: 101 },
            msg(3, 'user', 'again'),
            { role: 'assistant', content: '回复2', streaming: true },
        ]);
    });

    it('本流占位已被新流 token 替换(位置非 streaming、缓存无同 id)→ 在发起位置插入,恢复时间序', () => {
        const tab = {
            messages: [msg(1, 'user', '第一条'), msg(3, 'user', '第二条'), streaming('回复2')],
        };
        const result = mergeFreshList(tab, 2, null, { anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(result.messages).toEqual([
            msg(1, 'user', '第一条'),
            { role: 'assistant', content: '你好', id: 101 },
            msg(3, 'user', '第二条'),
            { role: 'assistant', content: '回复2', streaming: true },
        ]);
    });

    it('幂等:缓存已含同 id 消息(被并发流 fresh 替换结算)→ 不重复插入,render: false', () => {
        const tab = { messages: [msg(1, 'user', 'hi'), { role: 'assistant', content: '你好', id: 101 }] };
        const result = mergeFreshList(tab, 2, null, { anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(result.render).toBe(false);
        expect(result.messages).toBe(tab.messages);
        expect(result.messages.filter((m) => m.id === 101)).toHaveLength(1);
    });

    it('settleIndex=-1(从未创建占位,如零 token 流)→ 追加到尾部', () => {
        const tab = { messages: [msg(1, 'user', 'hi')] };
        const result = mergeFreshList(tab, 1, null, { anchor: null, messageId: 101, content: '你好' });
        expect(result.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', id: 101 },
        ]);
        expect(result.render).toBe(true);
    });

    it('非流式复用(messageId 缺省)→ 尾部追加无 id 消息', () => {
        const tab = { messages: [msg(1, 'user', 'hi')] };
        const result = mergeFreshList(tab, 1, null, { anchor: null, content: '回复' });
        expect(result.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '回复' }, // 无 id 字段
        ]);
        expect(result.render).toBe(true);
    });

    // ── S-09（F-58）重生成失败兜底：按被顶替旧消息身份原位替换，不尾部追加 ──

    it('F-58:anchor=null + replaceId → 按被顶替旧回复 id 原位替换（不尾部追加、无旧残留）', () => {
        // 重生成失败场景：后端已截断旧回复并生成新回复，本地重载失败（msgs=null）→
        // 本地缓存仍含旧回复(2)。replaceId=2 指认重生成目标 → 原位替换为带服务端 id(3) 的新回复。
        const tab = { messages: [msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复')] };
        const result = mergeFreshList(tab, 2, null, {
            settleIndex: -1, anchor: null, replaceId: 2, messageId: 3, content: '新回复',
        });
        expect(result.render).toBe(true);
        expect(result.messages).toEqual([
            msg(1, 'user', '你好'),
            { role: 'assistant', content: '新回复', id: 3 },
        ]);
        expect(result.messages).toHaveLength(2); // 无额外尾部追加
        expect(result.messages.some((m) => m.content === '旧回复')).toBe(false); // 无旧残留
    });

    it('F-58:幂等 — 新回复已含同 id（被并发结算）→ replaceId 不重复替换', () => {
        const tab = { messages: [msg(1, 'user', '你好'), { role: 'assistant', content: '新回复', id: 3 }] };
        const result = mergeFreshList(tab, 2, null, {
            settleIndex: -1, anchor: null, replaceId: 2, messageId: 3, content: '新回复',
        });
        expect(result.render).toBe(false);
        expect(result.messages).toBe(tab.messages);
        expect(result.messages.filter((m) => m.id === 3)).toHaveLength(1);
    });

    it('F-58:兜底 — replaceId 在缓存中不存在（旧消息已被并发移除）→ 回落尾部追加（既有语义保持）', () => {
        const tab = { messages: [msg(1, 'user', '你好')] };
        const result = mergeFreshList(tab, 1, null, {
            settleIndex: -1, anchor: null, replaceId: 99, messageId: 3, content: '新回复',
        });
        expect(result.render).toBe(true);
        expect(result.messages).toEqual([
            msg(1, 'user', '你好'),
            { role: 'assistant', content: '新回复', id: 3 },
        ]);
    });
});

describe('mergeFreshList — 入参防御', () => {
    it('tab 为 null / messages 缺失 → 安全返回空结果,不抛错', () => {
        expect(mergeFreshList(null, 0, [], {})).toEqual({ messages: [], render: false });
        expect(mergeFreshList({ messages: undefined }, 0, [], {})).toEqual({ messages: [], render: false });
    });

    it('msgs=null 且长度未变 → 走失败分支而非 fresh(不能以 null 替换)', () => {
        const tab = { messages: [msg(1, 'user', 'hi'), streaming('你好')] };
        const result = mergeFreshList(tab, 2, null, { anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(result.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', id: 101 },
        ]);
    });
});

// ══════════════════════════════════════════════════
// createStreamSession 生命周期(零 DOM,经注入 seam 驱动)
// ══════════════════════════════════════════════════

/** 会话测试台:内存 tab + vi.fn 注入;updateTab 就地合并模拟 tabs.js 语义 */
function makeHarness({ initial = [], active = true, withListSpy = false } = {}) {
    const tab = {
        conversationId: 1,
        phase: 'thinking',
        isStreaming: true,
        activeStream: { abort: vi.fn() },
        messages: initial,
    };
    const deps = {
        convId: 1,
        getTab: vi.fn(() => tab),
        updateTab: vi.fn((id, patch) => Object.assign(tab, patch)),
        isActiveStream: vi.fn(() => active),
        renderMessages: vi.fn(),
        refreshSendButton: vi.fn(),
        refreshConversations: vi.fn(),
        onError: vi.fn(),
    };
    const listSpy = withListSpy ? vi.spyOn(messages, 'list') : null;
    const session = createStreamSession(deps);
    return { session, deps, tab, listSpy };
}

describe('createStreamSession — onToken(token 累积 / 缓存同步 / 活动归属)', () => {
    it('累积并返回全文;缓存尾部替换为 streaming 占位(活动/后台都写)', () => {
        const { session, deps, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        expect(session.onToken('你')).toBe('你');
        expect(session.onToken('好')).toBe('你好');
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', streaming: true },
        ]);
        expect(deps.updateTab).toHaveBeenLastCalledWith(1, {
            messages: [msg(1, 'user', 'hi'), { role: 'assistant', content: '你好', streaming: true }],
        });
    });

    it('phase 非 streaming 时更新一次(thinking → streaming),已在 streaming 不再重复更新', () => {
        const { session, deps } = makeHarness();
        session.onToken('x');
        session.onToken('y');
        const phaseCalls = deps.updateTab.mock.calls.filter(([, patch]) => patch.phase);
        expect(phaseCalls).toHaveLength(1);
        expect(phaseCalls[0]).toEqual([1, { phase: 'streaming' }]);
    });

    it('tab 缺失(已关闭)→ 不写缓存不崩溃,仍返回全文', () => {
        const { session, deps } = makeHarness();
        deps.getTab.mockReturnValue(undefined);
        expect(session.onToken('你好')).toBe('你好');
        expect(deps.updateTab).not.toHaveBeenCalled();
    });

    it('settled 后 token 忽略:返回 null 且不累积、不写缓存', () => {
        const { session, deps, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        session.onError(new Error('x')); // 进入终态(错误气泡已写)
        expect(session.onToken('y')).toBeNull();
        expect(tab.messages.filter((m) => m.streaming)).toHaveLength(0); // 未追加占位
        expect(tab.messages.some((m) => m.content === 'y')).toBe(false); // 未累积写入
    });

    it('onToken 阶段不触发任何渲染回调(DOM 增量由 chat.js 驱动)', () => {
        const { session, deps } = makeHarness();
        session.onToken('你好');
        expect(deps.renderMessages).not.toHaveBeenCalled();
        expect(deps.refreshSendButton).not.toHaveBeenCalled();
        expect(deps.refreshConversations).not.toHaveBeenCalled();
    });
});

describe('createStreamSession — onDone(完成/终态写回/三分支)', () => {
    it('终态写回发起 tab(isStreaming:false / activeStream:null / phase:done),按钮立即复位,列表刷新', async () => {
        const { session, deps, tab, listSpy } = makeHarness({ initial: [msg(1, 'user', 'hi')], withListSpy: true });
        listSpy.mockResolvedValue([]);
        await session.onDone(101);
        expect(tab.isStreaming).toBe(false);
        expect(tab.activeStream).toBeNull();
        expect(tab.phase).toBe('done');
        expect(deps.refreshSendButton).toHaveBeenCalledTimes(1);
        expect(deps.refreshConversations).toHaveBeenCalledTimes(1);
    });

    it('fresh:长度未变 → 整体替换 + 活动时渲染', async () => {
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const { session, deps, tab, listSpy } = makeHarness({
            initial: [msg(1, 'user', 'hi'), streaming('你好')],
            withListSpy: true,
        });
        listSpy.mockResolvedValue(fresh);
        await session.onDone(101);
        expect(tab.messages).toBe(fresh);
        expect(deps.renderMessages).toHaveBeenCalledTimes(1);
    });

    it('fresh:非活动(后台流)→ 缓存照写,不渲染', async () => {
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const { session, deps, tab, listSpy } = makeHarness({
            initial: [msg(1, 'user', 'hi'), streaming('你好')],
            active: false,
            withListSpy: true,
        });
        listSpy.mockResolvedValue(fresh);
        await session.onDone(101);
        expect(tab.messages).toBe(fresh); // 后台累积/写回保持
        expect(deps.renderMessages).not.toHaveBeenCalled();
    });

    it('stale(revision 守卫 F-1):list 在途期间连发新消息 → 旧快照不覆盖,仅按位置结算本流标记', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        const { session, deps, tab, listSpy } = makeHarness({
            initial: [msg(1, 'user', 'hi'), streaming('你好')],
            withListSpy: true,
        });
        listSpy.mockReturnValue(deferred.promise);
        const p = session.onDone(101);
        // 连发:同 tab 追加新 user 消息(长度 2 → 3)
        deps.updateTab(1, { messages: [...tab.messages, msg(3, 'user', 'again')] });
        // 旧 list 快照返回(不含连发消息的陈旧状态)
        deferred.resolve([msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')]);
        await p;
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', streaming: false, id: 101 },
            msg(3, 'user', 'again'),
        ]);
        expect(deps.renderMessages).not.toHaveBeenCalled(); // stale 仅缓存结算
    });

    it('list 在途期间 tab 关闭 → no-op 无崩溃,列表刷新仍执行', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        const { session, deps, listSpy } = makeHarness({
            initial: [msg(1, 'user', 'hi'), streaming('你好')],
            withListSpy: true,
        });
        listSpy.mockReturnValue(deferred.promise);
        const p = session.onDone(101);
        deps.getTab.mockReturnValue(undefined); // 发起 tab 被关闭
        deferred.resolve([msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')]);
        await expect(p).resolves.toBeUndefined(); // no-op 无崩溃
        expect(deps.refreshConversations).toHaveBeenCalledTimes(1);
        // 终态写回在捕获时已发出;关闭后不再有 messages 写回路径
        expect(deps.updateTab.mock.calls.filter(([, patch]) => patch.messages)).toHaveLength(0);
    });

    it('list 重载失败 → 位置感知写回(占位移除+原位插入 id)+ 活动渲染 + console.error', async () => {
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        const { session, deps, tab, listSpy } = makeHarness({
            initial: [msg(1, 'user', 'hi')],
            withListSpy: true,
        });
        session.onToken('你好'); // 经 seam 累积(占位由 onToken 写入)
        listSpy.mockRejectedValue(new Error('服务端故障'));
        await session.onDone(101);
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', id: 101 },
        ]);
        expect(deps.renderMessages).toHaveBeenCalledTimes(1);
        expect(errorSpy).toHaveBeenCalledWith('重新加载消息列表失败:', expect.any(Error));
        errorSpy.mockRestore();
    });

    it('onDone(null) + 有部分内容 → 位置感知写回(无 id),不重载列表', async () => {
        const { session, deps, tab, listSpy } = makeHarness({
            initial: [msg(1, 'user', 'hi')],
            withListSpy: true,
        });
        session.onToken('你好');
        await session.onDone(null);
        expect(tab.messages).toEqual([msg(1, 'user', 'hi'), { role: 'assistant', content: '你好' }]);
        expect(deps.renderMessages).toHaveBeenCalledTimes(1);
        expect(listSpy).not.toHaveBeenCalled();
        expect(deps.refreshConversations).toHaveBeenCalledTimes(1);
    });

    it('onDone(null) + 空内容 → no-op 不写缓存(与既有行为一致)', async () => {
        const { session, deps, tab, listSpy } = makeHarness({ initial: [msg(1, 'user', 'hi')], withListSpy: true });
        await session.onDone(null);
        expect(tab.messages).toEqual([msg(1, 'user', 'hi')]);
        expect(deps.updateTab.mock.calls.filter(([, patch]) => patch.messages)).toHaveLength(0);
        expect(listSpy).not.toHaveBeenCalled();
    });

    it('终态守卫:onDone 二次调用 → 忽略,不重复重载/写回', async () => {
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const { session, deps, tab, listSpy } = makeHarness({
            initial: [msg(1, 'user', 'hi'), streaming('你好')],
            withListSpy: true,
        });
        listSpy.mockResolvedValue(fresh);
        await session.onDone(101);
        await session.onDone(202);
        expect(listSpy).toHaveBeenCalledTimes(1);
        expect(deps.refreshSendButton).toHaveBeenCalledTimes(1);
        expect(tab.phase).toBe('done');
    });

    it('Falsify 三连发 interleaving + 三条 list 全部失败 → 消息零丢失、无崩溃(占位归属代理边界)', async () => {
        // 同 tab 三连发,三条 list 全部失败:流 A 占位被流 B token 清除,流 B 占位被
        // 流 C token 清除 — settleIndex 以「发起时刻尾位置」代理本流占位,极端场景下
        // 位置归属退化为近似(消息不携带流身份,位置匹配是协议边界,见模块 docstring)。
        // 断言:全部 6 条消息最终都在(零丢失),无崩溃,本流消息按位置插入。
        const tab = { conversationId: 1, phase: 'thinking', isStreaming: true, messages: [msg(1, 'user', 'u1')] };
        const deps = {
            convId: 1,
            getTab: () => tab,
            updateTab: (id, patch) => Object.assign(tab, patch),
            isActiveStream: () => true,
            renderMessages: vi.fn(),
            refreshSendButton: vi.fn(),
            refreshConversations: vi.fn(),
        };
        const listSpy = vi.spyOn(messages, 'list');
        const deferreds = [1, 2, 3].map(() => {
            const d = {};
            d.promise = new Promise((_, reject) => { d.reject = reject; });
            return d;
        });
        let listCall = 0;
        listSpy.mockImplementation(() => deferreds[listCall++].promise); // 每次调用取下一个 deferred
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        // 每个 session 在其 user 消息入缓存后创建(anchor = 本流 user 位置,append-only 永不移位)
        const sessionA = createStreamSession(deps);
        // 流 A:token + done(101),list 挂起
        sessionA.onToken('你好');
        const pA = sessionA.onDone(101);
        // 流 B:user 消息 → 创建 B(anchor=u2)→ token + done(102),list 挂起
        deps.updateTab(1, { messages: [...tab.messages, msg(2, 'user', 'u2')] });
        const sessionB = createStreamSession(deps);
        sessionB.onToken('回复2');
        const pB = sessionB.onDone(102);
        // 流 C:user 消息 → 创建 C(anchor=u3)→ token + done(103),list 挂起
        deps.updateTab(1, { messages: [...tab.messages, msg(3, 'user', 'u3')] });
        const sessionC = createStreamSession(deps);
        sessionC.onToken('回复3');
        const pC = sessionC.onDone(103);

        // 三条 list 依次失败
        deferreds[0].reject(new Error('服务端故障'));
        await pA;
        deferreds[1].reject(new Error('服务端故障'));
        await pB;
        deferreds[2].reject(new Error('服务端故障'));
        await pC;

        // 零丢失:user 3 条 + assistant 3 条(全部在场),无 streaming 残留,无崩溃
        // 顺序语义:anchor 引用定位保证每条回复插在自己的 user 之后(时间序成立)
        const { messages: msgs } = tab;
        expect(msgs.filter((m) => m.role === 'user')).toHaveLength(3);
        expect(msgs.filter((m) => m.role === 'assistant')).toHaveLength(3);
        expect(msgs.filter((m) => m.streaming)).toEqual([]);
        expect(msgs.filter((m) => m.role === 'assistant').map((m) => m.id).sort()).toEqual([101, 102, 103]);
        expect(errorSpy).toHaveBeenCalledTimes(3);
        errorSpy.mockRestore();
        listSpy.mockRestore();
    });

    it('Falsify:stale 失配回退 anchor 写回 — A 完成 list 在途、B 连发清 A 占位、A list 成功(stale 失配)、B list 失败 → aA 不丢失', async () => {
        // 期末 code-review finding 1:旧实现 stale 失配直接 no-op,含 aA 的服务端列表
        // 整体丢弃 → aA 从缓存消失。修复:stale 守卫失败时回退 settleByPosition
        // (幂等:同 id 已存在则 no-op)。
        const tab = { conversationId: 1, phase: 'thinking', isStreaming: true, messages: [msg(1, 'user', 'u1')] };
        const deps = {
            convId: 1,
            getTab: () => tab,
            updateTab: (id, patch) => Object.assign(tab, patch),
            isActiveStream: () => true,
            renderMessages: vi.fn(),
            refreshSendButton: vi.fn(),
            refreshConversations: vi.fn(),
        };
        let resolveListA;
        let listCall = 0;
        const listSpy = vi.spyOn(messages, 'list');
        listSpy.mockImplementation(() => {
            if (listCall++ === 0) {
                return new Promise((r) => { resolveListA = r; }); // A 的 list 挂起
            }
            return Promise.reject(new Error('服务端故障')); // B 的 list 失败
        });
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

        // 流 A:token + done(101),list 挂起
        const sessionA = createStreamSession(deps);
        sessionA.onToken('回复A');
        const pA = sessionA.onDone(101);
        // 流 B 连发:u2 + token(清除 A 的 streaming 占位)+ done(102),list 失败
        deps.updateTab(1, { messages: [...tab.messages, msg(2, 'user', 'u2')] });
        const sessionB = createStreamSession(deps);
        sessionB.onToken('回复B');
        const pB = sessionB.onDone(102);

        // A 的 list 成功返回(服务端含 aA 的消息列表,长度已变 → stale 分支,settleIndex 失配)
        resolveListA([msg(1, 'user', 'u1'), { id: 101, role: 'assistant', content: '回复A' }, msg(2, 'user', 'u2')]);
        await pA;
        // B 的 list 失败 → anchor 写回 aB
        await pB;

        const msgs = tab.messages;
        expect(msgs.filter((m) => m.role === 'user')).toHaveLength(2);
        expect(msgs.filter((m) => m.role === 'assistant')).toHaveLength(2); // aA + aB 都在(不丢失)
        expect(msgs.filter((m) => m.streaming)).toEqual([]);
        expect(msgs.filter((m) => m.role === 'assistant').map((m) => m.id).sort()).toEqual([101, 102]);
        errorSpy.mockRestore();
        listSpy.mockRestore();
    });
});

describe('createStreamSession — onError(错误/停止,终态守卫)', () => {
    const abortError = () => Object.assign(new Error('aborted'), { name: 'AbortError' });

    it('普通错误 → 错误经注入回调上抛 + 不写 [错误] 进消息缓存 + 部分内容保留为普通消息', () => {
        const { session, deps, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        session.onToken('部分'); // 经 seam 累积
        session.onError(new Error('模型超时'));
        expect(tab.phase).toBe('error');
        expect(tab.isStreaming).toBe(false);
        expect(tab.activeStream).toBeNull();
        // 错误不写入消息缓存 — 经注入回调上抛给聊天域渲染错误条
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '部分' },
        ]);
        expect(tab.messages.some((m) => m.content?.includes('[错误]'))).toBe(false);
        expect(tab.messages.filter((m) => m.error)).toHaveLength(0);
        // 注入回调接收错误对象
        expect(deps.onError).toHaveBeenCalledWith(expect.objectContaining({ message: '模型超时' }));
        expect(deps.renderMessages).toHaveBeenCalledTimes(1);
        expect(deps.refreshSendButton).toHaveBeenCalledTimes(1);
        expect(deps.refreshConversations).toHaveBeenCalledTimes(1);
    });

    it('F-51 契约锁:render 抛错 → surfaceError 仍被调用(错误条不被渲染异常吞掉)', () => {
        // 回归本源缺陷:surfaceError 位于 render 之后时,render 抛错会跳过错误条上抛。
        // 契约:错误上抛回调先于渲染执行,渲染异常只影响 DOM 画面,不吞掉错误条。
        // (渲染异常仍向上传播 — 那是真实的 DOM 缺陷,不应被静默吞掉。)
        const { session, deps, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        session.onToken('部分'); // 经 seam 累积
        deps.renderMessages.mockImplementation(() => { throw new Error('渲染段崩了'); });
        expect(() => session.onError(new Error('模型超时'))).toThrow('渲染段崩了');
        // surfaceError 收到错误对象(先于 render,render 抛错已不可能阻断它)
        expect(deps.onError).toHaveBeenCalledWith(expect.objectContaining({ message: '模型超时' }));
        // 错误仍不落消息缓存(错误条归属聊天域),部分内容保留为普通消息
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '部分' },
        ]);
        expect(tab.phase).toBe('error');
    });

    it('停止(AbortError)+ 有内容 → 保留部分内容 + stopped 标记(「已停止」语义)', () => {
        const { session, deps, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        session.onToken('部分'); // 经 seam 累积
        session.onError(abortError());
        expect(tab.phase).toBe('error'); // 警示标记(既有行为)
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '部分', stopped: true },
        ]);
        // 停止路径不触发错误条上抛(surfaceError 不调用)
        expect(deps.onError).not.toHaveBeenCalled();
    });

    it('停止(AbortError)+ 无内容 → 仅保留已发消息', () => {
        const { session, deps, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        session.onError(abortError());
        expect(tab.messages).toEqual([msg(1, 'user', 'hi')]);
        // 停止路径不触发错误条上抛(surfaceError 不调用)
        expect(deps.onError).not.toHaveBeenCalled();
    });

    it('终态守卫:错误帧后流关闭补发 onDone(null) → 拦截,phase 保持 error、消息列表不含错误气泡', async () => {
        const { session, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        session.onError(new Error('模型超时'));
        await session.onDone(null);
        expect(tab.phase).toBe('error');
        expect(tab.messages.filter((m) => m.error)).toHaveLength(0);
        expect(tab.messages.some((m) => m.role === 'assistant' && !m.error)).toBe(false);
        expect(tab.messages).toEqual([msg(1, 'user', 'hi')]);
    });

    it('终态守卫:onError 二次调用 → 忽略', () => {
        const { session, deps, tab } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        session.onError(new Error('a'));
        session.onError(new Error('b'));
        expect(deps.updateTab.mock.calls.filter(([, patch]) => patch.phase)).toHaveLength(1);
        expect(tab.messages.filter((m) => m.error)).toHaveLength(0);
        expect(tab.messages).toEqual([msg(1, 'user', 'hi')]); // 错误不落缓存
    });
});

describe('createStreamSession — isSettled / 参数校验 / 协议表面', () => {
    it('isSettled:初始 false;onDone 后 true;onError 后 true;token 不改变', async () => {
        const h1 = makeHarness({ initial: [msg(1, 'user', 'hi')], withListSpy: true });
        expect(h1.session.isSettled()).toBe(false);
        h1.session.onToken('x');
        expect(h1.session.isSettled()).toBe(false);
        h1.listSpy.mockResolvedValue([]);
        await h1.session.onDone(101);
        expect(h1.session.isSettled()).toBe(true);

        const h2 = makeHarness();
        expect(h2.session.isSettled()).toBe(false);
        h2.session.onError(new Error('x'));
        expect(h2.session.isSettled()).toBe(true);
    });

    it('入参校验:缺 convId / getTab / updateTab → TypeError 快速失败', () => {
        expect(() => createStreamSession({})).toThrow(TypeError);
        expect(() => createStreamSession({ convId: 1 })).toThrow(TypeError);
        expect(() => createStreamSession({ convId: 1, getTab: () => {}, updateTab: () => {} })).not.toThrow();
    });

    it('回调缺省(renderMessages 等非函数)→ 安全降级为 no-op,不抛错', async () => {
        const listSpy = vi.spyOn(messages, 'list').mockResolvedValue([]);
        const tab = { conversationId: 1, phase: 'thinking', isStreaming: true, messages: [] };
        const session = createStreamSession({
            convId: 1,
            getTab: () => tab,
            updateTab: (id, patch) => Object.assign(tab, patch),
        });
        expect(() => session.onToken('x')).not.toThrow();
        await expect(session.onDone(101)).resolves.toBeUndefined();
        expect(() => session.onError(new Error('x'))).not.toThrow();
        listSpy.mockRestore();
    });

    it('Falsify:onError 时 tab 已关闭 → no-op 不抛错(settled 空列表兜底)', () => {
        const { session, deps } = makeHarness({ initial: [msg(1, 'user', 'hi')] });
        deps.getTab.mockReturnValue(undefined); // 发起 tab 被关闭
        expect(() => session.onError(new Error('模型超时'))).not.toThrow();
        // 终态写回 + 错误消息写回均发出(真实 tabs.js 对不存在 id 幂等 no-op,不抛错)
        expect(deps.updateTab).toHaveBeenCalledTimes(2);
        expect(deps.refreshSendButton).toHaveBeenCalledTimes(1);
        expect(deps.refreshConversations).toHaveBeenCalledTimes(1);
    });

    it('Falsify:活动判定由注入决定 — isActiveStream=true 且 renderMessages 缺省 → 渲染 no-op 不抛错', async () => {
        const listSpy = vi.spyOn(messages, 'list').mockResolvedValue([msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')]);
        const tab = { conversationId: 1, phase: 'thinking', isStreaming: true, messages: [msg(1, 'user', 'hi')] };
        const session = createStreamSession({
            convId: 1,
            getTab: () => tab,
            updateTab: (id, patch) => Object.assign(tab, patch),
            isActiveStream: () => true, // 活动,但 renderMessages 未注入
        });
        await expect(session.onDone(101)).resolves.toBeUndefined();
        expect(tab.messages).toEqual([msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')]);
        listSpy.mockRestore();
    });

    it('__all__ 收口全部公开函数', () => {
        expect(__all__.sort()).toEqual(['createStreamSession', 'mergeFreshList', 'settleTurn']);
    });
});

// ══════════════════════════════════════════════════
// settleTurn 统一结算入口(流式 onDone 正常完成段与非流式完成分支共用的
// reload → mergeFreshList → 写回 → 条件渲染 段落;内部 try/catch 双分支)
// ══════════════════════════════════════════════════

/** settleTurn 测试台:内存 tab + vi.fn 注入;updateTab 就地合并模拟 tabs.js 语义 */
function makeSettleHarness({ initial = [], active = true } = {}) {
    const tab = { conversationId: 1, phase: 'thinking', isStreaming: true, messages: initial };
    const deps = {
        convId: 1,
        getTab: vi.fn(() => tab),
        updateTab: vi.fn((id, patch) => Object.assign(tab, patch)),
        isActive: vi.fn(() => active),
        render: vi.fn(),
    };
    const listSpy = vi.spyOn(messages, 'list');
    return { deps, tab, listSpy };
}

describe('settleTurn — 统一结算入口（reload → mergeFreshList → 写回 → 条件渲染）', () => {
    it('fresh：长度未变 → 整体替换 + 活动时渲染（updateTab 按 convId 写回）', async () => {
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi'), streaming('你好')] });
        listSpy.mockResolvedValue(fresh);
        await settleTurn({ ...deps, revision: 2, settleIndex: 1, anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(tab.messages).toBe(fresh); // 直接采用服务端数组
        expect(deps.updateTab).toHaveBeenLastCalledWith(1, { messages: fresh });
        expect(deps.render).toHaveBeenCalledTimes(1);
        expect(listSpy).toHaveBeenCalledWith(1);
    });

    it('stale：list 在途期间同 tab 连发新消息 → 旧快照不覆盖，仅按位置结算本流 streaming 标记', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi'), streaming('你好')] });
        listSpy.mockReturnValue(deferred.promise);
        const p = settleTurn({ ...deps, revision: 2, settleIndex: 1, anchor: tab.messages[0], messageId: 101, content: '你好' });
        // 连发:同 tab 追加新 user 消息(长度 2 → 3)
        deps.updateTab(1, { messages: [...tab.messages, msg(3, 'user', 'again')] });
        // 旧 list 快照返回(不含连发消息的陈旧状态)
        deferred.resolve([msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')]);
        await p;
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', streaming: false, id: 101 },
            msg(3, 'user', 'again'),
        ]);
        expect(deps.render).not.toHaveBeenCalled(); // stale 仅缓存结算
    });

    it('list 重载失败（流式参数）→ 位置感知写回（占位移除 + 原位插入 id）+ 活动渲染 + console.error', async () => {
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi'), streaming('你好')] });
        listSpy.mockRejectedValue(new Error('服务端故障'));
        await settleTurn({ ...deps, revision: 2, settleIndex: 1, anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(tab.messages).toEqual([
            msg(1, 'user', 'hi'),
            { role: 'assistant', content: '你好', id: 101 },
        ]);
        expect(deps.render).toHaveBeenCalledTimes(1);
        expect(errorSpy).toHaveBeenCalledWith('重新加载消息列表失败:', expect.any(Error));
        errorSpy.mockRestore();
    });

    it('非流式失败兜底（settleIndex:-1 + content，不带 messageId）→ 尾部追加无 id 消息（G1/C2-D2 行为保持）', async () => {
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi')] });
        listSpy.mockRejectedValue(new Error('服务端故障'));
        await settleTurn({ ...deps, revision: 1, settleIndex: -1, content: '回复' });
        expect(tab.messages).toEqual([msg(1, 'user', 'hi'), { role: 'assistant', content: '回复' }]);
        expect(tab.messages[1].id).toBeUndefined(); // 不补 messageId —— 逐字复刻现状（决策 C2-D2）
        expect(deps.render).toHaveBeenCalledTimes(1);
        errorSpy.mockRestore();
    });

    it('非流式成功（settleIndex:-1，content 仅失败分支使用）→ fresh 整体替换（等价 {settleIndex:-1} 参数语义）', async () => {
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '回复')];
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi')] });
        listSpy.mockResolvedValue(fresh);
        await settleTurn({ ...deps, revision: 1, settleIndex: -1, content: '回复' });
        expect(tab.messages).toBe(fresh);
        expect(deps.render).toHaveBeenCalledTimes(1);
    });

    it('非流式 stale 边界现状钉住：revision 捕获后同 tab 连发（长度变化）→ 原样保留不覆盖（行为保持，不「顺手修好」）', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi')] });
        listSpy.mockReturnValue(deferred.promise);
        const p = settleTurn({ ...deps, revision: 1, settleIndex: -1, content: '回复' });
        deps.updateTab(1, { messages: [...tab.messages, msg(3, 'user', '连发')] }); // 长度 1 → 2
        deferred.resolve([msg(1, 'user', 'hi'), { id: 5, role: 'assistant', content: '回复' }]); // 陈旧快照
        await p;
        // stale + settleIndex=-1 + anchor=null → 无占位可结算、无 anchor 回退 → 原样
        expect(tab.messages).toEqual([msg(1, 'user', 'hi'), msg(3, 'user', '连发')]);
        expect(deps.render).not.toHaveBeenCalled();
    });

    it('并发插入后位置漂移：stale 失配（settleIndex 已非本流占位）→ 回退 anchor 位置写回本流内容（消息不丢失）', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'u1'), streaming('回复A')] });
        listSpy.mockReturnValue(deferred.promise);
        const p = settleTurn({ ...deps, revision: 2, settleIndex: 1, anchor: tab.messages[0], messageId: 101, content: '回复A' });
        // 并发流 B 连发:u2 + token 替换位置 1 的占位(settleIndex 失配);u1 保持原对象引用
        // (anchor 定位依赖引用 — 与既有 Falsify 用例同构)
        deps.updateTab(1, { messages: [tab.messages[0], msg(3, 'user', 'u2'), streaming('回复B')] });
        deferred.resolve([msg(1, 'user', 'u1'), { id: 101, role: 'assistant', content: '回复A' }]); // 陈旧快照(stale)
        await p;
        expect(tab.messages).toEqual([
            msg(1, 'user', 'u1'),
            { id: 101, role: 'assistant', content: '回复A' },
            msg(3, 'user', 'u2'),
            streaming('回复B'),
        ]);
        expect(deps.render).toHaveBeenCalledTimes(1);
    });

    // ── S-09（F-58 + F-60）──

    it('F-58:list 重载失败 + replaceId → 按被顶替旧消息 id 原位替换（不尾部追加、无旧残留）', async () => {
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        const { deps, tab, listSpy } = makeSettleHarness({
            initial: [msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复')],
        });
        listSpy.mockRejectedValue(new Error('服务端故障'));
        await settleTurn({ ...deps, revision: 2, settleIndex: -1, anchor: null, replaceId: 2, messageId: 3, content: '新回复' });
        expect(tab.messages).toEqual([
            msg(1, 'user', '你好'),
            { role: 'assistant', content: '新回复', id: 3 },
        ]);
        expect(tab.messages).toHaveLength(2);
        expect(tab.messages.some((m) => m.content === '旧回复')).toBe(false);
        expect(deps.render).toHaveBeenCalledTimes(1);
        expect(errorSpy).toHaveBeenCalledWith('重新加载消息列表失败:', expect.any(Error));
        errorSpy.mockRestore();
    });

    it('F-60:stale + settleIndex=-1 + anchor=null + messageId/content → 服务端列表写回渲染（不静默丢弃）', async () => {
        const deferred = {};
        deferred.promise = new Promise((resolve) => { deferred.resolve = resolve; });
        const { deps, tab, listSpy } = makeSettleHarness({
            initial: [msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复')],
        });
        listSpy.mockReturnValue(deferred.promise);
        const p = settleTurn({ ...deps, revision: 2, settleIndex: -1, anchor: null, messageId: 3, content: '新回复' });
        deps.updateTab(1, { messages: [...tab.messages, msg(4, 'user', '并发')] }); // 长度 2 → 3（stale）
        deferred.resolve([
            msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复'),
            msg(4, 'user', '并发'), msg(3, 'assistant', '新回复'),
        ]);
        await p;
        expect(tab.messages).toEqual([
            msg(1, 'user', '你好'), msg(2, 'assistant', '旧回复'),
            msg(4, 'user', '并发'), msg(3, 'assistant', '新回复'),
        ]);
        expect(deps.render).toHaveBeenCalledTimes(1); // 不再静默丢弃
    });

    it('幂等：缓存已含同 id 消息（已被并发流结算）→ 失败兜底不重复插入', async () => {
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        const { deps, tab, listSpy } = makeSettleHarness({
            initial: [msg(1, 'user', 'hi'), { role: 'assistant', content: '你好', id: 101 }],
        });
        listSpy.mockRejectedValue(new Error('服务端故障'));
        await settleTurn({ ...deps, revision: 2, settleIndex: 1, anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(tab.messages).toEqual([msg(1, 'user', 'hi'), { role: 'assistant', content: '你好', id: 101 }]);
        expect(tab.messages.filter((m) => m.id === 101)).toHaveLength(1); // 不重复插入
        expect(deps.render).not.toHaveBeenCalled();
        errorSpy.mockRestore();
    });

    it('非活动（后台流）→ 缓存照写，不渲染', async () => {
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const { deps, tab, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi'), streaming('你好')], active: false });
        listSpy.mockResolvedValue(fresh);
        await settleTurn({ ...deps, revision: 2, settleIndex: 1, anchor: tab.messages[0], messageId: 101, content: '你好' });
        expect(tab.messages).toBe(fresh); // 后台写回保持
        expect(deps.render).not.toHaveBeenCalled();
    });

    it('防悬挂：发起 tab 已关闭（getTab 返回 undefined）→ resolve 无异常、无渲染、无 messages 写回', async () => {
        const { deps, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi')] });
        listSpy.mockResolvedValue([msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')]);
        deps.getTab.mockReturnValue(undefined);
        await expect(settleTurn({ ...deps, revision: 1, settleIndex: -1 })).resolves.toBeUndefined();
        expect(deps.updateTab.mock.calls.filter(([, patch]) => patch.messages)).toHaveLength(0);
        expect(deps.render).not.toHaveBeenCalled();
    });

    it('防悬挂：tab 已关闭且 list 失败 → 仍 resolve 无异常（console.error 记录保持）', async () => {
        const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        const { deps, listSpy } = makeSettleHarness({ initial: [msg(1, 'user', 'hi')] });
        listSpy.mockRejectedValue(new Error('服务端故障'));
        deps.getTab.mockReturnValue(undefined);
        await expect(settleTurn({ ...deps, revision: 1, settleIndex: -1, content: '回复' })).resolves.toBeUndefined();
        expect(deps.updateTab).not.toHaveBeenCalled();
        expect(deps.render).not.toHaveBeenCalled();
        expect(errorSpy).toHaveBeenCalledTimes(1);
        errorSpy.mockRestore();
    });

    it('入参防御：isActive/render 缺省（非函数）→ 安全降级 no-op，不抛错', async () => {
        const fresh = [msg(1, 'user', 'hi'), msg(2, 'assistant', '你好')];
        const tab = { conversationId: 1, messages: [msg(1, 'user', 'hi')] };
        const listSpy = vi.spyOn(messages, 'list').mockResolvedValue(fresh);
        await expect(settleTurn({
            convId: 1,
            getTab: () => tab,
            updateTab: (id, patch) => Object.assign(tab, patch),
            revision: 1,
            settleIndex: -1,
        })).resolves.toBeUndefined();
        expect(tab.messages).toEqual(fresh);
        listSpy.mockRestore();
    });
});
