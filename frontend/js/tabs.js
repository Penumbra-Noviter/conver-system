/**
 * Conver System — 多 tab 会话工作区状态（深模块）
 *
 * 职责：
 *   1. 维护应用内会话 tab 集合（同一会话至多一个 tab，按 conversationId 去重）
 *   2. 每个 tab 持有独立的会话视图状态：消息缓存、输入草稿、滚动位置、
 *      流式阶段（idle/thinking/streaming/done/error）与流式句柄
 *   3. 结构性变更（开/关/激活/全关/恢复）自动写入 sessionStorage（只存 ids + activeId）
 *      并触发 onTabsChanged 通知；updateTab 通知分类：patch 含展示字段（title/phase）
 *      才通知（tab 条重渲染所需），纯内容 patch（messages/draft/scrollTop 等）不通知，
 *      且一律不写存储
 *
 * 协议表面（__all__）：openTab / activateTab / closeTab / closeTabs / closeAllTabs /
 *   getActiveTab / getTab / getTabs / getTabDisplay / updateTab / abortStream /
 *   serialize / restore / restoreFromStorage / onTabsChanged。
 * 纯逻辑零 DOM：jsdom 环境（提供 sessionStorage）即可完整测试。
 *
 * 关键语义：
 *   - updateTab 对不存在的 conversationId 幂等 no-op —— 支撑「关闭流式中的 tab 后
 *     异步写回」的防悬挂设计：onDone/onError 一律按发起时捕获的 conversationId 写回，
 *     发起 tab 可能已被关闭，此时静默丢弃
 *   - 恢复（restore）只重建 tab 骨架（id 列表 + activeId），消息/草稿/流式状态
 *     一律不持久化 —— 恢复的 tab 天然非流式（phase idle、isStreaming false、
 *     activeStream null），消息在激活时懒加载
 *   - updateTab 不写 sessionStorage：序列化结果只含 ids/activeId，内容更新不影响
 *     存储，避免流式逐 token 写盘；通知分类（FIX-C 热路径节流）：patch 含展示字段
 *     （title/phase）才触发 onTabsChanged —— tab 条状态指示随 phase 刷新需要；
 *     纯内容 patch（messages/draft/scrollTop 等）不通知，流式逐 token 的 messages
 *     更新不再触发 tab 条全量 innerHTML 重建
 *
 * 依赖方向：tabs.js 不依赖任何模块；app.js / chat.js / components/tab-bar.js → tabs.js
 */

// ══════════════════════════════════════════════════
// 内部状态
// ══════════════════════════════════════════════════

const STORAGE_KEY = 'conver.tabs.v1';

/** @type {Array<object>} 内部 tab 集（顺序即 tab 条展示顺序） */
let tabList = [];

/** @type {number|string|null} 当前活动 tab 的 conversationId；无 tab 时为 null */
let activeId = null;

/** @type {Set<Function>} onTabsChanged 监听器 */
const listeners = new Set();

/**
 * 展示字段单一声明表（F-83）—— 键 = 展示字段（title / phase），值为对应派生取值函数。
 * 唯一事实来源：DISPLAY_KEYS 由本表键集派生，getTabDisplay 的 title/phase 派生输入
 * 亦取自本表 —— 通知判定键集与渲染派生输入互为约束由单一声明表保证（不再双清单手
 * 同步：新增展示字段只改表一处，通知判定与渲染派生即同步生效）。
 * 派生函数入参为 tab 状态（getTabs() 元素；null / undefined 容错）
 */
const DISPLAY_FIELDS = {
    /** title 展示值：缺省「未命名会话」（空串 / null / undefined 时） */
    title: (tab) => tab?.title || '未命名会话',
    /** phase 展示值：原样透传，缺省 'idle'（未知值不抛错、不产生任何指示） */
    phase: (tab) => tab?.phase ?? 'idle',
};

