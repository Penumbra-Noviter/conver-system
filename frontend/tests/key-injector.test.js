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
 *   observeConfigControls / disconnectObserver / mutationTouchesConfig /
 *   TEXT_RESYNC / TEXT_INJECTED / resetSyncLoop（18 项）。
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

/** 装配配置控件观察者（S3 观察者生命周期 seam）：bar + initKeyInjector(mock) +
 * attach + observeConfigControls 挂到游戏文档；返回 {mod, bar, doc, fetchMock}。
 * 观察→过滤→防抖→同步→冷却→熔断→断连闭环在 key-injector 单一模块内 ——
 * 参数化接收 doc/config/endpointMode，不读任何视图模块状态。 */
async function setupObserver({ credentials = CRED_OPENAI, config = CONFIG, endpointMode = null } = {}) {
    const mod = await loadInjector();
    const fetchMock = vi.fn(async () => credentials);
    mod.initKeyInjector({ getCredentials: fetchMock });
    const bar = makeBar();
    const doc = makePanelDoc();
    mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => config, getEndpointMode: () => endpointMode });
    mod.observeConfigControls({ doc, config, endpointMode, bar });
    return { mod, bar, doc, fetchMock };
}

/** 游戏重建配置面板（innerHTML 替换 — 控件恢复默认值；病理循环重置动作） */
function rebuildPanel(doc) {
    doc.body.innerHTML = `
        <input id="cfg-endpoint" value="game-default-endpoint">
        <input id="cfg-apikey">
        <select id="cfg-model"><option value="game-default-model">game-default-model</option></select>
    `;
}

describe('key-injector — 协议表面 __all__ 与模块私有性', () => {
    it('__all__ 收口公开函数', async () => {
        const mod = await loadInjector();
        expect(mod.__all__.sort()).toEqual([
            'LINK_NAV_SETTINGS', 'MSG_CLAUDE_ONLY', 'MSG_NO_CREDENTIALS',
            'SEL_NAV_SETTINGS',
            'TEXT_INJECTED', 'TEXT_RESYNC',
            'attachKeyInject', 'autoSyncIntoGame', 'convertEndpoint',
            'disconnectObserver', 'hasConfigTriplet', 'initKeyInjector',
            'injectCredentialsIntoGame', 'mutationTouchesConfig',
            'observeConfigControls', 'resetSyncLoop',
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

        const result = await mod.syncGameCredentials({ getDoc: () => doc, config: CONFIG, endpointMode: null });

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

        const result = await mod.syncGameCredentials({ getDoc: () => doc, config: CONFIG, endpointMode: null });

        expect(result).toEqual({ enabled: false, reason: 'claude', filled: [], skipped: [], written: [] });
        expect(doc.getElementById('cfg-apikey').value).toBe(''); // 未写入
        expect(doc.getElementById('cfg-endpoint').value).toBe('game-default-endpoint');
    });

    it("none → 不注入返回 { enabled: false, reason: 'none' }", async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => CRED_NONE) });
        const doc = makePanelDoc();
        const result = await mod.syncGameCredentials({ getDoc: () => doc, config: CONFIG });
        expect(result).toEqual({ enabled: false, reason: 'none', filled: [], skipped: [], written: [] });
        expect(doc.getElementById('cfg-apikey').value).toBe('');
    });

    it('未初始化（initKeyInjector 未接线）→ 返回 null（调用方静默保持现状）', async () => {
        const mod = await loadInjector(); // 不 init
        expect(await mod.syncGameCredentials({ getDoc: () => makePanelDoc(), config: CONFIG })).toBeNull();
    });

    it('凭证获取失败 → 拒绝（调用方按路径降级）', async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => { throw new Error('网络错误'); }) });
        await expect(mod.syncGameCredentials({ getDoc: () => makePanelDoc(), config: CONFIG }))
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

