/**
 * Conver System — AI 游戏生成器深模块
 *
 * 职责：从用户提供的世界观文本（textarea 粘贴 或 .txt/.md 文件上传）生成
 *   HTML 模拟器游戏。流程：模态框输入 → POST /api/simulators/generate →
 *   成功自动刷新列表 / 校验失败显示错误 + 重试按钮（重试仅重发 description/title）
 *   / LLM 失败显示错误。
 *
 * 依赖方向：game-generator.js → components/modal.js（openModal 骨架）/
 *   components/loading-button.js（beginButtonLoading）/ fetch-seam.js
 *   （doFetch）/ simulator-contracts.js（GENERATE_URL）/ icons.js（iconHtml
 *   图标 seam）/ utils.js（showSuccess / escapeHtml）。
 *
 * 安全边界：上传的文本文件仅以 file.text() 纯文本读取，不 eval 不渲染。
 *
 * 协议表面（__all__）：initGameGenerator / openGenerateFlow /
 *   resetGameGenerator / setFetch。
 */

import { openModal } from './modal.js';
import { beginButtonLoading } from './loading-button.js';
import { doFetch } from '../fetch-seam.js';
import { GENERATE_URL } from '../simulator-contracts.js';
import { iconHtml } from '../icons.js';
import { showSuccess, escapeHtml } from '../utils.js';
// T4 凭证预检：复用 key-injector 既有引导链接文案/选择器常量（避免复制）
import { LINK_NAV_SETTINGS, SEL_NAV_SETTINGS } from '../key-injector.js';

// ══════════════════════════════════════════════════
// fetch seam（单一来源 js/fetch-seam.js）
// ══════════════════════════════════════════════════

export { setFetch } from '../fetch-seam.js';

// ══════════════════════════════════════════════════
// 常量与模块级状态
// ══════════════════════════════════════════════════

/** 生成请求超时（ms）：LLM 生成 + 校验，2 分钟充裕 */
const GENERATE_TIMEOUT_MS = 120000;

/** 允许的文本文件扩展名 */
const TEXT_EXTENSIONS = ['.txt', '.md', '.text'];

/** 文本文件大小上限（10MB） */
const MAX_TEXT_FILE_BYTES = 10 * 1024 * 1024;

/** 描述输入框最大字符数 */
const MAX_DESCRIPTION_LENGTH = 10000;

/** 生成中标志：防并发 */
let generating = false;

/** 生成完成钩子（app.js 注入 → refreshSimulators） */
let onGenerated = () => {};

/** 凭证获取函数（initGameGenerator 注入 getCredentials；T4 凭证预检） */
let fetchCredentials = null;

/** 设置页导航钩子（initGameGenerator 注入 onNavigateSettings；T4 凭证预检设置链接点击） */
let navigateSettings = null;

/** 凭证预检（T4）：none/claude 态模态框顶部提示文案 */
const MSG_NEED_OPENAI_KEY = '需先配置 OpenAI 兼容 Key';

// ══════════════════════════════════════════════════
// 内部工具
// ══════════════════════════════════════════════════

/**
 * 检查文件名是否为文本文件（.txt / .md / .text，大小写不敏感）
 * @param {object} file - 文件对象
 * @returns {boolean}
 */
function isTextFile(file) {
    if (!file || typeof file.name !== 'string') return false;
    const lower = file.name.toLowerCase();
    return TEXT_EXTENSIONS.some((ext) => lower.endsWith(ext));
}

/**
 * 读取文本文件内容
 * @param {object} file - File 对象
 * @returns {Promise<string>}
 */
async function readTextFile(file) {
    if (file.size > MAX_TEXT_FILE_BYTES) {
        throw new Error('文件超过 10MB 上限');
    }
    if (typeof file.text === 'function') {
        return await file.text();
    }
    // 兜底：用 FileReader
    return await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(new Error('文件读取失败'));
        reader.readAsText(file);
    });
}

/**
 * 渲染错误列表 HTML
 * @param {Array<{field: string, message: string}>} errors
 * @param {string} [suggestion]
 * @returns {string} HTML 字符串
 */
