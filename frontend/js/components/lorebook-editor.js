/**
 * Conver System — 世界书编辑器组件（WL-4）
 *
 * 角色世界书条目 CRUD 面板。列表 + 编辑表单双视图；骨架（遮罩/标题/关闭按钮/
 * 焦点陷阱/Escape/遮罩点击）由通用模态框工厂 openModal 承担（ARC-10 C3 seam，
 * 不新造骨架）。图标一律走 icons.js 的 iconHtml()（不新增 emoji 字面量）。
 *
 * 协议表面（__all__）：showLorebookEditor / isGenericKey / validateLorebookEntry /
 * buildLorebookPayload / addKeyChip / removeKeyChip。
 *
 * 字段名映射单一来源：buildLorebookPayload（与后端 schemas/lorebook.py
 * LorebookEntryBase 逐字段一致；新增字段先改后端 schema 再改此映射，
 * 契约锁 lorebook-editor.test.js 锁定字段名集合）。
 */

import { lorebook } from '../api.js';
import { iconHtml } from '../icons.js';
import { openModal } from './modal.js';
import { showAlert } from './confirm-dialog.js';
import { escapeHtml } from '../utils.js';

export const __all__ = [
    'showLorebookEditor',
    'isGenericKey',
    'validateLorebookEntry',
    'buildLorebookPayload',
    'addKeyChip',
    'removeKeyChip',
];

//: 单条内容长度上限（对标站实测约束；WL-4 默认 20000 字符，可调）
export const CONTENT_MAX_LENGTH = 20000;

//: 高频泛词黑名单（单字符或多字符无信息量虚词/标点 → 泛词告警）
export const GENERIC_KEYS = new Set([
    '你', '我', '他', '她', '它', '的', '了', '是', '在', '有', '这', '那',
    '。', '，', '！', '？', '、', '；', '：', ' ', '',
]);

//: 数值边界（与后端 schemas/lorebook.py Field 约束一致；拒语义由后端锁，
//: 前端在提交前拦截并给内联错误）
const BOUNDS = {
    order: { min: 0, max: 9999 },
    probability: { min: 1, max: 100 },
    depth: { min: 0, max: 20 },
    group_weight: { min: 1, max: 100 },
};

// ════════════════════════════════════════════════════════════════
// 纯函数核（可独立单测）
// ════════════════════════════════════════════════════════════════

/**
 * 泛词判定：单字符 或 高频无信息量词 → 告警（关键词过泛会显著增加注入量）
 * @param {string} key - 关键词
 * @returns {boolean}
 */
export function isGenericKey(key) {
    const k = String(key || '').trim();
    return k.length <= 1 || GENERIC_KEYS.has(k);
}

/**
 * 关键词 chips 录入（去重/裁剪/空拒）
 * @param {string[]} keys - 现有关键词列表
 * @param {string} key - 待录入关键词
 * @returns {string[]} 新列表（空输入返回原列表；重复返回原列表）
 */
export function addKeyChip(keys, key) {
    const k = String(key || '').trim();
    if (!k) return keys;
    if (keys.includes(k)) return keys;
    return [...keys, k];
}

/**
 * 关键词 chips 删除
 * @param {string[]} keys - 现有关键词列表
 * @param {string} key - 待删除关键词
 * @returns {string[]} 新列表
 */
export function removeKeyChip(keys, key) {
    return keys.filter((k) => k !== key);
}

/**
 * 条目校验（阻止提交 + 内联错误）
 * @param {object} entry - 表单当前值（{title, keys, content, constant, order,
 *   probability, group_name, group_weight, match_mode, position, depth, enabled}）
 * @returns {{ok: boolean, errors: object}} errors 键=字段名，值=内联错误文案
 */
export function validateLorebookEntry(entry) {
    const errors = {};
    const content = String(entry.content || '');
    const keys = Array.isArray(entry.keys) ? entry.keys : [];
    const constant = Boolean(entry.constant);

    if (content.length > CONTENT_MAX_LENGTH) {
        errors.content = `内容过长（上限 ${CONTENT_MAX_LENGTH} 字符）`;
    }
    if (keys.length === 0 && !constant) {
        errors.keys = '至少填写一个触发关键词（或勾选「常驻」）';
    }
    for (const field of ['order', 'probability', 'depth', 'group_weight']) {
        const value = Number(entry[field]);
        const { min, max } = BOUNDS[field];
        if (!Number.isFinite(value) || value < min || value > max) {
            errors[field] = `${field} 需在 ${min}-${max} 之间`;
        }
    }
    return { ok: Object.keys(errors).length === 0, errors };
}