/**
 * updateTab 触发 onTabsChanged 的展示字段键集 —— 由 DISPLAY_FIELDS 声明表派生
 * （键集合保持 ['title', 'phase'] 不变）。patch 含任一展示字段才可能改变 tab 条渲染，
 * 才触发通知；纯内容字段（messages/draft/scrollTop 等）patch 不触发通知 ——
 * 流式逐 token 的 messages 更新不再引起 tab 条全量 innerHTML 重建（FIX-C 热路径节流）。
 */
const DISPLAY_KEYS = Object.keys(DISPLAY_FIELDS);

// ══════════════════════════════════════════════════
// 内部工具
// ══════════════════════════════════════════════════

/**
 * 新建 tab 初始形态（openTab 与 restore 共用 —— 恢复的 tab 由此构造，天然非流式）
 * @param {number|string} conversationId - 会话 id
 * @returns {object} tab 对象
 */
function createTab(conversationId) {
    return {
        conversationId,
        characterId: null,
        title: '',
        messages: [],
        scrollTop: 0,
        draft: '',
        isStreaming: false,
        activeStream: null,
        phase: 'idle', // 'idle' | 'thinking' | 'streaming' | 'done' | 'error'
    };
}

/**
 * 将当前 tab 集写入 sessionStorage（只含 ids + activeId）
 * 失败静默降级（隐私模式 / 配额耗尽）——不阻断功能，通知仍照常触发
 */
function persist() {
    try {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(serialize()));
    } catch {
        // sessionStorage 不可用 — 静默降级
    }
}

/**
 * 从 sessionStorage 读取上次序列化的 tab 集（键名由本模块持有）。
 * 读取失败 / JSON 损坏 / 无记录 → null（restore 语义兜底为空集，不抛错）
 * @returns {object|null} 序列化结果（serialize() 的形状）或 null
 */
