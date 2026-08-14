/**
 * Conver System — 模拟器 Key 注入模块（深模块，U8-T2）
 *
 * 职责：运行视图「使用主应用 Key」按钮的注入交互收口 —— 凭证获取（经
 *   initKeyInjector 注入钩子，G7 模式：app.js 接 settings.credentials()）、
 *   按钮态解析（resolveButtonState：openai / claude / none 三态纯函数）、
 *   config 三元组完整性校验（hasConfigTriplet 纯函数）、同源 iframe 配置
 *   面板填值 + 派发 input/change（injectCredentialsIntoGame 纯函数 — 只
 *   依赖文档参数，不依赖 iframe 元素）、按钮反馈状态机（成功「已填入」
 *   2s / claude·none 禁用文案 / 失败静默降级），attachKeyInject 把交互挂到
 *   simulator-view.js 渲染的按钮条（.sim-key-bar）上。
 *
 * 注入安全（TD-57 信任边界评估 — spec「U8 注入交互」决策 D 落点）：
 *   威胁模型：22 款游戏与主应用同源运行，游戏脚本可读主应用 localStorage
 *   （含用户自填的 key）并可调 /api 任意端点（后端无鉴权）；跨源沙箱 /
 *   postMessage 隔离改造不在本波范围（TD-57 仅文档化评估）。
 *   本模块的收缩措施：
 *     1. 模块私有：ESM 作用域，不挂 window / globalThis，不扩大暴露面；
 *     2. 注入目标限 manifest 声明的 config 三元组 id（白名单），不做控件
 *        探测 / 自动发现；id 经 getElementById 查找（DOM API 通道，id 来自
 *        manifest 第三方数据亦无 HTML 字符串拼接面）；
 *     3. 只写三个字段（key/endpoint/model），不读取游戏内任何其他数据；
 *     4. 目标元素必须是 input/select 且存在，否则该字段跳过并静默降级
 *        （不报错不中断）；
 *     5. claude key 值绝不进入游戏（凭证端点契约：protocol=claude/none 时
 *        key 为空串 — 本模块只转发端点返回值，不做任何跨协议兜底）。
 *   残余风险（文档化）：注入的 openai key 必然进入游戏自身 DOM 与脚本
 *   内存（这是功能本义 — key 供游戏调用其配置的 OpenAI 兼容端点）；同源
 *   游戏间可互读属 TD-57 既有自用威胁模型，本模块不新增暴露。
 *
 * 依赖方向：key-injector.js →（无 — 纯函数 + DOM，凭证获取经注入钩子）；
 *   simulator-view.js → key-injector.js（attachKeyInject / hasConfigTriplet /
 *   文案常量）；app.js → key-injector.js（initKeyInjector 接线）。
 *
 * 协议表面（__all__）：initKeyInjector / attachKeyInject / resolveButtonState /
 *   hasConfigTriplet / injectCredentialsIntoGame / TEXT_KEY_INJECT /
 *   TEXT_INJECTED。
 */

// ══════════════════════════════════════════════════
// 常量（UI 契约 — 文案/时长与 spec 对齐）
// ══════════════════════════════════════════════════

/** 按钮初始文案（simulator-view.js renderShell 复用同一常量渲染） */
export const TEXT_KEY_INJECT = '使用主应用 Key';

/** 注入成功后的短暂反馈文案 */
export const TEXT_INJECTED = '已填入';

/** claude-only 禁用文案（spec 逐字：主应用仅有 Claude Key 时） */
const MSG_CLAUDE_ONLY = '游戏仅支持 OpenAI 兼容 Key';

/** none 禁用文案（spec 逐字：未配置任何 OpenAI 兼容 Key） */
const MSG_NO_CREDENTIALS = '未配置 OpenAI 兼容 Key';

/** 「已填入」反馈时长（毫秒；到期按钮恢复「使用主应用 Key」可点） */
const FEEDBACK_MS = 2000;

/** config 三元组字段顺序（注入顺序即此序；apikey 先于 endpoint/model） */
const CONFIG_FIELDS = ['apikey', 'endpoint', 'model'];

/** config 字段 → 凭证字段取值映射（apikey ← key；endpoint/model 同名） */
const FIELD_VALUE_KEYS = { apikey: 'key', endpoint: 'endpoint', model: 'model' };

