/**
 * 模拟器配置同步模块测试（U8-T2 + SIM-API-1）。
 *
 * 覆盖：
 *   - 模块私有性：ESM 深模块，不挂 window / globalThis（注入模块不出主应用作用域）
 *   - resolveButtonState 三态：openai（key 非空）→ 可注入；claude / none →
 *     禁用（含防御分支：openai 但 key 空串、未知 protocol、null 输入）
 *   - hasConfigTriplet：config 三元组完整性（三个非空字符串 id）
 *   - convertEndpoint（SIM-API-1）：endpointMode 'full' 追加 /chat/completions
 *     （尾斜杠归一 + 双重追加防护）；'base' 剥除后缀；未声明原样
 *   - injectCredentialsIntoGame 核心：填值 + 派发 input/change；endpointMode
 *     口径转换；select 缺目标 option → 追加受管 option（SIM-API-1 取代旧
 *     F1 静默跳过）；幂等写入（值已为目标 → 不写不派发、不重复追加 option）；
 *     空值跳过（不覆盖游戏默认）；白名单（非声明 id 不触碰）；元素类型校验
 *     （input/select 才写）；控件缺失 / 文档缺失静默降级；返回 filled/skipped
 *   - syncGameCredentials（SIM-API-1 编排核心）：openai → 注入；claude/none →
 *     不注入返回禁用原因；未初始化 → null
 *   - autoSyncIntoGame（SIM-API-1 自动同步）：openai → 静默注入（无「已填入」
 *     反馈、按钮保持可点）；claude/none → 自动禁用按钮条 + 文案；未初始化 →
 *     bar 保持现状；同步在途 bar 被移除 → 不抛错
 *   - 写回环状态机（sync loop state machine）：冷却/熔断状态迁移收口在
 *     key-injector 单一状态机；autoSyncIntoGame(path) 一次调用原子完成
 *     同步执行 + 冷却判定 + 置冷却 + 观察者计数 + 熔断判定；resetSyncLoop()
 *     幂等清零；熔断权优先于冷却；冷却仅真写入 written > 0 置位
 *   - 状态机用例：path 默认 load 语义（置冷却不计数）/ observer 熔断达阈值
 *     （3 次真写入 → breaker: true）/ 幂等兜底（漏断后仍返回 breaker）/
 *     收敛（幂等匹配不计数不熔断）/ 冷却（observer/load 冷却中跳过）/
 *     冷却仅真写入置位 / resetSyncLoop 幂等清零 / 按钮路径完全不经状态机
 *   - attachKeyInject 交互（手动重新同步）：点击 → 凭证获取 → 注入 → 「已填入」
 *     2s 反馈；claude/none 禁用态 + 文案；请求失败 / 全跳过静默恢复；幂等
 *     attach；重复点击只发一次请求；在途视图销毁后不污染新 bar
 *   - Falsify：未 initKeyInjector 点击静默；getDoc/getConfig 缺失防御
 *
 * 测试即模块接口契约：公开面 __all__ = initKeyInjector / attachKeyInject /
 *   resolveButtonState / hasConfigTriplet / convertEndpoint /
 *   injectCredentialsIntoGame / syncGameCredentials / autoSyncIntoGame /
 *   TEXT_RESYNC / TEXT_INJECTED / resetSyncLoop（11 项）。
 * 挂载模式：jsdom + vi.resetModules()；按钮条 fixture 与 simulator-view.js
 *   renderShell 渲染的 DOM 契约一致（.sim-key-bar / .sim-key-btn /
 *   .sim-key-msg）；注入目标文档用 createHTMLDocument 构造（注入核心只依赖
 *   文档参数 — spec「U8 注入交互」seam 清单）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** 凭证端点三态 fixture（与后端 CredentialsResponse 契约一致；
 * endpoint 为 base URL 形态 — 凭证端点契约） */
const CRED_OPENAI = { key: 'sk-smoke-openai', endpoint: 'https://api.example.com/v1', model: 'gpt-4o-mini', protocol: 'openai' };
const CRED_CLAUDE = { key: '', endpoint: '', model: '', protocol: 'claude' };
const CRED_NONE = { key: '', endpoint: '', model: '', protocol: 'none' };

/** 游戏配置面板 DOM id 三元组（manifest config 契约） */
const CONFIG = { endpoint: 'cfg-endpoint', apikey: 'cfg-apikey', model: 'cfg-model' };

/** 按钮条 fixture — 与 simulator-view.js renderShell 渲染结构一致（DOM 契约） */
function makeBar() {
    const bar = document.createElement('div');
    bar.className = 'sim-key-bar';
    bar.innerHTML = `
        <button type="button" class="sim-key-btn">重新同步</button>
        <span class="sim-key-msg" role="status" hidden></span>
    `;
    document.body.appendChild(bar);
    return bar;
}

/** 构造注入目标文档（游戏配置面板 — 注入核心只依赖文档参数） */
function makeGameDoc(html) {
    const doc = document.implementation.createHTMLDocument('game');
    doc.body.innerHTML = html;
    return doc;
}

/** 标准游戏配置面板文档（endpoint/model 带游戏默认值；select 含注入目标模型选项 —
 * select.value 仅在选项匹配时生效，与真实游戏面板一致） */
function makePanelDoc({ endpointDefault = 'game-default-endpoint', modelDefault = 'game-default-model' } = {}) {
    return makeGameDoc(`
        <input id="cfg-endpoint" value="${endpointDefault}">
        <input id="cfg-apikey">
        <select id="cfg-model">
            <option value="${modelDefault}">${modelDefault}</option>
            <option value="gpt-4o-mini">gpt-4o-mini</option>
        </select>
    `);
}

/** 加载全新 key-injector 模块 */
async function loadInjector() {
    vi.resetModules();
    const mod = await import('../js/key-injector.js');
    return mod;
}

