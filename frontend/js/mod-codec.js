/**
 * Conver System — Mod codec 深模块（F-103）
 *
 * Mod 面板的 codec 纯函数单一来源：从 components/mod-manager.js 原样迁入的
 * 8 个纯函数 + 目标区域常量（零行为变化，不改签名不改逻辑）。mod-manager.js
 * 只负责渲染与事件，经由本模块 import 这些符号。
 *
 * 职责划分（单一来源）：
 *   - prompt 区 payload 三区域序列化/解析（serializePromptPayload / parsePromptPayload）
 *   - 表单校验（validateModForm：名称必填 / target_area 收口三值）
 *   - 保存 payload 组装（buildModPayload：与后端 schemas/mods.py ModCreate 逐字段一致）
 *   - 导入导出信封（buildExportEnvelope / parseImportEnvelope / importModsFromEnvelope）
 *   - 挂载排序重排（computeSortSwap：上移/下移产出完整新序 binding_id 数组纯函数）
 *   - TARGET_AREAS：目标区域合法值（与后端 schemas/mods.py Literal 收口一致）
 *
 * 硬约束（Node ESM 真实消费者兼容）：模块顶层零 DOM / 零浏览器 API / 零副作用；
 * 仅 importModsFromEnvelope 经 api.js 的 mods seam 落库（fetch 注入点，不直接触碰
 * DOM），其余函数纯函数（jsdom 与真实浏览器均可直接 import）。
 *
 * 协议表面（__all__）：TARGET_AREAS / serializePromptPayload / parsePromptPayload /
 *   validateModForm / buildModPayload / computeSortSwap / buildExportEnvelope /
 *   parseImportEnvelope / importModsFromEnvelope。
 */

import { mods } from './api.js';

//: 目标区域合法值（与后端 schemas/mods.py Literal 收口一致）
export const TARGET_AREAS = ['prompt', 'memory', 'css'];

// ════════════════════════════════════════════════════════════════
// 纯函数核（可独立单测）
// ════════════════════════════════════════════════════════════════

/**
 * 把 prompt 区三区域内容序列化为 payload 字符串（JSON 三区域）。
 * 键名固定 world / before_char / after_char，与注入链组装消费方约定一致。
 * @param {string} [world] - 世界知识注入
 * @param {string} [beforeChar] - 角色设定前注入
 * @param {string} [afterChar] - 场景设定后注入
 * @returns {string} JSON 字符串
 */
export function serializePromptPayload(world, beforeChar, afterChar) {
    return JSON.stringify({
        world: world ?? '',
        before_char: beforeChar ?? '',
        after_char: afterChar ?? '',
    });
}

/**
 * 解析 payload 字符串为 prompt 区三区域（预填表单用）。
 * 非字符串 / 非法 JSON / 非对象 → 回退全空（不抛，编辑视图不崩溃）。
 * @param {unknown} payload - 存储的 payload
 * @returns {{world: string, before_char: string, after_char: string}}
 */
export function parsePromptPayload(payload) {
    const empty = { world: '', before_char: '', after_char: '' };
    if (typeof payload !== 'string' || payload === '') return empty;
    let data;
    try {
        data = JSON.parse(payload);
    } catch {
        return empty;
    }
    if (data === null || typeof data !== 'object' || Array.isArray(data)) return empty;
    return {
        world: typeof data.world === 'string' ? data.world : '',
        before_char: typeof data.before_char === 'string' ? data.before_char : '',
        after_char: typeof data.after_char === 'string' ? data.after_char : '',
    };
}

/**
 * 表单校验（阻止提交 + 内联错误）。
 * @param {object} form - 表单当前值（{name, target_area, ...}）
 * @returns {{ok: boolean, errors: object}} errors 键=字段名，值=内联错误文案
 */
export function validateModForm(form) {
    const errors = {};
    if (!String(form.name ?? '').trim()) {
        errors.name = '请填写名称';
    }
    if (!TARGET_AREAS.includes(form.target_area)) {
        errors.target_area = '请选择有效目标区域';
    }
    return { ok: Object.keys(errors).length === 0, errors };
}

/**
 * 保存 payload 构建（字段名映射单一来源：与后端 ModCreate 逐字段一致）。
 * prompt 区把三区域序列化为 JSON 字符串存入 payload；memory/css 区为自由文本。
 * @param {object} form - 表单原始值（字符串形态）
 * @returns {{name: string, description: string, target_area: string, payload: string}}
 */