/** 注入目标元素白名单标签（其余标签一律跳过 — 无控件探测） */
const TARGET_TAGS = new Set(['INPUT', 'SELECT']);

// ══════════════════════════════════════════════════
// 模块级状态（UI 实现细节 — 不属全局应用状态）
// ══════════════════════════════════════════════════

/** 凭证获取函数（initKeyInjector 注入；未注入时点击静默恢复可点） */
let fetchCredentials = null;

/** 当前活动按钮条（attach 时更新；异步续体以身份守卫避免污染新 bar） */
let activeBar = null;

/** 在途注入守卫（凭证获取 + 注入期间忽略该 bar 的重复点击；按 bar 独立） */
const busyBars = new WeakSet();

/** 「已填入」反馈计时器（无在途反馈时为 null） */
let feedbackTimer = null;

/** 已绑定交互的按钮条（幂等守卫 — 同 bar 重复 attach 不重复绑监听） */
const boundBars = new WeakSet();

/** bar → 点击时取用的提供方（{sessionOnly, getDoc, getConfig}；attach 时登记） */
const barProviders = new WeakMap();

// ══════════════════════════════════════════════════
// 纯函数：按钮态解析 / 三元组校验
// ══════════════════════════════════════════════════

/**
 * 解析凭证端点响应的按钮可用态（openai / claude / none 三态）。
 *
 * 契约（spec「U8 凭证端点契约」）：protocol=openai 且 key 非空 → 可注入；
 *   claude → 禁用（reason='claude'，文案「游戏仅支持 OpenAI 兼容 Key」）；
 *   none → 禁用（reason='none'，文案「未配置 OpenAI 兼容 Key」）。
 * 防御分支：openai 但 key 空串 / 非字符串、未知 protocol、null/undefined
 *   输入一律视为 none（禁用，不抛错）— 端点契约被破坏时行为不崩。
 *
 * @param {unknown} credentials - 凭证端点响应（{key, endpoint, model, protocol}）
 * @returns {{enabled: boolean, reason: 'claude'|'none'|null}}
 *   enabled=true 时 reason 恒为 null
 */
export function resolveButtonState(credentials) {
    const c = credentials ?? {};
    if (c.protocol === 'openai' && typeof c.key === 'string' && c.key !== '') {
        return { enabled: true, reason: null };
    }
    return { enabled: false, reason: c.protocol === 'claude' ? 'claude' : 'none' };
}

/**
 * 校验 manifest config 三元组完整性（三个字段均为非空字符串 DOM id）。
 *
 * 渲染条件（spec「U8 注入交互」）：仅 ai 游戏且 manifest 含完整 config
 *   三元组时渲染「使用主应用 Key」按钮；三元组不完整视为无 config
 *   （提示条维持现状）。
 *
 * @param {unknown} config - manifest 条目的 config 字段（endpoint/apikey/model）
 * @returns {boolean} 三元组完整为 true
 */
export function hasConfigTriplet(config) {
    return config !== null && typeof config === 'object' && !Array.isArray(config)
        && typeof config.endpoint === 'string' && config.endpoint !== ''
        && typeof config.apikey === 'string' && config.apikey !== ''
        && typeof config.model === 'string' && config.model !== '';
}

// ══════════════════════════════════════════════════
// 纯函数：注入核心（填值 + 派发事件）
// ══════════════════════════════════════════════════

/**
 * 按 manifest config 三元组把凭证非空字段填入游戏配置面板并派发事件。
 *
 * 逐字段处理（顺序 apikey → endpoint → model）：字段 id 为 config 中声明
 *   的非空字符串，且凭证对应值（apikey←key；endpoint/model 同名）为非空
 *   字符串时才尝试写入；目标元素经 getElementById 查找（白名单 — 不做控件
 *   探测 / 自动发现），须存在且为 input/select，否则该字段跳过并静默降级
 *   （不报错不中断，其余字段继续）。写入后对元素派发 input 与 change 事件
 *   （各游戏监听不一，spec 决策 A：两事件都派发，不做 per-game 适配）。
 *   endpoint/model 凭证值为空 → 跳过该字段（游戏保持自身默认）。
 *   本函数不读取游戏内任何其他数据；不写任何未声明 id。
 *
 * @param {object} [params]
 * @param {Document|null} [params.doc] - 同源 iframe contentDocument（注入核心
 *   只依赖文档参数 — iframe 未加载 / 缺失时全跳过不抛错）
 * @param {object|null} [params.config] - manifest config 三元组（DOM id 白名单）
 * @param {object|null} [params.credentials] - 凭证端点响应（key/endpoint/model）
 * @returns {{filled: string[], skipped: string[]}} 按字段名（apikey/endpoint/
 *   model）分别列出实际写入与跳过的字段；filled 为空即未注入任何值
 */
