/**
 * 模拟器列表模块测试（U7-T3）。
 *
 * 覆盖：
 *   - parseManifest 纯函数：合法归一化（v1/v2）/ 畸形 JSON / 非字符串输入 /
 *     顶层非对象 / version 不兼容（仅接受 1/2）/ simulators 缺失或非数组 /
 *     id 缺失或重复 / file 缺失 / type 非法 / 条目非对象 /
 *     条目级字段缺失宽容降级 / 空列表
 *   - parseManifest v2 saveKeys（U9-T1）：v2 归一化透出 / v1 缺 saveKeys 降级
 *     （无 saveKeys 属性 = 「无存档管理」信号）/ saveKeyPrefix 仅 v1 兼容透传 /
 *     saveKeys 结构非法条目级降级 / 模式不可编译与空串元素级剔除 /
 *     模式自含 ^$ 锚点条目级降级 / 清洗后空数组保留 / 混合 v1+v2 条目
 *   - filterGames 纯函数三档：全部（含未知 type 计入全部）/ AI / 纯本地 /
 *     未知筛选类型返回全部 / 非数组输入
 *   - canReprobeGame 纯函数判定矩阵（T-01）：local 恒 true / ai+imported true /
 *     ai 无 source 与 ai+generated false / 非对象与 type/source 非法输入 false 不抛错
 *   - 重新识别按钮渲染契约（T-01）：local 与 ai+imported 卡片渲染按钮
 *     （class/data-action/title/文案 DOM 契约不变），ai 无 source 与 ai+generated 不渲染；
 *     ai+imported 点击走与 local 相同的 POST reprobe → 刷新闭环
 *   - 四态渲染（fetch 经 setFetch seam 注入）：loading / ready（卡片网格）/
 *     error（错误文案 + 重试按钮）/ empty（空态文案）；错误态重试重新 fetch
 *   - 筛选交互：三档切换即重渲染 + 计数 + active 类迁移；筛选无匹配 → 空态
 *   - 卡片点击：注入 onOpenGame 收到完整 game；未注入 no-op 不抛错
 *   - Falsify：无 container no-op / 未 init 调 refresh no-op / 重复 init 幂等
 *     （钩子取最新）/ setFetch(null) 回落全局 fetch
 *   - U9-T2：工具条「存档管理」按钮渲染与点击钩子（onOpenSaveManager）、
 *     getGames() 公开读取游戏列表缓存（存档面板数据源）、幂等钩子更新
 *
 * 测试即模块接口契约：公开面 __all__ = initSimulatorsView / refreshSimulators /
 *   parseManifest / filterGames / canReprobeGame / getGames / setFetch（fetch 注入点
 *   单一来源 js/fetch-seam.js（TD-51/55/60）— api.js 与 simulators.js 共享同一
 *   setFetch/doFetch，一次注入两模块同时生效；setFetch(null) 恢复回落全局 fetch）。
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

/** v2 合法 manifest（U9-T1）：saveKeys 字符串数组 = 精确键 + 锚定正则模式（与 U9-T2 共享契约） */
const MANIFEST_V2 = {
    version: 2,
    simulators: [
        {
            id: 'life-sim',
            file: '人生模拟器v3.html',
            name: '人生模拟器 v3',
            type: 'ai',
            description: 'AI 驱动的生命模拟',
            saveKeys: ['ls_autosave', 'ls_used_names'],
            config: { endpoint: 'cfg-endpoint', apikey: 'cfg-apikey', model: 'cfg-model' },
        },
        {
            id: 'urban-god',
            file: '神明v3.html',
            name: '神明 v3',
            type: 'ai',
            description: 'AI 驱动的都市神明模拟',
            saveKeys: ['god_autosave', 'god_save_\\d+'],
            config: { endpoint: 'cfg-endpoint', apikey: 'cfg-apikey', model: 'cfg-model' },
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
    it('__all__ 收口公开函数与 fetch seam（含 U9-T2 getGames / T-01 canReprobeGame）', async () => {
        const { sim } = await loadModules();
        expect(sim.__all__.sort()).toEqual([
            'canReprobeGame',
            'filterGames',
            'getGames',
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

    it('endpointMode 透传：base/full 字符串 → 条目带 endpointMode（SIM-API-1 端点口径契约）', async () => {
        const { sim } = await loadModules();
        const data = {
            version: 2,
            simulators: [
                { id: 'a', file: 'a.html', type: 'ai', name: 'A', endpointMode: 'full', config: { endpoint: 'e', apikey: 'k', model: 'm' } },
                { id: 'b', file: 'b.html', type: 'ai', name: 'B', endpointMode: 'base', config: { endpoint: 'e', apikey: 'k', model: 'm' } },
            ],
        };
        const result = sim.parseManifest(JSON.stringify(data));
        expect(result.ok).toBe(true);
        expect(result.games[0].endpointMode).toBe('full');
        expect(result.games[1].endpointMode).toBe('base');
    });

    it('endpointMode 非法值 / 缺失 → 条目级降级（剔除该字段 — 注入按不转换处理，不整体失败）', async () => {
        const { sim } = await loadModules();
        const data = {
            version: 2,
            simulators: [
                { id: 'a', file: 'a.html', type: 'ai', name: 'A', endpointMode: 'weird', config: { endpoint: 'e', apikey: 'k', model: 'm' } },
                { id: 'b', file: 'b.html', type: 'ai', name: 'B', endpointMode: 42, config: { endpoint: 'e', apikey: 'k', model: 'm' } },
                { id: 'c', file: 'c.html', type: 'ai', name: 'C', config: { endpoint: 'e', apikey: 'k', model: 'm' } },
            ],
        };
        const result = sim.parseManifest(JSON.stringify(data));
        expect(result.ok).toBe(true);
        for (const game of result.games) {
            expect('endpointMode' in game, `endpointMode 剔除: ${game.id}`).toBe(false);
        }
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

    it('version 不兼容（缺失 / 非 1 或 2）→ ok:false，「manifest 版本不兼容」', async () => {
        const { sim } = await loadModules();
        expect(sim.parseManifest(JSON.stringify({ simulators: [] })).error).toBe('manifest 版本不兼容');
        expect(sim.parseManifest(JSON.stringify({ version: 0, simulators: [] })).error).toBe('manifest 版本不兼容');
        expect(sim.parseManifest(JSON.stringify({ version: 3, simulators: [] })).error).toBe('manifest 版本不兼容');
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

describe('parseManifest — v2 saveKeys 归一化 / v1 降级兼容（U9-T1）', () => {
    it('v2 合法 manifest → saveKeys 原样透出（精确键与正则模式字符串），无 saveKeyPrefix', async () => {
        const { sim } = await loadModules();
        const result = sim.parseManifest(JSON.stringify(MANIFEST_V2));
        expect(result.ok).toBe(true);
        expect(result.games[0].saveKeys).toEqual(['ls_autosave', 'ls_used_names']);
        expect(result.games[1].saveKeys).toEqual(['god_autosave', 'god_save_\\d+']);
        expect('saveKeyPrefix' in result.games[0]).toBe(false);
    });

    it('v1 条目缺 saveKeys → 归一化条目无 saveKeys 属性（降级信号 = undefined，「无存档管理」）', async () => {
        const { sim } = await loadModules();
        const result = sim.parseManifest(JSON.stringify(MANIFEST_OK));
        expect(result.ok).toBe(true);
        expect('saveKeys' in result.games[0]).toBe(false);
        expect(result.games[0].saveKeys).toBeUndefined();
    });

    it('v1 条目带 saveKeyPrefix → 兼容透传（退役字段仅 v1 数据携带，不参与存档语义）', async () => {
        const { sim } = await loadModules();
        const result = sim.parseManifest(JSON.stringify(MANIFEST_OK));
        expect(result.games[0].saveKeyPrefix).toBe('ls_');
    });

    it('混合 v1/v2 条目 → 各自归一化：v2 透出 saveKeys，v1 无 saveKeys 属性', async () => {
        const { sim } = await loadModules();
        const mixed = { version: 2, simulators: [MANIFEST_V2.simulators[0], MANIFEST_OK.simulators[1]] };
        const result = sim.parseManifest(JSON.stringify(mixed));
        expect(result.ok).toBe(true);
        expect(result.games[0].saveKeys).toEqual(['ls_autosave', 'ls_used_names']);
        expect('saveKeys' in result.games[1]).toBe(false);
        expect(result.games[1].id).toBe('spider-shadow');
    });

    it('Falsify:saveKeys 非数组 → 条目级降级（saveKeys 剔除），不整体失败', async () => {
        const { sim } = await loadModules();
        const bad = { ...MANIFEST_V2.simulators[0], saveKeys: 'ls_autosave' };
        const result = sim.parseManifest(JSON.stringify({ version: 2, simulators: [bad] }));
        expect(result.ok).toBe(true);
        expect('saveKeys' in result.games[0]).toBe(false);
        expect(result.games[0].id).toBe('life-sim');
    });

    it('Falsify:saveKeys 元素非字符串（含 null）→ 条目级降级', async () => {
        const { sim } = await loadModules();
        const bad = { ...MANIFEST_V2.simulators[0], saveKeys: ['ls_autosave', null] };
        const result = sim.parseManifest(JSON.stringify({ version: 2, simulators: [bad] }));
        expect(result.ok).toBe(true);
        expect('saveKeys' in result.games[0]).toBe(false);
    });

    it('Falsify:模式元素无法编译 → 剔除该项，其余元素保留（元素级降级）', async () => {
        const { sim } = await loadModules();
        const bad = { ...MANIFEST_V2.simulators[1], saveKeys: ['god_autosave', 'god_save_[', 'god_save_\\d+'] };
        const result = sim.parseManifest(JSON.stringify({ version: 2, simulators: [bad] }));
        expect(result.ok).toBe(true);
        expect(result.games[0].saveKeys).toEqual(['god_autosave', 'god_save_\\d+']);
    });

    it('Falsify:空字符串元素 → 剔除该项（元素级降级）', async () => {
        const { sim } = await loadModules();
        const bad = { ...MANIFEST_V2.simulators[0], saveKeys: ['ls_autosave', ''] };
        const result = sim.parseManifest(JSON.stringify({ version: 2, simulators: [bad] }));
        expect(result.ok).toBe(true);
        expect(result.games[0].saveKeys).toEqual(['ls_autosave']);
    });

    it('Falsify:模式自含 ^ / $ 锚点 → 条目级降级（锚定由匹配方统一加，数据不得自锚定）', async () => {
        const { sim } = await loadModules();
        const bad = { ...MANIFEST_V2.simulators[1], saveKeys: ['^god_autosave$'] };
        const result = sim.parseManifest(JSON.stringify({ version: 2, simulators: [bad] }));
        expect(result.ok).toBe(true);
        expect('saveKeys' in result.games[0]).toBe(false);
    });

    it('Falsify:清洗后为空数组 → 保留空数组（结构性合法，非降级信号）', async () => {
        const { sim } = await loadModules();
        const bad = { ...MANIFEST_V2.simulators[1], saveKeys: ['god_save_[', ''] };
        const result = sim.parseManifest(JSON.stringify({ version: 2, simulators: [bad] }));
        expect(result.ok).toBe(true);
        expect(result.games[0].saveKeys).toEqual([]);
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

describe('canReprobeGame — 重新识别按钮判据矩阵（T-01）', () => {
    it('local 类型（无 source）→ true（行为基线不变）', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame({ type: 'local' })).toBe(true);
    });

    it('ai 类型 + source=imported（历史误探为 ai 的老条目）→ true', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame({ type: 'ai', source: 'imported' })).toBe(true);
    });

    it('ai 类型无 source（内置 AI 条目）→ false', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame({ type: 'ai' })).toBe(false);
    });

    it('ai 类型 + source=generated（AI 生成条目）→ false', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame({ type: 'ai', source: 'generated' })).toBe(false);
    });

    it('local 类型 + source=generated → true（local 无条件可 reprobe）', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame({ type: 'local', source: 'generated' })).toBe(true);
    });

    it('Falsify:非对象输入（null / undefined / 字符串 / 数组）→ false 不抛错', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame(null)).toBe(false);
        expect(sim.canReprobeGame(undefined)).toBe(false);
        expect(sim.canReprobeGame('x')).toBe(false);
        expect(sim.canReprobeGame([])).toBe(false);
    });

    it('Falsify:type 缺失 / 非法（未知值 / 大小写 / 非字符串）→ false 不抛错', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame({})).toBe(false);
        expect(sim.canReprobeGame({ type: 'AI' })).toBe(false);
        expect(sim.canReprobeGame({ type: 'web' })).toBe(false);
        expect(sim.canReprobeGame({ type: 42 })).toBe(false);
    });

    it('Falsify:source 缺失 / 类型非法（数字）→ false（仅 ai+imported 精确匹配为 true）', async () => {
        const { sim } = await loadModules();
        expect(sim.canReprobeGame({ source: 'imported' })).toBe(false); // 无 type
        expect(sim.canReprobeGame({ type: 'ai', source: 42 })).toBe(false);
        expect(sim.canReprobeGame({ type: 'ai', source: null })).toBe(false);
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
        sim.setFetch(makeFetch({ result: mockManifest({ version: 3, simulators: [] }) }));
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

    it('local 卡片渲染「重新识别」按钮，ai 卡片不渲染（DOM 契约锁定：class/data-action/title/文案）', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        const localCard = panel.querySelector('.sim-card[data-id="spider-shadow"]');
        const reprobeBtn = localCard.querySelector('.sim-reprobe-btn');
        expect(reprobeBtn).not.toBeNull();
        expect(reprobeBtn.textContent).toContain('重新识别');
        // DOM 契约（T-01 锁定，不随渲染条件重构改变）：data-action / title 是
        // 事件委托与用户提示的载重字段
        expect(reprobeBtn.getAttribute('data-action')).toBe('reprobe');
        expect(reprobeBtn.getAttribute('title')).toBe('重新识别类型');

        const aiCard = panel.querySelector('.sim-card[data-id="life-sim"]');
        expect(aiCard.querySelector('.sim-reprobe-btn')).toBeNull();
    });

    it('T-01 渲染契约：ai+imported 卡片渲染「重新识别」按钮；ai+generated / 内置 ai 卡片不渲染；local 含 source 亦渲染', async () => {
        const { sim, panel } = await loadModules();
        const data = {
            version: 2,
            simulators: [
                { id: 'built-in-ai', file: 'built.html', name: '内置 AI', type: 'ai' },
                { id: 'imported-ai', file: 'imported-ai.html', name: '误探 AI', type: 'ai', source: 'imported' },
                { id: 'generated-ai', file: 'gen.html', name: '生成的 AI', type: 'ai', source: 'generated' },
                { id: 'local-imported', file: 'local-imported.html', name: '导入的本地', type: 'local', source: 'imported' },
            ],
        };
        sim.setFetch(makeFetch({ result: mockManifest(data) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(panel.querySelector('.sim-card[data-id="built-in-ai"] .sim-reprobe-btn')).toBeNull();
        expect(panel.querySelector('.sim-card[data-id="imported-ai"] .sim-reprobe-btn')).not.toBeNull();
        expect(panel.querySelector('.sim-card[data-id="generated-ai"] .sim-reprobe-btn')).toBeNull();
        expect(panel.querySelector('.sim-card[data-id="local-imported"] .sim-reprobe-btn')).not.toBeNull();
    });

    it('点击「重新识别」→ POST reprobe 端点 → 刷新列表', async () => {
        const { sim, panel } = await loadModules();
        // 路由 fetch：manifest 请求返回正常，reprobe 请求返回成功
        const fetchSpy = vi.fn(async (url, opts) => {
            if (url.includes('/api/simulators/reprobe')) {
                return Promise.resolve({
                    ok: true,
                    status: 200,
                    json: async () => ({ ok: true, game: { id: 'spider-shadow', type: 'ai', config: { endpoint: 's-endpoint', apikey: 's-key', model: 's-model' } } }),
                });
            }
            return Promise.resolve(mockManifest(MANIFEST_OK));
        });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        // 初始 local 卡片有重新识别按钮
        const localCard = panel.querySelector('.sim-card[data-id="spider-shadow"]');
        expect(localCard.querySelector('.sim-reprobe-btn')).not.toBeNull();

        // 点击重新识别 → 请求 reprobe 端点
        localCard.querySelector('.sim-reprobe-btn').click();

        // 等待 DOS 回调（showSuccess 触发 + refreshSimulators 触发）
        await vi.waitFor(() => {
            // reprobe 应被调用一次
            const reprobeCalls = fetchSpy.mock.calls.filter(c => c[0].includes('/api/simulators/reprobe'));
            expect(reprobeCalls).toHaveLength(1);
        });
    });

    it('T-01：ai+imported 卡片点击「重新识别」→ 与 local 相同 reprobe 流程（POST 端点 + 列表刷新闭环）', async () => {
        const { sim, panel } = await loadModules();
        const data = {
            version: 2,
            simulators: [
                { id: 'life-sim', file: '人生模拟器v3.html', name: '人生模拟器 v3', type: 'ai' },
                // 历史误探：本为 local，被误识为 ai；source=imported 标记已导入（T-01）
                { id: 'spider-shadow', file: '蛛网之影.html', name: '蛛网之影', type: 'ai', source: 'imported' },
            ],
        };
        let reprobed = false;
        const fetchSpy = vi.fn(async (url, opts) => {
            if (url.includes('/api/simulators/reprobe')) {
                reprobed = true;
                // 服务端重探成功：条目识别为 local（manifest 原子更新由服务端完成）
                return Promise.resolve({ ok: true, status: 200, json: async () => ({ ok: true, game: { id: 'spider-shadow', type: 'local' } }) });
            }
            // 重探成功后刷新返回更新后的 manifest：spider-shadow 现为 local
            return Promise.resolve(mockManifest(reprobed
                ? { ...data, simulators: data.simulators.map((s) => (s.id === 'spider-shadow' ? { ...s, type: 'local' } : s)) }
                : data));
        });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        // 初始：ai+imported 卡片已渲染重新识别按钮（T-01 渲染契约）
        const aiImportedCard = panel.querySelector('.sim-card[data-id="spider-shadow"]');
        expect(aiImportedCard.querySelector('.sim-reprobe-btn')).not.toBeNull();

        aiImportedCard.querySelector('.sim-reprobe-btn').click();

        // 与 local 相同的 POST reprobe 流程
        await vi.waitFor(() => {
            const reprobeCalls = fetchSpy.mock.calls.filter((c) => c[0].includes('/api/simulators/reprobe'));
            expect(reprobeCalls).toHaveLength(1);
        });
        // 重探成功后刷新列表：条目渲染为 local（重新识别闭环）
        await vi.waitFor(() => {
            const tag = panel.querySelector('.sim-card[data-id="spider-shadow"] .sim-type-tag');
            expect(tag?.textContent).toBe('纯本地');
        });
    });

    it('重新识别失败 → 列表不销毁', async () => {
        const { sim, panel } = await loadModules();
        const fetchSpy = vi.fn(async (url, opts) => {
            if (url.includes('/api/simulators/reprobe')) {
                return Promise.resolve({ ok: false, status: 404, json: async () => ({ detail: '游戏不存在' }) });
            }
            return Promise.resolve(mockManifest(MANIFEST_OK));
        });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        // 初始有 2 张卡片
        expect(panel.querySelectorAll('.sim-card')).toHaveLength(2);

        // 点击重新识别 → 失败
        const localCard = panel.querySelector('.sim-card[data-id="spider-shadow"]');
        localCard.querySelector('.sim-reprobe-btn').click();

        // 等待片刻，列表不应消失（仍含 2 卡）
        await vi.waitFor(() => {
            expect(panel.querySelectorAll('.sim-card')).toHaveLength(2);
        });
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

describe('simulators — 存档管理按钮与 getGames（U9-T2）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('工具条渲染「存档管理」按钮（与筛选按钮/计数同工具条）', async () => {
        const { sim, panel } = await loadModules();
        sim.initSimulatorsView({ container: panel });

        const btn = panel.querySelector('.sim-save-manage-btn');
        expect(btn).not.toBeNull();
        expect(btn.textContent).toBe('存档管理');
        expect(panel.querySelector('.sim-count')).not.toBeNull();
    });

    it('点击「存档管理」按钮 → 注入的 onOpenSaveManager 钩子被调用', async () => {
        const { sim, panel } = await loadModules();
        const saveSpy = vi.fn();
        sim.initSimulatorsView({ container: panel, onOpenSaveManager: saveSpy });

        panel.querySelector('.sim-save-manage-btn').click();
        expect(saveSpy).toHaveBeenCalledTimes(1);
    });

    it('Falsify:未注入 onOpenSaveManager → 点击 no-op 不抛错', async () => {
        const { sim, panel } = await loadModules();
        sim.initSimulatorsView({ container: panel });

        expect(() => panel.querySelector('.sim-save-manage-btn').click()).not.toThrow();
    });

    it('重复 init：onOpenSaveManager 取最新注入值（幂等钩子更新）', async () => {
        const { sim, panel } = await loadModules();
        const hook1 = vi.fn();
        const hook2 = vi.fn();
        sim.initSimulatorsView({ container: panel, onOpenSaveManager: hook1 });
        sim.initSimulatorsView({ container: panel, onOpenSaveManager: hook2 });

        panel.querySelector('.sim-save-manage-btn').click();
        expect(hook2).toHaveBeenCalledTimes(1);
        expect(hook1).not.toHaveBeenCalled();
    });

    it('getGames：refresh 后返回最近一次解析的游戏列表（存档面板数据源）', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(makeFetch({ result: mockManifest(MANIFEST_OK) }));
        sim.initSimulatorsView({ container: panel });
        expect(sim.getGames()).toEqual([]); // 未加载 → 空数组

        await sim.refreshSimulators();
        expect(sim.getGames().map((g) => g.id)).toEqual(['life-sim', 'spider-shadow']);
    });

    it('Falsify:未 init 调 getGames → 空数组不炸', async () => {
        const { sim } = await loadModules();
        expect(sim.getGames()).toEqual([]);
    });
});

describe('simulators — 清单加载超时与并发守卫（TD-51/55/60）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

    it('清单加载挂起 15s → 超时错误态含原因与重试按钮，重试可重新加载', async () => {
        const { sim, panel } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        const fetchSpy = makeFetch({ pending });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });

        vi.useFakeTimers();
        try {
            const refreshPromise = sim.refreshSimulators();
            expect(panel.querySelector('.sim-state').innerHTML).toContain('加载中…');
            await vi.advanceTimersByTimeAsync(15000);
            expect(panel.querySelector('.sim-error-msg').textContent).toBe('模拟器列表加载失败');
            expect(panel.querySelector('.sim-error-reason').textContent).toBe('模拟器清单加载超时（15 秒未收到响应）');
            expect(panel.querySelector('.sim-retry-btn')).not.toBeNull();
            await refreshPromise;
        } finally {
            vi.useRealTimers();
        }

        // 重试出口：点重试 → 重新 fetch → ready（真实计时器 + 既有 waitFor 模式）
        fetchSpy.mockImplementation(() => Promise.resolve(mockManifest(MANIFEST_OK)));
        panel.querySelector('.sim-retry-btn').click();
        await vi.waitFor(() => expect(panel.querySelectorAll('.sim-card')).toHaveLength(2));
        expect(fetchSpy).toHaveBeenCalledTimes(2);
    });

    it('响应体读取挂起（headers 已到，text() 永不结算）→ 15s 仍进超时错误态（两阶段守卫覆盖读取阶段，TD-72）', async () => {
        const { sim, panel } = await loadModules();
        // 响应头阶段正常完成（ok:true 立即到达），但响应体 text() 永久挂起 —
        // 旧实现 return res.text() 在返回求值处即清计时器，读取阶段不受守卫
        const fetchSpy = makeFetch({ result: Promise.resolve({ ok: true, status: 200, text: () => new Promise(() => {}) }) });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });

        vi.useFakeTimers();
        try {
            const refreshPromise = sim.refreshSimulators();
            expect(panel.querySelector('.sim-state').innerHTML).toContain('加载中…');
            await vi.advanceTimersByTimeAsync(15000);
            expect(panel.querySelector('.sim-error-msg').textContent).toBe('模拟器列表加载失败');
            expect(panel.querySelector('.sim-error-reason').textContent).toBe('模拟器清单加载超时（15 秒未收到响应）');
            expect(panel.querySelector('.sim-retry-btn')).not.toBeNull();
            await refreshPromise;
        } finally {
            vi.useRealTimers();
        }
    });

    it('清单 fetch 携带 cache:no-store（导入后刷新必须拿到新鲜 manifest — 静态挂载带 ETag/Last-Modified，浏览器条件请求 304 会用缓存旧数据，新导入卡片不出现）', async () => {
        const { sim, panel } = await loadModules();
        const fetchSpy = makeFetch({ result: mockManifest(MANIFEST_OK) });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        expect(fetchSpy.mock.calls[0][1].cache).toBe('no-store');
        expect(panel.querySelectorAll('.sim-card')).toHaveLength(2);
    });

    it('响应体读取阶段超时 → abort 已触发（signal.aborted 为真）且同超时文案（TD-72）', async () => {
        const { sim, panel } = await loadModules();
        // 记录 doFetch 收到的 AbortSignal — 读取阶段挂起到点后必须通知真实 fetch 断开
        const fetchSpy = vi.fn(() => Promise.resolve({ ok: true, status: 200, text: () => new Promise(() => {}) }));
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });

        vi.useFakeTimers();
        try {
            const refreshPromise = sim.refreshSimulators();
            await vi.advanceTimersByTimeAsync(15000);
            expect(panel.querySelector('.sim-error-reason').textContent).toBe('模拟器清单加载超时（15 秒未收到响应）');
            expect(fetchSpy.mock.calls[0][1].signal.aborted).toBe(true); // abort 通知真实 fetch 断开
            await refreshPromise;
        } finally {
            vi.useRealTimers();
        }
    });

    it('双 refresh 并发：慢旧请求后到不覆盖新渲染（seq 守卫 await 出口）', async () => {
        const { sim, panel } = await loadModules();
        const OLD = { version: 1, simulators: [{ id: 'old-game', file: 'old.html', name: '旧数据', type: 'ai' }] };
        const NEW = { version: 1, simulators: [{ id: 'new-game', file: 'new.html', name: '新数据', type: 'ai' }] };
        let resolveOld;
        const oldPending = new Promise((r) => { resolveOld = r; });
        let calls = 0;
        const fetchSpy = vi.fn(() => {
            calls += 1;
            return calls === 1 ? oldPending : Promise.resolve(mockManifest(NEW));
        });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });

        const first = sim.refreshSimulators();
        const second = sim.refreshSimulators();
        await second;
        expect(panel.querySelector('.sim-card-name').textContent).toBe('新数据');

        resolveOld(mockManifest(OLD)); // 旧请求迟到 → 不得覆盖新渲染
        await first;
        expect(panel.querySelector('.sim-card-name').textContent).toBe('新数据');
        expect(panel.querySelectorAll('.sim-card')).toHaveLength(1);
    });

    it('双 refresh 并发：慢旧请求错误后到不覆盖新渲染（seq 守卫 catch 出口）', async () => {
        const { sim, panel } = await loadModules();
        let rejectOld;
        const oldPending = new Promise((_, r) => { rejectOld = r; });
        let calls = 0;
        const fetchSpy = vi.fn(() => {
            calls += 1;
            return calls === 1 ? oldPending : Promise.resolve(mockManifest(MANIFEST_OK));
        });
        sim.setFetch(fetchSpy);
        sim.initSimulatorsView({ container: panel });

        const first = sim.refreshSimulators();
        const second = sim.refreshSimulators();
        await second;
        expect(panel.querySelectorAll('.sim-card')).toHaveLength(2);

        rejectOld(new Error('迟到的错误')); // 旧请求迟到失败 → 不得覆盖新渲染
        await first;
        expect(panel.querySelectorAll('.sim-card')).toHaveLength(2);
        expect(panel.querySelector('.sim-error-msg')).toBeNull();
    });

    it('超时后迟到响应不覆盖错误态', async () => {
        const { sim, panel } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        sim.setFetch(makeFetch({ pending }));
        sim.initSimulatorsView({ container: panel });

        vi.useFakeTimers();
        try {
            const refreshPromise = sim.refreshSimulators();
            await vi.advanceTimersByTimeAsync(15000);
            expect(panel.querySelector('.sim-error-reason').textContent).toBe('模拟器清单加载超时（15 秒未收到响应）');

            pending.resolve(mockManifest(MANIFEST_OK)); // 超时后迟到响应
            await refreshPromise;
            await vi.advanceTimersByTimeAsync(0); // 冲刷微任务
            expect(panel.querySelector('.sim-error-reason').textContent).toBe('模拟器清单加载超时（15 秒未收到响应）');
            expect(panel.querySelectorAll('.sim-card')).toHaveLength(0);
        } finally {
            vi.useRealTimers();
        }
    });

    it('Falsify:注入 fetch 同步抛错 → error 态兜底（超时计时器路径不泄漏）', async () => {
        const { sim, panel } = await loadModules();
        sim.setFetch(() => { throw new Error('同步爆炸'); });
        sim.initSimulatorsView({ container: panel });

        await sim.refreshSimulators();
        expect(panel.querySelector('.sim-error-msg').textContent).toBe('模拟器列表加载失败');
        expect(panel.querySelector('.sim-error-reason').textContent).toBe('同步爆炸');
        expect(panel.querySelector('.sim-retry-btn')).not.toBeNull();
    });
});

