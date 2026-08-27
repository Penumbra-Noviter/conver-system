/**
 * Conver System — 模拟器配置同步模块（深模块，U8-T2 + SIM-API-1）
 *
 * 职责：主应用对模拟器配置的单一事实来源同步 —— iframe 加载后自动使用主
 *   应用 OpenAI 兼容凭证（key/endpoint/model）、按钮「重新同步」手动兜底、
 *   动态配置控件持续同步（观察者触发 — 观察→过滤→防抖→同步→冷却→熔断→
 *   断连闭环在本模块）三通道共用
 *   同一同步核心（syncGameCredentials → injectCredentialsIntoGame）：
 *   - 凭证获取经 initKeyInjector 注入钩子（G7 模式：app.js 接
 *     settings.credentials()；测试注入 mock）；
 *   - 按钮态解析（resolveButtonState：openai / claude / none 三态纯函数）、
 *     config 三元组完整性校验（hasConfigTriplet 纯函数）、同源 iframe 配置
 *     面板填值 + 派发 input/change（injectCredentialsIntoGame 纯函数 — 只
 *     依赖文档参数，不依赖 iframe 元素）、按钮反馈状态机（成功「已填入」
 *     2s / claude·none 禁用文案 / 失败静默降级），attachKeyInject 把交互挂到
 *     simulator-view.js 渲染的按钮条（.sim-key-bar）上。TD-71：none 禁用态
 *     附带「前往设置页配置」链接（纯常量拼接），点击经 bar 一次性委托
 *     preventDefault + 调 onNavigateSettings 钩子（initKeyInjector 注入；
 *     app.js 接 switchView('settings')；非函数时点击 no-op）。
 *
 * SIM-API-1（ADR-0001「模拟器 API 配置由主应用单一控制」方案 2：宿主 iframe
 *   统一同步，第三方 HTML 零修改）落点：
 *   - 端点口径转换：manifest 条目声明 endpointMode（'full' 游戏字段要完整
 *     /chat/completions 地址 / 'base' 游戏自行拼接），凭证端点的 base URL
 *     按 mode 转换为游戏所需形态（避免启发式猜测；双重追加防护）；
 *   - 受管模型 option：模型 select 缺少主应用默认模型 option 时由宿主追加
 *     （浏览器 select.value 只在选项集内生效 — 旧 F1 静默跳过改为主应用模型
 *     可进入 select），再派发 input/change；
 *   - 幂等写入：字段值已等于目标值时不写不派发（持续同步的写回环守卫 —
 *     重复同步不再触发游戏 change 处理，动态重建场景收敛）；
 *   - 自动同步通道：load 自动同步（simulator-view handleLoad 触发
 *     autoSyncIntoGame，静默，不闪「已填入」）；配置控件重建持续同步
 *     走本模块观察者生命周期（observeConfigControls 挂载 → 过滤
 *     mutationTouchesConfig → 防抖 observerTimer → 同步 → 冷却/熔断 →
 *     breaker 断连）— 闭环单一模块可读，simulator-view 仅保留触发时机
 *     （load 后 observe / destroyFrame 断连 + 复位）。按钮点击走同一核心 +
 *     反馈状态机。写回环状态机（冷却/熔断）收口在本模块：
 *     autoSyncIntoGame 一次调用原子完成同步执行 + 冷却判定 + 置冷却 +
 *     观察者计数 + 熔断判定（path: 'load' | 'observer' 区分 load 不计数 /
 *     observer 计数熔断）；复位经 resetSyncLoop()（simulator-view
 *     destroyFrame 调用）。
 *
 * 注入安全（TD-57 信任边界评估 — spec「U8 注入交互」决策 D 落点；权威文档：
 *   docs/architecture.md「模拟器信任边界（TD-57）」小节 — 威胁模型 / 已接受
 *   风险 / 收缩措施 / 加固不可行论证以此为准）：
 *   威胁模型：22 款游戏与主应用同源运行，游戏脚本可读主应用 localStorage
 *   （含用户自填的 key）并可调 /api 任意端点（后端无鉴权）；跨源沙箱 /
 *   postMessage 隔离改造不在本波范围（TD-57 仅文档化评估，探索跟踪见
 *   探索文档未决事项 U11）。
 *   本模块的收缩措施：
 *     1. 模块私有：ESM 作用域，不挂 window / globalThis，不扩大暴露面；
 *     2. 注入目标限 manifest 声明的 config 三元组 id（白名单），不做控件
 *        探测 / 自动发现；id 经 getElementById 查找（DOM API 通道，id 来自
 *        manifest 第三方数据亦无 HTML 字符串拼接面）；
 *     3. 只写三个字段（key/endpoint/model），不读取游戏内任何其他数据；
 *     4. 目标元素必须是 input/select 且存在，否则该字段跳过并静默降级
 *        （不报错不中断）；select 目标缺主应用模型 option 时由宿主追加
 *        受管 option（SIM-API-1）—— 不依赖游戏预置选项集；
 *     5. 幂等写入：值与目标一致时不写不派发（写回环守卫）；
 *     6. claude key 值绝不进入游戏（凭证端点契约：protocol=claude/none 时
 *        key 为空串 — 本模块只转发端点返回值，不做任何跨协议兜底；
 *        syncGameCredentials 对 claude/none 不注入，仅返回禁用原因）。
 *   残余风险（文档化）：注入的 openai key 必然进入游戏自身 DOM 与脚本
 *   内存（这是功能本义 — key 供游戏调用其配置的 OpenAI 兼容端点）；同源
 *   游戏间可互读属 TD-57 既有自用威胁模型，本模块不新增暴露。
 *
 * 依赖方向：key-injector.js →（无 — 纯函数 + DOM，凭证获取经注入钩子）；
 *   simulator-view.js → key-injector.js（attachKeyInject / autoSyncIntoGame /
 *   observeConfigControls / disconnectObserver / hasConfigTriplet / 文案常量）；
 *   app.js → key-injector.js（initKeyInjector 接线）。
 *
 * 协议表面（__all__）：initKeyInjector / attachKeyInject / resolveButtonState /
 *   hasConfigTriplet / convertEndpoint / injectCredentialsIntoGame /
 *   syncGameCredentials / autoSyncIntoGame / observeConfigControls /
 *   disconnectObserver / mutationTouchesConfig / TEXT_RESYNC / TEXT_INJECTED /
 *   MSG_CLAUDE_ONLY / MSG_NO_CREDENTIALS / LINK_NAV_SETTINGS / SEL_NAV_SETTINGS /
 *   resetSyncLoop。
 */

