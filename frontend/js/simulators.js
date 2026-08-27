/**
 * Conver System — 模拟器列表视图（深模块，U7-T3）
 *
 * 职责：模拟器列表页的全部逻辑收口 —— manifest 获取/解析校验（parseManifest
 *   纯函数）、卡片网格渲染、类型筛选（filterGames 纯函数）、列表四态
 *   （loading / ready / error / empty）、错误态重试。点击卡片经注入的
 *   onOpenGame 钩子交给协调层（未注入时为空操作不报错）。工具条「存档管理」
 *   按钮（U9-T2）经注入的 onOpenSaveManager 钩子交给存档面板模块；工具条
 *   「导入游戏」按钮（工单 04）经注入的 onImportGame 钩子交给导入模块
 *   （simulator-import.openImportFlow）。卡片「已导入」badge 与「AI 生成」badge：parseManifest
 *   透传 source 白名单字段（'imported' / 'generated'，T-02 决策 10）。卡片
 *   「重新识别」按钮渲染判据由纯函数 canReprobeGame 驱动（T-01：local 恒可 /
 *   ai+source='imported' 可 / 其余不渲染），点击走 reprobeGame 端到端流程。游戏列表
 *   缓存经 getGames() 公开读取（存档面板 getGames 钩子的数据源 — 不重复
 *   fetch manifest，G7）。
 *
 * 依赖方向：simulators.js → icons.js（iconHtml 图标 seam）/ utils.js
 *   （escapeHtml）/ simulator-contracts.js（C8 契约深模块：MANIFEST_URL 清单
 *   URL / TIMEOUT_MS 超时毫秒 / TIMEOUT_REASON 清单域超时文案 — 模拟器域
 *   事实单一来源，本视图不持副本）；app.js → simulators.js（initSimulatorsView /
 *   refreshSimulators 接线）。打开回调经注入钩子（G7 注入钩子模式）：
 *   app.js 初始化时传入 onOpenGame（U7-T4 将接入 openSimulator）。
 *
 * fetch seam（单一来源 js/fetch-seam.js，TD-51/55/60）：fetch 注入点由
 *   api.js 与 simulators.js 共享 —— 两模块均 `export { setFetch } from
 *   './fetch-seam.js'` 并内部统一走 doFetch（setFetch(mock) 一次注入对两
 *   模块同时生效）；传 null/非函数恢复回落全局 fetch；与 app.test.js 既有
 *   globalThis.fetch mock 路由兼容（fetchImpl 为 null 时走全局 fetch）。
 *   清单加载超时守卫（TD-72 两阶段）：15s 总预算覆盖 headers（fetch
 *   promise 竞速）与响应体读取（res.text() 竞速）两阶段（两阶段共享同一
 *   计时器，headers 耗时扣减 text() 预算）—— 到点 abort
 *   通知真实 fetch 断开 + 独立拒绝驱动错误态；第二 race 的 await 是语义
 *   载重，保证 text() 结算后才清理计时器（未 await 则计时器在读取开始前
 *   已清，响应体挂起时守卫失效）。
 *
 * DOM 契约：本模块持有自身 DOM 引用（#simulator-list-panel 挂载点），
 *   index.html 提供静态空容器（U7-T1），内容全部由本模块渲染；模块求值于
 *   DOM 就位之后（type=module 延迟执行）。协调层「进入 simulators 视图」
 *   调用 refreshSimulators() 触发首次加载（懒加载：未进入视图不发请求）。
 *
 * 解析校验策略（spec Implementation Decisions）：结构性错误（畸形 JSON /
 *   version 不兼容 / 顶层非对象 / simulators 缺失或非数组 / id 缺失或重复 /
 *   file 缺失 / type 非法 / 条目非对象）→ 整体判定失败，列表进入错误态
 *   （含重试）；条目级字段缺失（name / description / saveKeyPrefix /
 *   config / saveKeys / endpointMode）→ 宽容降级（该字段不渲染/剔除，
 *   不整体失败；endpointMode 非 'base'/'full' 剔除，注入时按不转换处理）。
 *
 * saveKeys 契约（U9-T1，与 U9-T2 共享 — 契约常量单一来源见
 *   js/save-key-meta.js（TD-67/68 契约之家））：v2 条目声明存档键白名单，
 *   数组元素为字符串 —— 不含正则元字符的字符串 = 精确键名；含正则元字符的
 *   字符串 = 正则模式（白名单匹配时锚定完整键名 ^…$）。归一化：结构非法
 *   （非数组 / 元素非字符串 / 模式自含 ^ $ 锚点）→ 条目级降级（该游戏无
 *   saveKeys 属性 = 「无存档管理」信号）；模式无法编译 / 空串元素 → 元素级
 *   剔除。v1 条目缺 saveKeys → 无 saveKeys 属性（同样降级信号）；saveKeyPrefix
 *   已退役（TD-48）：v1 数据仅兼容透传，不参与任何存档语义。
 *
 * 协议表面（__all__）：initSimulatorsView / refreshSimulators /
 *   parseManifest / filterGames / canReprobeGame / getGames / setFetch。
 */

