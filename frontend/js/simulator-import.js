/**
 * Conver System — 模拟器导入深模块（工单 04，T-02 决策 9/11）
 *
 * 职责：列表页导入游戏的全部逻辑收口 —— 安全警告确认（「第三方游戏可读取
 *   本地数据并调用 API」，复用 confirm-dialog showConfirm 弹窗体系）、文件
 *   选择 + 拖拽双通道（隐藏 input[type=file] / 列表面板 dragover-drop）、
 *   multipart 上传（doFetch seam + FormData，字段名 `file`，与后端 03 端点
 *   契约对齐）、不确定态「正在导入…」（fetch 无上传进度事件，不用 XHR —
 *   spec 记录判断）、结果反馈（成功 toast + 改名提示 / 409-400 detail 原样
 *   showError / warnings 警告弹窗不拦截 / 未覆盖清单适配提示 + 引导）、
 *   成功后经 onImported 钩子刷新列表。切走 simulators 视图经
 *   resetSimulatorImport() 复位（导入中状态 / 拖拽高亮）。
 *
 * 安全边界（spec：明显恶意模式粗筛命中弹警告不拦截；静态审查不承诺防住，
 *   定位知情提示）：导入内容仅以 file.text() 纯文本读取供未覆盖分析，绝不
 *   eval / 绝不渲染进 DOM；warnings 由后端粗筛返回（键集单源
 *   simulator_store.SUSPICIOUS_PATTERNS），前端只做中文文案映射展示
 *   （WARNING_LABELS 契约单一来源）。
 *
 * 未覆盖提示（spec 决策 11）：上传成功后以已上传 HTML 文本 + 同源 fetch
 *   的覆盖层 CSS 文本（/css/simulator-pc.css — 与运行视图 iframe 相对路径
 *   ../css/simulator-pc.css 同文件同源等价），经 simulator-adapt.js 共享
 *   分析模块（parseCoverageRecords / extractGameClasses / compareCoverage）
 *   运行比对；未覆盖清单（class / var / font 项）非空则弹适配提示并引导
 *   （将 CSS 命名为 `<game-id>.css` 放入数据目录，注入于共享覆盖层之后 —
 *   工单 05）。映射记录缺失项（kind:'record'）为导入游戏预期状态（映射
 *   记录是内置游戏接入把关的契约），过滤不计入提示；覆盖层 fetch 失败
 *   静默跳过（不阻塞导入反馈）。
 *
 * 依赖方向：simulator-import.js → fetch-seam.js（doFetch/setFetch 单一来源
 *   seam）/ simulator-contracts.js（IMPORT_URL / WARNING_LABELS 契约单一
 *   来源）/ simulator-adapt.js（覆盖分析共享模块）/ utils.js（showSuccess /
 *   showError）/ components/confirm-dialog.js（showConfirm 确认弹窗）；
 *   app.js → initSimulatorImport / openImportFlow / resetSimulatorImport
 *   接线（onImported 钩子注入 → refreshSimulators；「导入游戏」按钮经
 *   simulators.js 的 onImportGame 钩子接到 openImportFlow）。
 *
 * DOM 契约：文件选择器为模块自建隐藏 input（append 到 document.body，
 *   accept=".html"）；拖拽目标为 initSimulatorImport 注入的列表面板
 *   （#simulator-list-panel，与 simulators.js 同容器）；导入中不确定态经
 *   容器内 .sim-import-btn 按钮禁用 + 文案「正在导入…」（按钮由
 *   simulators.js 渲染 — 本模块只做状态操作，按钮缺失 no-op 不炸）。
 *
 * 协议表面（__all__）：initSimulatorImport / openImportFlow / importFile /
 *   resetSimulatorImport / setFetch。
 */

import { showConfirm } from './components/confirm-dialog.js';
import { doFetch } from './fetch-seam.js';
import { IMPORT_URL, WARNING_LABELS } from './simulator-contracts.js';
import { parseCoverageRecords, extractGameClasses, compareCoverage } from './simulator-adapt.js';
import { showError, showSuccess } from './utils.js';