// ══════════════════════════════════════════════════
// 常量（UI 契约 — 文案/时长与 spec 对齐）
// ══════════════════════════════════════════════════

/** 按钮初始文案（simulator-view.js renderShell 复用同一常量渲染；
 * SIM-API-1 起自动同步为常态，按钮语义为手动重新同步） */
export const TEXT_RESYNC = '重新同步';

/** 注入成功后的短暂反馈文案 */
export const TEXT_INJECTED = '已填入';

/** claude-only 禁用文案（spec 逐字：主应用仅有 Claude Key 时） */
export const MSG_CLAUDE_ONLY = '游戏仅支持 OpenAI 兼容 Key';

/** none 禁用文案（spec 逐字：未配置任何 OpenAI 兼容 Key） */
export const MSG_NO_CREDENTIALS = '未配置 OpenAI 兼容 Key';

/** none 禁用态设置入口链接文案（TD-71 — 点击触发 onNavigateSettings 钩子） */
export const LINK_NAV_SETTINGS = '前往设置页配置';

/** none 禁用态链接选择器（事件委托锚点；纯常量拼接，无用户数据，无 XSS 面） */
export const SEL_NAV_SETTINGS = '.sim-key-nav-settings';

/** 「已填入」反馈时长（毫秒；到期按钮恢复「重新同步」可点） */
const FEEDBACK_MS = 2000;

/** config 三元组字段顺序（注入顺序即此序；apikey 先于 endpoint/model） */
const CONFIG_FIELDS = ['apikey', 'endpoint', 'model'];

/** config 字段 → 凭证字段取值映射（apikey ← key；endpoint/model 同名） */
const FIELD_VALUE_KEYS = { apikey: 'key', endpoint: 'endpoint', model: 'model' };

/** OpenAI 兼容协议聊天补全路径后缀（endpointMode 口径转换用） */
const ENDPOINT_SUFFIX = '/chat/completions';

/** 注入目标元素白名单标签（其余标签一律跳过 — 无控件探测） */
const TARGET_TAGS = new Set(['INPUT', 'SELECT']);

// ══════════════════════════════════════════════════
// 写回环状态机常量
// ══════════════════════════════════════════════════

/** 写回环冷却时长（毫秒；注入后冷却窗口内不重复同步 — 幂等写入已收敛常规场景，此为兜底） */
const SYNC_COOLDOWN_MS = 1000;

/** 观察者路径写回环熔断阈值：连续 SYNC_MAX_STRIKES 次真写入（written.length > 0）后熔断；
 * 熔断后 observer 调用恒返回 breaker: true，终止自动再同步 */
const SYNC_MAX_STRIKES = 3;

// ══════════════════════════════════════════════════
// 模块级状态（UI 实现细节 — 不属全局应用状态）
// ══════════════════════════════════════════════════

/** 凭证获取函数（initKeyInjector 注入；未注入时点击静默恢复可点） */
let fetchCredentials = null;

/** 设置页导航钩子（initKeyInjector 注入 onNavigateSettings；TD-71 —
 * none 态「前往设置页配置」链接点击调用；非函数时点击 no-op） */
let navigateSettings = null;

/** 当前活动按钮条（attach 时更新；异步续体以身份守卫避免污染新 bar） */
let activeBar = null;

/** 在途注入守卫（凭证获取 + 注入期间忽略该 bar 的重复点击；按 bar 独立） */
const busyBars = new WeakSet();

/** 「已填入」反馈计时器（无在途反馈时为 null） */
let feedbackTimer = null;

/** 已绑定交互的按钮条（幂等守卫 — 同 bar 重复 attach 不重复绑监听；
 * 设置链接点击委托随 attach 一次性绑定，同受本守卫约束） */
const boundBars = new WeakSet();

/** bar → 点击时取用的提供方（{getDoc, getConfig, getEndpointMode}；attach 时登记） */
const barProviders = new WeakMap();

// ══════════════════════════════════════════════════
// 写回环状态机状态
// ══════════════════════════════════════════════════