import { iconHtml } from './icons.js';
import { escapeHtml, showSuccess, showError } from './utils.js';
import { saveKeyIsValidPattern } from './save-key-meta.js';
import { doFetch } from './fetch-seam.js';
import { MANIFEST_URL, TIMEOUT_MS, TIMEOUT_REASON, REPROBE_URL } from './simulator-contracts.js';

// ══════════════════════════════════════════════════
// fetch seam（单一来源 js/fetch-seam.js — 见模块头 docstring；TD-51/55/60）
// ══════════════════════════════════════════════════

export { setFetch } from './fetch-seam.js';

// ══════════════════════════════════════════════════
// 模块级状态（UI 实现细节 — 不属全局应用状态）
// ══════════════════════════════════════════════════
// 模拟器域事实常量（MANIFEST_URL 清单 URL / TIMEOUT_MS 超时毫秒 /
// TIMEOUT_REASON 清单域超时文案）单一来源为 js/simulator-contracts.js
// （C8 契约深模块）—— 本视图不持副本，改路径 / 超时只改契约模块。

/** 列表挂载容器（initSimulatorsView 注入；未 init 时为 null） */
let container = null;

/** 状态区元素（工具条之下的四态渲染目标；initSimulatorsView 创建） */
let stateEl = null;

/** 卡片点击打开钩子（app.js 注入；未注入时 no-op 兜底） */
let onOpenGame = () => {};

/** 工具条「存档管理」按钮钩子（app.js 注入 → save-manager.openSavePanel；未注入时 no-op 兜底） */
let onOpenSaveManager = () => {};

/** 工具条「导入游戏」按钮钩子（app.js 注入 → simulator-import.openImportFlow；未注入时 no-op 兜底） */
let onImportGame = () => {};

/** 工具条「AI 生成」按钮钩子（app.js 注入 → game-generator.openGenerateFlow；未注入时 no-op 兜底） */
let onGenerateGame = () => {};

/** 最近一次解析成功的完整游戏列表（筛选基于缓存，不重复 fetch） */
let games = [];

/** 当前筛选档位：all | ai | local */
let currentFilter = 'all';

/** 事件绑定守卫：首次 initSimulatorsView 绑定后置位，重复调用仅更新钩子 */
let bound = false;

/** 请求序号守卫：只认最新一次刷新（迟到响应/迟到错误一律丢弃，TD-51/55/60） */
let fetchSeq = 0;

/** type → 类型标签文案（UI 契约） */
const TYPE_LABELS = { ai: 'AI 驱动', local: '纯本地' };

/** 筛选按钮三档（data-filter 值 → 文案；顺序即 UI 顺序） */
const FILTERS = [
    { value: 'all', label: '全部' },
    { value: 'ai', label: 'AI 驱动' },
    { value: 'local', label: '纯本地' },
];

// ══════════════════════════════════════════════════
// 纯函数：manifest 解析（校验 + 归一化）
// ══════════════════════════════════════════════════

/** 正则元字符集：saveKeys 元素含任一字符即按正则模式处理（精确键名不得含这些字符） —
 *  单一来源：js/save-key-meta.js（契约之家，TD-67/68） */

