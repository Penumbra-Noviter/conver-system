/**
 * 存档管理模块测试（U9-T2）。
 *
 * 覆盖（纯函数 seam 优先，面板行为经 jsdom DOM 断言外部行为）：
 *   - collectGameKeys：saveKeys 白名单匹配 localStorage 键收集（精确键 /
 *     锚定正则模式 / 混合 / 空数组 / undefined 降级 / 去重 / 排序确定性 /
 *     cfg 键与主应用自身键不误收）
 *   - buildExportPayload：导出 JSON 形状 {game_id, game_name, saved_at,
 *     keys:{键:值}} 与收录规则（仅白名单命中且存在的键；cfg 键防御不导出）
 *   - validateImportPayload：合法包 / 任一非法键整包拒绝（列出全部非法键，
 *     至多 N 个）/ 坏结构 / 值非 string / 值 JSON 不可解析 / 正则键名匹配
 *     语义与收集一致 / 无 saveKeys 游戏整体拒绝
 *   - applyImportPayload：白名单键同名替换写回；非白名单键防御不写入
 *   - deleteGameKeys：清除全部命中键；主应用自身键不误伤
 *   - 面板开关与渲染：open → 列表隐藏/存档面板显示；返回 → 恢复；切走视图
 *     复位（closeSavePanel）；游戏行（键数/总大小/「无存档管理」/wg_ 族注记）
 *   - 操作流：导出（Blob 下载内容与文件名）、导入（合法恢复 / 非法整包拒绝
 *     不写任何键 / 坏 JSON / 文件过大 / 无 saveKeys 游戏）、删除（确认弹窗
 *     确认后清除 / 取消不删）
 *
 * 挂载模式：jsdom + vi.resetModules()（每用例全新模块状态）+ 内联面板 DOM
 * （与 index.html 的 #simulator-save-panel 契约一致）。
 * 存档读写 seam：jsdom 原生 localStorage（面板流）+ 测试侧 makeStorage 假件
 * （纯函数隔离用例，接口与 Storage 子集一致）。
 * Blob 下载：jsdom 未实现 URL.createObjectURL — 用例 stub 并捕获 Blob 引用
 * （FileReader 读回内容断言）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ══════════════════════════════════════════════════
// 夹具
// ══════════════════════════════════════════════════

/** 精确键白名单游戏（parseManifest 归一化形状 — 与 simulators.test.js 共享契约） */
const GAME_EXACT = {
    id: 'life-sim', file: '人生模拟器v3.html', name: '人生模拟器 v3', type: 'ai',
    saveKeys: ['ls_autosave', 'ls_used_names'],
};

/** 正则模式白名单游戏（锚定完整键名匹配） */
const GAME_REGEX = {
    id: 'urban-god', file: '神明v3.html', name: '神明 v3', type: 'ai',
    saveKeys: ['god_autosave', 'god_save_\\d+'],
};

/** 混合（精确 + 正则）白名单游戏 */
const GAME_MIXED = {
    id: 'twilight-witch', file: '暮色女巫v2.html', name: '暮色女巫 v2', type: 'ai',
    saveKeys: ['twilight_autosave', 'twilight_cps', 'twilight_deaths', 'twilight_slot_\\d+'],
};

/** wg_ 族游戏（仅会话内生效 — 面板注记；saveKeys 仍可管理） */
const GAME_WG = {
    id: 'my-little-pony', file: '小马宝莉.html', name: '小马宝莉', type: 'local',
    saveKeys: ['wg_xiaomabaoli_save'],
};

/** 无 saveKeys 游戏（「无存档管理」降级信号） */
const GAME_NO_SAVE = {
    id: 'spider-shadow', file: '蛛网之影.html', name: '蛛网之影', type: 'local',
};

/** 主应用自身键（当前主应用零 localStorage 键 — 测试以模拟键断言不误伤） */
const APP_OWN_KEY = 'conver_settings_v1';

/** 最小三面板 DOM — 与 index.html #view-simulators 契约一致（只读契约） */
const PANELS_HTML = `
    <div id="simulator-list-panel"></div>
    <div id="simulator-run-panel" hidden></div>
    <div id="simulator-save-panel" hidden></div>
`;

/** Storage 子集假件（纯函数隔离用例 — 与 jsdom localStorage 接口一致） */
function makeStorage(initial = {}) {
    const map = new Map(Object.entries(initial));
    return {
        get length() { return map.size; },
        key: (i) => (i >= 0 && i < map.size ? [...map.keys()][i] : null),
        getItem: (k) => (map.has(k) ? map.get(k) : null),
        setItem: (k, v) => { map.set(k, String(v)); },
        removeItem: (k) => { map.delete(k); },
        clear: () => { map.clear(); },
    };
}

/** 加载全新 save-manager 模块（DOM 先就位；返回模块 + 三面板引用） */
async function loadModules() {
    vi.resetModules();
    localStorage.clear();
    document.body.innerHTML = PANELS_HTML;
    const sim = await import('../js/save-manager.js');
    return {
        sim,
        listPanel: document.querySelector('#simulator-list-panel'),
        runPanel: document.querySelector('#simulator-run-panel'),
        savePanel: document.querySelector('#simulator-save-panel'),
    };
}

/** 初始化面板（面板引用从 DOM 解析 — loadModules 已就位三面板；getGames 未传则返回给定游戏列表） */
function initPanel(sim, _panels, { games = [], getGames = null } = {}) {
    sim.initSaveManager({
        savePanel: document.querySelector('#simulator-save-panel'),
        listPanel: document.querySelector('#simulator-list-panel'),
        runPanel: document.querySelector('#simulator-run-panel'),
        getGames: getGames ?? (() => games),
    });
}

// ══════════════════════════════════════════════════
// 协议表面
// ══════════════════════════════════════════════════

describe('save-manager — 协议表面 __all__', () => {
    it('__all__ 收口公开函数（面板初始化/开关 + 纯函数收集/导出/校验/应用/删除）', async () => {
        const { sim } = await loadModules();
        expect(sim.__all__.sort()).toEqual([
            'applyImportPayload',
            'buildExportPayload',
            'closeSavePanel',
            'collectGameKeys',
            'deleteGameKeys',
            'initSaveManager',
            'openSavePanel',
            'validateImportPayload',
        ]);
    });
});

