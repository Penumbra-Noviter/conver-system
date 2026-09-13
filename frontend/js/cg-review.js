/**
 * Conver System — 剧情回顾视图（深模块，CG-3/T5）
 *
 * 职责：剧情回顾页的「时间线 | 画廊」双页签视图。
 *   - 时间线：已解锁 CG + 对应消息片段，按后端 cgTimeline 契约序拼接（只读）。
 *   - 画廊：角色全量 CG 网格（未解锁灰态 + unlock_hint + is_special 标记），
 *     支持确认解锁、大图查看与「录入 CG」表单。
 * 渲染范式对齐 search-view.js（纯函数 + escapeHtml + iconHtml seam）。
 *
 * 依赖方向：cg-review.js → api.js（images）/ icons.js / utils.js / tabs.js /
 *   components/confirm-dialog.js / components/modal.js / error-bar.js；
 *   app.js → renderCgTimeline（接线零改动，index.html 零改动）。无反向依赖。
 *
 * DOM 契约：本模块自建页签壳（.cg-tabs）与画廊容器（#cg-gallery），挂在
 *   #cg-timeline 所在 section 内；index.html 的 id/class 契约零变更。
 *   页签 DOM 在 renderCgTimeline 首次调用时自建（幂等，防重绑）。
 *
 * 协议表面（__all__）：renderCgTimeline / renderCgGallery / cgImageUrl。
 */

import { images } from './api.js';
import { escapeHtml } from './utils.js';
import { iconHtml } from './icons.js';
import { openModal } from './components/modal.js';
import { showConfirm } from './components/confirm-dialog.js';
import { renderErrorBar } from './error-bar.js';
import { getActiveTab } from './tabs.js';

const $ = (sel) => document.querySelector(sel);

/**
 * 取当前活动对话的角色 id（画廊/时间线共用同一数据源）。
 * 未选角色时返回 null，调用方走空态。
 * @returns {number|string|null}
 */
function getActiveCharacterId() {
    return getActiveTab()?.characterId ?? null;
}

/**
 * 页签名常量（单一来源，避免散落字面量）。
 */
const TAB_TIMELINE = 'timeline';
const TAB_GALLERY = 'gallery';

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
 * 幂等自建剧情回顾页的页签壳：.cg-tabs（时间线 | 画廊）+ #cg-gallery 容器，
 * 挂在 #cg-timeline 所在 section 内；已存在则不重建、不重复绑事件。
 *
 * @returns {{tabs: HTMLElement, timeline: HTMLElement, gallery: HTMLElement}|null}
 *   缺少 #view-cg 或 #cg-timeline 时返回 null（纯时间线场景，无页签）。
 */
function ensureCgViewShell() {
    const section = $('#view-cg');
    const timeline = $('#cg-timeline');
    if (!section || !timeline || !section.contains(timeline)) return null;

    let tabs = timeline.parentElement?.querySelector('.cg-tabs');
    if (!tabs) {
        tabs = document.createElement('div');
        tabs.className = 'cg-tabs';
        tabs.id = 'cg-tabs';
        tabs.innerHTML = `
            <button type="button" class="cg-tab active" data-cg-tab="${TAB_TIMELINE}">时间线</button>
            <button type="button" class="cg-tab" data-cg-tab="${TAB_GALLERY}">画廊</button>
        `;
        timeline.parentElement.insertBefore(tabs, timeline);

        const gallery = document.createElement('div');
        gallery.className = 'cg-gallery';
        gallery.id = 'cg-gallery';
        gallery.hidden = true;
        timeline.parentElement.insertBefore(gallery, timeline.nextSibling);

        // 页签事件在 cg-review.js 内部自持（spec T5：本票不碰 app.js/chat.js）
        tabs.addEventListener('click', handleCgTabClick);
    }

    return { tabs, timeline, gallery: $('#cg-gallery') };
}

/**
 * 切换页签激活态与面板可见性（不触发数据加载，渲染由调用方负责）。
 * @param {'timeline'|'gallery'} name - 目标页签
 */
function activateCgTab(name) {
    const showGallery = name === TAB_GALLERY;
    const section = $('#cg-timeline')?.parentElement;
    if (!section) return;
    section.querySelectorAll('.cg-tab').forEach((t) => {
        t.classList.toggle('active', t.dataset.cgTab === name);
    });
    const timeline = $('#cg-timeline');
    const gallery = $('#cg-gallery');
    if (timeline) timeline.hidden = showGallery;
    if (gallery) gallery.hidden = !showGallery;
}

/**
 * 页签点击委托：切画廊/时间线并触发对应渲染（角色 id 取自当前活动 tab）。
 * @param {Event} e - click 事件
 */
function handleCgTabClick(e) {
    const tab = e.target.closest('.cg-tab');
    if (!tab) return;
    const characterId = getActiveCharacterId();
    if (tab.dataset.cgTab === TAB_GALLERY) {
        activateCgTab(TAB_GALLERY);
        renderCgGallery(characterId);
    } else {
        activateCgTab(TAB_TIMELINE);
        renderCgTimeline(characterId);
    }
}

