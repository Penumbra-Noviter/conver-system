import { describe, expect, it } from 'vitest';
import { iconHtml } from '../js/icons.js';

describe('iconHtml', () => {
    it('按名称生成可由 CSS 着色的装饰性 SVG', () => {
        const html = iconHtml('send', { size: 18, className: 'action-icon' });

        expect(html).toContain('<svg');
        expect(html).toContain('data-icon="send"');
        expect(html).toContain('aria-hidden="true"');
        expect(html).toContain('stroke="currentColor"');
        expect(html).toContain('width="18"');
        expect(html).toContain('height="18"');
        expect(html).toContain('class="action-icon"');
    });

    it('拒绝未知图标名称，包括对象原型链名称', () => {
        expect(() => iconHtml('not-an-icon')).toThrow('未知图标: not-an-icon');
        expect(() => iconHtml('constructor')).toThrow('未知图标: constructor');
        expect(() => iconHtml('__proto__')).toThrow('未知图标: __proto__');
    });

    it('拒绝非法尺寸和可注入的 CSS 类名', () => {
        expect(() => iconHtml('send', { size: -1 })).toThrow('图标尺寸必须是 1 到 128 的有限数字');
        expect(() => iconHtml('send', { size: Infinity })).toThrow('图标尺寸必须是 1 到 128 的有限数字');
        expect(() => iconHtml('send', { size: '16\" onload=\"alert(1)' })).toThrow('图标尺寸必须是 1 到 128 的有限数字');
        expect(() => iconHtml('send', { className: 'x\" onload=\"alert(1)' })).toThrow('图标类名只能包含 CSS 标识符');
        expect(() => iconHtml('send', null)).toThrow('图标选项必须是对象');
    });
});
