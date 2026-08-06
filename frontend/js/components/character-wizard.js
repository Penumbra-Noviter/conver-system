/**
 * Conver System — 角色创建引导向导
 *
 * 6 步逐步引导新用户创建角色：
 *   Step 1: 选择创建方式（文档导入 / 模板 / 手动）
 *   Step 2: 文档导入或模板选择
 *   Step 3: 基本信息（name / avatar / description / tags）
 *   Step 4: 人格设定（personality / scenario / system_prompt）
 *   Step 5: 对话风格（first_mes / mes_example）
 *   Step 6: 预览保存
 *
 * 编辑已有角色仍使用现有的 character-form.js（简单表单）。
 */

import { characters } from '../api.js';
import { escapeHtml } from '../utils.js';
import { CHARACTER_TEMPLATES } from '../data/character-templates.js';

/**
 * 打开角色创建向导
 * @param {function} onSuccess - 创建成功后的回调
 */
export function showCharacterWizard(onSuccess = null) {
    const existing = document.querySelector('.modal-overlay');
    if (existing) existing.remove();

    // ── 向导状态 ──
    const state = {
        step: 1,
        // 创建方式: 'import' | 'template' | 'manual'
        mode: null,
        // 选中的模板 ID
        selectedTemplate: null,
        // 表单字段
        name: '',
        description: '',
        personality: '',
        scenario: '',
        first_mes: '',
        mes_example: '',
        system_prompt: '',
        tags: [],
        avatar: '',
        temperature: 0.7,
        // 文档解析结果
        parsing: false,
        parseError: '',
        parsedFields: [],
    };

    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';

    overlay.innerHTML = `
        <div class="modal wizard-modal">
            <div class="modal-header">
                <h3>创建新角色</h3>
                <button class="btn-icon modal-close" title="关闭">✕</button>
            </div>
            <div class="wizard-progress">
                <div class="wizard-progress-bar" id="wizard-progress-bar" style="width: 16.6%"></div>
            </div>
            <div class="wizard-step-indicators" id="wizard-step-indicators">
                <span class="wizard-step-dot active" data-step="1">1</span>
                <span class="wizard-step-line"></span>
                <span class="wizard-step-dot" data-step="2">2</span>
                <span class="wizard-step-line"></span>
                <span class="wizard-step-dot" data-step="3">3</span>
                <span class="wizard-step-line"></span>
                <span class="wizard-step-dot" data-step="4">4</span>
                <span class="wizard-step-line"></span>
                <span class="wizard-step-dot" data-step="5">5</span>
                <span class="wizard-step-line"></span>
                <span class="wizard-step-dot" data-step="6">6</span>
            </div>
            <div class="modal-body wizard-body" id="wizard-body">
                ${renderStep1(state)}
            </div>
            <div class="modal-footer wizard-footer">
                <span class="form-status" id="wizard-status"></span>
                <button class="btn-secondary modal-cancel">取消</button>
                <button class="btn-secondary" id="wizard-prev" style="visibility:hidden">上一步</button>
                <button class="btn-primary" id="wizard-next">下一步</button>
            </div>
        </div>
    `;

    document.body.appendChild(overlay);

    // ── DOM 引用 ──
    const body = overlay.querySelector('#wizard-body');
    const prevBtn = overlay.querySelector('#wizard-prev');
    const nextBtn = overlay.querySelector('#wizard-next');
    const statusEl = overlay.querySelector('#wizard-status');
    const progressBar = overlay.querySelector('#wizard-progress-bar');
    const stepDots = overlay.querySelectorAll('.wizard-step-dot');

    // ── 关闭 ──
    const close = () => overlay.remove();
    overlay.querySelector('.modal-close').addEventListener('click', close);
    overlay.querySelector('.modal-cancel')?.addEventListener('click', close);
    overlay.addEventListener('click', (e) => {
        if (e.target === overlay) close();
    });

    // ── 更新进度条 ──
    function updateProgress() {
        const pct = ((state.step - 1) / 5) * 100;
        progressBar.style.width = `${pct}%`;
        stepDots.forEach((dot) => {
            const s = parseInt(dot.dataset.step);
            dot.classList.toggle('active', s <= state.step);
        });
    }

    // ── 渲染当前步骤 ──
    function render() {
        body.innerHTML = renderStep(state.step, state);
        updateProgress();

        // 绑定步骤内事件
        bindStepEvents(state.step, state, body, nextBtn, prevBtn, statusEl, close, render);

        // 更新按钮状态
        prevBtn.style.visibility = state.step > 1 ? 'visible' : 'hidden';
        if (state.step === 6) {
            nextBtn.textContent = '保存角色';
        } else {
            nextBtn.textContent = '下一步';
        }
    }

    // ── 导航 ──
    prevBtn.addEventListener('click', () => {
        if (state.step > 1) {
            state.step--;
            render();
        }
    });

    nextBtn.addEventListener('click', () => {
        if (state.step === 6) {
            handleSave(state, statusEl, nextBtn, close, onSuccess);
        } else {
            // 验证当前步骤
            if (!validateStep(state.step, state, statusEl)) return;
            state.step++;
            render();
        }
    });

    // 键盘事件
    overlay.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') close();
    });

    render();
}