/** 写回环冷却截止时间戳（Date.now()；未冷却为 0 — 与 resetSyncLoop 初始值一致） */
let syncCooldownUntil = 0;

/** 观察者路径写回环熔断计数（连续真写入次数；达到 SYNC_MAX_STRIKES 后熔断；
 * 熔断后 observer 调用恒返回 breaker: true；resetSyncLoop 清零） */
let syncStrikes = 0;

// ══════════════════════════════════════════════════
// 配置控件观察者生命周期状态（SIM-API-1 — S3 状态机边界收口；触发器由
// simulator-view.js 持有，生命周期状态/逻辑收口本模块）
// ══════════════════════════════════════════════════

/** 配置控件重建观察者防抖时长（毫秒；连续重建合并为一次同步 —
 * simulator-view 触发点语义保持） */
const OBSERVER_DEBOUNCE_MS = 500;

/** 配置控件重建观察者（observeConfigControls 挂游戏文档；disconnectObserver 断开） */
let configObserver = null;

/** 观察者防抖计时器（无在途防抖时为 null；disconnectObserver 清理） */
let observerTimer = null;

/** 观察者同步执行上下文（observeConfigControls 登记 doc/config/endpointMode/bar —
 * 防抖到期 flushObserverSync 取用；disconnectObserver 清空） */
let observerContext = null;

// ══════════════════════════════════════════════════
// 纯函数：按钮态解析 / 三元组校验 / 端点口径转换
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
 *   三元组时渲染「重新同步」按钮条；三元组不完整视为无 config
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

/**
 * 按 manifest endpointMode 把凭证端点 base URL 转换为游戏所需形态
 * （SIM-API-1 — 各游戏端点字段分别接受 API Base URL 或完整 /chat/completions
 * 地址，直接注入同一字符串不能保证可用；口径转换避免启发式猜测）。
 *
 * 契约：'full' → 追加 /chat/completions（尾斜杠先归一；已含后缀不重复追加）；
 *   'base' → 剥除 /chat/completions 后缀（已是 base 形态保持原样）；
 *   其他值（含 undefined — manifest 未声明）→ 原样返回（兼容旧数据）。
 *
 * @param {unknown} endpoint - 凭证端点响应中的 endpoint（base URL）
 * @param {unknown} mode - manifest 条目的 endpointMode（'base' | 'full'）
 * @returns {unknown} 转换后的端点值（非字符串原样返回）
 */
export function convertEndpoint(endpoint, mode) {
    if (typeof endpoint !== 'string' || endpoint === '') return endpoint;
    const trimmed = endpoint.replace(/\/+$/, '');
    if (mode === 'full') {
        return trimmed.endsWith(ENDPOINT_SUFFIX) ? trimmed : `${trimmed}${ENDPOINT_SUFFIX}`;
    }
    if (mode === 'base') {
        return trimmed.endsWith(ENDPOINT_SUFFIX) ? trimmed.slice(0, -ENDPOINT_SUFFIX.length) : trimmed;
    }
    return endpoint;
}

// ══════════════════════════════════════════════════
// 纯函数：注入核心（填值 + 派发事件）
// ══════════════════════════════════════════════════

/**
 * select 是否含匹配 value 的 option（无匹配时由 ensureSelectOption 追加受管
 * option — HTMLSelectElement.value 只在选项集内生效，SIM-API-1 起宿主保证
 * 主应用模型名可进入 select，不再依赖游戏预置选项集）。
 *
 * @param {HTMLSelectElement} selectEl - 目标 select 元素（已确认 tagName=SELECT）
 * @param {string} value - 拟写入的凭证值（非空字符串）
 * @returns {boolean} 选项集中存在匹配值为 true
 */
function hasSelectOption(selectEl, value) {
    for (const opt of selectEl.options) {
        if (opt.value === value) return true;
    }
    return false;
}

/**
 * 追加受管 option（select 缺目标值时）：经 ownerDocument.createElement 创建
 * （无 HTML 字符串拼接面，option 文本/值同为目标值 — 值即文本，无注入面）。
 *
 * @param {HTMLSelectElement} selectEl - 目标 select 元素
 * @param {string} value - 拟写入的凭证值（非空字符串）
 * @returns {boolean} 本次新增了 option 为 true（已存在为 false）
 */
function ensureSelectOption(selectEl, value) {
    if (hasSelectOption(selectEl, value)) return false;
    const opt = selectEl.ownerDocument.createElement('option');
    opt.value = value;
    opt.textContent = value;
    selectEl.add(opt);
    return true;
}