describe('simulators — source 标识与导入入口（工单 04）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('parseManifest：source 为字符串 \'imported\' 或 \'generated\' → 透传 source 字段（白名单）', async () => {
        const { sim } = await loadModules();
        const data = {
            version: 2,
            simulators: [
                { id: 'a', file: 'a.html', name: 'A', type: 'local', source: 'imported' },
                { id: 'b', file: 'b.html', name: 'B', type: 'local' },
                { id: 'c', file: 'c.html', name: 'C', type: 'local', source: 'generated' },
            ],
        };
        const result = sim.parseManifest(JSON.stringify(data));
        expect(result.ok).toBe(true);
        expect(result.games[0].source).toBe('imported');
        expect('source' in result.games[1]).toBe(false); // 内置条目无 source 字段
        expect(result.games[2].source).toBe('generated');
    });

    it('parseManifest：source 非白名单（builtin / 数字 / null）→ 条目级降级剔除（白名单限 imported/generated）', async () => {
        const { sim } = await loadModules();
        const data = {
            version: 2,
            simulators: [
                { id: 'a', file: 'a.html', name: 'A', type: 'local', source: 'builtin' },
                { id: 'b', file: 'b.html', name: 'B', type: 'local', source: 42 },
                { id: 'c', file: 'c.html', name: 'C', type: 'local', source: null },
            ],
        };
        const result = sim.parseManifest(JSON.stringify(data));
        expect(result.ok).toBe(true);
        for (const game of result.games) {
            expect('source' in game, `source 剔除: ${game.id}`).toBe(false);
        }
    });

    it('ready 渲染：source=imported 卡片带「已导入」badge；source=generated 卡片带「AI 生成」badge；内置卡片无 badge', async () => {
        const { sim, panel } = await loadModules();
        const data = {
            version: 2,
            simulators: [
                { id: 'built-in', file: 'b.html', name: '内置', type: 'ai' },
                { id: 'imported-x', file: 'x.html', name: '第三方', type: 'local', source: 'imported' },
                { id: 'generated-y', file: 'y.html', name: 'AI 作品', type: 'ai', source: 'generated' },
            ],
        };
        sim.setFetch(makeFetch({ result: mockManifest(data) }));
        sim.initSimulatorsView({ container: panel });
        await sim.refreshSimulators();

        const importedCard = panel.querySelector('.sim-card[data-id="imported-x"]');
        expect(importedCard.querySelector('.sim-source-tag')).not.toBeNull();
        expect(importedCard.querySelector('.sim-source-tag').textContent).toBe('已导入');
        const generatedCard = panel.querySelector('.sim-card[data-id="generated-y"]');
        expect(generatedCard.querySelector('.sim-source-tag')).not.toBeNull();
        expect(generatedCard.querySelector('.sim-source-tag').textContent).toBe('AI 生成');
        expect(generatedCard.querySelector('.sim-source-generated')).not.toBeNull();
        const builtinCard = panel.querySelector('.sim-card[data-id="built-in"]');
        expect(builtinCard.querySelector('.sim-source-tag')).toBeNull();
    });

    it('工具条渲染「导入游戏」按钮（与筛选/存档管理按钮同工具条）', async () => {
        const { sim, panel } = await loadModules();
        sim.initSimulatorsView({ container: panel });

        const btn = panel.querySelector('.sim-import-btn');
        expect(btn).not.toBeNull();
        expect(btn.textContent).toBe('导入游戏');
    });

    it('点击「导入游戏」→ 注入的 onImportGame 钩子被调用', async () => {
        const { sim, panel } = await loadModules();
        const importSpy = vi.fn();
        sim.initSimulatorsView({ container: panel, onImportGame: importSpy });

        panel.querySelector('.sim-import-btn').click();
        expect(importSpy).toHaveBeenCalledTimes(1);
    });

    it('Falsify:未注入 onImportGame → 点击 no-op 不抛错', async () => {
        const { sim, panel } = await loadModules();
        sim.initSimulatorsView({ container: panel });

        expect(() => panel.querySelector('.sim-import-btn').click()).not.toThrow();
    });

    it('重复 init：onImportGame 取最新注入值（幂等钩子更新）', async () => {
        const { sim, panel } = await loadModules();
        const hook1 = vi.fn();
        const hook2 = vi.fn();
        sim.initSimulatorsView({ container: panel, onImportGame: hook1 });
        sim.initSimulatorsView({ container: panel, onImportGame: hook2 });

        panel.querySelector('.sim-import-btn').click();
        expect(hook2).toHaveBeenCalledTimes(1);
        expect(hook1).not.toHaveBeenCalled();
    });
});

