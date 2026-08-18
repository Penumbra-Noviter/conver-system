/**
 * Conver System — 模拟器运行视图（深模块，U7-T4 / U8-T2 / SIM-API-1）
 *
 * 职责：运行视图的全部逻辑收口 —— iframe 状态机（idle → opening → loaded |
 *   error，含 15s 超时守卫）、AI 提示条（type === 'ai' 渲染固定文案 +
 *   ai 且 manifest 含完整 config 三元组时附「重新同步」按钮条）、
 *   PC 阅读覆盖层注入（方案 A — iframe load 后把 frontend/css/
 *   simulator-pc.css 以 link 追加到游戏文档 head 末尾，幂等空安全，
 *   零改动 22 个游戏 HTML）、
 *   SIM-API-1 配置持续同步（iframe load 后自动同步主应用凭证/端点/模型 +
 *   MutationObserver 监听配置控件动态重建后再同步 — 冷却/熔断状态迁移收口
 *   在 key-injector 单一状态机，本模块只保留触发时机（load / 防抖到期）与
 *   观察者生命周期（挂载 / disconnect / destroyFrame 复位））、「返回」回列表
 *   （卸载 iframe；游戏存档在游戏自身 localStorage 前缀隔离保存，重进自动
 *   恢复，卸载不丢进度）。打开参数校验（非法 file → 直接 error 态，不创建
 *   iframe；file 含路径分隔符 → 拒绝 — iframe src 注入守卫，src 永远形如
 *   simulators/<file> 同源加载）。
 *
 * 依赖方向：simulator-view.js → icons.js（iconHtml）/ utils.js（escapeHtml，
 *   game.name 来自 manifest 第三方数据，header 渲染必须转义）/
 *   simulator-contracts.js（C8 契约深模块：SIM_DIR 静态目录 / TIMEOUT_MS
 *   超时毫秒 / isValidSimulatorFile file 判据 — 模拟器域事实单一来源，
 *   本视图不持副本）/
 *   key-injector.js（U8-T2/SIM-API-1：attachKeyInject 挂按钮交互 +
 *   autoSyncIntoGame 自动同步编排 + hasConfigTriplet 三元组校验 +
 *   resetSyncLoop 写回环复位 + TEXT_RESYNC 按钮文案 — 同步/注入逻辑收口
 *   在 key-injector.js，凭证获取经 initKeyInjector 钩子由 app.js 接线；
 *   本模块只负责触发时机与观察者）；
 *   app.js → simulator-view.js（initSimulatorRun 接线 + onOpenGame 接到
 *   openSimulator + 切走 simulators 视图时 closeSimulator 销毁 iframe —
 *   Grilling 共识：状态全在游戏自身 localStorage，避免后台游戏继续跑）。
 *
 * DOM 契约：两面板容器（#simulator-list-panel / #simulator-run-panel）来自
 *   index.html U7-T1 骨架，经 initSimulatorRun 注入绑定（未注入时 open/close
 *   no-op 不抛错）；运行面板内容全部由本模块渲染。面板显隐走 hidden 属性
 *   （style.css 对 #simulator-run-panel 设 display 时须补 [hidden] 覆盖 —
 *   见 T4 样式契约）。按钮条 DOM 契约（.sim-key-bar / .sim-key-btn /
 *   .sim-key-msg）与 key-injector.js attachKeyInject 对齐。
 *
 * 持续同步观察者（SIM-API-1 — ADR-0001 方案 2「用户或游戏重建配置控件后
 *   重新同步，主应用设置保持唯一事实来源」）：iframe load 进入 loaded 后对
 *   contentDocument.body 挂 MutationObserver（childList + subtree +
 *   attributes；childList 覆盖结构重建（innerHTML 替换），attributes 覆盖
 *   属性重建（setAttribute 重置控件值 — TD-75：attributeFilter 收窄到票面
 *   目标属性 value/hidden，配置控件自身 class/disabled 等运行期翻转不触发
 *   （期末评审 F1 修复 — 防良性变更累积误熔断）；宿主注入走 property 赋值
 *   与事件派发，不产生 attribute mutation — 无自触发面）。
 *   只处理触及 config 三元组 id 的变更（id 命中 / 变更子树含控件 — 游戏
 *   运行期高频 DOM 更新不触发）；防抖 500ms 合并连续重建。写回环冷却/熔断
 *   状态迁移已收口到 key-injector 单一状态机（autoSyncIntoGame 原子完成
 *   「同步执行 + 冷却判定 + 置冷却 + 观察者计数 + 熔断判定」，返回值经
 *   cooled/breaker 信号传达；冷却仅真写入 written > 0 置位，熔断达阈值
 *   后返回 breaker: true）。本模块只保留触发时机（load/
 *   防抖到期）与观察者生命周期（挂载 / disconnect / destroyFrame 复位）。
 *   冷却判定在状态机函数调用时执行（防抖到期执行点）。
 *
 * 错误检测基线（spec Implementation Decisions）：同源 404 仍触发 load 事件，
 *   错误态主要依赖超时守卫（15s 未收到 load）+ 打开参数校验；iframe 元素
 *   无标准 error 事件（onerror 仅 img/script 类），不监听。
 *
 * 协议表面（__all__）：initSimulatorRun / openSimulator / closeSimulator。
 */

