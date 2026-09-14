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
 * 采样参数滑块配置常量（SP-3，表单/向导共用单一来源）
 *
 * top_p / presence_penalty / frequency_penalty 为 OpenAI 系采样参数，default
 * 与 OpenAI API 默认一致（top_p=1 / presence=0 / frequency=0）——透传默认值
 * 等价于「不设置」，故用固定滑块（非 None）。max_tokens 无通用默认（不同模型
 * 不同），走「空输入 = null = 不覆盖 provider 默认」语义，由数字输入承载。
 */
export const SAMPLING_SLIDERS = Object.freeze({
    top_p: { min: 0, max: 1, step: 0.05, default: 1.0 },
    presence_penalty: { min: -2, max: 2, step: 0.1, default: 0.0 },
    frequency_penalty: { min: -2, max: 2, step: 0.1, default: 0.0 },
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
 * 采样参数统一格式化（两位小数）：表单/向导初始显示/实时显示一致
 * @param {number|string|null|undefined} value - 采样值（缺省/非法 → 该 key 的 default）
 * @param {string} key - SAMPLING_SLIDERS 的键（top_p / presence_penalty / frequency_penalty）
 * @returns {string} 两位小数字符串
 */
export function formatSampling(value, key) {
    const cfg = SAMPLING_SLIDERS[key];
    const num = Number(value ?? cfg.default);
    return (Number.isFinite(num) ? num : cfg.default).toFixed(2);
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
 * 备用开场白数量上限（对齐对标站 ≤10，PD-2）
 */
export const MAX_ALTERNATE_GREETINGS = 10;

/**
 * 归一化备用开场白列表（编辑面板回填 / 防脏数据）
 *
 * 逐项 trim → 过滤空项 → 去重（保持首次出现顺序）→ 截断至上限
 * MAX_ALTERNATE_GREETINGS。非数组输入 → []（与 tags 归一化一致）。
 * @param {Array<string>|null|undefined} list - 备用开场白列表
 * @returns {string[]} 归一化后的列表（长度 ≤ 上限）
 */
export function normalizeAlternateGreetings(list) {
    if (!Array.isArray(list)) return [];
    const seen = new Set();
    const out = [];
    for (const raw of list) {
        if (out.length >= MAX_ALTERNATE_GREETINGS) break;
        const text = typeof raw === 'string' ? raw.trim() : '';
        if (!text || seen.has(text)) continue;
        seen.add(text);
        out.push(text);
    }
    return out;
}

/**
 * 尝试向备用开场白列表追加一条（表单/向导共用单一来源）
 *
 * trim 后为空 / 与既有项重复 / 已达上限 → 返回归一化后的当前列表（不追加）；
 * 成功 → 返回追加后的新数组（长度 ≤ 上限）。非数组输入视作 []。
 * @param {Array<string>|null|undefined} list - 当前列表
 * @param {string} value - 待添加文本
 * @returns {string[]} 追加后的列表（不可变，失败时返回当前列表副本）
 */
export function addAlternateGreeting(list, value) {
    const current = normalizeAlternateGreetings(list);
    const text = typeof value === 'string' ? value.trim() : '';
    if (!text || current.length >= MAX_ALTERNATE_GREETINGS || current.includes(text)) {
        return current;
    }
    return [...current, text];
}

/**
 * 备用开场白行 HTML（表单/向导共用单一来源，消除两处模板重复）
 * @param {Array<string>|null|undefined} list - 备用开场白数组
 * @returns {string} 行 HTML（空/非数组 → ''）
 */
export function alternateGreetingRowsHtml(list) {
    if (!Array.isArray(list)) return '';
    return list.map((g) => `
        <div class="alt-greeting-row">
            <input type="text" class="alt-greeting-input" value="${escapeHtml(g)}">
            <button type="button" class="btn-icon alt-greeting-remove" title="删除备用开场白">${iconHtml('x', { size: 14 })}</button>
        </div>
    `).join('');
}

/**
 * 从显式字段对象构造 18 字段角色 payload（API 请求体契约）
 *
 * 空值语义（与现状逐字一致）：`avatar` 空/falsy → null；`creator` 缺省 → 空串；
 * `temperature` 归一为数值（缺省 0.7）；`name/description/personality/first_mes/
 * scenario/mes_example/system_prompt` 为字符串（可空串）；`tags` 为数组（非数组 → []）。
 * `prompt_mode` 归一为二值（非 'expert' → 'simple'）；`expert_prompt` 非字符串 → 空串。
 * 字段顺序无契约要求，字段集与空值语义是契约。
 *
 * @param {object} [fields={}] - 字段对象（name/description/personality/first_mes/
 *   scenario/mes_example/system_prompt/temperature/avatar/creator/tags/
 *   prompt_mode/expert_prompt）
 * @returns {object} 18 字段 payload
 */
export function buildCharacterPayload(fields = {}) {
    // max_tokens 无通用默认（不同模型不同）：空/非法/越界 → null（不覆盖 provider 默认）
    const rawMaxTokens = Number(fields.max_tokens);
    const maxTokens = Number.isFinite(rawMaxTokens) && rawMaxTokens >= 1 ? rawMaxTokens : null;
    return {
        name: fields.name ?? '',
        description: fields.description ?? '',
        personality: fields.personality ?? '',
        first_mes: fields.first_mes ?? '',
        scenario: fields.scenario ?? '',
        mes_example: fields.mes_example ?? '',
        system_prompt: fields.system_prompt ?? '',
        temperature: Number(fields.temperature ?? TEMP_SLIDER.default),
        top_p: Number(fields.top_p ?? SAMPLING_SLIDERS.top_p.default),
        presence_penalty: Number(fields.presence_penalty ?? SAMPLING_SLIDERS.presence_penalty.default),
        frequency_penalty: Number(fields.frequency_penalty ?? SAMPLING_SLIDERS.frequency_penalty.default),
        max_tokens: maxTokens,
        avatar: fields.avatar || null,
        creator: fields.creator ?? '',
        tags: Array.isArray(fields.tags) ? fields.tags : [],
        alternate_greetings: Array.isArray(fields.alternate_greetings) ? fields.alternate_greetings : [],
        prompt_mode: fields.prompt_mode === 'expert' ? 'expert' : 'simple',
        expert_prompt: fields.expert_prompt ?? '',
    };
}

/**
 * 从结构化字段拼接专家模式整段 PROMPT（PD-6「从当前字段生成」）
 *
 * 拼接顺序固定：首段取 `system_prompt`（非空优先，空则回落 `personality`），
 * 依次追加 `scenario`、`post_history_instructions`，非空段以两个换行分隔；
 * 全空 → 空串。各字段先 trim；非字符串（null/undefined/对象/数字）视为空段。
 *
 * @param {object} [fields={}] - 字段对象（system_prompt/personality/scenario/post_history_instructions）
 * @returns {string} 拼接后的整段 prompt（全空 → ''）
 */
export function buildExpertPrompt(fields = {}) {
    const source = fields && typeof fields === 'object' && !Array.isArray(fields) ? fields : {};
    const text = (value) => (typeof value === 'string' ? value.trim() : '');
    const head = text(source.system_prompt) || text(source.personality);
    const scenario = text(source.scenario);
    const postHistory = text(source.post_history_instructions);
    return [head, scenario, postHistory].filter(Boolean).join('\n\n');
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
    'splitTags', 'tagsToComma', 'TEMP_SLIDER', 'SAMPLING_SLIDERS', 'formatTemperature',
    'formatSampling', 'avatarPreviewHtml', 'NAME_REQUIRED_MESSAGE', 'MAX_ALTERNATE_GREETINGS',
    'normalizeAlternateGreetings', 'addAlternateGreeting', 'alternateGreetingRowsHtml',
    'buildCharacterPayload', 'buildExpertPrompt', 'beginSubmit', 'succeedSubmit', 'failSubmit',
];