/**
 * 保存 payload 构建（字段名映射单一来源：与后端 LorebookEntryBase 逐字段一致）
 * @param {object} form - 表单原始值（字符串/数组形态）
 * @returns {object} 可直接 POST/PUT 的 payload（数值/布尔已类型化）
 */
export function buildLorebookPayload(form) {
    return {
        title: String(form.title || ''),
        keys: Array.isArray(form.keys) ? form.keys : [],
        content: String(form.content || ''),
        constant: Boolean(form.constant),
        order: Number(form.order),
        probability: Number(form.probability),
        group_name: String(form.group_name || ''),
        group_weight: Number(form.group_weight),
        match_mode: String(form.match_mode || 'or'),
        position: String(form.position || 'world'),
        depth: Number(form.depth),
        enabled: form.enabled === undefined ? true : Boolean(form.enabled),
    };
}

// ════════════════════════════════════════════════════════════════
// 视图
// ════════════════════════════════════════════════════════════════

const LIST_FIELDS = ['title', 'keys', 'enabled', 'order', 'constant', 'id'];

/**
 * 打开世界书编辑器模态框（列表视图）
 * @param {object} opts
 * @param {number} opts.characterId - 归属角色 id
 * @param {string} [opts.characterName] - 角色名（模态框标题）
 * @param {function} [opts.onChanged] - 条目增删改后回调（如刷新）
 */
export function showLorebookEditor({ characterId, characterName = '角色', onChanged } = {}) {
    openModal({
        title: `${characterName} 的世界书`,
        modalClass: 'lorebook-modal',
        body: '<div class="lorebook-root" data-lorebook-root></div>',
        actions: '',
        removeExisting: '.modal-overlay',
        onOpen(overlay) {
            const root = overlay.querySelector('[data-lorebook-root]');
            renderList(root, characterId, onChanged);
        },
    });
}

/**
 * 渲染列表视图（搜索过滤 + 新增按钮 + 条目行）
 * @param {HTMLElement} root - 容器
 * @param {number} characterId - 角色 id
 * @param {function|null} onChanged - 变更回调
 */
async function renderList(root, characterId, onChanged) {
    root.innerHTML = `
        <div class="lorebook-toolbar">
            <input type="text" class="lorebook-search" data-lorebook-search placeholder="按标题/关键词过滤…">
            <button class="btn btn-primary lorebook-add" data-lorebook-add>${iconHtml('plus')} 新增条目</button>
        </div>
        <div class="lorebook-list" data-lorebook-list></div>
    `;
    const searchInput = root.querySelector('[data-lorebook-search]');
    const listEl = root.querySelector('[data-lorebook-list]');

    let entries = [];
    try {
        entries = await lorebook.list(characterId);
    } catch (err) {
        listEl.innerHTML = `<div class="lorebook-empty">加载世界书失败：${escapeHtml(err.message)}</div>`;
        return;
    }

    const render = () => {
        const q = (searchInput.value || '').trim().toLowerCase();
        const filtered = q
            ? entries.filter((e) =>
                (e.title || '').toLowerCase().includes(q) ||
                (e.keys || []).some((k) => k.toLowerCase().includes(q)))
            : entries;
        listEl.innerHTML = filtered.length
            ? filtered.map((e) => rowHtml(e)).join('')
            : '<div class="lorebook-empty">' + (entries.length ? '无匹配条目' : '还没有世界书条目，点「新增条目」开始') + '</div>';
        // 事件绑定（委托）
        listEl.querySelectorAll('[data-lorebook-edit]').forEach((btn) => {
            btn.addEventListener('click', () => renderEditor(root, characterId, entries.find((x) => x.id === Number(btn.dataset.lorebookEdit)), onChanged));
        });
        listEl.querySelectorAll('[data-lorebook-toggle]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const entry = entries.find((x) => x.id === Number(btn.dataset.lorebookToggle));
                try {
                    await lorebook.update(entry.id, { enabled: !entry.enabled });
                    entry.enabled = !entry.enabled;
                    render();
                    if (onChanged) onChanged();
                } catch (err) {
                    showAlert('切换失败: ' + err.message);
                }
            });
        });
        listEl.querySelectorAll('[data-lorebook-del]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const id = Number(btn.dataset.lorebookDel);
                try {
                    await lorebook.delete(id);
                    entries = entries.filter((e) => e.id !== id);
                    render();
                    if (onChanged) onChanged();
                } catch (err) {
                    showAlert('删除失败: ' + err.message);
                }
            });
        });
    };

    root.querySelector('[data-lorebook-add]').addEventListener('click', () =>
        renderEditor(root, characterId, null, onChanged));
    searchInput.addEventListener('input', render);
    render();
}