/**
 * 归一化 saveKeys（U9-T1 v2 契约，与 U9-T2 共享）。
 *
 * 输入为原始条目字段值，输出清洗后的字符串数组（元素语义：不含正则元字符
 * = 精确键名；含正则元字符 = 锚定完整键名的正则模式）。降级分级：
 *   - 结构非法（非数组 / 元素非字符串 / 模式自含 ^ $ 锚点）→ 返回 undefined
 *     （条目级降级：该游戏无 saveKeys 属性 = 「无存档管理」信号）；
 *   - 模式无法编译 / 空串元素 → 元素级剔除（该项不进入白名单）。
 * 清洗后为空数组时保留空数组（结构性合法，非降级信号）。
 *
 * @param {unknown} value - manifest 条目的原始 saveKeys 字段值
 * @returns {string[]|undefined} 清洗后的白名单数组；结构非法返回 undefined
 */
function normalizeSaveKeys(value) {
    if (!Array.isArray(value)) return undefined;
    const keys = [];
    for (const item of value) {
        if (typeof item !== 'string') return undefined; // 元素类型非法 → 条目级降级
        if (item.includes('^') || item.includes('$')) return undefined; // 自锚定 → 条目级降级
        if (item === '') continue; // 空串 → 元素级剔除
        if (!saveKeyIsValidPattern(item)) {
            continue; // 不可编译 → 元素级剔除
        }
        keys.push(item);
    }
    return keys;
}

/**
 * 解析并校验 manifest 原始 JSON 文本，归一化为游戏列表。
 *
 * 结构性错误（畸形 JSON / 非字符串输入 / 顶层非对象 / version 不兼容 /
 * simulators 缺失或非数组 / 条目非对象 / id 缺失或重复 / file 缺失 /
 * type 非法）→ 整体失败（{ ok:false, error }），列表进入错误态；
 * 条目级字段缺失（name / description / saveKeyPrefix / config / saveKeys）→
 * 宽容降级（name/description 归一化为空串，saveKeyPrefix/config/saveKeys
 * 非法类型剔除或归一化），不整体失败。
 *
 * version 仅接受 1 / 2（v1 数据兼容解析：条目无 saveKeys → 无 saveKeys 属性，
 * 即「无存档管理」降级信号；saveKeyPrefix 仅 v1 数据携带并透传，已退役不参与
 * 存档语义）。saveKeys 归一化语义见 normalizeSaveKeys 与模块头 docstring。
 *
 * @param {string} rawJson - manifest.json 的原始文本
 * @returns {{ok: true, games: Array<object>}|{ok: false, error: string}}
 *   ok:true 时 games 为归一化条目数组（含空数组）；ok:false 时 error 为
 *   面向用户的错误原因文案
 */
export function parseManifest(rawJson) {
    if (typeof rawJson !== 'string') {
        return { ok: false, error: 'manifest 必须是 JSON 字符串' };
    }

    let data;
    try {
        data = JSON.parse(rawJson);
    } catch {
        return { ok: false, error: 'manifest 不是合法 JSON' };
    }

    if (data === null || typeof data !== 'object' || Array.isArray(data)) {
        return { ok: false, error: 'manifest 顶层必须是对象' };
    }
    if (data.version !== 1 && data.version !== 2) {
        return { ok: false, error: 'manifest 版本不兼容' };
    }
    if (!Array.isArray(data.simulators)) {
        return { ok: false, error: 'manifest 缺少 simulators 列表' };
    }

    const seen = new Set();
    const games = [];
    for (const entry of data.simulators) {
        if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
            return { ok: false, error: 'manifest 条目必须是对象' };
        }
        if (typeof entry.id !== 'string' || entry.id === '' || seen.has(entry.id)) {
            return { ok: false, error: 'manifest 存在缺失或重复的 id' };
        }
        if (typeof entry.file !== 'string' || entry.file === '') {
            return { ok: false, error: 'manifest 条目缺少 file 字段' };
        }
        if (entry.type !== 'ai' && entry.type !== 'local') {
            return { ok: false, error: 'manifest 条目 type 非法' };
        }

        seen.add(entry.id);
        // 条目级宽容降级：name/description 缺失 → 空串（不渲染）；
        // saveKeyPrefix/config 非合法类型 → 剔除（不渲染）；
        // saveKeys 结构非法 → 无 saveKeys 属性（「无存档管理」降级信号）；
        // endpointMode 非 'base'/'full' → 剔除（注入时按不转换处理）；
        // source 白名单（T-02 决策 10）：仅接受字符串 'imported' 或 'generated'
        //（导入条目标识与 AI 生成条目标识），其余值/缺失 → 不设 source
        //（内置条目无此字段 → 无 badge）
        const game = {
            id: entry.id,
            file: entry.file,
            name: typeof entry.name === 'string' ? entry.name : '',
            type: entry.type,
            description: typeof entry.description === 'string' ? entry.description : '',
        };
        if (entry.source === 'imported' || entry.source === 'generated') game.source = entry.source;
        if (typeof entry.saveKeyPrefix === 'string') game.saveKeyPrefix = entry.saveKeyPrefix;
        if (entry.config !== null && typeof entry.config === 'object' && !Array.isArray(entry.config)) {
            game.config = entry.config;
        }
        if (entry.endpointMode === 'base' || entry.endpointMode === 'full') {
            game.endpointMode = entry.endpointMode;
        }
        const saveKeys = normalizeSaveKeys(entry.saveKeys);
        if (saveKeys) game.saveKeys = saveKeys;
        games.push(game);
    }

    return { ok: true, games };
}

