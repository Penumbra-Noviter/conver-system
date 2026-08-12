/**
 * Conver System — 角色提交域深模块（ARC-10 C4）
 *
 * 收敛角色表单（创建/编辑）与创建向导共有的保存行为，单一事实来源：
 *   1. splitTags — 标签中英文逗号分割（form/wizard 两处调用替换）
 *   2. buildCharacterPayload — 11 字段角色 payload 组装（字段名/空值语义逐字：
 *      avatar 空 → null、creator 默认空串、temperature 数值类型、其余文本字段
 *      字符串可空串、tags 数组）
 *   3. 提交态状态机 — 按钮禁用/「保存中…」/状态栏 class/成功 600ms 延时关窗/
 *      失败恢复
 *
 * form 的 isEdit 差异（update vs create + 成功文案 + 失败恢复文案）与 wizard
 * 恒 create 的差异保留在调用方：本模块不感知 isEdit，成功文案与失败恢复
 * 文案均由调用方传入（逐字保持）。
 */

import { escapeHtml } from '../utils.js';
import { iconHtml } from '../icons.js';

/**
 * 将逗号分隔的标签文本分割为标签数组（中英文逗号、trim、空项过滤）
 * @param {string|null|undefined} text - 标签文本
 * @returns {string[]} 标签数组（空输入 → []）
 */
export function splitTags(text) {
    return (text ?? '').split(/[,，]/).map((t) => t.trim()).filter(Boolean);
}

/**
 * 从显式字段对象构造 11 字段角色 payload（API 请求体契约）
 *
 * 空值语义（与现状逐字一致）：`avatar` 空/falsy → null；`creator` 缺省 → 空串；
 * `temperature` 归一为数值（缺省 0.7）；`name/description/personality/first_mes/
 * scenario/mes_example/system_prompt` 为字符串（可空串）；`tags` 为数组（非数组 → []）。
 * 字段顺序无契约要求，字段集与空值语义是契约。
 *
 * @param {object} [fields={}] - 字段对象（name/description/personality/first_mes/
 *   scenario/mes_example/system_prompt/temperature/avatar/creator/tags）
 * @returns {object} 11 字段 payload
 */
export function buildCharacterPayload(fields = {}) {
    return {
        name: fields.name ?? '',
        description: fields.description ?? '',
        personality: fields.personality ?? '',
        first_mes: fields.first_mes ?? '',
        scenario: fields.scenario ?? '',
        mes_example: fields.mes_example ?? '',
        system_prompt: fields.system_prompt ?? '',
        temperature: Number(fields.temperature ?? 0.7),
        avatar: fields.avatar || null,
        creator: fields.creator ?? '',
        tags: Array.isArray(fields.tags) ? fields.tags : [],
    };
}

/**
 * 进入提交中状态：按钮禁用 + 「保存中…」+ 状态栏清空 + class 复位
 * （disabled 即防重复提交守卫）
 * @param {HTMLButtonElement} btn - 提交按钮
 * @param {HTMLElement} statusEl - 状态栏元素（.form-status）
 */
export function beginSubmit(btn, statusEl) {
    btn.disabled = true;
    btn.textContent = '保存中…';
    statusEl.textContent = '';
    statusEl.className = 'form-status';
}

/**
 * 提交成功：success class + 成功文案 + 600ms 延时关窗 + onSuccess（延时逐字保持）
 * @param {HTMLElement} statusEl - 状态栏元素（.form-status）
 * @param {string} successMsgHtml - 成功文案 HTML（调用方传，逐字保持）
 * @param {function} close - 关闭弹窗的回调（工厂 close）
 * @param {function|null} [onSuccess=null] - 保存成功后的回调
 */
export function succeedSubmit(statusEl, successMsgHtml, close, onSuccess = null) {
    statusEl.innerHTML = successMsgHtml;
    statusEl.className = 'form-status success';
    setTimeout(() => {
        close();
        if (onSuccess) onSuccess();
    }, 600);
}

/**
 * 提交失败：error class + x 图标 + 转义后的错误原因 + 按钮恢复
 * @param {HTMLButtonElement} btn - 提交按钮
 * @param {HTMLElement} statusEl - 状态栏元素（.form-status）
 * @param {Error} err - 错误对象（展示 err.message，HTML 转义）
 * @param {string} restoreLabel - 按钮恢复文案（form isEdit 差异的出口）
 */
export function failSubmit(btn, statusEl, err, restoreLabel) {
    statusEl.innerHTML = `${iconHtml('x', { size: 14 })} ${escapeHtml(err.message)}`;
    statusEl.className = 'form-status error';
    btn.disabled = false;
    btn.textContent = restoreLabel;
}

export const __all__ = [
    'splitTags', 'buildCharacterPayload', 'beginSubmit', 'succeedSubmit', 'failSubmit',
];
