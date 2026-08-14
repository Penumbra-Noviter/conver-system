import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { iconHtml, __all__ } from '../js/icons.js';

const INDEX_HTML = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'index.html');

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

    it('U7 新增 gamepad 图标：nav 用法（size 20 + nav-icon 类）渲染齐全', () => {
        const html = iconHtml('gamepad', { size: 20, className: 'nav-icon' });

        expect(html).toContain('data-icon="gamepad"');
        expect(html).toContain('aria-hidden="true"');
        expect(html).toContain('stroke="currentColor"');
        expect(html).toContain('class="nav-icon"');
        expect(html).toContain('width="20"');
        expect(html).toContain('height="20"');
        expect(html).toContain('<rect');
        expect(html).toContain('<path');
    });

    it('play 图标已下架：调用抛「未知图标: play」', () => {
        expect(() => iconHtml('play')).toThrow('未知图标: play');
    });

    it('index.html 内联 gamepad 副本与 iconHtml(\'gamepad\') 一致（归一化内部标记）', () => {
        const html = fs.readFileSync(INDEX_HTML, 'utf8');
        const inlineCopies = [...html.matchAll(/<svg[^>]*data-icon="gamepad"[^>]*>([\s\S]*?)<\/svg>/g)]
            .map((match) => match[1]);
        const factoryInner = iconHtml('gamepad').match(/<svg[^>]*>([\s\S]*?)<\/svg>/)[1];

        expect(inlineCopies).toHaveLength(2); // 锁现存双副本：侧栏 :46 区 + 移动端 :419 区
        for (const inner of inlineCopies) {
            expect(inner).toBe(factoryInner);
        }
    });

    it('__all__ 收口协议表面注册（U7 新增图标不改导出面）', () => {
        expect(__all__.sort()).toEqual(['iconHtml']);
    });
});