// ══════════════════════════════════════════════════
// collectGameKeys — 键收集
// ══════════════════════════════════════════════════

describe('collectGameKeys — saveKeys 白名单匹配 localStorage 键收集', () => {
    it('精确键：只收集白名单命中且存在的键；cfg 键与主应用自身键不误收', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({
            ls_autosave: '{"v":1}',
            ls_used_names: '["a"]',
            ls_cfg: '{"apiKey":"sk-test"}',       // cfg 键（含 API Key）— 不在白名单
            [APP_OWN_KEY]: '{"theme":"dark"}',    // 主应用自身键 — 不在白名单
            unrelated_key: 'x',
        });
        expect(sim.collectGameKeys(GAME_EXACT, storage)).toEqual(['ls_autosave', 'ls_used_names']);
    });

    it('正则模式：锚定完整键名匹配（god_save_\\d+ → 数字后缀命中，非数字/带尾缀不命中）', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({
            god_autosave: 'a',
            god_save_1: 'b',
            god_save_42: 'c',
            god_save_abc: 'd',    // 非数字后缀 — 不命中
            god_save_1x: 'e',     // 锚定 ^…$：后缀 1x 不命中
        });
        expect(sim.collectGameKeys(GAME_REGEX, storage)).toEqual(['god_autosave', 'god_save_1', 'god_save_42']);
    });

    it('混合（精确 + 正则）：slot 模式与精确键同收；cfg 键不误收', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({
            twilight_autosave: 'a',
            twilight_cps: 'b',
            twilight_deaths: 'c',
            twilight_slot_0: 'd',
            twilight_slot_7: 'e',
            twilight_config: '{"apiKey":"sk"}', // cfg 键 — 不在 saveKeys
        });
        expect(sim.collectGameKeys(GAME_MIXED, storage)).toEqual([
            'twilight_autosave', 'twilight_cps', 'twilight_deaths', 'twilight_slot_0', 'twilight_slot_7',
        ]);
    });

    it('saveKeys 空数组 → 收集为空（结构性合法但零键）', async () => {
        const { sim } = await loadModules();
        const game = { ...GAME_EXACT, saveKeys: [] };
        const storage = makeStorage({ ls_autosave: 'x' });
        expect(sim.collectGameKeys(game, storage)).toEqual([]);
    });

    it('saveKeys undefined → 收集为空（「无存档管理」降级信号）', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({ spiderweb_state: 'x' });
        expect(sim.collectGameKeys(GAME_NO_SAVE, storage)).toEqual([]);
    });

    it('去重：同一键命中多条白名单条目（精确 + 正则）只收集一次', async () => {
        const { sim } = await loadModules();
        const game = { ...GAME_REGEX, saveKeys: ['god_save_1', 'god_save_\\d+'] };
        const storage = makeStorage({ god_save_1: 'x' });
        expect(sim.collectGameKeys(game, storage)).toEqual(['god_save_1']);
    });

    it('收集结果排序确定（不依赖 localStorage 枚举顺序）', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({ ls_used_names: 'a', ls_autosave: 'b' });
        expect(sim.collectGameKeys(GAME_EXACT, storage)).toEqual(['ls_autosave', 'ls_used_names']);
    });

    it('Falsify:game null / saveKeys 非数组 / storage null / 无 key() 方法 → [] 不炸', async () => {
        const { sim } = await loadModules();
        expect(sim.collectGameKeys(null, makeStorage({}))).toEqual([]);
        expect(sim.collectGameKeys({ id: 'x', saveKeys: 'ls_autosave' }, makeStorage({}))).toEqual([]);
        expect(sim.collectGameKeys(GAME_EXACT, null)).toEqual([]);
        expect(sim.collectGameKeys(GAME_EXACT, { getItem: () => null })).toEqual([]);
    });

    it('Falsify:白名单含不可编译正则元素 → 跳过该元素不炸（防御 parseManifest 外的原始数据）', async () => {
        const { sim } = await loadModules();
        const game = { ...GAME_REGEX, saveKeys: ['god_autosave', 'god_save_['] };
        const storage = makeStorage({ god_autosave: 'a', god_save_1: 'b' });
        expect(sim.collectGameKeys(game, storage)).toEqual(['god_autosave']);
    });
});

// ══════════════════════════════════════════════════
// buildExportPayload — 导出 JSON 形状与收录规则
// ══════════════════════════════════════════════════

describe('buildExportPayload — 导出 JSON 形状与收录规则', () => {
    const NOW = '2026-08-14T00:00:00.000Z';

    it('形状：{game_id, game_name, saved_at, keys:{键:值}}；saved_at 可注入（纯函数确定性）', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({ ls_autosave: '{"v":1}', ls_used_names: '["a"]' });
        const payload = sim.buildExportPayload(
            GAME_EXACT, ['ls_autosave', 'ls_used_names'], storage, NOW,
        );
        expect(payload).toEqual({
            game_id: 'life-sim',
            game_name: '人生模拟器 v3',
            saved_at: NOW,
            keys: { ls_autosave: '{"v":1}', ls_used_names: '["a"]' },
        });
    });

    it('收录规则：只收录白名单命中且存在的键；传入的 cfg 键名 → 防御不收录（导出导不出 cfg 键）', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({
            ls_autosave: 'a',
            ls_cfg: '{"apiKey":"sk-test"}',
        });
        const payload = sim.buildExportPayload(GAME_EXACT, ['ls_autosave', 'ls_cfg'], storage, NOW);
        expect(Object.keys(payload.keys)).toEqual(['ls_autosave']);
    });

    it('正则模式键收集后导出：键值原样收录', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({ god_autosave: 'a', god_save_3: '{"hp":10}' });
        const keyNames = sim.collectGameKeys(GAME_REGEX, storage);
        const payload = sim.buildExportPayload(GAME_REGEX, keyNames, storage, NOW);
        expect(payload.keys).toEqual({ god_autosave: 'a', god_save_3: '{"hp":10}' });
    });

    it('keyNames 含不存在于 storage 的键 → 不收录（只导出当前存在的键）', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({ ls_autosave: 'a' });
        const payload = sim.buildExportPayload(
            GAME_EXACT, ['ls_autosave', 'ls_used_names'], storage, NOW,
        );
        expect(payload.keys).toEqual({ ls_autosave: 'a' });
    });

    it('Falsify:storage null / keyNames 非数组 → keys 为空对象，不炸', async () => {
        const { sim } = await loadModules();
        expect(sim.buildExportPayload(GAME_EXACT, ['ls_autosave'], null, NOW).keys).toEqual({});
        expect(sim.buildExportPayload(GAME_EXACT, 'ls_autosave', makeStorage({}), NOW).keys).toEqual({});
    });

    it('Falsify:game null → game_id/game_name 为空串，不炸', async () => {
        const { sim } = await loadModules();
        const payload = sim.buildExportPayload(null, [], makeStorage({}), NOW);
        expect(payload.game_id).toBe('');
        expect(payload.game_name).toBe('');
        expect(payload.keys).toEqual({});
    });
});