/**
 * 按 manifest config 三元组把凭证非空字段同步到游戏配置面板并派发事件。
 *
 * 逐字段处理（顺序 apikey → endpoint → model）：字段 id 为 config 中声明
 *   的非空字符串，且凭证对应值（apikey←key；endpoint/model 同名）为非空
 *   字符串时才尝试写入；endpoint 值先按 endpointMode 做口径转换（SIM-API-1）。
 *   目标元素经 getElementById 查找（白名单 — 不做控件探测 / 自动发现），
 *   须存在且为 input/select，否则该字段跳过并静默降级（不报错不中断，其余
 *   字段继续）。select 元素：目标值不在选项集时追加受管 option（主应用模型
 *   名可进入 select — SIM-API-1 取代旧 F1 静默跳过）。幂等写入：元素当前值
 *   已等于目标值 → 不写不派发（记入 filled — 字段已处于目标态；持续同步的
 *   写回环守卫）。写入后对元素派发 input 与 change 事件（各游戏监听不一，
 *   spec 决策 A：两事件都派发，不做 per-game 适配）。
 *   endpoint/model 凭证值为空 → 跳过该字段（游戏保持自身默认）。
 *   本函数不读取游戏内任何其他数据；不写任何未声明 id。
 *
 * @param {object} [params]
 * @param {Document|null} [params.doc] - 同源 iframe contentDocument（注入核心
 *   只依赖文档参数 — iframe 未加载 / 缺失时全跳过不抛错）
 * @param {object|null} [params.config] - manifest config 三元组（DOM id 白名单）
 * @param {object|null} [params.credentials] - 凭证端点响应（key/endpoint/model）
 * @param {string|null} [params.endpointMode] - manifest endpointMode（'base' |
 *   'full'；null/undefined 不转换 — 兼容旧数据）
 * @returns {{filled: string[], skipped: string[], written: string[]}}
 *   按字段名（apikey/endpoint/model）：filled = 已处于目标值（含本次写入与
 *   幂等匹配）；skipped = 跳过的字段；written = 本次真正写入并派发事件的
 *   字段（filled 的子集 — 期末评审修正：熔断/反馈类消费方须用 written 判定
 *   「宿主真改了游戏配置」，filled 的幂等匹配不计入）。filled 为空即未同步
 *   任何值
 */
export function injectCredentialsIntoGame({ doc, config, credentials, endpointMode } = {}) {
    const filled = [];
    const skipped = [];
    const written = [];
    if (!doc || typeof doc.getElementById !== 'function') {
        skipped.push(...CONFIG_FIELDS);
        return { filled, skipped, written };
    }
    const creds = credentials ?? {};
    for (const field of CONFIG_FIELDS) {
        const id = config?.[field];
        if (typeof id !== 'string' || id === '') {
            skipped.push(field);
            continue;
        }
        const rawValue = creds[FIELD_VALUE_KEYS[field]];
        const value = field === 'endpoint' ? convertEndpoint(rawValue, endpointMode) : rawValue;
        if (typeof value !== 'string' || value === '') {
            skipped.push(field); // 空值不覆盖游戏默认
            continue;
        }
        const el = doc.getElementById(id);
        if (!el || !TARGET_TAGS.has(el.tagName)) {
            skipped.push(field); // 控件缺失 / 类型不符 → 静默降级
            continue;
        }
        // select 缺目标 option → 追加受管 option；added=true 时浏览器自动选中
        // 新 option（空 select 场景 el.value 可能未写即匹配）—— 该选中是本次
        // 追加的副作用，也必须派发事件（否则依赖 change 保存状态的游戏存旧值，
        // Falsify 修复：幂等跳过仅限「option 已存在且值已匹配」）
        const added = el.tagName === 'SELECT' ? ensureSelectOption(el, value) : false;
        if (!added && el.value === value) {
            filled.push(field); // 幂等：已为目标值且非本次追加 → 不写不派发（写回环守卫）
            continue;
        }
        el.value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        filled.push(field);
        written.push(field);
    }
    return { filled, skipped, written };
}

// ══════════════════════════════════════════════════
// 同步编排（自动同步 / 按钮点击共用核心）
// ══════════════════════════════════════════════════

/**
 * 同步编排核心：取凭证 → 三态分流 → 注入（SIM-API-1 自动同步与按钮点击
 * 共用）。claude / none → 不注入（claude key 绝不进入游戏），返回禁用原因；
 * openai → 注入 getDoc()/config/endpointMode 提供的文档与三元组。
 * 未初始化（app.js 未接线 initKeyInjector）→ 返回 null（调用方静默保持
 * 现状，不显示误导性禁用文案）。
 * 凭证获取失败 → 拒绝（调用方按路径降级：按钮点击静默复位 / 自动同步保持）。
 *
 * @param {object} [params]
 * @param {Document|null} [params.doc] - 同源 iframe contentDocument（未提供
 *   getDoc 时回落的注入目标 —— 外部直接调用路径）
 * @param {Function} [params.getDoc] - () => Document|null；惰性取用源 —— doc 在
 *   凭证获取完成后才经此取用（F-89 写前失效守卫的执行点，见 flushObserverSync）；
 *   提供时优先于 doc 参数
 * @param {object|null} [params.config] - manifest config 三元组
 * @param {string|null} [params.endpointMode] - manifest endpointMode
 * @returns {Promise<null|{enabled: boolean, reason: 'claude'|'none'|null,
 *   filled: string[], skipped: string[], written: string[]}>}
 *   null = 未初始化；enabled=false 时 filled/skipped/written 恒为空数组
 */
