/**
 * Conver System — 会话 tab 条（presentational 组件）
 *
 * 职责：
 *   1. 订阅 tabs.js 的 onTabsChanged，变更即重渲染 tab 条
 *   2. 事件委托：点击 tab → 经注入的 onActivate 处理器激活（app.js 注入，
 *      内部走 P6.5-2 收敛的统一激活流程）；点击 ✕ → 直接 closeTab
 *   3. 状态指示：生成中（phase thinking/streaming）tab 标题前脉冲小圆点；
 *      出错/停止（phase error）警示标记；完成（phase done）无提示
 *   4. 无 tab 时不渲染容器（hidden）
 *
 * 依赖方向：tab-bar.js → tabs.js（协议）+ utils.js（escapeHtml）；
 *   app.js → tab-bar.js（注入 onActivate，避免反向依赖）
 *
 * 关键语义：
 *   - 关闭流式中的 tab = 显式停止：先 abort 其 activeStream 再 closeTab；
 *     其后的异步写回（onError 经 updateTab）由 tabs.js 幂等 no-op 兜底
 *   - 关闭的是活动 tab → 激活右邻居（无则左）；关最后一个 → onActivate(null)
 *     （app.js 侧转空态）；此时 DOM 视图已过期（仍显示被关会话），
 *     故以 { saveCurrent: false } 通知 app.js 跳过「保存当前视图」步骤，
 *     防止被关会话的 DOM 草稿/滚动污染新活动 tab 缓存
 */

import { getTabs, getActiveTab, getTab, closeTab, onTabsChanged } from '../tabs.js';
import { escapeHtml } from '../utils.js';

/**
 * 初始化 tab 条组件
 * @param {object} options
 * @param {HTMLElement} options.container - #chat-tabs 容器
 * @param {Function} [options.onActivate] - 激活处理器 (convId, opts) => void；
 *   由 app.js 注入。opts.saveCurrent=false 表示 DOM 视图已过期（✕ 关闭活动 tab 联动）
 * @returns {Function} 卸载函数（取消订阅 + 解绑事件）
 */
export function initTabBar({ container, onActivate } = {}) {
    if (!container) return () => {};

    const handleClick = (e) => {
        const closeBtn = e.target.closest('.tab-close');
        const tabEl = e.target.closest('.chat-tab');
        if (!tabEl) return;
        const convId = Number(tabEl.dataset.convId);

        if (closeBtn) {
            // 关闭流式中的 tab = 显式停止（先 abort 再关）
            const tab = getTab(convId);
            if (tab?.activeStream) {
                try { tab.activeStream.abort(); } catch { /* 忽略中止失败 */ }
            }
            const wasActive = getActiveTab()?.conversationId === convId;
            closeTab(convId);
            if (wasActive && typeof onActivate === 'function') {
                // 右邻居（无则左）激活；无剩余 tab → null（空态）。
                // DOM 视图已过期 → saveCurrent:false 防止缓存污染
                onActivate(getActiveTab()?.conversationId ?? null, { saveCurrent: false });
            }
        } else if (typeof onActivate === 'function') {
            onActivate(convId);
        }
    };

    const render = () => {
        const tabs = getTabs();
        container.hidden = tabs.length === 0;
        if (tabs.length === 0) {
            container.innerHTML = '';
            return;
        }
        const activeId = getActiveTab()?.conversationId ?? null;
        container.innerHTML = tabs
            .map((t) => {
                const isActive = t.conversationId === activeId;
                const generating = t.phase === 'thinking' || t.phase === 'streaming';
                const title = t.title || '未命名会话';
                return `
            <div class="chat-tab${isActive ? ' active' : ''}" data-conv-id="${t.conversationId}" title="${escapeHtml(title)}">
                ${generating ? '<span class="tab-dot" title="生成中"></span>' : ''}
                ${t.phase === 'error' ? '<span class="tab-warn" title="生成出错/已停止">!</span>' : ''}
                <span class="tab-title">${escapeHtml(title)}</span>
                <button class="tab-close" title="关闭会话">✕</button>
            </div>`;
            })
            .join('');
    };

    render();
    const unsubscribe = onTabsChanged(render);
    container.addEventListener('click', handleClick);
    return () => {
        unsubscribe();
        container.removeEventListener('click', handleClick);
    };
}

export const __all__ = ['initTabBar'];