// ══════════════════════════════════════════════════
// 纯函数：类型筛选
// ══════════════════════════════════════════════════

/**
 * 按类型过滤游戏列表。
 *
 * 筛选档位：'ai' → 仅 ai；'local' → 仅 local；'all' 与未知档位 → 原样返回。
 * 未知 game.type 的游戏计入「全部」、不落入 ai/local 任一档（过滤策略
 * 已定，spec U7）；parseManifest 已保证 type 合法，此分支为防御性兜底。
 *
 * @param {Array<object>} games - 游戏列表（parseManifest 归一化产物）
 * @param {string} type - 筛选档位：all | ai | local
 * @returns {Array<object>} 过滤后的游戏列表（非数组输入返回空数组）
 */
export function filterGames(games, type) {
    if (!Array.isArray(games)) return [];
    if (type === 'ai') return games.filter((g) => g?.type === 'ai');
    if (type === 'local') return games.filter((g) => g?.type === 'local');
    return games;
}

/**
 * 重新识别按钮渲染判据（T-01）：游戏条目是否可一键重新识别类型。
 *
 * 语义契约：local 条目（无论是否带 source）恒可 reprobe（行为基线不变）；
 * ai 条目仅当 source='imported'（历史误探为 ai、经导入纠正的老条目）可
 * reprobe；其余（内置 ai 条目 / ai+source='generated' AI 生成条目）不渲染
 * 按钮。非对象输入 / type 缺失或非法 → false；ai 分支下 source 缺失或非
 * 'imported' → false（防御不炸；parseManifest 已保证 type 合法，此分支为
 * 防御性兜底，filterGames 先例）。
 *
 * @param {unknown} game - 游戏条目对象（parseManifest 归一化条目）
 * @returns {boolean} 可重新识别返回 true；否则 false
 */
export function canReprobeGame(game) {
    if (game === null || typeof game !== 'object' || Array.isArray(game)) return false;
    if (game.type === 'local') return true;
    return game.type === 'ai' && game.source === 'imported';
}

// ══════════════════════════════════════════════════
// 渲染（四态：loading / ready / error / empty）
// ══════════════════════════════════════════════════

/**
 * 渲染工具条（筛选三档按钮 + 计数 + 存档管理按钮）与状态区骨架（四态渲染目标）。
 * 只渲染一次（initSimulatorsView 时），refresh/筛选仅重渲染状态区。
 */
function renderShell() {
    const filterButtons = FILTERS
        .map((f) => `<button type="button" class="sim-filter-btn${f.value === 'all' ? ' active' : ''}" data-filter="${f.value}">${f.label}</button>`)
        .join('');
    container.innerHTML = `
        <div class="sim-toolbar">
            <div class="sim-filters" role="group" aria-label="类型筛选">${filterButtons}</div>
            <button type="button" class="sim-generate-btn" data-action="generate-game">AI 生成</button>
            <button type="button" class="sim-import-btn" data-action="import-game">导入游戏</button>
            <button type="button" class="sim-save-manage-btn" data-action="open-save-manager">存档管理</button>
            <span class="sim-count"></span>
        </div>
        <div class="sim-state"></div>
    `;
    stateEl = container.querySelector('.sim-state');
}