export async function syncGameCredentials({ doc, getDoc, config, endpointMode } = {}) {
    if (typeof fetchCredentials !== 'function') return null; // 未初始化 → 无操作
    const creds = await fetchCredentials();
    const state = resolveButtonState(creds);
    if (!state.enabled) {
        return { enabled: false, reason: state.reason, filled: [], skipped: [], written: [] };
    }
    // F-89 写前失效校验执行点：doc 在凭证获取（含网络窗口）完成后才取用 —— 取用点
    // 重取使宿主注入的失效守卫（observerContext === ctx，见 flushObserverSync）真正
    // 生效：断连在途写入窗口内 observerContext 已置 null → getDoc() 返回 null →
    // 注入全跳过 → 陈旧在途写变 no-op（written.length = 0，熔断计数不 +1）。
    // 未提供 getDoc（外部直接调用）→ 回落 doc 参数（行为与既有契约一致）。
    const targetDoc = typeof getDoc === 'function' ? getDoc() : doc;
    const result = injectCredentialsIntoGame({ doc: targetDoc, config, credentials: creds, endpointMode });
    return { enabled: true, reason: null, ...result };
}

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
        btn.textContent = TEXT_RESYNC;
    }
    const msg = bar.querySelector('.sim-key-msg');
    if (msg) {
        msg.textContent = '';
        msg.hidden = true;
    }
}

/** 进入禁用态：按钮禁用 + 原因文案（claude-only 与 none 文案区分）。
 * none 分支渲染「未配置 OpenAI 兼容 Key · 前往设置页配置（链接）」——
 * 纯常量拼接（无用户数据，无 XSS 面）；链接点击经 bar 上的一次性委托
 * 路由（handleBarClick），preventDefault + 调 onNavigateSettings 钩子
 * （未注入钩子时点击 no-op）。 */
function disableBar(bar, reason) {
    const btn = bar.querySelector('.sim-key-btn');
    if (btn) btn.disabled = true;
    const msg = bar.querySelector('.sim-key-msg');
    if (msg) {
        if (reason === 'claude') {
            msg.textContent = MSG_CLAUDE_ONLY;
        } else {
            msg.innerHTML = `${MSG_NO_CREDENTIALS} · <a href="#" class="sim-key-nav-settings">${LINK_NAV_SETTINGS}</a>`;
        }
        msg.hidden = false;
    }
}

/**
 * 按钮条点击委托（TD-71）：命中「前往设置页配置」链接 → preventDefault
 * （拦截 href="#" 默认跳转）+ 调 onNavigateSettings 钩子；非函数时点击
 * no-op 不抛错。绑定在 bar 上一次（attachKeyInject 的 boundBars 幂等
 * 守卫）—— disableBar 多次调用重建链接元素也不产生重复监听。
 * @param {Event} e - 按钮条内任意 click 事件（委托冒泡）
 */
function handleBarClick(e) {
    if (!e.target?.closest?.(SEL_NAV_SETTINGS)) return;
    e.preventDefault();
    if (typeof navigateSettings === 'function') navigateSettings();
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
        btn.textContent = TEXT_RESYNC;
    }, FEEDBACK_MS);
}

/**
 * 同步执行核心（自动同步 / 按钮点击共用；feedback 区分反馈状态机）。
 *
 * 取提供方 → syncGameCredentials 三态分流 → bar 状态机：
 *   未初始化（返回 null）→ bar 保持现状（静默，不显示误导性禁用文案）；
 *   claude / none → 按钮永久禁用（本视图生命周期内）+ 对应文案；
 *   openai → 注入 getDoc()/getConfig()/getEndpointMode() 提供方的文档与
 *     三元组；feedback 时 filled > 0 → 「已填入」反馈，filled = 0（控件全
 *     缺失）→ 静默恢复可点（用户可手动配置）；feedback=false（自动同步）
 *     静默注入不闪反馈。
 * 凭证获取失败 → 请求失败静默降级：feedback 时按钮恢复可点；自动同步路径
 *   保持现状不弹错不中断。
 * 异步续体以「bar === activeBar && bar.isConnected」守卫：视图在途关闭 /
 *   重建时丢弃 UI 更新，不污染新 bar（同步结果仍返回 — 调用方按需消费）。
 *
 * @param {object} [params]
 * @param {HTMLElement|null} [params.bar] - 按钮条容器（.sim-key-bar）
 * @param {Function} [params.getDoc] - () => Document|null；同步时取同源
 *   iframe contentDocument（动态取 — iframe 异步加载）
 * @param {Function} [params.getConfig] - () => object|null；同步时取当前
 *   游戏的 manifest config 三元组
 * @param {Function} [params.getEndpointMode] - () => string|null；同步时取
 *   当前游戏的 manifest endpointMode
 * @param {boolean} [params.feedback] - true 为按钮点击路径（「已填入」反馈 /
 *   失败复位）；false 为自动同步路径（静默）
 * @returns {Promise<null|{enabled: boolean, reason: 'claude'|'none'|null,
 *   filled: string[], skipped: string[], written: string[]}>} 同步结果（同 syncGameCredentials；
 *   未初始化 / 视图关闭早退 / 请求失败 → null）
 */
