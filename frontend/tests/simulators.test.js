/**
 * 模拟器列表模块测试（U7-T3）。
 *
 * 覆盖：
 *   - parseManifest 纯函数：合法归一化 / 畸形 JSON / 非字符串输入 / 顶层非对象 /
 *     version 不兼容 / simulators 缺失或非数组 / id 缺失或重复 / file 缺失 /
 *     type 非法 / 条目非对象 / 条目级字段缺失宽容降级 / 空列表
 *   - filterGames 纯函数三档：全部（含未知 type 计入全部）/ AI / 纯本地 /
 *     未知筛选类型返回全部 / 非数组输入
 *   - 四态渲染（fetch 经 setFetch seam 注入）：loading / ready（卡片网格）/
 *     error（错误文案 + 重试按钮）/ empty（空态文案）；错误态重试重新 fetch
 *   - 筛选交互：三档切换即重渲染 + 计数 + active 类迁移；筛选无匹配 → 空态
 *   - 卡片点击：注入 onOpenGame 收到完整 game；未注入 no-op 不抛错
 *   - Falsify：无 container no-op / 未 init 调 refresh no-op / 重复 init 幂等
 *     （钩子取最新）/ setFetch(null) 回落全局 fetch
 *
 * 测试即模块接口契约：公开面 __all__ = initSimulatorsView / refreshSimulators /
 *   parseManifest / filterGames / setFetch（fetch seam 与 api.js setFetch
 *   同构 — api.js 的 fetchImpl 为模块私有不可读，本模块镜像同一 seam 模式；
 *   setFetch(null) 恢复回落全局 fetch）。
 * 挂载模式：jsdom + vi.resetModules()（每用例全新模块状态）+ 内联 mock
 *   manifest（不依赖真实 simulators/ 数据文件）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** 最小列表面板 DOM — 与 index.html 的 #simulator-list-panel 契约一致（只读契约） */
const PANEL_DOM_HTML = '<div id="simulator-list-panel"></div>';

/** 内联合法 manifest（2 款：ai 带 config/saveKeyPrefix + local 无 config） */
const MANIFEST_OK = {
    version: 1,
    simulators: [
        {
            id: 'life-sim',
            file: '人生模拟器v3.html',
            name: '人生模拟器 v3',
            type: 'ai',
            description: 'AI 驱动的生命模拟',
            saveKeyPrefix: 'ls_',
            config: { endpoint: 'cfg-endpoint', apikey: 'cfg-apikey', model: 'cfg-model' },
        },
        {
            id: 'spider-shadow',
            file: '蛛网之影.html',
            name: '蛛网之影',
            type: 'local',
            description: '纯本地角色扮演',
        },
    ],
};

/** 加载全新 simulators 模块（DOM 先就位；返回模块 + 面板引用） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = PANEL_DOM_HTML;
    const sim = await import('../js/simulators.js');
    return { sim, panel: document.querySelector('#simulator-list-panel') };
}

/** mock Response：text() 返回给定 JSON 文本（simulators.js fetch seam 消费） */
const mockText = (text, status = 200) =>
    Promise.resolve({ ok: status < 400, status, text: async () => text });

const mockManifest = (data) => mockText(JSON.stringify(data));

/** 构造可路由 fetch mock：记录调用，按用例路由（成功 / 抛错 / 挂起） */
function makeFetch({ result = null, fail = null, pending = null } = {}) {
    return vi.fn(async () => {
        if (pending) return pending.promise;
        if (fail) throw fail;
        return result;
    });
}

describe('simulators — 协议表面 __all__', () => {
    it('__all__ 收口公开函数与 fetch seam', async () => {
        const { sim } = await loadModules();
        expect(sim.__all__.sort()).toEqual([
            'filterGames',
            'initSimulatorsView',
            'parseManifest',
            'refreshSimulators',
            'setFetch',
        ]);
    });
});

