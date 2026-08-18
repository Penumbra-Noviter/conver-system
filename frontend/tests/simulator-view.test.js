/**
 * 模拟器运行视图模块测试（U7-T4 + U8-T2 + SIM-API-1）。
 *
 * 覆盖：
 *   - 状态机全迁移：open → opening（加载中占位 + iframe 隐藏）→ 派发 load
 *     事件 → loaded（iframe 可见、列表面板隐藏）；open → 超时（fake timers
 *     推进 15s）→ error（错误文案 + 重试/返回按钮）
 *   - 重试：error 态点重试 → 重新 opening → loaded；返回：closeSimulator →
 *     运行面板隐藏、列表面板恢复、iframe 卸载（计时器清理）
 *   - 打开参数非法（null / 非对象 / file 缺失 / 空串 / 非字符串 / 含路径分隔符
 *     — iframe src 注入守卫）→ 直接 error 态，不创建 iframe
 *   - AI 提示条：type=ai 渲染「此游戏需自行配置 AI 接口」；type=local（及
 *     缺 type 防御）不渲染
 *   - XSS：game.name 来自 manifest 第三方数据 → header 渲染经 escapeHtml 转义
 *   - Falsify：未 init 调 open/close no-op 不抛错；重复 init 幂等；重复 open
 *     只留最新 iframe 且计时器单一；open 中 close 后推进超时无残留错误
 *   - 配置同步（U8-T2 + SIM-API-1）：按钮条渲染条件（ai + 完整 config 三元组
 *     → 「重新同步」按钮）；load 自动同步（openai → 面板已填值（endpointMode
 *     口径转换 / 受管 model option）/ claude·none → 按钮自动禁用 + 文案 /
 *     凭证失败 → 静默）；点击手动重新同步（「已填入」2s 反馈）；配置控件重建
 *     观察者（防抖再同步 / 触发时机 — 冷却/熔断语义见 key-injector 状态机用例）
 *
 * 测试即模块接口契约：公开面 __all__ = initSimulatorRun / openSimulator /
 *   closeSimulator。jsdom 不自动触发 iframe load（已探测）——load 事件由
 *   测试手动派发（addEventListener 监听，非内联 onload）。
 * 挂载模式：jsdom + vi.resetModules() + 内联面板 DOM（index.html id 契约）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** 最小双面板 DOM — 与 index.html 的 #simulator-list-panel /
 *  #simulator-run-panel 契约一致（只读契约） */
const PANELS_DOM_HTML = `
    <div id="simulator-list-panel"></div>
    <div id="simulator-run-panel" hidden></div>
`;

/** 合法游戏 fixture（ai / local / 缺 type 防御） */
const GAME_AI = { id: 'life-sim', file: '人生模拟器v3.html', name: '人生模拟器 v3', type: 'ai', description: 'AI 驱动的生命模拟' };
const GAME_LOCAL = { id: 'spider-shadow', file: '蛛网之影.html', name: '蛛网之影', type: 'local' };

/** ai 游戏 + 完整 config 三元组（U8-T2 按钮渲染条件；manifest config 契约；
 * endpointMode='full' 与真实 manifest life-sim 条目一致 — SIM-API-1 端点
 * 口径转换契约） */
const GAME_AI_CONFIG = {
    id: 'life-sim', file: '人生模拟器v3.html', name: '人生模拟器 v3', type: 'ai',
    config: { endpoint: 'cfg-endpoint', apikey: 'cfg-apikey', model: 'cfg-model' },
    endpointMode: 'full',
};

/** openai 凭证响应（凭证端点契约；endpoint 为 base URL 形态） */
const CRED_OPENAI = { key: 'sk-smoke-openai', endpoint: 'https://api.example.com/v1', model: 'gpt-4o-mini', protocol: 'openai' };

/** 加载全新 simulator-view 模块（DOM 先就位；返回模块 + 双面板引用） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = PANELS_DOM_HTML;
    const view = await import('../js/simulator-view.js');
    return {
        view,
        listPanel: document.querySelector('#simulator-list-panel'),
        runPanel: document.querySelector('#simulator-run-panel'),
    };
}

/** 打开游戏并手动派发 iframe load 事件（jsdom 不自动触发） */
function openAndLoad(view, game) {
    view.openSimulator(game);
    const frame = document.querySelector('#simulator-run-panel iframe');
    frame.dispatchEvent(new Event('load'));
    return frame;
}

/** 当前运行面板内的 iframe（无则 null） */
const frameEl = () => document.querySelector('#simulator-run-panel iframe');

describe('simulator-view — 协议表面 __all__', () => {
    it('__all__ 收口公开函数', async () => {
        const { view } = await loadModules();
        expect(view.__all__.sort()).toEqual(['closeSimulator', 'initSimulatorRun', 'openSimulator']);
    });
});