function renderErrors(errors, suggestion) {
    const items = errors.map((e) =>
        `<li><strong>${escapeHtml(e.field)}</strong>：${escapeHtml(e.message)}</li>`
    ).join('');
    let html = `<ul class="gg-error-list">${items}</ul>`;
    if (suggestion) {
        html += `<p class="gg-suggestion">${escapeHtml(suggestion)}</p>`;
    }
    return html;
}

// ══════════════════════════════════════════════════
// 模态框构建
// ══════════════════════════════════════════════════

/**
 * 构建生成模态框的 body HTML
 * @param {string} [initialDescription] - 初始描述文本（重试时保留）
 * @param {string} [initialTitle] - 初始标题（重试时保留）
 * @returns {string} body HTML
 */
function buildModalBody(initialDescription, initialTitle) {
    const desc = initialDescription ? escapeHtml(initialDescription) : '';
    const title = initialTitle ? escapeHtml(initialTitle) : '';
    return `<div class="gg-cred-warning" id="gg-cred-warning" hidden></div>
        <div class="form-field">
        <label for="gg-title">游戏名称 <span class="field-hint">（可选）</span></label>
        <input type="text" id="gg-title" maxlength="100" placeholder="例如：霓虹追迹"
            value="${title}">
    </div>
    <div class="form-field">
        <label for="gg-description">世界观设定 <span class="field-required">*</span></label>
        <textarea id="gg-description" rows="8" maxlength="${MAX_DESCRIPTION_LENGTH}"
            placeholder="描述你的世界设定，包括背景、氛围、核心冲突等。越详细，生成的游戏越丰富。&#10;&#10;示例：&#10;在一个被霓虹灯照亮的赛博朋克城市中，你是一名私家侦探。城市被巨型企业控制，&#10;底层市民生活在阴暗的街巷中。一天，你接到一个神秘委托，调查一起数据窃取案，&#10;却逐渐揭开了一个涉及城市最大企业的惊天阴谋。">${desc}</textarea>
        <span class="field-hint">支持模板变量：<code>{{user}}</code>、<code>{{char}}</code></span>
        <span class="field-error" id="gg-desc-error" hidden></span>
    </div>
    <div class="form-field">
        <button type="button" class="btn-secondary" id="gg-upload-btn">
            ${iconHtml('fileText', { size: 16 })} 上传文本文件
        </button>
        <span class="field-hint" style="margin-left:8px">支持 .txt .md .text</span>
        <input type="file" id="gg-file-input" accept=".txt,.md,.text" hidden>
    </div>
    <div id="gg-result-area"></div>`;
}

/**
 * 构建生成模态框的 actions HTML
 * @returns {string} actions HTML
 */
function buildModalActions() {
    return `<button type="button" class="btn-secondary modal-cancel">取消</button>
        <button type="button" class="btn-primary" id="gg-submit-btn">${iconHtml('sparkles', { size: 16 })} 生成游戏</button>`;
}

// ══════════════════════════════════════════════════
// 生成请求
// ══════════════════════════════════════════════════

/**
 * 发送生成请求
 * @param {object} body - { description, title? }
 * @returns {Promise<Response>}
 */
async function sendGenerateRequest(body) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), GENERATE_TIMEOUT_MS);
    try {
        return await doFetch(GENERATE_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
            signal: controller.signal,
        });
    } finally {
        clearTimeout(timer);
    }
}

// ══════════════════════════════════════════════════
// 模态框交互
// ══════════════════════════════════════════════════

/**
 * 渲染错误结果区域（错误头 + 消息/错误列表 + 重试按钮）
 * @param {HTMLElement} resultArea - 结果容器
 * @param {string} title - 错误标题
 * @param {object} opts - { errors?, suggestion?, message? }
 * @param {Function} onRetry - 重试回调
 */
