/**
 * Conver System — 存档管理面板（深模块，U9-T2）
 *
 * 职责：列表页工具条「存档管理」按钮打开的独立存档面板全部逻辑收口 ——
 *   游戏存档列表（每游戏：存档键数 / 总大小（字符数））、单游戏导出 JSON
 *   （Blob 下载）、导入恢复（键名白名单校验，任一非法整包拒绝）、删除
 *   （确认后清除）。无 saveKeys 的游戏显示「无存档管理」降级态；wg_ 族
 *   （小马宝莉 / 高中生模拟器）注记「仅会话内生效，重进需重注」。
 *
 * 依赖方向：save-manager.js → utils.js（escapeHtml / showToast）/
 *   components/confirm-dialog.js（showConfirm 删除确认）；
 *   app.js → save-manager.js（initSaveManager 接线 + openSavePanel 接到
 *   工具条按钮 + 切走 simulators 视图时 closeSavePanel 复位 — 沿用运行
 *   视图销毁纪律）。游戏列表经注入 getGames 钩子获取（G7 注入钩子模式，
 *   先例 onOpenGame），不重复 fetch manifest。
 *
 * saveKeys 白名单契约（U9-T1，与 simulators.js 共享 — 契约常量单一来源见
 *   js/save-key-meta.js（TD-67/68 契约之家：SAVE_KEY_META_RE / escapeRegExp /
 *   WG_SESSION_ONLY_IDS））：v2 条目声明存档键白名单，数组元素为字符串 ——
 *   不含正则元字符的字符串 = 精确键名（=== 匹配）；含正则元字符的字符串 =
 *   正则模式（锚定完整键名 ^…$ 匹配）。收集 / 导出 / 校验 / 应用四步共用
 *   同一匹配语义（whitelistHits 内部助手）。白名单条目非字符串 / 不可编译 →
 *   跳过（防御 parseManifest 之外的原始数据）。
 *
 * 排除面（spec 决策 E）：cfg 键（含 API Key）与主应用自身键由 saveKeys
 *   白名单天然排除 —— 导出导不出来、导入写不进去；主应用当前零
 *   localStorage 键，无干扰面。仿微 wxai_state_v1 为单键混装（配置 +
 *   状态，含游戏内 API Key）已收录 saveKeys（U9-T1 决策，键无法拆分）——
 *   面板固定提示「导出文件可能包含游戏内配置数据（如 API Key），请妥善
 *   保管」。
 *
 * DOM 契约：三面板（#simulator-list-panel / #simulator-run-panel /
 *   #simulator-save-panel）来自 index.html U7-T1 骨架 + 本工单静态容器，
 *   经 initSaveManager 注入绑定（缺失 → no-op 不抛错）；存档面板内容全部
 *   由本模块渲染。面板显隐走 hidden 属性（style.css 对
 *   #simulator-save-panel 设 display 时须补 [hidden] 覆盖 — T2 样式契约）。
 *   存档面板仅从列表页工具条可达，与运行视图天然互斥（运行中列表隐藏，
 *   按钮不可见）；openSavePanel 防御性同时隐藏列表/运行两面板。
 *
 * 存档读写：jsdom 原生 localStorage 无新 seam —— 纯函数（收集/导出/校验/
 *   应用/删除）接受 storage 参数（Storage 兼容对象；生产传 window.localStorage，
 *   测试可注入假件），面板流程直接用 window.localStorage。
 *
 * 导入文件读取：隐藏 input[type=file] + FileReader（文本读取）+ 文件大小
 *   守卫（上限 MAX_IMPORT_BYTES = 5MB，超限整包拒绝 — 实现时定上限记录）。
 *   校验失败文案：整包拒绝时列出全部问题（键名不在白名单 / 值非合法 JSON
 *   字符串），至多 MAX_REPORTED_ISSUES = 10 条，超出截断并计数。
 *
 * 协议表面（__all__）：initSaveManager / openSavePanel / closeSavePanel /
 *   collectGameKeys / buildExportPayload / validateImportPayload /
 *   applyImportPayload / deleteGameKeys。
 */