describe('simulator-view — 状态机（opening → loaded）', () => {
    beforeEach(() => { vi.useFakeTimers(); vi.restoreAllMocks(); });
    afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

    it('open(ai) → opening：运行面板可见、列表面板隐藏、加载占位 + 隐藏 iframe（src 指向 simulators/<file>）+ AI 提示条', async () => {
        const { view, listPanel, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel, runPanel });
        view.openSimulator(GAME_AI);

        expect(runPanel.hidden).toBe(false);
        expect(listPanel.hidden).toBe(true);
        expect(runPanel.querySelector('.sim-run-status').textContent).toBe('加载中…');
        const frame = frameEl();
        expect(frame).not.toBeNull();
        expect(frame.getAttribute('src')).toBe('simulators/人生模拟器v3.html');
        expect(frame.classList.contains('sim-run-frame-hidden')).toBe(true);
        expect(runPanel.querySelector('.sim-run-name').textContent).toBe('人生模拟器 v3');
        expect(runPanel.querySelector('.sim-run-hint').textContent).toBe('此游戏需自行配置 AI 接口');
        expect(runPanel.querySelector('.sim-run-back')).not.toBeNull();
    });

    it('派发 load 事件 → loaded：iframe 可见、加载占位移除、计时器清理（推进 15s 仍 loaded）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        openAndLoad(view, GAME_AI);

        const frame = frameEl();
        expect(frame.classList.contains('sim-run-frame-hidden')).toBe(false);
        expect(runPanel.querySelector('.sim-run-status')).toBeNull();
        // 计时器已清理：推进 15s 不落入 error
        vi.advanceTimersByTime(15000);
        expect(runPanel.querySelector('.sim-run-error')).toBeNull();
        expect(frameEl()).not.toBeNull();
    });

    it('local 游戏 → 不渲染 AI 提示条', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_LOCAL);

        expect(runPanel.querySelector('.sim-run-hint')).toBeNull();
        expect(frameEl().getAttribute('src')).toBe('simulators/蛛网之影.html');
    });

    it('缺 type 防御：file 合法但无 type → 正常打开、无提示条（不报错）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator({ file: 'x.html', name: 'X' });

        expect(runPanel.querySelector('.sim-run-hint')).toBeNull();
        expect(frameEl()).not.toBeNull();
    });

    it('XSS：game.name 含 HTML 标记（manifest 第三方数据）→ header 转义渲染', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator({ file: 'x.html', name: '<b>X</b><script>alert(1)</script>', type: 'ai' });

        const nameEl = runPanel.querySelector('.sim-run-name');
        expect(nameEl.innerHTML).toBe('&lt;b&gt;X&lt;/b&gt;&lt;script&gt;alert(1)&lt;/script&gt;');
        expect(nameEl.textContent).toBe('<b>X</b><script>alert(1)</script>');
    });
});

describe('simulator-view — 错误态（超时 / 参数非法）与恢复', () => {
    beforeEach(() => { vi.useFakeTimers(); vi.restoreAllMocks(); });
    afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

    it('open → 推进 15s 未收到 load → error：错误文案 + 重试/返回按钮，iframe 已卸载', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);

        vi.advanceTimersByTime(15000);

        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
        expect(runPanel.querySelector('.sim-run-error-msg').textContent).toBe('游戏加载失败');
        expect(runPanel.querySelector('.sim-run-error-reason').textContent).toBe('加载超时（15 秒未收到响应）');
        expect(runPanel.querySelector('[data-action="retry"]')).not.toBeNull();
        expect(runPanel.querySelector('[data-action="back"]')).not.toBeNull();
        expect(frameEl()).toBeNull();
    });

    it('重试：error 态点重试 → 重新 opening（新 iframe）→ 派发 load → loaded', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        vi.advanceTimersByTime(15000);
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();

        runPanel.querySelector('[data-action="retry"]').click();
        expect(runPanel.querySelector('.sim-run-status').textContent).toBe('加载中…');
        const frame2 = frameEl();
        expect(frame2).not.toBeNull();
        expect(frame2.getAttribute('src')).toBe('simulators/人生模拟器v3.html');

        frame2.dispatchEvent(new Event('load'));
        expect(frame2.classList.contains('sim-run-frame-hidden')).toBe(false);
        expect(runPanel.querySelector('.sim-run-error')).toBeNull();
    });

    it('error 态点返回 → closeSimulator 语义：面板恢复、iframe 卸载', async () => {
        const { view, listPanel, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel, runPanel });
        view.openSimulator(GAME_AI);
        vi.advanceTimersByTime(15000);

        runPanel.querySelector('[data-action="back"]').click();
        expect(runPanel.hidden).toBe(true);
        expect(listPanel.hidden).toBe(false);
        expect(frameEl()).toBeNull();
    });

    it('openSimulator(null / 非对象 / file 缺失 / 空串 / 非字符串) → 直接 error 态，不创建 iframe', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });

        for (const bad of [null, undefined, 'x', {}, { file: '' }, { file: 42 }, { file: null }]) {
            view.openSimulator(bad);
            expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
            expect(frameEl()).toBeNull();
            expect(runPanel.querySelector('.sim-run-error-reason').textContent).toBe('参数非法：缺少有效的游戏文件');
        }
    });

    it('Falsify:file 含路径分隔符（iframe src 注入守卫）→ 直接 error 态，不创建 iframe', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });

        view.openSimulator({ file: '../evil.html', name: 'x', type: 'ai' });
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
        expect(frameEl()).toBeNull();

        view.openSimulator({ file: 'a/b.html', name: 'x', type: 'ai' });
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
        expect(frameEl()).toBeNull();

        view.openSimulator({ file: 'http://evil.com/x.html', name: 'x', type: 'ai' });
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
        expect(frameEl()).toBeNull();
    });

    it('TD-56:file 含百分号编码（如 ..%2f 穿越 / 正常名含 %20）→ 直接 error 态，不创建 iframe', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });

        view.openSimulator({ file: '..%2f..%2fsecret.html', name: 'x', type: 'ai' });
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
        expect(frameEl()).toBeNull();
        expect(runPanel.querySelector('.sim-run-error-reason').textContent).toBe('参数非法：缺少有效的游戏文件');

        view.openSimulator({ file: '正常游戏%20v2.html', name: 'y' });
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
        expect(frameEl()).toBeNull();
    });

    it('参数非法 error 态点重试（同一非法 game）→ 再次 error，不创建 iframe，不抛错', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator({});

        expect(() => runPanel.querySelector('[data-action="retry"]').click()).not.toThrow();
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
        expect(frameEl()).toBeNull();
    });
});