describe('key-injector — mutationTouchesConfig 观察者过滤（纯函数 — S3 参数化 seam）', () => {
    /** 构造 game 文档内元素（id 成员判定用 — 纯函数不依赖 iframe 元素） */
    const el = (html) => makeGameDoc(html).body.firstElementChild;
    /** 构造 MutationRecord 形状（childList 默认；只取过滤关心的字段） */
    const rec = (partial) => ({ type: 'childList', addedNodes: [], removedNodes: [], target: null, ...partial });

    it('childList added 节点自身 id ∈ 三元组 → true', async () => {
        const { mutationTouchesConfig } = await loadInjector();
        expect(mutationTouchesConfig([rec({ addedNodes: [el('<input id="cfg-apikey">')] })], CONFIG)).toBe(true);
    });

    it('childList added 子树含三元组 id（游戏整段重建配置面板）→ true', async () => {
        const { mutationTouchesConfig } = await loadInjector();
        const subtree = el('<div><section><input id="cfg-model"></section></div>');
        expect(mutationTouchesConfig([rec({ addedNodes: [subtree] })], CONFIG)).toBe(true);
    });

    it('childList removed 节点自身/子树含三元组 id → true', async () => {
        const { mutationTouchesConfig } = await loadInjector();
        expect(mutationTouchesConfig([rec({ removedNodes: [el('<input id="cfg-endpoint">')] })], CONFIG)).toBe(true);
        expect(mutationTouchesConfig([rec({ removedNodes: [el('<div><input id="cfg-model"></div>')] })], CONFIG)).toBe(true);
    });

    it('attributes 变更：目标元素自身 id ∈ 三元组 → true（TD-75 setAttribute 重建路径 — 属性变更仅目标自身判定）', async () => {
        const { mutationTouchesConfig } = await loadInjector();
        const target = el('<input id="cfg-apikey">');
        expect(mutationTouchesConfig([rec({ type: 'attributes', target, attributeName: 'value' })], CONFIG)).toBe(true);
    });

    it('attributes 变更：目标 id 不在三元组（attributeFilter 外运行期属性元素）→ false', async () => {
        const { mutationTouchesConfig } = await loadInjector();
        const status = el('<div id="game-status" class="x"></div>');
        expect(mutationTouchesConfig([rec({ type: 'attributes', target: status, attributeName: 'class' })], CONFIG)).toBe(false);
    });

    it('三元组不完整 / config 缺失 → false（id 白名单为空 — 无命中可判定）', async () => {
        const { mutationTouchesConfig } = await loadInjector();
        const hit = [rec({ addedNodes: [el('<input id="cfg-apikey">')] })];
        expect(mutationTouchesConfig(hit, null)).toBe(false);
        expect(mutationTouchesConfig(hit, undefined)).toBe(false);
        expect(mutationTouchesConfig(hit, { endpoint: 'e', apikey: 'k' })).toBe(false);
        expect(mutationTouchesConfig(hit, { ...CONFIG, apikey: '' })).toBe(false); // 残缺三元组 → 该 id 不在白名单
    });

    it('空 mutations / 无关 id / 文本节点 → false（游戏运行期高频 DOM 更新不触发同步）', async () => {
        const { mutationTouchesConfig } = await loadInjector();
        expect(mutationTouchesConfig([], CONFIG)).toBe(false);
        expect(mutationTouchesConfig(undefined, CONFIG)).toBe(false);
        expect(mutationTouchesConfig(null, CONFIG)).toBe(false);
        const unrelated = el('<div id="npc-dialog">对话</div>');
        expect(mutationTouchesConfig([rec({ addedNodes: [unrelated] })], CONFIG)).toBe(false);
        const text = makeGameDoc('plain text').body.firstChild; // 文本节点（nodeType 3）
        expect(text.nodeType).toBe(3);
        expect(mutationTouchesConfig([rec({ addedNodes: [text] })], CONFIG)).toBe(false);
    });
});