import { escapeHtml, showToast } from './utils.js';
import { showConfirm } from './components/confirm-dialog.js';
import { SAVE_KEY_META_RE, WG_SESSION_ONLY_IDS } from './save-key-meta.js';

// ══════════════════════════════════════════════════
// 常量（UI 契约 — 文案/上限与 spec 对齐）
// ══════════════════════════════════════════════════

/** 正则元字符集：saveKeys 元素含任一字符即按正则模式处理 — 单一来源：
 *  js/save-key-meta.js（契约之家，TD-67/68） */

/** 面板固定提示：导出可能包含游戏内配置数据（仿微 wxai_state_v1 单键混装注记） */
const EXPORT_HINT = '导出文件可能包含游戏内配置数据（如 API Key），请妥善保管';

/** 无 saveKeys 游戏降级文案（spec 逐字） */
const NO_SAVE_TEXT = '无存档管理';

/** wg_ 族（仅会话内生效）注记文案（spec 逐字） */
const WG_NOTE = '仅会话内生效，重进需重注';

/** wg_ 族游戏 id 集（小马宝莉 / 高中生模拟器 — 键形 'wg_' + CFG.id + '_save'）：
 *  单一来源 js/save-key-meta.js（WG_SESSION_ONLY_IDS，契约之家，TD-67/68） */

/** 导入文件大小守卫上限（字节；localStorage 同源总量约 5MB，单文件不超此限） */
const MAX_IMPORT_BYTES = 5 * 1024 * 1024;

/** 导入校验失败文案列出问题条数上限（超出截断并计数） */
const MAX_REPORTED_ISSUES = 10;

// ══════════════════════════════════════════════════
// 模块级状态（UI 实现细节 — 不属全局应用状态）
// ══════════════════════════════════════════════════

/** 存档面板容器（initSaveManager 注入；未 init 时为 null） */
let savePanel = null;

/** 列表面板容器（initSaveManager 注入；未 init 时为 null） */
let listPanel = null;

/** 运行面板容器（initSaveManager 注入；openSavePanel 防御性隐藏） */
let runPanel = null;

/** 游戏列表获取钩子（app.js 注入；未注入时返回空列表） */
let getGames = () => [];

/** 事件绑定守卫：首次 initSaveManager 绑定后置位，重复调用仅更新钩子/引用 */
let bound = false;

/** 导入目标游戏 id（点「导入」时记录，文件选择器 change 时消费） */
let pendingGameId = null;

// ══════════════════════════════════════════════════
// 内部工具：白名单匹配（收集/导出/校验/应用共用同一语义）
// ══════════════════════════════════════════════════

/**
 * saveKeys 白名单是否命中给定键名（锚定完整键名匹配）。
 *
 * 条目语义与 simulators.js normalizeSaveKeys 契约一致：不含正则元字符的
 * 字符串 = 精确键名（===）；含正则元字符的字符串 = 正则模式（^…$ 锚定）。
 * 防御：条目非字符串 → 跳过；模式不可编译 → 跳过（parseManifest 已归一化，
 * 此分支防直接调用方传入原始数据）。任一命中即 true。
 *
 * @param {unknown} saveKeys - 游戏 saveKeys 白名单（parseManifest 归一化数组）
 * @param {string} keyName - 待判定键名
 * @returns {boolean} 命中任一白名单条目
 */
function whitelistHits(saveKeys, keyName) {
    if (!Array.isArray(saveKeys) || typeof keyName !== 'string') return false;
    for (const entry of saveKeys) {
        if (typeof entry !== 'string' || entry === '') continue;
        if (SAVE_KEY_META_RE.test(entry)) {
            try {
                if (new RegExp(`^${entry}$`).test(keyName)) return true;
            } catch {
                continue; // 不可编译 → 跳过该条目
            }
        } else if (entry === keyName) {
            return true;
        }
    }
    return false;
}

// ══════════════════════════════════════════════════
// 纯函数：键收集 / 导出 / 校验 / 应用 / 删除
// ══════════════════════════════════════════════════

