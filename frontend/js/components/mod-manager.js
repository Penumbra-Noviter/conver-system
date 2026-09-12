/**
 * Conver System — Mod 管理面板组件（MD-2 / 03 + 04）
 *
 * 全局 Mod 库维护面板：列表（id 升序）/ 新建 / 编辑 / 删除 / 目标区域
 * （prompt|memory|css）/ 导入导出 JSON。骨架（遮罩 / 标题 / 关闭按钮 /
 * 焦点陷阱 / Escape / 遮罩点击）由通用模态框工厂 openModal 承担；图标一律走
 * icons.js 的 iconHtml()（不手写 emoji/SVG 碎片）。
 *
 * MD-2/04 扩展「当前角色挂载」区块：当 showModManager 收到 characterId 时，
 * 与 Mod 库区块并列渲染该角色已挂载 Mod（sort_order 升序），支持挂载新 Mod /
 * 解绑 / 切换启用开关 / 上移下移排序。挂载视图展示 Mod 名称与目标区域时，把
 * 「绑定列表」与「Mod 库列表」按 mod_id 客户端关联（不引入后端嵌套 join）；
 * 未在库中命中的 mod_id（异常数据）显示「未知 Mod」占位不崩溃。
 *
 * 排序落库方式（主会话拍板）：上移/下移 = 与相邻绑定交换 sort_order，落库走
 * mods.setSortOrder(bindingId, sortOrder) 两次调用（binding_id 稳定、无丢失窗口）。
 *
 * 导入导出为纯前端能力：
 *   - 导出 = 取 mods.list() 组装信封 {"version":1,"mods":[...]} → 本地 Blob 下载
 *     （不走 api.js requestBlob：数据在客户端，无服务端导出面；镜像
 *     save-manager.js 的 downloadJson 形态）。
 *   - 导入 = 读文件 → 校验信封（version + mods 数组）→ 逐条 mods.create
 *     （source 落 "imported"）并逐条容错（单条失败不阻断其余）。
 *
 * prompt 区 payload 在 UI 呈现为「三区域文本框 world/before_char/after_char」并
 * 序列化为 JSON 字符串存入 payload；memory/css 区 payload 为自由文本。表单按
 * target_area 切换录入形态。
 *
 * 字段名映射单一来源：buildModPayload（与后端 schemas/mods.py ModCreate 逐字段
 * 一致；name/description/target_area/payload，version/source 由服务端默认）。
 *
 * 协议表面（__all__）：showModManager / computeSortSwap / TARGET_AREAS /
 * serializePromptPayload / parsePromptPayload / validateModForm / buildModPayload /
 * buildExportEnvelope / parseImportEnvelope / importModsFromEnvelope。
 */

import { mods } from '../api.js';
import { iconHtml } from '../icons.js';
import { openModal } from './modal.js';
import { showAlert, showConfirm } from './confirm-dialog.js';
import { escapeHtml } from '../utils.js';

