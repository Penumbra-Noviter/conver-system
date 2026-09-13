/**
 * Conver System — css 区 Mod 前端注入 seam（spec T4）
 *
 * 职责：把角色挂载的 `target_area="css"` Mod payload 注入对话视图。
 *   - applyCharacterCss(characterId)：拉取该角色绑定 → 两段式客户端关联 Mod 库
 *     （ModBindingResponse 不嵌套 Mod 详情 —— 既有契约，前端按 mod_id 关联）→
 *     过滤 enabled && target_area==='css' → 按 binding sort_order 升序以 '\n'
 *     拼接 → 注入 `<style id="mod-css-active">` 挂 document.head。
 *   - removeCharacterCss()：移除该节点（无节点 no-op）。
 *
 * 信任模型（ADR D2 / spec Out of Scope）：payload 零转义、零选择器前缀改写 ——
 *   本地信任级别与 per-game CSS 相同。注入通道用 style.textContent 赋值，
 *   payload 不参与 HTML 解析，DOM 结构不被 payload 撑破。
 *
 * 幂等与竞态：模块持有单调递增令牌 —— 每次 apply/remove 使更早的在途 apply
 *   失效，任意调用序列后至多存在一个 `#mod-css-active` 节点，且迟到完成
 *   （旧角色取数晚归）不会覆盖最新一次 apply/remove 的结果。
 *
 * 失败语义：取数/网络失败静默降级（console.error 记录），apply 不向调用方抛出
 *   （resolve false），不阻塞会话打开；失败时既有节点保持原状（最后已知状态）。
 *
 * 依赖方向：mod-css.js → api.js（只 import 既有 mods.listCharacterMods / mods.list）；
 *   chat.js → mod-css.js（会话生命周期接线）。
 */

import { mods } from './api.js';

/** style 节点 id（幂等标记 —— 重复注入先移除旧节点） */
const STYLE_ID = 'mod-css-active';

/** 单调递增调用令牌：每次 apply/remove 递增；在途 apply 完成时令牌不符即丢弃 */
let callToken = 0;

/**
 * 拉取并拼接角色 css Mod payload（两段式客户端关联）。
 * @param {number|string} characterId - 角色 id
 * @returns {Promise<string>} 按 binding sort_order 升序 '\n' 拼接的 CSS 文本
 *   （无命中 → ''）；取数失败向上抛出（由 applyCharacterCss 捕获降级）
 */
async function collectCssPayloads(characterId) {
    // 两段式：bindings 不嵌套 Mod 详情（ModBindingResponse 契约）→ 并行拉取 Mod 库关联
    const [bindings, library] = await Promise.all([
        mods.listCharacterMods(characterId),
        mods.list(),
    ]);
    const modById = new Map((Array.isArray(library) ? library : []).map((m) => [m.id, m]));
    return (Array.isArray(bindings) ? bindings : [])
        .filter((b) => b && b.enabled && modById.has(b.mod_id))
        .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0))
        .map((b) => modById.get(b.mod_id))
        .filter((m) => m.target_area === 'css' && typeof m.payload === 'string')
        .map((m) => m.payload)
        .filter((p) => p.trim() !== '')
        .join('\n');
}

/**
 * 移除 style 节点（不动调用令牌 —— 供 apply 内部复用）
 * @private
 */
function removeStyleNode() {
    document.getElementById(STYLE_ID)?.remove();
}

/**
 * 拉取并注入角色 css Mod payload（`<style id="mod-css-active">`，id 幂等）
 *
 * 空 payload（无 css Mod / 全禁用 / 空白）→ 不注入（若已有节点则移除，保证
 *   「apply 后节点存在 ⇔ 本次拉到非空 payload」的自洽语义）。
 *
 * @param {number|string} characterId - 角色 id
 * @returns {Promise<boolean>} 是否实际注入了节点（空 payload / 取数失败 /
 *   被更新的 apply·remove 取代 → false；从不 reject）
 */
export async function applyCharacterCss(characterId) {
    const token = ++callToken;
    if (characterId == null) {
        // 防御：无有效角色 id → 视为无 css 可用（清残留，不发起请求）
        removeStyleNode();
        return false;
    }
    let css;
    try {
        css = await collectCssPayloads(characterId);
    } catch (err) {
        console.error('加载 css Mod 失败:', err);
        return false; // 静默降级：不注入、不抛出；既有节点保持原状
    }
    if (token !== callToken) return false; // 已被更新的 apply/remove 取代 → 丢弃迟到结果
    removeStyleNode();
    if (!css.trim()) return false;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = css; // textContent 赋值：payload 不经 HTML 解析，DOM 结构不破
    document.head.appendChild(style);
    return true;
}

/**
 * 移除 css Mod 样式节点；无节点时 no-op。同时使在途 apply 失效
 * （先 remove 后到的旧 apply 不得把样式再注入回来）。
 */
export function removeCharacterCss() {
    callToken += 1;
    removeStyleNode();
}

export const __all__ = ['applyCharacterCss', 'removeCharacterCss'];