/**
 * 收集游戏中命中 saveKeys 白名单且当前存在的 localStorage 键（存档键收集）。
 *
 * 枚举 storage 全部键名（Storage.length/key(i) 协议），按白名单匹配语义
 * （精确 === / 正则 ^…$ 锚定）筛选；cfg 键（含 API Key）与主应用自身键
 * 不在白名单内 → 天然排除。saveKeys undefined / 空数组 → 空收集（undefined
 * 即「无存档管理」降级信号）。返回排序去重后的键名数组（不依赖枚举顺序）。
 *
 * @param {unknown} game - 游戏条目（parseManifest 归一化；saveKeys 为白名单）
 * @param {unknown} storage - Storage 兼容对象（生产 window.localStorage）
 * @returns {string[]} 命中白名单且存在的键名（升序、去重）
 */
export function collectGameKeys(game, storage) {
    if (game === null || typeof game !== 'object' || Array.isArray(game)) return [];
    if (!Array.isArray(game.saveKeys)) return [];
    if (storage === null || typeof storage !== 'object' || typeof storage.key !== 'function' || typeof storage.length !== 'number') {
        return [];
    }
    const hit = new Set();
    for (let i = 0; i < storage.length; i++) {
        const name = storage.key(i);
        if (typeof name !== 'string') continue;
        if (whitelistHits(game.saveKeys, name)) hit.add(name);
    }
    return [...hit].sort();
}

/**
 * 构建单游戏导出 JSON 载荷（导出文件内容契约）。
 *
 * 形状：{game_id, game_name, saved_at, keys:{键:值}}。收录规则：
 *   - 仅收录 keyNames 中命中 saveKeys 白名单（防御：直接传入的 cfg 键名
 *     不收录 — 「导出导不出来」）且当前存在于 storage 的键；
 *   - 值取 storage 原文（Storage 值恒为字符串）。
 * saved_at 可注入（纯函数确定性；生产不传，默认当前 ISO 时间）。
 *
 * @param {unknown} game - 游戏条目（非对象 → game_id/game_name 空串防御）
 * @param {unknown} keyNames - 候选键名数组（通常为 collectGameKeys 产物）
 * @param {unknown} storage - Storage 兼容对象（null → keys 为空对象）
 * @param {string} [now] - saved_at 值（默认 new Date().toISOString()）
 * @returns {{game_id: string, game_name: string, saved_at: string, keys: Record<string,string>}}
 */
export function buildExportPayload(game, keyNames, storage, now = new Date().toISOString()) {
    const g = game !== null && typeof game === 'object' && !Array.isArray(game) ? game : {};
    const keys = {};
    if (Array.isArray(keyNames) && storage !== null && typeof storage === 'object'
        && typeof storage.getItem === 'function' && Array.isArray(g.saveKeys)) {
        for (const name of keyNames) {
            if (typeof name !== 'string') continue;
            if (!whitelistHits(g.saveKeys, name)) continue; // 白名单防御：cfg 键不导出
            const value = storage.getItem(name);
            if (value === null || value === undefined) continue; // 只导出存在的键
            keys[name] = String(value);
        }
    }
    return {
        game_id: typeof g.id === 'string' ? g.id : '',
        game_name: typeof g.name === 'string' ? g.name : '',
        saved_at: now,
        keys,
    };
}

/**
 * 校验导入载荷（键名白名单 + 值类型，任一问题整包拒绝）。
 *
 * 契约（spec 决策 H）：键名须命中该游戏 saveKeys 白名单（匹配语义与
 *   收集一致 — 正则模式条目按锚定正则判定，键名本身含正则元字符不按字面
 *   放行）；值仅校验 string + JSON 可解析（JSON.parse 不抛错，含 '' 拒绝）。
 *   任一问题 → {ok:false, error}（列出全部问题，至多 MAX_REPORTED_ISSUES 条，
 *   超出截断计数），调用方不得写入任何键；全部合法 → {ok:true, keys}。
 *   game_id / game_name / saved_at 为元数据不校验（白名单是安全边界）。
 *   keys 缺失 / 非普通对象 → 拒绝；keys 为空对象 → 合法空包（应用 no-op）。
 *   game 无 saveKeys → 整体拒绝（「无存档管理」游戏不可导入）。
 *   累积器为无原型对象（TD-70）：合法键含 '__proto__' 时按普通自有属性
 *   累积，不被原型 setter 吞掉 — 白名单命中即可完整写出。
 *
 * @param {unknown} payload - JSON.parse 后的导入载荷
 * @param {unknown} game - 目标游戏条目（saveKeys 为白名单）
 * @returns {{ok: true, keys: Record<string,string>}|{ok: false, error: string}}
 */
