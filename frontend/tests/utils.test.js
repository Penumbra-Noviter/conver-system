import { describe, it, expect } from 'vitest';
import { escapeHtml, getInitials, formatTags } from '../js/utils.js';

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
