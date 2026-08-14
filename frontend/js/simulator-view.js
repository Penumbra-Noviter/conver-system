/**
 * Conver System — 模拟器运行视图（深模块，U7-T4 / U8-T2）
 *
 * 职责：运行视图的全部逻辑收口 —— iframe 状态机（idle → opening → loaded |
 *   error，含 15s 超时守卫）、AI 提示条（type === 'ai' 渲染固定文案 +
 *   U8-T2 起 ai 且 manifest 含完整 config 三元组时附「使用主应用 Key」
 *   按钮条）、「返回」回列表（卸载 iframe；游戏存档在游戏自身 localStorage
 *   前缀隔离保存，重进自动恢复，卸载不丢进度）。打开参数校验（非法 file →
 *   直接 error 态，不创建 iframe；file 含路径分隔符 → 拒绝 — iframe src
 *   注入守卫，src 永远形如 simulators/<file> 同源加载）。
 *
 * 依赖方向：simulator-view.js → icons.js（iconHtml）/ utils.js（escapeHtml，
 *   game.name 来自 manifest 第三方数据，header 渲染必须转义）/
 *   key-injector.js（U8-T2：attachKeyInject 挂按钮交互 + hasConfigTriplet
 *   三元组校验 + TEXT_KEY_INJECT 按钮文案 — 点击/注入逻辑收口在注入模块，
 *   凭证获取经 key-injector initKeyInjector 钩子由 app.js 接线）；
 *   app.js → simulator-view.js（initSimulatorRun 接线 + onOpenGame 接到
 *   openSimulator + 切走 simulators 视图时 closeSimulator 销毁 iframe —
 *   Grilling 共识：状态全在游戏自身 localStorage，避免后台游戏继续跑）。
 *
 * DOM 契约：两面板容器（#simulator-list-panel / #simulator-run-panel）来自
 *   index.html U7-T1 骨架，经 initSimulatorRun 注入绑定（未注入时 open/close
 *   no-op 不抛错）；运行面板内容全部由本模块渲染。面板显隐走 hidden 属性
 *   （style.css 对 #simulator-run-panel 设 display 时须补 [hidden] 覆盖 —
 *   见 T4 样式契约）。按钮条 DOM 契约（.sim-key-bar / .sim-key-btn /
 *   .sim-key-msg / .sim-key-note）与 key-injector.js attachKeyInject 对齐。
 *
 * wg_ 族会话注记（U8-T2 验收 4）：小马宝莉 / 高中生模拟器无保存按钮，
 *   注入仅会话内生效 — 成功注入后按钮旁显示「重进游戏需再次点击」小字。
 *   识别方式：spec 明示两游戏（manifest 无会话内标志字段），id 集合单一来源
 *   js/save-key-meta.js（WG_SESSION_ONLY_IDS，契约之家，TD-67/68；存档面板
 *   「仅会话内生效」注记同源消费，新增该族游戏只改契约之家一处）。
 *
 * 错误检测基线（spec Implementation Decisions）：同源 404 仍触发 load 事件，
 *   错误态主要依赖超时守卫（15s 未收到 load）+ 打开参数校验；iframe 元素
 *   无标准 error 事件（onerror 仅 img/script 类），不监听。
 *
 * 协议表面（__all__）：initSimulatorRun / openSimulator / closeSimulator。
 */

import { iconHtml } from './icons.js';
import { escapeHtml } from './utils.js';
import { attachKeyInject, hasConfigTriplet, TEXT_KEY_INJECT } from './key-injector.js';
import { WG_SESSION_ONLY_IDS } from './save-key-meta.js';

// ══════════════════════════════════════════════════
// 常量（UI 契约 — 文案/时长与 spec 对齐）
// ══════════════════════════════════════════════════

/** 模拟器静态目录（与列表模块 MANIFEST_URL 同源约定；T2 静态托管根挂载覆盖） */
const SIM_DIR = 'simulators';

/** 加载超时守卫时长（spec 建议 15s） */
const TIMEOUT_MS = 15000;

/** AI 游戏提示条固定文案（spec 逐字） */
const HINT_AI = '此游戏需自行配置 AI 接口';

/** wg_ 族会话注记文案（U8-T2 验收 4 — 注入仅会话内生效） */
const NOTE_SESSION_ONLY = '重进游戏需再次点击';

/** wg_ 族游戏 id 集合（spec 明示：小马宝莉 / 高中生模拟器；manifest 无
 *  会话内标志字段 — 集合单一来源 js/save-key-meta.js：WG_SESSION_ONLY_IDS，
 *  契约之家，TD-67/68；存档面板注记同源消费，见模块头 docstring） */

// ══════════════════════════════════════════════════
// 模块级状态（UI 实现细节 — 不属全局应用状态）
// ══════════════════════════════════════════════════

/** 列表面板容器（initSimulatorRun 注入；未 init 时为 null） */
let listPanel = null;

/** 运行面板容器（initSimulatorRun 注入；未 init 时为 null） */
let runPanel = null;

/** 状态机：idle | opening | loaded | error */
let state = 'idle';

