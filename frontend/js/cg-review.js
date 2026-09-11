/**
 * Conver System — 剧情回顾视图（深模块，CG-3）
 *
 * 职责：剧情回顾页的时间线渲染 —— 已解锁 CG + 对应消息片段，按后端
 * cgTimeline 契约序（消息 created_at 升序 + 同消息入库序）拼接，只读视图。
 * 渲染范式对齐 search-view.js（纯函数 + escapeHtml + iconHtml seam）。
 *
 * 依赖方向：cg-review.js → api.js（images.cgTimeline）/ icons.js / utils.js；
 *   app.js → cg-review.js（renderCgTimeline 接线）。无反向依赖。
 *
 * DOM 契约：本模块持有 #cg-timeline 引用；index.html 的 id/class 契约零变更。
 *   模块求值于 DOM 就位之后（type=module 延迟执行）。
 *
 * 协议表面（__all__）：renderCgTimeline / cgImageUrl。
 */

import { images } from './api.js';
import { escapeHtml } from './utils.js';

const $ = (sel) => document.querySelector(sel);

/**
 * CG 图片本地文件路径 → 可加载 URL。
 *
 * 出图结果落盘数据目录 cg/ 子目录（CG-1 本地优先），后端 /cg 静态挂载同目录；
 * result_url 为**本地绝对路径**（如 C:\...\cg\cg_xxx.png），前端取其文件名映射
 * `/cg/<文件名>` 供 <img src> 加载（URL 形态的 result_url 原样返回）。
 * @param {string} url - result_url（本地路径或 URL）
 * @returns {string} 可加载 URL（本地路径 → /cg/<basename>；URL → 原样；空 → ''）
 */
export function cgImageUrl(url) {
    const raw = String(url || '');
    if (/^https?:\/\//.test(raw)) return raw;
    const name = raw.split(/[\\/]/).pop();
    return name ? `/cg/${encodeURIComponent(name)}` : '';
}

/**
 * 渲染剧情回顾时间线（已解锁 CG + 对应消息片段）。
 *
 * @param {number|null} characterId - 归属作品；null → 空态提示（未选角色）
 * @returns {Promise<void>}
 */
export async function renderCgTimeline(characterId) {
    const container = $('#cg-timeline');
    if (!container) return;

    if (characterId == null) {
        container.innerHTML = '<p class="empty-hint">先在聊天中打开一个角色对话，再回顾其剧情 CG</p>';
        return;
    }

    let items;
    try {
        items = await images.cgTimeline(characterId);
    } catch (err) {
        container.innerHTML = `<p class="empty-hint">回顾加载失败: ${escapeHtml(err?.message || String(err))}</p>`;
        return;
    }

    if (!Array.isArray(items) || items.length === 0) {
        container.innerHTML = '<p class="empty-hint">暂无已解锁的 CG 回顾</p>';
        return;
    }

    // 顺序即后端契约（消息 created_at 升序 + 同消息入库序），前端不重排
    container.innerHTML = items.map((item) => `
        <div class="cg-timeline-item">
            <img class="cg-timeline-image" src="${cgImageUrl(item.url)}" alt="" loading="lazy" />
            <p class="cg-timeline-caption">${escapeHtml(item.message_content || '')}</p>
        </div>
    `).join('');
}

export const __all__ = ['renderCgTimeline', 'cgImageUrl'];
