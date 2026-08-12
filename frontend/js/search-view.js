/**
 * Conver System — 搜索视图（深模块，ARC-9 C1 从 app.js 提取）
 *
 * 职责：搜索视图的全部交互逻辑收口 —— 防抖（searchTimeout 模块级状态迁入）、
 *   五态文案（空输入 / 至少输入 2 个字符 / 搜索中… / 未找到匹配的消息 /
 *   搜索失败: <原因>，逐字保持）、结果渲染（复用 format.js searchResultItemHtml
 *   纯函数 + escapeHtml 转义）、结果点击跳转（经注入的 navigateToConversation
 *   钩子，不反向 import 编排区）。
 *
 * 依赖方向：search-view.js → api.js（messages.search）/ format.js（纯函数）/
 *   utils.js（escapeHtml）；app.js → search-view.js（initSearchView 接线）。
 *   结果跳转经注入钩子（G7 注入钩子模式）：app.js 初始化时传入
 *   navigateToConversation（内部走 activateConversation 统一激活流程）。
 *
 * DOM 契约：本模块持有自身 DOM 引用（#search-input / #search-results /
 *   #btn-search-clear），index.html 的 id/class 契约零变更；模块求值于
 *   DOM 就位之后（type=module 延迟执行），与 chat.js chatDom 同构。
 *   聚焦时序（switchView 内 100ms setTimeout）属视图切换，留在 app.js。
 *
 * 协议表面（__all__）：initSearchView。
 */

import { messages } from './api.js';
import { searchResultItemHtml } from './format.js';
import { escapeHtml } from './utils.js';

// ══════════════════════════════════════════════════
// 搜索视图 DOM 引用（index.html id/class 契约）
// ══════════════════════════════════════════════════

const $ = (sel) => document.querySelector(sel);

const searchInput = $('#search-input');
const searchResults = $('#search-results');
const btnSearchClear = $('#btn-search-clear');

/** 防抖计时器（模块级状态 — 原 app.js searchTimeout 迁入） */
let searchTimeout = null;

/** 结果点击跳转钩子（app.js 接线时注入；缺失时 no-op 兜底） */
let navigateToConversation = () => {};

/**
 * 初始化搜索视图（绑定输入/键盘/清空事件 + 注入结果跳转钩子）。
 * 幂等：重复调用只更新钩子，不重复绑定事件。
 * DOM 元素缺失（index.html 契约被破坏的极端场景）→ no-op 不抛错。
 * @param {object} [options]
 * @param {Function} [options.navigateToConversation] - (conversationId) => void；
 *   搜索结果点击跳转（app.js 注入 activateConversation 统一激活流程）
 */
export function initSearchView({ navigateToConversation: nav } = {}) {
    if (typeof nav === 'function') navigateToConversation = nav;
    if (!searchInput || !searchResults || !btnSearchClear) return;

    // ── 搜索输入事件（防抖 300ms）──
    searchInput.addEventListener('input', () => {
        clearTimeout(searchTimeout);
        searchTimeout = null;
        const q = searchInput.value;
        // 延迟搜索，避免每输入一个字就请求
        searchTimeout = setTimeout(() => performSearch(q), 300);
    });

    searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            clearTimeout(searchTimeout);
            searchTimeout = null;
            performSearch(searchInput.value);
        }
        if (e.key === 'Escape') {
            searchInput.value = '';
            searchInput.blur();
            performSearch('');
        }
    });

    btnSearchClear.addEventListener('click', () => {
        searchInput.value = '';
        searchInput.focus();
        performSearch('');
    });
}

/**
 * 执行搜索并渲染结果（防抖 / Enter / Escape / 清空按钮共用入口）
 * @param {string} query - 搜索关键词
 */
async function performSearch(query) {
    const resultsEl = searchResults;
    query = query.trim();

    if (!query) {
        resultsEl.innerHTML = '<p class="search-hint">输入关键词搜索所有对话中的消息</p>';
        return;
    }

    if (query.length < 2) {
        resultsEl.innerHTML = '<p class="search-status">至少输入 2 个字符</p>';
        return;
    }

    resultsEl.innerHTML = '<p class="search-status">搜索中…</p>';

    try {
        const results = await messages.search(query);
        renderSearchResults(results, query);
    } catch (err) {
        console.error('搜索失败:', err);
        resultsEl.innerHTML = `<p class="search-status search-error">搜索失败: ${escapeHtml(err.message)}</p>`;
    }
}

/**
 * 渲染搜索结果列表
 * @param {Array} results - 搜索结果数组
 * @param {string} query - 原始查询（用于高亮）
 */
function renderSearchResults(results, query) {
    const resultsEl = searchResults;

    if (!results || results.length === 0) {
        resultsEl.innerHTML = '<p class="search-status">未找到匹配的消息</p>';
        return;
    }

    const escapedQuery = escapeHtml(query);

    resultsEl.innerHTML = `
        <p class="search-count">共找到 ${results.length} 条匹配消息</p>
        <div class="search-result-list">
            ${results.map(r => searchResultItemHtml(r, query)).join('')}
        </div>
    `;

    // 点击结果跳转到对应对话（经注入钩子 — 统一激活流程）
    resultsEl.querySelectorAll('.search-result-item').forEach(item => {
        item.addEventListener('click', () => {
            const convId = parseInt(item.dataset.conversationId);
            if (convId) {
                navigateToConversation(convId);
            }
        });
    });
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 search-view.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'initSearchView',
];
