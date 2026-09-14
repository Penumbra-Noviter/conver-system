/**
 * Conver System — Prompt Debug 只读预览面板（PD-4）
 *
 * 打开只读面板展示最终组装后的 prompt 分段（后端 prompt-debug 端点产物），
 * 每条渲染 role 徽标 + 来源色标 + content（等宽预排版，保留换行）。
 * 面板只读：不提供编辑，关闭即弃（openModal 骨架，无持久状态）。
 * 来源 → 色标类名映射收敛到 SOURCE_CLASS 单一映射表（不散落 if/else）。
 *
 * 样式说明：本工单文件范围不含 css/style.css，色标颜色与等宽排版以自包含
 *   <style> 内嵌于面板 body（对齐 mod-css.js「JS 内注入样式」先例）。
 */

import { openModal } from './modal.js';
import { escapeHtml } from '../utils.js';
import { conversations } from '../api.js';

/**
 * 来源 → 色标类名 单一映射表（契约锁 1：色标映射唯一来源，渲染只查表）。
 * 6 类来源（character/world/memory/mod/history/user）各一色，值唯一。
 * @type {Record<string, string>}
 */
export const SOURCE_CLASS = {
    character: 'pd-source-character',
    world: 'pd-source-world',
    memory: 'pd-source-memory',
    mod: 'pd-source-mod',
    history: 'pd-source-history',
    user: 'pd-source-user',
};

/** 非法来源回落默认样式类（契约锁 4） */
export const SOURCE_DEFAULT_CLASS = 'pd-source-default';

/** 来源 → 中文展示标签（与色标映射并列的展示文案；非法值回落默认标签） */
const SOURCE_LABEL = {
    character: '角色',
    world: '世界书',
    memory: '记忆',
    mod: 'Mod',
    history: '历史',
    user: '用户',
};

/** 非法来源回落默认标签 */
const SOURCE_DEFAULT_LABEL = '未知';

/** 面板自包含样式（色标六色 + 等宽预排版 + meta 布局；不改 css/style.css） */
const PANEL_STYLE = `
    .prompt-debug-modal { max-width: 720px; }
    .pd-meta { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px; font-size: 13px; }
    .pd-meta-item { padding: 2px 8px; border-radius: 6px; background: var(--panel-2, #f2f2f2); color: var(--ink-2, #666); }
    .pd-segments { display: flex; flex-direction: column; gap: 10px; }
    .pd-segment { border: 1px solid var(--border, #e2e2e2); border-radius: 8px; overflow: hidden; }
    .pd-segment-meta { display: flex; align-items: center; gap: 6px; padding: 6px 10px; background: var(--panel, #fff); border-bottom: 1px solid var(--border, #e2e2e2); }
    .pd-role-badge { font-size: 11px; font-weight: 600; padding: 1px 7px; border-radius: 4px; background: var(--accent, #4f7cff); color: #fff; text-transform: uppercase; }
    .pd-source-badge { font-size: 11px; padding: 1px 7px; border-radius: 10px; }
    .pd-segment-content { margin: 0; padding: 10px; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 12px; line-height: 1.5; white-space: pre-wrap; word-break: break-word; color: var(--ink-1, #1a1a1a); max-height: 320px; overflow-y: auto; }
    .pd-empty { padding: 24px; text-align: center; color: var(--ink-3, #999); }
    .pd-source-character { background: #e3f2fd; color: #1565c0; }
    .pd-source-world { background: #e8f5e9; color: #2e7d32; }
    .pd-source-memory { background: #f3e5f5; color: #7b1fa2; }
    .pd-source-mod { background: #fff3e0; color: #e65100; }
    .pd-source-history { background: #eceff1; color: #455a64; }
    .pd-source-user { background: #e0f2f1; color: #00695c; }
    .pd-source-default { background: #f5f5f5; color: #616161; }
`;

/**
 * 来源 → 色标类名（非法值回落默认类，不抛错）。
 * 用 Object.hasOwn 防原型链污染键（source='constructor'/'toString' 等不得命中表）。
 * @param {unknown} source - 分段来源（后端枚举，允许 null/undefined/非字符串）
 * @returns {string} 色标 CSS 类名
 */