describe('simulator-view — closeSimulator 返回与守卫', () => {
    beforeEach(() => { vi.useFakeTimers(); vi.restoreAllMocks(); });
    afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

    it('closeSimulator：运行面板隐藏、列表面板恢复、iframe 卸载、计时器清理', async () => {
        const { view, listPanel, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel, runPanel });
        openAndLoad(view, GAME_AI);
        expect(frameEl()).not.toBeNull();

        view.closeSimulator();
        expect(runPanel.hidden).toBe(true);
        expect(listPanel.hidden).toBe(false);
        expect(frameEl()).toBeNull();
        // 计时器清理：推进 15s 无残留 error（run 面板保持隐藏）
        vi.advanceTimersByTime(15000);
        expect(runPanel.hidden).toBe(true);
    });

    it('header 返回按钮 → closeSimulator（面板恢复）', async () => {
        const { view, listPanel, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel, runPanel });
        view.openSimulator(GAME_AI);

        runPanel.querySelector('.sim-run-back').click();
        expect(runPanel.hidden).toBe(true);
        expect(listPanel.hidden).toBe(false);
        expect(frameEl()).toBeNull();
    });

    it('open 中 close → 推进超时无残留错误（计时器已清理）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        view.closeSimulator();
        expect(runPanel.hidden).toBe(true);

        vi.advanceTimersByTime(15000);
        expect(runPanel.hidden).toBe(true);
        expect(runPanel.querySelector('.sim-run-error')).toBeNull();
    });

    it('Falsify:未 init 调 openSimulator / closeSimulator → no-op 不抛错', async () => {
        const { view } = await loadModules();
        expect(() => view.openSimulator(GAME_AI)).not.toThrow();
        expect(() => view.closeSimulator()).not.toThrow();
        expect(document.querySelector('#simulator-run-panel iframe')).toBeNull();
    });

    it('Falsify:initSimulatorRun 缺面板（null/缺失）→ no-op 不抛错', async () => {
        const { view } = await loadModules();
        expect(() => view.initSimulatorRun({})).not.toThrow();
        expect(() => view.initSimulatorRun({ listPanel: null, runPanel: null })).not.toThrow();
        expect(() => view.openSimulator(GAME_AI)).not.toThrow();
    });

    it('重复 initSimulatorRun（幂等）：仅更新引用，重复 open/close 行为正确', async () => {
        const { view, listPanel, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel, runPanel });
        view.initSimulatorRun({ listPanel, runPanel }); // 重复调用

        openAndLoad(view, GAME_AI);
        expect(frameEl()).not.toBeNull();
        view.closeSimulator();
        expect(runPanel.hidden).toBe(true);
        expect(listPanel.hidden).toBe(false);
        // 重复 init 后重新打开仍正常
        openAndLoad(view, GAME_AI);
        expect(frameEl()).not.toBeNull();
    });

    it('重复 open（opening 中再 open 另一游戏）→ 只留最新 iframe、计时器单一', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        view.openSimulator(GAME_LOCAL); // 未派发 load 直接换游戏

        const frames = runPanel.querySelectorAll('iframe');
        expect(frames).toHaveLength(1);
        expect(frames[0].getAttribute('src')).toBe('simulators/蛛网之影.html');
        // 旧计时器已清理：推进 15s 恰好一次 error（无重复/双计时器异常）
        vi.advanceTimersByTime(15000);
        expect(runPanel.querySelectorAll('.sim-run-error')).toHaveLength(1);
    });

    it('loaded 后再 open 另一游戏 → 重新 opening（旧 iframe 替换，无残留监听器）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        openAndLoad(view, GAME_AI);

        view.openSimulator(GAME_LOCAL);
        expect(runPanel.querySelector('.sim-run-status').textContent).toBe('加载中…');
        expect(runPanel.querySelectorAll('iframe')).toHaveLength(1);
        expect(frameEl().getAttribute('src')).toBe('simulators/蛛网之影.html');
    });

    it('Falsify:loaded 后重复派发 load（迟到事件）→ 守卫忽略，状态不变不抛错', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const frame = openAndLoad(view, GAME_AI);
        expect(frame.classList.contains('sim-run-frame-hidden')).toBe(false);

        expect(() => frame.dispatchEvent(new Event('load'))).not.toThrow();
        expect(frame.classList.contains('sim-run-frame-hidden')).toBe(false);
        expect(runPanel.querySelector('.sim-run-error')).toBeNull();
    });

    it('Falsify:游戏名含双引号（iframe title 属性注入面 — escapeHtml 不转义引号）→ title 经 setAttribute 赋值，无注入属性', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const evilName = 'X" onload="alert(1)';
        view.openSimulator({ file: 'x.html', name: evilName, type: 'ai' });

        const frame = frameEl();
        expect(frame.hasAttribute('onload')).toBe(false); // 无注入属性（旧实现：引号截断 + onload 成真属性）
        expect(frame.getAttribute('title')).toBe(evilName); // setAttribute 通道完整往返
    });

    it('Falsify:load 竞态 — 旧 iframe 销毁后迟到 load 事件不污染新游戏（超时守卫保留）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        const oldFrame = frameEl();
        view.openSimulator(GAME_LOCAL); // API 层替换（旧 iframe 已从 DOM 移除）
        expect(oldFrame.isConnected).toBe(false);

        // 迟到事件：旧元素监听仍在，向已销毁的旧 iframe 派发 load
        oldFrame.dispatchEvent(new Event('load'));

        // 新游戏不被污染：仍 opening（加载占位 + iframe 隐藏）
        expect(runPanel.querySelector('.sim-run-status').textContent).toBe('加载中…');
        const newFrame = frameEl();
        expect(newFrame.classList.contains('sim-run-frame-hidden')).toBe(true);
        // 新游戏超时守卫未被清除：推进 15s → error（若守卫被清则永不 load 时永久空白无兜底）
        vi.advanceTimersByTime(15000);
        expect(runPanel.querySelector('.sim-run-error')).not.toBeNull();
    });
});

