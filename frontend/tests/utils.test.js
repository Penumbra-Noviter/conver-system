import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { escapeHtml, getInitials, formatTags, autoResizeInput, showToast, showSuccess, showError, MAX_TOASTS } from '../js/utils.js';

describe('showToast — 队列上限', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
        // 清理遗留定时器
        vi.useFakeTimers();
    });
    afterEach(() => {
        vi.useRealTimers();
        document.body.innerHTML = '';
    });

    it('MAX_TOASTS 常量约等于 3', () => {
        expect(MAX_TOASTS).toBeGreaterThanOrEqual(2);
        expect(MAX_TOASTS).toBeLessThanOrEqual(4);
    });

    it('显示 1 条 toast → DOM 中 1 条', () => {
        showToast('消息1');
        expect(document.body.querySelectorAll('.toast').length).toBe(1);
    });

    it('4 条 toast ≥ MAX_TOASTS 时移除最旧一条', () => {
        showToast('消息1');
        showToast('消息2');
        showToast('消息3');
        showToast('消息4'); // 第 4 条 → 挤掉最旧

        const toasts = document.body.querySelectorAll('.toast');
        expect(toasts.length).toBe(MAX_TOASTS);
        // 最旧一条（消息1）已被移除
        expect([...toasts].map((t) => t.textContent)).not.toContain('消息1');
        // 新条（消息4）存在
        expect([...toasts].map((t) => t.textContent)).toContain('消息4');
    });

    it('showError / showSuccess 薄封装行为一致（队列上限 + 5s 自动消失）', async () => {
        showError('错误1');
        showSuccess('成功1');
        showError('错误2');
        showSuccess('成功2'); // 第4条 → 挤掉最旧

        const toasts = document.body.querySelectorAll('.toast');
        expect(toasts.length).toBe(MAX_TOASTS);
        // 最旧一条（错误1）已被移除
        expect([...toasts].map((t) => t.textContent)).not.toContain('错误1');
        showSuccess('成功3'); // 第5条 → 挤掉最旧（成功1）
        expect([...document.body.querySelectorAll('.toast')].map((t) => t.textContent)).not.toContain('成功1');
    });

    it('定时器到期后 toast 自动移除', () => {
        showToast('自动消失');
        expect(document.body.querySelectorAll('.toast').length).toBe(1);
        vi.advanceTimersByTime(5000);
        expect(document.body.querySelectorAll('.toast').length).toBe(0);
    });
});

describe('escapeHtml', () => {
    it('转义 < > &', () => {
        expect(escapeHtml('<script>x</script>')).toBe('&lt;script&gt;x&lt;/script&gt;');
        expect(escapeHtml('a & b')).toBe('a &amp; b');
    });

    it('非字符串返回空串', () => {
        expect(escapeHtml(null)).toBe('');
        expect(escapeHtml(undefined)).toBe('');
        expect(escapeHtml(123)).toBe('');
    });

    it('普通文本不变', () => {
        expect(escapeHtml('plain text')).toBe('plain text');
    });
});

describe('getInitials', () => {
    it('中文名取前两字', () => {
        expect(getInitials('测试角色')).toBe('测试');
    });

    it('英文名取前两字母大写', () => {
        expect(getInitials('alice')).toBe('AL');
        expect(getInitials('Bob')).toBe('BO');
    });

    it('空值返回 ?', () => {
        expect(getInitials('')).toBe('?');
        expect(getInitials(null)).toBe('?');
    });
});

describe('formatTags', () => {
    it('取前三个标签', () => {
        expect(formatTags(['冒险', '奇幻', '可爱', '多余'])).toBe('冒险, 奇幻, 可爱');
    });

    it('空数组/非数组返回空串', () => {
        expect(formatTags([])).toBe('');
        expect(formatTags(null)).toBe('');
        expect(formatTags('not-array')).toBe('');
    });
});

describe('autoResizeInput', () => {
    it('先复位再按 scrollHeight 增高（150px 上限）', () => {
        const el = document.createElement('textarea');
        Object.defineProperty(el, 'scrollHeight', { value: 200, configurable: true });
        el.style.height = '10px';

        autoResizeInput(el);

        expect(el.style.height).toBe('150px'); // Math.min(200, 150) + 'px'

        Object.defineProperty(el, 'scrollHeight', { value: 40, configurable: true });
        autoResizeInput(el);
        expect(el.style.height).toBe('40px');
    });

    it('scrollHeight 为 0（jsdom 无布局）不抛错', () => {
        const el = document.createElement('textarea');
        el.style.height = '10px';
        expect(() => autoResizeInput(el)).not.toThrow();
    });
});
