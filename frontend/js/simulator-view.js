/**
 * Conver System — 模拟器运行视图（深模块，U7-T4 / U8-T2 / SIM-API-1）
 *
 * 职责：运行视图的全部逻辑收口 —— iframe 状态机（idle → opening → loaded |
 *   error，含 15s 超时守卫）、AI 提示条（type === 'ai' 渲染固定文案 +
 *   ai 且 manifest 含完整 config 三元组时附「重新同步」按钮条）、
 *   SIM-API-1 配置持续同步（iframe load 后自动同步主应用凭证/端点/模型 +
 *   MutationObserver 监听配置控件动态重建后再同步）、「返回」回列表
 *   （卸载 iframe；游戏存档在游戏自身 localStorage 前缀隔离保存，重进自动
 *   恢复，卸载不丢进度）。打开参数校验（非法 file → 直接 error 态，不创建
 *   iframe；file 含路径分隔符 → 拒绝 — iframe src 注入守卫，src 永远形如
 *   simulators/<file> 同源加载）。
 *
 * 依赖方向：simulator-view.js → icons.js（iconHtml）/ utils.js（escapeHtml，
 *   game.name 来自 manifest 第三方数据，header 渲染必须转义）/
 *   key-injector.js（U8-T2/SIM-API-1：attachKeyInject 挂按钮交互 +
 *   autoSyncIntoGame 自动同步编排 + hasConfigTriplet 三元组校验 +
 *   TEXT_RESYNC 按钮文案 — 同步/注入逻辑收口在 key-injector.js，凭证获取
 *   经 initKeyInjector 钩子由 app.js 接线；本模块只负责触发时机与观察者）；
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
 *   属性重建（setAttribute 重置控件值 — TD-75：目标元素自身 id ∈ 三元组才
 *   处理，运行期无关属性变更（class/style 等）经 id 过滤不触发；宿主注入
 *   走 property 赋值与事件派发，不产生 attribute mutation — 无自触发面）。
 *   只处理触及 config 三元组 id 的变更（id 命中 / 变更子树含控件 — 游戏
 *   运行期高频 DOM 更新不触发）；防抖 500ms 合并连续重建；注入后 1s 冷却
 *   （写回环守卫：宿主写入派发的 change 若被游戏同步重建面板，冷却窗口内
 *   不重复同步 — key-injector 幂等写入已收敛常规场景，冷却为假设性循环的
 *   兜底）。冷却判定在防抖到期时执行（注入续体更新冷却时间戳晚于 option
 *   追加等自写 mutation 回调，mutation 时判定会失真 — TD-76 实测钉死）。
 *   写回环熔断（TD-76）：观察者路径触发的再同步实际写入字段（filled > 0）
 *   连续达 SYNC_MAX_STRIKES 次 → 熔断 disconnect（停止自动再同步；手动
 *   「重新同步」按钮路径不受影响）；load 路径自动同步不计数；destroyFrame
 *   （关闭 / 重开游戏）复位计数 — 重开游戏观察者重新挂载、自动同步恢复。
 *   观察者随 iframe 卸载 disconnect（destroyFrame），无跨游戏残留。
 *
 * 错误检测基线（spec Implementation Decisions）：同源 404 仍触发 load 事件，
 *   错误态主要依赖超时守卫（15s 未收到 load）+ 打开参数校验；iframe 元素
 *   无标准 error 事件（onerror 仅 img/script 类），不监听。
 *
 * 协议表面（__all__）：initSimulatorRun / openSimulator / closeSimulator。
 */

import { iconHtml } from './icons.js';
import { escapeHtml } from './utils.js';
import { attachKeyInject, hasConfigTriplet, autoSyncIntoGame, TEXT_RESYNC } from './key-injector.js';

// ══════════════════════════════════════════════════
// 常量（UI 契约 — 文案/时长与 spec 对齐）
// ══════════════════════════════════════════════════