function renderErrorResult(resultArea, title, opts, onRetry) {
    resultArea.className = 'gg-error';
    let html = `<div class="gg-error-header">${iconHtml('warning', { size: 16 })} ${escapeHtml(title)}</div>`;
    if (opts.errors && Array.isArray(opts.errors)) {
        html += renderErrors(opts.errors, opts.suggestion);
    } else if (opts.message) {
        html += `<p class="gg-error-message">${escapeHtml(opts.message)}</p>`;
    }
    html += `<button type="button" class="btn-primary" id="gg-retry-btn">${iconHtml('refresh', { size: 16 })} 重试</button>`;
    resultArea.innerHTML = html;
    const retryBtn = resultArea.querySelector('#gg-retry-btn');
    if (retryBtn) {
        retryBtn.addEventListener('click', onRetry);
    }
}

/**
 * 执行生成（模态框内步骤）
 * @param {object} opts
 * @param {HTMLElement} opts.overlay - 模态框 overlay
 * @param {Function} opts.close - 关闭模态框函数
 * @param {string} opts.description - 世界观描述
 * @param {string} [opts.title] - 游戏标题
 */
async function executeGenerate({ overlay, close, description, title }) {
    if (generating) return;
    generating = true;

    const submitBtn = overlay.querySelector('#gg-submit-btn');
    const resultArea = overlay.querySelector('#gg-result-area');
    const restore = beginButtonLoading(submitBtn, '正在生成…');

    const body = { description };
    if (title && title.trim()) body.title = title.trim();

    // 清空旧结果
    resultArea.innerHTML = '';
    resultArea.className = '';

    try {
        const res = await sendGenerateRequest(body);
        const text = await res.text();

        let data;
        try { data = JSON.parse(text); } catch { data = null; }

        if (res.ok && data && data.ok && data.game) {
            // 成功
            showSuccess('游戏生成成功！');
            try { await onGenerated(); } catch { /* 列表刷新失败不阻塞 */ }
            close();
            return;
        }

        // 校验失败 422 — 显示错误 + 重试按钮
        if (res.status === 422 && data && typeof data.detail === 'object') {
            const d = data.detail;
            if (d && d.ok === false && Array.isArray(d.errors)) {
                renderErrorResult(resultArea, '校验未通过', { errors: d.errors, suggestion: d.suggestion }, () => {
                    executeGenerate({ overlay, close, description, title });
                });
                return;
            }
        }

        // 其他错误
        const msg = data && typeof data.detail === 'string'
            ? data.detail : `生成失败（HTTP ${res.status}）`;
        renderErrorResult(resultArea, '生成失败', { message: msg }, () => {
            executeGenerate({ overlay, close, description, title });
        });
    } catch (err) {
        const msg = err?.name === 'AbortError' ? '生成超时，请重试' : `生成失败：${err instanceof Error ? err.message : String(err)}`;
        renderErrorResult(resultArea, '请求失败', { message: msg }, () => {
            executeGenerate({ overlay, close, description, title });
        });
    } finally {
        restore();
        generating = false;
    }
}

// ══════════════════════════════════════════════════
// 对外入口
// ══════════════════════════════════════════════════

/**
 * 初始化游戏生成器（注册 onGenerated 钩子 + T4 凭证预检钩子）。
 * 幂等：重复调用仅更新钩子。
 * @param {object} [options]
 * @param {Function} [options.onGenerated] - () => Promise<void>；生成成功后
 *   调用（app.js 注入 → refreshSimulators）
 * @param {Function} [options.getCredentials] - () => Promise<{protocol}>；
 *   T4 凭证预检：打开时读取凭证端点（none/claude 态顶部提示；openai 态无提示；
 *   失败降级不阻塞）
 * @param {Function} [options.onNavigateSettings] - () => void；none/claude 态
 *   「前往设置页配置」链接点击时调用（点击 → switchView('settings')）
 */
export function initGameGenerator({ onGenerated: hook, getCredentials, onNavigateSettings } = {}) {
    if (typeof hook === 'function') onGenerated = hook;
    if (typeof getCredentials === 'function') fetchCredentials = getCredentials;
    if (typeof onNavigateSettings === 'function') navigateSettings = onNavigateSettings;
}

/**
 * 打开生成游戏模态框（工具栏按钮/菜单入口）。
 * 已在生成中 → 忽略。
 */