/** 列表行 HTML（标题/关键词前 3 + 计数/开关/order/常驻标记） */
function rowHtml(e) {
    const keys = e.keys || [];
    const keysPreview = keys.length
        ? escapeHtml(keys.slice(0, 3).join('、')) + (keys.length > 3 ? ` <span class="lorebook-keys-count">+${keys.length - 3}</span>` : '')
        : '<span class="lorebook-keys-empty">（常驻/无关键词）</span>';
    return `
        <div class="lorebook-row${e.constant ? ' is-constant' : ''}">
            <div class="lorebook-row-main">
                <div class="lorebook-row-title">${escapeHtml(e.title || '（未命名）')}${e.constant ? ` ${iconHtml('pin')}<span class="lorebook-badge">常驻</span>` : ''}</div>
                <div class="lorebook-row-keys">${keysPreview}</div>
            </div>
            <span class="lorebook-order">${e.order}</span>
            <button class="btn-icon lorebook-toggle" data-lorebook-toggle="${e.id}" title="${e.enabled ? '点击禁用' : '点击启用'}">${e.enabled ? iconHtml('toggleOn') : iconHtml('toggleOff')}</button>
            <button class="btn-icon" data-lorebook-edit="${e.id}" title="编辑">${iconHtml('edit')}</button>
            <button class="btn-icon" data-lorebook-del="${e.id}" title="删除">${iconHtml('trash')}</button>
        </div>`;
}