export function sourceClass(source) {
    return (typeof source === 'string' && Object.hasOwn(SOURCE_CLASS, source))
        ? SOURCE_CLASS[source]
        : SOURCE_DEFAULT_CLASS;
}

/**
 * 来源 → 展示标签（非法值回落默认标签）。
 * @param {unknown} source - 分段来源
 * @returns {string} 来源中文标签
 */
function sourceLabel(source) {
    return (typeof source === 'string' && Object.hasOwn(SOURCE_LABEL, source))
        ? SOURCE_LABEL[source]
        : SOURCE_DEFAULT_LABEL;
}

/**
 * 渲染单条分段：role 徽标 + 来源色标 + 转义后的 content。
 * content/role 均经 escapeHtml（防注入），来源色标类名直接取自 SOURCE_CLASS 表。
 * @param {object} segment - { role, content, source }
 * @returns {string} 分段 HTML
 */
export function segmentHtml(segment) {
    const role = segment?.role ?? '';
    const content = segment?.content ?? '';
    const source = segment?.source ?? '';
    return `
        <div class="pd-segment">
            <div class="pd-segment-meta">
                <span class="pd-role-badge">${escapeHtml(role)}</span>
                <span class="pd-source-badge ${sourceClass(source)}">${escapeHtml(sourceLabel(source))}</span>
            </div>
            <pre class="pd-segment-content">${escapeHtml(content)}</pre>
        </div>`;
}

/**
 * 渲染分段列表 HTML；空/非数组 → 空态提示。
 * @param {Array<object>|null|undefined} segments - 分段数组
 * @returns {string} 列表 HTML（或空态）
 */
export function segmentsHtml(segments) {
    if (!Array.isArray(segments) || segments.length === 0) {
        return '<div class="pd-empty">无分段数据</div>';
    }
    return segments.map(segmentHtml).join('');
}

/**
 * 渲染面板主体 HTML：顶部 meta（角色名/模型/模式）+ 分段列表。
 * meta 三字段均转义（防注入）。
 * @param {object|null|undefined} data - prompt-debug 响应
 * @returns {string} 面板 body HTML
 */
export function promptDebugBodyHtml(data) {
    return `
        <div class="pd-meta">
            <span class="pd-meta-item">角色：${escapeHtml(data?.character_name ?? '')}</span>
            <span class="pd-meta-item">模型：${escapeHtml(data?.model ?? '')}</span>
            <span class="pd-meta-item">模式：${escapeHtml(data?.prompt_mode ?? '')}</span>
        </div>
        <div class="pd-segments">${segmentsHtml(data?.segments)}</div>`;
}

/**
 * 打开 Prompt Debug 只读面板。
 * 拉取 conversations.promptDebug(id) → openModal 渲染；加载失败渲染错误态面板
 * （不抛错）；已有面板时幂等去重（不重复请求）。
 * @param {number|string} conversationId - 会话 id
 * @returns {Promise<void>}
 */
export async function showPromptDebug(conversationId) {
    if (document.getElementById('prompt-debug-overlay')) return;
    let data;
    try {
        data = await conversations.promptDebug(conversationId);
    } catch (err) {
        console.error('加载 Prompt Debug 失败:', err);
        openModal({
            title: 'Prompt Debug',
            modalClass: 'prompt-debug-modal',
            overlayId: 'prompt-debug-overlay',
            body: `<style>${PANEL_STYLE}</style><div class="pd-empty">加载失败</div>`,
        });
        return;
    }
    openModal({
        title: 'Prompt Debug',
        modalClass: 'prompt-debug-modal',
        overlayId: 'prompt-debug-overlay',
        body: `<style>${PANEL_STYLE}</style>${promptDebugBodyHtml(data)}`,
    });
}

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'SOURCE_CLASS',
    'SOURCE_DEFAULT_CLASS',
    'sourceClass',
    'segmentHtml',
    'segmentsHtml',
    'promptDebugBodyHtml',
    'showPromptDebug',
];