export function validateImportPayload(payload, game) {
    if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
        return { ok: false, error: '存档文件格式无效：顶层必须是对象' };
    }
    if (!('keys' in payload)) {
        return { ok: false, error: '存档文件缺少 keys 字段' };
    }
    if (payload.keys === null || typeof payload.keys !== 'object' || Array.isArray(payload.keys)) {
        return { ok: false, error: '存档文件 keys 字段必须是对象' };
    }
    const saveKeys = game !== null && typeof game === 'object' ? game.saveKeys : undefined;
    if (!Array.isArray(saveKeys)) {
        return { ok: false, error: '该游戏无存档管理（saveKeys 未声明），无法导入' };
    }

    const problems = [];
    const valid = Object.create(null); // TD-70：无原型累积器（__proto__ 键不被原型吞掉）
    for (const [key, value] of Object.entries(payload.keys)) {
        if (!whitelistHits(saveKeys, key)) {
            problems.push(`键「${key}」不在该游戏存档键白名单内`);
            continue;
        }
        if (typeof value !== 'string' || !isJsonString(value)) {
            problems.push(`键「${key}」的值不是合法 JSON 字符串`);
            continue;
        }
        valid[key] = value;
    }
    if (problems.length > 0) {
        const shown = problems.slice(0, MAX_REPORTED_ISSUES).join('；');
        const suffix = problems.length > MAX_REPORTED_ISSUES
            ? `；…等共 ${problems.length} 个问题（仅列出前 ${MAX_REPORTED_ISSUES} 个）`
            : '';
        return { ok: false, error: `存档文件校验失败：${shown}${suffix}` };
    }
    return { ok: true, keys: valid };
}

/** 值是否 string 且 JSON 可解析（'' / 非 JSON 文本 → false） */
function isJsonString(value) {
    try {
        JSON.parse(value);
        return true;
    } catch {
        return false;
    }
}

/**
 * 应用导入载荷：白名单键同名替换写回 storage（spec 决策 H）。
 *
 * 防御（导出/导入排除面收口）：仅写入命中 saveKeys 白名单的键 — 直接
 *   调用本函数传入非白名单键也不写入（「导入写不进去」）；值非字符串
 *   跳过。validateImportPayload 是 UI 边界的整包拒绝闸门，本函数为
 *   应用层防御。空对象 / 无 saveKeys / storage 缺失 → no-op 返回 0。
 *
 * 失败回滚（TD-63 裁定修法 = 写前快照，非容量预检 — localStorage 无剩余
 *   容量 API）：每个待写键先记录快照 {key, prev: getItem(key)} 再 setItem；
 *   任一键写入抛异常 → 已写键逆序尽力回滚（prev 为 null/undefined →
 *   removeItem，否则 setItem 还原原值）→ 异常上抛（调用方可安全提示
 *   用户）。回滚为尽力而为（TD-73）：单个键还原失败（如存储仍不可写）
 *   不中断循环 — 继续尝试还原其余键，失败键残留新值；循环结束统一抛
 *   原始 err（回滚异常不遮蔽写入异常）。抛错键本身未写入（setItem
 *   原子性），无需回滚该键。快照仅覆盖实际写入路径（白名单命中且值为
 *   字符串的键），守卫先行、被跳过键不触碰 storage。
 *
 * @param {unknown} game - 游戏条目（saveKeys 为白名单）
 * @param {unknown} keys - {键: 值} 映射（validateImportPayload 产物）
 * @param {unknown} storage - Storage 兼容对象
 * @returns {number} 实际写入的键数；写入失败时尽力回滚并抛原始错（不返回）
 */