describe('simulator-view — 配置同步按钮条与自动同步（U8-T2 + SIM-API-1）', () => {
    beforeEach(() => {
        vi.useFakeTimers();
        vi.restoreAllMocks();
        document.body.innerHTML = '';
    });
    afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

    /** 加载模块 + init 双面板 + initKeyInjector(mock) + open 游戏并派发 load。
     * seed 在派发 load 前调用 → 观察者挂到已就位的配置面板（模拟真实
     * load 时文档已解析）；不传 seed → load 时文档为空（auto-sync 全跳过）。 */
    async function openWithInject(view, game, credentials = CRED_OPENAI, seed = null) {
        const injector = await import('../js/key-injector.js');
        const fetchMock = vi.fn(async () => credentials);
        injector.initKeyInjector({ getCredentials: fetchMock });
        view.openSimulator(game);
        const frame = frameEl();
        const doc = seed ? seed(frame) : frame.contentDocument;
        frame.dispatchEvent(new Event('load'));
        return { injector, fetchMock, frame, doc };
    }

    /** 向 iframe contentDocument 写入游戏配置面板（同源直读 — U8 基线事实） */
    function seedGamePanel(frame, { endpointDefault = 'game-default-endpoint', modelDefault = 'game-default-model' } = {}) {
        const doc = frame.contentDocument;
        doc.open();
        doc.write(`<html><body>
            <input id="cfg-endpoint" value="${endpointDefault}">
            <input id="cfg-apikey">
            <select id="cfg-model">
                <option value="${modelDefault}">${modelDefault}</option>
                <option value="gpt-4o-mini">gpt-4o-mini</option>
            </select>
        </body></html>`);
        doc.close();
        return doc;
    }

    const keyBtn = () => document.querySelector('#simulator-run-panel .sim-key-btn');

    it('渲染条件：ai + 完整 config 三元组 → 按钮「重新同步」+ 提示条仍在 + msg 隐藏（无会话注记元素）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI_CONFIG);

        expect(runPanel.querySelector('.sim-run-hint').textContent).toBe('此游戏需自行配置 AI 接口');
        const btn = keyBtn();
        expect(btn).not.toBeNull();
        expect(btn.textContent).toBe('重新同步');
        expect(btn.disabled).toBe(false);
        const msg = runPanel.querySelector('.sim-key-msg');
        expect(msg.hidden).toBe(true);
        // SIM-API-1：会话注记已退役（自动同步每次 load 重放，无需「重进需再次点击」提示）
        expect(runPanel.querySelector('.sim-key-note')).toBeNull();
    });

    it('渲染条件：local 游戏 → 无按钮（无 config 的 ai 游戏提示条维持现状 — 按钮不渲染）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });

        view.openSimulator(GAME_LOCAL);
        expect(runPanel.querySelector('.sim-run-hint')).toBeNull();
        expect(keyBtn()).toBeNull();

        // ai 但无 config 字段 → 提示条在、按钮不渲染
        view.openSimulator(GAME_AI);
        expect(runPanel.querySelector('.sim-run-hint')).not.toBeNull();
        expect(keyBtn()).toBeNull();
    });

    it('渲染条件：config 三元组不完整（缺 model）→ 无按钮', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator({ ...GAME_AI, config: { endpoint: 'e', apikey: 'k' } });

        expect(runPanel.querySelector('.sim-run-hint')).not.toBeNull();
        expect(keyBtn()).toBeNull();
    });

    it('SIM-API-1:load 自动同步（openai）→ 面板已填值、无「已填入」反馈、按钮保持可点', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0); // 冲刷自动同步微任务

        expect(fetchMock).toHaveBeenCalledTimes(1); // load 自动同步一次凭证获取
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        // endpointMode=full：endpoint 注入为 base + /chat/completions
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1/chat/completions');
        expect(doc.getElementById('cfg-model').value).toBe('gpt-4o-mini');
        const btn = keyBtn();
        expect(btn.textContent).toBe('重新同步'); // 静默：无「已填入」反馈
        expect(btn.disabled).toBe(false);
        expect(runPanel.querySelector('.sim-key-msg').hidden).toBe(true);
    });

    it('SIM-API-1:load 自动同步（model 不在选项集）→ 受管 option 追加并选中', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { doc } = await openWithInject(
            view,
            GAME_AI_CONFIG,
            { ...CRED_OPENAI, model: 'smoke-test-model' }, // 不在 life-sim 选项集（deepseek 两选项）
            seedGamePanel,
        );
        await vi.advanceTimersByTimeAsync(0);

        const modelEl = doc.getElementById('cfg-model');
        expect(modelEl.value).toBe('smoke-test-model');
        expect([...modelEl.options].map((o) => o.value)).toContain('smoke-test-model');
        expect(modelEl.options.length).toBe(3); // 原 2 + 受管 1
    });

    it('SIM-API-1:load 自动同步（claude）→ 按钮自动禁用 + 文案「游戏仅支持 OpenAI 兼容 Key」、游戏不被注入', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { doc } = await openWithInject(
            view,
            GAME_AI_CONFIG,
            { key: '', endpoint: '', model: '', protocol: 'claude' },
            seedGamePanel,
        );
        await vi.advanceTimersByTimeAsync(0);

        expect(keyBtn().disabled).toBe(true);
        expect(runPanel.querySelector('.sim-key-msg').hidden).toBe(false);
        expect(runPanel.querySelector('.sim-key-msg').textContent).toContain('游戏仅支持 OpenAI 兼容 Key');
        expect(doc.getElementById('cfg-apikey').value).toBe(''); // claude key 绝不进入游戏
    });

    it('SIM-API-1:load 自动同步（none）→ 按钮自动禁用 + 「未配置 OpenAI 兼容 Key」含设置链接', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        await openWithInject(
            view,
            GAME_AI_CONFIG,
            { key: '', endpoint: '', model: '', protocol: 'none' },
            seedGamePanel,
        );
        await vi.advanceTimersByTimeAsync(0);

        expect(keyBtn().disabled).toBe(true);
        const msg = runPanel.querySelector('.sim-key-msg');
        expect(msg.hidden).toBe(false);
        expect(msg.textContent).toContain('未配置 OpenAI 兼容 Key');
        expect(msg.querySelector('.sim-key-nav-settings')).not.toBeNull();
    });

    it('SIM-API-1:load 自动同步（凭证获取失败）→ 静默：按钮保持可点、无禁用文案', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        // 自始拒绝的凭证 mock（load 自动同步即走失败路径）
        const injector = await import('../js/key-injector.js');
        injector.initKeyInjector({ getCredentials: vi.fn(async () => { throw new Error('网络错误'); }) });
        view.openSimulator(GAME_AI_CONFIG);
        const frame = frameEl();
        seedGamePanel(frame);
        frame.dispatchEvent(new Event('load'));
        await vi.advanceTimersByTimeAsync(0);

        expect(keyBtn().disabled).toBe(false);
        expect(keyBtn().textContent).toBe('重新同步');
        expect(runPanel.querySelector('.sim-key-msg').hidden).toBe(true);
    });

    it('点击接线（seed 在 load 后 — auto-sync 空文档全跳过）：凭证获取 → 注入面板（值 + input/change 事件）→ 「已填入」→ 2s 后恢复', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, frame } = await openWithInject(view, GAME_AI_CONFIG); // 不 seed → load 时空文档
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1); // load 自动同步已发一次请求（全跳过）

        const doc = seedGamePanel(frame);
        const seen = [];
        doc.getElementById('cfg-apikey').addEventListener('input', () => seen.push('input'));
        doc.getElementById('cfg-apikey').addEventListener('change', () => seen.push('change'));

        keyBtn().click();
        await vi.advanceTimersByTimeAsync(0);

        expect(fetchMock).toHaveBeenCalledTimes(2); // 自动同步 1 + 点击 1
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1/chat/completions'); // endpointMode=full 转换
        expect(doc.getElementById('cfg-model').value).toBe('gpt-4o-mini');
        expect(seen).toEqual(['input', 'change']);
        expect(keyBtn().textContent).toBe('已填入');
        expect(keyBtn().disabled).toBe(true);

        await vi.advanceTimersByTimeAsync(2000);
        expect(keyBtn().textContent).toBe('重新同步');
        expect(keyBtn().disabled).toBe(false);
    });

    it('endpoint/model 凭证为空 → 注入不覆盖游戏默认（仅 key 写入）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { frame } = await openWithInject(view, GAME_AI_CONFIG, { ...CRED_OPENAI, endpoint: '', model: '' });
        await vi.advanceTimersByTimeAsync(0);
        const doc = seedGamePanel(frame);

        keyBtn().click();
        await vi.advanceTimersByTimeAsync(0);

        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
        expect(doc.getElementById('cfg-endpoint').value).toBe('game-default-endpoint');
        expect(doc.getElementById('cfg-model').value).toBe('game-default-model');
        expect(keyBtn().textContent).toBe('已填入');
    });

    it('请求失败（凭证端点不可达）→ 静默降级：无弹窗不抛错、按钮恢复可点', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock } = await openWithInject(view, GAME_AI_CONFIG);
        await vi.advanceTimersByTimeAsync(0);
        fetchMock.mockRejectedValue(new Error('网络错误'));

        expect(() => keyBtn().click()).not.toThrow();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();

        expect(keyBtn().disabled).toBe(false);
        expect(keyBtn().textContent).toBe('重新同步');
        expect(runPanel.querySelector('.sim-key-msg').hidden).toBe(true);
    });

    it('控件缺失（iframe 文档无 config 控件）→ 静默降级：按钮恢复可点、无「已填入」', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { frame } = await openWithInject(view, GAME_AI_CONFIG);
        await vi.advanceTimersByTimeAsync(0);
        const doc = frame.contentDocument;
        doc.open();
        doc.write('<html><body><div id="cfg-apikey"></div></body></html>');
        doc.close();

        keyBtn().click();
        await vi.advanceTimersByTimeAsync(0);

        expect(keyBtn().disabled).toBe(false);
        expect(keyBtn().textContent).toBe('重新同步');
        expect(runPanel.querySelector('.sim-key-msg').hidden).toBe(true);
    });

    it('Falsify:重复点击（凭证获取挂起中）→ 只发一次请求', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, frame } = await openWithInject(view, GAME_AI_CONFIG);
        await vi.advanceTimersByTimeAsync(0);
        seedGamePanel(frame); // 注入目标面板就位
        let resolveFetch;
        // 自动同步已消费首调用 → 点击路径从第二次调用起挂起
        fetchMock.mockImplementationOnce(() => new Promise((r) => { resolveFetch = r; }));

        keyBtn().click();
        keyBtn().click();
        keyBtn().click();
        expect(fetchMock).toHaveBeenCalledTimes(2); // 自动同步 1 + 首个点击 1（后两个在途守卫拦截）

        resolveFetch(CRED_OPENAI);
        await vi.advanceTimersByTimeAsync(0);
        expect(keyBtn().textContent).toBe('已填入');
    });

    it('Falsify:iframe 尚未加载（contentDocument 为空文档）→ 点击静默降级不抛错', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        await openWithInject(view, GAME_AI_CONFIG); // open 后未 seed 面板（模拟 iframe 未加载）
        await vi.advanceTimersByTimeAsync(0);
        frameEl().contentDocument.open();
        frameEl().contentDocument.close(); // 空文档 — 无 config 控件

        expect(() => keyBtn().click()).not.toThrow();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();
        expect(keyBtn().disabled).toBe(false);
        expect(keyBtn().textContent).toBe('重新同步');
    });

    it('Falsify:未 initKeyInjector（app.js 未接线）→ 点击不抛错、按钮静默恢复、无误导性禁用文案', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI_CONFIG); // 不 init injector
        const frame = frameEl();
        frame.dispatchEvent(new Event('load'));
        await vi.advanceTimersByTimeAsync(0); // load 自动同步：未初始化 → bar 保持现状

        expect(keyBtn().disabled).toBe(false);
        expect(runPanel.querySelector('.sim-key-msg').hidden).toBe(true);

        expect(() => keyBtn().click()).not.toThrow();
        await expect(vi.advanceTimersByTimeAsync(0)).resolves.not.toThrow();
        expect(keyBtn().disabled).toBe(false);
    });

    it('SIM-API-1 观察者:游戏重建配置面板（控件恢复默认值）→ 防抖后自动再同步', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai'); // load 自动同步已填
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 越过写回环冷却（load 自动同步写入后 1s 内的重建属自写入反应，跳过）
        await vi.advanceTimersByTimeAsync(1000);
        // 游戏重建配置面板（innerHTML 替换 — 控件恢复默认值）
        doc.body.innerHTML = `
            <input id="cfg-endpoint" value="game-default-endpoint">
            <input id="cfg-apikey">
            <select id="cfg-model">
                <option value="game-default-model">game-default-model</option>
            </select>
        `;
        await vi.advanceTimersByTimeAsync(500); // 观察者防抖到期
        await vi.advanceTimersByTimeAsync(0); // 再同步微任务

        expect(fetchMock).toHaveBeenCalledTimes(2); // 重建触发再同步
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai'); // 主应用配置重新生效
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1/chat/completions');
    });

    it('SIM-API-1 观察者:写回环冷却 — 自动同步写入后 1s 内的面板重建跳过再同步；冷却后再重建恢复', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 冷却窗口内（未推进时间）：重建面板 → 观察者跳过（自写入反应）
        doc.body.innerHTML = `
            <input id="cfg-apikey">
            <input id="cfg-endpoint">
            <select id="cfg-model"><option value="game-default-model">game-default-model</option></select>
        `;
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetchMock).toHaveBeenCalledTimes(1); // 冷却内重建未触发再同步

        // 冷却已过：再次重建 → 防抖后自动再同步
        doc.body.innerHTML = `
            <input id="cfg-apikey">
            <input id="cfg-endpoint">
            <select id="cfg-model"><option value="game-default-model">game-default-model</option></select>
        `;
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(2);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
    });

    it('SIM-API-1 观察者:与配置控件无关的变更（游戏状态渲染）→ 不触发再同步', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        await vi.advanceTimersByTimeAsync(1000);
        // 游戏运行期高频 DOM 更新（状态渲染 — 不触及 config 控件）
        doc.body.insertAdjacentHTML('beforeend', '<div class="game-ui">第 3 天 · 体力 78</div>');
        await vi.advanceTimersByTimeAsync(2000);

        expect(fetchMock).toHaveBeenCalledTimes(1); // 未触发再同步
    });

    it('SIM-API-1 观察者:closeSimulator → 观察者断开（关闭后游戏文档变更不再触发）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        view.closeSimulator(); // 卸载 iframe → 观察者 disconnect
        await vi.advanceTimersByTimeAsync(1000);
        // 对已卸载的游戏文档做配置控件变更（引用仍在 — 观察者已断开不响应）
        doc.body.innerHTML = `
            <input id="cfg-apikey">
            <input id="cfg-endpoint">
            <select id="cfg-model"><option value="game-default-model">game-default-model</option></select>
        `;
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetchMock).toHaveBeenCalledTimes(1); // 断开后不触发
    });

    it('TD-75:游戏以属性变更（setAttribute(value)）重建配置控件 → 防抖后自动再同步', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai'); // load 自动同步已填
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 越过写回环冷却（load 自动同步写入后 1s 内的重建属自写入反应，跳过）
        await vi.advanceTimersByTimeAsync(1000);
        // 游戏以属性变更重建配置控件（value attribute 重置为默认 — 无 DOM 结构变更，
        // childList 观察不到；ADR-0001「重建配置控件后重新同步」承诺的窄缺口）
        doc.getElementById('cfg-apikey').setAttribute('value', '');
        doc.getElementById('cfg-endpoint').setAttribute('value', 'game-default-endpoint');
        doc.getElementById('cfg-model').setAttribute('value', 'game-default-model');
        await vi.advanceTimersByTimeAsync(500); // 观察者防抖到期
        await vi.advanceTimersByTimeAsync(0); // 再同步微任务

        expect(fetchMock).toHaveBeenCalledTimes(2); // 属性变更重建触发再同步
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai'); // 主应用配置重新生效
        expect(doc.getElementById('cfg-endpoint').value).toBe('https://api.example.com/v1/chat/completions');
    });

    it('TD-75:与配置控件无关的属性变更（class/style — 游戏状态渲染）→ 不触发再同步', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 游戏状态元素（非配置控件 — id 不在三元组）运行期高频属性变更
        const statusEl = doc.createElement('div');
        statusEl.className = 'game-ui';
        doc.body.appendChild(statusEl);
        await vi.advanceTimersByTimeAsync(1000);
        statusEl.setAttribute('class', 'game-ui game-day-3');
        statusEl.setAttribute('style', 'color: red');
        await vi.advanceTimersByTimeAsync(2000);

        expect(fetchMock).toHaveBeenCalledTimes(1); // 无关属性变更不触发再同步
    });

    /** 游戏重建配置面板（innerHTML 替换 — 控件恢复默认值；病理循环重置动作） */
    function rebuildPanel(doc) {
        doc.body.innerHTML = `
            <input id="cfg-endpoint" value="game-default-endpoint">
            <input id="cfg-apikey">
            <select id="cfg-model"><option value="game-default-model">game-default-model</option></select>
        `;
    }

    it('TD-76:病理循环（每次同步后重建+恢复默认，重建都在冷却窗外）→ 第 3 次观察者同步后熔断，后续重建不再 fetch', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1); // load 自动同步（非观察者路径 — 不计数）

        // 显式 3 轮钉住熔断层：每轮越过冷却 → 重建（恢复默认值）→ 防抖 → 同步写入 → strike+1
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000); // 越过写回环冷却（重建落在冷却窗外）
            rebuildPanel(doc);
            await vi.advanceTimersByTimeAsync(500); // 观察者防抖
            await vi.advanceTimersByTimeAsync(0); // 再同步微任务
        }
        expect(fetchMock).toHaveBeenCalledTimes(4); // load 1 + 观察者同步 3（第 3 次后熔断）

        // 熔断后：游戏继续重建 → 不再触发再同步（fetch 数封顶）
        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(2000);
        expect(fetchMock).toHaveBeenCalledTimes(4); // 熔断后重建不再 fetch
    });

    it('TD-76:正常场景（单次重建同步后不再重建）→ 不熔断，后续再次重建仍能再同步', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 单次重建 → 再同步写入（strike=1）→ 游戏不再重建（正常收敛）
        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(2);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');

        // 稍后游戏再次重建（strike=2 < 3）→ 仍能再同步，未熔断
        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(3); // 未熔断 — 观察者仍响应
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
    });

    it('TD-76:熔断后点击「重新同步」按钮仍可注入（手动路径与观察者熔断无关）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);

        // 病理循环 3 轮 → 观察者熔断（fetch = load 1 + 观察者 3）
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            rebuildPanel(doc);
            await vi.advanceTimersByTimeAsync(500);
            await vi.advanceTimersByTimeAsync(0);
        }
        expect(fetchMock).toHaveBeenCalledTimes(4);

        // 熔断后手动「重新同步」仍可注入（按钮路径不经过观察者）
        keyBtn().click();
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(5); // 手动路径可用
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai'); // 值恢复
    });

    it('TD-76:熔断后 closeSimulator → 重开游戏（新 load）→ 观察者重新挂载、自动同步恢复', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);

        // 病理循环 3 轮 → 观察者熔断
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            rebuildPanel(doc);
            await vi.advanceTimersByTimeAsync(500);
            await vi.advanceTimersByTimeAsync(0);
        }
        expect(fetchMock).toHaveBeenCalledTimes(4);

        // 关闭并重开游戏（新 iframe + 新文档）→ 熔断计数复位、观察者重新挂载；
        // openWithInject 重新 initKeyInjector（新凭证 mock 独立计数 — 旧 mock
        // 停在熔断时的 4 次）
        view.closeSimulator();
        const { fetchMock: fetchMockNew, frame } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMockNew).toHaveBeenCalledTimes(1); // 新 load 自动同步

        // 新游戏重建面板 → 观察者恢复工作（自动再同步）
        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(frame.contentDocument);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMockNew).toHaveBeenCalledTimes(2); // 观察者重新挂载后恢复再同步
        expect(frame.contentDocument.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
    });

    it('期末 F1:配置控件自身 class 属性翻转（attributeFilter 外属性）→ 不触发同步、不熔断', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 配置控件自身的良性属性翻转（class — attributeFilter 外）连续 3 次
        // （间隔越过冷却）→ 不触发同步（fetch 不增）、strike 不累积 → 不熔断
        const apikeyEl = doc.getElementById('cfg-apikey');
        for (let i = 0; i < 3; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            apikeyEl.setAttribute('class', `state-${i}`);
            await vi.advanceTimersByTimeAsync(2000);
        }
        expect(fetchMock).toHaveBeenCalledTimes(1); // 属性翻转从未触发同步

        // 熔断未发生：随后真实重建（恢复默认值）仍能再同步
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(2); // 观察者仍响应 — 未误熔断
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
    });

    it('期末 F2:重建后控件保持目标值（同步幂等匹配）→ 多次重建不累计熔断计数', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { fetchMock, doc } = await openWithInject(view, GAME_AI_CONFIG, CRED_OPENAI, seedGamePanel);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 游戏重建面板但控件值已保持主应用配置（重建不重置值 — select 经
        // option selected 属性保持选中态）→ 同步幂等匹配（written 为空）→
        // 熔断计数不累计；连续 5 次重建后观察者仍响应
        for (let i = 0; i < 5; i++) {
            await vi.advanceTimersByTimeAsync(1000);
            doc.body.innerHTML = `
                <input id="cfg-endpoint" value="https://api.example.com/v1/chat/completions">
                <input id="cfg-apikey" value="sk-smoke-openai">
                <select id="cfg-model">
                    <option value="game-default-model">game-default-model</option>
                    <option value="gpt-4o-mini" selected>gpt-4o-mini</option>
                </select>
            `;
            await vi.advanceTimersByTimeAsync(500);
            await vi.advanceTimersByTimeAsync(0);
        }
        expect(fetchMock).toHaveBeenCalledTimes(6); // load 1 + 观察者同步 5（幂等匹配 — 未熔断）

        // 仍能响应真实重建（游戏重置值 → 真写入 → 同步生效）
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(7);
        expect(doc.getElementById('cfg-apikey').value).toBe('sk-smoke-openai');
    });

    it('期末 F3:load 注入追加受管 option（自写 mutation）→ 冷却判定移位生效，无幽灵再同步', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        // seed 面板 model select 不含凭证 model → load 注入会追加受管 option
        // （自写 mutation — 注入续体置冷却晚于该 mutation 的观察者回调）
        const { fetchMock, doc } = await openWithInject(
            view,
            GAME_AI_CONFIG,
            { ...CRED_OPENAI, model: 'smoke-test-model' },
            (frame) => seedGamePanel(frame, { modelDefault: 'game-default-model' }),
        );
        await vi.advanceTimersByTimeAsync(0); // load 自动同步 + 自写 mutation 回调
        expect(fetchMock).toHaveBeenCalledTimes(1); // 无幽灵再同步（冷却判定在防抖到期时已生效）
        expect(doc.getElementById('cfg-model').value).toBe('smoke-test-model'); // 受管 option 已注入

        // 冷却窗内自写 mutation 的防抖到期 → 跳过（不误刷新冷却压制后续真实重建）
        await vi.advanceTimersByTimeAsync(500);
        expect(fetchMock).toHaveBeenCalledTimes(1);

        // 冷却过后真实重建（控件恢复默认）→ 正常再同步
        await vi.advanceTimersByTimeAsync(1000);
        rebuildPanel(doc);
        await vi.advanceTimersByTimeAsync(500);
        await vi.advanceTimersByTimeAsync(0);
        expect(fetchMock).toHaveBeenCalledTimes(2);
    });
});