/** 组装：bar + initKeyInjector(mock) + attach；返回 {mod, bar, btn, msg, fetchMock} */
async function setupBar({ credentials = CRED_OPENAI, getDoc = null, getConfig = null, getEndpointMode = null } = {}) {
    const mod = await loadInjector();
    const fetchMock = vi.fn(async () => credentials);
    mod.initKeyInjector({ getCredentials: fetchMock });
    const bar = makeBar();
    const btn = bar.querySelector('.sim-key-btn');
    const msg = bar.querySelector('.sim-key-msg');
    mod.attachKeyInject({
        bar,
        getDoc: getDoc ?? (() => makePanelDoc()),
        getConfig: getConfig ?? (() => CONFIG),
        getEndpointMode: getEndpointMode ?? (() => null),
    });
    return { mod, bar, btn, msg, fetchMock };
}

describe('key-injector — 协议表面 __all__ 与模块私有性', () => {
    it('__all__ 收口公开函数', async () => {
        const mod = await loadInjector();
        expect(mod.__all__.sort()).toEqual([
            'LINK_NAV_SETTINGS', 'MSG_CLAUDE_ONLY', 'MSG_NO_CREDENTIALS',
            'SEL_NAV_SETTINGS',
            'TEXT_INJECTED', 'TEXT_RESYNC',
            'attachKeyInject', 'autoSyncIntoGame', 'convertEndpoint',
            'hasConfigTriplet', 'initKeyInjector',
            'injectCredentialsIntoGame', 'resetSyncLoop',
            'resolveButtonState', 'syncGameCredentials',
        ]);
    });

    it('导出禁用文案/引导链接常量（供生成器复用 — T4 避免复制）', async () => {
        const mod = await loadInjector();
        expect(mod.MSG_CLAUDE_ONLY).toBe('游戏仅支持 OpenAI 兼容 Key');
        expect(mod.MSG_NO_CREDENTIALS).toBe('未配置 OpenAI 兼容 Key');
        expect(mod.LINK_NAV_SETTINGS).toBe('前往设置页配置');
        expect(mod.SEL_NAV_SETTINGS).toBe('.sim-key-nav-settings');
    });

    it('模块私有：import 后 window / globalThis 无注入模块挂载（不扩大同源暴露面）', async () => {
        const before = Object.keys(globalThis).length;
        await loadInjector();
        expect(globalThis.keyInjector).toBeUndefined();
        expect(window.keyInjector).toBeUndefined();
        // 模块加载不应新增全局键（ESM 私有作用域）
        expect(Object.keys(globalThis).length).toBe(before);
    });
});

describe('key-injector — resolveButtonState 三态', () => {
    it('protocol=openai 且 key 非空 → { enabled: true, reason: null }', async () => {
        const { resolveButtonState } = await loadInjector();
        expect(resolveButtonState(CRED_OPENAI)).toEqual({ enabled: true, reason: null });
        expect(resolveButtonState({ ...CRED_OPENAI, endpoint: '', model: '' }).enabled).toBe(true);
    });

    it('protocol=claude → { enabled: false, reason: "claude" }（即使带 key 字段 — 端点契约下 key 必为空）', async () => {
        const { resolveButtonState } = await loadInjector();
        expect(resolveButtonState(CRED_CLAUDE)).toEqual({ enabled: false, reason: 'claude' });
        expect(resolveButtonState({ ...CRED_CLAUDE, key: 'sk-ant' })).toEqual({ enabled: false, reason: 'claude' });
    });

    it('protocol=none → { enabled: false, reason: "none" }', async () => {
        const { resolveButtonState } = await loadInjector();
        expect(resolveButtonState(CRED_NONE)).toEqual({ enabled: false, reason: 'none' });
    });

    it('防御：openai 但 key 空串 / 未知 protocol / null 输入 → 禁用（reason "none"）不抛错', async () => {
        const { resolveButtonState } = await loadInjector();
        expect(resolveButtonState({ ...CRED_OPENAI, key: '' })).toEqual({ enabled: false, reason: 'none' });
        expect(resolveButtonState({ ...CRED_OPENAI, key: 42 })).toEqual({ enabled: false, reason: 'none' });
        expect(resolveButtonState({ protocol: 'weird', key: 'x' })).toEqual({ enabled: false, reason: 'none' });
        expect(resolveButtonState(null)).toEqual({ enabled: false, reason: 'none' });
        expect(resolveButtonState(undefined)).toEqual({ enabled: false, reason: 'none' });
        expect(resolveButtonState({})).toEqual({ enabled: false, reason: 'none' });
    });
});

describe('key-injector — hasConfigTriplet 三元组校验', () => {
    it('完整三元组（三个非空字符串 id）→ true', async () => {
        const { hasConfigTriplet } = await loadInjector();
        expect(hasConfigTriplet(CONFIG)).toBe(true);
        expect(hasConfigTriplet({ endpoint: 'a', apikey: 'b', model: 'c' })).toBe(true);
    });

    it('缺字段 / 空串 / 非字符串 / null / 非对象 → false', async () => {
        const { hasConfigTriplet } = await loadInjector();
        expect(hasConfigTriplet({ endpoint: 'a', apikey: 'b' })).toBe(false);
        expect(hasConfigTriplet({ ...CONFIG, model: '' })).toBe(false);
        expect(hasConfigTriplet({ ...CONFIG, apikey: 42 })).toBe(false);
        expect(hasConfigTriplet({ ...CONFIG, endpoint: null })).toBe(false);
        expect(hasConfigTriplet(null)).toBe(false);
        expect(hasConfigTriplet(undefined)).toBe(false);
        expect(hasConfigTriplet([])).toBe(false);
        expect(hasConfigTriplet('cfg')).toBe(false);
    });
});

