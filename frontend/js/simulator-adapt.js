/**
 * Conver System — 模拟器适配分析共享深模块（T-01，工单 04 复用）
 *
 * 职责：新游戏接入覆盖层把关的分析逻辑 —— 覆盖层映射记录解析
 *   （parseCoverageRecords）/ 游戏 HTML 三面提取（extractGameClasses：
 *   日志条目类名 / CSS 变量体系 / 显式字号声明）/ 覆盖比对
 *   （compareCoverage：输出「未覆盖清单」）。CLI 消费者
 *   scripts/check-simulator-css.mjs 与工单 04 导入后的未覆盖提示共用
 *   本模块 —— 语法与判定规则一经定版即为契约，改动必须同步两处消费方
 *   及契约测试（frontend/tests/simulator-adapt.test.js）。
 *
 * 覆盖判定模型（定版契约）：
 *   - classes：游戏使用的覆盖层已知日志条目类（ENTRY_CLASSES），须 ∈
 *     覆盖层规则选择器类名集 ∪ 该游戏映射记录 classes 列；
 *   - vars：游戏出现的覆盖层变量覆盖体系成员（VARS_FAMILY —— 覆盖层
 *     实际声明的变量 ∪ 明确记录「刻意不覆盖」的决策面 --sub），须 ∈
 *     覆盖层变量声明集 ∪ 记录 vars 列（豁免项带 `!`）；
 *   - fonts：游戏显式字号声明（< FONT_SCAN_THRESHOLD_PX 且选择器含日志
 *     体系类），须被覆盖层字号规则级联匹配 —— 选择器结构匹配（覆盖层
 *     规则选择器为游戏选择器的保序子序列且末位对齐，即祖先可多、元素
 *     本体一致）+ 规则带 !important 或特异性 ≥ 游戏声明；或列入记录
 *     fonts 豁免清单（`选择器:字号!`，源文件核对的刻意保留）。
 *   - 记录缺失（游戏不在 `# sim-pc:` 映射段）= 未接入核对，整体报出
 *     —— 强制新游戏接入先补映射记录（本工单补的适配盲区强制校验）。
 *
 * 映射记录语法（simulator-pc.css 末尾注释块内，机器可解析）：
 *   `# sim-pc:` 标记行 + 每游戏一行：
 *   <游戏名> | classes=<类名,...> | vars=<--变量,...> | fonts=<选择器:字号,...>
 *   豁免项后缀 `!`（vars=--sub! / fonts=.msg code:13px!）；字段可省略；
 *   畸形行跳过（容错）。游戏名与 frontend/simulators/<游戏名>.html
 *   文件干名一致。
 *
 * 硬约束（Node ESM 真实消费者兼容 — 冒烟脚本直 import 先例）：模块顶层
 *   零 DOM / 零浏览器 API / 零副作用，仅语言内建正则与字符串操作；
 *   对游戏内容只做纯文本解析，无 eval / 无任意代码执行面。
 *
 * 协议表面（__all__）：ENTRY_CLASSES / VARS_FAMILY /
 *   FONT_SCAN_THRESHOLD_PX / parseCoverageRecords / extractGameClasses /
 *   compareCoverage。
 */

// ══════════════════════════════════════════════════
// 常量（覆盖层域事实 — 单一来源）
// ══════════════════════════════════════════════════

/** 覆盖层日志条目类（simulator-pc.css 分区 1 承诺覆盖的 5 个条目类） */
export const ENTRY_CLASSES = ['log-entry', 'chat-msg', 'msg', 'ency-entry', 'mem-entry'];

/** 覆盖层内层正文类（分区 1 F2 规则承诺的正文面，参与字号扫描范围判定） */
export const INNER_CLASSES = ['m-text', 'm-bubble', 'bubble', 'wrap', 'm-main'];

/**
 * 覆盖层变量覆盖体系 —— 分区 2 A 类声明 + 分区 3 B 类映射 + 明确记录的
 * 决策面 --sub（分区 7 注释：刻意不覆盖，全局注入会污染无 --sub 的游戏）。
 * 游戏出现本体系成员即纳入变量面核对。
 */