export function injectCredentialsIntoGame({ doc, config, credentials } = {}) {
    const filled = [];
    const skipped = [];
    if (!doc || typeof doc.getElementById !== 'function') {
        skipped.push(...CONFIG_FIELDS);
        return { filled, skipped };
    }
    const creds = credentials ?? {};
    for (const field of CONFIG_FIELDS) {
        const id = config?.[field];
        if (typeof id !== 'string' || id === '') {
            skipped.push(field);
            continue;
        }
        const value = creds[FIELD_VALUE_KEYS[field]];
        if (typeof value !== 'string' || value === '') {
            skipped.push(field); // 空值不覆盖游戏默认
            continue;
        }
        const el = doc.getElementById(id);
        if (!el || !TARGET_TAGS.has(el.tagName)) {
            skipped.push(field); // 控件缺失 / 类型不符 → 静默降级
            continue;
        }
        el.value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        filled.push(field);
    }
    return { filled, skipped };
}

// ══════════════════════════════════════════════════
// 交互：按钮反馈状态机
// ══════════════════════════════════════════════════

/** 清理在途反馈计时器（幂等；attach / 视图重建时调用） */
function clearFeedbackTimer() {
    if (feedbackTimer !== null) {
        clearTimeout(feedbackTimer);
        feedbackTimer = null;
    }
}

/** 把按钮条复位到初始可点态（清禁用 + 清文案；静默降级路径共用） */
function resetBar(bar) {
    const btn = bar.querySelector('.sim-key-btn');
    if (btn) {
        btn.disabled = false;
        btn.textContent = TEXT_KEY_INJECT;
    }
    const msg = bar.querySelector('.sim-key-msg');
    if (msg) {
        msg.textContent = '';
        msg.hidden = true;
    }
}

/** 进入禁用态：按钮禁用 + 原因文案（claude-only 与 none 文案区分） */
function disableBar(bar, reason) {
    const btn = bar.querySelector('.sim-key-btn');
    if (btn) btn.disabled = true;
    const msg = bar.querySelector('.sim-key-msg');
    if (msg) {
        msg.textContent = reason === 'claude' ? MSG_CLAUDE_ONLY : MSG_NO_CREDENTIALS;
        msg.hidden = false;
    }
}

/** 注入成功反馈：按钮「已填入」→ FEEDBACK_MS 后恢复可点（身份 + 连接双守卫） */
function showInjectedFeedback(bar) {
    const btn = bar.querySelector('.sim-key-btn');
    if (!btn) return;
    btn.textContent = TEXT_INJECTED;
    btn.disabled = true; // 反馈期间禁用（防重复点击）
    clearFeedbackTimer();
    feedbackTimer = setTimeout(() => {
        feedbackTimer = null;
        // 视图已重建 / 关闭（bar 被替换或移除）→ 丢弃反馈恢复
        if (bar !== activeBar || !bar.isConnected) return;
        btn.disabled = false;
        btn.textContent = TEXT_KEY_INJECT;
    }, FEEDBACK_MS);
}

/**
 * 按钮点击编排：获取凭证 → 三态分流 → 注入 / 禁用。
 *
 * claude / none → 按钮永久禁用（本视图生命周期内）+ 对应文案；
 * openai → 注入 getDoc()/getConfig() 提供方的文档与三元组；filled > 0 →
 *   「已填入」反馈（sessionOnly 时同时显示「重进游戏需再次点击」注记）；
 *   filled = 0（控件全缺失）→ 静默恢复可点（用户可手动配置）；
 * 凭证获取失败 / 未初始化 → 静默恢复可点，不弹错不中断。
 * 异步续体以「bar === activeBar && bar.isConnected」守卫：视图在途关闭 /
 *   重建时丢弃 UI 更新，不污染新 bar。
 * @param {Event} e - 按钮 click 事件（currentTarget 所在 bar 为操作目标）
 */
