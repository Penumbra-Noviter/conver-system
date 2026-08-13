/**
 * Conver System — 模拟器列表视图（深模块，U7-T3）
 *
 * 职责：模拟器列表页的全部逻辑收口 —— manifest 获取/解析校验（parseManifest
 *   纯函数）、卡片网格渲染、类型筛选（filterGames 纯函数）、列表四态
 *   （loading / ready / error / empty）、错误态重试。点击卡片经注入的
 *   onOpenGame 钩子交给协调层（未注入时为空操作不报错）。
 *
 * 依赖方向：simulators.js → icons.js（iconHtml 图标 seam）/ utils.js
 *   （escapeHtml）；app.js → simulators.js（initSimulatorsView /
 *   refreshSimulators 接线）。打开回调经注入钩子（G7 注入钩子模式）：
 *   app.js 初始化时传入 onOpenGame（U7-T4 将接入 openSimulator）。
 *
 * fetch seam：manifest 为静态文件（非 /api 端点），api.js 不提供任意 URL
 *   的 fetch 执行入口（其 fetchImpl 为模块私有、不可读），故本模块镜像
 *   api.js setFetch 同一 seam 模式 —— 测试注入 mock（setFetch(fn)），
 *   传 null/非函数恢复回落全局 fetch；与 app.test.js 既有
 *   globalThis.fetch mock 路由兼容（fetchImpl 为 null 时走全局 fetch）。
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
 *   config）→ 宽容降级（该字段不渲染/剔除，不整体失败）。
 *
 * 协议表面（__all__）：initSimulatorsView / refreshSimulators /
 *   parseManifest / filterGames / setFetch。
 */

import { iconHtml } from './icons.js';
import { escapeHtml } from './utils.js';

// ══════════════════════════════════════════════════
// fetch seam（与 api.js setFetch 同构 — 见模块头 docstring）
// ══════════════════════════════════════════════════

/** 测试注入的 fetch 实现（null → 回落全局 fetch；api.js seam 模式镜像） */
let fetchImpl = null;

/**
 * 注入自定义 fetch 实现（测试用，避免真实网络）。传 null/非函数恢复默认全局 fetch。
 * @param {Function|null} fn - fetch 兼容函数 (url, options) => Promise<Response>
 */
export function setFetch(fn) {
    fetchImpl = typeof fn === 'function' ? fn : null;
}

// ══════════════════════════════════════════════════
// 模块级状态（UI 实现细节 — 不属全局应用状态）
// ══════════════════════════════════════════════════

/** manifest 静态目录相对路径（后端静态托管覆盖） */
const MANIFEST_URL = 'simulators/manifest.json';

/** 列表挂载容器（initSimulatorsView 注入；未 init 时为 null） */
let container = null;

/** 状态区元素（工具条之下的四态渲染目标；initSimulatorsView 创建） */
let stateEl = null;

/** 卡片点击打开钩子（app.js 注入；未注入时 no-op 兜底） */
let onOpenGame = () => {};

/** 最近一次解析成功的完整游戏列表（筛选基于缓存，不重复 fetch） */
let games = [];

/** 当前筛选档位：all | ai | local */
let currentFilter = 'all';

/** 事件绑定守卫：首次 initSimulatorsView 绑定后置位，重复调用仅更新钩子 */
let bound = false;

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

/**
 * 解析并校验 manifest 原始 JSON 文本，归一化为游戏列表。
 *
 * 结构性错误（畸形 JSON / 非字符串输入 / 顶层非对象 / version 不兼容 /
 * simulators 缺失或非数组 / 条目非对象 / id 缺失或重复 / file 缺失 /
 * type 非法）→ 整体失败（{ ok:false, error }），列表进入错误态；
 * 条目级字段缺失（name / description / saveKeyPrefix / config）→
 * 宽容降级（name/description 归一化为空串，saveKeyPrefix/config 非法
 * 类型剔除），不整体失败。
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
    if (data.version !== 1) {
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
        // saveKeyPrefix/config 非合法类型 → 剔除（不渲染）
        const game = {
            id: entry.id,
            file: entry.file,
            name: typeof entry.name === 'string' ? entry.name : '',
            type: entry.type,
            description: typeof entry.description === 'string' ? entry.description : '',
        };
        if (typeof entry.saveKeyPrefix === 'string') game.saveKeyPrefix = entry.saveKeyPrefix;
        if (entry.config !== null && typeof entry.config === 'object' && !Array.isArray(entry.config)) {
            game.config = entry.config;
        }
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

// ══════════════════════════════════════════════════
// 渲染（四态：loading / ready / error / empty）
// ══════════════════════════════════════════════════

/**
 * 渲染工具条（筛选三档按钮 + 计数）与状态区骨架（四态渲染目标）。
 * 只渲染一次（initSimulatorsView 时），refresh/筛选仅重渲染状态区。
 */
