/**
 * 模拟器运行视图模块测试（U7-T4）。
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
});
