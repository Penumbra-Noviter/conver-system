/**
 * Conver System — 角色创建/编辑表单组件
 *
 * 专用模态框表单，替换原有的 prompt() 弹窗。
 * 支持创建和编辑两种模式。
 *
 * 骨架（遮罩/标题/关闭按钮/遮罩点击/Escape）由通用模态框工厂 openModal 承担
 * （ARC-10 C3 收口）；本组件只提供 body/actions HTML 与 onOpen 内的字段
 * 渲染/校验/完整性引导/提交逻辑。
 */

import { characters } from '../api.js';
import { escapeHtml } from '../utils.js';
import { showConfirm } from './confirm-dialog.js';
import { iconHtml } from '../icons.js';
import { openModal } from './modal.js';
import { splitTags, buildCharacterPayload, beginSubmit, succeedSubmit, failSubmit } from './character-submit.js';
import { avatarImgHtml } from '../format.js';

/**
 * 打开角色表单模态框
 * @param {'create'|'edit'} mode - 表单模式
 * @param {object|null} characterData - 编辑模式时传入角色数据
 * @param {function} onSuccess - 保存成功后的回调
 */
export function showCharacterForm(mode = 'create', characterData = null, onSuccess = null) {
    const isEdit = mode === 'edit';
    const char = characterData || {};

    const body = `
        <div class="form-field">
            <label for="cf-name">角色名称 <span class="required">*</span><span class="field-warning" id="cf-warn-name" hidden>建议填写</span></label>
            <input type="text" id="cf-name" maxlength="100" placeholder="输入角色名称" value="${escapeHtml(char.name || '')}">
            <span class="field-error" id="cf-name-error"></span>
            <span class="field-hint" id="cf-completeness-hint" hidden>完整角色建议包含：人格设定 + 开场白</span>
        </div>

        <div class="form-field">
            <label for="cf-description">简短描述</label>
            <input type="text" id="cf-description" maxlength="200" placeholder="角色的简短描述" value="${escapeHtml(char.description || '')}">
        </div>

        <div class="form-field">
            <label for="cf-personality">人格设定 (Personality)<span class="field-warning" id="cf-warn-personality" hidden>建议填写</span></label>
            <textarea id="cf-personality" rows="6" placeholder="角色的人格设定、性格特征、说话方式等核心 System Prompt">${escapeHtml(char.personality || '')}</textarea>
            <span class="field-hint">支持模板变量：<code>{{user}}</code>（用户昵称）、<code>{{char}}</code>（角色名称）</span>
        </div>

        <div class="form-field">
            <label for="cf-first-mes">开场白 (Greeting)<span class="field-warning" id="cf-warn-first-mes" hidden>建议填写</span></label>
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
    `;

    const actions = `
        <span class="form-status" id="cf-status"></span>
        <button class="btn-secondary modal-cancel">取消</button>
        <button class="btn-primary" id="cf-submit">${isEdit ? '保存修改' : '创建角色'}</button>
    `;

    openModal({
        title: isEdit ? '编辑角色' : '创建新角色',
        modalClass: 'character-form-modal',
        body,
        actions,
        removeExisting: '.modal-overlay',
        focusSelector: '#cf-name',
        onOpen(overlay, close) {
            // ── DOM 引用 ──
            const nameInput = overlay.querySelector('#cf-name');
            const personalityInput = overlay.querySelector('#cf-personality');
            const firstMesInput = overlay.querySelector('#cf-first-mes');
            const tempSlider = overlay.querySelector('#cf-temperature');
            const tempValue = overlay.querySelector('#cf-temp-value');
            const statusEl = overlay.querySelector('#cf-status');
            const avatarInput = overlay.querySelector('#cf-avatar');
            const avatarPreview = overlay.querySelector('#cf-avatar-preview');
            const warnName = overlay.querySelector('#cf-warn-name');
            const warnPersonality = overlay.querySelector('#cf-warn-personality');
            const warnFirstMes = overlay.querySelector('#cf-warn-first-mes');
            const completenessHint = overlay.querySelector('#cf-completeness-hint');

            // 完整性引导（D6）：姓名 + 人格设定 + 开场白三项均非空视为完整
            const updateCompletenessHints = () => {
                const name = nameInput.value.trim();
                const personality = personalityInput.value.trim();
                const firstMes = firstMesInput.value.trim();
                warnName.hidden = name.length > 0;
                warnPersonality.hidden = personality.length > 0;
                warnFirstMes.hidden = firstMes.length > 0;
                completenessHint.hidden = name.length > 0 && personality.length > 0 && firstMes.length > 0;
            };
            updateCompletenessHints();

            // ── 事件绑定 ──
            // 关闭路径（关闭按钮/遮罩点击/Escape）由工厂承担；取消按钮在此绑定
            overlay.querySelector('.modal-cancel').addEventListener('click', close);

            // 温度滑块实时显示
            tempSlider.addEventListener('input', () => {
                tempValue.textContent = parseFloat(tempSlider.value).toFixed(2);
            });

            // 头像预览（onerror 回退走渲染纯函数模块 avatarImgHtml 参数化复用）
            avatarInput.addEventListener('input', () => {
                const val = avatarInput.value.trim();
                if (val) {
                    avatarPreview.innerHTML = avatarImgHtml(val, '头像预览', "<span class='avatar-placeholder'>图片加载失败</span>");
                } else {
                    avatarPreview.innerHTML = '<span class="avatar-placeholder">无头像</span>';
                }
            });

            // 完整性引导：关键字段输入时实时刷新提示
            [nameInput, personalityInput, firstMesInput].forEach((el) => {
                el.addEventListener('input', updateCompletenessHints);
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

                // 完整性软提示（D6：软提示可跳过，不拦截；仅手动表单）
                const personality = personalityInput.value.trim();
                const firstMes = firstMesInput.value.trim();
                const missing = [];
                if (!personality) missing.push('人格设定');
                if (!firstMes) missing.push('开场白');
                if (missing.length > 0) {
                    const confirmed = await showConfirm({
                        title: '设定不完整',
                        message: `未填写 ${missing.join(' / ')}。建议补齐后保存，仍要保存吗？`,
                        confirmText: '仍要保存',
                        cancelText: '返回修改',
                    });
                    if (!confirmed) return;
                }

                // 收集数据（11 字段 payload 组装收敛到角色提交域深模块）
                const data = buildCharacterPayload({
                    name,
                    description: overlay.querySelector('#cf-description').value.trim(),
                    personality,
                    first_mes: firstMes,
                    scenario: overlay.querySelector('#cf-scenario').value.trim(),
                    mes_example: overlay.querySelector('#cf-mes-example').value.trim(),
                    system_prompt: overlay.querySelector('#cf-system-prompt').value.trim(),
                    temperature: tempSlider.value,
                    avatar: avatarInput.value.trim(),
                    creator: overlay.querySelector('#cf-creator').value.trim(),
                    tags: splitTags(overlay.querySelector('#cf-tags').value.trim()),
                });

                // 提交态状态机（禁用/文案/状态栏/600ms 延时关窗/失败恢复收敛到深模块）
                const submitBtn = overlay.querySelector('#cf-submit');
                beginSubmit(submitBtn, statusEl);

                try {
                    if (isEdit) {
                        await characters.update(char.id, data);
                        succeedSubmit(statusEl, `${iconHtml('check', { size: 14 })} 更新成功`, close, onSuccess);
                    } else {
                        await characters.create(data);
                        succeedSubmit(statusEl, `${iconHtml('check', { size: 14 })} 创建成功`, close, onSuccess);
                    }
                } catch (err) {
                    failSubmit(submitBtn, statusEl, err, isEdit ? '保存修改' : '创建角色');
                }
            });
        },
    });
}

/**
 * 将标签数组转为逗号分隔字符串（表单字段显示）
 */
function tagsToComma(tags) {
    if (!Array.isArray(tags) || tags.length === 0) return '';
    return tags.join(', ');
}