describe('fetch-seam — 单源直测契约（TD-51/55/60）', () => {
    afterEach(() => { vi.useRealTimers(); });

    /** 加载全新 fetch-seam 模块（resetModules 保证每用例独立状态） */
    async function loadSeam() {
        vi.resetModules();
        return import('../js/fetch-seam.js');
    }

    it('setFetch 注入生效：doFetch 路由到注入实现（参数含 init 对象透传）', async () => {
        const seam = await loadSeam();
        const spy = vi.fn(async () => ({ ok: true }));
        seam.setFetch(spy);
        await seam.doFetch('https://example.com/x', { method: 'GET', signal: undefined });
        expect(spy).toHaveBeenCalledTimes(1);
        expect(spy).toHaveBeenCalledWith('https://example.com/x', { method: 'GET', signal: undefined });
        seam.setFetch(null); // 收尾恢复（跨用例不泄漏注入）
    });

    it('setFetch(null) 回落全局 fetch；非函数入参同回落（契约锁）', async () => {
        const seam = await loadSeam();
        const globalSpy = vi.fn(async () => ({ ok: true }));
        vi.stubGlobal('fetch', globalSpy);
        seam.setFetch(null);
        await seam.doFetch('/fallback');
        expect(globalSpy).toHaveBeenCalledTimes(1);
        expect(globalSpy).toHaveBeenCalledWith('/fallback');

        // Falsify:非函数入参（字符串）→ 与 null 同语义，回落全局 fetch
        seam.setFetch('not-a-function');
        await seam.doFetch('/fallback-2');
        expect(globalSpy).toHaveBeenCalledTimes(2);

        seam.setFetch(null);
        vi.unstubAllGlobals();
    });
});