/** 渲染 loading 态（请求在途；同步执行，先于 await 可见） */
function renderLoading() {
    if (!stateEl) return;
    stateEl.innerHTML = '<p class="sim-status">加载中…</p>';
}

/**
 * 渲染 ready / empty 态：按当前筛选档位渲染卡片网格与计数。
 * 全部为空（manifest 无条目）→ 「暂无模拟器」；仅筛选无匹配 → 「该类型暂无模拟器」。
 */
function renderList() {
    if (!stateEl) return;
    const filtered = filterGames(games, currentFilter);
    container.querySelector('.sim-count').textContent = `共 ${filtered.length} 款`;

    if (filtered.length === 0) {
        const emptyText = games.length === 0 ? '暂无模拟器' : '该类型暂无模拟器';
        stateEl.innerHTML = `<p class="sim-status sim-empty">${emptyText}</p>`;
        return;
    }

    const cards = filtered.map((game) => `
        <article class="sim-card">
            <div class="sim-card-icon">${iconHtml('gamepad', { size: 20 })}</div>
            <div class="sim-card-body">
                <div class="sim-card-title">
                    ${game.name ? `<h3 class="sim-card-name">${escapeHtml(game.name)}</h3>` : ''}
                    <span class="sim-type-tag sim-type-${game.type}">${TYPE_LABELS[game.type]}</span>
                    ${game.source === 'imported' ? '<span class="sim-source-tag">已导入</span>' : ''}
                    ${game.source === 'generated' ? '<span class="sim-source-tag sim-source-generated">AI 生成</span>' : ''}
                    ${canReprobeGame(game) ? `<button type="button" class="sim-reprobe-btn" data-action="reprobe" title="重新识别类型">${iconHtml('refresh', { size: 12 })} 重新识别</button>` : ''}
                </div>
                ${game.description ? `<p class="sim-card-desc">${escapeHtml(game.description)}</p>` : ''}
            </div>
        </article>
    `).join('');
    stateEl.innerHTML = `<div class="sim-grid">${cards}</div>`;
    // data-id 经 DOM dataset 赋值（数据通道单一化纪律 — 属性值不嵌 HTML 字符串：
    // escapeHtml 文本序列化不转义引号，字符串拼接 data-id 存在属性注入面 +
    // 引号截断；dataset 赋值天然安全且完整往返，先例：format.js messageBubbleHtml
    // 复制数据通道，CONTEXT.md message bubble factory）
    stateEl.querySelectorAll('.sim-card').forEach((el, i) => {
        el.dataset.id = filtered[i].id;
    });
}

/**
 * 渲染 error 态：错误文案 + 原因（转义）+ 重试按钮。
 * @param {string} reason - 失败原因（fetch 异常 / parseManifest 错误文案）
 */
function renderError(reason) {
    if (!stateEl) return;
    stateEl.innerHTML = `
        <div class="sim-error">
            <span class="sim-error-icon">${iconHtml('warning', { size: 20 })}</span>
            <p class="sim-error-msg">模拟器列表加载失败</p>
            <p class="sim-error-reason">${escapeHtml(reason)}</p>
            <button type="button" class="sim-retry-btn" data-action="retry">重试</button>
        </div>
    `;
}

// ══════════════════════════════════════════════════
// 对外入口
// ══════════════════════════════════════════════════

/**
 * 初始化模拟器列表视图：挂载工具条与状态区骨架，渲染初始 loading 态，
 * 绑定筛选按钮与卡片/重试事件委托。
 *
 * 幂等：重复调用仅更新 onOpenGame / onOpenSaveManager / onImportGame /
 *   onGenerateGame 钩子、不重复绑定事件（search-view 先例）。container 缺失
 *   （index.html 契约被破坏的极端场景）→ no-op 不抛错。加载不发请求 ——
 *   首次 fetch 由协调层「进入 simulators 视图」调 refreshSimulators() 触发
 *   （懒加载）。
 * @param {object} [options]
 * @param {HTMLElement} [options.container] - 列表挂载容器（#simulator-list-panel）
 * @param {Function} [options.onOpenGame] - (game) => void；点击卡片触发，
 *   game 为 parseManifest 归一化条目（未注入时点击为空操作不报错）
 * @param {Function} [options.onOpenSaveManager] - () => void；工具条「存档
 *   管理」按钮触发（未注入时点击为空操作不报错）
 * @param {Function} [options.onImportGame] - () => void；工具条「导入游戏」
 *   按钮触发（工单 04；未注入时点击为空操作不报错）
 * @param {Function} [options.onGenerateGame] - () => void；工具条「AI 生成」
 *   按钮触发（未注入时点击为空操作不报错）
 */