export function applyImportPayload(game, keys, storage) {
    if (game === null || typeof game !== 'object' || Array.isArray(game)) return 0;
    if (!Array.isArray(game.saveKeys)) return 0;
    if (keys === null || typeof keys !== 'object' || Array.isArray(keys)) return 0;
    if (storage === null || typeof storage !== 'object' || typeof storage.setItem !== 'function') return 0;
    /** 已成功写入键的快照（{key, prev} — 回滚依据；prev null/undefined = 写前不存在） */
    const written = [];
    try {
        for (const [key, value] of Object.entries(keys)) {
            if (!whitelistHits(game.saveKeys, key)) continue; // 防御：非白名单不写入
            if (typeof value !== 'string') continue;
            const prev = storage.getItem(key); // 写前快照（TD-63）
            storage.setItem(key, value);
            written.push({ key, prev });
        }
    } catch (err) {
        // 尽力而为回滚（TD-73）：已写键逆序逐个还原（新增键移除 / 旧值
        // 还原）。单个键还原失败（如存储仍不可写）不中断循环、不遮蔽原始
        // err — 其余键继续尝试还原；循环结束统一抛原始异常（同一性保留）。
        for (let i = written.length - 1; i >= 0; i--) {
            const { key, prev } = written[i];
            try {
                if (prev === null || prev === undefined) storage.removeItem(key);
                else storage.setItem(key, prev);
            } catch {
                // 单个键还原失败 → 继续尝试其余键（尽力而为，失败键残留新值）
            }
        }
        throw err;
    }
    return written.length;
}

/**
 * 删除游戏全部命中 saveKeys 白名单且存在的键（确认由 UI 层负责）。
 *
 * 与 collectGameKeys 同语义；主应用自身键与 cfg 键不在白名单内 → 不误伤。
 * game / storage 缺失 → 空结果 no-op。
 *
 * @param {unknown} game - 游戏条目（saveKeys 为白名单）
 * @param {unknown} storage - Storage 兼容对象
 * @returns {string[]} 实际被删除的键名列表（供提示「已删除 N 个存档键」）
 */
export function deleteGameKeys(game, storage) {
    const keyNames = collectGameKeys(game, storage);
    if (keyNames.length === 0) return [];
    if (storage === null || typeof storage !== 'object' || typeof storage.removeItem !== 'function') return [];
    for (const name of keyNames) storage.removeItem(name);
    return keyNames;
}

// ══════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════

/** 按注入钩子取游戏列表（getGames 非函数 / 返回非数组 → 空列表，防御不炸） */
function getGamesList() {
    const list = typeof getGames === 'function' ? getGames() : [];
    return Array.isArray(list) ? list : [];
}

/** 按 id 从当前游戏列表取条目（列表刷新后仍取最新） */
function getGameById(gameId) {
    return getGamesList().find((g) => g !== null && typeof g === 'object' && g.id === gameId);
}

/**
 * 渲染存档面板（header + 导出提示 + 游戏列表 + 隐藏文件输入）。
 * 游戏行：有 saveKeys → 名称 / 键数 / 总大小（字符数）/ 操作按钮（零键时
 *   导出删除禁用）；无 saveKeys → 「无存档管理」降级态；wg_ 族 → 会话内
 *   注记（仍按 saveKeys 管理）。game.id 经 dataset 赋值（数据通道单一化
 *   纪律 — 属性值不嵌 HTML 字符串，simulators.js 先例）。
 */
function renderSavePanel() {
    const list = getGamesList();
    const rows = list.map((game) => renderGameRow(game)).join('');
    savePanel.innerHTML = `
        <div class="sim-save-header">
            <button type="button" class="sim-save-back">返回</button>
            <h3 class="sim-save-title">存档管理</h3>
        </div>
        <p class="sim-save-hint">${EXPORT_HINT}</p>
        <div class="sim-save-list">${rows || '<p class="sim-save-empty">暂无游戏数据</p>'}</div>
        <input type="file" class="sim-save-file-input" accept=".json,application/json" hidden>
    `;
    savePanel.querySelectorAll('.sim-save-game').forEach((el, i) => {
        el.dataset.id = String(list[i]?.id ?? '');
    });
}

