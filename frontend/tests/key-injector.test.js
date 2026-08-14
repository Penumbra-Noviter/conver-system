/**
 * 模拟器 Key 注入模块测试（U8-T2）。
 *
 * 覆盖：
 *   - 模块私有性：ESM 深模块，不挂 window / globalThis（注入模块不出主应用作用域）
 *   - resolveButtonState 三态：openai（key 非空）→ 可注入；claude / none →
 *     禁用（含防御分支：openai 但 key 空串、未知 protocol、null 输入）
 *   - hasConfigTriplet：config 三元组完整性（三个非空字符串 id）
 *   - injectCredentialsIntoGame 核心：填值 + 派发 input/change；空值跳过
 *     （不覆盖游戏默认）；白名单（非声明 id 不触碰）；元素类型校验
 *     （input/select 才写）；控件缺失 / 文档缺失静默降级；返回 filled/skipped
 *   - attachKeyInject 交互：点击 → 凭证获取 → 注入 → 「已填入」2s 反馈；
 *     claude/none 禁用态 + 文案；请求失败 / 全跳过静默恢复；sessionOnly 注记；
 *     幂等 attach；重复点击只发一次请求；在途视图销毁后不污染新 bar
 *   - Falsify：未 initKeyInjector 点击静默；getDoc/getConfig 缺失防御
 *
 * 测试即模块接口契约：公开面 __all__ = initKeyInjector / attachKeyInject /
 *   resolveButtonState / hasConfigTriplet / injectCredentialsIntoGame /
 *   TEXT_KEY_INJECT / TEXT_INJECTED。
 * 挂载模式：jsdom + vi.resetModules()；按钮条 fixture 与 simulator-view.js
 *   renderShell 渲染的 DOM 契约一致（.sim-key-bar / .sim-key-btn /
 *   .sim-key-msg / .sim-key-note）；注入目标文档用 createHTMLDocument 构造
 *   （注入核心只依赖文档参数 — spec「U8 注入交互」seam 清单）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** 凭证端点三态 fixture（与后端 CredentialsResponse 契约一致） */
const CRED_OPENAI = { key: 'sk-smoke-openai', endpoint: 'https://api.example.com/v1', model: 'gpt-4o-mini', protocol: 'openai' };
const CRED_CLAUDE = { key: '', endpoint: '', model: '', protocol: 'claude' };
const CRED_NONE = { key: '', endpoint: '', model: '', protocol: 'none' };

/** 游戏配置面板 DOM id 三元组（manifest config 契约） */
const CONFIG = { endpoint: 'cfg-endpoint', apikey: 'cfg-apikey', model: 'cfg-model' };