/**
 * 渲染单张 CG 网格项。
 *
 * 关键安全语义（Falsify）：未解锁项**不加载原图 src**（渲染灰态占位），
 * 仅已解锁项加载原图 —— 不泄露未解锁 CG 内容。
 * @param {object} item - CgImage 响应行
 * @returns {string} 网格项 HTML
 */
function renderCgTile(item) {
    const unlocked = Boolean(item.unlocked);
    const special = Boolean(item.is_special);
    const group = escapeHtml(item.group_name || '默认分组');
    const weight = escapeHtml(String(item.weight ?? 100));
    const hint = escapeHtml(item.unlock_hint || '');
    const cgId = escapeHtml(String(item.id ?? ''));
    const characterId = escapeHtml(String(item.character_id ?? ''));

    const specialMark = special
        ? `<span class="cg-tile-special" title="特殊 CG">${iconHtml('sparkles', { size: 14 })}</span>`
        : '';
    const hintHtml = !unlocked && hint ? `<p class="cg-tile-hint">${hint}</p>` : '';

    // 锁定态：灰态占位（不设 src）；已解锁态：加载原图。
    const media = unlocked
        ? `<img class="cg-tile-image" src="${escapeHtml(cgImageUrl(item.url))}" alt="" loading="lazy" />`
        : `<div class="cg-tile-placeholder">${iconHtml('pin', { size: 20 })}</div>`;

    const action = unlocked
        ? `<button type="button" class="cg-tile-action" data-cg-action="view" data-cg-id="${cgId}" title="查看大图">${iconHtml('search', { size: 16 })}</button>`
        : `<button type="button" class="cg-tile-action" data-cg-action="unlock" data-cg-id="${cgId}" title="解锁">${iconHtml('check', { size: 16 })}</button>`;

    return `
        <div class="${unlocked ? 'cg-tile cg-tile-unlocked' : 'cg-tile cg-tile-locked'}" data-cg-id="${cgId}" data-cg-character="${characterId}">
            <div class="cg-tile-img-wrap">
                ${specialMark}
                ${media}
            </div>
            <div class="cg-tile-meta">
                <span class="cg-tile-group">${group}</span>
                <span class="cg-tile-weight">权重 ${weight}</span>
                ${hintHtml}
            </div>
            ${action}
        </div>`;
}

/**
 * 渲染「录入 CG」表单（提交走 images.create；校验失败走 error-bar 通道）。
 * @param {number|string} characterId - 归属作品
 * @returns {string} 表单 HTML
 */
function renderCgForm(characterId) {
    return `
        <form class="cg-create-form" data-cg-character="${escapeHtml(String(characterId ?? ''))}">
            <input type="text" name="url" placeholder="图片 URL 或本地路径" data-cg-field="url" />
            <input type="text" name="group_name" placeholder="分组" data-cg-field="group_name" />
            <input type="number" name="weight" placeholder="权重（默认 100）" data-cg-field="weight" min="0" />
            <input type="text" name="unlock_hint" placeholder="解锁提示" data-cg-field="unlock_hint" />
            <label class="cg-create-special"><input type="checkbox" name="is_special" data-cg-field="is_special" /> 特殊 CG</label>
            <button type="submit" class="cg-create-submit">录入 CG</button>
            <p class="cg-create-error" data-cg-field="url-error"></p>
        </form>`;
}

/**
 * 渲染画廊网格（全量 CG，id 降序；锁定项灰态 + unlock_hint + is_special）。
 *
 * @param {number|string|null} characterId - 归属作品；null → 空态（不请求）
 * @returns {Promise<void>}
 */
export async function renderCgGallery(characterId) {
    ensureCgViewShell();
    const container = $('#cg-gallery');
    if (!container) return;

    if (characterId == null) {
        container.innerHTML = '<p class="empty-hint">先在聊天中打开一个角色对话，再回顾其剧情 CG</p>';
        return;
    }

    let items;
    try {
        items = await images.list(characterId);
    } catch (err) {
        container.innerHTML = '<p class="empty-hint">画廊加载失败</p>';
        renderErrorBar({
            container: container.parentElement,
            message: err?.message || '画廊加载失败',
            protocol: null,
            onNavigateSettings: null,
        });
        return;
    }

    if (!Array.isArray(items)) items = [];
    // 后端已按 id 降序返回；前端保持契约，不做二次排序（确定性）
    const grid = items.map(renderCgTile).join('');
    container.innerHTML = `${renderCgForm(characterId)}${grid}`;
    bindCgGalleryEvents(container);
}

/**
 * 绑定画廊容器事件委托（点击解锁/查看大图 + 表单提交）。幂等：同一容器只绑一次。
 * @param {HTMLElement} container - #cg-gallery 容器
 */
