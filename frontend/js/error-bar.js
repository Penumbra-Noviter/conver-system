/**
 * Conver System — 错误条深模块（T1 首启引导与无 Key 主路径闭环）
 *
 * 职责：渲染一条独立、可关闭的聊天错误提示条，供聊天域统一承载发送失败
 *   （非流式 / 流式）的错误提示 —— 错误不再写入消息列表或 tab 缓存：
 *   - 文案分流：凭证协议为 none（未配置 AI 接口）时显示「配置 Key」引导文案；
 *     其他态（openai / claude / 未知）显示原始错误信息；
 *   - 交互：「前往设置」按钮（点击调注入的 onNavigateSettings，复用视图切换
 *     勾子）+ 手动关闭按钮；约 ERROR_BAR_DISMISS_MS 自动消失；
 *   - 幂等：同一容器重复渲染替换旧条（同一时刻仅一条在屏）；
 *   - 入参防御：无容器 / 无导航回调 / 非字符串 message 均静默降级不抛错。
 *
 * 依赖方向：error-bar.js → 无（纯 DOM 深模块；导航回调经参数注入，避免反向
 *   依赖 app.js 的私有 switchView）。chat.js → error-bar.js（renderErrorBar）。
 *
 * 渲染位置：条挂到调用方传入的容器（chat.js 传 #chat-messages 的父级 ——
 *   不随 renderMessages 的 innerHTML 重建而消失）。
 */

// ══════════════════════════════════════════════════
// 常量（UI 契约 — 文案/时长与 spec 对齐）
// ══════════════════════════════════════════════════

/** 错误条自动消失时长（毫秒；spec「约 8 秒自动消失」） */
export const ERROR_BAR_DISMISS_MS = 8000;

/** 「前往设置」按钮文案 */
const TEXT_NAV_SETTINGS = '前往设置';

/** none 态引导文案（spec：「无 Key 态文案引导配 Key」） */
const TEXT_NONE_GUIDE = '未配置 AI 接口，请先配置 Key';

/** 错误条根节点选择器（容器内同刻仅一条；重复渲染替换旧条） */
const SEL_ERROR_BAR = '.chat-error-bar';

// ══════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════

/**
 * 渲染错误条到容器（顶部插入；同容器已有旧条先移除 — 仅一条在屏）。
 *
 * 文案分流：protocol === 'none' → 显示「配置 Key」引导文案（不含原始错误）；
 *   其余 protocol → 显示原始错误信息（errMsg 兜底为 message 字符串本身）。
 * 「前往设置」按钮点击：调 onNavigateSettings（函数时；非函数时 no-op）并关闭
 *   本条；手动关闭按钮 / 约 ERROR_BAR_DISMISS_MS 自动消失（timer 在手动关闭
 *   与导航关闭时一并清除，杜绝残留计时器）。
 * 入参防御：container 缺失（非容器元素）→ no-op 返回 null（不抛错）。
 *
 * @param {object} [params]
 * @param {HTMLElement|null} [params.container] - 挂载容器（须支持
 *   querySelector/insertBefore；缺失时 no-op）
 * @param {string} [params.message] - 原始错误信息（none 态不使用）
 * @param {string|null} [params.protocol] - 凭证协议（'openai' | 'claude' |
 *   'none' | null/未知）；仅 'none' 触发引导文案分流
 * @param {Function} [params.onNavigateSettings] - 「前往设置」点击回调
 *   （app.js 接线 switchView('settings')；非函数时点击 no-op）
 * @returns {HTMLElement|null} 本次渲染的错误条元素；容器缺失时为 null
 */
export function renderErrorBar({ container, message, protocol, onNavigateSettings } = {}) {
    if (!container || typeof container.querySelector !== 'function') return null;

    // 幂等：同容器重复渲染替换旧条
    container.querySelector(SEL_ERROR_BAR)?.remove();

    const isNone = protocol === 'none';
    const text = isNone ? TEXT_NONE_GUIDE : String(message ?? '');

    const bar = document.createElement('div');
    bar.className = 'chat-error-bar';
    bar.setAttribute('role', 'alert');

    const msg = document.createElement('span');
    msg.className = 'chat-error-bar-msg';
    msg.textContent = text;

    const navBtn = document.createElement('button');
    navBtn.className = 'chat-error-bar-nav';
    navBtn.textContent = TEXT_NAV_SETTINGS;

    const closeBtn = document.createElement('button');
    closeBtn.className = 'chat-error-bar-close';
    closeBtn.setAttribute('aria-label', '关闭');
    closeBtn.textContent = '✕';

    bar.append(msg, navBtn, closeBtn);

    // 基础视觉（复用既有 CSS 变量；正式样式表未随本票扩展，先以内联保证可见）
    bar.style.display = 'flex';
    bar.style.alignItems = 'center';
    bar.style.flexWrap = 'wrap';
    bar.style.gap = '10px';
    bar.style.padding = '10px 14px';
    bar.style.background = 'var(--panel-2)';
    bar.style.border = '1px solid var(--ink-4)';
    bar.style.borderRadius = 'var(--radius-md)';
    bar.style.color = 'var(--ink-2)';
    bar.style.fontSize = 'var(--text-sm)';

    /** @type {ReturnType<typeof setTimeout>|undefined} 自动消失计时器（nav/close 时清除） */
    let dismissTimer;

    const dismiss = () => {
        if (dismissTimer) {
            clearTimeout(dismissTimer);
            dismissTimer = undefined;
        }
        bar.remove();
    };

    closeBtn.addEventListener('click', dismiss);

    navBtn.addEventListener('click', () => {
        if (typeof onNavigateSettings === 'function') onNavigateSettings();
        dismiss();
    });

    dismissTimer = setTimeout(dismiss, ERROR_BAR_DISMISS_MS);

    container.insertBefore(bar, container.firstChild);
    return bar;
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些符号与 error-bar.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'renderErrorBar',
    'ERROR_BAR_DISMISS_MS',
];