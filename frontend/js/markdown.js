/**
 * Conver System — 轻量 Markdown 渲染模块
 *
 * 职责：renderMarkdown 由 utils.js 迁出（FE-3），独立承载「文本 → HTML 字符串」
 *       的渲染映射；内部复用 utils.js 的 escapeHtml 保证先转义再解析（防 XSS）。
 *
 * 协议表面（__all__）：renderMarkdown。
 */

import { escapeHtml } from './utils.js';

// 允许的 URL scheme 白名单（Falsify 硬化：javascript: / data: / vbscript: 等注入 scheme 一律中和）
const SAFE_URL_SCHEMES = /^(https?|mailto|tel)$/i;

/**
 * 校验链接 URL 的 scheme（防 javascript: 等 XSS 注入）
 *
 * WHATWG URL 解析器在解析 scheme 前会剥离全部 ASCII tab/换行，并剔除首尾 C0 控制字符，
 * 因此 `java\tscript:foo` / `\x00javascript:foo` 等变体在浏览器中仍解析为 javascript:。
 * 这里先在 scheme 匹配前剔除 [\u0000-\u0020]（C0 控制字符 + 空格）再比对白名单，
 * 防止控制字符绕过；匹配通过时仍返回原始（trim 后）URL，正常 URL 逐字节不变。
 *
 * TD-42（属性注入面）：href 属性以双引号包裹，URL 内任何裸引号（" 或 '）均可击穿
 * 属性边界注入事件属性（`[x](" onmouseover="alert(1))` 实测产出 onmouseover 属性）。
 * escapeHtml 不转义引号（textContent→innerHTML 引号原样通过），故在 trim 后直接拒绝
 * 含引号 URL（返回 null → 调用方中和为纯文本）。单引号实测不击穿双引号属性边界
 * （jsdom DOM 解析验证），但 URL 安全性判定不应依赖渲染模板的属性引号风格
 * （防未来模板单引号化后静默复发），故一并拒绝；代价：RFC 3986 sub-delims 允许的
 * 含 ' URL（如 mailto:foo'bar@x.com）被中和为纯文本，本仓库无真实用例，可接受。
 *
 * @param {string} url - 原始链接地址（已 HTML 转义，可能含首尾空白）
 * @returns {string|null} 去首尾空白后的安全 URL；含引号或 scheme 不在白名单时返回 null（调用方渲染为纯文本）
 */
function sanitizeUrl(url) {
    const trimmed = url.trim();
    if (trimmed.includes('"') || trimmed.includes("'")) return null;
    const scheme = trimmed.replace(/[\u0000-\u0020]/g, '').match(/^([a-z][a-z0-9+.-]*):/i);
    if (scheme && !SAFE_URL_SCHEMES.test(scheme[1])) return null;
    return trimmed;
}