function renderShell() {
    const filterButtons = FILTERS
        .map((f) => `<button type="button" class="sim-filter-btn${f.value === 'all' ? ' active' : ''}" data-filter="${f.value}">${f.label}</button>`)
        .join('');
    container.innerHTML = `
        <div class="sim-toolbar">
            <div class="sim-filters" role="group" aria-label="类型筛选">${filterButtons}</div>
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
        <article class="sim-card" data-id="${escapeHtml(game.id)}">
            <div class="sim-card-icon">${iconHtml('gamepad', { size: 20 })}</div>
            <div class="sim-card-body">
                <div class="sim-card-title">
                    ${game.name ? `<h3 class="sim-card-name">${escapeHtml(game.name)}</h3>` : ''}
                    <span class="sim-type-tag sim-type-${game.type}">${TYPE_LABELS[game.type]}</span>
                </div>
                ${game.description ? `<p class="sim-card-desc">${escapeHtml(game.description)}</p>` : ''}
            </div>
        </article>
    `).join('');
    stateEl.innerHTML = `<div class="sim-grid">${cards}</div>`;
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
 * 幂等：重复调用仅更新 onOpenGame 钩子、不重复绑定事件（search-view
 * 先例）。container 缺失（index.html 契约被破坏的极端场景）→ no-op
 * 不抛错。加载不发请求 —— 首次 fetch 由协调层「进入 simulators 视图」
 * 调 refreshSimulators() 触发（懒加载）。
 * @param {object} [options]
 * @param {HTMLElement} [options.container] - 列表挂载容器（#simulator-list-panel）
 * @param {Function} [options.onOpenGame] - (game) => void；点击卡片触发，
 *   game 为 parseManifest 归一化条目（未注入时点击为空操作不报错）
 */
export function initSimulatorsView({ container: el, onOpenGame: hook } = {}) {
    if (!el) return;
    container = el;
    if (typeof hook === 'function') onOpenGame = hook;
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

    // 事件委托：卡片点击 → onOpenGame(game)；重试按钮 → refreshSimulators。
    // 委托挂在持久状态区元素上，重渲染不丢监听（search-view 结果跳转先例）
    stateEl.addEventListener('click', (e) => {
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
 * 获取 manifest 文本（经 fetch seam：fetchImpl ?? 全局 fetch）。
 * 响应非 2xx → 抛错（HTTP 状态码入原因）；响应形状异常 → 抛错入 catch 兜底。
 * @returns {Promise<string>} manifest 原始 JSON 文本
 */
async function fetchManifestText() {
    const res = await (fetchImpl ?? globalThis.fetch)(MANIFEST_URL);
    if (res?.ok === false) {
        throw new Error(`加载失败 (${res.status})`);
    }
    if (!res || typeof res.text !== 'function') {
        throw new Error('模拟器清单响应无效');
    }
    return res.text();
}

/**
 * 重新 fetch manifest + 重渲染（供协调层「进入 simulators 视图」钩子调用）。
 *
 * 状态机：loading → ready（解析成功）| error（fetch 失败 / 解析结构错误，
 *   含重试按钮）| empty（manifest 无条目）。解析结构性错误整体进错误态，
 *   条目级缺陷由 parseManifest 降级不炸。未 init（container 缺失）→
 *   no-op 不抛错（Falsify 兜底）。
 * @returns {Promise<void>}
 */
export async function refreshSimulators() {
    if (!container) return;
    renderLoading();
    try {
        const raw = await fetchManifestText();
        const parsed = parseManifest(raw);
        if (!parsed.ok) {
            renderError(parsed.error);
            return;
        }
        games = parsed.games;
        renderList();
    } catch (err) {
        renderError(err instanceof Error ? err.message : String(err));
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
    'setFetch',
];