describe('parseManifest — 纯函数（合法/结构错误/条目级降级）', () => {
    it('合法 manifest → ok:true，条目归一化为 {id,file,name,type,description} + 可选字段透传', async () => {
        const { sim } = await loadModules();
        const result = sim.parseManifest(JSON.stringify(MANIFEST_OK));
        expect(result.ok).toBe(true);
        expect(result.games).toEqual([
            {
                id: 'life-sim',
                file: '人生模拟器v3.html',
                name: '人生模拟器 v3',
                type: 'ai',
                description: 'AI 驱动的生命模拟',
                saveKeyPrefix: 'ls_',
                config: { endpoint: 'cfg-endpoint', apikey: 'cfg-apikey', model: 'cfg-model' },
            },
            { id: 'spider-shadow', file: '蛛网之影.html', name: '蛛网之影', type: 'local', description: '纯本地角色扮演' },
        ]);
    });

    it('空 simulators 列表 → ok:true 且 games 为空（空态判定依据）', async () => {
        const { sim } = await loadModules();
        const result = sim.parseManifest(JSON.stringify({ version: 1, simulators: [] }));
        expect(result.ok).toBe(true);
        expect(result.games).toEqual([]);
    });

    it('畸形 JSON → ok:false，错误文案「manifest 不是合法 JSON」', async () => {
        const { sim } = await loadModules();
        const result = sim.parseManifest('not-json{{{');
        expect(result.ok).toBe(false);
        expect(result.error).toBe('manifest 不是合法 JSON');
    });

    it('Falsify:非字符串输入（null / 对象）→ ok:false', async () => {
        const { sim } = await loadModules();
        expect(sim.parseManifest(null).ok).toBe(false);
        expect(sim.parseManifest({ version: 1 }).ok).toBe(false);
        expect(sim.parseManifest(undefined).ok).toBe(false);
    });

    it('Falsify:顶层非对象（JSON 数字 / 数组 / null）→ ok:false', async () => {
        const { sim } = await loadModules();
        expect(sim.parseManifest('42').ok).toBe(false);
        expect(sim.parseManifest('[]').ok).toBe(false);
        expect(sim.parseManifest('null').ok).toBe(false);
    });

    it('version 不兼容（缺失 / 非 1）→ ok:false，「manifest 版本不兼容」', async () => {
        const { sim } = await loadModules();
        expect(sim.parseManifest(JSON.stringify({ simulators: [] })).error).toBe('manifest 版本不兼容');
        expect(sim.parseManifest(JSON.stringify({ version: 2, simulators: [] })).error).toBe('manifest 版本不兼容');
    });

    it('simulators 缺失 / 非数组 → ok:false', async () => {
        const { sim } = await loadModules();
        expect(sim.parseManifest(JSON.stringify({ version: 1 })).error).toBe('manifest 缺少 simulators 列表');
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: 'x' })).ok).toBe(false);
    });

    it('id 缺失 / 重复 → ok:false，「manifest 存在缺失或重复的 id」', async () => {
        const { sim } = await loadModules();
        const withoutId = { ...MANIFEST_OK.simulators[0], id: undefined };
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: [withoutId] })).error)
            .toBe('manifest 存在缺失或重复的 id');
        const duplicated = [MANIFEST_OK.simulators[0], { ...MANIFEST_OK.simulators[0] }];
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: duplicated })).ok).toBe(false);
    });

    it('file 缺失 → ok:false，「manifest 条目缺少 file 字段」', async () => {
        const { sim } = await loadModules();
        const { file, ...noFile } = MANIFEST_OK.simulators[0];
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: [noFile] })).error)
            .toBe('manifest 条目缺少 file 字段');
    });

    it('type 非法（未知值 / 缺失）→ ok:false，「manifest 条目 type 非法」', async () => {
        const { sim } = await loadModules();
        const badType = { ...MANIFEST_OK.simulators[0], type: 'web' };
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: [badType] })).error)
            .toBe('manifest 条目 type 非法');
        const { type, ...noType } = MANIFEST_OK.simulators[0];
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: [noType] })).ok).toBe(false);
    });

    it('Falsify:条目非对象（null / 字符串元素）→ ok:false', async () => {
        const { sim } = await loadModules();
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: [null] })).ok).toBe(false);
        expect(sim.parseManifest(JSON.stringify({ version: 1, simulators: ['x'] })).ok).toBe(false);
    });

    it('条目级字段缺失（name/description）→ 宽容降级为空串，不整体失败', async () => {
        const { sim } = await loadModules();
        const { name, description, ...sparse } = MANIFEST_OK.simulators[1];
        const result = sim.parseManifest(JSON.stringify({ version: 1, simulators: [sparse] }));
        expect(result.ok).toBe(true);
        expect(result.games[0].name).toBe('');
        expect(result.games[0].description).toBe('');
    });

    it('Falsify:saveKeyPrefix/config 类型异常 → 降级剔除可选字段，不炸', async () => {
        const { sim } = await loadModules();
        const weird = { ...MANIFEST_OK.simulators[0], saveKeyPrefix: 42, config: 'not-object' };
        const result = sim.parseManifest(JSON.stringify({ version: 1, simulators: [weird] }));
        expect(result.ok).toBe(true);
        expect(result.games[0].saveKeyPrefix).toBeUndefined();
        expect(result.games[0].config).toBeUndefined();
    });
});