function bindCgGalleryEvents(container) {
    if (container._cgGalleryBound) return;
    container._cgGalleryBound = true;
    container.addEventListener('click', handleCgGalleryClick);
    container.addEventListener('submit', handleCgCreateSubmit);
}

/**
 * 渲染剧情回顾时间线（已解锁 CG + 对应消息片段）。
 * 首次调用自建页签壳并默认激活时间线（app.js 进入视图时既有调用语义不变）。
 *
 * @param {number|string|null} characterId - 归属作品；null → 空态提示（未选角色）
 * @returns {Promise<void>}
 */
export async function renderCgTimeline(characterId) {
    const shell = ensureCgViewShell();
    if (shell) activateCgTab(TAB_TIMELINE);

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

/**
 * 画廊网格点击委托：解锁 / 查看大图。
 * @param {Event} e - click 事件
 */
function handleCgGalleryClick(e) {
    const actionEl = e.target.closest('[data-cg-action]');
    if (!actionEl) return;
    const tile = actionEl.closest('.cg-tile');
    const cgId = Number(tile?.dataset.cgId);
    const characterId = Number(tile?.dataset.cgCharacter);
    const action = actionEl.dataset.cgAction;
    // 防御：actionEl 脱离 .cg-tile 时 dataset 缺省 → NaN，静默 no-op（当前渲染不可达）
    if (Number.isNaN(cgId) || Number.isNaN(characterId)) return;

    if (action === 'unlock') {
        handleUnlock(cgId, characterId);
    } else if (action === 'view') {
        handleView(cgId);
    }
}

/**
 * 录入表单提交：校验 URL 非空 → images.create → 刷新画廊（新条目锁定态在前）。
 * @param {Event} e - submit 事件
 */
async function handleCgCreateSubmit(e) {
    e.preventDefault();
    const form = e.target;
    if (!form || !form.matches?.('.cg-create-form')) return;
    const characterId = Number(form.dataset.cgCharacter);
    const url = (form.querySelector('[data-cg-field="url"]')?.value || '').trim();

    if (!url) {
        const error = form.querySelector('[data-cg-field="url-error"]');
        if (error) error.textContent = 'URL 不能为空';
        renderErrorBar({
            container: form.parentElement,
            message: 'URL 不能为空',
            protocol: null,
            onNavigateSettings: null,
        });
        return;
    }

    const data = {
        url,
        group_name: (form.querySelector('[data-cg-field="group_name"]')?.value || '').trim(),
        weight: Number(form.querySelector('[data-cg-field="weight"]')?.value || 100),
        unlock_hint: (form.querySelector('[data-cg-field="unlock_hint"]')?.value || '').trim(),
        is_special: form.querySelector('[data-cg-field="is_special"]')?.checked ?? false,
    };

    try {
        await images.create(characterId, data);
        await renderCgGallery(characterId);
    } catch (err) {
        renderErrorBar({
            container: form.parentElement,
            message: err?.message || '录入失败',
            protocol: null,
            onNavigateSettings: null,
        });
    }
}

/**
 * 确认解锁：showConfirm → images.unlock → 成功后原地将该 tile 刷新为已解锁态。
 * @param {number} cgId - CG id
 * @param {number} characterId - 归属作品（未用于请求，保留语义清晰）
 */
async function handleUnlock(cgId, characterId) {
    const confirmed = await showConfirm({
        title: '解锁 CG',
        message: '确定要解锁这张 CG 吗？',
        confirmText: '解锁',
        cancelText: '取消',
    });
    if (!confirmed) return;

    try {
        const cg = await images.unlock(cgId);
        // 原地局部刷新该项为已解锁态（不重 list，避免整表刷新）
        const tile = document.querySelector(`#cg-gallery .cg-tile[data-cg-id="${cgId}"]`);
        if (tile) tile.outerHTML = renderCgTile({ ...cg, unlocked: true });
    } catch (err) {
        renderErrorBar({
            container: $('#cg-gallery')?.parentElement ?? document.body,
            message: err?.message || '解锁失败',
            protocol: null,
            onNavigateSettings: null,
        });
    }
}

/**
 * 查看大图：轻量 overlay（复用 openModal），url 取已映射的网格图 src。
 * @param {number} cgId - CG id
 */
function handleView(cgId) {
    const tile = document.querySelector(`#cg-gallery .cg-tile[data-cg-id="${cgId}"]`);
    const img = tile?.querySelector('.cg-tile-image');
    const url = img?.getAttribute('src') || '';
    if (!url) return;
    openModal({
        title: 'CG 大图',
        body: `<div class="cg-lightbox"><img src="${escapeHtml(url)}" alt="" /><button type="button" class="cg-lightbox-close" title="关闭">${iconHtml('x', { size: 18 })}</button></div>`,
        actions: '',
        closeOnBackdrop: true,
        onOpen: (overlay) => {
            overlay.querySelector('.cg-lightbox-close')?.addEventListener('click', () => overlay.remove());
        },
    });
}

export const __all__ = ['renderCgTimeline', 'renderCgGallery', 'cgImageUrl'];