describe('key-injector — convertEndpoint 端点口径转换（SIM-API-1）', () => {
    it("mode='full'：base URL → 追加 /chat/completions", async () => {
        const { convertEndpoint } = await loadInjector();
        expect(convertEndpoint('https://api.example.com/v1', 'full'))
            .toBe('https://api.example.com/v1/chat/completions');
    });

    it("mode='full'：尾斜杠先归一再追加（不产生 //）", async () => {
        const { convertEndpoint } = await loadInjector();
        expect(convertEndpoint('https://api.example.com/v1/', 'full'))
            .toBe('https://api.example.com/v1/chat/completions');
    });

    it("mode='full'：已含 /chat/completions → 原样（不双重追加）", async () => {
        const { convertEndpoint } = await loadInjector();
        expect(convertEndpoint('https://api.example.com/v1/chat/completions', 'full'))
            .toBe('https://api.example.com/v1/chat/completions');
    });

    it("mode='base'：完整 /chat/completions 地址 → 剥除后缀", async () => {
        const { convertEndpoint } = await loadInjector();
        expect(convertEndpoint('https://api.example.com/v1/chat/completions', 'base'))
            .toBe('https://api.example.com/v1');
        expect(convertEndpoint('https://api.example.com/v1/chat/completions/', 'base'))
            .toBe('https://api.example.com/v1');
    });

    it("mode='base'：已是 base 形态 → 原样", async () => {
        const { convertEndpoint } = await loadInjector();
        expect(convertEndpoint('https://api.example.com/v1', 'base'))
            .toBe('https://api.example.com/v1');
    });

    it('mode 未声明 / 未知值 → 原样返回（兼容旧数据不转换）', async () => {
        const { convertEndpoint } = await loadInjector();
        expect(convertEndpoint('https://api.example.com/v1', undefined))
            .toBe('https://api.example.com/v1');
        expect(convertEndpoint('https://api.example.com/v1', 'weird'))
            .toBe('https://api.example.com/v1');
        expect(convertEndpoint('https://api.example.com/v1', null))
            .toBe('https://api.example.com/v1');
    });

    it('非字符串 / 空串 → 原样返回', async () => {
        const { convertEndpoint } = await loadInjector();
        expect(convertEndpoint('', 'full')).toBe('');
        expect(convertEndpoint(null, 'full')).toBeNull();
        expect(convertEndpoint(42, 'full')).toBe(42);
        expect(convertEndpoint(undefined, 'full')).toBeUndefined();
    });
});