// ══════════════════════════════════════════════════
// fetch seam（单一来源 js/fetch-seam.js — 见模块头 docstring；TD-51/55/60）
// ══════════════════════════════════════════════════

export { setFetch } from './fetch-seam.js';

// ══════════════════════════════════════════════════
// 常量与模块级状态（UI 实现细节 — 不属全局应用状态）
// ══════════════════════════════════════════════════

/** 导入上传超时（ms）：5MB 本地上传充裕；到点 abort 通知真实 fetch 断开 */
const IMPORT_TIMEOUT_MS = 30000;

/** 覆盖层 CSS 文本超时（ms）：同源静态文件，秒级完成，仅防御性 */
const COVERAGE_FETCH_TIMEOUT_MS = 5000;

/**
 * 覆盖层 CSS URL（同源 fetch 文本 — 未覆盖分析输入）：与运行视图 iframe 内
 * PC_OVERLAY_HREF = '../css/simulator-pc.css' 指向同一文件（iframe 于
 * /simulators/<file> 下，相对 ../css → /css/；本模块于主页面上下文，绝对
 * /css/ 同源等价）。
 */
const COVERAGE_CSS_URL = '/css/simulator-pc.css';

/** 导入前安全警告弹窗文案（spec：明确警告「第三方游戏可读取本地数据并调用 API」并需确认） */
const WARNING_CONFIRM = {
    title: '导入安全警告',
    message: '第三方游戏可读取本地数据并调用 API',
    detail: '仅导入你信任的游戏文件。导入后该游戏与内置游戏同处同源区域：'
        + '可读取本应用本地数据（含你的 API 凭证）并调用本应用 API 端点。',
    confirmText: '我了解，继续导入',
    cancelText: '取消',
    danger: true,
};

/** 列表面板（拖拽目标 + 导入按钮所在容器；initSimulatorImport 注入；未 init 为 null） */
let container = null;

/** 隐藏文件选择器（initSimulatorImport 创建；未 init 为 null） */
let fileInput = null;

/** 导入完成钩子（app.js 注入 → refreshSimulators；未注入时 no-op 兜底） */
let onImported = () => {};

/** 导入中标志：防并发（在途期间按钮禁用 + 拖拽/再次导入忽略） */
let importing = false;

/** .html 扩展名判据（与后端 03 校验同口径：扩展名 .html，大小写不敏感） */
const HTML_FILE_RE = /\.html$/i;

// ══════════════════════════════════════════════════
// 内部工具（UI 实现细节）
// ══════════════════════════════════════════════════

/**
 * 文件名是否为 .html（大小写不敏感；与后端校验口径一致）。非字符串 name /
 * 缺 name → false（Falsify 防御，不依赖 File instanceof — 拖拽 mock 与
 * 跨环境形态均可）。
 * @param {object} file - 文件对象（File 或 {name: string} 形态）
 * @returns {boolean} 扩展名为 .html 为 true
 */
function isHtmlFile(file) {
    return Boolean(file) && typeof file.name === 'string' && HTML_FILE_RE.test(file.name);
}

/**
 * 设置导入中不确定态：容器内「导入游戏」按钮（simulators.js 渲染）禁用 +
 * 文案「正在导入…」；按钮缺失（未渲染 / 未 init）→ no-op 不炸。
 * @param {boolean} on - true 进入导入中态（禁用 + 文案），false 复位
 */
function setImporting(on) {
    const btn = container?.querySelector('.sim-import-btn');
    if (!btn) return;
    btn.disabled = on;
    btn.textContent = on ? '正在导入…' : '导入游戏';
}

/**
 * 上传文件（multipart POST IMPORT_URL）。到点 abort 通知真实 fetch 断开，
 * 拒绝以 AbortError 上抛（调用方映射中文超时文案）。
 * @param {object} file - 待上传文件（File）
 * @returns {Promise<Response>} fetch 响应
 */