/**
 * 安全键收集 + 大小统计（TD-69）：window.localStorage 访问抛错（如存储被
 *   禁用 SecurityError）→ 降级 {keys: [], totalChars: 0} — 渲染「0 个存档」
 *   + 导出/删除按钮禁用，面板打开不崩（操作路径健壮性不在本批范围）。
 * @param {unknown} game - 游戏条目（saveKeys 为白名单）
 * @returns {{keys: string[], totalChars: number}} 收集结果或降级空结果
 */
function collectKeysSafely(game) {
    try {
        const keys = collectGameKeys(game, window.localStorage);
        const totalChars = keys.reduce(
            (n, k) => n + String(window.localStorage.getItem(k) ?? '').length, 0,
        );
        return { keys, totalChars };
    } catch {
        return { keys: [], totalChars: 0 };
    }
}

/**
 * 渲染单个游戏行（内部：renderSavePanel 使用；game 非对象防御 → 空串行）。
 * @param {unknown} game - 游戏条目
 * @returns {string} 行 HTML
 */
function renderGameRow(game) {
    const g = game !== null && typeof game === 'object' ? game : {};
    const name = typeof g.name === 'string' ? g.name : '';
    // 名称与 id 兜底均经 escapeHtml（manifest 第三方数据 — 文本上下文不产生属性）
    const displayName = escapeHtml(name) || escapeHtml(String(g.id ?? ''));
    if (!Array.isArray(g.saveKeys)) {
        return `<article class="sim-save-game sim-save-degraded">
            <span class="sim-save-game-name">${displayName}</span>
            <span class="sim-save-note">${NO_SAVE_TEXT}</span>
        </article>`;
    }
    const { keys, totalChars } = collectKeysSafely(g); // TD-69：存储异常降级空结果
    const wgNote = typeof g.id === 'string' && WG_SESSION_ONLY_IDS.has(g.id)
        ? `<span class="sim-save-note sim-save-wg-note">${WG_NOTE}</span>` : '';
    const disabled = keys.length === 0 ? ' disabled' : '';
    return `<article class="sim-save-game">
        <div class="sim-save-game-name">${displayName}</div>
        <div class="sim-save-meta">${keys.length} 个存档 · ${totalChars} 字符</div>
        ${wgNote}
        <div class="sim-save-actions">
            <button type="button" class="sim-save-btn sim-save-export" data-action="export"${disabled}>导出</button>
            <button type="button" class="sim-save-btn sim-save-import" data-action="import">导入</button>
            <button type="button" class="sim-save-btn sim-save-delete" data-action="delete"${disabled}>删除</button>
        </div>
    </article>`;
}

// ══════════════════════════════════════════════════
// 操作流（导出 / 导入 / 删除）
// ══════════════════════════════════════════════════

/**
 * 导出文件名净化（TD-65）：控制字符（\x00-\x1f\x7f）/ 引号 / 反斜杠 / 正斜杠 /
 *  冒号 / 星号 / 问号 / 尖括号 / 竖线 / 百分号 → '_'；trim 尾部点与空格；
 *  空结果兜底 'game'。正常 id 经净化后不变（既有契约断言
 *  `<gameId>-saves.json` 保持绿）。
 * @param {unknown} name - 待净化文件名（非字符串 → 'game' 防御）
 * @returns {string} 净化后的文件名
 */