function readSerialized() {
    try {
        const raw = sessionStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch {
        // sessionStorage 不可用 / 数据损坏 — 静默降级
        return null;
    }
}

/** 触发 onTabsChanged 通知（无参数；监听方自行 getTabs() 取最新快照） */
function notifyChanged() {
    for (const fn of listeners) fn();
}

/** 结构性变更统一出口：持久化 + 通知 */
function commit() {
    persist();
    notifyChanged();
}

// ══════════════════════════════════════════════════
// 协议表面
// ══════════════════════════════════════════════════

/**
 * 打开会话 tab：按 conversationId 去重 —— 已存在仅激活（返回既有 tab），
 * 不存在则新建并激活。null/undefined 视为无效入参，no-op 返回 null。
 * @param {number|string} conversationId - 会话 id
 * @returns {object|null} 该 tab（已存在返回既有对象）；入参无效返回 null
 */
export function openTab(conversationId) {
    if (conversationId == null) return null;
    const existing = getTab(conversationId);
    if (existing) {
        if (activeId !== conversationId) {
            activeId = conversationId;
            commit();
        }
        return existing;
    }
    tabList.push(createTab(conversationId));
    activeId = conversationId;
    commit();
    return getTab(conversationId);
}

/**
 * 激活已有 tab（不新建）。目标不存在或已是活动 tab → no-op，无通知。
 * @param {number|string} conversationId - 会话 id
 */
export function activateTab(conversationId) {
    if (!getTab(conversationId) || activeId === conversationId) return;
    activeId = conversationId;
    commit();
}

/**
 * 内部：移除指定 tab（不 commit；由调用方统一 commit）。
 * activeId 重定位语义与 closeTab 一致：关活动 tab 激活右邻居，无右取左；
 * 关最后一个 → activeId 为 null。
 * @param {number|string} conversationId - 会话 id
 * @returns {boolean} 是否实际移除（不存在 → false）
 */
function removeTab(conversationId) {
    const idx = tabList.findIndex((t) => t.conversationId === conversationId);
    if (idx === -1) return false;
    tabList.splice(idx, 1);
    if (activeId === conversationId) {
        const right = tabList[idx]; // 原右邻居顶上
        const left = tabList[idx - 1]; // 无右取左
        activeId = right ? right.conversationId : (left ? left.conversationId : null);
    }
    return true;
}

/**
 * 关闭会话 tab。关闭的是活动 tab 时激活右邻居，无右取左；
 * 关最后一个 → activeTab 为 null。目标不存在 → no-op。
 * @param {number|string} conversationId - 会话 id
 */
export function closeTab(conversationId) {
    if (removeTab(conversationId)) commit();
}

/**
 * 批量关闭会话 tab（级联删除 / 清空全部的统一批量原语）：
 *   对每个 id 先中止在途流式再移除（abort 全覆盖），逐 tab 语义与多次 closeTab
 *   一致（活动 tab 被关 → 右邻居顶上、无则左；最后一个 → activeTab 为 null）；
 *   整个批次只 commit 一次（单次持久化 + 单次 onTabsChanged，避免 N 次 commit 风暴）。
 *   空数组 / 非数组 / 全部 id 不存在 → no-op 无通知；重复 id 幂等（只关一次）。
 * @param {Array<number|string>} ids - 要关闭的会话 id 列表
 */
export function closeTabs(ids) {
    if (!Array.isArray(ids) || ids.length === 0) return;
    let changed = false;
    for (const conversationId of ids) {
        abortStream(conversationId);
        if (removeTab(conversationId)) changed = true;
    }
    if (changed) commit();
}

/**
 * 关闭全部 tab（清空 tab 集，activeTab 为 null）。
 * 已为空 → no-op，无通知。
 */
export function closeAllTabs() {
    if (tabList.length === 0 && activeId === null) return;
    tabList = [];
    activeId = null;
    commit();
}

/**
 * 获取活动 tab；无任何 tab 时为 null
 * @returns {object|null}
 */
export function getActiveTab() {
    return tabList.find((t) => t.conversationId === activeId) ?? null;
}

/**
 * 按 conversationId 获取 tab；不存在返回 undefined
 * @param {number|string} conversationId - 会话 id
 * @returns {object|undefined}
 */
export function getTab(conversationId) {
    return tabList.find((t) => t.conversationId === conversationId);
}

/**
 * 获取全部 tab 的浅拷贝数组（元素为 live 引用，顺序即展示顺序）
 * @returns {Array<object>}
 */
export function getTabs() {
    return [...tabList];
}

/**
 * 展示契约（ARC-5）：由 tab 状态纯派生 tab 条渲染所需字段，tab-bar.js 渲染
 * 只经本函数取展示字段（不直接读 tab.title / tab.phase）。
 *   - title：缺省「未命名会话」（空串 / null / undefined 时）
 *   - generating：phase 为 thinking | streaming（标题前脉冲点）
 *   - errored：phase 为 error（警示标记）
 *   - phase：原样透传（未知值不抛错、不产生任何指示）
 * 纯函数：不修改输入、每次返回新对象。
 * 约束：本函数派生输入（title/phase）与 DISPLAY_KEYS（updateTab 通知依据）同源自
 * DISPLAY_FIELDS 单一声明表 —— 新增展示字段只改表一处（见上）。
 * @param {object|null} tab - tab 对象（getTabs() 元素）；null/undefined → 缺省形态
 * @returns {{title: string, phase: string, generating: boolean, errored: boolean}}
 */
export function getTabDisplay(tab) {
    const phase = DISPLAY_FIELDS.phase(tab);
    return {
        title: DISPLAY_FIELDS.title(tab),
        phase,
        generating: phase === 'thinking' || phase === 'streaming',
        errored: phase === 'error',
    };
}

/**
 * 浅合并 patch 到 tab 状态；对不存在的 conversationId 幂等 no-op（不抛错、不新增）。
 * conversationId 是身份键，不可经 patch 改写（静默忽略）。
 * 通知分类（FIX-C）：patch 含展示字段（DISPLAY_KEYS —— DISPLAY_FIELDS 声明表键集，
 * 见上）才触发 onTabsChanged —— tab 条只订阅展示字段变化；纯内容 patch
 * （messages/draft/scrollTop 等）不通知，流式逐 token 的 messages 更新不触发
 * tab 条全量重渲染。一律不写 sessionStorage（见模块 docstring）。
 * @param {number|string} conversationId - 会话 id
 * @param {object} patch - 要合并的字段（如 { title, phase, messages, isStreaming }）
 */
export function updateTab(conversationId, patch) {
    const tab = getTab(conversationId);
    if (!tab || !patch || typeof patch !== 'object') return;
    const { conversationId: _identity, ...merged } = patch;
    Object.assign(tab, merged);
    if (DISPLAY_KEYS.some((k) => k in merged)) notifyChanged();
}

/**
 * 中止指定 tab 的在途流式请求（显式停止语义 — 停止按钮 / 删会话 / 关 tab / 清空联动统一入口）
 * 无 tab / 无流式句柄 → no-op；abort() 抛错静默忽略（连接已断开等场景）。
 * @param {number|string} conversationId - 会话 id
 */
export function abortStream(conversationId) {
    const stream = getTab(conversationId)?.activeStream;
    if (!stream) return;
    try {
        stream.abort();
    } catch {
        // 忽略中止失败（连接已断开等场景）
    }
}

/**
 * 序列化 tab 集 —— 只返回 { ids, activeId }，不序列化消息/草稿/滚动等缓存
 * @returns {{ids: Array<number|string>, activeId: number|string|null}}
 */
export function serialize() {
    return {
        ids: tabList.map((t) => t.conversationId),
        activeId,
    };
}

/**
 * 按序列化结果恢复 tab 集（替换当前集）：
 *   - 经 isValidId 回调过滤失效 id（如已删除会话）；activeId 失效回退首个有效 id，
 *     全失效 → 空集
 *   - 恢复的 tab 一律非流式（phase idle、isStreaming false、activeStream null）
 *   - 无有效记录 / serialized 非法（非对象或缺 ids 数组）→ 空集，不报错
 * @param {object|null} serialized - serialize() 的输出（可为 null/损坏数据）
 * @param {object} [options]
 * @param {Function} [options.isValidId] - (conversationId) => boolean；缺省视为全部有效
 * @returns {object|null} 恢复后的活动 tab（空集时为 null）
 */
export function restore(serialized, { isValidId } = {}) {
    const raw = serialized && typeof serialized === 'object' && Array.isArray(serialized.ids)
        ? serialized
        : null;
    const check = typeof isValidId === 'function' ? isValidId : () => true;
    const ids = raw ? [...new Set(raw.ids.filter((id) => check(id)))] : [];
    const active = raw && ids.includes(raw.activeId) ? raw.activeId : (ids[0] ?? null);
    tabList = ids.map((id) => createTab(id));
    activeId = active;
    commit();
    return getActiveTab();
}

/**
 * 从 sessionStorage 读取并恢复 tab 集（init 集成辅助 — P6.5-4 刷新恢复时序）。
 * 等价于 restore(readSerialized(), opts)：无记录 / 数据损坏 / 全失效 → 空集，
 * 不报错；恢复的 tab 一律非流式。任何有效恢复都写回存储并触发通知。
 * @param {object} [options]
 * @param {Function} [options.isValidId] - (conversationId) => boolean；缺省视为全部有效
 * @returns {object|null} 恢复后的活动 tab（空集时为 null）
 */
export function restoreFromStorage({ isValidId } = {}) {
    return restore(readSerialized(), { isValidId });
}

/**
 * 注册 tab 集变更通知（任何结构性变更与 updateTab 内容更新后触发，无参数）
 * @param {Function} fn - 变更回调
 * @returns {Function} 取消订阅函数
 */
export function onTabsChanged(fn) {
    if (typeof fn !== 'function') return () => {};
    listeners.add(fn);
    return () => listeners.delete(fn);
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 tabs.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'openTab',
    'activateTab',
    'closeTab',
    'closeTabs',
    'closeAllTabs',
    'getActiveTab',
    'getTab',
    'getTabs',
    'getTabDisplay',
    'updateTab',
    'abortStream',
    'serialize',
    'restore',
    'restoreFromStorage',
    'onTabsChanged',
];