/** 模拟器静态目录（与列表模块 MANIFEST_URL 同源约定；T2 静态托管根挂载覆盖） */
const SIM_DIR = 'simulators';

/** 加载超时守卫时长（spec 建议 15s） */
const TIMEOUT_MS = 15000;

/** AI 游戏提示条固定文案（spec 逐字） */
const HINT_AI = '此游戏需自行配置 AI 接口';

/** 配置控件重建观察者防抖时长（毫秒；连续重建合并为一次同步） */
const OBSERVER_DEBOUNCE_MS = 500;

/** 注入后写回环冷却时长（毫秒；宿主写入派发的 change 若被游戏同步重建
 * 面板，冷却窗口内不重复同步 — 幂等写入已收敛常规场景，此为兜底） */
const SYNC_COOLDOWN_MS = 1000;

/** 观察者路径写回环熔断阈值（TD-76）：连续 SYNC_MAX_STRIKES 次观察者再同步
 * 实际写入字段（filled > 0 — 每次同步后游戏又重建面板恢复默认值 = 游戏在
 * 重置主应用配置的病理循环）→ 熔断断开观察者，终止自动再同步；正常场景
 * （单次重建后收敛）再同步至多写入 1 次，恒低于阈值不误熔断 */
const SYNC_MAX_STRIKES = 3;

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

/** 注入写回环冷却截止时间戳（Date.now()；未冷却为 0） */
let syncCooldownUntil = 0;

/** 观察者路径写回环熔断计数（TD-76：连续写入次数；达到 SYNC_MAX_STRIKES
 * 熔断断开观察者；destroyFrame 复位 — 重开游戏观察者重新挂载） */
let syncStrikes = 0;

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
    syncCooldownUntil = 0; // 冷却属当前视图生命周期 — 跨游戏不残留（防新游戏观察者被旧冷却误伤）
    syncStrikes = 0; // 熔断计数复位 — 重开游戏观察者重新挂载、自动同步恢复（TD-76）
    if (frame) {
        frame.remove();
        frame = null;
    }
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
 * 语义：childList 变更（节点增删）— 目标元素自身 id ∈ 三元组，或新增/移除
 * 子树内任一元素 id ∈ 三元组（游戏整段重建配置面板时命中；子树元素遍历用
 * id 成员判定，无选择器转义面）；attributes 变更（TD-75 — 游戏以
 * setAttribute 重建控件）— 仅目标元素自身 id ∈ 三元组视为触及（运行期无关
 * 属性变更（class/style 等）经 id 过滤不触发同步）。
 * @param {MutationRecord[]} mutations - MutationObserver 回调的变更记录
 * @param {object|null} config - manifest config 三元组（endpoint/apikey/model）
 * @returns {boolean} 任一变更触及配置控件为 true
 */
