import { describe, it, expect } from 'vitest';
import { renderMarkdown } from '../js/markdown.js';

describe('renderMarkdown', () => {
    describe('空输入', () => {
        it('空串 / 非字符串返回空串', () => {
            expect(renderMarkdown('')).toBe('');
            expect(renderMarkdown(null)).toBe('');
            expect(renderMarkdown(undefined)).toBe('');
            expect(renderMarkdown(123)).toBe('');
        });
    });

    describe('转义优先', () => {
        it('HTML 特殊字符被转义', () => {
            expect(renderMarkdown('a < b & c > d')).toBe('a &lt; b &amp; c &gt; d');
        });

        it('HTML 标签不生效，但 Markdown 标记生效', () => {
            expect(renderMarkdown('<b>x</b> *y*')).toBe('&lt;b&gt;x&lt;/b&gt; <em>y</em>');
        });

        it('脚本标签内容被转义后再解析标记', () => {
            expect(renderMarkdown('<script>alert(1)</script> **bold**')).toBe(
                '&lt;script&gt;alert(1)&lt;/script&gt; <strong>bold</strong>'
            );
        });
    });

    describe('代码块', () => {
        it('带语言标识', () => {
            expect(renderMarkdown('```js\nconst x = 1;\n```')).toBe(
                '<pre><code class="lang-js">const x = 1;\n</code></pre>'
            );
        });

        it('无语言标识', () => {
            expect(renderMarkdown('```\ncode\n```')).toBe('<pre><code>code\n</code></pre>');
        });

        it('代码块内 HTML 被转义（XSS 边界）', () => {
            expect(renderMarkdown('```html\n<img src=x onerror=alert(1)>\n```')).toBe(
                '<pre><code class="lang-html">&lt;img src=x onerror=alert(1)&gt;\n</code></pre>'
            );
        });

        it('未闭合围栏原样输出不崩溃', () => {
            expect(renderMarkdown('```\nunclosed')).toBe('```\nunclosed');
        });
    });

    describe('内联代码', () => {
        it('反引号包裹转 <code>', () => {
            expect(renderMarkdown('run `npm install` now')).toBe('run <code>npm install</code> now');
        });
    });

    describe('粗体 / 斜体', () => {
        it('** 双星号 → strong', () => {
            expect(renderMarkdown('**加粗**')).toBe('<strong>加粗</strong>');
        });

        it('* 单星号 → em', () => {
            expect(renderMarkdown('*斜体*')).toBe('<em>斜体</em>');
        });

        it('粗体斜体共存互不干扰', () => {
            expect(renderMarkdown('**b** and *i*')).toBe('<strong>b</strong> and <em>i</em>');
        });
    });

    describe('链接', () => {
        it('[text](url) → 安全新窗口链接', () => {
            expect(renderMarkdown('[官网](https://example.com)')).toBe(
                '<a href="https://example.com" target="_blank" rel="noopener noreferrer">官网</a>'
            );
        });

        it('链接文本 XSS 被转义', () => {
            expect(renderMarkdown('[<img src=x>](https://example.com)')).toBe(
                '<a href="https://example.com" target="_blank" rel="noopener noreferrer">&lt;img src=x&gt;</a>'
            );
        });

        it('危险 scheme（javascript:/data:/vbscript:）链接被中和为纯文本（XSS 边界）', () => {
            expect(renderMarkdown('[x](javascript:alert(1))')).not.toContain('<a');
            expect(renderMarkdown('[x](javascript:foo)')).toBe('x');
            expect(renderMarkdown('[x](JaVaScRiPt:foo)')).toBe('x');
            expect(renderMarkdown('[x]( javascript:foo)')).toBe('x');
            expect(renderMarkdown('[x](data:text/html)')).toBe('x');
            expect(renderMarkdown('[x](vbscript:msgbox)')).toBe('x');
        });

        it('安全 scheme 与无 scheme 地址仍渲染为链接', () => {
            expect(renderMarkdown('[a](https://x.com)')).toContain('href="https://x.com"');
            expect(renderMarkdown('[b](mailto:a@b.c)')).toContain('href="mailto:a@b.c"');
            expect(renderMarkdown('[c](/relative/path)')).toContain('href="/relative/path"');
        });
    });

    describe('列表状态机', () => {
        it('无序列表 - 连续行', () => {
            expect(renderMarkdown('- 甲\n- 乙')).toBe('<ul>\n<li>甲</li>\n<li>乙</li>\n</ul>');
        });

        it('有序列表 1. 2.', () => {
            expect(renderMarkdown('1. 一\n2. 二')).toBe('<ol>\n<li>一</li>\n<li>二</li>\n</ol>');
        });

        it('类型切换时正确关闭前一列表', () => {
            expect(renderMarkdown('- a\n1. b\n- c')).toBe(
                '<ul>\n<li>a</li>\n</ul>\n<ol>\n<li>b</li>\n</ol>\n<ul>\n<li>c</li>\n</ul>'
            );
        });

        it('普通行收尾时关闭打开中的列表', () => {
            expect(renderMarkdown('- a\n- b\nplain')).toBe(
                '<ul>\n<li>a</li>\n<li>b</li>\n</ul>\nplain'
            );
        });
    });

    describe('横线 / 空行', () => {
        it('--- 单独成行 → <hr>', () => {
            expect(renderMarkdown('---')).toBe('<hr>');
        });

        it('列表内横线先关闭列表', () => {
            expect(renderMarkdown('- a\n---\n- b')).toBe(
                '<ul>\n<li>a</li>\n</ul>\n<hr>\n<ul>\n<li>b</li>\n</ul>'
            );
        });

        it('空行 → 段落分隔', () => {
            expect(renderMarkdown('a\n\nb')).toBe('a\n<p></p>\nb');
        });
    });

    describe('Falsify：畸形标记不崩溃', () => {
        it('未闭合的链接/粗体/斜体/内联码原样输出', () => {
            expect(renderMarkdown('[x](abc')).toBe('[x](abc');
            expect(renderMarkdown('**unclosed')).toBe('**unclosed');
            expect(renderMarkdown('*unclosed')).toBe('*unclosed');
            expect(renderMarkdown('`unclosed')).toBe('`unclosed');
        });

        it('连续空行输出多个段落分隔', () => {
            expect(renderMarkdown('a\n\n\nb')).toBe('a\n<p></p>\n<p></p>\nb');
        });
    });
});