describe('key-injector — injectCredentialsIntoGame 填值 + 事件派发', () => {
    it('openai 凭证 → 三控件填值（apikey←key；endpoint/model 同名）且各自收到 input 与 change', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        const seen = {};
        for (const id of ['cfg-endpoint', 'cfg-apikey', 'cfg-model']) {
            seen[id] = [];
            doc.getElementById(id).addEventListener('input', () => seen[id].push('input'));
            doc.getElementById(id).addEventListener('change', () => seen[id].push('change'));
        }

        const result = injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI });

        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1');
        expect(doc.getElementById('cfg-model').value).toBe('gpt-4o-mini');
        expect(seen['cfg-apikey']).toEqual(['input', 'change']);
        expect(seen['cfg-endpoint']).toEqual(['input', 'change']);
        expect(seen['cfg-model']).toEqual(['input', 'change']);
        expect(result).toEqual({ filled: ['apikey', 'endpoint', 'model'], skipped: [], written: ['apikey', 'endpoint', 'model'] });
    });

    it("endpointMode='full' → endpoint 注入为 base + /chat/completions（模型/Key 不受影响）", async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        const result = injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI, endpointMode: 'full' });

        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1/chat/completions');
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-model').value).toBe('gpt-4o-mini');
        expect(result).toEqual({ filled: ['apikey', 'endpoint', 'model'], skipped: [], written: ['apikey', 'endpoint', 'model'] });
    });

    it("endpointMode='base' → 完整地址剥除 /chat/completions 后注入", async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        injectCredentialsIntoGame({
            doc,
            config: CONFIG,
            credentials: { ...CRED_OPENAI, endpoint: 'https://api.example.com/v1/chat/completions' },
            endpointMode: 'base',
        });

        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1');
    });

    it('endpoint/model 为空 → 跳过该字段保持游戏默认（spec：不覆盖游戏默认），key 仍注入', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        const result = injectCredentialsIntoGame({
            doc,
            config: CONFIG,
            credentials: { ...CRED_OPENAI, endpoint: '', model: '' },
        });

        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('game-default-endpoint');
        expect(doc.getElementById('cfg-model').value).toBe('game-default-model');
        expect(result).toEqual({ filled: ['apikey'], skipped: ['endpoint', 'model'], written: ['apikey'] });
    });

    it('白名单：只触碰 manifest 声明 id — 文档中其他控件不被写入（无控件探测）', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        doc.body.innerHTML += '<input id="cfg-maxtokens" value="4096"><input id="secret-field" value="keep-me">';

        injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI });

        expect(doc.getElementById('cfg-maxtokens').value).toBe('4096');
        expect(doc.getElementById('secret-field').value).toBe('keep-me');
    });

    it('元素校验：id 存在但不是 input/select（div）→ 该字段跳过；id 缺失 → 跳过；其余字段正常注入', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makeGameDoc(`
            <div id="cfg-endpoint"></div>
            <input id="cfg-apikey">
        `);

        const result = injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI });

        expect(doc.getElementById('cfg-endpoint').textContent).toBe('');
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(result).toEqual({ filled: ['apikey'], skipped: ['endpoint', 'model'], written: ['apikey'] });
    });

    it('SIM-API-1:select 无匹配 option → 追加受管 option 并选中（主应用模型名可进入 select）、派发事件、filled 含 model', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc(); // select 选项集：game-default-model / gpt-4o-mini
        const modelEl = doc.getElementById('cfg-model');
        const seen = [];
        modelEl.addEventListener('input', () => seen.push('input'));
        modelEl.addEventListener('change', () => seen.push('change'));

        const result = injectCredentialsIntoGame({
            doc,
            config: CONFIG,
            credentials: { ...CRED_OPENAI, model: 'deepseek-r1' }, // 不在选项集 → 宿主追加受管 option
        });

        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1');
        expect(modelEl.value).toBe('deepseek-r1'); // 受管 option 已选中
        const optValues = [...modelEl.options].map((o) => o.value);
        expect(optValues).toContain('deepseek-r1'); // 受管 option 已在选项集
        expect(optValues).toHaveLength(3); // 原 2 + 受管 1
        expect(seen).toEqual(['input', 'change']);
        expect(result).toEqual({ filled: ['apikey', 'endpoint', 'model'], skipped: [], written: ['apikey', 'endpoint', 'model'] });
    });

    it('SIM-API-1:select 无任何 option → 追加受管 option 后选中并派发事件（apikey/endpoint 控件缺失照常跳过）', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makeGameDoc('<select id="cfg-model"></select>');
        const modelEl = doc.getElementById('cfg-model');
        const seen = [];
        modelEl.addEventListener('input', () => seen.push('input'));
        modelEl.addEventListener('change', () => seen.push('change'));
        const result = injectCredentialsIntoGame({
            doc,
            config: CONFIG,
            credentials: { ...CRED_OPENAI, model: 'deepseek-r1' },
        });
        expect(doc.getElementById('cfg-model').value).toBe('deepseek-r1');
        expect([...doc.getElementById('cfg-model').options].map((o) => o.value)).toEqual(['deepseek-r1']);
        // Falsify 修复（评审 F1）：空 select 追加首个 option 时浏览器自动选中
        // → 值已匹配会落入幂等分支静默 —— 追加导致的选中也必须派发事件，
        // 否则依赖 change 保存状态的游戏存旧值
        expect(seen).toEqual(['input', 'change']);
        expect(result).toEqual({ filled: ['model'], skipped: ['apikey', 'endpoint'], written: ['model'] });
    });

    it('Falsify:空 select 追加 option 后自动选中（值未写即匹配）→ 仍派发事件（不落入幂等静默）', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makeGameDoc('<select id="cfg-model"></select>');
        const modelEl = doc.getElementById('cfg-model');
        const seen = [];
        modelEl.addEventListener('input', () => seen.push('input'));
        modelEl.addEventListener('change', () => seen.push('change'));
        injectCredentialsIntoGame({ doc, config: CONFIG, credentials: { ...CRED_OPENAI, model: 'm1' } });
        expect(seen).toEqual(['input', 'change']); // 追加+自动选中 → 必须派发

        // 幂等复查：值已为目标且 option 已存在 → 不再派发（写回环守卫不变）
        seen.length = 0;
        injectCredentialsIntoGame({ doc, config: CONFIG, credentials: { ...CRED_OPENAI, model: 'm1' } });
        expect(seen).toEqual([]);
        expect(modelEl.options.length).toBe(1); // 无重复受管 option
    });

    it('SIM-API-1 幂等:值已为目标值 → 不写不派发、不重复追加受管 option（写回环守卫）', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        const modelEl = doc.getElementById('cfg-model');
        const seen = [];
        for (const id of ['cfg-endpoint', 'cfg-apikey', 'cfg-model']) {
            doc.getElementById(id).addEventListener('input', () => seen.push(`input:${id}`));
            doc.getElementById(id).addEventListener('change', () => seen.push(`change:${id}`));
        }
        const credentials = { ...CRED_OPENAI, model: 'deepseek-r1' };

        const first = injectCredentialsIntoGame({ doc, config: CONFIG, credentials });
        expect(first.filled.sort()).toEqual(['apikey', 'endpoint', 'model']);
        expect(seen.length).toBe(6); // 三字段各 input+change
        const optionCount = modelEl.options.length; // 原 2 + 受管 1
        expect(optionCount).toBe(3);

        const second = injectCredentialsIntoGame({ doc, config: CONFIG, credentials });
        expect(second.filled.sort()).toEqual(['apikey', 'endpoint', 'model']); // 已处于目标值
        expect(seen.length).toBe(6); // 幂等：无新增事件
        expect(modelEl.options.length).toBe(optionCount); // 无重复受管 option
        expect(modelEl.value).toBe('deepseek-r1');
    });

    it('model 已在选项集 → 不追加 option（直接选中原 option）', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc(); // 选项集含 gpt-4o-mini
        const modelEl = doc.getElementById('cfg-model');
        injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI });
        expect(modelEl.options.length).toBe(2); // 未新增
        expect(modelEl.value).toBe('gpt-4o-mini');
    });

    it('文本域（textarea）不算注入目标 → 跳过（目标限 input/select）', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makeGameDoc('<textarea id="cfg-apikey">orig</textarea>');
        const result = injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI });
        expect(doc.getElementById('cfg-apikey').value).toBe('orig');
        expect(result).toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'], written: [] });
    });

    it('降级：doc 缺失（null / 无 getElementById）→ 全 skipped 不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        expect(injectCredentialsIntoGame({ doc: null, config: CONFIG, credentials: CRED_OPENAI }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'], written: [] });
        expect(injectCredentialsIntoGame({ doc: {}, config: CONFIG, credentials: CRED_OPENAI }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'], written: [] });
    });

    it('降级：config 缺失 / config 字段非字符串 → 跳过该字段不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        expect(injectCredentialsIntoGame({ doc, config: null, credentials: CRED_OPENAI }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'], written: [] });
        // endpoint 字段非字符串 → 仅该字段跳过；apikey/model 声明 id 正常注入
        expect(injectCredentialsIntoGame({ doc, config: { endpoint: 42, apikey: 'cfg-apikey', model: 'cfg-model' }, credentials: CRED_OPENAI }))
            .toEqual({ filled: ['apikey', 'model'], skipped: ['endpoint'], written: ['apikey', 'model'] });
    });

    it('降级：凭证缺失（null / 字段非字符串）→ 全 skipped 不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        expect(injectCredentialsIntoGame({ doc, config: CONFIG, credentials: null }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'], written: [] });
        expect(injectCredentialsIntoGame({ doc, config: CONFIG, credentials: { key: 7 } }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'], written: [] });
    });

    it('防御：整包参数缺失 → 全 skipped 不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        expect(injectCredentialsIntoGame()).toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'], written: [] });
    });
});