export const __all__ = [
    'showModManager',
    'computeSortSwap',
    'TARGET_AREAS',
    'serializePromptPayload',
    'parsePromptPayload',
    'validateModForm',
    'buildModPayload',
    'buildExportEnvelope',
    'parseImportEnvelope',
    'importModsFromEnvelope',
];

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
        if (m === null || typeof m !== 'object') {
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
 * 计算上移/下移时相邻两项交换 sort_order 后的两次 setSortOrder 参数。
 * 纯函数（不接触 DOM / 不落库），供移动事件处理器与独立单测消费。
 * @param {Array} bindings - 已按 sort_order 升序的绑定列表
 * @param {number} index - 待移动项在列表中的下标
 * @param {'up'|'down'} direction - 移动方向（up=与前一交换，down=与后一交换）
 * @returns {Array<{id: number, sortOrder: number}>} 两次 setSortOrder 调用参数
 *   （边界越界返回空数组 — 调用方据此 no-op）
 */
export function computeSortSwap(bindings, index, direction) {
    if (!Array.isArray(bindings)) return [];
    const target = direction === 'up' ? index - 1 : index + 1;
    if (index < 0 || target < 0 || target >= bindings.length) return [];
    const a = bindings[index];
    const b = bindings[target];
    return [
        { id: a.id, sortOrder: b.sort_order ?? 0 },
        { id: b.id, sortOrder: a.sort_order ?? 0 },
    ];
}

// ════════════════════════════════════════════════════════════════
// 视图
// ════════════════════════════════════════════════════════════════

/**
 * 打开 Mod 管理模态框（Mod 库区块 + 可选「当前角色挂载」区块）。
 * @param {object} opts
 * @param {string} [opts.characterName='角色'] - 角色名（模态框标题）
 * @param {number|null} [opts.characterId=null] - 角色 id；传入时渲染挂载区块
 * @param {function} [opts.onChanged] - 库增删改后回调（如刷新）
 */
export function showModManager({ characterId = null, characterName = '角色', onChanged } = {}) {
    openModal({
        title: `${characterName} 的 Mod 管理`,
        modalClass: 'mod-manager-modal',
        body: '<div class="mod-manager-root" data-mod-manager-root></div>',
        actions: '',
        removeExisting: '.modal-overlay',
        onOpen(overlay) {
            const root = overlay.querySelector('[data-mod-manager-root]');
            renderManager(root, { characterId, onChanged });
        },
    });
}

/**
 * 渲染面板整体：Mod 库区块（恒有）+ 当前角色挂载区块（有 characterId 时并列）。
 * @param {HTMLElement} root - 容器
 * @param {object} opts
 * @param {number|null} opts.characterId - 角色 id（null 则不渲染挂载区块）
 * @param {function|null} opts.onChanged - 变更回调
 */
async function renderManager(root, { characterId, onChanged }) {
    root.innerHTML = `
        <div class="mod-library-section" data-mod-library-section></div>
        ${characterId != null ? '<div class="mod-mount-section" data-mod-mount-section></div>' : ''}
    `;
    const librarySection = root.querySelector('[data-mod-library-section]');
    await renderLibrary(librarySection, onChanged);
    if (characterId != null) {
        const mountSection = root.querySelector('[data-mod-mount-section]');
        await renderMounts(mountSection, characterId, onChanged);
    }
}

/**
 * 渲染 Mod 库列表视图（工具栏 + 列表 + 导入隐藏文件输入）
 * @param {HTMLElement} root - 容器
 * @param {function|null} onChanged - 变更回调
 */
async function renderLibrary(root, onChanged) {
    root.innerHTML = `
        <div class="mod-toolbar">
            <button class="btn btn-primary" data-mod-add>${iconHtml('plus')} 新建 Mod</button>
            <button class="btn" data-mod-export title="导出库为 JSON">${iconHtml('download')} 导出</button>
            <button class="btn" data-mod-import title="从 JSON 导入">${iconHtml('fileJson')} 导入</button>
            <input type="file" data-mod-import-file accept="application/json,.json" hidden>
        </div>
        <div class="mod-list" data-mod-list></div>
    `;
    const listEl = root.querySelector('[data-mod-list]');

    let modsList = [];
    try {
        modsList = await mods.list();
    } catch (err) {
        listEl.innerHTML = `<div class="mod-empty">加载 Mod 库失败：${escapeHtml(err.message)}</div>`;
        return;
    }

    const render = () => {
        const sorted = [...modsList].sort((a, b) => (a.id ?? 0) - (b.id ?? 0));
        listEl.innerHTML = sorted.length
            ? sorted.map((m) => modRowHtml(m)).join('')
            : '<div class="mod-empty">还没有 Mod，点「新建 Mod」开始</div>';
        listEl.querySelectorAll('[data-mod-edit]').forEach((btn) => {
            btn.addEventListener('click', () => renderEditor(
                root,
                modsList.find((m) => m.id === Number(btn.dataset.modEdit)),
                onChanged,
            ));
        });
        listEl.querySelectorAll('[data-mod-del]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const id = Number(btn.dataset.modDel);
                const mod = modsList.find((m) => m.id === id);
                const ok = await showConfirm({
                    title: '删除 Mod',
                    message: `确定删除「${mod?.name ?? ''}」吗？`,
                    detail: '删除后不可恢复',
                    confirmText: '删除',
                    cancelText: '取消',
                    danger: true,
                });
                if (!ok) return;
                try {
                    await mods.delete(id);
                    modsList = modsList.filter((m) => m.id !== id);
                    render();
                    if (onChanged) onChanged();
                } catch (err) {
                    showAlert('删除失败: ' + err.message);
                }
            });
        });
    };

    root.querySelector('[data-mod-add]').addEventListener('click', () => renderEditor(root, null, onChanged));
    root.querySelector('[data-mod-export]').addEventListener('click', () => exportLibrary(modsList));
    root.querySelector('[data-mod-import]').addEventListener('click', () => {
        root.querySelector('[data-mod-import-file]').click();
    });
    root.querySelector('[data-mod-import-file]').addEventListener('change', async (ev) => {
        const file = ev.target.files?.[0];
        if (!file) return;
        let text;
        try {
            text = await readFileText(file);
        } catch {
            showAlert('读取文件失败');
            return;
        }
        const result = await importModsFromEnvelope(text);
        if (!result.ok) {
            showAlert('导入失败: ' + result.error);
            return;
        }
        showAlert(`导入完成：成功 ${result.imported} 条${result.failed ? `，失败 ${result.failed} 条` : ''}`);
        try {
            modsList = await mods.list();
            render();
            if (onChanged) onChanged();
        } catch (err) {
            showAlert('刷新失败: ' + err.message);
        }
    });

    render();
}