// ══════════════════════════════════════════════════
// validateImportPayload — 导入校验（整包拒绝）
// ══════════════════════════════════════════════════

describe('validateImportPayload — 白名单校验（任一非法整包拒绝）', () => {
    it('合法包：键名全命中白名单且值为合法 JSON 字符串 → ok:true，keys 全量返回', async () => {
        const { sim } = await loadModules();
        const payload = {
            game_id: 'urban-god',
            game_name: '神明 v3',
            saved_at: '2026-08-14T00:00:00.000Z',
            keys: { god_autosave: '{"v":1}', god_save_3: '{"hp":10}', god_save_42: '[1,2]' },
        };
        const result = sim.validateImportPayload(payload, GAME_REGEX);
        expect(result.ok).toBe(true);
        expect(result.keys).toEqual({ god_autosave: '{"v":1}', god_save_3: '{"hp":10}', god_save_42: '[1,2]' });
    });

    it('合法值边界：数字 / null / 对象形态的 JSON 文本均可解析 → 通过', async () => {
        const { sim } = await loadModules();
        const payload = { keys: { ls_autosave: '123', ls_used_names: 'null', } };
        const result = sim.validateImportPayload(payload, GAME_EXACT);
        expect(result.ok).toBe(true);
        expect(result.keys).toEqual({ ls_autosave: '123', ls_used_names: 'null' });
    });

    it('任一非法键（含 cfg 键名 / 非白名单键）→ 整包拒绝，error 列出全部非法键名', async () => {
        const { sim } = await loadModules();
        const payload = {
            keys: { ls_autosave: '{"v":1}', ls_cfg: '{"apiKey":"sk-test"}', evil_extra: '"x"' },
        };
        const result = sim.validateImportPayload(payload, GAME_EXACT);
        expect(result.ok).toBe(false);
        expect(result.error).toContain('存档文件校验失败');
        expect(result.error).toContain('键「ls_cfg」不在该游戏存档键白名单内');
        expect(result.error).toContain('键「evil_extra」不在该游戏存档键白名单内');
    });

    it('Falsify:载荷非对象（null / 数组 / 字符串）→ 拒绝「存档文件格式无效」', async () => {
        const { sim } = await loadModules();
        expect(sim.validateImportPayload(null, GAME_EXACT).error).toBe('存档文件格式无效：顶层必须是对象');
        expect(sim.validateImportPayload([], GAME_EXACT).error).toBe('存档文件格式无效：顶层必须是对象');
        expect(sim.validateImportPayload('abc', GAME_EXACT).error).toBe('存档文件格式无效：顶层必须是对象');
    });

    it('Falsify:keys 缺失 → 拒绝「存档文件缺少 keys 字段」；keys 非普通对象（数组）→ 拒绝', async () => {
        const { sim } = await loadModules();
        expect(sim.validateImportPayload({ game_id: 'x' }, GAME_EXACT).error).toBe('存档文件缺少 keys 字段');
        expect(sim.validateImportPayload({ keys: [] }, GAME_EXACT).error).toBe('存档文件 keys 字段必须是对象');
        expect(sim.validateImportPayload({ keys: 'x' }, GAME_EXACT).error).toBe('存档文件 keys 字段必须是对象');
    });

    it('Falsify:值非 string（数字 / 对象 / null / 布尔）→ 整包拒绝', async () => {
        const { sim } = await loadModules();
        const payload = { keys: { ls_autosave: 42, ls_used_names: { a: 1 } } };
        const result = sim.validateImportPayload(payload, GAME_EXACT);
        expect(result.ok).toBe(false);
        expect(result.error).toContain('键「ls_autosave」的值不是合法 JSON 字符串');
        expect(result.error).toContain('键「ls_used_names」的值不是合法 JSON 字符串');
    });

    it('Falsify:值 string 但 JSON 不可解析（裸文本 / 空串）→ 整包拒绝', async () => {
        const { sim } = await loadModules();
        const result = sim.validateImportPayload({ keys: { ls_autosave: 'not-json', ls_used_names: '' } }, GAME_EXACT);
        expect(result.ok).toBe(false);
        expect(result.error).toContain('键「ls_autosave」的值不是合法 JSON 字符串');
        expect(result.error).toContain('键「ls_used_names」的值不是合法 JSON 字符串');
    });

    it('正则白名单键名匹配语义与收集一致：god_save_3 合法；god_save_abc 与字面 \\d+ 键名非法（不按字面放行）', async () => {
        const { sim } = await loadModules();
        const ok = sim.validateImportPayload({ keys: { god_save_3: '{"v":1}' } }, GAME_REGEX);
        expect(ok.ok).toBe(true);
        const bad = sim.validateImportPayload({ keys: { god_save_abc: '"x"' } }, GAME_REGEX);
        expect(bad.ok).toBe(false);
        expect(bad.error).toContain('键「god_save_abc」不在该游戏存档键白名单内');
        // 正则模式键名本身含元字符（字面 'god_save_\\d+'）→ 正则语义不匹配数字要求 → 非法
        const literal = sim.validateImportPayload({ keys: { 'god_save_\\d+': '"x"' } }, GAME_REGEX);
        expect(literal.ok).toBe(false);
        expect(literal.error).toContain('不在该游戏存档键白名单内');
    });

    it('Falsify:game 无 saveKeys → 整体拒绝「该游戏无存档管理…无法导入」', async () => {
        const { sim } = await loadModules();
        const result = sim.validateImportPayload({ keys: { spiderweb_state: '"x"' } }, GAME_NO_SAVE);
        expect(result.ok).toBe(false);
        expect(result.error).toBe('该游戏无存档管理（saveKeys 未声明），无法导入');
        // game 非对象 / null → 同样按无白名单拒绝
        expect(sim.validateImportPayload({ keys: {} }, null).ok).toBe(false);
    });

    it('非法键过多（>10）→ error 截断至 10 条并计数', async () => {
        const { sim } = await loadModules();
        const keys = {};
        for (let i = 0; i < 15; i++) keys[`bad_key_${i}`] = '"x"';
        const result = sim.validateImportPayload({ keys }, GAME_EXACT);
        expect(result.ok).toBe(false);
        expect(result.error).toContain('等共 15 个问题（仅列出前 10 个）');
        expect(result.error.match(/键「/g)).toHaveLength(10);
    });

    it('空 keys 对象 → 合法空包（ok:true，应用为 no-op）', async () => {
        const { sim } = await loadModules();
        const result = sim.validateImportPayload({ keys: {} }, GAME_EXACT);
        expect(result).toEqual({ ok: true, keys: {} });
    });
});