describe('key-injector — syncGameCredentials 同步编排核心（SIM-API-1）', () => {
    it('openai → 注入 doc 并返回 { enabled: true, reason: null, filled, skipped }', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();

        const result = await mod.syncGameCredentials({ doc, config: CONFIG, endpointMode: null });

        expect(result.enabled).toBe(true);
        expect(result.reason).toBeNull();
        expect(result.filled.sort()).toEqual(['apikey', 'endpoint', 'model']);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
    });

    it("claude → 不注入（claude key 绝不进入游戏）返回 { enabled: false, reason: 'claude' }", async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_CLAUDE);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();

        const result = await mod.syncGameCredentials({ doc, config: CONFIG, endpointMode: null });

        expect(result).toEqual({ enabled: false, reason: 'claude', filled: [], skipped: [], written: [] });
        expect(doc.getElementById('cfg-apikey').value).toBe(''); // 未写入
        expect(doc.getElementById('cfg-endpoint').value).toBe('game-default-endpoint');
    });

    it("none → 不注入返回 { enabled: false, reason: 'none' }", async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => CRED_NONE) });
        const doc = makePanelDoc();
        const result = await mod.syncGameCredentials({ doc, config: CONFIG });
        expect(result).toEqual({ enabled: false, reason: 'none', filled: [], skipped: [], written: [] });
        expect(doc.getElementById('cfg-apikey').value).toBe('');
    });

    it('未初始化（initKeyInjector 未接线）→ 返回 null（调用方静默保持现状）', async () => {
        const mod = await loadInjector(); // 不 init
        expect(await mod.syncGameCredentials({ doc: makePanelDoc(), config: CONFIG })).toBeNull();
    });

    it('凭证获取失败 → 拒绝（调用方按路径降级）', async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => { throw new Error('网络错误'); }) });
        await expect(mod.syncGameCredentials({ doc: makePanelDoc(), config: CONFIG }))
            .rejects.toThrow('网络错误');
    });
});