// ══════════════════════════════════════════════════
// 步骤渲染
// ══════════════════════════════════════════════════

const STEP_TITLES = {
    1: '选择创建方式',
    2: '导入文档 / 选择模板',
    3: '基本信息',
    4: '人格设定',
    5: '对话风格',
    6: '预览保存',
};

function renderStep(step, state) {
    switch (step) {
        case 1: return renderStep1(state);
        case 2: return renderStep2(state);
        case 3: return renderStep3(state);
        case 4: return renderStep4(state);
        case 5: return renderStep5(state);
        case 6: return renderStep6(state);
        default: return '<p>未知步骤</p>';
    }
}

// ── Step 1: 选择创建方式 ──

function renderStep1(state) {
    return `
        <div class="wizard-step">
            <p class="wizard-step-desc">选择一种方式开始创建你的角色：</p>
            <div class="wizard-mode-grid">
                <div class="wizard-mode-card ${state.mode === 'import' ? 'selected' : ''}" data-mode="import">
                    <div class="wizard-mode-icon">📄</div>
                    <div class="wizard-mode-name">智能导入</div>
                    <div class="wizard-mode-desc">粘贴角色设定文档，AI 自动提取角色信息</div>
                </div>
                <div class="wizard-mode-card ${state.mode === 'template' ? 'selected' : ''}" data-mode="template">
                    <div class="wizard-mode-icon">🎭</div>
                    <div class="wizard-mode-name">从模板开始</div>
                    <div class="wizard-mode-desc">从预设角色模板中选择，快速入门</div>
                </div>
                <div class="wizard-mode-card ${state.mode === 'manual' ? 'selected' : ''}" data-mode="manual">
                    <div class="wizard-mode-icon">✏️</div>
                    <div class="wizard-mode-name">手动创建</div>
                    <div class="wizard-mode-desc">从零开始，逐项填写角色信息</div>
                </div>
            </div>
        </div>
    `;
}

// ── Step 2: 文档导入 / 模板选择 ──

function renderStep2(state) {
    if (state.mode === 'import') {
        return `
            <div class="wizard-step">
                <p class="wizard-step-desc">粘贴角色设定文档或简介，AI 将自动提取角色信息：</p>
                <div class="wizard-import-area">
                    <textarea id="wizard-import-text" rows="12" placeholder="在此粘贴角色设定文档、小说片段、角色简介等&#10;&#10;例如：&#10;「小红是一只住在森林里的小狐狸，她活泼开朗，喜欢帮助迷路的小动物们……」
                    ">${escapeHtml(state.importText || '')}</textarea>
                </div>
                <div class="wizard-parse-status" id="wizard-parse-status">
                    ${state.parsing ? '<span class="wizard-parsing">⏳ AI 正在解析文档…</span>' : ''}
                    ${state.parseError ? `<span class="wizard-parse-error">❌ ${escapeHtml(state.parseError)}</span>` : ''}
                    ${state.parsedFields.length > 0 ? `<span class="wizard-parse-success">✅ 已提取 ${state.parsedFields.length} 个字段</span>` : ''}
                </div>
                <button class="btn-secondary" id="wizard-parse-btn" ${state.parsing ? 'disabled' : ''}>
                    ${state.parsing ? '解析中…' : '🤖 AI 智能解析'}
                </button>
                <p class="field-hint" style="margin-top: 8px">需要先配置 API Key（设置 → 填写 Claude/OpenAI Key）</p>
            </div>
        `;
    }

    if (state.mode === 'template') {
        const cards = CHARACTER_TEMPLATES.map((t) => `
            <div class="template-card ${state.selectedTemplate === t.id ? 'selected' : ''}" data-template-id="${escapeHtml(t.id)}">
                <div class="template-card-icon">${getTemplateIcon(t.id)}</div>
                <div class="template-card-name">${escapeHtml(t.name)}</div>
                <div class="template-card-desc">${escapeHtml(t.description)}</div>
                <div class="template-card-tags">${t.tags.map(tag => `<span class="template-tag">${escapeHtml(tag)}</span>`).join('')}</div>
            </div>
        `).join('');

        return `
            <div class="wizard-step">
                <p class="wizard-step-desc">选择一个模板作为起点，之后可以自由修改：</p>
                <div class="template-grid">
                    ${cards}
                </div>
            </div>
        `;
    }

    // manual mode — skip to step 3, handled by navigation
    return '<p>手动创建，请点击"下一步"开始填写</p>';
}