import { iconHtml } from './icons.js';
import { escapeHtml } from './utils.js';
import { attachKeyInject, hasConfigTriplet, autoSyncIntoGame, resetSyncLoop, TEXT_RESYNC } from './key-injector.js';
import { SIM_DIR, TIMEOUT_MS, isValidSimulatorFile } from './simulator-contracts.js';

// ══════════════════════════════════════════════════
// 常量（UI 契约 — 文案/时长与 spec 对齐）
// ══════════════════════════════════════════════════
// 模拟器域事实常量（SIM_DIR 静态目录 / TIMEOUT_MS 超时毫秒 / isValidSimulatorFile
// file 判据）单一来源为 js/simulator-contracts.js（C8 契约深模块）—— 本视图不持
// 副本，改目录 / 超时只改契约模块；iframe 超时文案秒数由共享 TIMEOUT_MS 派生。

/** AI 游戏提示条固定文案（spec 逐字） */
const HINT_AI = '此游戏需自行配置 AI 接口';

/** 配置控件重建观察者防抖时长（毫秒；连续重建合并为一次同步） */
const OBSERVER_DEBOUNCE_MS = 500;

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

/** 配置控件重建观察者（loaded 后挂游戏文档；destroyFrame 时 disconnect） */
let configObserver = null;

/** 观察者防抖计时器（无在途防抖时为 null） */
let observerTimer = null;

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
    disconnectObserver();
    resetSyncLoop(); // 复位写回环状态机（冷却+熔断清零；跨游戏不残留 — 熔断计数复位唯一触发点）
    if (frame) {
        frame.remove();
        frame = null;
    }
}

// ══════════════════════════════════════════════════
// PC 阅读覆盖层注入（方案 A — T1 共享覆盖层 simulator-pc.css）
// ══════════════════════════════════════════════════

/** PC 阅读覆盖层样式表 href（静态相对路径常量 — 相对 simulators/<file>.html
 *  → frontend/css/；注入 href 单点，不拼接任何外部输入 — 无注入面） */
const PC_OVERLAY_HREF = '../css/simulator-pc.css';

/**
 * 向游戏文档注入 PC 阅读覆盖层（方案 A — T1 共享覆盖层）。
 * iframe load 后把 <link rel="stylesheet"> 追加到游戏文档 <head> 末尾
 * （同特异性下优先级最高，覆盖游戏内联样式；游戏独立打开不受影响 —
 * 零改动 22 个游戏 HTML）。href 为 PC_OVERLAY_HREF 常量（注入 href
 * 单点，见上）。
 * 幂等：head 已含同 href link → no-op；doc?.head 不可用（jsdom 空文档 /
 * destroyFrame 后迟到 load）→ no-op 不抛错。href 为模块常量，无外部输入面。
 * @param {Document|null|undefined} doc - iframe contentDocument（可空）
 */
function injectPcOverlay(doc) {
    if (!doc?.head) return;
    if (doc.head.querySelector(`link[href="${PC_OVERLAY_HREF}"]`)) return;
    const link = doc.createElement('link');
    link.rel = 'stylesheet';
    link.href = PC_OVERLAY_HREF;
    doc.head.appendChild(link);
}

// ══════════════════════════════════════════════════
// 配置控件持续同步（SIM-API-1 — MutationObserver + 防抖 + 冷却）
// ══════════════════════════════════════════════════

/**
 * 断开配置控件观察者 + 清理防抖计时器（幂等；destroyFrame / 重新 observe /
 * closeSimulator 共用）。
 */
