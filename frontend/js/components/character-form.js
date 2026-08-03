/**
 * Conver System — 角色创建/编辑表单组件
 *
 * 专用模态框表单，替换原有的 prompt() 弹窗。
 * 支持创建和编辑两种模式。
 */

import { characters } from '../api.js';
import { escapeHtml } from '../utils.js';

/**
 * 打开角色表单模态框
 * @param {'create'|'edit'} mode - 表单模式
 * @param {object|null} characterData - 编辑模式时传入角色数据
 * @param {function} onSuccess - 保存成功后的回调
 */
export function showCharacterForm(mode = 'create', characterData = null, onSuccess = null) {
    // 移除已存在的模态框
    const existing = document.querySelector('.modal-overlay');
    if (existing) existing.remove();

    const isEdit = mode === 'edit';
    const char = characterData || {};

    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';

    overlay.innerHTML = `
        <div class="modal character-form-modal">
            <div class="modal-header">
                <h3>${isEdit ? '编辑角色' : '创建新角色'}</h3>
                <button class="btn-icon modal-close" title="关闭">✕</button>
            </div>
            <div class="modal-body">
                <div class="form-field">
                    <label for="cf-name">角色名称 <span class="required">*</span></label>
                    <input type="text" id="cf-name" maxlength="100" placeholder="输入角色名称" value="${escapeHtml(char.name || '')}">
                    <span class="field-error" id="cf-name-error"></span>
                </div>

                <div class="form-field">
                    <label for="cf-description">简短描述</label>
                    <input type="text" id="cf-description" maxlength="200" placeholder="角色的简短描述" value="${escapeHtml(char.description || '')}">
                </div>

                <div class="form-field">
                    <label for="cf-personality">人格设定 (Personality)</label>
                    <textarea id="cf-personality" rows="6" placeholder="角色的人格设定、性格特征、说话方式等核心 System Prompt">${escapeHtml(char.personality || '')}</textarea>
                    <span class="field-hint">支持模板变量：<code>{{user}}</code>（用户昵称）、<code>{{char}}</code>（角色名称）</span>
                </div>

                <div class="form-field">
                    <label for="cf-first-mes">开场白 (Greeting)</label>
                    <textarea id="cf-first-mes" rows="3" placeholder="首次对话时角色自动发送的开场消息">${escapeHtml(char.first_mes || '')}</textarea>
                    <span class="field-hint">支持模板变量：<code>{{user}}</code>、<code>{{char}}</code></span>
                </div>

                <div class="form-field">
                    <label for="cf-scenario">场景设定</label>
                    <textarea id="cf-scenario" rows="3" placeholder="对话发生的场景描述">${escapeHtml(char.scenario || '')}</textarea>
                    <span class="field-hint">支持模板变量：<code>{{user}}</code>、<code>{{char}}</code></span>
                </div>

                <div class="form-field">
                    <label for="cf-mes-example">对话范例 (few-shot)</label>
                    <textarea id="cf-mes-example" rows="4" placeholder="<character>示例对话</character>（可选，帮助模型理解角色的说话风格）">${escapeHtml(char.mes_example || '')}</textarea>
                </div>

                <div class="form-field">
                    <label for="cf-temperature">温度 (Temperature): <span id="cf-temp-value">${char.temperature ?? 0.7}</span></label>
                    <input type="range" id="cf-temperature" min="0" max="2" step="0.05" value="${char.temperature ?? 0.7}">
                    <div class="range-labels">
                        <span>精确 (0)</span>
                        <span>平衡 (1.0)</span>
                        <span>创意 (2.0)</span>
                    </div>
                </div>

                <div class="form-field">
                    <label for="cf-avatar">头像 URL / Base64</label>
                    <input type="text" id="cf-avatar" placeholder="粘贴头像链接或 base64 数据" value="${escapeHtml(char.avatar || '')}">
                    <div class="avatar-preview" id="cf-avatar-preview">
                        ${char.avatar ? `<img src="${escapeHtml(char.avatar)}" alt="头像预览">` : '<span class="avatar-placeholder">无头像</span>'}
                    </div>
                </div>

                <div class="form-row">
                    <div class="form-field">
                        <label for="cf-tags">标签 (逗号分隔)</label>
                        <input type="text" id="cf-tags" placeholder="例如: 冒险, 奇幻, 可爱" value="${escapeHtml(tagsToComma(char.tags) || '')}">
                    </div>
                </div>

                <div class="form-field">
                    <label for="cf-creator">创作者</label>
                    <input type="text" id="cf-creator" placeholder="角色作者/来源" value="${escapeHtml(char.creator || '')}">
                </div>

                <div class="form-field">
                    <label for="cf-system-prompt">自定义 System Prompt（覆盖人格设定）</label>
                    <textarea id="cf-system-prompt" rows="3" placeholder="留空则使用人格设定作为 System Prompt">${escapeHtml(char.system_prompt || '')}</textarea>
                </div>
            </div>
            <div class="modal-footer">
                <span class="form-status" id="cf-status"></span>
                <button class="btn-secondary modal-cancel">取消</button>
                <button class="btn-primary" id="cf-submit">${isEdit ? '保存修改' : '创建角色'}</button>
            </div>
        </div>
    `;

    document.body.appendChild(overlay);

    // ── DOM 引用 ──
    const nameInput = overlay.querySelector('#cf-name');
    const tempSlider = overlay.querySelector('#cf-temperature');
    const tempValue = overlay.querySelector('#cf-temp-value');
    const statusEl = overlay.querySelector('#cf-status');
    const avatarInput = overlay.querySelector('#cf-avatar');
    const avatarPreview = overlay.querySelector('#cf-avatar-preview');

    // ── 事件绑定 ──

    // 关闭
    const close = () => overlay.remove();
    overlay.querySelector('.modal-close').addEventListener('click', close);
    overlay.querySelector('.modal-cancel').addEventListener('click', close);
    overlay.addEventListener('click', (e) => {
        if (e.target === overlay) close();
    });

    // 温度滑块实时显示
    tempSlider.addEventListener('input', () => {
        tempValue.textContent = parseFloat(tempSlider.value).toFixed(2);
    });

    // 头像预览
    avatarInput.addEventListener('input', () => {
        const val = avatarInput.value.trim();
        if (val) {
            avatarPreview.innerHTML = `<img src="${escapeHtml(val)}" alt="头像预览" onerror="this.parentElement.innerHTML='<span class=\\'avatar-placeholder\\'>图片加载失败</span>'">`;
        } else {
            avatarPreview.innerHTML = '<span class="avatar-placeholder">无头像</span>';
        }
    });

    // 键盘事件：Escape 关闭
    overlay.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') close();
    });

    // ── 提交 ──
    overlay.querySelector('#cf-submit').addEventListener('click', async () => {
        // 校验
        const name = nameInput.value.trim();
        if (!name) {
            const errorEl = overlay.querySelector('#cf-name-error');
            errorEl.textContent = '角色名称不能为空';
            nameInput.focus();
            return;
        }

        // 收集数据
        const data = {
            name,
            description: overlay.querySelector('#cf-description').value.trim(),
            personality: overlay.querySelector('#cf-personality').value.trim(),
            first_mes: overlay.querySelector('#cf-first-mes').value.trim(),
            scenario: overlay.querySelector('#cf-scenario').value.trim(),
            mes_example: overlay.querySelector('#cf-mes-example').value.trim(),
            system_prompt: overlay.querySelector('#cf-system-prompt').value.trim(),
            temperature: parseFloat(tempSlider.value),
            avatar: avatarInput.value.trim() || null,
            creator: overlay.querySelector('#cf-creator').value.trim(),
            tags: tagsToArray(overlay.querySelector('#cf-tags').value.trim()),
        };

        // 提交按钮状态
        const submitBtn = overlay.querySelector('#cf-submit');
        submitBtn.disabled = true;
        submitBtn.textContent = '保存中…';
        statusEl.textContent = '';
        statusEl.className = 'form-status';

        try {
            if (isEdit) {
                await characters.update(char.id, data);
                statusEl.textContent = '✅ 更新成功';
            } else {
                await characters.create(data);
                statusEl.textContent = '✅ 创建成功';
            }
            statusEl.className = 'form-status success';

            setTimeout(() => {
                close();
                if (onSuccess) onSuccess();
            }, 600);
        } catch (err) {
            statusEl.textContent = `❌ ${err.message}`;
            statusEl.className = 'form-status error';
            submitBtn.disabled = false;
            submitBtn.textContent = isEdit ? '保存修改' : '创建角色';
        }
    });

    // 聚焦名称输入框
    setTimeout(() => nameInput.focus(), 50);

    return overlay;
}

/**
 * 将标签数组转为逗号分隔字符串
 */
function tagsToComma(tags) {
    if (!Array.isArray(tags) || tags.length === 0) return '';
    return tags.join(', ');
}

/**
 * 将逗号分隔的标签文本转为标签数组
 */
function tagsToArray(tags) {
    if (!tags) return [];
    return tags.split(/[,，]/).map(t => t.trim()).filter(Boolean);
}