// ── Step 3: 基本信息 ──

function renderStep3(state) {
    return `
        <div class="wizard-step">
            <p class="wizard-step-desc">填写角色的基本信息：</p>
            <div class="form-field">
                <label for="wiz-name">角色名称 <span class="required">*</span></label>
                <input type="text" id="wiz-name" maxlength="100" placeholder="输入角色名称" value="${escapeHtml(state.name)}">
                <span class="field-error" id="wiz-name-error"></span>
            </div>
            <div class="form-field">
                <label for="wiz-desc">简短描述</label>
                <input type="text" id="wiz-desc" maxlength="200" placeholder="角色的一句话简介" value="${escapeHtml(state.description)}">
                <span class="field-hint">告诉用户这个角色是谁，例如"森林里的小狐狸"</span>
            </div>
            <div class="form-field">
                <label for="wiz-avatar">头像 URL</label>
                <input type="text" id="wiz-avatar" placeholder="粘贴头像链接" value="${escapeHtml(state.avatar)}">
                <div class="avatar-preview" id="wiz-avatar-preview">
                    ${state.avatar ? `<img src="${escapeHtml(state.avatar)}" alt="头像预览">` : '<span class="avatar-placeholder">无头像</span>'}
                </div>
            </div>
            <div class="form-field">
                <label for="wiz-tags">标签（逗号分隔）</label>
                <input type="text" id="wiz-tags" placeholder="如: 冒险, 奇幻, 可爱" value="${escapeHtml((state.tags || []).join(', '))}">
                <span class="field-hint">帮助其他用户发现你的角色</span>
            </div>
        </div>
    `;
}

// ── Step 4: 人格设定 ──

function renderStep4(state) {
    return `
        <div class="wizard-step">
            <p class="wizard-step-desc">设定角色的核心人格——这决定了 AI 如何扮演这个角色：</p>
            <div class="form-field">
                <label for="wiz-personality">人格设定 <span class="required">*</span></label>
                <textarea id="wiz-personality" rows="8" placeholder="描述角色的性格特征、说话方式、行为模式、背景故事等">${escapeHtml(state.personality)}</textarea>
                <span class="field-hint">💡 <strong>这是最重要的字段</strong>。越详细，AI 对角色的扮演越精准。包括：性格特征、说话风格、行为习惯、背景故事、知识和能力等。</span>
            </div>
            <div class="form-field">
                <label for="wiz-scenario">场景设定</label>
                <textarea id="wiz-scenario" rows="3" placeholder="对话发生的场景和环境描述">${escapeHtml(state.scenario)}</textarea>
                <span class="field-hint">💡 描述对话发生的场景，如"午后的图书馆"或"星际飞船的舰桥"。支持模板变量：<code>{{user}}</code>、<code>{{char}}</code></span>
            </div>
            <div class="form-field">
                <label for="wiz-system-prompt">自定义 System Prompt（可选）</label>
                <textarea id="wiz-system-prompt" rows="3" placeholder="留空则使用人格设定作为 System Prompt">${escapeHtml(state.system_prompt)}</textarea>
                <span class="field-hint">💡 如果填写，将<strong>覆盖</strong>人格设定作为系统提示词。通常留空即可。</span>
            </div>
        </div>
    `;
}