export function openGenerateFlow() {
    if (generating) return;

    const body = buildModalBody();
    const actions = buildModalActions();

    const overlay = openModal({
        title: 'AI 生成游戏',
        modalClass: 'game-gen-modal',
        body,
        actions,
        cancelResult: null,
        removeExisting: '.modal-overlay',
        focusSelector: '#gg-description',
        onOpen: (el, close) => {

            // T4 凭证预检：后台读取凭证端点，none/claude 态注入顶部提示 +
            // 设置链接（复用 key-injector 常量与引导模式）；openai 态无提示；
            // 请求失败静默降级（不阻塞打开、不弹错 — 标注以实测为准）。
            if (typeof fetchCredentials === 'function') {
                fetchCredentials()
                    .then((creds) => {
                        if (!el.isConnected) return; // 模态框已关闭 → 丢弃
                        const protocol = creds?.protocol;
                        if (protocol === 'none' || protocol === 'claude') {
                            const warning = el.querySelector('#gg-cred-warning');
                            if (!warning) return;
                            const navClass = SEL_NAV_SETTINGS.slice(1);
                            warning.hidden = false;
                            warning.innerHTML = `${escapeHtml(MSG_NEED_OPENAI_KEY)} <a href="#" class="${navClass}">${escapeHtml(LINK_NAV_SETTINGS)}</a>`;
                            warning.querySelector(SEL_NAV_SETTINGS)?.addEventListener('click', (e) => {
                                e.preventDefault();
                                if (typeof navigateSettings === 'function') navigateSettings();
                            });
                        }
                    })
                    .catch(() => { /* 降级：静默（不提示、不阻塞、不弹错） */ });
            }

            // 取消按钮绑定关闭
            el.querySelector('.modal-cancel')?.addEventListener('click', () => close());

            // 文件上传按钮
            const uploadBtn = el.querySelector('#gg-upload-btn');
            const fileInput = el.querySelector('#gg-file-input');
            const descTextarea = el.querySelector('#gg-description');
            const descError = el.querySelector('#gg-desc-error');
            const submitBtn = el.querySelector('#gg-submit-btn');
            const titleInput = el.querySelector('#gg-title');

            // 文件上传：点击按钮 → 打开文件选择器
            uploadBtn.addEventListener('click', () => fileInput.click());

            // 文件选择后 → 读取文本填入 textarea
            fileInput.addEventListener('change', async () => {
                const file = fileInput.files?.[0];
                if (!file) return;
                if (!isTextFile(file)) {
                    descError.textContent = '仅支持 .txt、.md、.text 文件';
                    descError.hidden = false;
                    return;
                }
                descError.hidden = true;
                try {
                    const text = await readTextFile(file);
                    descTextarea.value = text;
                    // 自动生成标题（取自文件名除扩展名部分）
                    if (!titleInput.value.trim()) {
                        const stem = file.name.replace(/\.[^.]+$/, '');
                        titleInput.value = stem;
                    }
                } catch (err) {
                    descError.textContent = err instanceof Error ? err.message : '文件读取失败';
                    descError.hidden = false;
                }
                fileInput.value = '';
            });

            // 提交按钮
            submitBtn.addEventListener('click', () => {
                const desc = descTextarea.value.trim();
                if (!desc) {
                    descError.textContent = '请输入世界观设定';
                    descError.hidden = false;
                    descTextarea.focus();
                    return;
                }
                if (desc.length > MAX_DESCRIPTION_LENGTH) {
                    descError.textContent = `描述不能超过 ${MAX_DESCRIPTION_LENGTH} 字`;
                    descError.hidden = false;
                    return;
                }
                descError.hidden = true;
                const title = titleInput.value.trim() || null;
                executeGenerate({ overlay: el, close, description: desc, title });
            });

            // 输入时清除错误提示
            descTextarea.addEventListener('input', () => {
                descError.hidden = true;
            });
        },
    });
}

/**
 * 切走模拟器视图时复位（生成中状态清理）。
 */
export function resetGameGenerator() {
    generating = false;
}

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'initGameGenerator',
    'openGenerateFlow',
    'resetGameGenerator',
    'setFetch',
];