/** 列表行 HTML（名称 / 目标区域徽标 / 来源） */
function modRowHtml(mod) {
    const area = mod.target_area || 'prompt';
    return `
        <div class="mod-row">
            <div class="mod-row-main">
                <div class="mod-row-name">${escapeHtml(mod.name || '（未命名）')}</div>
                <div class="mod-row-meta">
                    <span class="mod-badge mod-badge-${escapeHtml(area)}">${escapeHtml(area)}</span>
                    <span class="mod-row-source">${escapeHtml(mod.source || 'manual')}</span>
                </div>
            </div>
            <button class="btn-icon" data-mod-edit="${mod.id}" title="编辑">${iconHtml('edit')}</button>
            <button class="btn-icon" data-mod-del="${mod.id}" title="删除">${iconHtml('trash')}</button>
        </div>`;
}

/** 渲染编辑/新建视图（按 target_area 切换 prompt 三区域 vs 自由文本录入） */
function renderEditor(root, mod, onChanged) {
    const isEdit = Boolean(mod);
    const targetArea = mod?.target_area || 'prompt';
    const prompt = parsePromptPayload(mod?.payload);
    const isPrompt = targetArea === 'prompt';

    root.innerHTML = `
        <div class="mod-editor">
            <div class="form-field">
                <label for="mod-name">名称 <span class="field-error" id="mod-name-error"></span></label>
                <input type="text" id="mod-name" maxlength="200" value="${escapeHtml(mod?.name ?? '')}" placeholder="Mod 名称">
            </div>
            <div class="form-field">
                <label for="mod-desc">说明</label>
                <textarea id="mod-desc" rows="2" placeholder="可选说明">${escapeHtml(mod?.description ?? '')}</textarea>
            </div>
            <div class="form-field">
                <label for="mod-area">目标区域</label>
                <select id="mod-area">
                    <option value="prompt" ${targetArea === 'prompt' ? 'selected' : ''}>prompt（提示词注入）</option>
                    <option value="memory" ${targetArea === 'memory' ? 'selected' : ''}>memory（记忆）</option>
                    <option value="css" ${targetArea === 'css' ? 'selected' : ''}>css（样式）</option>
                </select>
            </div>
            <div class="form-field" data-mod-prompt-fields ${isPrompt ? '' : 'hidden'}>
                <span class="mod-sub-section">Prompt 三区域 payload</span>
                <label for="mod-world">world</label>
                <textarea id="mod-world" rows="3" placeholder="世界知识注入">${escapeHtml(prompt.world)}</textarea>
                <label for="mod-before-char">before_char</label>
                <textarea id="mod-before-char" rows="3" placeholder="角色设定前注入">${escapeHtml(prompt.before_char)}</textarea>
                <label for="mod-after-char">after_char</label>
                <textarea id="mod-after-char" rows="3" placeholder="场景设定后注入">${escapeHtml(prompt.after_char)}</textarea>
            </div>
            <div class="form-field" data-mod-free-fields ${isPrompt ? 'hidden' : ''}>
                <label for="mod-payload">Payload 内容</label>
                <textarea id="mod-payload" rows="5" placeholder="注入内容">${escapeHtml(isPrompt ? '' : (mod?.payload ?? ''))}</textarea>
            </div>
            <div class="mod-editor-actions">
                <button class="btn" id="mod-cancel">返回列表</button>
                <button class="btn btn-primary" id="mod-save">${isEdit ? '保存修改' : '新建 Mod'}</button>
            </div>
        </div>
    `;

    const areaSelect = root.querySelector('#mod-area');
    const promptFields = root.querySelector('[data-mod-prompt-fields]');
    const freeFields = root.querySelector('[data-mod-free-fields]');

    areaSelect.addEventListener('change', () => {
        const isP = areaSelect.value === 'prompt';
        promptFields.hidden = !isP;
        freeFields.hidden = isP;
    });

    root.querySelector('#mod-cancel').addEventListener('click', () => renderLibrary(root, onChanged));
    root.querySelector('#mod-save').addEventListener('click', async () => {
        const form = {
            name: root.querySelector('#mod-name').value,
            description: root.querySelector('#mod-desc').value,
            target_area: areaSelect.value,
            payload: root.querySelector('#mod-payload').value,
            world: root.querySelector('#mod-world').value,
            before_char: root.querySelector('#mod-before-char').value,
            after_char: root.querySelector('#mod-after-char').value,
        };
        const { ok, errors } = validateModForm(form);
        if (!ok) {
            for (const [field, message] of Object.entries(errors)) {
                const el = root.querySelector(`#mod-${field}-error`);
                if (el) el.textContent = message;
            }
            return;
        }
        const payload = buildModPayload(form);
        try {
            if (isEdit) {
                await mods.update(mod.id, payload);
            } else {
                await mods.create(payload);
            }
            if (onChanged) onChanged();
            renderLibrary(root, onChanged);
        } catch (err) {
            showAlert((isEdit ? '保存失败' : '新建失败') + ': ' + err.message);
        }
    });
}