// ── Step 5: 对话风格 ──

function renderStep5(state) {
    return `
        <div class="wizard-step">
            <p class="wizard-step-desc">设定角色的对话风格——这决定了角色如何与用户交流：</p>
            <div class="form-field">
                <label for="wiz-first-mes">开场白 <span class="required">*</span></label>
                <textarea id="wiz-first-mes" rows="3" placeholder="角色首次对话时自动发送的第一句话">${escapeHtml(state.first_mes)}</textarea>
                <span class="field-hint">💡 开场白是用户对角色<strong>第一印象</strong>。好的开场白能立即展现角色性格。支持模板变量：<code>{{user}}</code>、<code>{{char}}</code></span>
            </div>
            <div class="form-field">
                <label for="wiz-mes-example">对话范例（可选）</label>
                <textarea id="wiz-mes-example" rows="4" placeholder="<START>&#10;{{user}}: 你好&#10;{{char}}: 欢迎，我等你很久了">${escapeHtml(state.mes_example)}</textarea>
                <span class="field-hint">💡 展示角色说话风格的示例对话，帮助 AI 理解角色的语气和表达方式。用 <code>&lt;START&gt;</code> 标记开始，用 <code>{{user}}</code> 和 <code>{{char}}</code> 表示对话双方。</span>
            </div>
        </div>
    `;
}

// ── Step 6: 预览保存 ──

function renderStep6(state) {
    const tags = state.tags || [];
    return `
        <div class="wizard-step">
            <p class="wizard-step-desc">检查角色信息，确认无误后保存：</p>
            <div class="wizard-summary">
                <div class="wizard-summary-section">
                    <h4>📋 基本信息</h4>
                    <div class="wizard-summary-row"><span class="summary-label">名称</span><span class="summary-value">${escapeHtml(state.name) || '<span class="summary-empty">未填写</span>'}</span></div>
                    <div class="wizard-summary-row"><span class="summary-label">描述</span><span class="summary-value">${escapeHtml(state.description) || '<span class="summary-empty">未填写</span>'}</span></div>
                    <div class="wizard-summary-row"><span class="summary-label">标签</span><span class="summary-value">${tags.length ? tags.map(t => `<span class="summary-tag">${escapeHtml(t)}</span>`).join(' ') : '<span class="summary-empty">无</span>'}</span></div>
                </div>
                <div class="wizard-summary-section">
                    <h4>🧠 人格设定</h4>
                    <div class="wizard-summary-row"><span class="summary-label">人格</span><span class="summary-value summary-text">${escapeHtml(state.personality) || '<span class="summary-empty">未填写</span>'}</span></div>
                    <div class="wizard-summary-row"><span class="summary-label">场景</span><span class="summary-value">${escapeHtml(state.scenario) || '<span class="summary-empty">未填写</span>'}</span></div>
                </div>
                <div class="wizard-summary-section">
                    <h4>💬 对话风格</h4>
                    <div class="wizard-summary-row"><span class="summary-label">开场白</span><span class="summary-value">${escapeHtml(state.first_mes) || '<span class="summary-empty">未填写</span>'}</span></div>
                    <div class="wizard-summary-row"><span class="summary-label">对话范例</span><span class="summary-value summary-text">${escapeHtml(state.mes_example) || '<span class="summary-empty">未填写</span>'}</span></div>
                </div>
                <div class="wizard-summary-section">
                    <h4>⚙️ 设置</h4>
                    <div class="form-field">
                        <label for="wiz-temp">温度 (Temperature): <span id="wiz-temp-value">${state.temperature.toFixed(2)}</span></label>
                        <input type="range" id="wiz-temp" min="0" max="2" step="0.05" value="${state.temperature}">
                        <div class="range-labels">
                            <span>精确 (0)</span>
                            <span>平衡 (1.0)</span>
                            <span>创意 (2.0)</span>
                        </div>
                        <span class="field-hint">💡 较低的值使回复更可控，较高的值使回复更有创意</span>
                    </div>
                </div>
            </div>
        </div>
    `;
}

// ══════════════════════════════════════════════════
// 事件绑定
// ══════════════════════════════════════════════════