/** 按钮条 fixture — 与 simulator-view.js renderShell 渲染结构一致（DOM 契约） */
function makeBar({ sessionOnly = false } = {}) {
    const bar = document.createElement('div');
    bar.className = 'sim-key-bar';
    bar.innerHTML = `
        <button type="button" class="sim-key-btn">使用主应用 Key</button>
        <span class="sim-key-msg" role="status" hidden></span>
        ${sessionOnly ? '<span class="sim-key-note" hidden>重进游戏需再次点击</span>' : ''}
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

/** 组装：bar + initKeyInjector(mock) + attach；返回 {mod, bar, btn, msg, note, fetchMock} */
async function setupBar({ sessionOnly = false, credentials = CRED_OPENAI, getDoc = null, getConfig = null } = {}) {
    const mod = await loadInjector();
    const fetchMock = vi.fn(async () => credentials);
    mod.initKeyInjector({ getCredentials: fetchMock });
    const bar = makeBar({ sessionOnly });
    const btn = bar.querySelector('.sim-key-btn');
    const msg = bar.querySelector('.sim-key-msg');
    const note = bar.querySelector('.sim-key-note');
    mod.attachKeyInject({
        bar,
        sessionOnly,
        getDoc: getDoc ?? (() => makePanelDoc()),
        getConfig: getConfig ?? (() => CONFIG),
    });
    return { mod, bar, btn, msg, note, fetchMock };
}

describe('key-injector — 协议表面 __all__ 与模块私有性', () => {
    it('__all__ 收口公开函数', async () => {
        const mod = await loadInjector();
        expect(mod.__all__.sort()).toEqual([
            'TEXT_INJECTED', 'TEXT_KEY_INJECT',
            'attachKeyInject', 'hasConfigTriplet', 'initKeyInjector',
            'injectCredentialsIntoGame', 'resolveButtonState',
        ]);
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
        expect(result).toEqual({ filled: ['apikey', 'endpoint', 'model'], skipped: [] });
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
        expect(result).toEqual({ filled: ['apikey'], skipped: ['endpoint', 'model'] });
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
        expect(result).toEqual({ filled: ['apikey'], skipped: ['endpoint', 'model'] });
    });

    it('F1:select 无匹配 option（凭证 model 不在游戏选项集）→ model 跳过不进 filled、保持原值、不派发事件', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc(); // select 选项集：game-default-model / gpt-4o-mini
        const seen = [];
        doc.getElementById('cfg-model').addEventListener('input', () => seen.push('input'));
        doc.getElementById('cfg-model').addEventListener('change', () => seen.push('change'));

        const result = injectCredentialsIntoGame({
            doc,
            config: CONFIG,
            credentials: { ...CRED_OPENAI, model: 'deepseek-r1' }, // 不在选项集 → 赋值静默无效
        });

        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1');
        expect(doc.getElementById('cfg-model').value).toBe('game-default-model'); // 保持游戏默认
        expect(seen).toEqual([]); // 未派发 input/change（未写入）
        expect(result).toEqual({ filled: ['apikey', 'endpoint'], skipped: ['model'] });
    });

    it('Falsify:select 无任何 option → 无匹配值 → 跳过该字段不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makeGameDoc('<select id="cfg-model"></select>');
        const result = injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI });
        expect(doc.getElementById('cfg-model').value).toBe('');
        expect(result).toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
    });

    it('文本域（textarea）不算注入目标 → 跳过（目标限 input/select）', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makeGameDoc('<textarea id="cfg-apikey">orig</textarea>');
        const result = injectCredentialsIntoGame({ doc, config: CONFIG, credentials: CRED_OPENAI });
        expect(doc.getElementById('cfg-apikey').value).toBe('orig');
        expect(result).toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
    });

    it('降级：doc 缺失（null / 无 getElementById）→ 全 skipped 不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        expect(injectCredentialsIntoGame({ doc: null, config: CONFIG, credentials: CRED_OPENAI }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
        expect(injectCredentialsIntoGame({ doc: {}, config: CONFIG, credentials: CRED_OPENAI }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
    });

    it('降级：config 缺失 / config 字段非字符串 → 跳过该字段不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        expect(injectCredentialsIntoGame({ doc, config: null, credentials: CRED_OPENAI }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
        // endpoint 字段非字符串 → 仅该字段跳过；apikey/model 声明 id 正常注入
        expect(injectCredentialsIntoGame({ doc, config: { endpoint: 42, apikey: 'cfg-apikey', model: 'cfg-model' }, credentials: CRED_OPENAI }))
            .toEqual({ filled: ['apikey', 'model'], skipped: ['endpoint'] });
    });

    it('降级：凭证缺失（null / 字段非字符串）→ 全 skipped 不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        const doc = makePanelDoc();
        expect(injectCredentialsIntoGame({ doc, config: CONFIG, credentials: null }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
        expect(injectCredentialsIntoGame({ doc, config: CONFIG, credentials: { key: 7 } }))
            .toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
    });

    it('防御：整包参数缺失 → 全 skipped 不抛错', async () => {
        const { injectCredentialsIntoGame } = await loadInjector();
        expect(injectCredentialsIntoGame()).toEqual({ filled: [], skipped: ['apikey', 'endpoint', 'model'] });
    });
});

describe('key-injector — attachKeyInject 交互（点击 → 注入 → 反馈）', () => {
    beforeEach(() => { vi.useFakeTimers(); });
    afterEach(() => { vi.useRealTimers(); document.body.innerHTML = ''; });

    it('点击 → 调凭证获取 → 注入 getDoc() 文档 → 按钮「已填入」→ 2s 后恢复「使用主应用 Key」可点', async () => {
        const { bar, btn, msg, fetchMock } = await setupBar();
        btn.click();
        await vi.advanceTimersByTimeAsync(0); // 冲刷 fetch/inject 微任务

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(btn.textContent).toBe('已填入');
        expect(btn.disabled).toBe(true); // 反馈期间禁用（防重复点击）
        expect(msg.hidden).toBe(true);

        await vi.advanceTimersByTimeAsync(2000);
        expect(btn.textContent).toBe('使用主应用 Key');
        expect(btn.disabled).toBe(false);
    });

    it('claude → 按钮禁用 + 文案「游戏仅支持 OpenAI 兼容 Key」（区分 claude-only）', async () => {
        const { bar, btn, msg } = await setupBar({ credentials: CRED_CLAUDE });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        expect(btn.disabled).toBe(true);
        expect(msg.hidden).toBe(false);
        expect(msg.textContent).toBe('游戏仅支持 OpenAI 兼容 Key');
    });

    it('none → 按钮禁用 + 文案「未配置 OpenAI 兼容 Key」', async () => {
        const { bar, btn, msg } = await setupBar({ credentials: CRED_NONE });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        expect(btn.disabled).toBe(true);
        expect(msg.hidden).toBe(false);
        expect(msg.textContent).toBe('未配置 OpenAI 兼容 Key');
    });

    it('请求失败（fetch 拒绝）→ 静默降级：无抛错、按钮恢复可点、无禁用文案', async () => {
        const { mod, bar, btn, msg, fetchMock } = await setupBar();
        fetchMock.mockRejectedValueOnce(new Error('网络错误'));
        btn.click();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();

        expect(btn.disabled).toBe(false);
        expect(btn.textContent).toBe('使用主应用 Key');
        expect(msg.hidden).toBe(true);
    });

    it('注入 0 个字段（控件全缺失）→ 静默降级：无「已填入」、按钮恢复可点（用户可手动配置）', async () => {
        const { bar, btn } = await setupBar({ getDoc: () => makeGameDoc('<div></div>') });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);

        expect(btn.textContent).toBe('使用主应用 Key');
        expect(btn.disabled).toBe(false);
    });

    it('F1 交互:select 无匹配 option → model 静默跳过（未写入未派发），key 已注入 → 按钮「已填入」如实反馈', async () => {
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

        expect(btn.textContent).toBe('已填入'); // key/endpoint 注入成功 → 反馈如实
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(modelEl.value).toBe('game-default-model'); // model 未被误填
        expect(events).toEqual([]); // 未派发事件
    });

    it('sessionOnly（wg_ 族）注入成功 → 注记「重进游戏需再次点击」可见；非 sessionOnly 无注记', async () => {
        const { bar, btn, note } = await setupBar({ sessionOnly: true });
        btn.click();
        await vi.advanceTimersByTimeAsync(0);
        expect(note).not.toBeNull();
        expect(note.hidden).toBe(false);
        expect(note.textContent).toBe('重进游戏需再次点击');

        // 非 sessionOnly：bar 无注记元素
        const { bar: bar2, btn: btn2, note: note2 } = await setupBar({ sessionOnly: false });
        expect(note2).toBeNull();
        btn2.click();
        await vi.advanceTimersByTimeAsync(0);
        expect(bar2.querySelector('.sim-key-note')).toBeNull();
    });

    it('幂等 attach：同一 bar 重复 attach → 点击只触发一次凭证获取（无重复监听）', async () => {
        const { mod, bar, btn, fetchMock } = await setupBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG });
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG });

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
        expect(btn.textContent).toBe('使用主应用 Key');
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
        expect(btn.textContent).toBe('使用主应用 Key');
        expect(btn.disabled).toBe(true);
    });

    it('Falsify:旧 bar 挂起中新建 bar（重开游戏）→ 旧请求 resolve 不污染新 bar', async () => {
        let resolveOld;
        const { mod, bar: oldBar, btn: oldBtn, fetchMock } = await setupBar();
        fetchMock.mockImplementationOnce(() => new Promise((r) => { resolveOld = r; }));
        oldBtn.click();

        // 视图重建：新 bar + 重新 attach（同一模块实例）
        const newBar = makeBar();
        mod.attachKeyInject({ bar: newBar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG });
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
        expect(() => mod.attachKeyInject({ bar: barB, getDoc: () => makePanelDoc(), getConfig: () => CONFIG })).not.toThrow();
        await vi.advanceTimersByTimeAsync(2000);

        // 旧 bar 不恢复（计时器已清，不残留「已填入」翻转）；新 bar 保持初始态
        expect(btnA.textContent).toBe('已填入');
        expect(barB.querySelector('.sim-key-btn').textContent).toBe('使用主应用 Key');
        expect(barB.querySelector('.sim-key-btn').disabled).toBe(false);
    });

    it('Falsify:未 initKeyInjector（凭证获取未注入）→ 点击静默恢复可点，不抛错', async () => {
        const mod = await loadInjector();
        const bar = makeBar();
        mod.attachKeyInject({ bar, getDoc: () => makePanelDoc(), getConfig: () => CONFIG });
        const btn = bar.querySelector('.sim-key-btn');

        btn.click();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();
        expect(btn.disabled).toBe(false);
        expect(btn.textContent).toBe('使用主应用 Key');
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