// ══════════════════════════════════════════════════
// validateImportPayload — __proto__ 键（TD-70 无原型累积器）
// ══════════════════════════════════════════════════

describe('validateImportPayload — __proto__ 键（TD-70 无原型累积器）', () => {
    it('__proto__ 白名单键：validateImportPayload → applyImportPayload 全链路完整写回', async () => {
        const { sim } = await loadModules();
        const game = { ...GAME_EXACT, saveKeys: [...GAME_EXACT.saveKeys, '__proto__'] };
        // 对象字面量 __proto__ 语法会设原型；JSON.parse 才产生自有 __proto__ 属性（导入真实路径）
        const payload = JSON.parse('{"keys":{"ls_autosave":"\\"a\\"","__proto__":"\\"p\\""}}');

        const result = sim.validateImportPayload(payload, game);
        expect(result.ok).toBe(true);
        expect(Object.keys(result.keys).sort()).toEqual(['__proto__', 'ls_autosave']);
        expect(result.keys['__proto__']).toBe('"p"');

        const written = sim.applyImportPayload(game, result.keys, localStorage);
        expect(written).toBe(2);
        expect(localStorage.getItem('__proto__')).toBe('"p"');
        expect(localStorage.getItem('ls_autosave')).toBe('"a"');
    });
});

// ══════════════════════════════════════════════════
// applyImportPayload — 应用（同名替换写回）
// ══════════════════════════════════════════════════

describe('applyImportPayload — 白名单键同名替换写回', () => {
    it('合法键写回：同名键替换旧值；返回写入计数', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({ ls_autosave: 'old', app_own: 'keep' });
        const written = sim.applyImportPayload(GAME_EXACT, { ls_autosave: '{"v":2}', ls_used_names: '["b"]' }, storage);
        expect(written).toBe(2);
        expect(storage.getItem('ls_autosave')).toBe('{"v":2}');
        expect(storage.getItem('ls_used_names')).toBe('["b"]');
        expect(storage.getItem('app_own')).toBe('keep'); // 主应用键不受影响
    });

    it('Falsify:非白名单键（cfg 键名）→ 防御不写入（导入写不进去）', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({});
        const written = sim.applyImportPayload(GAME_EXACT, { ls_cfg: '{"apiKey":"sk"}', ls_autosave: 'ok' }, storage);
        expect(written).toBe(1);
        expect(storage.getItem('ls_cfg')).toBeNull();
        expect(storage.getItem('ls_autosave')).toBe('ok');
    });

    it('Falsify:值非字符串 → 跳过不写入', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({});
        const written = sim.applyImportPayload(GAME_EXACT, { ls_autosave: { a: 1 } }, storage);
        expect(written).toBe(0);
        expect(storage.getItem('ls_autosave')).toBeNull();
    });

    it('Falsify:game null / saveKeys 缺失 / keys 非对象 / storage null → 0 不炸', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({});
        expect(sim.applyImportPayload(null, { ls_autosave: 'x' }, storage)).toBe(0);
        expect(sim.applyImportPayload(GAME_NO_SAVE, { spiderweb_state: 'x' }, storage)).toBe(0);
        expect(sim.applyImportPayload(GAME_EXACT, 'x', storage)).toBe(0);
        expect(sim.applyImportPayload(GAME_EXACT, { ls_autosave: 'x' }, null)).toBe(0);
    });
});

// ══════════════════════════════════════════════════
// applyImportPayload — 写前快照 + 失败回滚（TD-63 裁定修法，非容量预检）
// ══════════════════════════════════════════════════

describe('applyImportPayload — 写前快照 + 失败回滚（TD-63）', () => {
    it('第 N 键 setItem 抛错 → 前 N-1 键逆序回滚（原值还原 / 新增键移除）且异常上抛', async () => {
        const { sim } = await loadModules();
        const game = { ...GAME_EXACT, saveKeys: ['ls_new_key', 'ls_autosave', 'ls_used_names', 'ls_bomb_key'] };
        const map = new Map([['ls_autosave', 'old'], ['ls_used_names', 'keep']]);
        const storage = {
            getItem: (k) => (map.has(k) ? map.get(k) : null),
            setItem: (k, v) => {
                if (k === 'ls_bomb_key') throw new Error('QuotaExceededError'); // 第 4 键写入失败
                map.set(k, String(v));
            },
            removeItem: (k) => { map.delete(k); },
        };
        const keys = {
            ls_new_key: '"new"',       // 写前不存在 → 回滚应移除（新增键）
            ls_autosave: '{"v":2}',    // 写前 old → 回滚应还原原值
            ls_used_names: '["b"]',    // 写前 keep → 回滚应还原原值
            ls_bomb_key: 'boom',       // 抛错键本身未写入，无需回滚
        };
        expect(() => sim.applyImportPayload(game, keys, storage)).toThrow('QuotaExceededError');
        expect(storage.getItem('ls_new_key')).toBeNull();
        expect(storage.getItem('ls_autosave')).toBe('old');
        expect(storage.getItem('ls_used_names')).toBe('keep');
        expect(storage.getItem('ls_bomb_key')).toBeNull();
    });
});

