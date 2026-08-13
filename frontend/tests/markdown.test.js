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

        it('代码块内 **x** 保持字面，不被渲染为 strong（TD-38 防回归）', () => {
            expect(renderMarkdown('```\n**x**\n```')).toBe('<pre><code>**x**\n</code></pre>');
        });

        it('代码块内 [x](y) 保持字面，不渲染出链接（TD-38 防回归）', () => {
            const out = renderMarkdown('```\n[a](b)\n```');
            expect(out).toBe('<pre><code>[a](b)\n</code></pre>');
            expect(out).not.toContain('<a');
        });

        it('代码块内 `x` 保持字面，不渲染为内联代码（TD-38 防回归）', () => {
            expect(renderMarkdown('```\n`x`\n```')).toBe('<pre><code>`x`\n</code></pre>');
        });
    });

    describe('占位符碰撞免疫（TD-38 防复发：碰撞计数器失同步阻断修复）', () => {
        const NUL = '\u0000';
        const nulCount = (s) => s.match(/\u0000/g) ?? [];

        it('单块 + 用户内容含 \u0000MDCB0\u0000 → 碰撞跳号，代码块正确还原', () => {
            const out = renderMarkdown(`\u0000MDCB0\u0000\n\n\`\`\`\ncode\n\`\`\``);
            expect(out).toContain('<pre><code>code\n</code></pre>');
            // 用户自带 NUL 占位符同形文本属用户内容，原样保留（非占位符泄漏）
            expect(nulCount(out)).toHaveLength(2);
        });

        it('双块 + 用户内容含 \u0000MDCB0\u0000 → 两块各自独立还原（防复发：FIRST 不丢失、SECOND 不双份）', () => {
            const out = renderMarkdown(
                `\u0000MDCB0\u0000\n\n\`\`\`\nFIRST\n\`\`\`\n\n\`\`\`\nSECOND\n\`\`\``
            );
            // 审核实证：修复前 FIRST 完全丢失、SECOND 出现两次（计数器失同步 → 第二块复用
            // 第一块占位符 → Map.set 覆盖首条记录 → 还原循环把两处占位符都替换为第二块 HTML）
            expect(out).toContain('<pre><code>FIRST\n</code></pre>');
            expect(out).toContain('<pre><code>SECOND\n</code></pre>');
            // 无 NUL 残留（占位符不得泄漏）：输出仅含输入自带 \u0000MDCB0\u0000 字面量的
            // 2 个 NUL，渲染器取号（MDCB1/MDCB2）必须全部还原，不得以占位符形态残留
            expect(nulCount(out)).toHaveLength(2);
        });

        it('双块 + 用户内容含 \u0000MDCB0\u0000 与 \u0000MDCB1\u0000 → 三索引碰撞链后仍独立还原（防复发）', () => {
            const out = renderMarkdown(
                `\u0000MDCB0\u0000\u0000MDCB1\u0000\n\n\`\`\`\nFIRST\n\`\`\`\n\n\`\`\`\nSECOND\n\`\`\``
            );
            expect(out).toContain('<pre><code>FIRST\n</code></pre>');
            expect(out).toContain('<pre><code>SECOND\n</code></pre>');
            // 用户字面量 MDCB0/MDCB1 共 4 个 NUL；渲染器占位符全部还原
            expect(nulCount(out)).toHaveLength(4);
        });

        it('三块 + 用户内容含 \u0000MDCB0\u0000 → 三块全部独立还原（防复发）', () => {
            const out = renderMarkdown(
                `\u0000MDCB0\u0000\n\n\`\`\`\nA\n\`\`\`\n\n\`\`\`\nB\n\`\`\`\n\n\`\`\`\nC\n\`\`\``
            );
            expect(out).toContain('<pre><code>A\n</code></pre>');
            expect(out).toContain('<pre><code>B\n</code></pre>');
            expect(out).toContain('<pre><code>C\n</code></pre>');
            expect(nulCount(out)).toHaveLength(2);
        });

        it('块内容本身含碰撞索引文本（\u0000MDCB1\u0000 在首块内）→ 互不误替', () => {
            const out = renderMarkdown(
                `\`\`\`\n\u0000MDCB1\u0000\n\`\`\`\n\n\`\`\`\nSECOND\n\`\`\``
            );
            expect(out).toContain('<pre><code>\u0000MDCB1\u0000\n</code></pre>');
            expect(out).toContain('<pre><code>SECOND\n</code></pre>');
            expect(nulCount(out)).toHaveLength(2);
        });

        // ── TD-46 契约锁：未登记字面量原样保留（alternation 单 pass 重构的
        //    风险路径——split/join 只替换精确子串，alternation 不得误匹配
        //    未登记的同形字面量；基线（split/join）与重构后（alternation）必须同绿）──

        it('用户内容含未登记字面量 \u0000MDCB99\u0000 → 原样保留，已登记占位符正常还原（TD-46 契约锁）', () => {
            const out = renderMarkdown(`\u0000MDCB99\u0000\n\n\`\`\`\ncode\n\`\`\``);
            expect(out).toContain('<pre><code>code\n</code></pre>');
            // 渲染器取号只到 MDCB0，\u0000MDCB99\u0000 不在 Map 中 → 不得被替换
            expect(out).toContain('\u0000MDCB99\u0000');
            expect(nulCount(out)).toHaveLength(2);
        });

        it('未登记字面量（\u0000MDCB99\u0000/\u0000MDCB5\u0000）+ 三块 → 已登记全部还原、未登记原样保留（TD-46）', () => {
            const out = renderMarkdown(
                `\u0000MDCB99\u0000 与 \u0000MDCB5\u0000\n\n\`\`\`\nFIRST\n\`\`\`\n\n\`\`\`\nSECOND\n\`\`\`\n\n\`\`\`\nTHIRD\n\`\`\``
            );
            expect(out).toContain('<pre><code>FIRST\n</code></pre>');
            expect(out).toContain('<pre><code>SECOND\n</code></pre>');
            expect(out).toContain('<pre><code>THIRD\n</code></pre>');
            expect(out).toContain('\u0000MDCB99\u0000');
            expect(out).toContain('\u0000MDCB5\u0000');
            // 未登记字面量 2 个 × 各 2 个 NUL = 4；渲染器占位符（MDCB0/1/2）全部还原
            expect(nulCount(out)).toHaveLength(4);
        });

        it('八块大文本（单块内容 2000 字符）→ 全还原、每块恰一份、无 NUL 泄漏（TD-46 规模 Falsify）', () => {
            const longContent = 'x'.repeat(2000);
            const blocks = [longContent, 'B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7'];
            const input = blocks.map((c) => `\`\`\`\n${c}\n\`\`\``).join('\n\n');
            const out = renderMarkdown(input);
            for (const c of blocks) {
                const needle = `<pre><code>${c}\n</code></pre>`;
                expect(out.split(needle).length - 1).toBe(1); // 每块恰一份：无双份、无丢失
            }
            expect(nulCount(out)).toHaveLength(0);
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

        it('scheme 内嵌/前导控制字符变体被中和为纯文本（TD-28，XSS 边界）', () => {
            expect(renderMarkdown('[x](java\tscript:alert(1))')).not.toContain('<a');
            expect(renderMarkdown('[x](java\nscript:foo)')).toBe('x');
            expect(renderMarkdown('[x](java\rscript:foo)')).toBe('x');
            expect(renderMarkdown('[x](\x00javascript:foo)')).toBe('x');
            expect(renderMarkdown('[x](java\tscript:foo)')).not.toContain('<a');
        });

        it('控制字符 Falsify：混合大小写/多组合/正常位置/纯控制字符不崩溃', () => {
            expect(renderMarkdown('[x](JaVa\tScRiPt:foo)')).toBe('x');
            expect(renderMarkdown('[x](j\ta\nv\ras\tr\nipt:foo)')).toBe('x');
            expect(renderMarkdown('[x](https://a\tb.com)')).toContain('href="https://a\tb.com"');
            expect(() => renderMarkdown('[x](\t)')).not.toThrow();
            expect(() => renderMarkdown('[x](\x00)')).not.toThrow();
        });
    });

    describe('属性注入面（TD-42）', () => {
        it('双引号击穿 href 属性被中和为纯文本（防复发断言）', () => {
            // 票面防复发断言：注入存活时输出含 onmouseover
            expect(renderMarkdown('[x](" onmouseover="alert(1))')).not.toContain('onmouseover');
            // 中和为纯文本（尾部 ) 为链接正则首个 ) 截断后的遗留字面量，与 javascript:alert(1) 变体同语义）
            expect(renderMarkdown('[x](" onmouseover="alert(1))')).toBe('x)');
            // 多属性注入同面（onclick）
            expect(renderMarkdown('[x](" onclick="alert(1))')).toBe('x)');
        });

        it('单引号变体同样被中和（URL 安全性判定不依赖属性引号风格）', () => {
            expect(renderMarkdown("[x](' onmouseover='alert(1))")).toBe('x)');
            expect(renderMarkdown("[x](' onmouseover='alert(1))")).not.toContain('onmouseover');
        });

        it('引号位于 URL 中间/结尾同样拒绝', () => {
            expect(renderMarkdown('[x](https://a.com/pa"th)')).toBe('x');
            expect(renderMarkdown("[x](https://a.com/x')")).toBe('x');
        });

        it('正常含单引号 URL（RFC 3986 sub-delims）被中和为纯文本（裁决文档化）', () => {
            expect(renderMarkdown("[b](mailto:foo'bar@x.com)")).toBe('b');
        });

        it('实体编码 &quot; 变体被 escapeHtml 双转义为惰性文本（不产生属性）', () => {
            const out = renderMarkdown('[x](&quot; onmouseover=&quot;alert(1))');
            expect(out).toContain('&amp;quot; onmouseover=&amp;quot;');
            expect(out).not.toContain('onmouseover="');
            const doc = new DOMParser().parseFromString(`<body>${out}</body>`, 'text/html');
            expect(doc.querySelector('a').hasAttribute('onmouseover')).toBe(false);
        });

        it('反引号变体不产生属性（href 值内惰性文本）', () => {
            const out = renderMarkdown('[x](` onmouseover=`alert(1))');
            expect(out).toContain('<a');
            const doc = new DOMParser().parseFromString(`<body>${out}</body>`, 'text/html');
            expect(doc.querySelector('a').hasAttribute('onmouseover')).toBe(false);
        });

        it('%22 百分号编码引号变体不产生事件属性（TD-45 回归网）', () => {
            const out = renderMarkdown('[x](%22 onmouseover=%22alert(1))');
            // %22 非属性边界字符：链接存活但 onmouseover 只能作为 href 值内惰性文本
            expect(out).toContain('<a');
            const doc = new DOMParser().parseFromString(`<body>${out}</body>`, 'text/html');
            for (const el of doc.body.querySelectorAll('*')) {
                expect(el.hasAttribute('onmouseover')).toBe(false);
            }
        });

        it('&QUOT; 大写实体变体被 escapeHtml 双转义为惰性文本（TD-45 回归网）', () => {
            const out = renderMarkdown('[x](&QUOT; onmouseover=&QUOT;alert(1))');
            expect(out).toContain('&amp;QUOT;');
            const doc = new DOMParser().parseFromString(`<body>${out}</body>`, 'text/html');
            for (const el of doc.body.querySelectorAll('*')) {
                expect(el.hasAttribute('onmouseover')).toBe(false);
            }
        });

        it('&#34; 十进制实体变体被 escapeHtml 双转义为惰性文本（TD-45 回归网）', () => {
            const out = renderMarkdown('[x](&#34; onmouseover=&#34;alert(1))');
            expect(out).toContain('&amp;#34;');
            const doc = new DOMParser().parseFromString(`<body>${out}</body>`, 'text/html');
            for (const el of doc.body.querySelectorAll('*')) {
                expect(el.hasAttribute('onmouseover')).toBe(false);
            }
        });

        it('全角引号（U+201C/U+201D）不是属性边界字符，不产生事件属性（TD-45 回归网）', () => {
            const out = renderMarkdown('[x](\u201C onmouseover=\u201Dalert(1))');
            expect(out).toContain('<a');
            const doc = new DOMParser().parseFromString(`<body>${out}</body>`, 'text/html');
            for (const el of doc.body.querySelectorAll('*')) {
                expect(el.hasAttribute('onmouseover')).toBe(false);
            }
        });

        it('反引号 + javascript: 组合变体不产生事件属性、href 不以可执行 scheme 开头（TD-45 回归网）', () => {
            const out = renderMarkdown('[x](` onmouseover=`javascript:alert(1))');
            expect(out).toContain('<a');
            const doc = new DOMParser().parseFromString(`<body>${out}</body>`, 'text/html');
            for (const el of doc.body.querySelectorAll('*')) {
                expect(el.hasAttribute('onmouseover')).toBe(false);
            }
            // href 值以反引号开头 → 浏览器按相对 URL 处理，javascript: 不处于 scheme 位置
            expect(doc.querySelector('a').getAttribute('href')).not.toMatch(/^javascript:/i);
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