export function initSimulatorsView({ container: el, onOpenGame: hook, onOpenSaveManager: saveHook, onImportGame: importHook, onGenerateGame: generateHook } = {}) {
    if (!el) return;
    container = el;
    if (typeof hook === 'function') onOpenGame = hook;
    if (typeof saveHook === 'function') onOpenSaveManager = saveHook;
    if (typeof importHook === 'function') onImportGame = importHook;
    if (typeof generateHook === 'function') onGenerateGame = generateHook;
    if (bound) return; // 幂等守卫：已绑定则早退（钩子已在上方更新）

    renderShell();
    bindEvents();
    renderLoading();
    bound = true;
}

/** 绑定筛选按钮点击 + 状态区事件委托（卡片点击 / 重试） */
function bindEvents() {
    container.querySelectorAll('.sim-filter-btn').forEach((btn) => {
        btn.addEventListener('click', () => {
            currentFilter = btn.dataset.filter;
            container.querySelectorAll('.sim-filter-btn').forEach((b) => {
                b.classList.toggle('active', b === btn);
            });
            renderList();
        });
    });

    // 工具条「存档管理」按钮 → 存档面板钩子（U9-T2；未注入时 no-op 不报错；
    // 点击时读取模块变量 — 重复 init 更新钩子后取最新值，先例同卡片委托）
    container.querySelector('.sim-save-manage-btn')?.addEventListener('click', () => onOpenSaveManager());

    // 工具条「AI 生成」按钮 → 游戏生成器钩子（未注入时 no-op 不报错）
    container.querySelector('.sim-generate-btn')?.addEventListener('click', () => onGenerateGame());

    // 工具条「导入游戏」按钮 → 导入流程钩子（工单 04；未注入时 no-op 不报错）
    container.querySelector('.sim-import-btn')?.addEventListener('click', () => onImportGame());

    // 事件委托：重新识别 → reprobeGame；卡片点击 → onOpenGame(game)；
    // 重试按钮 → refreshSimulators。
    // 委托挂在持久状态区元素上，重渲染不丢监听（search-view 结果跳转先例）
    stateEl.addEventListener('click', (e) => {
        const reprobe = e.target.closest('[data-action="reprobe"]');
        if (reprobe) {
            const card = reprobe.closest('.sim-card');
            if (card?.dataset.id) reprobeGame(card.dataset.id);
            return;
        }
        const retry = e.target.closest('[data-action="retry"]');
        if (retry) {
            refreshSimulators();
            return;
        }
        const card = e.target.closest('.sim-card');
        if (!card) return;
        const game = games.find((g) => g.id === card.dataset.id);
        if (game) onOpenGame(game);
    });
}

/**
 * 获取 manifest 文本（经 fetch seam：fetch-seam.js doFetch → 注入实现 ?? 全局 fetch）。
 * 响应非 2xx → 抛错（HTTP 状态码入原因）；响应形状异常 → 抛错入 catch 兜底。
 * 15s 超时守卫（两阶段，TD-72）：headers 阶段（fetch promise 竞速）与响应体
 * 读取阶段（res.text() 竞速）均纳入同一 15s 总预算（共享计时器，headers
 * 耗时扣减 text() 预算）—— 任一阶段挂起到点后独立驱动拒绝
 * （不依赖 fetch 是否响应 signal），同时 abort 通知真实 fetch 断开；第二
 * race 的 await 是语义载重：finally 须等 text() 结算后才清计时器，否则
 * 读取阶段挂起时守卫与 abort 均失效。
 * @returns {Promise<string>} manifest 原始 JSON 文本
 */