function disconnectObserver() {
    if (configObserver) {
        configObserver.disconnect();
        configObserver = null;
    }
    if (observerTimer) {
        clearTimeout(observerTimer);
        observerTimer = null;
    }
}

/**
 * 变更是否触及 config 三元组控件（SIM-API-1 观察者过滤 — 游戏运行期高频
 * DOM 更新（状态渲染等）不得触发同步；只有 id 命中或变更子树含控件才算）。
 * 语义：目标元素自身 id ∈ 三元组（childList 与 attributes 变更共用判定 —
 * 期末评审去重）；或 childList 新增/移除子树内任一元素 id ∈ 三元组（游戏
 * 整段重建配置面板时命中；子树元素遍历用 id 成员判定，无选择器转义面）。
 * attributes 变更（TD-75 — 游戏以 setAttribute 重建控件）仅目标元素自身
 * 判定；运行期无关属性变更（class/style 等）由 observe 的 attributeFilter
 * 先行拦截（期末评审 F1 修复 — 只监听 value/hidden 票面目标属性）。
 * @param {MutationRecord[]} mutations - MutationObserver 回调的变更记录
 * @param {object|null} config - manifest config 三元组（endpoint/apikey/model）
 * @returns {boolean} 任一变更触及配置控件为 true
 */
function mutationTouchesConfig(mutations, config) {
    const ids = [config?.endpoint, config?.apikey, config?.model]
        .filter((v) => typeof v === 'string' && v !== '');
    if (ids.length === 0) return false;
    for (const m of mutations ?? []) {
        if (typeof m?.target?.id === 'string' && ids.includes(m.target.id)) return true;
        if (m?.type === 'attributes') continue; // 属性变更仅目标自身判定（上）
        const nodes = [...(m?.addedNodes ?? [])];
        if (m?.removedNodes?.length) nodes.push(...m.removedNodes);
        for (const node of nodes) {
            if (node?.nodeType !== 1) continue;
            if (ids.includes(node.id)) return true;
            for (const el of node.querySelectorAll?.('*') ?? []) {
                if (ids.includes(el.id)) return true;
            }
        }
    }
    return false;
}

/**
 * 观察者回调：变更触及配置控件 → 防抖 500ms → 自动同步（观察者路径）。
 * 冷却/熔断判定已收口到 key-injector 状态机，本模块只消费返回值
 * breaker 信号决定观察者断连。
 * @param {MutationRecord[]} mutations - MutationObserver 回调的变更记录
 */
function handleConfigMutation(mutations) {
    if (state !== 'loaded' || !frame) return;
    if (!mutationTouchesConfig(mutations, currentGame?.config)) return;
    if (observerTimer) clearTimeout(observerTimer);
    observerTimer = setTimeout(async () => {
        observerTimer = null;
        if (state !== 'loaded' || !frame) return;
        const result = await autoSyncAfterLoad();
        // 熔断判定在状态机内完成，本模块仅消费 breaker 信号决定观察者生命周期
        if (result?.breaker === true) disconnectObserver(); // 熔断：断开观察者，终止自动再同步
    }, OBSERVER_DEBOUNCE_MS);
}

/**
 * 对 loaded 游戏文档挂配置控件观察者（幂等：先 disconnect 再挂）。
 * 仅 ai + 完整 config 三元组的游戏观察；contentDocument 不可用（测试
 * 空文档等）→ no-op 不抛错。
 */
function observeConfigControls() {
    disconnectObserver();
    if (state !== 'loaded' || !frame?.contentDocument) return;
    const game = currentGame;
    if (!game || game.type !== 'ai' || !hasConfigTriplet(game.config)) return;
    const doc = frame.contentDocument;
    if (!doc.body || typeof doc.body.addEventListener !== 'function') return;
    configObserver = new MutationObserver(handleConfigMutation);
    // TD-75：childList（结构重建）+ attributes（setAttribute 重建 — 属性变更
    // 路径）。写回环安全前提：宿主注入用 property 赋值（el.value = value）
    // 与事件派发，不产生 attribute mutation — attributes 监听不新增自触发
    // 面；attributeFilter 收窄到票面目标属性（value/hidden，期末评审 F1
    // 修复 — 配置控件自身 class/disabled 等运行期翻转不触发同步，防良性
    // 变更累积误熔断）；mutationTouchesConfig 的 id 过滤兜底
    configObserver.observe(doc.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['value', 'hidden'],
    });
}