/**
 * 生成与当前内容碰撞免疫的代码块占位符（TD-38 原子化；TD-47 碰撞作用域扩展）
 *
 * token 形如 \u0000MDCB<序号>\u0000，碰撞免疫由两层保证：
 * 1) NUL 前缀：用户内容中出现裸 NUL 占位符同形文本的概率极低（jsdom
 *    序列化实测保留 NUL、不替换为 U+FFFD——TD-43 的 U+FFFD 结论仅适用于
 *    解析侧；真实浏览器序列化侧替换 NUL，两种环境均由碰撞循环兜底）；
 * 2) 碰撞循环：候选 token 已存在于当前 HTML 时递增序号重试，实测覆盖
 *    jsdom 保留 NUL 的场景（见 TD-38 自审）。
 * 占位符不含 ` * [ ] ( ) 等行内标记字符、不匹配行首列表语法，行内 pass
 * 与列表 pass 均无法触及。
 *
 * 碰撞作用域（TD-47 扩展）：仅查提取前原始串的完整形态不够——用户半形
 * 字面量（\u0000MDCBn 缺尾 NUL / MDCBn\u0000 缺首 NUL）紧邻代码块时，
 * 提取替换后经占位符边界拼接出新完整 token 形态，还原时被误匹配（用户
 * 内容替换成块 HTML、块双份）。故每个候选序号同时检查三种形态，任一
 * 存在即跳过该序号：
 *   a) 完整形态 \u0000MDCBn\u0000（原有检查）；
 *   b) 左半形 \u0000MDCBn——「用户左半形 + 占位符首 NUL」拼接方向，
 *      命中则 Map 中无 n，还原不误匹配；
 *   c) 右半形 MDCBn\u0000——「占位符尾 NUL + 用户右半形」拼接方向，
 *      同上（当前单 pass 非重叠还原下右半形拼接被重叠遮蔽、不可复现，
 *      属防御性对称检查，防还原实现/占位符形态未来变化后复发）。
 * 数字边界（如用户文本含 \u0000MDCB01\u0000）：候选 0 左半形 \u0000MDCB0
 * 命中（前缀）→ 跳过 MDCB0，MDCB1 三种形态均不命中 → 安全占用（拼接
 * 产物与 \u0000MDCB1\u0000 不同，不误匹配）。正常文本（无任何 MDCB 形
 * 文本）三种检查均不命中，序号分配与原实现逐号一致。防复发断言见
 * tests/markdown.test.js「占位符拼接防护（TD-47）」describe 块。
 *
 * 取号单一职责（期末 Falsify 阻断修复）：碰撞循环内部可能消耗多个序号
 * （如用户内容占用 MDCB0/MDCB1 时，一次取号实际消耗 0/1/2 三个序号），
 * 故返回值携带 nextId（取号后下一个可用序号），调用方必须回写
 * tokenId = nextId 而非自增——否则内外计数器失同步，后续代码块会复用已
 * 占用占位符 → Map.set 覆盖首条记录 → 还原循环把多处占位符替换为同一块
 * HTML（首块内容丢失、尾块双份）。防复发断言见 tests/markdown.test.js
 * 「占位符碰撞免疫」describe 块。
 *
 * @param {string} html - 当前（已转义）HTML 字符串，用于碰撞检测
 * @param {number} tokenId - 本次取号起始序号（调用方维护）
 * @returns {{ token: string, nextId: number }} token: 唯一占位符；nextId: 本次取号消耗后的下一可用序号（调用方回写）
 */
function createCodeBlockToken(html, tokenId) {
    let token;
    do {
        token = `\u0000MDCB${tokenId}\u0000`;
        tokenId++;
    } while (
        html.includes(token) ||                        // 完整形态（原有）
        html.includes(`\u0000MDCB${tokenId - 1}`) ||   // 左半形：半形+占位符首NUL 拼接方向
        html.includes(`MDCB${tokenId - 1}\u0000`)      // 右半形：占位符尾NUL+半形 拼接方向
    );
    return { token, nextId: tokenId };
}

/**
 * 转义正则元字符（TD-46 防御性辅助）
 *
 * 还原占位符需把 Map 中已登记的 token 拼为 alternation 正则。当前 token 形态
 * （\u0000MDCB<序号>\u0000）仅含 NUL/字母/数字：NUL 在 JS 正则中为字面字符
 * （正则字面量 /\u0000/ 与 RegExp 构造器均可直接匹配，无需转义），数字字母
 * 均非元字符——本函数对当前形态是恒等变换；但为防御未来 token 形态变化
 * （如引入 . * ( ) 等元字符），统一经此函数转义后再拼装。
 *
 * @param {string} str - 需要嵌入正则的字符串
 * @returns {string} 元字符转义后的字符串（可安全用于 RegExp 构造器）
 */