export function buildModPayload(form) {
    const targetArea = TARGET_AREAS.includes(form.target_area) ? form.target_area : 'prompt';
    return {
        name: String(form.name ?? '').trim(),
        description: String(form.description ?? ''),
        target_area: targetArea,
        payload: targetArea === 'prompt'
            ? serializePromptPayload(form.world, form.before_char, form.after_char)
            : String(form.payload ?? ''),
    };
}

/**
 * 组装导出信封（字面 version=1 + mods 数组）。
 * @param {Array} modsList - mods.list() 结果（完整 Mod 对象列表）
 * @returns {{version: number, mods: Array}}
 */
export function buildExportEnvelope(modsList) {
    return { version: 1, mods: Array.isArray(modsList) ? modsList : [] };
}

/**
 * 校验导入信封文本。
 * 非法 JSON / 信封格式错 / version 不符 / mods 非数组 → {ok:false, error}。
 * @param {string} text - 导入文件文本
 * @returns {{ok: boolean, mods: Array, error: string|null}}
 */
export function parseImportEnvelope(text) {
    if (typeof text !== 'string' || text.trim() === '') {
        return { ok: false, mods: [], error: '导入内容为空' };
    }
    let data;
    try {
        data = JSON.parse(text);
    } catch {
        return { ok: false, mods: [], error: '不是合法 JSON' };
    }
    if (data === null || typeof data !== 'object' || Array.isArray(data)) {
        return { ok: false, mods: [], error: '信封格式错误' };
    }
    if (data.version !== 1) {
        return { ok: false, mods: [], error: '版本不符（仅支持 version 1）' };
    }
    if (!Array.isArray(data.mods)) {
        return { ok: false, mods: [], error: 'mods 字段不是数组' };
    }
    return { ok: true, mods: data.mods, error: null };
}

/**
 * 从合法信封逐条落库（source 强制 "imported"，逐条容错：单条失败不阻断其余）。
 * @param {string} text - 导入文件文本
 * @returns {Promise<{ok: boolean, imported: number, failed: number, error: string|null}>}
 */
export async function importModsFromEnvelope(text) {
    const parsed = parseImportEnvelope(text);
    if (!parsed.ok) {
        return { ok: false, imported: 0, failed: 0, error: parsed.error };
    }
    let imported = 0;
    let failed = 0;
    for (const m of parsed.mods) {
        if (m === null || typeof m !== 'object' || Array.isArray(m)) {
            failed += 1;
            continue;
        }
        try {
            await mods.create({
                name: String(m.name ?? ''),
                description: String(m.description ?? ''),
                target_area: TARGET_AREAS.includes(m.target_area) ? m.target_area : 'prompt',
                payload: typeof m.payload === 'string' ? m.payload : '',
                source: 'imported',
            });
            imported += 1;
        } catch {
            failed += 1;
        }
    }
    return { ok: true, imported, failed, error: null };
}

/**
 * 计算上移/下移后的完整挂载顺序（F-102 新契约：产出 binding_id 顺序数组）。
 * 纯函数（不接触 DOM / 不落库），供移动事件处理器与独立单测消费。
 * @param {Array} bindings - 已按 sort_order 升序的绑定列表
 * @param {number} index - 待移动项在列表中的下标
 * @param {'up'|'down'} direction - 移动方向（up=与前一交换，down=与后一交换）
 * @returns {Array<number>} 移动后的完整 binding_id 顺序数组（按新序）；
 *   边界越界（首项上移 / 末项下移 / 下标越界）返回原顺序数组 — 调用方据此 no-op
 */
export function computeSortSwap(bindings, index, direction) {
    if (!Array.isArray(bindings)) return [];
    const ids = bindings.map((b) => b.id);
    const target = direction === 'up' ? index - 1 : index + 1;
    if (index < 0 || index >= bindings.length || target < 0 || target >= bindings.length) {
        return ids;
    }
    const next = [...ids];
    [next[index], next[target]] = [next[target], next[index]];
    return next;
}

// ════════════════════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些符号与 mod-codec.js 交互）
// ════════════════════════════════════════════════════════════════

export const __all__ = [
    'TARGET_AREAS',
    'serializePromptPayload',
    'parsePromptPayload',
    'validateModForm',
    'buildModPayload',
    'computeSortSwap',
    'buildExportEnvelope',
    'parseImportEnvelope',
    'importModsFromEnvelope',
];
