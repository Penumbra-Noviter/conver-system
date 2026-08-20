import { beforeEach, afterEach, describe, expect, it } from 'vitest';
import { beginButtonLoading, clearButtonLoading } from '../js/components/loading-button.js';

// 按钮 loading 状态工具：禁用 + 内联 spinner + 文字切换，恢复时按 HTML 快照还原。

beforeEach(() => {
    document.body.innerHTML = '<button type="button" id="btn"><svg data-icon="plus"></svg>保存</button>';
});

afterEach(() => {
    document.body.innerHTML = '';
});

describe('beginButtonLoading', () => {
    it('禁用按钮 + 插入 spinner + 文字切换（含 icon 的按钮）', () => {
        const btn = document.querySelector('#btn');
        const restore = beginButtonLoading(btn, '保存中…');

        expect(btn.disabled).toBe(true);
        expect(btn.classList.contains('is-loading')).toBe(true);
        expect(btn.querySelector('.btn-spinner')).not.toBeNull();
        expect(btn.textContent).toContain('保存中…');
        expect(btn.querySelector('[data-icon]')).toBeNull(); // 文字切换期 icon 暂隐

        restore();
    });

    it('restore 还原按钮（含原 icon 与 disabled 原状）', () => {
        const btn = document.querySelector('#btn');
        const restore = beginButtonLoading(btn, '保存中…');
        restore();

        expect(btn.disabled).toBe(false);
        expect(btn.classList.contains('is-loading')).toBe(false);
        expect(btn.querySelector('.btn-spinner')).toBeNull();
        expect(btn.querySelector('[data-icon="plus"]')).not.toBeNull();
        expect(btn.textContent).toContain('保存');
    });

    it('restore 幂等（重复调用无副作用）', () => {
        const btn = document.querySelector('#btn');
        const restore = beginButtonLoading(btn, '保存中…');
        restore();
        restore();

        expect(btn.disabled).toBe(false);
        expect(btn.querySelector('.btn-spinner')).toBeNull();
    });

    it('loading 期间重复 beginButtonLoading no-op（防两个异步流互相覆盖）', () => {
        const btn = document.querySelector('#btn');
        const restore1 = beginButtonLoading(btn, 'A…');
        const restore2 = beginButtonLoading(btn, 'B…');

        expect(btn.textContent).toContain('A…');
        expect(btn.textContent).not.toContain('B…');

        restore1();
        restore2(); // no-op，不二次还原
        expect(btn.querySelector('[data-icon="plus"]')).not.toBeNull();
    });

    it('icon 按钮传空串 loadingText → 仅 spinner 无文字', () => {
        const btn = document.querySelector('#btn');
        const original = btn.textContent.trim();
        beginButtonLoading(btn, '');

        expect(btn.querySelector('.btn-spinner')).not.toBeNull();
        expect(btn.textContent.trim()).toBe('');

        // 清理（restore 引用不持有，走 clearButtonLoading）
        clearButtonLoading(btn);
        expect(btn.textContent.trim()).toBe(original);
    });
});

describe('clearButtonLoading', () => {
    it('还原 beginButtonLoading 状态（未持有 restore 引用的场景）', () => {
        const btn = document.querySelector('#btn');
        beginButtonLoading(btn, '加载中…');
        clearButtonLoading(btn);

        expect(btn.disabled).toBe(false);
        expect(btn.classList.contains('is-loading')).toBe(false);
        expect(btn.querySelector('.btn-spinner')).toBeNull();
        expect(btn.querySelector('[data-icon="plus"]')).not.toBeNull();
    });

    it('非 loading 态调用 no-op 不抛错', () => {
        const btn = document.querySelector('#btn');
        expect(() => clearButtonLoading(btn)).not.toThrow();
    });
});