function bindStepEvents(step, state, body, nextBtn, prevBtn, statusEl, close, render) {
    switch (step) {
        case 1:
            bindStep1Events(state, body, render);
            break;
        case 2:
            bindStep2Events(state, body, statusEl, render);
            break;
        case 3:
            bindStep3Events(state, body);
            break;
        case 4:
            bindStep4Events(state, body);
            break;
        case 5:
            bindStep5Events(state, body);
            break;
        case 6:
            bindStep6Events(state, body);
            break;
    }
}

function bindStep1Events(state, body, render) {
    body.querySelectorAll('.wizard-mode-card').forEach((card) => {
        card.addEventListener('click', () => {
            state.mode = card.dataset.mode;
            // 如果是手动创建，直接跳到 step 3（跳过 step 2）
            if (state.mode === 'manual') {
                state.step = 3;
                render();
            } else {
                // 重新渲染以更新选中状态
                render();
            }
        });
    });
}

function bindStep2Events(state, body, statusEl, render) {
    if (state.mode === 'import') {
        const textarea = body.querySelector('#wizard-import-text');
        const parseBtn = body.querySelector('#wizard-parse-btn');

        if (textarea) {
            textarea.addEventListener('input', () => {
                state.importText = textarea.value;
            });
        }

        if (parseBtn) {
            parseBtn.addEventListener('click', async () => {
                const text = textarea?.value?.trim();
                if (!text) {
                    state.parseError = '请先粘贴文档内容';
                    render();
                    return;
                }

                state.parsing = true;
                state.parseError = '';
                render();

                try {
                    const result = await characters.parseDocument({ text });
                    // 填充字段
                    state.name = result.name || '';
                    state.description = result.description || '';
                    state.personality = result.personality || '';
                    state.scenario = result.scenario || '';
                    state.first_mes = result.first_mes || '';
                    state.mes_example = result.mes_example || '';
                    state.system_prompt = result.system_prompt || '';
                    state.tags = Array.isArray(result.tags) ? result.tags : [];
                    state.parsedFields = Array.isArray(result.parsed_fields) ? result.parsed_fields : [];
                    state.parseError = '';
                } catch (err) {
                    state.parseError = err.message || '解析失败，请重试';
                } finally {
                    state.parsing = false;
                    render();
                }
            });
        }
    }

    if (state.mode === 'template') {
        body.querySelectorAll('.template-card').forEach((card) => {
            card.addEventListener('click', () => {
                const tid = card.dataset.templateId;
                const template = CHARACTER_TEMPLATES.find(t => t.id === tid);
                if (template) {
                    state.selectedTemplate = tid;
                    state.name = template.name || '';
                    state.description = template.description || '';
                    state.personality = template.personality || '';
                    state.scenario = template.scenario || '';
                    state.first_mes = template.first_mes || '';
                    state.mes_example = template.mes_example || '';
                    state.system_prompt = template.system_prompt || '';
                    state.tags = [...(template.tags || [])];
                }
                render();
            });
        });
    }
}

function bindStep3Events(state, body) {
    const nameInput = body.querySelector('#wiz-name');
    const descInput = body.querySelector('#wiz-desc');
    const avatarInput = body.querySelector('#wiz-avatar');
    const tagsInput = body.querySelector('#wiz-tags');
    const avatarPreview = body.querySelector('#wiz-avatar-preview');

    if (nameInput) nameInput.addEventListener('input', () => { state.name = nameInput.value.trim(); });
    if (descInput) descInput.addEventListener('input', () => { state.description = descInput.value.trim(); });
    if (tagsInput) tagsInput.addEventListener('input', () => {
        state.tags = tagsInput.value ? tagsInput.value.split(/[,，]/).map(t => t.trim()).filter(Boolean) : [];
    });
    if (avatarInput) {
        avatarInput.addEventListener('input', () => {
            state.avatar = avatarInput.value.trim();
            if (avatarPreview) {
                if (state.avatar) {
                    avatarPreview.innerHTML = `<img src="${escapeHtml(state.avatar)}" alt="头像预览" onerror="this.parentElement.innerHTML='<span class=\\'avatar-placeholder\\'>图片加载失败</span>'">`;
                } else {
                    avatarPreview.innerHTML = '<span class="avatar-placeholder">无头像</span>';
                }
            }
        });
    }
}