async function runSync({ bar, getDoc, getConfig, getEndpointMode, feedback }) {
    if (!bar || bar !== activeBar) return null;
    if (busyBars.has(bar)) return null; // 在途守卫：凭证获取挂起中忽略该 bar 的重复点击
    const btn = bar.querySelector('.sim-key-btn');
    if (!btn || btn.disabled) return null;
    if (feedback) {
        busyBars.add(bar);
        btn.disabled = true;
    }
    try {
        const result = await syncGameCredentials({
            getDoc,
            config: typeof getConfig === 'function' ? getConfig() : null,
            endpointMode: typeof getEndpointMode === 'function' ? getEndpointMode() : null,
        });
        if (result === null) {
            // 未初始化（app.js 未接线）→ 点击路径静默复位可点；自动同步路径保持现状
            if (feedback) resetBar(bar);
            return null;
        }
        if (bar !== activeBar || !bar.isConnected) return result; // 视图已关闭 → 丢弃 UI 更新
        if (!result.enabled) {
            disableBar(bar, result.reason);
            return result;
        }
        if (feedback) {
            if (result.filled.length > 0) {
                showInjectedFeedback(bar);
            } else {
                resetBar(bar); // 未同步任何字段 → 静默恢复可点（用户可手动配置）
            }
        }
        return result;
    } catch {
        if (feedback && bar === activeBar && bar.isConnected) {
            resetBar(bar); // 请求失败 → 静默降级
        }
        return null;
    } finally {
        if (feedback) busyBars.delete(bar);
    }
}

/**
 * 按钮点击编排（手动重新同步）：走 runSync 反馈路径（「已填入」2s 反馈 /
 * claude·none 禁用文案 / 失败复位）。
 * @param {Event} e - 按钮 click 事件（currentTarget 所在 bar 为操作目标）
 */
async function handleKeyClick(e) {
    const bar = e.currentTarget?.closest?.('.sim-key-bar');
    if (!bar || bar !== activeBar) return;
    if (busyBars.has(bar)) return;
    const btn = bar.querySelector('.sim-key-btn');
    if (!btn || btn.disabled) return;
    const { getDoc, getConfig, getEndpointMode } = barProviders.get(bar) ?? {};
    await runSync({ bar, getDoc, getConfig, getEndpointMode, feedback: true });
}

/**
 * 自动同步入口（SIM-API-1）：静默取凭证 → 注入当前游戏配置面板（iframe
 * load / 配置控件动态重建后由 simulator-view.js 调用；不闪「已填入」反馈）。
 * claude / none → 按钮条禁用 + 原因文案（UI 显示原因并引导前往主应用设置）；
 * 未初始化 → bar 保持现状。返回同步结果（simulator-view 据返回值决定
 * 观察者写回环冷却/熔断 — 见该模块 autoSyncAfterLoad）。
 *
 * 写回环状态机（冷却/熔断）收口在本函数：一次调用原子完成同步执行 +
 * 冷却判定（冷却中返回 cooled: true）+ 置冷却 + 观察者真写入计数 +
 * 熔断判定（达 SYNC_MAX_STRIKES 次返回 breaker: true）。
 * path 参数区分 load 路径（置冷却不计数）与 observer 路径（置冷却+计数+
 * 熔断判定）。手动按钮路径（feedback=true）完全不经本函数，不受状态机影响。
 *
 * @param {object} [params]
 * @param {HTMLElement|null} [params.bar] - 按钮条容器（.sim-key-bar）
 * @param {Function} [params.getDoc] - () => Document|null；同步时取同源
 *   iframe contentDocument
 * @param {Function} [params.getConfig] - () => object|null；同步时取当前
 *   游戏的 manifest config 三元组
 * @param {Function} [params.getEndpointMode] - () => string|null；同步时取
 *   当前游戏的 manifest endpointMode
 * @param {'load'|'observer'} [params.path='load'] - 同步路径：'load' 置冷却
 *   不计数（默认）；'observer' 置冷却+计数+熔断判定
 * @returns {Promise<null|{enabled: boolean, reason: 'claude'|'none'|null,
 *   filled: string[], skipped: string[], written: string[],
 *   cooled?: boolean, breaker?: boolean}>} 同步结果；冷却中返回 cooled: true；
 *   熔断达阈值或已熔断返回 breaker: true；未初始化/bar 缺失返回 null
 */
export async function autoSyncIntoGame(params = {}) {
    const { bar, getDoc, getConfig, getEndpointMode, path = 'load' } = params ?? {};

    // 熔断权优先于冷却：已熔断的 observer 调用恒返回 breaker（constraint 9）
    if (path === 'observer' && syncStrikes >= SYNC_MAX_STRIKES) {
        return { enabled: false, reason: null, filled: [], skipped: [], written: [], breaker: true };
    }

    // 冷却判定在状态机函数调用时执行（防抖到期执行点，非 mutation 回调 — TD-76）
    if (Date.now() < syncCooldownUntil) {
        return { enabled: false, reason: null, filled: [], skipped: [], written: [], cooled: true };
    }

    if (!bar) return null;
    const result = await runSync({ bar, getDoc, getConfig, getEndpointMode, feedback: false });

    // 后同步状态迁移：仅真写入（written > 0）时置冷却；observer 额外计数 + 熔断判定
    if (result && result.enabled) {
        if (result.written.length > 0) {
            syncCooldownUntil = Date.now() + SYNC_COOLDOWN_MS;
            if (path === 'observer') {
                syncStrikes += 1;
                if (syncStrikes >= SYNC_MAX_STRIKES) {
                    result.breaker = true;
                }
            }
        }
    }

    return result;
}

/**
 * 复位写回环状态机（幂等清冷却 + 清熔断计数）。
 *
 * 未冷却 / 未熔断时调用无副作用（幂等 — destroyFrame 每次调用都安全）。
 * 复位唯一触发点：simulator-view.js destroyFrame（关闭/重开游戏）。
 * observeConfigControls 开头 disconnectObserver 不得顺带复位。
 */