async function fetchManifestText() {
    const controller = new AbortController();
    let timer = null;
    const timeoutPromise = new Promise((_, reject) => {
        timer = setTimeout(() => {
            controller.abort(); // 通知真实 fetch 断开（迟到的 AbortError 由下方吞掉兜底）
            reject(new Error(TIMEOUT_REASON));
        }, TIMEOUT_MS);
    });
    try {
        // cache: 'no-store' — manifest 是易变数据（导入成功后刷新须拿到新鲜
        // 内容）：静态挂载带 ETag/Last-Modified，无 Cache-Control，浏览器
        // 二次 fetch 条件请求 304 会用缓存旧数据，导入新卡不出现（冒烟实测
        // 定位，2026-08-19）
        const fetchPromise = doFetch(MANIFEST_URL, { signal: controller.signal, cache: 'no-store' });
        fetchPromise.catch(() => {}); // 超时后迟到响应/拒绝不产生未处理拒绝（一律丢弃）
        const res = await Promise.race([fetchPromise, timeoutPromise]);
        if (res?.ok === false) {
            throw new Error(`加载失败 (${res.status})`);
        }
        if (!res || typeof res.text !== 'function') {
            throw new Error('模拟器清单响应无效');
        }
        // TD-72：await 为语义载重 —— 响应体读取纳入第二 race，finally 须等
        // text() 结算后才清计时器（不带 await 等于没修：读取阶段守卫失效）
        return await Promise.race([res.text(), timeoutPromise]);
    } finally {
        clearTimeout(timer); // 正常完成 / 同步抛错路径均清理计时器
    }
}

/**
 * 重新 fetch manifest + 重渲染（供协调层「进入 simulators 视图」钩子调用）。
 *
 * 状态机：loading → ready（解析成功）| error（fetch 失败 / 解析结构错误 /
 *   15s 超时，均含重试按钮）| empty（manifest 无条目）。解析结构性错误整体
 *   进错误态，条目级缺陷由 parseManifest 降级不炸。请求序号守卫：并发刷新
 *   只认最新一次 —— await 之后与 catch 分支均先判 seq，迟到响应/迟到错误
 *   一律丢弃不渲染。未 init（container 缺失）→ no-op 不抛错（Falsify 兜底）。
 * @returns {Promise<void>}
 */
export async function refreshSimulators() {
    if (!container) return;
    const seq = ++fetchSeq;
    renderLoading();
    try {
        const raw = await fetchManifestText();
        if (seq !== fetchSeq) return; // 旧请求迟到 → 丢弃（并发刷新只认最新）
        const parsed = parseManifest(raw);
        if (!parsed.ok) {
            renderError(parsed.error);
            return;
        }
        games = parsed.games;
        renderList();
    } catch (err) {
        if (seq !== fetchSeq) return; // 旧请求迟到错误 → 丢弃
        renderError(err instanceof Error ? err.message : String(err));
    }
}

/**
 * 读取最近一次解析成功的完整游戏列表（存档面板 getGames 钩子的数据源 —
 *   不重复 fetch manifest）。未加载 / 未 init → 空数组。
 * @returns {Array<object>} parseManifest 归一化游戏条目数组
 */
export function getGames() {
    return Array.isArray(games) ? games : [];
}

/**
 * 重新识别游戏类型：POST 到 reprobe 端点 → 更新 manifest → 刷新列表。
 * 仅渲染了「重新识别」按钮的卡片可触发（canReprobeGame 判定为 true：local /
 * ai+source='imported'，T-01）；成功刷新列表并显示成功提示，失败显示错误不销毁列表。
 * @param {string} id - 游戏条目 id
 */
async function reprobeGame(id) {
    try {
        const res = await doFetch(REPROBE_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id }),
        });
        if (!res?.ok) {
            const detail = res ? await res.json().then(d => d.detail || `请求失败 (${res.status})`).catch(() => `请求失败 (${res.status})`) : '网络错误';
            showError(`重新识别失败：${detail}`);
            return;
        }
        await refreshSimulators();
        showSuccess('已重新识别');
    } catch (err) {
        showError(`重新识别失败：${err instanceof Error ? err.message : String(err)}`);
    }
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 simulators.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'initSimulatorsView',
    'refreshSimulators',
    'parseManifest',
    'filterGames',
    'canReprobeGame',
    'getGames',
    'setFetch',
];
