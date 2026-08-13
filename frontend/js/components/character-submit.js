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
 * FE-2 字段语义收口（同域扩展，保持提交链路零改动）：温度滑块配置/格式化、
 * 头像预览、名称必填文案、标签拼接与标签分割同置一处，表单与向导不可漂移：
 *   - TEMP_SLIDER / formatTemperature — 滑块范围刻度 + 两位小数统一显示
 *   - avatarPreviewHtml — 头像预览（img + 加载失败回退 / 「无头像」占位）
 *   - NAME_REQUIRED_MESSAGE — 「角色名称不能为空」文案
 *   - tagsToComma — 标签数组 → 逗号字符串（splitTags 逆操作）
 *
 * form 的 isEdit 差异（update vs create + 成功文案 + 失败恢复文案）与 wizard
 * 恒 create 的差异保留在调用方：本模块不感知 isEdit，成功文案与失败恢复
 * 文案均由调用方传入（逐字保持）。
 */

import { escapeHtml } from '../utils.js';
import { iconHtml } from '../icons.js';
import { avatarImgHtml } from '../format.js';

/**
 * 将逗号分隔的标签文本分割为标签数组（中英文逗号、trim、空项过滤）
 * @param {string|null|undefined} text - 标签文本
 * @returns {string[]} 标签数组（空输入 → []）
 */
export function splitTags(text) {
    return (text ?? '').split(/[,，]/).map((t) => t.trim()).filter(Boolean);
}

/**
 * 将标签数组转为逗号分隔字符串（表单/向导字段显示；splitTags 的逆操作）
 * @param {Array<string>|null|undefined} tags - 标签数组
 * @returns {string} 逗号分隔字符串（空/非数组 → ''）
 */
export function tagsToComma(tags) {
    if (!Array.isArray(tags) || tags.length === 0) return '';
    return tags.join(', ');
}

/**
 * 温度滑块配置常量（表单/向导共用单一来源）
 * min/max/step 决定滑块范围与刻度，default 为温度缺省值（payload 与初始显示共用）
 */
export const TEMP_SLIDER = Object.freeze({
    min: 0,
    max: 2,
    step: 0.05,
    default: 0.7,
});

/**
 * 温度统一格式化（两位小数）：表单与向导初始显示/实时显示一致
 * 非数字输入（'abc'/NaN/Infinity 等）经 Number.isFinite 校验失败后回退
 * TEMP_SLIDER.default（畸形存量数据编辑不显示 NaN）
 * @param {number|string|null|undefined} value - 温度值（缺省/非法 → TEMP_SLIDER.default）
 * @returns {string} 两位小数字符串（如 '0.70'）
 */
export function formatTemperature(value) {
    const num = Number(value ?? TEMP_SLIDER.default);
    return (Number.isFinite(num) ? num : TEMP_SLIDER.default).toFixed(2);
}

/**
 * 头像预览 HTML（表单/向导共用单一实现）
 * 非空 → avatarImgHtml 渲染（alt「头像预览」+ 加载失败回退「图片加载失败」）；
 * 空 → 「无头像」占位（逐字保持既有形态）。
 * @param {string|null|undefined} src - 头像地址
 * @returns {string} 预览容器 HTML
 */
export function avatarPreviewHtml(src) {
    if (!src) return '<span class="avatar-placeholder">无头像</span>';
    return avatarImgHtml(src, '头像预览', "<span class='avatar-placeholder'>图片加载失败</span>");
}

/**
 * 角色名称必填校验文案（表单/向导共用单一来源）
 */
export const NAME_REQUIRED_MESSAGE = '角色名称不能为空';

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
        temperature: Number(fields.temperature ?? TEMP_SLIDER.default),
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
    'splitTags', 'tagsToComma', 'TEMP_SLIDER', 'formatTemperature', 'avatarPreviewHtml',
    'NAME_REQUIRED_MESSAGE', 'buildCharacterPayload', 'beginSubmit', 'succeedSubmit', 'failSubmit',
];