async function uploadFile(file) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), IMPORT_TIMEOUT_MS);
    try {
        const fd = new FormData();
        fd.append('file', file); // 字段名 `file`（后端 03 契约；Content-Type 交浏览器带 boundary）
        return await doFetch(IMPORT_URL, { method: 'POST', body: fd, signal: controller.signal });
    } finally {
        clearTimeout(timer);
    }
}

/**
 * 读取非 2xx 响应的错误 detail（FastAPI HTTPException 形状 { detail: string }）。
 * 非 JSON / 缺 detail / detail 非字符串 → 回退 HTTP 状态码文案。
 * @param {Response} res - 非 2xx 响应
 * @returns {Promise<string>} 面向用户的错误文案（后端 detail 原样 — 409/400 契约）
 */
async function readErrorDetail(res) {
    try {
        const data = await res.json();
        if (data && typeof data.detail === 'string' && data.detail) return data.detail;
    } catch {
        // 非 JSON body（如 500 默认页）→ 状态码兜底
    }
    return `导入失败（HTTP ${res.status}）`;
}

/**
 * 读取文件文本（未覆盖分析输入）。文件无 .text() 方法 / 读取失败 → null
 * （跳过未覆盖提示，不阻塞导入反馈）。
 * @param {object} file - 已上传文件（File）
 * @returns {Promise<string|null>} HTML 文本；不可读返回 null
 */
async function readFileText(file) {
    if (!file || typeof file.text !== 'function') return null;
    try {
        return await file.text();
    } catch {
        return null;
    }
}

/**
 * 导入后 warnings 警告弹窗（spec：命中弹警告不拦截 — 导入已完成，仅知情
 * 提示）。逐项列出中文映射（WARNING_LABELS 契约单一来源）；未知键（后端
 * 新增未联动）兜底展示原始键名。
 * @param {string[]} warnings - 后端粗筛命中键集
 * @returns {Promise<void>} 用户确认后 resolve
 */
async function showWarnings(warnings) {
    const labels = warnings.map((key) => `· ${WARNING_LABELS[key] ?? key}`).join('\n');
    await showConfirm({
        title: '安全警告',
        message: '检测到以下可疑模式（仅提示，导入未拦截）：',
        detail: labels,
        confirmText: '我了解',
        danger: true,
    });
}

/** 未覆盖项 → 一行展示文案（与 scripts/check-simulator-css.mjs renderItem 同风格） */
function renderUncoveredItem(item) {
    if (item.kind === 'class') return `· 类名 ${item.item}`;
    if (item.kind === 'var') return `· 变量 ${item.item}`;
    if (item.kind === 'font') return `· 字号 ${item.item} = ${item.size}`;
    return `· ${item.item}`;
}

/**
 * 读取覆盖层 CSS 文本（同源 fetch，未覆盖分析输入）。到点 abort 通知真实
 * fetch 断开；非 2xx 返回空串（跳过分析）；拒绝上抛（调用方跳过提示）。
 * 手写 controller + setTimeout（与 uploadFile / simulators.js
 * fetchManifestText 同模式 — 不依赖 AbortSignal.timeout，jsdom/浏览器兼容）。
 * @returns {Promise<string>} 覆盖层 CSS 全文；非 2xx 为空串
 */
async function fetchCoverageCssText() {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), COVERAGE_FETCH_TIMEOUT_MS);
    try {
        const res = await doFetch(COVERAGE_CSS_URL, { signal: controller.signal });
        if (res?.ok) return await res.text();
        return '';
    } finally {
        clearTimeout(timer);
    }
}

