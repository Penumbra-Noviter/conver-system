/**
 * error-bar.js 深模块单测（T1 — 首启引导与无 Key 主路径闭环）
 *
 * 覆盖渲染契约（全部经公共 seam renderErrorBar 驱动，不触碰内部实现）：
 *   - 文案分流：none 态显示「配置 Key」引导文案；其他态显示原始错误信息
 *   - 交互：「前往设置」按钮存在且点击触发 onNavigateSettings；手动关闭按钮移除条
 *   - 生命周期：约 ERROR_BAR_DISMISS_MS 自动消失（fake timers）
 *   - 幂等：同容器重复渲染替换旧条（仅一条在屏）
 *   - Falsify：无容器 / 无导航回调 / 非字符串 message 均不抛错
 *
 * 挂载模式：jsdom + 动态 import（深模块无模块级状态，无需 resetModules）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

let container;
let errorBarModule;

async function loadModule() {
    vi.resetModules();
    container = document.createElement('div');
    document.body.appendChild(container);
    return await import('../js/error-bar.js');
}

beforeEach(() => {
    document.body.innerHTML = '';
    return loadModule().then((m) => { errorBarModule = m; });
});

afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = '';
});

describe('renderErrorBar — 文案分流（none / 其他态）', () => {
    it('其他态（openai/claude）→ 显示原始错误信息', () => {
        errorBarModule.renderErrorBar({
            container, message: '网络超时，请重试', protocol: 'openai',
            onNavigateSettings: vi.fn(),
        });
        const bar = container.querySelector('.chat-error-bar');
        expect(bar).not.toBeNull();
        expect(bar.textContent).toContain('网络超时，请重试');
    });

    it('none 态 → 显示「配置 Key」引导文案（不显示原始错误）', () => {
        errorBarModule.renderErrorBar({
            container, message: '401 Unauthorized', protocol: 'none',
            onNavigateSettings: vi.fn(),
        });
        const bar = container.querySelector('.chat-error-bar');
        expect(bar.textContent).toContain('配置 Key');
        expect(bar.textContent).not.toContain('401 Unauthorized');
    });

    it('null/未知 protocol → 视同其他态，显示原始错误（保守不引导）', () => {
        errorBarModule.renderErrorBar({
            container, message: '请求失败', protocol: null, onNavigateSettings: vi.fn(),
        });
        expect(container.querySelector('.chat-error-bar').textContent).toContain('请求失败');
    });
});

describe('renderErrorBar — 交互（前往设置 / 手动关闭 / 自动消失）', () => {
    it('「前往设置」按钮存在；点击 → onNavigateSettings 被调 + 条关闭', () => {
        const nav = vi.fn();
        errorBarModule.renderErrorBar({
            container, message: 'boom', protocol: 'openai', onNavigateSettings: nav,
        });
        const navBtn = container.querySelector('.chat-error-bar-nav');
        expect(navBtn).not.toBeNull();
        expect(navBtn.textContent).toContain('前往设置');
        navBtn.click();
        expect(nav).toHaveBeenCalledTimes(1);
        expect(container.querySelector('.chat-error-bar')).toBeNull();
    });

    it('手动关闭按钮 → 条移除', () => {
        errorBarModule.renderErrorBar({
            container, message: 'boom', protocol: 'openai', onNavigateSettings: vi.fn(),
        });
        container.querySelector('.chat-error-bar-close').click();
        expect(container.querySelector('.chat-error-bar')).toBeNull();
    });

    it('约 ERROR_BAR_DISMISS_MS 后自动消失', () => {
        vi.useFakeTimers();
        errorBarModule.renderErrorBar({
            container, message: 'boom', protocol: 'openai', onNavigateSettings: vi.fn(),
        });
        expect(container.querySelector('.chat-error-bar')).not.toBeNull();
        vi.advanceTimersByTime(errorBarModule.ERROR_BAR_DISMISS_MS);
        expect(container.querySelector('.chat-error-bar')).toBeNull();
    });

    it('再次渲染同容器 → 替换旧条（仅一条在屏）', () => {
        errorBarModule.renderErrorBar({
            container, message: 'err1', protocol: 'openai', onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: 'err2', protocol: 'openai', onNavigateSettings: vi.fn(),
        });
        expect(container.querySelectorAll('.chat-error-bar')).toHaveLength(1);
        expect(container.querySelector('.chat-error-bar').textContent).toContain('err2');
    });
});

describe('renderErrorBar — Falsify（入参防御）', () => {
    it('无容器 → no-op 不抛错', () => {
        expect(() => errorBarModule.renderErrorBar({
            message: 'x', protocol: 'openai', onNavigateSettings: vi.fn(),
        })).not.toThrow();
        expect(() => errorBarModule.renderErrorBar()).not.toThrow();
    });

    it('无 onNavigateSettings（非函数）→ 「前往设置」点击 no-op 不抛错', () => {
        errorBarModule.renderErrorBar({ container, message: 'x', protocol: 'openai' });
        expect(() => container.querySelector('.chat-error-bar-nav').click()).not.toThrow();
        expect(container.querySelector('.chat-error-bar')).toBeNull();
    });

    it('非字符串 message（undefined/null）→ 不抛错、条可渲染', () => {
        expect(() => errorBarModule.renderErrorBar({
            container, message: undefined, protocol: 'openai', onNavigateSettings: vi.fn(),
        })).not.toThrow();
        expect(container.querySelector('.chat-error-bar')).not.toBeNull();
    });
});

describe('renderErrorBar — 会话隔离（F-50 跨会话并存）', () => {
    it('两个不同 conversationId → 错误条可同时并存（各自 data-conv）', () => {
        errorBarModule.renderErrorBar({
            container, message: '会话A错误', protocol: 'openai', conversationId: 11, onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: '会话B错误', protocol: 'openai', conversationId: 22, onNavigateSettings: vi.fn(),
        });
        const bars = container.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(2);
        expect([...bars].map((b) => b.dataset.conv).sort()).toEqual(['11', '22']);
        expect(container.textContent).toContain('会话A错误');
        expect(container.textContent).toContain('会话B错误');
    });

    it('同一 conversationId 连续两次渲染 → 替换旧条，容器内仅一条', () => {
        errorBarModule.renderErrorBar({
            container, message: 'err1', protocol: 'openai', conversationId: 7, onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: 'err2', protocol: 'openai', conversationId: 7, onNavigateSettings: vi.fn(),
        });
        const bars = container.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(1);
        expect(bars[0].textContent).toContain('err2');
        expect(bars[0].dataset.conv).toBe('7');
    });

    it('同会话重复渲染只移除同会话旧条 — 其他会话的条不被动到', () => {
        errorBarModule.renderErrorBar({
            container, message: 'A1', protocol: 'openai', conversationId: 1, onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: 'B1', protocol: 'openai', conversationId: 2, onNavigateSettings: vi.fn(),
        });
        // 会话 2 再次失败 → 只替换会话 2 的条
        errorBarModule.renderErrorBar({
            container, message: 'B2', protocol: 'openai', conversationId: 2, onNavigateSettings: vi.fn(),
        });
        const bars = container.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(2);
        const byConv = Object.fromEntries([...bars].map((b) => [b.dataset.conv, b.textContent]));
        expect(byConv['1']).toContain('A1');
        expect(byConv['2']).toContain('B2');
    });

    it('无 conversationId（undefined）→ 保持既有行为：移除容器内所有旧条后插入', () => {
        errorBarModule.renderErrorBar({
            container, message: 'A1', protocol: 'openai', conversationId: 1, onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: '全局错误', protocol: 'openai', onNavigateSettings: vi.fn(),
        });
        const bars = container.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(1);
        expect(bars[0].textContent).toContain('全局错误');
        expect(bars[0].dataset.conv).toBeUndefined();
    });

    it('无 conversationId（null）→ 视同无会话身份，移除容器内所有旧条后插入', () => {
        errorBarModule.renderErrorBar({
            container, message: 'A1', protocol: 'openai', conversationId: 5, onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: 'err', protocol: 'openai', conversationId: null, onNavigateSettings: vi.fn(),
        });
        expect(container.querySelectorAll('.chat-error-bar')).toHaveLength(1);
        expect(container.querySelector('.chat-error-bar').dataset.conv).toBeUndefined();
    });

    it('字符串 conversationId 与数字可等同寻址（data-conv 归一为字符串）', () => {
        errorBarModule.renderErrorBar({
            container, message: 'str', protocol: 'openai', conversationId: '42', onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: 'num', protocol: 'openai', conversationId: 42, onNavigateSettings: vi.fn(),
        });
        const bars = container.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(1);
        expect(bars[0].dataset.conv).toBe('42');
        expect(bars[0].textContent).toContain('num');
    });
});

describe('renderErrorBar — 特殊字符会话 id（F-67 选择器注入防御）', () => {
    it('conversationId 含 " 或 ] 时不抛 SyntaxError，条正常渲染', () => {
        expect(() => errorBarModule.renderErrorBar({
            container, message: '特殊id错误', protocol: 'openai',
            conversationId: 'a"b]c', onNavigateSettings: vi.fn(),
        })).not.toThrow();
        expect(container.querySelector('.chat-error-bar')).not.toBeNull();
    });

    it('含特殊字符会话 id 同会话幂等替换 — 第二次渲染不残留重复条', () => {
        errorBarModule.renderErrorBar({
            container, message: 'err1', protocol: 'openai',
            conversationId: 'a"b]c', onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: 'err2', protocol: 'openai',
            conversationId: 'a"b]c', onNavigateSettings: vi.fn(),
        });
        const bars = container.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(1);
        expect(bars[0].textContent).toContain('err2');
        expect(bars[0].dataset.conv).toBe('a"b]c');
    });

    it('不同会话（含特殊字符 id）跨会话并存不被误删（F-50 保持）', () => {
        errorBarModule.renderErrorBar({
            container, message: 'A1', protocol: 'openai',
            conversationId: 'a"b', onNavigateSettings: vi.fn(),
        });
        errorBarModule.renderErrorBar({
            container, message: 'B1', protocol: 'openai',
            conversationId: 'c]d', onNavigateSettings: vi.fn(),
        });
        // 会话 c]d 再次失败 → 只替换该会话的条，a"b 的条不被动到
        errorBarModule.renderErrorBar({
            container, message: 'B2', protocol: 'openai',
            conversationId: 'c]d', onNavigateSettings: vi.fn(),
        });
        const bars = container.querySelectorAll('.chat-error-bar');
        expect(bars).toHaveLength(2);
        const byConv = Object.fromEntries([...bars].map((b) => [b.dataset.conv, b.textContent]));
        expect(byConv['a"b']).toContain('A1');
        expect(byConv['c]d']).toContain('B2');
    });
});

describe('error-bar — 协议表面收口', () => {
    it('__all__ 收口全部公开符号', () => {
        expect(errorBarModule.__all__.sort()).toEqual(['ERROR_BAR_DISMISS_MS', 'renderErrorBar']);
    });
});