describe('key-injector — attachKeyInject 交互（手动重新同步）', () => {
    beforeEach(() => { vi.useFakeTimers(); });
    afterEach(() => { vi.useRealTimers(); document.body.innerHTML = ''; });

    it('点击 → 调凭证获取 → 注入 getDoc() 文档 → 按钮「已填入」→ 2s 后恢复「重新同步」可点', async () => {
        const { bar, btn, msg, fetchMock } = await setupBar();
        btn.click();
        await vi.advanceTimersByTimeAsync(0); // 冲刷 fetch/inject 微任务

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(btn.textContent).toBe('已填入');
        expect(btn.disabled).toBe(true); // 反馈期间禁用（防重复点击）
        expect(msg.hidden).toBe(true);

        await vi.advanceTimersByTimeAsync(2000);
        expect(btn.textContent).toBe('重新同步');
        expect(btn.disabled).toBe(false);
    });

    it('claude → 按钮禁用 + 文案「游戏仅支持 OpenAI 兼容 Key」（区分 claude-only）', async () => {
        const { bar, btn, msg } = await setupBar({ credentials: CRED_CLAUDE });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        expect(btn.disabled).toBe(true);
        expect(msg.hidden).toBe(false);
        expect(msg.textContent).toContain('游戏仅支持 OpenAI 兼容 Key');
    });

    it('none → 按钮禁用 + 文案「未配置 OpenAI 兼容 Key」', async () => {
        const { bar, btn, msg } = await setupBar({ credentials: CRED_NONE });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        expect(btn.disabled).toBe(true);
        expect(msg.hidden).toBe(false);
        expect(msg.textContent).toContain('未配置 OpenAI 兼容 Key');
    });

    it('TD-71:none 态提示含「前往设置页配置」链接，点击触发 onNavigateSettings；未注入钩子时点击 no-op 不抛错', async () => {
        const navigate = vi.fn();
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_NONE);
        mod.initKeyInjector({ getCredentials: fetchMock, onNavigateSettings: navigate });
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const btn = bar.querySelector('.sim-key-btn');
        const msg = bar.querySelector('.sim-key-msg');

        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        // none 态文案 = 常量 + 链接（纯常量拼接，无用户数据）
        expect(msg.hidden).toBe(false);
        expect(msg.textContent).toContain('未配置 OpenAI 兼容 Key');
        expect(msg.textContent).toContain('前往设置页配置');
        const link = msg.querySelector('.sim-key-nav-settings');
        expect(link).not.toBeNull();

        link.click();
        expect(navigate).toHaveBeenCalledTimes(1);
        // 重复点击链接 → 钩子再次触发（委托在 bar 上，不重复绑定）
        link.click();
        expect(navigate).toHaveBeenCalledTimes(2);

        // 未注入 onNavigateSettings（非函数）→ 点击 no-op 不抛错。
        // 沿用本文件既有多 bar 模式（同模块实例重初始化钩子 — 与
        // 「旧 bar 挂起中新建 bar」用例同构；二次 loadInjector 在本
        // 环境不可靠，不采用）
        mod.initKeyInjector({ getCredentials: fetchMock });
        const bar2 = makeBar();
        // 注意：attachKeyInject 契约参数名是 bar — 对象字面量须用 { bar: bar2 }
        // （shorthand { bar2 } 会生成名为 bar2 的属性，attach 将 no-op）
        mod.attachKeyInject({ bar: bar2, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        bar2.querySelector('.sim-key-btn').click();
        await vi.advanceTimersByTimeAsync(0);
        const link2 = bar2.querySelector('.sim-key-msg .sim-key-nav-settings');
        expect(link2).not.toBeNull();
        expect(() => link2.click()).not.toThrow();
    });

    it('TD-71:disableBar 在同一 bar 上多次调用（openai 全跳过 → none 换态）→ 链接点击只触发一次钩子（无重复监听）', async () => {
        const navigate = vi.fn();
        const mod = await loadInjector();
        const fetchMock = vi.fn()
            .mockResolvedValueOnce(CRED_OPENAI)
            .mockResolvedValueOnce(CRED_NONE);
        mod.initKeyInjector({ getCredentials: fetchMock, onNavigateSettings: navigate });
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makeGameDoc('<div></div>'), getConfig: () => CONFIG, getEndpointMode: () => null });
        const btn = bar.querySelector('.sim-key-btn');

        btn.click(); // openai 但控件全缺失 → 静默 resetBar（按钮恢复可点）
        await vi.advanceTimersByTimeAsync(0);
        expect(btn.disabled).toBe(false);

        btn.click(); // 同 bar 再次点击 → none → disableBar 第二次渲染禁用文案
        await vi.advanceTimersByTimeAsync(0);
        expect(bar.querySelector('.sim-key-msg .sim-key-nav-settings')).not.toBeNull();

        bar.querySelector('.sim-key-msg .sim-key-nav-settings').click();
        expect(navigate).toHaveBeenCalledTimes(1); // 委托一次性绑定 → 只触发一次
    });

    it('请求失败（fetch 拒绝）→ 静默降级：无抛错、按钮恢复可点、无禁用文案', async () => {
        const { mod, bar, btn, msg, fetchMock } = await setupBar();
        fetchMock.mockRejectedValueOnce(new Error('网络错误'));
        btn.click();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();

        expect(btn.disabled).toBe(false);
        expect(btn.textContent).toBe('重新同步');
        expect(msg.hidden).toBe(true);
    });

    it('注入 0 个字段（控件全缺失）→ 静默降级：无「已填入」、按钮恢复可点（用户可手动配置）', async () => {
        const { bar, btn } = await setupBar({ getDoc: () => makeGameDoc('<div></div>') });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        expect(btn.textContent).toBe('重新同步');
        expect(btn.disabled).toBe(false);
    });

    it('SIM-API-1 交互:select 无匹配 option → 受管 option 追加 + 选中 + 派发事件 → 按钮「已填入」如实反馈', async () => {
        const doc = makePanelDoc();
        const modelEl = doc.getElementById('cfg-model');
        const events = [];
        modelEl.addEventListener('input', () => events.push('input'));
        modelEl.addEventListener('change', () => events.push('change'));
        const { bar, btn } = await setupBar({
            credentials: { ...CRED_OPENAI, model: 'deepseek-r1' },
            getDoc: () => doc,
        });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        expect(btn.textContent).toBe('已填入'); // key/endpoint/model 均注入成功 → 反馈如实
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(modelEl.value).toBe('deepseek-r1'); // 受管 option 已选中
        expect([...modelEl.options].map((o) => o.value)).toContain('deepseek-r1');
        expect(events).toEqual(['input', 'change']); // 事件已派发
    });

    it('幂等 attach：同一 bar 重复 attach → 点击只触发一次凭证获取（无重复监听）', async () => {
        const { mod, bar, btn, fetchMock } = await setupBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });

        btn.click();
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('重复点击（凭证获取挂起中）→ 只发一次请求（在途守卫）', async () => {
        let resolveFetch;
        const { mod, bar, btn, fetchMock } = await setupBar();
        fetchMock.mockImplementationOnce(() => new Promise((r) => { resolveFetch = r; }));
        btn.click();
        btn.click(); // 在途重复点击
        btn.click();
        expect(fetchMock).toHaveBeenCalledTimes(1);

        resolveFetch(CRED_OPENAI);
        await vi.advanceTimersByTimeAsync(0);
        expect(btn.textContent).toBe('已填入');
        // 反馈结束后按钮恢复
        await vi.advanceTimersByTimeAsync(2000);
        expect(btn.textContent).toBe('重新同步');
    });

    it('Falsify:凭证获取挂起中 bar 被移除（视图关闭/重建）→ resolve 后不抛错、不写已移除 DOM', async () => {
        let resolveFetch;
        const { mod, bar, btn, fetchMock } = await setupBar();
        fetchMock.mockImplementationOnce(() => new Promise((r) => { resolveFetch = r; }));
        btn.click();

        bar.remove(); // 模拟 closeSimulator / renderShell 重建
        resolveFetch(CRED_OPENAI);
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();
        await vi.advanceTimersByTimeAsync(2000); // 反馈计时器到期 → 已移除 bar 不更新
        // 旧 bar 保持断开前状态（点击后禁用、未进「已填入」反馈）— 无抛错、无污染
        expect(btn.textContent).toBe('重新同步');
        expect(btn.disabled).toBe(true);
    });

    it('Falsify:旧 bar 挂起中新建 bar（重开游戏）→ 旧请求 resolve 不污染新 bar', async () => {
        let resolveOld;
        const { mod, bar: oldBar, btn: oldBtn, fetchMock } = await setupBar();
        fetchMock.mockImplementationOnce(() => new Promise((r) => { resolveOld = r; }));
        oldBtn.click();

        // 视图重建：新 bar + 重新 attach（同一模块实例）
        const newBar = makeBar();
        mod.attachKeyInject({ bar: newBar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const newBtn = newBar.querySelector('.sim-key-btn');
        const newFetch = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: newFetch });
        newBtn.click();
        await vi.advanceTimersByTimeAsync(0);
        expect(newBtn.textContent).toBe('已填入');
        expect(newFetch).toHaveBeenCalledTimes(1);

        // 旧请求此刻才 resolve → 不得触碰新 bar
        resolveOld(CRED_OPENAI);
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();
        expect(newBtn.textContent).toBe('已填入'); // 新 bar 反馈未被旧请求覆盖
    });

    it('Falsify:旧 bar 反馈计时器在途时 attach 新 bar（重开游戏）→ 旧计时器被清理、无残留更新、不抛错', async () => {
        const { mod, bar: barA, btn: btnA } = await setupBar();
        btnA.click();
        await vi.advanceTimersByTimeAsync(0);
        expect(btnA.textContent).toBe('已填入'); // barA 反馈计时器在途（2s）

        // 视图重建：attach 新 bar → 清理在途反馈计时器 + 活动 bar 切换
        const barB = makeBar();
        expect(() => mod.attachKeyInject({ bar: barB, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null })).not.toThrow();
        await vi.advanceTimersByTimeAsync(2000);

        // 旧 bar 不恢复（计时器已清，不残留「已填入」翻转）；新 bar 保持初始态
        expect(btnA.textContent).toBe('已填入');
        expect(barB.querySelector('.sim-key-btn').textContent).toBe('重新同步');
        expect(barB.querySelector('.sim-key-btn').disabled).toBe(false);
    });

    it('Falsify:未 initKeyInjector（凭证获取未注入）→ 点击静默恢复可点，不抛错', async () => {
        const mod = await loadInjector();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const btn = bar.querySelector('.sim-key-btn');

        btn.click();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();
        expect(btn.disabled).toBe(false);
        expect(btn.textContent).toBe('重新同步');
    });

    it('Falsify:attachKeyInject 缺 bar / 缺 getDoc getConfig → 点击不抛错（防御）', async () => {
        const mod = await loadInjector();
        expect(() => mod.attachKeyInject({})).not.toThrow();
        expect(() => mod.attachKeyInject(null)).not.toThrow();
        expect(() => mod.attachKeyInject({ bar: null })).not.toThrow();

        const bar = makeBar();
        mod.attachKeyInject({ bar }); // 无 getDoc/getConfig
        const btn = bar.querySelector('.sim-key-btn');
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        btn.click();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();
        expect(btn.disabled).toBe(false);
    });
});