/**
 * 未覆盖适配提示：以已上传 HTML 文本 + 同源 fetch 的覆盖层 CSS 文本运行
 * simulator-adapt 共享分析，未覆盖清单（class/var/font）非空则弹窗列出并
 * 引导 per-game CSS（`<game-id>.css` 放入数据目录）。
 *
 * 语义边界：映射记录缺失项（kind:'record'）是导入游戏预期状态（映射记录
 * 为内置游戏接入把关契约 — 见 simulator-adapt.js 模块 docstring），过滤
 * 不计入提示（否则任何导入都必弹，验收「为空 → 不弹」不可达）；覆盖层
 * fetch 失败 / 文件文本不可读 → 静默跳过（提示是增强，不阻塞导入反馈）。
 * @param {{id: string}} game - 导入成功返回的 game 条目（id 用于引导文案）
 * @param {string} htmlText - 已上传 HTML 文本
 * @returns {Promise<void>}
 */
async function showAdaptationHint(game, htmlText) {
    let cssText;
    try {
        cssText = await fetchCoverageCssText();
    } catch {
        return; // 覆盖层不可得 → 跳过提示（不阻塞导入反馈）
    }
    if (!cssText) return;
    const coverage = parseCoverageRecords(cssText);
    const items = compareCoverage(extractGameClasses(htmlText), game.id, coverage)
        .filter((item) => item.kind !== 'record');
    if (items.length === 0) return; // 为空 → 不弹
    await showConfirm({
        title: '覆盖层适配提示',
        message: `检测到 ${items.length} 项可能未被阅读覆盖层覆盖：`,
        detail: `${items.map(renderUncoveredItem).join('\n')}\n\n`
            + `引导：如需按此游戏微调样式，将 CSS 命名为「${game.id}.css」放入数据目录，`
            + '即可获得 per-game 覆盖（注入于共享覆盖层之后）。',
        confirmText: '知道了',
    });
}

// ══════════════════════════════════════════════════
// 导入编排（双通道共用：文件选择 change / 拖拽确认后 / 测试直调）
// ══════════════════════════════════════════════════

/**
 * 执行导入（警告确认已完成的前置路径调用 — 按钮路径在选文件前确认、拖拽
 * 路径在 importFile 内确认，两路径各确认一次）。流程：不确定态 → multipart
 * 上传（超时 abort）→ 非 2xx detail 原样展示 / 网络失败可读错误 → 成功：
 * toast（改名含新文件名）→ onImported 钩子刷新列表 → warnings 警告弹窗
 * （不拦截）→ 未覆盖适配提示。
 * @param {object} file - 待导入文件（File）
 * @returns {Promise<void>}
 */
async function doImport(file) {
    if (importing) return; // 防并发（在途期间拖拽 / 再次导入一律忽略）
    importing = true;
    setImporting(true);
    let res;
    try {
        res = await uploadFile(file);
    } catch (err) {
        showError(err?.name === 'AbortError' ? '导入超时，请重试' : `导入失败：${err instanceof Error ? err.message : String(err)}`);
        return;
    } finally {
        setImporting(false); // 上传结算即复位（成功/失败均可重试）
        importing = false;
    }

    if (!res.ok) {
        showError(await readErrorDetail(res));
        return;
    }
    let data;
    try {
        data = await res.json();
    } catch {
        showError('导入响应无效，请重试');
        return;
    }
    if (!data || typeof data !== 'object' || !data.game || typeof data.game !== 'object') {
        showError('导入响应无效，请重试');
        return;
    }

    // 成功反馈：toast（改名提示）→ 刷新列表 → warnings 警告（不拦截）→ 未覆盖提示
    showSuccess(data.renamed ? `导入成功（文件已重命名为 ${data.game.file}）` : '导入成功');
    try {
        await onImported();
    } catch {
        // 列表刷新失败不阻塞后续提示（刷新可经重试按钮恢复）
    }
    if (Array.isArray(data.warnings) && data.warnings.length > 0) {
        await showWarnings(data.warnings);
    }
    const htmlText = await readFileText(file);
    if (htmlText !== null) {
        await showAdaptationHint(data.game, htmlText);
    }
}

// ══════════════════════════════════════════════════
// 对外入口
// ══════════════════════════════════════════════════