export function resetSyncLoop() {
    syncCooldownUntil = 0;
    syncStrikes = 0;
}

// ══════════════════════════════════════════════════
// 配置控件观察者生命周期（SIM-API-1 — 观察→过滤→防抖→同步→冷却→熔断→断连
// 闭环单一模块可读；触发器由 simulator-view.js 持有）
// ══════════════════════════════════════════════════

/**
 * 断开配置控件观察者 + 清理防抖计时器 + 清空观察者执行上下文（幂等；
 * destroyFrame / 重新 observe / closeSimulator 共用）。
 * 不复位写回环状态机（冷却/熔断复位经 resetSyncLoop — observeConfigControls
 * 开头断连不得顺带复位，避免熔断语义丢失）。
 */
export function disconnectObserver() {
    if (configObserver) {
        configObserver.disconnect();
        configObserver = null;
    }
    if (observerTimer) {
        clearTimeout(observerTimer);
        observerTimer = null;
    }
    observerContext = null;
}

/**
 * 变更是否触及 config 三元组控件（SIM-API-1 观察者过滤 — 游戏运行期高频
 * DOM 更新（状态渲染等）不得触发同步；只有 id 命中或变更子树含控件才算）。
 * 语义：目标元素自身 id ∈ 三元组（childList 与 attributes 变更共用判定 —
 * 期末评审去重）；或 childList 新增/移除子树内任一元素 id ∈ 三元组（游戏
 * 整段重建配置面板时命中；子树元素遍历用 id 成员判定，无选择器转义面）。
 * attributes 变更（TD-75 — 游戏以 setAttribute 重建控件）仅目标元素自身
 * 判定；运行期无关属性变更（class/style 等）由 observe 的 attributeFilter
 * 先行拦截（期末评审 F1 修复 — 只监听 value/hidden 票面目标属性）。
 * 纯函数 — 不依赖 iframe 元素与视图模块状态。
 * @param {MutationRecord[]} mutations - MutationObserver 回调的变更记录
 * @param {object|null} config - manifest config 三元组（endpoint/apikey/model）
 * @returns {boolean} 任一变更触及配置控件为 true
 */
export function mutationTouchesConfig(mutations, config) {
    const ids = [config?.endpoint, config?.apikey, config?.model]
        .filter((v) => typeof v === 'string' && v !== '');
    if (ids.length === 0) return false;
    for (const m of mutations ?? []) {
        if (typeof m?.target?.id === 'string' && ids.includes(m.target.id)) return true;
        if (m?.type === 'attributes') continue;
        const nodes = [...(m?.addedNodes ?? [])];
        if (m?.removedNodes?.length) nodes.push(...m.removedNodes);
        for (const node of nodes) {
            if (node?.nodeType !== 1) continue;
            if (ids.includes(node.id)) return true;
            for (const el of node.querySelectorAll?.('*') ?? []) {
                if (ids.includes(el.id)) return true;
            }
        }
    }
    return false;
}

/**
 * 观察者回调：变更触及配置控件 → 防抖 OBSERVER_DEBOUNCE_MS → 自动同步
 * （observer 路径）。冷却/熔断判定已收口到 autoSyncIntoGame 单一状态机，
 * 本回调只消费 breaker 信号决定观察者断连。
 * @param {MutationRecord[]} mutations - MutationObserver 回调的变更记录
 */
function handleConfigMutation(mutations) {
    const ctx = observerContext;
    if (!ctx) return;
    if (!mutationTouchesConfig(mutations, ctx.config)) return;
    if (observerTimer) clearTimeout(observerTimer);
    observerTimer = setTimeout(flushObserverSync, OBSERVER_DEBOUNCE_MS);
}

/**
 * 观察者防抖到期回调：取 observe 时登记的执行上下文 → 以 observer 路径
 * 自动同步（冷却判定在状态机函数调用时执行 — 防抖到期执行点，TD-76）；
 * 熔断信号（breaker: true）→ 断开观察者，终止自动再同步。
 * F-89 断连失效守卫：getDoc 闭包以「observerContext === ctx」校验上下文仍有效 ——
 * 同步在途（await autoSyncIntoGame 含凭证 fetch）期间 destroyFrame 断连已置
 * observerContext = null，返回 null → 注入全跳过 → written.length = 0 → 陈旧
 * 在途写变 no-op，同步不再置冷却、不再给共享熔断计数 syncStrikes +1（新观察者
 * 循环的熔断起点不被污染）。与 runSync 既有「bar !== activeBar」续体守卫
 * （视图关闭丢弃 UI 更新）同族。
 */
async function flushObserverSync() {
    observerTimer = null;
    const ctx = observerContext;
    if (!ctx || !ctx.bar || !ctx.doc) return;
    const result = await autoSyncIntoGame({
        bar: ctx.bar,
        getDoc: () => (observerContext === ctx ? ctx.doc : null),
        getConfig: () => ctx.config ?? null,
        getEndpointMode: () => ctx.endpointMode ?? null,
        path: 'observer',
    });
    // 熔断判定在状态机内完成，本模块仅消费 breaker 信号决定观察者生命周期
    if (result?.breaker === true) disconnectObserver();
}