describe('filterGames — 纯函数三档', () => {
    /** 含未知 type 的游戏（计入「全部」、不落入 ai/local 任一档 — 过滤策略已定） */
    const games = [
        { id: 'a', type: 'ai' },
        { id: 'b', type: 'local' },
        { id: 'c', type: 'web' },
    ];

    it('all → 原样返回全部（含未知 type）', async () => {
        const { sim } = await loadModules();
        expect(sim.filterGames(games, 'all')).toEqual(games);
    });

    it('ai → 仅 ai 类型', async () => {
        const { sim } = await loadModules();
        expect(sim.filterGames(games, 'ai').map((g) => g.id)).toEqual(['a']);
    });

    it('local → 仅 local 类型', async () => {
        const { sim } = await loadModules();
        expect(sim.filterGames(games, 'local').map((g) => g.id)).toEqual(['b']);
    });

    it('未知 game type 不落入 ai/local 任一档（计入「全部」）', async () => {
        const { sim } = await loadModules();
        expect(sim.filterGames(games, 'ai')).not.toContainEqual(games[2]);
        expect(sim.filterGames(games, 'local')).not.toContainEqual(games[2]);
    });

    it('Falsify:未知筛选类型 → 返回全部（防御不炸）', async () => {
        const { sim } = await loadModules();
        expect(sim.filterGames(games, 'web')).toEqual(games);
        expect(sim.filterGames(games, undefined)).toEqual(games);
    });

    it('Falsify:非数组输入 → 返回空数组', async () => {
        const { sim } = await loadModules();
        expect(sim.filterGames(null, 'all')).toEqual([]);
        expect(sim.filterGames('x', 'ai')).toEqual([]);
    });
});