describe('key-injector — autoSyncIntoGame 自动同步（SIM-API-1）', () => {
    beforeEach(() => { vi.useFakeTimers(); });
    afterEach(() => { vi.useRealTimers(); document.body.innerHTML = ''; });

    it('openai → 静默注入：游戏面板填值、无「已填入」反馈、按钮保持「重新同步」可点', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        const btn = bar.querySelector('.sim-key-btn');

        await mod.autoSyncIntoGame({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1');
        expect(doc.getElementById('cfg-model').value).toBe('gpt-4o-mini');
        expect(btn.textContent).toBe('重新同步'); // 静默：不闪「已填入」
        expect(btn.disabled).toBe(false);
        expect(bar.querySelector('.sim-key-msg').hidden).toBe(true);
    });

    it('openai + endpointMode=full → 端点按游戏口径转换后静默注入', async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => CRED_OPENAI) });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => 'full' });

        await mod.autoSyncIntoGame({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => 'full' });

        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1/chat/completions');
    });

    it('claude → 自动禁用按钮条 + 文案「游戏仅支持 OpenAI 兼容 Key」（不注入游戏）', async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => CRED_CLAUDE) });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });

        await mod.autoSyncIntoGame({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });

        const btn = bar.querySelector('.sim-key-btn');
        expect(btn.disabled).toBe(true);
        expect(bar.querySelector('.sim-key-msg').hidden).toBe(false);
        expect(bar.querySelector('.sim-key-msg').textContent).toContain('游戏仅支持 OpenAI 兼容 Key');
        expect(doc.getElementById('cfg-apikey').value).toBe(''); // claude key 绝不进入游戏
    });

    it('none → 自动禁用 + 「未配置 OpenAI 兼容 Key」文案（含设置页链接 — TD-71 语义随自动同步生效）', async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => CRED_NONE) });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });

        await mod.autoSyncIntoGame({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });

        const msg = bar.querySelector('.sim-key-msg');
        expect(bar.querySelector('.sim-key-btn').disabled).toBe(true);
        expect(msg.hidden).toBe(false);
        expect(msg.textContent).toContain('未配置 OpenAI 兼容 Key');
        expect(msg.querySelector('.sim-key-nav-settings')).not.toBeNull();
    });

    it('未初始化（initKeyInjector 未接线）→ bar 保持现状（不显示误导性禁用文案）', async () => {
        const mod = await loadInjector(); // 不 init
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const btn = bar.querySelector('.sim-key-btn');

        await mod.autoSyncIntoGame({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });

        expect(btn.disabled).toBe(false);
        expect(btn.textContent).toBe('重新同步');
        expect(bar.querySelector('.sim-key-msg').hidden).toBe(true);
    });

    it('Falsify:同步在途 bar 被移除（视图关闭/重建）→ resolve 后不抛错、不写已移除 DOM', async () => {
        let resolveFetch;
        const mod = await loadInjector();
        const fetchMock = vi.fn(() => new Promise((r) => { resolveFetch = r; }));
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });

        const pending = mod.autoSyncIntoGame({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        bar.remove(); // 模拟 closeSimulator / renderShell 重建
        resolveFetch(CRED_OPENAI);
        await expect(pending).resolves.not.toThrow();
        // 已移除 bar 无注入反馈、无禁用文案变更（不污染新视图）
        expect(bar.querySelector('.sim-key-btn').textContent).toBe('重新同步');
        expect(bar.querySelector('.sim-key-msg').hidden).toBe(true);
    });

    it('Falsify:autoSyncIntoGame 缺 bar → no-op 不抛错', async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => CRED_OPENAI) });
        await expect(mod.autoSyncIntoGame()).resolves.not.toThrow();
        await expect(mod.autoSyncIntoGame(null)).resolves.not.toThrow();
        await expect(mod.autoSyncIntoGame({})).resolves.not.toThrow();
    });
});