/** 当前打开的游戏（错误态重试复用；close 后置 null） */
let currentGame = null;

/** 当前 iframe 元素（无则 null） */
let frame = null;

/** 超时守卫计时器（无在途超时守卫时为 null） */
let timeoutTimer = null;

// ══════════════════════════════════════════════════
// 内部工具
// ══════════════════════════════════════════════════

/** 清理超时守卫计时器（幂等） */
function clearTimer() {
    if (timeoutTimer !== null) {
        clearTimeout(timeoutTimer);
        timeoutTimer = null;
    }
}

/** 卸载 iframe 并清理计时器（幂等；close / 超时 / 重复 open 共用） */
function destroyFrame() {
    clearTimer();
    if (frame) {
        frame.remove();
        frame = null;
    }
}

/**
 * 打开参数校验：game 须为对象且 file 为非空字符串、不含路径分隔符
 * （iframe src 注入守卫 — file 来自 manifest 第三方数据，防御越界/外链）。
 * @param {unknown} game - openSimulator 入参
 * @returns {boolean}
 */
function isValidGame(game) {
    return game !== null && typeof game === 'object'
        && typeof game.file === 'string' && game.file !== ''
        && !game.file.includes('/') && !game.file.includes('\\');
}

/** 显示运行面板、隐藏列表面板 */
function showRunPanel() {
    runPanel.hidden = false;
    listPanel.hidden = true;
}

/** 显示列表面板、隐藏运行面板 */
function showListPanel() {
    runPanel.hidden = true;
    listPanel.hidden = false;
}

// ══════════════════════════════════════════════════
// 渲染（header 常驻 + body 三态：opening / loaded / error）
// ══════════════════════════════════════════════════

/**
 * 渲染运行视图骨架：header（返回按钮 + 游戏名（转义）+ AI 提示条 + 可选
 * 「使用主应用 Key」按钮条）+ body。ai 游戏且 manifest 含完整 config 三元组
 * 时渲染按钮条（U8-T2；三元组不完整视为无 config — 提示条维持现状）；wg_
 * 族游戏（无保存按钮）按钮条内含隐藏的会话注记元素（成功注入后显示）。
 * iframe 与加载占位一起渲染于 body；src 留待 openSimulator 绑定 load
 * 监听后设置（jsdom 不自动触发 load，测试手动派发）。
 * @param {object} game - 已通过参数校验的游戏条目
 */
function renderShell(game) {
    // 防御归一化：参数非法分支可能收到 null/非对象（error 态仍需 header 返回按钮）
    const g = game !== null && typeof game === 'object' ? game : {};
    const name = typeof g.name === 'string' ? g.name : '';
    const isAi = g.type === 'ai';
    const hint = isAi
        ? `<span class="sim-run-hint">${HINT_AI}</span>` : '';
    // 按钮条仅 ai + 完整 config 三元组渲染；会话注记仅 wg_ 族渲染（隐藏，注入成功后才显示）
    const keyBar = isAi && hasConfigTriplet(g.config)
        ? `<div class="sim-key-bar">
            <button type="button" class="sim-key-btn">${TEXT_KEY_INJECT}</button>
            <span class="sim-key-msg" role="status" hidden></span>
            ${WG_SESSION_ONLY_IDS.has(g.id) ? `<span class="sim-key-note" hidden>${NOTE_SESSION_ONLY}</span>` : ''}
        </div>`
        : '';
    runPanel.innerHTML = `
        <div class="sim-run-header">
            <button type="button" class="sim-run-back">${iconHtml('chevronLeft', { size: 14 })}<span>返回</span></button>
            <h3 class="sim-run-name">${escapeHtml(name)}</h3>
            ${hint}
            ${keyBar}
        </div>
        <div class="sim-run-body">
            <p class="sim-run-status">加载中…</p>
            <iframe class="sim-run-frame sim-run-frame-hidden"></iframe>
        </div>
    `;
    runPanel.querySelector('.sim-run-back').addEventListener('click', closeSimulator);
    // 按钮交互挂到 key-injector（点击/注入/反馈状态机收口在注入模块；
    // getDoc/getConfig 动态取 — iframe 异步加载，点击时再取当前值）
    const bar = runPanel.querySelector('.sim-key-bar');
    if (bar) {
        attachKeyInject({
            bar,
            sessionOnly: WG_SESSION_ONLY_IDS.has(g.id),
            getDoc: () => frame?.contentDocument ?? null,
            getConfig: () => currentGame?.config ?? null,
        });
    }
}

/**
 * 渲染 body 错误态：错误文案 + 原因 + 重试/返回按钮（重试复用当前游戏）。
 * @param {string} reason - 失败原因（超时 / 参数非法文案）
 */