describe('simulators — 四态渲染与交互（fetch 经 setFetch seam）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('initSimulatorsView 挂载：筛选工具条三档按钮 + 初始 loading 态', async () => {
        const { sim, panel } = await loadModules();
        sim.initSimulatorsView({ container: panel });

        const labels = [...panel.querySelectorAll('.sim-filter-btn')].map((b) => b.textContent);
        expect(labels).toEqual(['全部', 'AI 驱动', '纯本地']);
        expect(panel.querySelector('.sim-filter-btn[data-filter="all"]').classList.contains('active')).toBe(true);
        expect(panel.querySelector('.sim-state').innerHTML).toContain('加载中…');
    });

    it('refresh 成功 → ready：卡片网格含名称/类型标签/描述 + 计数', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        const cards = panel.querySelectorAll('.sim-card');
        expect(cards).toHaveLength(2);
        expect(panel.querySelector('.sim-count').textContent).toContain('共 2 款');
        expect(cards[0].querySelector('.sim-card-name').textContent).toBe('人生模拟器 v3');
        expect(cards[0].querySelector('.sim-type-tag').textContent).toBe('AI 驱动');
        expect(cards[0].querySelector('.sim-type-tag').classList.contains('sim-type-ai')).toBe(true);
        expect(cards[0].querySelector('.sim-card-desc').textContent).toBe('AI 驱动的生命模拟');
        expect(cards[1].querySelector('.sim-type-tag').textContent).toBe('纯本地');
        expect(cards[1].querySelector('.sim-type-tag').classList.contains('sim-type-local')).toBe(true);
        expect(cards[1].querySelector('.sim-card-name').textContent).toBe('蛛网之影');
        expect(cards[0].dataset.id).toBe('life-sim');
    });

    it('条目级缺失 name → 卡片不渲染名称字段（降级不炸）', async () => {
        const { sim, panel } = await loadModules();
        const { name, ...sparse } = MANIFEST_OK.simulators[0];
        sim.setFetch(makeFetch({ result: mockManifest({ version: 1, simulators: [sparse] }) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(panel.querySelectorAll('.sim-card')).toHaveLength(1);
        expect(panel.querySelector('.sim-card-name')).toBeNull();
        expect(panel.querySelector('.sim-type-tag').textContent).toBe('AI 驱动');
    });

    it('Falsify:游戏 id 含双引号（属性值注入面 — escapeHtml 不转义引号）→ data-id 经 dataset 赋值，无额外属性且完整回传', async () => {
        const { sim, panel } = await loadModules();
        const evilId = 'life-sim" onclick="alert(1)';
        sim.setFetch(makeFetch({ result: mockManifest({
            version: 1,
            simulators: [{ id: evilId, file: 'x.html', name: 'N', type: 'ai' }],
        }) }));
        const openSpy = vi.fn();
        sim.initSimulatorsView({ container: panel, onOpenGame: openSpy });
        await sim.refreshSimulators();

        const card = panel.querySelector('.sim-card');
        expect(card.hasAttribute('onclick')).toBe(false); // 无注入属性（旧实现：引号截断 + onclick 成真属性）
        expect(card.dataset.id).toBe(evilId); // dataset 通道完整往返（无引号截断）
        card.click();
        expect(openSpy).toHaveBeenCalledTimes(1);
        expect(openSpy).toHaveBeenCalledWith(expect.objectContaining({ id: evilId }));
    });

    it('游戏名含双引号（文本上下文 — escapeHtml 文本通道）→ 名称以文本渲染，不产生属性', async () => {
        const { sim, panel } = await loadModules();
        const evilName = 'A" onmouseover="x';
        sim.setFetch(makeFetch({ result: mockManifest({
            version: 1,
            simulators: [{ id: 'a', file: 'x.html', name: evilName, type: 'ai' }],
        }) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        const nameEl = panel.querySelector('.sim-card-name');
        expect(nameEl.textContent).toBe(evilName);
        expect(nameEl.hasAttribute('onmouseover')).toBe(false);
    });

    it('loading 态：请求挂起期间展示「加载中…」（渲染先于 await）', async () => {
        const { sim, panel } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        sim.setFetch(makeFetch({ pending }));
        sim.initSimulatorsView({ container: panel });

        const refreshPromise = sim.refreshSimulators();
        expect(panel.querySelector('.sim-state').innerHTML).toContain('加载中…');
        pending.resolve(mockManifest(MANIFEST_OK));
        await refreshPromise;
        expect(panel.querySelectorAll('.sim-card')).toHaveLength(2);
    });

    it('refresh fetch 抛错 → error：错误文案 + 原因（escapeHtml 转义）+ 重试按钮', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ fail: new Error('<网络错误>') }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(panel.querySelector('.sim-error-msg').textContent).toBe('模拟器列表加载失败');
        expect(panel.querySelector('.sim-error-reason').textContent).toBe('<网络错误>');
        expect(panel.querySelector('.sim-error-reason').innerHTML).toContain('&lt;网络错误&gt;');
        expect(panel.querySelector('.sim-retry-btn').textContent).toBe('重试');
    });

    it('refresh HTTP 非 2xx（ok:false）→ error 态（HTTP 状态码入原因）', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockText('boom', 500) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(panel.querySelector('.sim-error-msg').textContent).toBe('模拟器列表加载失败');
        expect(panel.querySelector('.sim-error-reason').textContent).toBe('加载失败 (500)');
    });

    it('Falsify:fetch 响应形状异常（无 text 方法）→ error 态兜底不炸', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: Promise.resolve({ ok: true, status: 200 }) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(panel.querySelector('.sim-error-msg').textContent).toBe('模拟器列表加载失败');
        expect(panel.querySelector('.sim-error-reason').textContent).toBe('模拟器清单响应无效');
    });

    it('refresh 解析结构错误（version 不兼容）→ error 态（解析原因透出）', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest({ version: 2, simulators: [] }) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(panel.querySelector('.sim-error-msg').textContent).toBe('模拟器列表加载失败');
        expect(panel.querySelector('.sim-error-reason').textContent).toBe('manifest 版本不兼容');
    });

    it('refresh 空 manifest（simulators:[]）→ empty 空态文案', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest({ version: 1, simulators: [] }) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(panel.querySelector('.sim-state .sim-empty').textContent).toBe('暂无模拟器');
    });

    it('筛选交互：点「AI 驱动」→ 仅 ai 卡 + 计数更新 + active 类迁移；点「全部」→ 恢复', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        panel.querySelector('.sim-filter-btn[data-filter="ai"]').click();
        let cards = panel.querySelectorAll('.sim-card');
        expect(cards).toHaveLength(1);
        expect(cards[0].querySelector('.sim-type-tag').textContent).toBe('AI 驱动');
        expect(panel.querySelector('.sim-count').textContent).toContain('共 1 款');
        expect(panel.querySelector('.sim-filter-btn[data-filter="ai"]').classList.contains('active')).toBe(true);
        expect(panel.querySelector('.sim-filter-btn[data-filter="all"]').classList.contains('active')).toBe(false);

        panel.querySelector('.sim-filter-btn[data-filter="all"]').click();
        cards = panel.querySelectorAll('.sim-card');
        expect(cards).toHaveLength(2);
        expect(panel.querySelector('.sim-count').textContent).toContain('共 2 款');
    });

    it('筛选无匹配（仅 ai 游戏时筛 local）→ 「该类型暂无模拟器」空态', async () => {
        const { sim, panel } = await loadModules();
        // 仅 1 款 ai 游戏（MANIFEST_OK.simulators[0] = life-sim, ai）
        const aiOnly = { version: 1, simulators: [MANIFEST_OK.simulators[0]] };
        sim.setFetch(makeFetch({ result: mockManifest(aiOnly) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        panel.querySelector('.sim-filter-btn[data-filter="local"]').click();
        expect(panel.querySelector('.sim-state .sim-empty').textContent).toBe('该类型暂无模拟器');
        expect(panel.querySelector('.sim-count').textContent).toContain('共 0 款');
    });

    it('错误态重试：点重试 → 重新 fetch → ready', async () => {
        const { sim, panel } = await loadModules();
        const fetchSpy = makeFetch({ fail: new Error('网络错误') });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();
        expect(panel.querySelector('.sim-retry-btn')).not.toBeNull();

        // 第二次 fetch 成功（fetch mock 换路由）
        fetchSpy.mockImplementation(() => Promise.resolve(mockManifest(MANIFEST_OK)));
        panel.querySelector('.sim-retry-btn').click();
        await vi.waitFor(() => expect(panel.querySelectorAll('.sim-card')).toHaveLength(2));
        expect(fetchSpy).toHaveBeenCalledTimes(2);
    });

    it('卡片点击 → 注入的 onOpenGame 收到完整 game 对象', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        const openSpy = vi.fn();
        sim.initSimulatorsView({ container: panel, onOpenGame: openSpy });
        await sim.refreshSimulators();

        panel.querySelector('.sim-card[data-id="spider-shadow"]').click();
        expect(openSpy).toHaveBeenCalledTimes(1);
        expect(openSpy).toHaveBeenCalledWith({
            id: 'spider-shadow',
            file: '蛛网之影.html',
            name: '蛛网之影',
            type: 'local',
            description: '纯本地角色扮演',
        });
    });

    it('Falsify:未注入 onOpenGame → 点击卡片 no-op 不抛错', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(() => panel.querySelector('.sim-card').click()).not.toThrow();
    });

    it('Falsify:点击 data-id 不在缓存列表的卡片（陈旧 DOM）→ no-op 不抛错', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        const openSpy = vi.fn();
        sim.initSimulatorsView({ container: panel, onOpenGame: openSpy });
        await sim.refreshSimulators();

        // 程序化注入一个缓存中不存在的陈旧卡片
        panel.querySelector('.sim-state').insertAdjacentHTML(
            'beforeend', '<article class="sim-card" data-id="ghost">幽灵</article>',
        );
        expect(() => panel.querySelector('.sim-card[data-id="ghost"]').click()).not.toThrow();
        expect(openSpy).not.toHaveBeenCalled();
    });

    it('Falsify:initSimulatorsView 无 container → no-op 不抛错', async () => {
        const { sim } = await loadModules();
        expect(() => sim.initSimulatorsView({})).not.toThrow();
        expect(() => sim.initSimulatorsView()).not.toThrow();
    });

    it('Falsify:未 init 调 refreshSimulators → no-op 不抛错', async () => {
        const { sim } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        await expect(sim.refreshSimulators()).resolves.toBeUndefined();
    });

    it('重复 initSimulatorsView：钩子取最新注入值，事件不重复绑定（幂等）', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        const hook1 = vi.fn();
        const hook2 = vi.fn();
        sim.initSimulatorsView({ container: panel, onOpenGame: hook1 });
        sim.initSimulatorsView({ container: panel, onOpenGame: hook2 });
        await sim.refreshSimulators();

        // 点击卡片 → 最新钩子被调用（重复 init 仅更新钩子）
        panel.querySelector('.sim-card').click();
        expect(hook2).toHaveBeenCalledTimes(1);
        expect(hook1).not.toHaveBeenCalled();
        // 筛选按钮不重复绑定：单次点击仍只重渲染一次（无异常）
        panel.querySelector('.sim-filter-btn[data-filter="ai"]').click();
        expect(panel.querySelectorAll('.sim-card')).toHaveLength(1);
    });

    it('setFetch(null) 恢复 → 回落全局 fetch（seam 契约）', async () => {
        const { sim, panel } = await loadModules();
        const globalSpy = vi.fn(() => Promise.resolve(mockManifest(MANIFEST_OK)));
        vi.stubGlobal('fetch', globalSpy);
        sim.setFetch(makeFetch({ result: mockManifest({ version: 1, simulators: [] }) }));
        sim.initSimulatorsView({ container: panel });

        sim.setFetch(null); // mock 恢复 null → 回落全局 fetch
        await sim.refreshSimulators();
        expect(globalSpy).toHaveBeenCalledTimes(1);
        expect(globalSpy.mock.calls[0][0]).toContain('simulators/manifest.json');
        vi.unstubAllGlobals();
    });
});