// ══════════════════════════════════════════════════
// deleteGameKeys — 删除（确认由 UI 层负责）
// ══════════════════════════════════════════════════

describe('deleteGameKeys — 清除全部命中键（主应用键不误伤）', () => {
    it('删除全部白名单命中键并返回被删键名；cfg 键与主应用自身键不受影响', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({
            ls_autosave: 'a',
            ls_used_names: 'b',
            ls_cfg: '{"apiKey":"sk"}',
            [APP_OWN_KEY]: '{"theme":"dark"}',
        });
        const removed = sim.deleteGameKeys(GAME_EXACT, storage);
        expect(removed).toEqual(['ls_autosave', 'ls_used_names']);
        expect(storage.getItem('ls_autosave')).toBeNull();
        expect(storage.getItem('ls_used_names')).toBeNull();
        expect(storage.getItem('ls_cfg')).toBe('{"apiKey":"sk"}');
        expect(storage.getItem(APP_OWN_KEY)).toBe('{"theme":"dark"}');
    });

    it('Falsify:game null / storage null → [] 不炸', async () => {
        const { sim } = await loadModules();
        expect(sim.deleteGameKeys(null, makeStorage({}))).toEqual([]);
        expect(sim.deleteGameKeys(GAME_EXACT, null)).toEqual([]);
    });

    it('无命中键 → [] 且不调用 removeItem', async () => {
        const { sim } = await loadModules();
        const storage = makeStorage({ app_own: 'keep' });
        const removeSpy = vi.fn();
        storage.removeItem = removeSpy;
        expect(sim.deleteGameKeys(GAME_EXACT, storage)).toEqual([]);
        expect(removeSpy).not.toHaveBeenCalled();
    });
});

// ══════════════════════════════════════════════════
// 面板：开关 / 渲染 / 三面板互斥
// ══════════════════════════════════════════════════