function sanitizeFilename(name) {
    if (typeof name !== 'string') return 'game';
    const cleaned = name.replace(/[\x00-\x1f\x7f"\\/:*?<>|%]/g, '_').replace(/[. ]+$/, '');
    return cleaned === '' ? 'game' : cleaned;
}

/**
 * Blob JSON 下载（客户端导出 — 不走 api.js requestBlob：数据在本地 localStorage，
 * 无服务端导出面）。URL.createObjectURL 缺失（jsdom / 极旧环境）→ toast 降级
 * 不抛错。文件名 `${sanitizeFilename(gameId)}-saves.json`（TD-65 净化）。
 * @param {object} payload - buildExportPayload 产物
 * @param {string} filename - 下载文件名
 */
function downloadJson(payload, filename) {
    if (typeof URL.createObjectURL !== 'function' || typeof URL.revokeObjectURL !== 'function') {
        showToast('导出失败：当前环境不支持文件下载', 'error');
        return;
    }
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

/** 导出单游戏：收集命中键 → 构建载荷 → Blob 下载。零键 → toast 提示不下载。 */
function exportGame(gameId) {
    const game = getGameById(gameId);
    if (!game) return;
    const keyNames = collectGameKeys(game, window.localStorage);
    if (keyNames.length === 0) {
        showToast('没有可导出的存档键', 'error');
        return;
    }
    const payload = buildExportPayload(game, keyNames, window.localStorage);
    downloadJson(payload, `${sanitizeFilename(gameId)}-saves.json`); // TD-65：文件名净化
}

/**
 * 删除单游戏存档：确认弹窗（showConfirm）→ 清除全部命中键 → toast + 刷新列表。
 * 零键（防御：按钮已禁用）→ 提示不弹窗。
 */
async function deleteGame(gameId) {
    const game = getGameById(gameId);
    if (!game) return;
    const keyNames = collectGameKeys(game, window.localStorage);
    if (keyNames.length === 0) {
        showToast('没有可删除的存档键', 'error');
        return;
    }
    const confirmed = await showConfirm({
        title: '删除存档',
        message: `确定删除「${typeof game.name === 'string' ? game.name : gameId}」的全部存档吗？`,
        detail: `将清除 ${keyNames.length} 个存档键，此操作不可恢复。`,
        confirmText: '删除',
        cancelText: '取消',
        danger: true,
    });
    if (!confirmed) return;
    const removed = deleteGameKeys(game, window.localStorage);
    showToast(`已删除 ${removed.length} 个存档键`, 'success');
    renderSavePanel();
}

/** FileReader 文本读取（jsdom 与真实浏览器均支持；失败 reject 交调用方兜底） */
function readFileText(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error ?? new Error('读取文件失败'));
        reader.readAsText(file);
    });
}

/**
 * 导入文件处理（隐藏 input change）：大小守卫 → JSON.parse → 白名单校验
 * （任一非法整包拒绝，不写任何键）→ 应用（同名键替换）→ toast + 刷新列表。
 * 文件选择后清空 input.value（允许重复选择同一文件）。导入目标在进入处理
 * 的第一时间清空（TD-64：capture-then-clear 置于所有早退路径之前 — 取消 /
 * 超限不残留目标，下次导入不会应用到错误的游戏）。应用写入失败（TD-63，
 * 如存储配额）→ 已回滚 + toast「导入失败：存储空间不足或写入失败」+
 * 刷新面板，不残留半截数据。
 */
async function handleImportChange(e) {
    const input = e?.target;
    const file = input?.files?.[0];
    const gameId = pendingGameId; // TD-64：先捕获…
    pendingGameId = null;         // …再清空（置于所有早退路径之前）
    if (input) input.value = '';
    if (!file) return;
    if (file.size > MAX_IMPORT_BYTES) {
        showToast(`存档文件过大（上限 ${MAX_IMPORT_BYTES / 1024 / 1024}MB）`, 'error');
        return;
    }
    const game = gameId ? getGameById(gameId) : null;
    if (!game || !Array.isArray(game.saveKeys)) {
        showToast('该游戏无存档管理，无法导入', 'error');
        return;
    }
    let payload;
    try {
        const text = await readFileText(file);
        payload = JSON.parse(text);
    } catch {
        showToast('不是有效的 JSON 文件', 'error');
        return;
    }
    const result = validateImportPayload(payload, game);
    if (!result.ok) {
        showToast(result.error, 'error');
        return;
    }
    let written;
    try {
        written = applyImportPayload(game, result.keys, window.localStorage);
    } catch {
        // TD-63：写入失败已回滚 — 错误提示 + 刷新面板（不残留半截数据）
        showToast('导入失败：存储空间不足或写入失败', 'error');
        renderSavePanel();
        return;
    }
    showToast(`已恢复 ${written} 个存档键`, 'success');
    renderSavePanel();
}