function mutationTouchesConfig(mutations, config) {
    const ids = [config?.endpoint, config?.apikey, config?.model]
        .filter((v) => typeof v === 'string' && v !== '');
    if (ids.length === 0) return false;
    for (const m of mutations ?? []) {
        if (m?.type === 'attributes') {
            // TD-75：属性变更仅当目标元素自身是配置控件才触及（游戏运行期
            // 高频的无关属性变更（class/style 等）经 id 过滤不触发同步）
            if (typeof m?.target?.id === 'string' && ids.includes(m.target.id)) return true;
            continue;
        }
        if (typeof m?.target?.id === 'string' && ids.includes(m.target.id)) return true;
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
 * 观察者回调：变更触及配置控件 → 防抖 500ms → 自动同步。写回环冷却判定在
 * 防抖到期时执行（TD-76 实测：注入续体更新冷却时间戳晚于自写 mutation
 * （select option 追加等）的观察者回调 — mutation 时判定读到旧时间戳会
 * 失真，产生幽灵再同步并误刷新冷却，压制后续真实重建的响应）。
 * @param {MutationRecord[]} mutations - MutationObserver 回调的变更记录
 */
function handleConfigMutation(mutations) {
    if (state !== 'loaded' || !frame) return;
    if (!mutationTouchesConfig(mutations, currentGame?.config)) return;
    if (observerTimer) clearTimeout(observerTimer);
    observerTimer = setTimeout(() => {
        observerTimer = null;
        if (state !== 'loaded' || !frame) return;
        if (Date.now() < syncCooldownUntil) return; // 自注入冷却（写回环守卫 — 防抖到期时判定）
        autoSyncAfterLoad(true); // 观察者路径 — 写入计熔断 strike（TD-76）
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
    // 面；游戏运行期频繁的无关属性变更（class 等）经 mutationTouchesConfig
    // 的 id 过滤不触发同步
    configObserver.observe(doc.body, { childList: true, subtree: true, attributes: true });
}

/**
 * 自动同步入口（SIM-API-1）：iframe load 后静默取主应用凭证 → 注入当前
 * 游戏配置面板（key-injector autoSyncIntoGame；claude/none 由 key-injector
 * 禁用按钮条 + 原因文案）。同步实际写入过字段 → 置观察者写回环冷却（宿主
 * 写入派发的 change 若被游戏同步重建面板，冷却窗口内不重复同步）；未写入
 * （控件未就位 — 游戏延迟渲染配置面板的主场景）→ 不冷却，观察者及时再同步。
 * 写回环熔断（TD-76）：countStrike=true（观察者防抖路径）且本次实际写入
 * 字段 → 熔断计数 +1，连续达 SYNC_MAX_STRIKES 次 → disconnectObserver
 * 熔断（停止自动再同步；手动「重新同步」按钮路径不经本函数不受影响）。
 * load 路径（handleLoad 直调，countStrike 默认 false）不计数 — 正常场景
 * 每次 load 的自动同步恒定可用。
 * 仅 ai + 完整三元组执行；bar 缺失 / 视图已关闭 → no-op 不抛错。
 * @param {boolean} [countStrike] - true 为观察者路径（写入计熔断 strike）；
 *   false（默认）为 load 路径（不计数）
 */
async function autoSyncAfterLoad(countStrike = false) {
    if (state !== 'loaded' || !frame) return;
    const game = currentGame;
    if (!game || game.type !== 'ai' || !hasConfigTriplet(game.config)) return;
    const bar = runPanel?.querySelector('.sim-key-bar');
    if (!bar) return;
    const result = await autoSyncIntoGame({
        bar,
        getDoc: () => frame?.contentDocument ?? null,
        getConfig: () => currentGame?.config ?? null,
        getEndpointMode: () => currentGame?.endpointMode ?? null,
    });
    if (result?.enabled && result.filled.length > 0) {
        syncCooldownUntil = Date.now() + SYNC_COOLDOWN_MS;
        if (countStrike) {
            syncStrikes += 1;
            if (syncStrikes >= SYNC_MAX_STRIKES) disconnectObserver(); // 熔断：终止自动再同步
        }
    }
}

/**
 * 打开参数校验：game 须为对象且 file 为非空字符串、不含路径分隔符、不含
 * 百分号编码（iframe src 注入守卫 — file 来自 manifest 第三方数据，防御
 * 越界/外链；TD-56：manifest 22 文件实测无 %，单点拒绝整个百分号编码面 —
 * Starlette 遍历防护与 manifest 可信资产为既有兜底，本判定为纵深加固）。
 * @param {unknown} game - openSimulator 入参
 * @returns {boolean}
 */
function isValidGame(game) {
    return game !== null && typeof game === 'object'
        && typeof game.file === 'string' && game.file !== ''
        && !game.file.includes('/') && !game.file.includes('\\')
        && !game.file.includes('%');
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
    autoSyncAfterLoad();
    observeConfigControls();
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