describe('save-manager 面板 — 开关与渲染', () => {
    it('openSavePanel：列表/运行两面板隐藏、存档面板显示（三面板互斥）+ header/返回/导出提示', async () => {
        const { sim, listPanel, runPanel, savePanel } = await loadModules();
        initPanel(sim, { savePanel, listPanel, runPanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();

        expect(savePanel.hidden).toBe(false);
        expect(listPanel.hidden).toBe(true);
        expect(runPanel.hidden).toBe(true);
        expect(savePanel.querySelector('.sim-save-title').textContent).toBe('存档管理');
        expect(savePanel.querySelector('.sim-save-back').textContent).toBe('返回');
        expect(savePanel.querySelector('.sim-save-hint').textContent)
            .toContain('导出文件可能包含游戏内配置数据');
    });

    it('游戏行：有 saveKeys → 名称 / 键数 / 总大小（字符数）；零键 → 导出删除按钮禁用', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        localStorage.setItem('ls_used_names', '["a","b"]'); // 11 字符
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();

        const row = savePanel.querySelector('.sim-save-game');
        expect(row.querySelector('.sim-save-game-name').textContent).toBe('人生模拟器 v3');
        expect(row.querySelector('.sim-save-meta').textContent).toBe('2 个存档 · 16 字符'); // {"v":1}=7 字符 + ["a","b"]=9 字符
        expect(row.querySelector('[data-action="export"]').disabled).toBe(false);
        expect(row.querySelector('[data-action="delete"]').disabled).toBe(false);
        expect(row.dataset.id).toBe('life-sim');
    });

    it('零键游戏 → 导出/删除按钮 disabled；导入始终可用', async () => {
        const { sim, savePanel } = await loadModules();
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();

        const row = savePanel.querySelector('.sim-save-game');
        expect(row.querySelector('.sim-save-meta').textContent).toBe('0 个存档 · 0 字符');
        expect(row.querySelector('[data-action="export"]').disabled).toBe(true);
        expect(row.querySelector('[data-action="delete"]').disabled).toBe(true);
        expect(row.querySelector('[data-action="import"]').disabled).toBe(false);
    });

    it('无 saveKeys 游戏 → 「无存档管理」降级态（无操作按钮）', async () => {
        const { sim, savePanel } = await loadModules();
        initPanel(sim, { savePanel }, { games: [GAME_NO_SAVE] });
        sim.openSavePanel();

        const row = savePanel.querySelector('.sim-save-game');
        expect(row.classList.contains('sim-save-degraded')).toBe(true);
        expect(row.querySelector('.sim-save-note').textContent).toBe('无存档管理');
        expect(row.querySelector('[data-action]')).toBeNull();
    });

    it('wg_ 族游戏 → 「仅会话内生效，重进需重注」注记且仍按 saveKeys 管理（有操作按钮）', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('wg_xiaomabaoli_save', '{"v":1}');
        initPanel(sim, { savePanel }, { games: [GAME_WG] });
        sim.openSavePanel();

        const row = savePanel.querySelector('.sim-save-game');
        expect(row.querySelector('.sim-save-wg-note').textContent).toBe('仅会话内生效，重进需重注');
        expect(row.querySelector('.sim-save-meta').textContent).toBe('1 个存档 · 7 字符');
        expect(row.querySelector('[data-action="export"]')).not.toBeNull();
    });

    it('游戏名含特殊字符 → 转义渲染（manifest 第三方数据不产生 HTML）', async () => {
        const { sim, savePanel } = await loadModules();
        const evil = { ...GAME_EXACT, name: 'A" onclick="x' };
        initPanel(sim, { savePanel }, { games: [evil] });
        sim.openSavePanel();

        const nameEl = savePanel.querySelector('.sim-save-game-name');
        expect(nameEl.textContent).toBe('A" onclick="x');
        expect(nameEl.hasAttribute('onclick')).toBe(false);
    });

    it('Falsify:name 为空且 id 含引号（降级行 id 兜底）→ id 兜底文本转义，不产生属性', async () => {
        const { sim, savePanel } = await loadModules();
        const evil = { id: 'a" onmouseover="x', file: 'x.html', name: '', type: 'ai' };
        initPanel(sim, { savePanel }, { games: [evil] });
        sim.openSavePanel();

        const row = savePanel.querySelector('.sim-save-game');
        expect(row.querySelector('.sim-save-game-name').textContent).toBe('a" onmouseover="x');
        expect(row.querySelector('.sim-save-game-name').hasAttribute('onmouseover')).toBe(false);
        expect(row.dataset.id).toBe('a" onmouseover="x'); // dataset 通道完整往返
    });

    it('getGames 返回空列表 → 「暂无游戏数据」空态；getGames 非函数 → 空列表不炸', async () => {
        const { sim, savePanel } = await loadModules();
        initPanel(sim, { savePanel }, { games: [] });
        sim.openSavePanel();
        expect(savePanel.querySelector('.sim-save-empty').textContent).toBe('暂无游戏数据');

        // 未注入 getGames（默认空列表）→ 重开不炸
        const sim2 = (await loadModules()).sim;
        sim2.initSaveManager({ savePanel, listPanel: document.querySelector('#simulator-list-panel'), runPanel: document.querySelector('#simulator-run-panel') });
        sim2.openSavePanel();
        expect(sim2.__all__).toBeDefined();
    });

    it('closeSavePanel：存档面板隐藏、列表恢复、内容清空（销毁纪律）；返回按钮触发 close', async () => {
        const { sim, listPanel, savePanel } = await loadModules();
        initPanel(sim, { savePanel, listPanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        expect(savePanel.querySelector('.sim-save-game')).not.toBeNull();

        savePanel.querySelector('.sim-save-back').click();

        expect(savePanel.hidden).toBe(true);
        expect(listPanel.hidden).toBe(false);
        expect(savePanel.innerHTML).toBe('');
    });

    it('重复 open → 重渲染取最新 localStorage 状态（键数更新）', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        expect(savePanel.querySelector('.sim-save-meta').textContent).toContain('1 个存档');

        localStorage.setItem('ls_used_names', '["a"]');
        sim.openSavePanel();
        expect(savePanel.querySelector('.sim-save-meta').textContent).toContain('2 个存档');
    });

    it('Falsify:initSaveManager 面板缺失 / openSavePanel 未 init → no-op 不抛错', async () => {
        const { sim } = await loadModules();
        expect(() => sim.initSaveManager({})).not.toThrow();
        expect(() => sim.initSaveManager()).not.toThrow();
        expect(() => sim.openSavePanel()).not.toThrow();
        expect(() => sim.closeSavePanel()).not.toThrow();
    });
});

// ══════════════════════════════════════════════════
// 面板：操作流（导出 / 导入 / 删除）
// ══════════════════════════════════════════════════

describe('save-manager 面板 — 导出（Blob 下载）', () => {
    afterEach(() => {
        delete URL.createObjectURL;
        delete URL.revokeObjectURL;
    });

    /** FileReader 读回 Blob 文本（jsdom 未实现 Blob.text — 与 app.test.js 同构） */
    function blobText(blob) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error);
            reader.readAsText(blob);
        });
    }

    it('导出：Blob 内容为导出 JSON（含游戏标识 + 键值对），文件名 <gameId>-saves.json，仅收录白名单命中键', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        localStorage.setItem('ls_used_names', '["a"]');
        localStorage.setItem('ls_cfg', '{"apiKey":"sk-test"}'); // cfg 键不得导出
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();

        const createSpy = vi.fn(() => 'blob:mock');
        URL.createObjectURL = createSpy;
        URL.revokeObjectURL = vi.fn();
        const clickSpy = vi.fn();
        vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(clickSpy);

        savePanel.querySelector('[data-action="export"]').click();

        expect(createSpy).toHaveBeenCalledTimes(1);
        expect(clickSpy).toHaveBeenCalledTimes(1);
        expect(clickSpy.mock.instances[0].download).toBe('life-sim-saves.json');
        const blob = createSpy.mock.calls[0][0];
        expect(blob).toBeInstanceOf(Blob);
        const parsed = JSON.parse(await blobText(blob));
        expect(parsed.game_id).toBe('life-sim');
        expect(parsed.game_name).toBe('人生模拟器 v3');
        expect(typeof parsed.saved_at).toBe('string');
        expect(parsed.keys).toEqual({ ls_autosave: '{"v":1}', ls_used_names: '["a"]' });
        expect(Object.keys(parsed.keys)).not.toContain('ls_cfg');
        expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:mock');
    });

    it('Falsify:jsdom 无 URL.createObjectURL → toast 降级不抛错、不下载', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        expect(() => savePanel.querySelector('[data-action="export"]').click()).not.toThrow();
        expect(toastSpy).toHaveBeenCalledWith('导出失败：当前环境不支持文件下载', 'error');
    });

    it('Falsify:零键游戏导出按钮 disabled → 点击不触发（无 toast）', async () => {
        const { sim, savePanel } = await loadModules();
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="export"]').click();
        expect(toastSpy).not.toHaveBeenCalled();
    });
});

// ══════════════════════════════════════════════════
// 面板：导出文件名净化（TD-65 — 非法字符替换 / 尾部修剪 / 空结果兜底）
// ══════════════════════════════════════════════════