/**
 * 初始化模拟器导入：创建隐藏文件选择器（accept=".html"，append 到 body）、
 * 绑定列表面板拖拽事件（dragover 高亮 / dragleave 移除 / drop 入口）、
 * 登记 onImported 钩子。
 *
 * 幂等：重复调用仅更新 onImported 钩子与 container；文件选择器与拖拽监听
 * 只创建/绑定一次（bound 守卫）。container 缺失 → no-op 不抛错（Falsify）。
 * @param {object} [options]
 * @param {HTMLElement} [options.container] - 列表面板（#simulator-list-panel；
 *   拖拽目标 + 导入按钮所在容器）
 * @param {Function} [options.onImported] - () => Promise<void>；导入成功后
 *   调用（app.js 注入 → refreshSimulators；未注入时 no-op 兜底）
 */
export function initSimulatorImport({ container: el, onImported: hook } = {}) {
    if (!el) return;
    container = el;
    if (typeof hook === 'function') onImported = hook;
    if (fileInput) return; // 幂等守卫：已创建则早退（钩子已在上方更新）

    fileInput = document.createElement('input');
    fileInput.type = 'file';
    fileInput.accept = '.html';
    fileInput.hidden = true;
    // 文件选择路径：确认已在前置（openImportFlow 选文件前完成），选中直接
    // 上传 — 不重复弹警告；value 清空允许重复选同一文件
    fileInput.addEventListener('change', () => {
        const file = fileInput.files?.[0];
        fileInput.value = '';
        if (!file) return;
        doImport(file);
    });
    document.body.appendChild(fileInput);

    // 拖拽双通道（目标为列表区整体 — 工单 04 交互决策）：dragover 需
    // preventDefault 才允许 drop（浏览器默认拒绝拖放 HTML 文件）；导入在途
    // 时不高亮（防误导）
    container.addEventListener('dragover', (e) => {
        e.preventDefault();
        if (!importing) container.classList.add('sim-drop-active');
    });
    container.addEventListener('dragleave', () => {
        container.classList.remove('sim-drop-active');
    });
    container.addEventListener('drop', (e) => {
        e.preventDefault();
        container.classList.remove('sim-drop-active');
        if (importing) return; // 导入在途忽略拖拽
        const files = e.dataTransfer?.files ?? [];
        if (files.length > 1) {
            showError('一次只能导入一个文件');
            return;
        }
        if (files.length === 1) importFile(files[0]);
    });
}

/**
 * 「导入游戏」按钮入口（simulators.js onImportGame 钩子接入）：安全警告
 * 确认 → 确认后打开文件选择器（选文件后直接上传，不再重复警告）。
 * 未 init（无文件选择器）→ no-op 不抛错；导入在途 → 忽略。
 * @returns {Promise<void>}
 */
export async function openImportFlow() {
    if (importing || !fileInput) return;
    const ok = await showConfirm(WARNING_CONFIRM);
    if (ok) fileInput.click();
}

/**
 * 拖拽路径入口（单个文件）：.html 校验 → 安全警告确认 → 确认后上传。
 * 非 .html → 明确提示不上传（不弹确认）；确认取消 → 中止。name 缺失 /
 * 非字符串 → 按非 html 拒绝（Falsify）。
 * @param {object} file - 拖入的文件（File）
 * @returns {Promise<void>}
 */
export async function importFile(file) {
    if (!isHtmlFile(file)) {
        showError('仅支持 .html 文件（拖入单个游戏文件）');
        return;
    }
    if (importing) return;
    const ok = await showConfirm(WARNING_CONFIRM);
    if (!ok) return;
    await doImport(file);
}

/**
 * 切走 simulators 视图时复位（app.js switchView 调用）：导入中状态复位
 * （按钮恢复可用，允许重试）、拖拽高亮移除。未 init → no-op 不抛错。
 */
export function resetSimulatorImport() {
    importing = false;
    setImporting(false);
    container?.classList.remove('sim-drop-active');
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 simulator-import.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'initSimulatorImport',
    'openImportFlow',
    'importFile',
    'resetSimulatorImport',
    'setFetch',
];