describe('key-injector — 配置控件观察者生命周期（S3 — 观察→过滤→防抖→同步→冷却→熔断→断连）', () => {
    beforeEach(() => { vi.useFakeTimers(); });
    afterEach(() => { vi.useRealTimers(); document.body.innerHTML = ''; });

    it('observe 挂载后：配置控件结构重建（childList + subtree）→ 防抖后观察者路径再同步（参数化 doc/config/endpointMode — 不读视图状态）', async () => {
        const { doc, fetchMock } = await setupObserver();
        expect(fetchMock).not.toHaveBeenCalled(); // 挂载本身不触发同步

        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500); // 观察者防抖到期
        await vi.advanceTimersByTimeAsync(0); // 再同步微任务

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1');
        expect(doc.getElementById('cfg-model').value).toBe('gpt-4o-mini');
    });

    it('observe 参数化口径：endpointMode=full → 以游戏口径转换后同步', async () => {
        const { doc, fetchMock } = await setupObserver({ endpointMode: 'full' });

        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1/chat/completions');
    });

    it('防抖（observerTimer）：500ms 窗口内连续重建合并为一次同步', async () => {
        const { doc, fetchMock } = await setupObserver();

        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(100);
        rebuildPanel(doc); // 窗口内第二次变化（重置防抖计时器）
        await vi.advanceTimersByTimeAsync(100);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);

        expect(fetchMock).toHaveBeenCalledTimes(1); // 合并为一次同步
    });

    it('attributeFilter 外属性（配置控件自身 class/style 翻转）→ 回调不被交付、不触发同步（观察参数白名单保持）', async () => {
        const { doc, fetchMock } = await setupObserver();

        const apikeyEl = doc.getElementById('cfg-apikey');
        apikeyEl.setAttribute('class', 'state-1');
        apikeyEl.setAttribute('style', 'color: red');
        await vi.advanceTimersByTimeAsync(2000);

        expect(fetchMock).not.toHaveBeenCalled(); // attributeFilter ['value','hidden'] 先行拦截，无自触发面
    });

    it('TD-75:票面属性 value（setAttribute 重建控件值）→ 防抖后触发再同步', async () => {
        const { doc, fetchMock } = await setupObserver();

        doc.getElementById('cfg-apikey').setAttribute('value', '');
        doc.getElementById('cfg-endpoint').setAttribute('value', 'game-default-endpoint');
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai'); // 主应用配置重新生效
    });

    it('写回环冷却：真写入后冷却窗内重建 → 防抖到期跳过；冷却过后重建恢复', async () => {
        const { doc, fetchMock } = await setupObserver();

        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1); // 首轮同步（真写入 → 置冷却）

        rebuildPanel(doc); // 冷却窗内重建（自写入反应）
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetchMock).toHaveBeenCalledTimes(1); // 冷却内防抖到期跳过（无额外 fetch）

        await vi.advanceTimersByTimeAsync(1000); // 冷却已过
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(2); // 恢复再同步
    });

    it('断连（disconnectObserver）：断连后游戏文档变更不再触发同步', async () => {
        const { mod, doc, fetchMock } = await setupObserver();

        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        mod.disconnectObserver();
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetchMock).toHaveBeenCalledTimes(1); // 断连后不再响应
    });

    it('F-89 断连失效守卫：在途同步期间 destroyFrame（断连+复位）→ 陈旧在途写变 no-op，syncStrikes 不污染新观察者循环', async () => {
        const mod = await loadInjector();
        // 延迟解析的凭证获取 —— 模拟凭证 fetch（await autoSyncIntoGame）窗口
        let resolveCreds;
        const fetchMock = vi.fn(() => new Promise((resolve) => { resolveCreds = resolve; }));
        mod.initKeyInjector({ getCredentials: fetchMock });

        const bar = makeBar();
        const doc = makePanelDoc();
        mod.attachKeyInject({ bar, getDoc: () => doc, getConfig: () => CONFIG, getEndpointMode: () => null });
        mod.observeConfigControls({ doc, config: CONFIG, endpointMode: null, bar });

        // 游戏重建配置面板 → 防抖到期 → observer 路径同步在途（凭证 fetch 挂起）
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500); // 防抖到期 → flushObserverSync 启动并挂起
        expect(fetchMock).toHaveBeenCalledTimes(1); // 同步在途（解析前无任何写入）

        // 帧销毁序列（simulator-view destroyFrame 语义）：断连（observerContext=null）+ 复位计数
        mod.disconnectObserver();
        mod.resetSyncLoop();

        // 在途凭证此时才返回 → 陈旧在途写必须被拦截（不得落在已销毁帧的 document）
        resolveCreds(CRED_OPENAI);
        await vi.advanceTimersByTimeAsync(0); // 陈旧在途同步续体结算

        // 断言 1：陈旧在途写不落地 — 旧 doc 配置面板保持游戏默认（未注入）
        expect(doc.getElementById('cfg-apikey').value).toBe('');
        expect(doc.getElementById('cfg-endpoint').value).toBe('game-default-endpoint');

        // 断言 2：熔断计数未被污染 — 重开游戏的新观察者循环仍以 0 strikes 起步：
        // 恰 3 轮真写入才熔断（陈旧写若被计数，新循环第 2 轮即提前熔断断连）
        const doc2 = makePanelDoc();
        const bar2 = makeBar();
        const fetch2 = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetch2 });
        mod.attachKeyInject({ bar: bar2, getDoc: () => doc2, getConfig: () => CONFIG, getEndpointMode: () => null });
        mod.observeConfigControls({ doc: doc2, config: CONFIG, endpointMode: null, bar: bar2 });

        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000); // 越过写回环冷却（每轮真写入置冷却）
            rebuildPanel(doc2);
            await vi.advanceTimersByTimeAsync(500); // 观察者防抖
            await vi.advanceTimersByTimeAsync(0); // 同步微任务
        }
        expect(fetch2).toHaveBeenCalledTimes(3); // 熔断阈值以真实写入计（未被陈旧写提前污染）

        // 第 3 轮真写后熔断 → 观察者断开：后续重建不再同步（与既有熔断用例同构）
        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc2);
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetch2).toHaveBeenCalledTimes(3); // 已断连 → 不复活同步
    });

    it('断连清理在途防抖：断连 + 重开重挂后，旧防抖到期不得以新会话上下文执行同步', async () => {
        const { mod, doc, fetchMock } = await setupObserver();

        rebuildPanel(doc); // 触发变更 → 调度旧会话防抖
        await vi.advanceTimersByTimeAsync(100); // 旧防抖在途（< 500ms）
        mod.disconnectObserver(); // 断连：清防抖计时器（本契约点）—— 旧防抖作废
        expect(fetchMock).not.toHaveBeenCalled(); // 断连本身不触发同步

        // 重开游戏（同模块）：重新 observe 新文档 → 新观察者上下文就位
        const doc2 = makePanelDoc();
        const bar2 = makeBar();
        const fetch2 = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetch2 });
        mod.attachKeyInject({ bar: bar2, getDoc: () => doc2, getConfig: () => CONFIG, getEndpointMode: () => null });
        mod.observeConfigControls({ doc: doc2, config: CONFIG, endpointMode: null, bar: bar2 });

        await vi.advanceTimersByTimeAsync(2000); // 越过旧防抖到期点
        expect(fetch2).not.toHaveBeenCalled(); // 旧防抖已被断连清理 → 不以新会话上下文幽灵同步
    });

    it('熔断后断连：连续 3 轮重建+真写入 → 第 3 次同步后观察者断开，后续重建不再同步', async () => {
        const { mod, doc, fetchMock } = await setupObserver();

        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000); // 越过写回环冷却（重建落在冷却窗外 — TD-76 病理循环钉层）
            rebuildPanel(doc);
            await vi.advanceTimersByTimeAsync(500); // 观察者防抖
            await vi.advanceTimersByTimeAsync(0); // 再同步微任务
        }
        expect(fetchMock).toHaveBeenCalledTimes(3); // 3 轮观察者同步（第 3 次后熔断）

        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetchMock).toHaveBeenCalledTimes(3); // 熔断 → 不再同步（fetch 数封顶）

        // 断连判定探针：仅复位熔断计数（不重挂观察者 — 真实流程中断连与复位仅在
        // destroyFrame 成对出现）→ 若观察者仍连接则同步复活；已断连则保持封顶。
        mod.resetSyncLoop();
        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetchMock).toHaveBeenCalledTimes(3); // 观察者已断开 → 复位计数不复活同步
    });

    it('熔断后重开（断连 + resetSyncLoop + 重新 observe）→ 新同步循环恢复工作', async () => {
        const { mod, doc, fetchMock } = await setupObserver();

        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            rebuildPanel(doc);
            await vi.advanceTimersByTimeAsync(500);
            await vi.advanceTimersByTimeAsync(0);
        }
        expect(fetchMock).toHaveBeenCalledTimes(3);

        // 视图销毁序列（destroyFrame 语义）：断连 + 复位
        mod.disconnectObserver();
        mod.resetSyncLoop();
        // 重开游戏：同一模块重新 observe（新文档）
        const doc2 = makePanelDoc();
        const bar2 = makeBar();
        const fetch2 = vi.fn(async () => CRED_OPENAI);
        mod.initKeyInjector({ getCredentials: fetch2 });
        mod.attachKeyInject({ bar: bar2, getDoc: () => doc2, getConfig: () => CONFIG, getEndpointMode: () => null });
        mod.observeConfigControls({ doc: doc2, config: CONFIG, endpointMode: null, bar: bar2 });

        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc2);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetch2).toHaveBeenCalledTimes(1); // 复位后观察者恢复工作
        expect(doc2.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
    });

    it('防御：doc / bar / 三元组缺失或不全 → observe no-op 不抛错（Falsify）', async () => {
        const mod = await loadInjector();
        mod.initKeyInjector({ getCredentials: vi.fn(async () => CRED_OPENAI) });
        const bar = makeBar();
        const doc = makePanelDoc();
        expect(() => mod.observeConfigControls()).not.toThrow();
        expect(() => mod.observeConfigControls(null)).not.toThrow();
        expect(() => mod.observeConfigControls({})).not.toThrow();
        expect(() => mod.observeConfigControls({ doc, config: CONFIG })).not.toThrow(); // 缺 bar
        expect(() => mod.observeConfigControls({ doc, bar })).not.toThrow(); // 缺 config
        expect(() => mod.observeConfigControls({ doc, config: { endpoint: 'e' }, bar })).not.toThrow(); // 三元组不全
        expect(() => mod.observeConfigControls({ doc: null, config: CONFIG, bar })).not.toThrow(); // doc 缺失
        expect(() => mod.observeConfigControls({ doc, config: CONFIG, bar })).not.toThrow(); // 正常挂载路径
    });

    it('断连幂等：未挂载 / 重复断连 → 不抛错', async () => {
        const mod = await loadInjector();
        expect(() => mod.disconnectObserver()).not.toThrow();
        const { mod: fresh } = await setupObserver();
        expect(() => fresh.disconnectObserver()).not.toThrow();
        expect(() => fresh.disconnectObserver()).not.toThrow();
    });
});