describe('save-manager 面板 — 导出文件名净化（TD-65）', () => {
    afterEach(() => {
        delete URL.createObjectURL;
        delete URL.revokeObjectURL;
    });

    it('含引号/路径分隔符/控制字符/% 的 id → 下载文件名被净化（a.download 断言）', async () => {
        const { sim, savePanel } = await loadModules();
        const evilId = 'a"b\\c/d\x01e%f'; // " \ / 控制字符 % — 全部应替换为 _
        const evil = { ...GAME_EXACT, id: evilId };
        localStorage.setItem('ls_autosave', '{"v":1}');
        initPanel(sim, { savePanel }, { games: [evil] });
        sim.openSavePanel();

        URL.createObjectURL = vi.fn(() => 'blob:mock');
        URL.revokeObjectURL = vi.fn();
        const clickSpy = vi.fn();
        vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(clickSpy);

        savePanel.querySelector('[data-action="export"]').click();

        expect(clickSpy).toHaveBeenCalledTimes(1);
        expect(clickSpy.mock.instances[0].download).toBe('a_b_c_d_e_f-saves.json');
    });

    it('Falsify:空 id → 文件名兜底「game-saves.json」（净化边界：空结果兜底 game）', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        initPanel(sim, { savePanel }, { games: [{ ...GAME_EXACT, id: '' }] });
        sim.openSavePanel();

        URL.createObjectURL = vi.fn(() => 'blob:mock');
        URL.revokeObjectURL = vi.fn();
        const clickSpy = vi.fn();
        vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(clickSpy);

        savePanel.querySelector('[data-action="export"]').click();

        expect(clickSpy.mock.instances[0].download).toBe('game-saves.json');
    });

    it('Falsify:id 尾部带点与空格 → trim 后下载（净化边界：尾部点空格修剪）', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        initPanel(sim, { savePanel }, { games: [{ ...GAME_EXACT, id: 'trail. ' }] });
        sim.openSavePanel();

        URL.createObjectURL = vi.fn(() => 'blob:mock');
        URL.revokeObjectURL = vi.fn();
        const clickSpy = vi.fn();
        vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(clickSpy);

        savePanel.querySelector('[data-action="export"]').click();

        expect(clickSpy.mock.instances[0].download).toBe('trail-saves.json');
    });
});

// ══════════════════════════════════════════════════
// 面板：存储禁用降级（TD-69 — SecurityError 时渲染不崩，操作路径不在本票）
// ══════════════════════════════════════════════════

describe('save-manager 面板 — 存储禁用（SecurityError）降级（TD-69）', () => {
    let originalStorageDescriptor = null;
    afterEach(() => {
        // 还原描述符 — 不污染其他用例（jsdom localStorage 为 configurable 访问器）
        if (originalStorageDescriptor) Object.defineProperty(window, 'localStorage', originalStorageDescriptor);
        originalStorageDescriptor = null;
    });

    it('window.localStorage getter 抛 SecurityError → openSavePanel 降级「0 个存档」不崩 + 导出/删除按钮禁用', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}'); // 正常态应显示 1 个存档
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        expect(savePanel.querySelector('.sim-save-meta').textContent).toContain('1 个存档');

        originalStorageDescriptor = Object.getOwnPropertyDescriptor(window, 'localStorage');
        Object.defineProperty(window, 'localStorage', {
            configurable: true,
            get() { throw new Error('SecurityError: The operation is insecure.'); },
        });

        expect(() => sim.openSavePanel()).not.toThrow();
        const row = savePanel.querySelector('.sim-save-game');
        expect(row.querySelector('.sim-save-meta').textContent).toBe('0 个存档 · 0 字符');
        expect(row.querySelector('[data-action="export"]').disabled).toBe(true);
        expect(row.querySelector('[data-action="delete"]').disabled).toBe(true);
        expect(row.querySelector('[data-action="import"]').disabled).toBe(false);
    });
});

describe('save-manager 面板 — 导入（文件选择器 → 校验 → 恢复）', () => {
    /** 构造导入 File 并注入隐藏 input.files 后派发 change */
    function dispatchImport(savePanel, content, { size = null, name = 'save.json' } = {}) {
        const file = new File([content], name, { type: 'application/json' });
        if (size !== null) Object.defineProperty(file, 'size', { value: size });
        const input = savePanel.querySelector('.sim-save-file-input');
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    it('导入合法包 → 同名键替换写回 + toast「已恢复 N 个存档键」+ 列表刷新', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', 'old');
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="import"]').click();
        dispatchImport(savePanel, JSON.stringify({
            game_id: 'life-sim',
            game_name: '人生模拟器 v3',
            saved_at: '2026-08-14T00:00:00.000Z',
            keys: { ls_autosave: '{"v":2}', ls_used_names: '["b"]' },
        }));

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('已恢复 2 个存档键', 'success'));
        expect(localStorage.getItem('ls_autosave')).toBe('{"v":2}'); // 同名键替换
        expect(localStorage.getItem('ls_used_names')).toBe('["b"]');
        expect(savePanel.querySelector('.sim-save-meta').textContent).toContain('2 个存档'); // 列表刷新
        expect(savePanel.querySelector('.sim-save-file-input').value).toBe(''); // input 已清空
    });

    it('Falsify:任一非法键 → 整包拒绝：不写任何键 + toast 列出非法键名', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', 'keep');
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="import"]').click();
        dispatchImport(savePanel, JSON.stringify({
            keys: { ls_autosave: '{"v":9}', ls_cfg: '{"apiKey":"sk"}' },
        }));

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalled());
        expect(toastSpy.mock.calls[0][1]).toBe('error');
        expect(toastSpy.mock.calls[0][0]).toContain('键「ls_cfg」不在该游戏存档键白名单内');
        expect(localStorage.getItem('ls_autosave')).toBe('keep'); // 整包拒绝：未写入
        expect(localStorage.getItem('ls_cfg')).toBeNull();
    });

    it('Falsify:文件不是合法 JSON → toast「不是有效的 JSON 文件」', async () => {
        const { sim, savePanel } = await loadModules();
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="import"]').click();
        dispatchImport(savePanel, 'not-json{{{');

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('不是有效的 JSON 文件', 'error'));
    });

    it('Falsify:文件超过大小守卫上限（5MB）→ toast「存档文件过大」整包拒绝', async () => {
        const { sim, savePanel } = await loadModules();
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="import"]').click();
        // 上限 5MB（与实现 MAX_IMPORT_BYTES 同一数据契约）；5MB+1 字节超限
        dispatchImport(savePanel, 'x', { size: 5 * 1024 * 1024 + 1 });

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalled());
        expect(toastSpy.mock.calls[0][0]).toContain('存档文件过大（上限 5MB）');
        expect(toastSpy.mock.calls[0][1]).toBe('error');
    });

    it('Falsify:值非法 JSON → 整包拒绝不写入（值仅接受 string + JSON 可解析）', async () => {
        const { sim, savePanel } = await loadModules();
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="import"]').click();
        dispatchImport(savePanel, JSON.stringify({ keys: { ls_autosave: 'broken' } }));

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalled());
        expect(toastSpy.mock.calls[0][0]).toContain('键「ls_autosave」的值不是合法 JSON 字符串');
        expect(localStorage.getItem('ls_autosave')).toBeNull();
    });
});