describe('key-injector — sync loop state machine', () => {
    beforeEach(() => { vi.useFakeTimers(); });
    afterEach(() => { vi.useRealTimers(); document.body.innerHTML = ''; });

    it('path 默认 (load): autoSyncIntoGame() 不带 path = load 语义（置冷却不计数）', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null };

        // 1st call: default path = load, inject + set cooldown, no count
        const r1 = await mod.autoSyncIntoGame(opts);
        expect(r1.enabled).toBe(true);
        expect(r1.written.length).toBe(3);
        expect(r1.cooled).toBeUndefined();
        expect(r1.breaker).toBeUndefined();
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // Immediate call within cooldown → cooled
        const r2 = await mod.autoSyncIntoGame(opts);
        expect(r2.cooled).toBe(true);
        expect(fetchMock).toHaveBeenCalledTimes(1); // no additional fetch

        // After cooldown expires, normal inject resumes
        await vi.advanceTimersByTimeAsync(1000);
        const r3 = await mod.autoSyncIntoGame(opts);
        expect(r3.enabled).toBe(true);
        expect(r3.cooled).toBeUndefined();
        expect(fetchMock).toHaveBeenCalledTimes(2);
    });

    it('observer 路径: 连续真写入达 SYNC_MAX_STRIKES 次后第 3 次返回 breaker: true', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        const r1 = await mod.autoSyncIntoGame(opts);
        expect(r1.breaker).toBeUndefined();
        expect(r1.enabled).toBe(true);

        await vi.advanceTimersByTimeAsync(1000);
        const r2 = await mod.autoSyncIntoGame(opts);
        expect(r2.breaker).toBeUndefined();
        expect(r2.enabled).toBe(true);

        await vi.advanceTimersByTimeAsync(1000);
        const r3 = await mod.autoSyncIntoGame(opts);
        expect(r3.breaker).toBe(true);
        expect(r3.enabled).toBe(true); // threshold-crossing call still injects
        expect(fetchMock).toHaveBeenCalledTimes(3);
    });

    it('幂等兜底: 漏断后后续 observer 调用仍返回 breaker: true', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        // Trip breaker with 3 observer calls
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            await mod.autoSyncIntoGame(opts);
        }

        // 4th call: still returns breaker, no sync
        fetchMock.mockClear();
        const r4 = await mod.autoSyncIntoGame(opts);
        expect(r4.breaker).toBe(true);
        expect(r4.enabled).toBe(false); // no sync happened
        expect(fetchMock).not.toHaveBeenCalled(); // no additional fetch

        // 5th call: still returns breaker
        const r5 = await mod.autoSyncIntoGame(opts);
        expect(r5.breaker).toBe(true);
        expect(r5.enabled).toBe(false);
        expect(fetchMock).not.toHaveBeenCalled();
    });

    it('收敛: 幂等匹配（written 空）不计数', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        // Doc with all values already matching credentials
        const doc = makeGameDoc(`
            <input id="cfg-endpoint" value="https://api.example.com/v1">
            <input id="cfg-apikey" value="sk-smoke-openai">
            <select id="cfg-model">
                <option value="gpt-4o-mini" selected>gpt-4o-mini</option>
            </select>
        `);
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        for (let i = 0; i < 5; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            const r = await mod.autoSyncIntoGame(opts);
            expect(r.breaker).toBeUndefined(); // not broken after 5 calls
            expect(r.enabled).toBe(true); // sync still happens (though idempotent)
        }
        expect(fetchMock).toHaveBeenCalledTimes(5);
    });

    it('冷却: observer 返回 cooled: true, 不注入不置冷却不计数', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        // 1st call: inject + set cooldown
        const r1 = await mod.autoSyncIntoGame(opts);
        expect(r1.enabled).toBe(true);
        expect(r1.cooled).toBeUndefined();

        // 2nd call within cooldown: cooled
        const r2 = await mod.autoSyncIntoGame(opts);
        expect(r2.cooled).toBe(true);
        expect(r2.enabled).toBe(false); // no sync
        expect(fetchMock).toHaveBeenCalledTimes(1); // no additional fetch

        // After cooldown, 3rd call: inject normally
        await vi.advanceTimersByTimeAsync(1000);
        const r3 = await mod.autoSyncIntoGame(opts);
        expect(r3.cooled).toBeUndefined();
        expect(r3.enabled).toBe(true);
        expect(fetchMock).toHaveBeenCalledTimes(2);
    });

    it('冷却: load 冷却中同样跳过 (no-op)', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null };

        // 1st load call: inject + set cooldown
        const r1 = await mod.autoSyncIntoGame(opts);
        expect(r1.enabled).toBe(true);

        // 2nd load call within cooldown: cooled
        const r2 = await mod.autoSyncIntoGame(opts);
        expect(r2.cooled).toBe(true);
        expect(r2.enabled).toBe(false);
        expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('冷却由 load 与 observer 真写入置位: 写入后 0ms 调用 → cooled, 1000ms 后 → 正常', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        const loadOpts = { bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null };
        const obsOpts = { ...loadOpts, path: 'observer' };

        // Load path: inject + set cooldown
        await mod.autoSyncIntoGame(loadOpts);

        // 0ms later: observer call → cooled
        const r1 = await mod.autoSyncIntoGame(obsOpts);
        expect(r1.cooled).toBe(true);

        // 1000ms later: observer call → normal
        await vi.advanceTimersByTimeAsync(1000);
        const r2 = await mod.autoSyncIntoGame(obsOpts);
        expect(r2.cooled).toBeUndefined();
        expect(r2.enabled).toBe(true);
    });

    it('resetSyncLoop: 幂等清零后 observer 重新从 1 开始计数', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        // Trip breaker with 3 observer calls
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            await mod.autoSyncIntoGame(opts);
        }

        // Verify breaker is tripped
        const r0 = await mod.autoSyncIntoGame(opts);
        expect(r0.breaker).toBe(true);

        // Reset
        mod.resetSyncLoop();

        // After reset, observer should start from 1
        await vi.advanceTimersByTimeAsync(1000);
        const r1 = await mod.autoSyncIntoGame(opts);
        expect(r1.breaker).toBeUndefined();
        expect(r1.enabled).toBe(true);

        // 2 more calls should trip breaker again
        await vi.advanceTimersByTimeAsync(1000);
        const r2 = await mod.autoSyncIntoGame(opts);
        expect(r2.breaker).toBeUndefined();

        await vi.advanceTimersByTimeAsync(1000);
        const r3 = await mod.autoSyncIntoGame(opts);
        expect(r3.breaker).toBe(true);
    });

    it('resetSyncLoop: 未冷却/未熔断时调用无副作用（幂等）', async () => {
        const mod = await loadInjector();
        // Call before any state is set
        expect(() => mod.resetSyncLoop()).not.toThrow();
        // Call twice
        expect(() => mod.resetSyncLoop()).not.toThrow();

        // Verify state is clean: first observer call works normally
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const doc = makePanelDoc();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        const r = await mod.autoSyncIntoGame(opts);
        expect(r.enabled).toBe(true);
        expect(r.breaker).toBeUndefined();
    });

    it('按钮路径: 熔断达阈值后点击仍可注入', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const btn = bar.querySelector('.sim-key-btn');
        const opts = { bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        // Trip breaker with 3 observer calls
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            await mod.autoSyncIntoGame(opts);
        }

        // Verify breaker is tripped
        const r = await mod.autoSyncIntoGame(opts);
        expect(r.breaker).toBe(true);

        // Button click should still work (bypasses state machine)
        fetchMock.mockClear();
        btn.click();
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(btn.textContent).toBe('已填入');
    });

    it('熔断权优先于冷却: 已熔断后 observer 恒返回 breaker, 不再走冷却判定', async () => {
        const mod = await loadInjector();
        const fetchMock = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetchMock });
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null });
        const opts = { bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG, getEndpointMode: () => null, path: 'observer' };

        // Trip breaker with 3 observer calls
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            await mod.autoSyncIntoGame(opts);
        }

        // Immediately call observer (within cooldown from 3rd call)
        // Should return breaker, not cooled
        const r = await mod.autoSyncIntoGame(opts);
        expect(r.breaker).toBe(true);
        expect(r.cooled).toBeUndefined(); // breaker takes priority
    });
});