describe('simulator-view — PC 阅读覆盖层注入（方案 A / T2 — injectPcOverlay）', () => {
    beforeEach(() => { vi.useFakeTimers(); vi.restoreAllMocks(); });
    afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

    /** 覆盖层 link 选择器（与 js 内 PC_OVERLAY_HREF 常量契约对偶——T2 验收
     * 「href 在 js 中唯一出现」要求内部函数不可导出，测试只能持有字符串副本；
     * 改动 href 必须同步两处，simulator-pc-css.test.js 的契约锁已覆盖） */
    const OVERLAY_HREF = '../css/simulator-pc.css';
    const overlayLinks = (doc) => doc?.head?.querySelectorAll(`link[href="${OVERLAY_HREF}"]`) ?? [];

    /** open 游戏并把 iframe 文档种子化为带 <head> 的游戏文档，再派发 load */
    function openAndLoadSeeded(view, game = GAME_AI) {
        view.openSimulator(game);
        const frame = frameEl();
        const doc = frame.contentDocument;
        doc.open();
        doc.write('<html><head><title>game</title></head><body><div id="game-log"></div></body></html>');
        doc.close();
        frame.dispatchEvent(new Event('load'));
        return { frame, doc };
    }

    it('loaded 后 contentDocument.head 出现 link[href="../css/simulator-pc.css"]（rel=stylesheet，追加于 head 末尾）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { doc } = openAndLoadSeeded(view);

        const links = overlayLinks(doc);
        expect(links).toHaveLength(1);
        expect(links[0].rel).toBe('stylesheet');
        expect(links[0].getAttribute('href')).toBe('../css/simulator-pc.css');
        expect(doc.head.lastElementChild).toBe(links[0]); // 追加于 head 末尾 → 同特异性优先级最高
    });

    it('幂等：游戏文档已含同 href link → load 后不重复注入（querySelectorAll 长度 1）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        const frame = frameEl();
        const doc = frame.contentDocument;
        doc.open();
        doc.write('<html><head><link rel="stylesheet" href="../css/simulator-pc.css"></head><body></body></html>');
        doc.close();
        frame.dispatchEvent(new Event('load'));

        expect(overlayLinks(doc)).toHaveLength(1); // 已存在 → no-op，不重复
    });

    it('Falsify:contentDocument 为 null（destroyFrame 后迟到 load）→ 不抛错、无副作用', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        const frame = frameEl();
        vi.spyOn(frame, 'contentDocument', 'get').mockReturnValue(null);
        // 模拟器域事实：同源 iframe src 形如 simulators/<file>，load 与内容文档
        // 生命周期分离 — contentDocument 不可用时注入必须 no-op
        expect(() => frame.dispatchEvent(new Event('load'))).not.toThrow();
        expect(frame.classList.contains('sim-run-frame-hidden')).toBe(false); // loaded 态正常推进
    });

    it('Falsify:doc 存在但 head 缺失 → 不抛错、不注入', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        const frame = frameEl();
        const doc = frame.contentDocument;
        doc.open();
        doc.write('<html><body><div id="game-log"></div></body></html>');
        doc.close();
        doc.head?.remove(); // 强制 head 缺失（jsdom 下 head 为 live 派生）

        expect(() => frame.dispatchEvent(new Event('load'))).not.toThrow();
        expect(overlayLinks(doc)).toHaveLength(0);
    });

    it('opening 态（load 前）不注入；loaded 后才出现 link', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        view.openSimulator(GAME_AI);
        const frame = frameEl();

        // load 前（opening）：游戏文档无覆盖层 link
        expect(overlayLinks(frame.contentDocument)).toHaveLength(0);

        const doc = frame.contentDocument;
        doc.open();
        doc.write('<html><head><title>game</title></head><body></body></html>');
        doc.close();
        frame.dispatchEvent(new Event('load'));

        expect(overlayLinks(doc)).toHaveLength(1); // load 后才注入
    });

    it('Falsify:loaded 后重复派发 load → 状态守卫忽略，link 不重复（仍 1 个）', async () => {
        const { view, runPanel } = await loadModules();
        view.initSimulatorRun({ listPanel: runPanel.parentElement.querySelector('#simulator-list-panel'), runPanel });
        const { frame, doc } = openAndLoadSeeded(view);
        expect(overlayLinks(doc)).toHaveLength(1);

        expect(() => frame.dispatchEvent(new Event('load'))).not.toThrow();
        expect(overlayLinks(doc)).toHaveLength(1);
    });
});
