/**
 * Conver System — 桌面壳设置（D11：关闭行为偏好）
 *
 * 职责：
 *   1. 经 __TAURI_INTERNALS__ 桥读写壳级设置（settings.json，Rust 侧 settings.rs）
 *   2. 首次运行（偏好未设置）弹出关闭行为选择弹窗
 *   3. 设置页「关闭窗口」分组回填与即时保存（独立于后端 settings API，
 *      属壳级偏好，不随「保存设置」按钮提交）
 *
 * 纯网页模式（无 Tauri 桥）全模块 no-op——托盘与关闭行为是桌面壳概念。
 * 协议表面（__all__）：hasDesktopBridge / getCloseAction / setCloseAction /
 * ensureCloseActionChoice / initCloseActionSetting。
 */

import { openModal } from './components/modal.js';
import { showAlert } from './components/confirm-dialog.js';
import { escapeHtml } from './utils.js';

const CLOSE_ACTIONS = ['tray', 'quit'];

/**
 * 是否运行于桌面壳（__TAURI_INTERNALS__ 由 Tauri 注入每个页面；网页版不存在）
 * @returns {boolean}
 */
export function hasDesktopBridge() {
    return typeof window.__TAURI_INTERNALS__?.invoke === 'function';
}

/**
 * 读取关闭行为偏好
 * @returns {Promise<null|'tray'|'quit'>} null = 未设置（首次运行 / 文件损坏 / 读取失败）
 */
export async function getCloseAction() {
    if (!hasDesktopBridge()) return null;
    try {
        return await window.__TAURI_INTERNALS__.invoke('get_close_action');
    } catch (err) {
        console.error('读取关闭行为偏好失败:', err);
        return null;
    }
}

/**
 * 写入关闭行为偏好（非法取值忽略，不发命令）。
 * 保存后自动读回验证，不一致时抛错。
 * @param {'tray'|'quit'} action
 * @returns {Promise<void>}
 */
export async function setCloseAction(action) {
    if (!hasDesktopBridge() || !CLOSE_ACTIONS.includes(action)) return;
    await window.__TAURI_INTERNALS__.invoke('set_close_action', { action });
    // 读回验证：确保 Rust 侧实际落盘的值与预期一致
    const readback = await getCloseAction();
    if (readback !== action) {
        throw new Error(
            `关闭行为保存后读回不匹配: 期望 "${action}", 读回 "${readback || 'null'}"`
        );
    }
}

/**
 * 展示关闭行为选择弹窗（两按钮必选其一；关闭按钮/遮罩/Escape 按默认托盘处理，
 * 不改变既有关闭语义，仅放弃本次选择）
 * @returns {Promise<'tray'|'quit'>}
 */
function showCloseActionChoice() {
    return new Promise((resolve) => {
        openModal({
            title: '关闭窗口时的默认行为',
            modalClass: 'close-action-modal',
            removeExisting: '.confirm-modal, .close-action-modal',
            focusSelector: '.close-action-tray',
            cancelResult: 'tray',
            onClose: resolve,
            body: `
                <p class="confirm-message">点击窗口关闭按钮后，程序仍会在系统托盘继续后台运行。请选择你希望的默认行为：</p>
                <div class="close-action-options">
                    <button type="button" class="btn-secondary close-action-tray">最小化到托盘（后台继续运行）</button>
                    <button type="button" class="btn-primary close-action-quit">直接退出程序</button>
                </div>
                <p class="settings-hint">之后可在「设置 → 关闭窗口」中更改。</p>
            `,
            onOpen: (overlay, close) => {
                overlay
                    .querySelector('.close-action-tray')
                    .addEventListener('click', () => close('tray'));
                overlay
                    .querySelector('.close-action-quit')
                    .addEventListener('click', () => close('quit'));
            },
        });
    });
}

/**
 * 首次运行引导：偏好未设置 → 弹出选择并持久化（已设置 / 纯网页模式 no-op）。
 * 保存失败时显示可见告警，不阻塞使用——关闭语义保持默认托盘，下次启动可重试。
 * @returns {Promise<void>}
 */
export async function ensureCloseActionChoice() {
    if (!hasDesktopBridge()) return;
    const current = await getCloseAction();
    if (current !== null) return;
    const chosen = await showCloseActionChoice();
    try {
        await setCloseAction(chosen);
        syncCloseActionSetting(chosen);
    } catch (err) {
        console.error('保存关闭行为偏好失败:', err);
        showAlert('关闭行为保存失败，请重试: ' + err.message);
    }
}

/**
 * 初始化设置页「关闭窗口」分组：仅桌面壳显示，回填当前值，变更即时保存。
 * 分组元素缺失（index.html 契约被破坏的极端场景）→ no-op 不抛错。
 * @returns {Promise<void>}
 */
export async function initCloseActionSetting() {
    if (!hasDesktopBridge()) return;
    const group = document.querySelector('#group-close-action');
    if (!group) return;
    group.hidden = false;
    const current = await getCloseAction();
    if (current) syncCloseActionSetting(current);
    group.querySelectorAll('input[name="close-action"]').forEach((radio) => {
        radio.addEventListener('change', async () => {
            try {
                await setCloseAction(radio.value);
                syncCloseActionSetting(radio.value);
                showAlert('关闭行为已保存');
            } catch (err) {
                console.error('保存关闭行为偏好失败:', err);
                showAlert('保存失败: ' + err.message);
            }
        });
    });
}

/**
 * 同步设置页单选框到当前偏好（写入失败 / 首次弹窗选择后保持表单一致）
 * @param {'tray'|'quit'} action
 */
function syncCloseActionSetting(action) {
    document.querySelectorAll('input[name="close-action"]').forEach((radio) => {
        radio.checked = radio.value === action;
    });
}

export const __all__ = [
    'hasDesktopBridge',
    'getCloseAction',
    'setCloseAction',
    'ensureCloseActionChoice',
    'initCloseActionSetting',
];