// ══════════════════════════════════════════════════
// 面板：导入配额失败（TD-63 UI 层收口 — 回滚 + toast + 刷新）
// ══════════════════════════════════════════════════

describe('save-manager 面板 — 导入配额失败回滚（TD-63）', () => {
    let originalStorageDescriptor = null;
    afterEach(() => {
        if (originalStorageDescriptor) Object.defineProperty(window, 'localStorage', originalStorageDescriptor);
        originalStorageDescriptor = null;
    });

    /** 构造导入 File 并注入隐藏 input.files 后派发 change（复用既有 dispatchImport 模式） */
    function dispatchImport(savePanel, content, { size = null, name = 'save.json' } = {}) {
        const file = new File([content], name, { type: 'application/json' });
        if (size !== null) Object.defineProperty(file, 'size', { value: size });
        const input = savePanel.querySelector('.sim-save-file-input');
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    it('导入配额失败（setItem 抛错）→ 已写键回滚 + toast「导入失败：存储空间不足或写入失败」+ 面板刷新', async () => {
        const { sim, savePanel } = await loadModules();
        const games = [GAME_EXACT];
        const getGamesSpy = vi.fn(() => games);
        initPanel(sim, { savePanel }, { games, getGames: getGamesSpy });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        // 配额受限存储：ls_used_names 写入抛错（回滚须真实还原 ls_autosave 原值）
        const map = new Map([['ls_autosave', 'old']]);
        originalStorageDescriptor = Object.getOwnPropertyDescriptor(window, 'localStorage');
        Object.defineProperty(window, 'localStorage', {
            configurable: true,
            value: {
                get length() { return map.size; },
                key: (i) => [...map.keys()][i] ?? null,
                getItem: (k) => (map.has(k) ? map.get(k) : null),
                setItem: (k, v) => {
                    if (k === 'ls_used_names') throw new Error('QuotaExceededError');
                    map.set(k, String(v));
                },
                removeItem: (k) => { map.delete(k); },
                clear: () => { map.clear(); },
            },
        });
        const rendersBefore = getGamesSpy.mock.calls.length;

        savePanel.querySelector('[data-action="import"]').click();
        dispatchImport(savePanel, JSON.stringify({
            keys: { ls_autosave: '{"v":2}', ls_used_names: '["b"]' },
        }));

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('导入失败：存储空间不足或写入失败', 'error'));
        expect(map.get('ls_autosave')).toBe('old');     // 已写键回滚：原值还原
        expect(map.has('ls_used_names')).toBe(false);   // 抛错键未写入
        expect(getGamesSpy.mock.calls.length).toBeGreaterThan(rendersBefore); // 面板刷新（经注入钩子重取数据）
        expect(savePanel.querySelector('.sim-save-file-input').value).toBe(''); // input 已清空
    });
});

// ══════════════════════════════════════════════════
// 面板：导入目标清空（TD-64 — capture-then-clear 置于所有早退路径之前）
// ══════════════════════════════════════════════════

describe('save-manager 面板 — 导入目标清空（TD-64）', () => {
    /** 构造导入 File 并注入隐藏 input.files 后派发 change（复用既有 dispatchImport 模式） */
    function dispatchImport(savePanel, content, { size = null, name = 'save.json' } = {}) {
        const file = new File([content], name, { type: 'application/json' });
        if (size !== null) Object.defineProperty(file, 'size', { value: size });
        const input = savePanel.querySelector('.sim-save-file-input');
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    it('超限早退后 pendingGameId 已清空不误恢复：再直接派发合法文件（不经按钮点击）不应用到任何游戏', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', 'keep');
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="import"]').click(); // pendingGameId → life-sim
        dispatchImport(savePanel, 'x', { size: 5 * 1024 * 1024 + 1 }); // 超限 → 早退
        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('存档文件过大（上限 5MB）', 'error'));

        // 直接派发合法导入文件（不经按钮点击）→ pendingGameId 已清空 → 目标游戏为空 → 不误恢复
        dispatchImport(savePanel, JSON.stringify({ keys: { ls_autosave: '{"v":9}' } }));
        await vi.waitFor(() => expect(toastSpy.mock.calls.length).toBe(2));
        expect(toastSpy.mock.calls[1][0]).toBe('该游戏无存档管理，无法导入');
        expect(localStorage.getItem('ls_autosave')).toBe('keep'); // 未误恢复到错误游戏
    });
});

describe('save-manager 面板 — 删除（确认后清除）', () => {
    it('确认 → 清除全部命中键 + toast + 列表刷新（键数归零、按钮禁用）', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        localStorage.setItem('ls_used_names', '["a"]');
        localStorage.setItem('app_own_key', 'keep'); // 主应用键不得误伤
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();
        const utils = await import('../js/utils.js');
        const toastSpy = vi.spyOn(utils, 'showToast');

        savePanel.querySelector('[data-action="delete"]').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        expect(document.querySelector('.confirm-message').textContent).toContain('人生模拟器 v3');
        document.querySelector('.modal-overlay .confirm-ok').click();

        await vi.waitFor(() => expect(toastSpy).toHaveBeenCalledWith('已删除 2 个存档键', 'success'));
        expect(localStorage.getItem('ls_autosave')).toBeNull();
        expect(localStorage.getItem('ls_used_names')).toBeNull();
        expect(localStorage.getItem('app_own_key')).toBe('keep'); // 主应用键不受影响
        expect(savePanel.querySelector('.sim-save-meta').textContent).toContain('0 个存档');
        expect(savePanel.querySelector('[data-action="delete"]').disabled).toBe(true);
    });

    it('取消确认 → 不删除任何键', async () => {
        const { sim, savePanel } = await loadModules();
        localStorage.setItem('ls_autosave', '{"v":1}');
        initPanel(sim, { savePanel }, { games: [GAME_EXACT] });
        sim.openSavePanel();

        savePanel.querySelector('[data-action="delete"]').click();
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).not.toBeNull());
        document.querySelector('.modal-overlay .confirm-cancel').click();
        await new Promise((r) => setTimeout(r, 0));

        expect(localStorage.getItem('ls_autosave')).toBe('{"v":1}');
    });
});