/**
 * FileReader 文本读取（jsdom 与真实浏览器均支持；失败 reject 交调用方兜底）。
 * @param {File} file - 待读取文件
 * @returns {Promise<string>}
 */
function readFileText(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error ?? new Error('读取文件失败'));
        reader.readAsText(file);
    });
}

/**
 * 导出库为本地 JSON Blob 下载（纯前端，不走 api.js requestBlob）。
 * 信封 = {"version":1,"mods":[...]}；jsdom / 极旧环境无 URL.createObjectURL → 提示降级。
 * @param {Array} modsList - 当前库列表
 */
function exportLibrary(modsList) {
    const envelope = buildExportEnvelope(modsList);
    if (typeof URL.createObjectURL !== 'function' || typeof URL.revokeObjectURL !== 'function') {
        showAlert('导出失败：当前环境不支持文件下载');
        return;
    }
    const blob = new Blob([JSON.stringify(envelope, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'mods-library.json';
    a.click();
    URL.revokeObjectURL(url);
}

// ════════════════════════════════════════════════════════════════
// 挂载区块（MD-2/04）— 当前角色已挂载 Mod 的管理
// ════════════════════════════════════════════════════════════════

/**
 * 渲染「当前角色挂载」区块（列表 / 开关 / 挂载 / 解绑 / 上移下移排序）。
 * 绑定列表与 Mod 库列表按 mod_id 客户端关联；未命中显示「未知 Mod」占位。
 * 所有变更操作成功后重拉列表（服务端实况）；失败 → showAlert + 重拉回滚。
 * @param {HTMLElement} root - 区块容器
 * @param {number} characterId - 角色 id
 * @param {function|null} onChanged - 变更回调（挂载变更不触发，保留签名一致）
 */
async function renderMounts(root, characterId, onChanged) {
    root.innerHTML = `
        <div class="mod-mount-heading">当前角色挂载</div>
        <div class="mod-mount-toolbar">
            <select data-mod-bind-select aria-label="选择要挂载的 Mod">
                <option value="">选择 Mod 挂载…</option>
            </select>
            <button class="btn btn-primary" data-mod-bind-add>${iconHtml('plus')} 挂载</button>
        </div>
        <div class="mod-mount-list" data-mod-mount-list></div>
    `;
    const selectEl = root.querySelector('[data-mod-bind-select]');
    const listEl = root.querySelector('[data-mod-mount-list]');

    let bindings = [];
    let modsList = [];
    try {
        [bindings, modsList] = await Promise.all([
            mods.listCharacterMods(characterId),
            mods.list(),
        ]);
    } catch (err) {
        listEl.innerHTML = `<div class="mod-empty">加载挂载失败：${escapeHtml(err.message)}</div>`;
        return;
    }

    const modById = new Map(modsList.map((m) => [m.id, m]));
    const sorted = () => [...bindings].sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0));

    const render = () => {
        const list = sorted();
        listEl.innerHTML = list.length
            ? list.map((b, i) => bindingRowHtml(b, modById.get(b.mod_id), i === 0, i === list.length - 1)).join('')
            : '<div class="mod-empty">该角色还没有挂载 Mod，从上方选择一个 Mod 挂载</div>';
        renderBindOptions(selectEl, modsList, bindings);

        listEl.querySelectorAll('[data-mod-binding-toggle]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const id = Number(btn.dataset.modBindingToggle);
                const binding = bindings.find((b) => b.id === id);
                if (!binding) return;
                try {
                    await mods.setEnabled(id, !binding.enabled);
                    await reload();
                } catch (err) {
                    showAlert('切换失败: ' + err.message);
                    await reload();
                }
            });
        });

        listEl.querySelectorAll('[data-mod-binding-unbind]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const id = Number(btn.dataset.modBindingUnbind);
                const binding = bindings.find((b) => b.id === id);
                const mod = modById.get(binding?.mod_id);
                const ok = await showConfirm({
                    title: '解绑 Mod',
                    message: `确定解绑「${mod?.name ?? '未知 Mod'}」吗？`,
                    detail: '解绑后该 Mod 不再注入此角色（库中仍保留）',
                    confirmText: '解绑',
                    cancelText: '取消',
                    danger: true,
                });
                if (!ok) return;
                try {
                    await mods.unbind(id);
                    await reload();
                } catch (err) {
                    showAlert('解绑失败: ' + err.message);
                    await reload();
                }
            });
        });

        listEl.querySelectorAll('[data-mod-binding-up]').forEach((btn) => {
            btn.addEventListener('click', () => moveBinding(Number(btn.dataset.modBindingUp), 'up'));
        });
        listEl.querySelectorAll('[data-mod-binding-down]').forEach((btn) => {
            btn.addEventListener('click', () => moveBinding(Number(btn.dataset.modBindingDown), 'down'));
        });
    };

    const moveBinding = async (id, direction) => {
        const list = sorted();
        const index = list.findIndex((b) => b.id === id);
        if (index < 0) return;
        const ops = computeSortSwap(list, index, direction);
        if (ops.length === 0) return;
        try {
            await mods.setSortOrder(ops[0].id, ops[0].sortOrder);
            await mods.setSortOrder(ops[1].id, ops[1].sortOrder);
            await reload();
        } catch (err) {
            showAlert('调整排序失败: ' + err.message);
            await reload();
        }
    };

    const reload = async () => {
        try {
            bindings = await mods.listCharacterMods(characterId);
            render();
        } catch (err) {
            showAlert('刷新失败: ' + err.message);
        }
    };

    root.querySelector('[data-mod-bind-add]').addEventListener('click', async () => {
        const modId = Number(selectEl.value);
        if (!modId) {
            showAlert('请先选择一个 Mod');
            return;
        }
        // 客户端重复挂载拦截（后端 ModAlreadyBoundError 400 兜底）
        if (bindings.some((b) => b.mod_id === modId)) {
            showAlert('该 Mod 已挂载');
            return;
        }
        try {
            await mods.bind(characterId, { mod_id: modId });
            await reload();
        } catch (err) {
            showAlert('挂载失败: ' + err.message);
            await reload();
        }
    });

    render();
}