/** 渲染编辑视图（表单：chips/内容/匹配/位置/数值/开关） */
function renderEditor(root, characterId, entry, onChanged) {
    const e = entry || {};
    const keys = Array.isArray(e.keys) ? e.keys : [];
    const isEdit = Boolean(entry);
    const chipHtml = keys.map((k) =>
        `<span class="lorebook-chip">${escapeHtml(k)}<button type="button" class="lorebook-chip-x" data-chip-x="${escapeHtml(k)}">${iconHtml('x')}</button></span>`).join('');

    root.innerHTML = `
        <div class="lorebook-editor">
            <div class="form-field">
                <label for="le-title">标题</label>
                <input type="text" id="le-title" maxlength="200" value="${escapeHtml(e.title || '')}" placeholder="条目标题（可空）">
            </div>
            <div class="form-field">
                <label for="le-keys">触发关键词 <span class="field-error" id="le-keys-error"></span></label>
                <div class="lorebook-chips" id="le-chips">${chipHtml}</div>
                <div class="lorebook-chips-input">
                    <input type="text" id="le-keys-input" placeholder="回车或点添加录入关键词">
                    <button type="button" class="btn" id="le-keys-add">添加</button>
                </div>
                <span class="field-warning" id="le-generic-warning" hidden>关键词过泛，会显著增加注入量</span>
                <span class="field-hint">or=任一关键词命中即注入；and=全部命中才注入</span>
            </div>
            <div class="form-field">
                <label for="le-content">注入内容 <span class="field-error" id="le-content-error"></span></label>
                <textarea id="le-content" rows="5" placeholder="命中后注入的世界书内容">${escapeHtml(e.content || '')}</textarea>
                <span class="field-hint">支持模板变量：<code>{{user}}</code>、<code>{{char}}</code>；上限 ${CONTENT_MAX_LENGTH} 字符</span>
            </div>
            <div class="lorebook-grid">
                <div class="form-field">
                    <label for="le-match-mode">匹配模式</label>
                    <select id="le-match-mode">
                        <option value="or" ${(e.match_mode || 'or') === 'or' ? 'selected' : ''}>或（任一命中）</option>
                        <option value="and" ${e.match_mode === 'and' ? 'selected' : ''}>与（全部命中）</option>
                    </select>
                </div>
                <div class="form-field">
                    <label for="le-position">注入位置</label>
                    <select id="le-position">
                        <option value="world" ${(e.position || 'world') === 'world' ? 'selected' : ''}>世界知识（[世界知识]）</option>
                        <option value="before_char" ${e.position === 'before_char' ? 'selected' : ''}>角色设定前</option>
                        <option value="after_char" ${e.position === 'after_char' ? 'selected' : ''}>场景设定后</option>
                    </select>
                </div>
                <div class="form-field">
                    <label for="le-order">排序 order <span class="field-error" id="le-order-error"></span></label>
                    <input type="number" id="le-order" min="0" max="9999" value="${e.order ?? 100}">
                </div>
                <div class="form-field">
                    <label for="le-probability">命中概率 % <span class="field-error" id="le-probability-error"></span></label>
                    <input type="number" id="le-probability" min="1" max="100" value="${e.probability ?? 100}">
                </div>
                <div class="form-field">
                    <label for="le-group-name">互斥组名</label>
                    <input type="text" id="le-group-name" maxlength="100" value="${escapeHtml(e.group_name || '')}" placeholder="空=不分组">
                </div>
                <div class="form-field">
                    <label for="le-group-weight">组内权重 <span class="field-error" id="le-group-weight-error"></span></label>
                    <input type="number" id="le-group-weight" min="1" max="100" value="${e.group_weight ?? 100}">
                </div>
                <div class="form-field">
                    <label for="le-depth">记忆深度 <span class="field-error" id="le-depth-error"></span></label>
                    <input type="number" id="le-depth" min="0" max="20" value="${e.depth ?? 20}">
                    <span class="field-hint">0=只看当前输入；N=最近 N 轮</span>
                </div>
            </div>
            <div class="lorebook-switches">
                <label class="lorebook-switch"><input type="checkbox" id="le-constant" ${e.constant ? 'checked' : ''}> 常驻（不判命中，直接注入）</label>
                <label class="lorebook-switch"><input type="checkbox" id="le-enabled" ${e.enabled === undefined || e.enabled ? 'checked' : ''}> 启用</label>
            </div>
            <div class="lorebook-editor-actions">
                <button class="btn" id="le-cancel">返回列表</button>
                <button class="btn btn-primary" id="le-save">${isEdit ? '保存修改' : '新增条目'}</button>
            </div>
        </div>
    `;

    let currentKeys = [...keys];
    const chipsEl = root.querySelector('#le-chips');
    const keysInput = root.querySelector('#le-keys-input');
    const keysError = root.querySelector('#le-keys-error');
    const genericWarning = root.querySelector('#le-generic-warning');
    const contentInput = root.querySelector('#le-content');
    const contentError = root.querySelector('#le-content-error');

    const renderChips = () => {
        chipsEl.innerHTML = currentKeys.map((k) =>
            `<span class="lorebook-chip">${escapeHtml(k)}<button type="button" class="lorebook-chip-x" data-chip-x="${escapeHtml(k)}">${iconHtml('x')}</button></span>`).join('');
        chipsEl.querySelectorAll('[data-chip-x]').forEach((btn) => {
            btn.addEventListener('click', () => {
                currentKeys = removeKeyChip(currentKeys, btn.dataset.chipX);
                renderChips();
                updateWarnings();
            });
        });
        keysError.textContent = '';
        updateWarnings();
    };
    const updateWarnings = () => {
        const dirty = currentKeys.some((k) => isGenericKey(k));
        genericWarning.hidden = !dirty;
        if (!currentKeys.length && !root.querySelector('#le-constant').checked) {
            keysError.textContent = '至少填写一个触发关键词（或勾选「常驻」）';
        } else {
            keysError.textContent = '';
        }
    };
    const addFromInput = () => {
        currentKeys = addKeyChip(currentKeys, keysInput.value);
        keysInput.value = '';
        renderChips();
    };

    keysInput.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') { ev.preventDefault(); addFromInput(); }
    });
    root.querySelector('#le-keys-add').addEventListener('click', addFromInput);
    root.querySelector('#le-constant').addEventListener('change', updateWarnings);
    contentInput.addEventListener('input', () => {
        contentError.textContent = contentInput.value.length > CONTENT_MAX_LENGTH
            ? `内容过长（上限 ${CONTENT_MAX_LENGTH} 字符）` : '';
    });

    root.querySelector('#le-cancel').addEventListener('click', () => {
        renderList(root, characterId, onChanged);
    });
    root.querySelector('#le-save').addEventListener('click', async () => {
        const form = {
            title: root.querySelector('#le-title').value,
            keys: currentKeys,
            content: contentInput.value,
            constant: root.querySelector('#le-constant').checked,
            order: root.querySelector('#le-order').value,
            probability: root.querySelector('#le-probability').value,
            group_name: root.querySelector('#le-group-name').value,
            group_weight: root.querySelector('#le-group-weight').value,
            match_mode: root.querySelector('#le-match-mode').value,
            position: root.querySelector('#le-position').value,
            depth: root.querySelector('#le-depth').value,
            enabled: root.querySelector('#le-enabled').checked,
        };
        const { ok, errors } = validateLorebookEntry(form);
        if (!ok) {
            for (const [field, message] of Object.entries(errors)) {
                const el = root.querySelector(`#le-${field}-error`);
                if (el) el.textContent = message;
            }
            return;
        }
        const payload = buildLorebookPayload(form);
        try {
            if (isEdit) {
                await lorebook.update(entry.id, payload);
            } else {
                await lorebook.create(characterId, payload);
            }
            if (onChanged) onChanged();
            renderList(root, characterId, onChanged);
        } catch (err) {
            showAlert((isEdit ? '保存失败' : '新增失败') + ': ' + err.message);
        }
    });

    renderChips();
}