/**
 * 自动同步入口（SIM-API-1）：观察者防抖到期后调用，以 observer 路径同步。
 *
 * 冷却/熔断判定已收口到 key-injector 状态机，本函数仅负责触发时机与
 * 观察者生命周期（熔断后 disconnectObserver）。返回同步结果供调用方
 * 消费（breaker 信号决定观察者断连）。
 * 仅 ai + 完整三元组执行；bar 缺失 / 视图已关闭 → 返回 undefined 不抛错。
 * @returns {Promise<object|undefined>} autoSyncIntoGame 结果（含 cooled/breaker；
 *   bar 缺失等早退路径返回 undefined）
 */
async function autoSyncAfterLoad() {
    if (state !== 'loaded' || !frame) return undefined;
    const game = currentGame;
    if (!game || game.type !== 'ai' || !hasConfigTriplet(game.config)) return undefined;
    const bar = runPanel?.querySelector('.sim-key-bar');
    if (!bar) return undefined;
    return autoSyncIntoGame({
        bar,
        getDoc: () => frame?.contentDocument ?? null,
        getConfig: () => currentGame?.config ?? null,
        getEndpointMode: () => currentGame?.endpointMode ?? null,
        path: 'observer',
    });
}

/**
 * 打开参数校验：game 须为对象且 file 字段通过安全判据（iframe src 注入
 * 守卫 — file 来自 manifest 第三方数据，防御越界/外链）。file 级判据
 * （非空字符串 + 不含 / \ %）委托契约模块 isValidSimulatorFile（单一来源
 * js/simulator-contracts.js，C8）；对象判定与「参数非法：缺少有效的游戏
 * 文件」错误文案留本视图层。
 * @param {unknown} game - openSimulator 入参
 * @returns {boolean}
 */
function isValidGame(game) {
    return game !== null && typeof game === 'object'
        && isValidSimulatorFile(game.file);
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
 * 「重新同步」按钮条）+ body。ai 游戏且 manifest 含完整 config 三元组
 * 时渲染按钮条（U8-T2/SIM-API-1；三元组不完整视为无 config — 提示条维持
 * 现状；按钮条语义为手动重新同步，自动同步在 load 后静默执行）。
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
    // 按钮条仅 ai + 完整 config 三元组渲染
    const keyBar = isAi && hasConfigTriplet(g.config)
        ? `<div class="sim-key-bar">
            <button type="button" class="sim-key-btn">${TEXT_RESYNC}</button>
            <span class="sim-key-msg" role="status" hidden></span>
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
    // getDoc/getConfig/getEndpointMode 动态取 — iframe 异步加载，点击时再取当前值）
    const bar = runPanel.querySelector('.sim-key-bar');
    if (bar) {
        attachKeyInject({
            bar,
            getDoc: () => frame?.contentDocument ?? null,
            getConfig: () => currentGame?.config ?? null,
            getEndpointMode: () => currentGame?.endpointMode ?? null,
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

/** iframe load 事件 → loaded（清计时器、显示 iframe、移除加载占位、
 * SIM-API-1 自动同步 + 挂配置控件重建观察者） */
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
    // PC 阅读覆盖层注入（方案 A — T1；load 后追加共享样式表，幂等空安全；
    // 位于自动同步之前 — 覆盖层先行就位不影响同步路径）
    injectPcOverlay(frame?.contentDocument ?? null);
    // Load 自动同步（默认 path='load'：置冷却不计数）
    autoSyncIntoGame({
        bar: runPanel?.querySelector('.sim-key-bar'),
        getDoc: () => frame?.contentDocument ?? null,
        getConfig: () => currentGame?.config ?? null,
        getEndpointMode: () => currentGame?.endpointMode ?? null,
    });
    observeConfigControls();
}

/** 超时守卫到期（TIMEOUT_MS 内未收到 load）→ error（卸载 iframe，展示重试/返回）。
 * 文案保留运行视图自身语义（非清单域 TIMEOUT_REASON），秒数由共享
 * TIMEOUT_MS 派生（改超时常量必联动文案秒数）。 */
function handleTimeout() {
    if (state !== 'opening') return; // 兜底：已 loaded/closed 的残留计时器忽略
    state = 'error';
    destroyFrame();
    renderError(`加载超时（${TIMEOUT_MS / 1000} 秒未收到响应）`);
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