/** 挂载行 HTML（名称 / 区域徽标 / 排序序号 / 上移下移 / 开关 / 解绑） */
function bindingRowHtml(binding, mod, isFirst, isLast) {
    const name = mod ? (mod.name || '（未命名）') : '未知 Mod';
    const area = mod?.target_area || 'unknown';
    const order = binding.sort_order ?? 0;
    return `
        <div class="mod-binding-row" data-binding-id="${binding.id}" data-sort-order="${order}">
            <span class="mod-binding-order" title="排序序号">${order}</span>
            <div class="mod-binding-main">
                <div class="mod-binding-name">${escapeHtml(name)}</div>
                <div class="mod-binding-meta">
                    ${mod
                        ? `<span class="mod-badge mod-badge-${escapeHtml(area)}">${escapeHtml(area)}</span>`
                        : '<span class="mod-badge">未知区域</span>'}
                </div>
            </div>
            <button class="btn-icon mod-binding-up" data-mod-binding-up="${binding.id}" title="上移" ${isFirst ? 'disabled' : ''}>${iconHtml('chevronLeft')}</button>
            <button class="btn-icon mod-binding-down" data-mod-binding-down="${binding.id}" title="下移" ${isLast ? 'disabled' : ''}>${iconHtml('chevronRight')}</button>
            <button class="btn-icon mod-binding-toggle" data-mod-binding-toggle="${binding.id}" title="${binding.enabled ? '点击禁用' : '点击启用'}">${binding.enabled ? iconHtml('toggleOn') : iconHtml('toggleOff')}</button>
            <button class="btn-icon mod-binding-unbind" data-mod-binding-unbind="${binding.id}" title="解绑">${iconHtml('trash')}</button>
        </div>`;
}

/** 挂载下拉选项：只列未挂载 Mod（客户端去重，id 升序） */
function renderBindOptions(selectEl, modsList, bindings) {
    const boundIds = new Set(bindings.map((b) => b.mod_id));
    const unbound = modsList
        .filter((m) => !boundIds.has(m.id))
        .sort((a, b) => (a.id ?? 0) - (b.id ?? 0));
    selectEl.innerHTML = '<option value="">选择 Mod 挂载…</option>' +
        unbound.map((m) => `<option value="${m.id}">${escapeHtml(m.name || '（未命名）')}</option>`).join('');
}