function renderError(reason) {
    runPanel.querySelector('.sim-run-body').innerHTML = `
        <div class="sim-run-error">
            <p class="sim-run-error-msg">游戏加载失败</p>
            <p class="sim-run-error-reason">${escapeHtml(reason)}</p>
            <div class="sim-run-error-actions">
                <button type="button" class="sim-retry-btn" data-action="retry">重试</button>
                <button type="button" class="btn-secondary" data-action="back">返回</button>
            </div>
        </div>
    `;
    runPanel.querySelector('[data-action="retry"]').addEventListener('click', () => {
        openSimulator(currentGame);
    });
    runPanel.querySelector('[data-action="back"]').addEventListener('click', closeSimulator);
}

// ══════════════════════════════════════════════════
// 状态机迁移
// ══════════════════════════════════════════════════

/** iframe load 事件 → loaded（清计时器、显示 iframe、移除加载占位） */
function handleLoad(e) {
    if (state !== 'opening') return; // 兜底：close/超时后迟到的 load 忽略
    // 事件源校验（load 竞态守卫）：旧 iframe 销毁后其监听仍在，向旧元素派发
    // 的迟到 load 会误清新游戏超时守卫 + 提前显示新 iframe（新游戏永不 load
    // 则永久空白无兜底）— 仅接受当前 frame 自身的事件
    if (e?.target !== frame) return;
    clearTimer();
    state = 'loaded';
    if (frame) frame.classList.remove('sim-run-frame-hidden');
    runPanel.querySelector('.sim-run-status')?.remove();
}

/** 超时守卫到期（15s 未收到 load）→ error（卸载 iframe，展示重试/返回） */
function handleTimeout() {
    if (state !== 'opening') return; // 兜底：已 loaded/closed 的残留计时器忽略
    state = 'error';
    destroyFrame();
    renderError('加载超时（15 秒未收到响应）');
}

/** 进入 opening：渲染骨架（含新 iframe）→ 绑定 load → 设 src/title → 起超时守卫 */
function startOpening(game) {
    destroyFrame(); // 重复 open：清理旧 iframe 与旧计时器（含残留 load 监听）
    state = 'opening';
    currentGame = game;
    renderShell(game);
    frame = runPanel.querySelector('.sim-run-frame');
    frame.addEventListener('load', handleLoad);
    // title 经 setAttribute 赋值（数据通道单一化纪律 — 属性值不嵌 HTML 字符串：
    // escapeHtml 文本序列化不转义引号，字符串拼接 title 存在属性注入面；先例同
    // simulators.js data-id dataset 通道）
    frame.setAttribute('title', typeof game.name === 'string' ? game.name : '');
    frame.setAttribute('src', `${SIM_DIR}/${game.file}`);
    timeoutTimer = setTimeout(handleTimeout, TIMEOUT_MS);
}

// ══════════════════════════════════════════════════
// 对外入口
// ══════════════════════════════════════════════════

/**
 * 初始化运行视图：绑定列表/运行两面板容器引用。
 *
 * 幂等：重复调用仅更新面板引用（事件/计时器均挂在渲染产物上，随渲染
 * 重建，无重复绑定）。面板缺失（index.html 契约被破坏的极端场景）→
 * no-op 不抛错；未 init 时 openSimulator / closeSimulator 均 no-op。
 * @param {object} [options]
 * @param {HTMLElement} [options.listPanel] - 列表面板（#simulator-list-panel）
 * @param {HTMLElement} [options.runPanel] - 运行面板（#simulator-run-panel）
 */
export function initSimulatorRun({ listPanel: lp, runPanel: rp } = {}) {
    if (!lp || !rp) return;
    listPanel = lp;
    runPanel = rp;
}

/**
 * 打开模拟器运行视图（状态机进入：idle → opening → loaded | error）。
 *
 * 参数非法（非对象 / file 缺失、空串、非字符串、含路径分隔符）→ 直接
 * error 态，不创建 iframe；合法 → 隐藏列表面板、显示运行面板、渲染
 * AI 提示条（type === 'ai'），创建 iframe（src = simulators/<file>，
 * 同源）并启动 15s 超时守卫；iframe load 事件 → loaded。
 * opening 中重复 open → 替换为最新游戏（旧 iframe/计时器清理）。
 * @param {object} game - 游戏条目（列表模块 parseManifest 归一化产物；
 *   至少需要 file，type 用于 AI 提示条）
 */
export function openSimulator(game) {
    if (!runPanel || !listPanel) return; // 未 init 守卫
    showRunPanel();
    if (!isValidGame(game)) {
        state = 'error';
        currentGame = game;
        renderShell(game);
        renderError('参数非法：缺少有效的游戏文件');
        return;
    }
    startOpening(game);
}

/**
 * 关闭运行视图，返回列表：卸载 iframe（清理超时守卫）、隐藏运行面板、
 * 显示列表面板。游戏存档在游戏自身 localStorage（前缀隔离），卸载不丢
 * 进度，重进自动恢复。idle / 未 init 时 no-op 不抛错。
 */
export function closeSimulator() {
    if (!runPanel || !listPanel) return;
    if (state === 'idle') return;
    destroyFrame();
    state = 'idle';
    currentGame = null;
    runPanel.innerHTML = '';
    showListPanel();
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 simulator-view.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'initSimulatorRun',
    'openSimulator',
    'closeSimulator',
];