function bindStep4Events(state, body) {
    const personalityInput = body.querySelector('#wiz-personality');
    const scenarioInput = body.querySelector('#wiz-scenario');
    const systemPromptInput = body.querySelector('#wiz-system-prompt');

    if (personalityInput) personalityInput.addEventListener('input', () => { state.personality = personalityInput.value; });
    if (scenarioInput) scenarioInput.addEventListener('input', () => { state.scenario = scenarioInput.value; });
    if (systemPromptInput) systemPromptInput.addEventListener('input', () => { state.system_prompt = systemPromptInput.value; });
}

function bindStep5Events(state, body) {
    const firstMesInput = body.querySelector('#wiz-first-mes');
    const mesExampleInput = body.querySelector('#wiz-mes-example');

    if (firstMesInput) firstMesInput.addEventListener('input', () => { state.first_mes = firstMesInput.value; });
    if (mesExampleInput) mesExampleInput.addEventListener('input', () => { state.mes_example = mesExampleInput.value; });
}

function bindStep6Events(state, body) {
    const tempSlider = body.querySelector('#wiz-temp');
    const tempValue = body.querySelector('#wiz-temp-value');

    if (tempSlider && tempValue) {
        tempSlider.addEventListener('input', () => {
            state.temperature = parseFloat(tempSlider.value);
            tempValue.textContent = state.temperature.toFixed(2);
        });
    }
}

// ══════════════════════════════════════════════════
// 验证
// ══════════════════════════════════════════════════

function validateStep(step, state, statusEl) {
    statusEl.textContent = '';
    statusEl.className = 'form-status';

    switch (step) {
        case 1:
            if (!state.mode) {
                statusEl.textContent = '请选择一种创建方式';
                statusEl.className = 'form-status error';
                return false;
            }
            return true;

        case 2:
            if (state.mode === 'import') {
                // 可能已解析或未解析，都是 OK 的
                return true;
            }
            if (state.mode === 'template') {
                if (!state.selectedTemplate) {
                    statusEl.textContent = '请选择一个模板';
                    statusEl.className = 'form-status error';
                    return false;
                }
            }
            return true;

        case 3:
            if (!state.name) {
                statusEl.textContent = '角色名称不能为空';
                statusEl.className = 'form-status error';
                const nameInput = document.querySelector('#wiz-name');
                if (nameInput) nameInput.focus();
                return false;
            }
            return true;

        case 4:
            // personality 非必填（但建议），不拦截
            return true;

        case 5:
            // first_mes 非必填（但建议），不拦截
            return true;

        default:
            return true;
    }
}

// ══════════════════════════════════════════════════
// 保存
// ══════════════════════════════════════════════════

async function handleSave(state, statusEl, submitBtn, close, onSuccess) {
    // 最终校验
    if (!state.name) {
        statusEl.textContent = '角色名称不能为空';
        statusEl.className = 'form-status error';
        return;
    }

    const data = {
        name: state.name,
        description: state.description || '',
        personality: state.personality || '',
        scenario: state.scenario || '',
        first_mes: state.first_mes || '',
        mes_example: state.mes_example || '',
        system_prompt: state.system_prompt || '',
        tags: state.tags || [],
        temperature: state.temperature,
        avatar: state.avatar || null,
        creator: '',
    };

    submitBtn.disabled = true;
    submitBtn.textContent = '保存中…';
    statusEl.textContent = '';
    statusEl.className = 'form-status';

    try {
        await characters.create(data);
        statusEl.textContent = '✅ 创建成功';
        statusEl.className = 'form-status success';

        setTimeout(() => {
            close();
            if (onSuccess) onSuccess();
        }, 600);
    } catch (err) {
        statusEl.textContent = `❌ ${err.message}`;
        statusEl.className = 'form-status error';
        submitBtn.disabled = false;
        submitBtn.textContent = '保存角色';
    }
}

// ══════════════════════════════════════════════════
// 辅助
// ══════════════════════════════════════════════════

function getTemplateIcon(templateId) {
    const icons = {
        senpai: '📚',
        wanderer: '🌍',
        tsundere: '🤖',
        butler: '🍵',
        nekomimi: '🐱',
    };
    return icons[templateId] || '🎭';
}