async function handleKeyClick(e) {
    const bar = e.currentTarget?.closest?.('.sim-key-bar');
    if (!bar || bar !== activeBar) return;
    if (busyBars.has(bar)) return; // 在途守卫：凭证获取挂起中忽略该 bar 的重复点击
    const btn = bar.querySelector('.sim-key-btn');
    if (!btn || btn.disabled) return;
    const { sessionOnly = false, getDoc, getConfig } = barProviders.get(bar) ?? {};
    busyBars.add(bar);
    btn.disabled = true;
    try {
        if (typeof fetchCredentials !== 'function') {
            resetBar(bar); // 未初始化（app.js 未接线）→ 静默恢复
            return;
        }
        const creds = await fetchCredentials();
        const state = resolveButtonState(creds);
        if (!state.enabled) {
            if (bar !== activeBar || !bar.isConnected) return;
            disableBar(bar, state.reason);
            return;
        }
        const result = injectCredentialsIntoGame({
            doc: typeof getDoc === 'function' ? getDoc() : null,
            config: typeof getConfig === 'function' ? getConfig() : null,
            credentials: creds,
        });
        if (bar !== activeBar || !bar.isConnected) return; // 视图已关闭 → 丢弃
        if (result.filled.length > 0) {
            const msg = bar.querySelector('.sim-key-msg');
            if (msg) {
                msg.textContent = '';
                msg.hidden = true;
            }
            if (sessionOnly) {
                const note = bar.querySelector('.sim-key-note');
                if (note) note.hidden = false;
            }
            showInjectedFeedback(bar);
        } else {
            resetBar(bar); // 未注入任何字段 → 静默恢复可点（用户可手动配置）
        }
    } catch {
        if (bar === activeBar && bar.isConnected) {
            resetBar(bar); // 请求失败 → 静默降级
        }
    } finally {
        busyBars.delete(bar);
    }
}

/**
 * 把注入交互挂到按钮条（simulator-view.js renderShell 渲染后调用）。
 *
 * 幂等：同一 bar 重复 attach 只绑定一次（WeakSet 守卫）。bar 缺失 /
 *   getDoc/getConfig 未提供时点击静默降级不抛错（Falsify 防御）。
 * @param {object} [params]
 * @param {HTMLElement|null} [params.bar] - 按钮条容器（.sim-key-bar）
 * @param {boolean} [params.sessionOnly] - wg_ 族游戏（无保存按钮，注入仅
 *   会话内生效）→ 成功注入后显示「重进游戏需再次点击」注记
 * @param {Function} [params.getDoc] - () => Document|null；点击时取同源
 *   iframe contentDocument（动态取 — iframe 异步加载）
 * @param {Function} [params.getConfig] - () => object|null；点击时取当前
 *   游戏的 manifest config 三元组
 */
export function attachKeyInject(params = {}) {
    const { bar, sessionOnly = false, getDoc, getConfig } = params ?? {};
    if (!bar || typeof bar.querySelector !== 'function') return;
    if (boundBars.has(bar)) return; // 幂等守卫
    boundBars.add(bar);
    barProviders.set(bar, { sessionOnly, getDoc, getConfig });
    activeBar = bar;
    clearFeedbackTimer();
    const btn = bar.querySelector('.sim-key-btn');
    if (btn) btn.addEventListener('click', handleKeyClick);
}

/**
 * 初始化注入模块：注入凭证获取函数（G7 注入钩子 — app.js 接线
 *   settings.credentials()；测试注入 mock）。
 *
 * 幂等：重复调用仅更新获取函数。传 null/非函数 → 恢复未初始化态
 *   （点击静默恢复可点）。凭证获取走 api.js 既有 setFetch seam，无新 seam。
 * @param {object} [options]
 * @param {Function} [options.getCredentials] - () => Promise<{key, endpoint,
 *   model, protocol}>；凭证端点响应
 */
export function initKeyInjector({ getCredentials } = {}) {
    fetchCredentials = typeof getCredentials === 'function' ? getCredentials : null;
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些符号与 key-injector.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'initKeyInjector',
    'attachKeyInject',
    'resolveButtonState',
    'hasConfigTriplet',
    'injectCredentialsIntoGame',
    'TEXT_KEY_INJECT',
    'TEXT_INJECTED',
];