export const VARS_FAMILY = [
    '--t2', '--t3', '--bg-deep', '--border',
    '--text-secondary', '--text-muted',
    '--muted', '--fs-s', '--fs-m', '--fs-l', '--tx2', '--tx3',
    '--sub',
];

/** 显式字号扫描阈值（px）：低于该值的日志面字号纳入核对（元数据面由记录豁免在案） */
export const FONT_SCAN_THRESHOLD_PX = 14;

/** 映射记录标记行（simulator-pc.css 中 `# sim-pc:` 单独成行） */
export const RECORD_MARKER = '# sim-pc:';

/** 日志体系类全集（条目 + 内层，用于字号扫描范围判定） */
const LOG_FAMILY_CLASSES = [...ENTRY_CLASSES, ...INNER_CLASSES];

const VARS_FAMILY_RE = new RegExp(`--(?:${VARS_FAMILY.map((v) => v.slice(2)).join('|')})(?![a-z0-9-])`, 'g');

/** 注释剥离（不修改字符语义，仅用于规则解析） */
function stripCssComments(cssText) {
    return cssText.replace(/\/\*[\s\S]*?\*\//g, '');
}

/**
 * 解析 CSS 选择器为「复合选择器链」。
 *
 * 每个复合选择器（空格分隔的一节）解析为 {ids, cls, tags}；伪类
 * （:hover / :not(...)）与伪元素（::before）剥离 —— 伪元素选择器由
 * 调用方预先跳过。仅类名参与结构匹配（覆盖层规则全部为类/标签/伪类
 * 形态）。
 *
 * @param {string} selector - CSS 选择器文本（单条，不含逗号）
 * @returns {Array<{ids: string[], cls: string[], tags: string[]}>}
 *   复合选择器链（空输入返回空数组）
 */
function parseSelectorChain(selector) {
    const chain = [];
    for (const part of selector.trim().split(/\s+/)) {
        if (!part) continue;
        const clean = part.replace(/::?[a-zA-Z-]+(\([^)]*\))?/g, '');
        const comp = { ids: [], cls: [], tags: [] };
        const re = /([.#]?)([a-zA-Z_][a-zA-Z0-9_-]*)/g;
        let m;
        while ((m = re.exec(clean))) {
            if (m[1] === '.') comp.cls.push(m[2]);
            else if (m[1] === '#') comp.ids.push(m[2]);
            else comp.tags.push(m[2]);
        }
        chain.push(comp);
    }
    return chain;
}

/** 复合选择器 P 覆盖 S：P 的类/id/标签全部出现在 S 中 */
function subsumes(pa, sb) {
    return pa.cls.every((c) => sb.cls.includes(c))
        && pa.ids.every((c) => sb.ids.includes(c))
        && pa.tags.every((c) => sb.tags.includes(c));
}

/**
 * 覆盖层规则选择器 P 是否匹配游戏选择器 S 的全部元素（结构匹配）。
 *
 * CSS 后代语义：P 的末位复合选择器必须命中 S 末位（被修饰元素本体），
 * P 的其余复合选择器按保序子序列在 S 的祖先链中回溯（游戏选择器可带
 * 额外祖先，如 `#log .msg .m-text` 可被 `.msg .m-text` 匹配）。
 *
 * @param {Array} pChain - 覆盖层规则选择器链（parseSelectorChain 输出）
 * @param {Array} sChain - 游戏声明选择器链
 * @returns {boolean} P 匹配 S 的全部元素为 true
 */
function selectorMatches(pChain, sChain) {
    if (!pChain.length || !sChain.length) return false;
    if (pChain.length > sChain.length) return false;
    if (!subsumes(pChain[pChain.length - 1], sChain[sChain.length - 1])) return false;
    let i = sChain.length - 2;
    let j = pChain.length - 2;
    while (j >= 0 && i >= 0) {
        if (subsumes(pChain[j], sChain[i])) j--;
        i--;
    }
    return j < 0;
}

/** 选择器链特异性 [id, class, tag] 计数 */
function specificityOf(chain) {
    let ids = 0;
    let cls = 0;
    let tags = 0;
    for (const comp of chain) {
        ids += comp.ids.length;
        cls += comp.cls.length;
        tags += comp.tags.length;
    }
    return [ids, cls, tags];
}

/** 特异性 a ≥ b（数组字典序比较） */
function specificityGte(a, b) {
    return a[0] > b[0] || (a[0] === b[0] && (a[1] > b[1] || (a[1] === b[1] && a[2] >= b[2])));
}

/** 空覆盖集 */
function emptyCovered() {
    return { classes: [], vars: [], fontRules: [] };
}

/**
 * 从覆盖层 CSS 解析「已覆盖选择器集合」+ 映射记录。
 *
 * covered（由实际 CSS 规则推导，契约测试断言记录与其一致）：
 *   - covered.classes：全部规则选择器中的类名（含嵌套 @media）
 *   - covered.vars：全部规则中声明的 CSS 变量名（--x:）
 *   - covered.fontRules：全部含 font-size 的规则
 *     [{selector, size, imp, chain}]（selector 原文、字号、!important、
 *     选择器链）
 * games（`# sim-pc:` 标记行后的每游戏一行）：
 *   [{name, classes: string[], vars: [{name, exempt}],
 *     fonts: [{selector, size, exempt}]}] —— 豁免项 exempt=true
 *   对应 `!` 后缀（源文件核对的刻意保留，记录在案防误报）。
 *
 * @param {string} cssText - 覆盖层 CSS 全文
 * @returns {{games: Array, covered: {classes: string[], vars: string[],
 *   fontRules: Array<{selector: string, size: string, imp: boolean,
 *   chain: Array}>}}} 解析结果（畸形行/畸形选择器跳过，不抛异常）
 */
export function parseCoverageRecords(cssText) {
    if (typeof cssText !== 'string' || cssText === '') {
        return { games: [], covered: emptyCovered() };
    }
    const stripped = stripCssComments(cssText);
    const classes = new Set();
    const vars = new Set();
    const fontRules = [];
    for (const m of stripped.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const decls = m[2];
        for (const dm of decls.matchAll(/--([a-zA-Z0-9_-]+)\s*:/g)) vars.add(`--${dm[1]}`);
        const fsMatch = decls.match(/font-size\s*:\s*([^;}]+)/i);
        const size = fsMatch ? fsMatch[1].trim() : null;
        for (const part of m[1].split(',')) {
            const selector = part.trim();
            if (!selector || selector.startsWith('@') || selector.includes('::')) continue;
            const chain = parseSelectorChain(selector);
            if (!chain.length) continue;
            for (const comp of chain) for (const c of comp.cls) classes.add(c);
            if (size) {
                fontRules.push({
                    selector,
                    size: size.replace(/\s*!important\s*$/i, ''),
                    imp: /!important\s*$/i.test(size),
                    chain,
                });
            }
        }
    }

    const games = [];
    const lines = cssText.split(/\r?\n/);
    let inRecords = false;
    for (const raw of lines) {
        const line = raw.trim();
        if (!inRecords) {
            if (line === RECORD_MARKER) inRecords = true;
            continue;
        }
        const sep = line.indexOf('|');
        if (sep <= 0) continue; // 无管道分隔 → 非记录行（含注释收尾 `*/`）
        const name = line.slice(0, sep).trim();
        if (!name) continue;
        const game = { name, classes: [], vars: [], fonts: [] };
        for (const token of line.slice(sep + 1).split('|')) {
            const t = token.trim();
            const kv = t.match(/^(classes|vars|fonts)=(.*)$/);
            if (!kv) continue;
            const value = kv[2].trim();
            if (!value) continue;
            if (kv[1] === 'classes') {
                for (const c of value.split(',')) {
                    const item = c.trim();
                    if (/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(item)) game.classes.push(item);
                }
            } else if (kv[1] === 'vars') {
                for (const c of value.split(',')) {
                    const m2 = c.trim().match(/^(--[a-z0-9-]+)(!)?$/);
                    if (m2) game.vars.push({ name: m2[1], exempt: Boolean(m2[2]) });
                }
            } else {
                for (const c of value.split(',')) {
                    const m2 = c.trim().match(/^(.+):([0-9.]+px)(!?)$/);
                    if (m2) game.fonts.push({ selector: m2[1].trim(), size: m2[2], exempt: m2[3] === '!' });
                }
            }
        }
        if (game.classes.length || game.vars.length || game.fonts.length) games.push(game);
    }
    return {
        games,
        covered: {
            classes: [...classes].sort(),
            vars: [...vars].sort(),
            fontRules,
        },
    };
}

/** 从 style 块提取游戏 CSS（含 @media 嵌套内容），注释剥离 */
function extractGameCss(htmlText) {
    const blocks = [];
    const re = /<style[^>]*>([\s\S]*?)<\/style>/gi;
    let m;
    while ((m = re.exec(htmlText))) blocks.push(m[1]);
    return stripCssComments(blocks.join('\n'));
}

/** 在给定文本的引号字符串上下文中收集日志条目类（class 属性 / className / classList） */
function collectEntryClassesInQuoted(text, out) {
    for (const m of text.matchAll(/class(?:Name)?\s*=\s*["']([^"']*)["']|classList\.(?:add|remove)\(\s*["']([^"']*)["']/g)) {
        const value = m[1] ?? m[2];
        for (const token of value.split(/\s+/)) {
            if (ENTRY_CLASSES.includes(token)) out.add(token);
        }
    }
}

/**
 * 从游戏 HTML 提取三类适配面（零 DOM，纯正则）。
 *
 *   - classes：日志条目类使用面 —— 来源：CSS 选择器 / class 属性 /
 *     className 赋值 / classList.add|remove 字面量；
 *   - vars：覆盖层变量覆盖体系成员的出现面（定义 `--x:` 或引用
 *     `var(--x)`，全 HTML 文本扫描）；
 *   - fonts：游戏显式字号声明 —— <style> 块中 font-size < 阈值且选择器
 *     含日志体系类（条目类 + 内层正文类）的 (selector, size, important)
 *     列表；var() 字号跳过（走变量面）、伪元素选择器跳过、注释不解析、
 *     同选择器同字号同重要级去重。带 !important 的声明单独标记 ——
 *     覆盖层契约三前提（同特异性 + 后加载序 + 游戏不带 !important）
 *     外，必报未覆盖。
 *
 * @param {string} htmlText - 游戏 HTML 全文
 * @returns {{classes: string[], vars: string[],
 *   fonts: Array<{selector: string, size: string}>}} 提取结果（空输入
 *   返回三面空数组）
 */
export function extractGameClasses(htmlText) {
    if (typeof htmlText !== 'string' || htmlText === '') {
        return { classes: [], vars: [], fonts: [] };
    }
    const cssText = extractGameCss(htmlText);

    const classes = new Set();
    const entryRe = new RegExp(`\\.(${ENTRY_CLASSES.join('|')})(?![a-zA-Z0-9_-])`, 'g');
    for (const m of cssText.matchAll(entryRe)) classes.add(m[1]);
    collectEntryClassesInQuoted(htmlText, classes);

    const vars = new Set();
    for (const m of htmlText.matchAll(VARS_FAMILY_RE)) vars.add(`--${m[0].slice(2)}`);

    const fonts = [];
    const seen = new Set();
    for (const m of cssText.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const fsMatch = m[2].match(/font-size\s*:\s*([^;}]+)/i);
        if (!fsMatch) continue;
        const raw = fsMatch[1].trim();
        const important = /!important\s*$/i.test(raw);
        const size = raw.replace(/\s*!important\s*$/i, '').trim();
        if (size.startsWith('var(')) continue;
        const px = parseFloat(size);
        if (!/^\d+(\.\d+)?px$/.test(size) || !Number.isFinite(px) || px >= FONT_SCAN_THRESHOLD_PX) continue;
        for (const part of m[1].split(',')) {
            const selector = part.trim();
            if (!selector || selector.startsWith('@') || selector.includes('::')) continue;
            const chain = parseSelectorChain(selector);
            if (!chain.length) continue;
            const flat = chain.flatMap((c) => c.cls);
            if (!flat.some((c) => LOG_FAMILY_CLASSES.includes(c))) continue;
            const key = `${selector}\u0000${size}\u0000${important}`;
            if (seen.has(key)) continue;
            seen.add(key);
            fonts.push({ selector, size, important });
        }
    }

    return {
        classes: [...classes].sort(),
        vars: [...vars].sort(),
        fonts,
    };
}

/**
 * 覆盖比对：游戏三面提取结果 vs 覆盖层已覆盖集合 + 映射记录。
 *
 * 判定（模型见模块 docstring）：缺覆盖即输出未覆盖项；映射记录缺失
 * （gameName 不在 games 中）输出 kind:'record' 项 —— 强制新游戏接入
 * 先补记录。输出项形状：
 *   {kind: 'record', item: 游戏名}
 *   {kind: 'class',  item: 类名}
 *   {kind: 'var',    item: 变量名}
 *   {kind: 'font',   item: 选择器, size: 字号, important?: true}
 *     （important=true：声明带 !important，覆盖层契约前提外必报）
 *
 * @param {{classes: string[], vars: string[], fonts: Array}} game -
 *   extractGameClasses 输出
 * @param {string} gameName - 游戏名（映射记录键，与 HTML 文件干名一致）
 * @param {{games: Array, covered: Object}} coverage -
 *   parseCoverageRecords 输出
 * @returns {Array<{kind: string, item: string, size?: string,
 *   important?: boolean}>} 未覆盖清单（全绿返回空数组）
 */
export function compareCoverage(game, gameName, coverage) {
    // 空输入防护（波末审核 F3）：消费方可能传入 null/undefined/畸形对象
    // （如导入流程经部分失败路径进入）—— 一律按「无信息」归一化，不抛
    // TypeError：game 缺失 → 仅报记录缺失；coverage 缺失/畸形 → 按空
    // 覆盖层判定（与 parseCoverageRecords('') 输出同语义）
    const { classes = [], vars = [], fonts = [] } = game ?? {};
    const cov = coverage && typeof coverage === 'object'
        ? coverage
        : { games: [], covered: emptyCovered() };
    const covered = cov.covered && typeof cov.covered === 'object'
        ? cov.covered
        : emptyCovered();
    const items = [];
    const record = Array.isArray(cov.games) ? cov.games.find((g) => g.name === gameName) : undefined;
    if (!record) {
        items.push({ kind: 'record', item: gameName });
    }
    const recordClasses = record ? record.classes : [];
    for (const cls of classes) {
        if (!Array.isArray(covered.classes) || !covered.classes.includes(cls)) {
            if (!recordClasses.includes(cls)) {
                items.push({ kind: 'class', item: cls });
            }
        }
    }
    const recordVars = record ? record.vars : [];
    for (const v of vars) {
        if (!Array.isArray(covered.vars) || !covered.vars.includes(v)) {
            if (!recordVars.some((e) => e.name === v)) {
                items.push({ kind: 'var', item: v });
            }
        }
    }
    const recordFonts = record ? record.fonts : [];
    for (const f of fonts) {
        if (recordFonts.some((e) => e.selector === f.selector)) continue;
        // 游戏声明带 !important = 覆盖层契约三前提外（同特异性 + 后加载序 +
        // 游戏不带 !important），覆盖层无法保证胜出 → 必报
        if (f.important) {
            items.push({ kind: 'font', item: f.selector, size: f.size, important: true });
            continue;
        }
        const coveredByRule = Array.isArray(covered.fontRules) && covered.fontRules.some((rule) =>
            selectorMatches(rule.chain, parseSelectorChain(f.selector))
            && (rule.imp || specificityGte(specificityOf(rule.chain), specificityOf(parseSelectorChain(f.selector)))));
        if (!coveredByRule) {
            items.push({ kind: 'font', item: f.selector, size: f.size });
        }
    }
    return items;
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些符号与 simulator-adapt.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'ENTRY_CLASSES',
    'INNER_CLASSES',
    'VARS_FAMILY',
    'FONT_SCAN_THRESHOLD_PX',
    'RECORD_MARKER',
    'parseCoverageRecords',
    'extractGameClasses',
    'compareCoverage',
];