// ══════════════════════════════════════════════════
// 对外入口（面板初始化 / 开关）
// ══════════════════════════════════════════════════

/**
 * 初始化存档管理面板：绑定三面板引用 + getGames 钩子 + 事件委托（click /
 *   change — 挂在持久面板根元素上，重渲染不丢监听）。
 *
 * 幂等：重复调用仅更新引用与钩子、不重复绑定事件（simulators.js 先例）。
 * 面板缺失（index.html 契约被破坏的极端场景）→ no-op 不抛错；未 init 时
 * openSavePanel / closeSavePanel 均 no-op。runPanel 可缺省（注入时
 * openSavePanel 防御性一并隐藏，保证三面板互斥）。
 * @param {object} [options]
 * @param {HTMLElement} [options.savePanel] - 存档面板容器（#simulator-save-panel）
 * @param {HTMLElement} [options.listPanel] - 列表面板（#simulator-list-panel）
 * @param {HTMLElement} [options.runPanel] - 运行面板（#simulator-run-panel，可缺省）
 * @param {Function} [options.getGames] - () => 游戏列表（parseManifest 归一化
 *   条目；未注入时面板渲染空列表不报错）
 */
export function initSaveManager({ savePanel: sp, listPanel: lp, runPanel: rp, getGames: hook } = {}) {
    if (!sp || !lp) return;
    savePanel = sp;
    listPanel = lp;
    runPanel = rp;
    if (typeof hook === 'function') getGames = hook;
    if (bound) return; // 幂等守卫：已绑定则早退（钩子已在上方更新）

    savePanel.addEventListener('click', (e) => {
        if (e.target.closest('.sim-save-back')) {
            closeSavePanel();
            return;
        }
        const row = e.target.closest('.sim-save-game');
        const btn = e.target.closest('[data-action]');
        if (!row || !btn) return;
        const gameId = row.dataset.id;
        if (btn.dataset.action === 'export') exportGame(gameId);
        else if (btn.dataset.action === 'import') {
            pendingGameId = gameId;
            savePanel.querySelector('.sim-save-file-input')?.click();
        } else if (btn.dataset.action === 'delete') {
            deleteGame(gameId);
        }
    });
    savePanel.addEventListener('change', (e) => {
        if (e.target?.classList?.contains('sim-save-file-input')) handleImportChange(e);
    });
    bound = true;
}

/**
 * 打开存档面板：隐藏列表/运行两面板，显示存档面板并渲染游戏列表。
 * 仅列表页工具条可达（运行中列表隐藏 → 按钮不可见，天然互斥）；未 init →
 * no-op 不抛错；runPanel 未注入时只隐藏列表面板。
 */
export function openSavePanel() {
    if (!savePanel || !listPanel) return;
    listPanel.hidden = true;
    if (runPanel) runPanel.hidden = true;
    savePanel.hidden = false;
    renderSavePanel();
}

/**
 * 关闭存档面板，返回列表：隐藏存档面板、显示列表面板、清空面板内容
 * （销毁纪律 — 沿用运行视图 closeSimulator 行为）并复位导入目标。未 init /
 * 已关闭 → no-op 不抛错。
 */
export function closeSavePanel() {
    if (!savePanel || !listPanel) return;
    savePanel.hidden = true;
    listPanel.hidden = false;
    savePanel.innerHTML = '';
    pendingGameId = null;
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些函数与 save-manager.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'initSaveManager',
    'openSavePanel',
    'closeSavePanel',
    'collectGameKeys',
    'buildExportPayload',
    'validateImportPayload',
    'applyImportPayload',
    'deleteGameKeys',
];