/**
 * 对 loaded 游戏文档挂配置控件观察者（SIM-API-1 观察者生命周期入口 —
 * 观察→过滤→防抖→同步→冷却→熔断→断连闭环单一模块可读）。
 *
 * 触发器：simulator-view.js handleLoad（load 后调用）；re-observe 幂等
 * （先 disconnect 再挂）。参数化接收 doc / config / endpointMode / bar —
 * 不读任何 simulator-view 模块状态（currentGame / frame / state）。
 * 前置守卫：doc/body/bar 可用 + config 三元组完整才观察（观察无意义时不挂，
 * no-op 不抛错）；三缺任一 → 直接返回。
 * 观察参数白名单保持：childList + subtree + attributes +
 * attributeFilter ['value','hidden']（TD-75 — 票面目标属性收窄，配置控件
 * 自身 class/disabled 等运行期翻转不触发，防良性变更累积误熔断）。宿主注入
 * 走 property 赋值与事件派发，不产生 attribute mutation — 无自触发面。
 *
 * @param {object} [params]
 * @param {Document|null} [params.doc] - 同源 iframe contentDocument
 * @param {object|null} [params.config] - manifest config 三元组（DOM id 白名单）
 * @param {string|null} [params.endpointMode] - manifest endpointMode（'base'|'full'）
 * @param {HTMLElement|null} [params.bar] - 按钮条容器（.sim-key-bar）
 */
export function observeConfigControls(params = {}) {
    const { doc, config, endpointMode, bar } = params ?? {};
    disconnectObserver();
    if (!doc || !bar) return;
    if (!hasConfigTriplet(config)) return; // 三元组不完整 → 无控件可观察
    const body = doc.body;
    if (!body || typeof body.addEventListener !== 'function') return;
    if (typeof MutationObserver === 'undefined') return;
    observerContext = { doc, config, endpointMode, bar };
    configObserver = new MutationObserver(handleConfigMutation);
    configObserver.observe(body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['value', 'hidden'],
    });
}

/**
 * 把同步交互挂到按钮条（simulator-view.js renderShell 渲染后调用）。
 *
 * 幂等：同一 bar 重复 attach 只绑定一次（WeakSet 守卫）。bar 缺失 /
 *   getDoc/getConfig 未提供时点击静默降级不抛错（Falsify 防御）。
 * @param {object} [params]
 * @param {HTMLElement|null} [params.bar] - 按钮条容器（.sim-key-bar）
 * @param {Function} [params.getDoc] - () => Document|null；点击时取同源
 *   iframe contentDocument（动态取 — iframe 异步加载）
 * @param {Function} [params.getConfig] - () => object|null；点击时取当前
 *   游戏的 manifest config 三元组
 * @param {Function} [params.getEndpointMode] - () => string|null；点击时取
 *   当前游戏的 manifest endpointMode
 */
export function attachKeyInject(params = {}) {
    const { bar, getDoc, getConfig, getEndpointMode } = params ?? {};
    if (!bar || typeof bar.querySelector !== 'function') return;
    if (boundBars.has(bar)) return; // 幂等守卫
    boundBars.add(bar);
    // 设置链接点击委托：随按钮交互一次性绑定（TD-71 — 避免 disableBar
    // 多次调用时链接点击重复触发钩子；同受 boundBars 幂等守卫约束）
    bar.addEventListener('click', handleBarClick);
    barProviders.set(bar, { getDoc, getConfig, getEndpointMode });
    activeBar = bar;
    clearFeedbackTimer();
    const btn = bar.querySelector('.sim-key-btn');
    if (btn) btn.addEventListener('click', handleKeyClick);
}

/**
 * 初始化同步模块：注入凭证获取函数与设置页导航钩子（G7 注入钩子 —
 * app.js 接线 settings.credentials() 与 switchView('settings')；测试注入
 * mock）。
 *
 * 幂等：重复调用仅更新函数。传 null/非函数 → 恢复未初始化态（同步静默
 * 保持现状；设置链接点击 no-op）。凭证获取走 api.js 既有 setFetch seam，
 * 无新 seam。
 * @param {object} [options]
 * @param {Function} [options.getCredentials] - () => Promise<{key, endpoint,
 *   model, protocol}>；凭证端点响应
 * @param {Function} [options.onNavigateSettings] - () => void；none 态
 *   「前往设置页配置」链接点击时调用（TD-71；非函数时点击 no-op）
 */
export function initKeyInjector({ getCredentials, onNavigateSettings } = {}) {
    fetchCredentials = typeof getCredentials === 'function' ? getCredentials : null;
    navigateSettings = typeof onNavigateSettings === 'function' ? onNavigateSettings : null;
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些符号与 key-injector.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'initKeyInjector',
    'attachKeyInject',
    'resolveButtonState',
    'hasConfigTriplet',
    'convertEndpoint',
    'injectCredentialsIntoGame',
    'syncGameCredentials',
    'autoSyncIntoGame',
    'observeConfigControls',
    'disconnectObserver',
    'mutationTouchesConfig',
    'TEXT_RESYNC',
    'TEXT_INJECTED',
    'MSG_CLAUDE_ONLY',
    'MSG_NO_CREDENTIALS',
    'LINK_NAV_SETTINGS',
    'SEL_NAV_SETTINGS',
    'resetSyncLoop',
];