function escapeRegExp(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * 轻量 Markdown 渲染（安全 — 先转义再解析标记）
 * 支持：代码块、内联代码、粗体、斜体、链接、无序/有序列表
 * @param {string} text - 原始文本
 * @returns {string} 渲染后的 HTML
 */
export function renderMarkdown(text) {
    if (typeof text !== 'string' || !text) return '';

    // 先转义 HTML，再解析 Markdown 标记
    let html = escapeHtml(text);

    // ── 代码块 (```...```) — TD-38 占位符原子化 ──
    // 先提取代码块为唯一占位符（内容 + 语言登记入 map），行内标记 pass
    // （内联代码/粗体/斜体/链接/列表）全部在占位符之外进行，全部处理完毕
    // 后统一还原为 <pre><code> HTML——块内 **x** / [x](y) / `x` 等标记
    // 不再被误渲染（真实交互缺陷修复），块内容也不受列表 pass 行级拆解影响。
    const codeBlocks = new Map();
    let tokenId = 0;
    html = html.replace(/```(\w*)\n?([\s\S]*?)```/g, (match, lang, code) => {
        // 取号在 createCodeBlockToken 内完成（碰撞循环可能消耗多个序号），
        // 计数器同步以返回值 nextId 回写为准，此处不得再自增（TD-38 阻断修复）
        const { token, nextId } = createCodeBlockToken(html, tokenId);
        tokenId = nextId;
        const langClass = lang ? ` class="lang-${escapeHtml(lang)}"` : '';
        codeBlocks.set(token, `<pre><code${langClass}>${code}</code></pre>`);
        return token;
    });

    // ── 内联代码 `code` ──
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

    // ── 粗体 **text** ──
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

    // ── 斜体 *text* ──
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');

    // ── 链接 [text](url) ──
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, url) => {
        const href = sanitizeUrl(url);
        if (href === null) return label;
        return `<a href="${href}" target="_blank" rel="noopener noreferrer">${label}</a>`;
    });

    // ── 列表（行级处理） — 将行首的 - / * / 1. 转为 HTML 列表 ──
    const lines = html.split('\n');
    const result = [];
    let inUl = false;
    let inOl = false;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // 处理水平分割线
        if (/^[-*_]{3,}$/.test(line.trim())) {
            if (inUl) { result.push('</ul>'); inUl = false; }
            if (inOl) { result.push('</ol>'); inOl = false; }
            result.push('<hr>');
            continue;
        }

        // 无序列表 - 或 *
        const ulMatch = line.match(/^(\s*)[*\-]\s+(.*)$/);
        if (ulMatch) {
            if (inOl) { result.push('</ol>'); inOl = false; }
            if (!inUl) { result.push('<ul>'); inUl = true; }
            result.push(`<li>${ulMatch[2]}</li>`);
            continue;
        }

        // 有序列表 1. 2.
        const olMatch = line.match(/^(\s*)\d+\.\s+(.*)$/);
        if (olMatch) {
            if (inUl) { result.push('</ul>'); inUl = false; }
            if (!inOl) { result.push('<ol>'); inOl = true; }
            result.push(`<li>${olMatch[2]}</li>`);
            continue;
        }

        // 关闭打开的列表
        if (inUl) { result.push('</ul>'); inUl = false; }
        if (inOl) { result.push('</ol>'); inOl = false; }

        // 空行 → 段落分隔
        if (line.trim() === '') {
            result.push('<p></p>');
        } else {
            result.push(line);
        }
    }

    if (inUl) result.push('</ul>');
    if (inOl) result.push('</ol>');

    html = result.join('\n');

    // ── 还原代码块（列表 pass 之后、返回之前完成，输出不残留占位符形态）──
    // TD-46 性能重构：原实现逐块 split/join（每块一次全文扫描 → O(块数 × 文本
    // 长度)，多块大文本二次方级）；改为 alternation 单 pass 正则替换，一次扫描
    // O(N + Σtoken 长度)。alternation 仅由 Map 中已登记的 token 字面量拼装，
    // 用户内容中未登记的同形文本（如 \u0000MDCB99\u0000）不在匹配面内、原样
    // 保留——与 split/join 的精确子串替换契约等价，防误匹配断言见
    // tests/markdown.test.js「占位符碰撞免疫」describe 块 TD-46 契约锁用例。
    // 空 Map 时跳过构造：空 pattern 的 /g 正则会命中每个空位并回调，必须避免。
    if (codeBlocks.size > 0) {
        const tokenPattern = new RegExp(
            [...codeBlocks.keys()].map(escapeRegExp).join('|'),
            'g'
        );
        html = html.replace(tokenPattern, (token) => codeBlocks.get(token));
    }

    return html;
}
