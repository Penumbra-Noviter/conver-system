/**
 * Conver System — simulator-adapt.js 适配分析共享模块测试（T-01）
 *
 * 职责：把工单 01 验收标准落成可机器验证断言——
 *   - 映射记录可被 parseCoverageRecords 解析（`# sim-pc:` 锚 + 每游戏一行；
 *     契约测试断言解析结果与 CSS 实际规则一致）
 *   - 证伪用例：含未覆盖类名（如 `.log-entry .content` 显式 12px 字号）的
 *     样本 HTML → compareCoverage 输出该未覆盖项；CLI 退出码非 0
 *   - 22 款全绿：真实 simulators 目录 + 真实覆盖层 CSS → 无未覆盖项（回归锁）
 *   - 模块顶层零 DOM（Node 直 import 可运行）
 *
 * 覆盖判定模型（定版契约，工单 04 共用）：
 *   - classes：游戏使用的日志条目类（覆盖层已知体系类），须 ∈ 覆盖层规则类名集
 *   - vars：游戏出现的覆盖层变量覆盖体系成员，须 ∈ 覆盖层变量声明集 ∪ 记录豁免
 *   - fonts：游戏显式字号 < 14px 且选择器含日志体系类，须被覆盖层字号规则
 *     级联匹配（选择器结构匹配 + !important 或同特异性后加载），或列入
 *     记录豁免清单（`选择器:字号!`）
 *   - 记录缺失（游戏不在 `# sim-pc:` 段）= 未接入核对，整体报出
 */

import { describe, it as test, expect } from 'vitest';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import os from 'node:os';

import {
    parseCoverageRecords,
    extractGameClasses,
    compareCoverage,
    ENTRY_CLASSES,
    VARS_FAMILY,
    FONT_SCAN_THRESHOLD_PX,
} from '../js/simulator-adapt.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const SIM_DIR = path.resolve(here, '../simulators');
const CSS_PATH = path.resolve(here, '../css/simulator-pc.css');
const CLI_PATH = path.resolve(here, '../../scripts/check-simulator-css.mjs');

const REAL_CSS = readFileSync(CSS_PATH, 'utf8');

/** 最小合成覆盖层 CSS（覆盖判定模型的最小事实源） */
function synthCss(records = '') {
    return `
/* 分区 1 */
.log-entry, .chat-msg, .msg, .ency-entry, .mem-entry { font-size: 15px !important; }
.log-entry.system, .log-entry.think, .chat-msg.system, .msg.sys, .reason-ai, .mem-entry, .ency-entry { font-size: 13px; }
.msg .m-text, .msg .m-bubble, .msg .bubble, .msg .wrap, .log-entry .wrap, .log-entry .bubble, .chat-msg .bubble { font-size: 15px !important; }
/* 分区 2 */
:root, [data-theme] { --t2: #c2c2d8; --t3: #8e8ea8; --bg-deep: #0e0e18; --border: #333350; }
/* 映射记录 */
${records}
`;
}

describe('simulator-adapt.js 顶层约束', () => {
    test('Node 直 import 可运行（零 DOM，冒烟先例）', () => {
        expect(typeof parseCoverageRecords).toBe('function');
        expect(typeof extractGameClasses).toBe('function');
        expect(typeof compareCoverage).toBe('function');
    });

    test('常量契约：条目类 / 变量体系 / 扫描阈值', () => {
        expect(ENTRY_CLASSES).toEqual(['log-entry', 'chat-msg', 'msg', 'ency-entry', 'mem-entry']);
        expect(VARS_FAMILY).toContain('--t2');
        expect(VARS_FAMILY).toContain('--muted');
        expect(VARS_FAMILY).toContain('--sub'); // 刻意不覆盖的决策面（分区 7 注释）
        expect(VARS_FAMILY).toContain('--tx2');
        expect(VARS_FAMILY).toContain('--fs-m');
        expect(FONT_SCAN_THRESHOLD_PX).toBe(14);
    });
});

describe('parseCoverageRecords：映射记录解析', () => {
    test('无 `# sim-pc:` 标记 → games 为空，covered 仍从规则解析', () => {
        const c = parseCoverageRecords(synthCss());
        expect(c.games).toEqual([]);
        expect(c.covered.classes).toEqual(expect.arrayContaining(['log-entry', 'msg', 'm-text', 'wrap']));
        expect(c.covered.vars).toEqual(expect.arrayContaining(['--t2', '--t3', '--bg-deep', '--border']));
    });

    test('单游戏三字段 + 豁免 `!` 标记', () => {
        const css = synthCss(`
# sim-pc:
小马宝莉 | classes=msg,log-entry | vars=--muted | fonts=.msg code:13px!,.msg .r-box:12.5px!
`);
        const c = parseCoverageRecords(css);
        expect(c.games).toHaveLength(1);
        const [g] = c.games;
        expect(g.name).toBe('小马宝莉');
        expect(g.classes).toEqual(['msg', 'log-entry']);
        expect(g.vars).toEqual([{ name: '--muted', exempt: false }]);
        expect(g.fonts).toEqual([
            { selector: '.msg code', size: '13px', exempt: true },
            { selector: '.msg .r-box', size: '12.5px', exempt: true },
        ]);
    });

    test('多游戏多行 + 字段省略 + 豁免变量', () => {
        const css = synthCss(`
# sim-pc:
仿微 | classes=msg | vars=--sub!
仙途 | classes=log-entry
`);
        const c = parseCoverageRecords(css);
        expect(c.games.map((g) => g.name)).toEqual(['仿微', '仙途']);
        expect(c.games[0].vars).toEqual([{ name: '--sub', exempt: true }]);
        expect(c.games[1].classes).toEqual(['log-entry']);
        expect(c.games[1].vars).toEqual([]);
        expect(c.games[1].fonts).toEqual([]);
    });

    test('畸形行跳过（容错：缺字段分隔 / 未知字段 / 空行），不炸解析', () => {
        const css = synthCss(`
# sim-pc:
坏行没有管道分隔
ok | classes=msg
另一坏行 ||| 双管道
未知 | bogus=1 | classes=msg
`);
        const c = parseCoverageRecords(css);
        expect(c.games.map((g) => g.name)).toEqual(['ok', '未知']);
        expect(c.games[0].classes).toEqual(['msg']);
        expect(c.games[1].classes).toEqual(['msg']); // 未知字段跳过，合法字段保留
    });

    test('covered.fontRules 收集字号规则（选择器 / 字号 / !important 标志）', () => {
        const c = parseCoverageRecords(synthCss());
        const fr = c.covered.fontRules;
        expect(fr.some((r) => r.selector === '.log-entry' && r.imp)).toBe(true);
        expect(fr.some((r) => r.selector === '.msg .m-text' && r.imp)).toBe(true);
        expect(fr.some((r) => r.selector === '.log-entry.system' && !r.imp)).toBe(true);
        expect(fr.some((r) => r.selector === '.log-entry' && r.size === '15px')).toBe(true);
    });

    test('空 CSS / 非字符串输入 → 空结果不抛异常', () => {
        expect(parseCoverageRecords('').games).toEqual([]);
        expect(parseCoverageRecords(undefined).games).toEqual([]);
        expect(parseCoverageRecords(null).games).toEqual([]);
    });

    test('标记行可出现在注释块内（生产形态：CSS 注释包裹）', () => {
        const css = synthCss(`
/*
 * 映射记录（机器契约 # sim-pc:）
 * 语法说明……
 */
# sim-pc:
小马宝莉 | classes=msg
*/
`);
        const c = parseCoverageRecords(css);
        expect(c.games.map((g) => g.name)).toEqual(['小马宝莉']);
    });
});

describe('extractGameClasses：游戏 HTML 三面提取', () => {
    test('空 HTML → 三面全空', () => {
        expect(extractGameClasses('')).toEqual({ classes: [], vars: [], fonts: [] });
        expect(extractGameClasses('<!doctype html><html><body></body></html>').classes).toEqual([]);
    });

    test('日志条目类四来源：CSS 选择器 / class 属性 / className / classList.add', () => {
        const html = `<style>.log-entry { padding: 4px; } .msg .bubble { x: 1 }</style>
<div class="log-entry system">a</div>
<script>
  el.className = 'msg ';
  el2.classList.add('chat-msg');
</script>`;
        const { classes } = extractGameClasses(html);
        expect(classes).toEqual(['chat-msg', 'log-entry', 'msg']);
    });

    test('变量体系：定义（--x:）与引用（var(--x)）均命中 family', () => {
        const html = `<style>
:root { --t2: #abc; --muted: #def; --other: #123; }
.a { color: var(--tx2); background: var(--other); }
</style>`;
        const { vars } = extractGameClasses(html);
        expect(vars).toEqual(['--muted', '--t2', '--tx2']);
    });

    test('显式字号：<14px 命中、≥14px 忽略、var() 忽略、注释剥离、@media 内规则', () => {
        const html = `<style>
/* .log-entry .fake { font-size: 9px; } 注释内不算 */
.log-entry { font-size: 12.5px; }
.log-entry .ok { font-size: 14px; }
.log-entry .v { font-size: var(--fs-m); }
.msg .txt { font-size: 13px; }
@media (max-width: 700px) { .log-entry { font-size: 11px; } }
</style>`;
        const { fonts } = extractGameClasses(html);
        expect(fonts).toHaveLength(3);
        expect(fonts).toContainEqual({ selector: '.log-entry', size: '12.5px', important: false });
        expect(fonts).toContainEqual({ selector: '.msg .txt', size: '13px', important: false });
        expect(fonts).toContainEqual({ selector: '.log-entry', size: '11px', important: false });
        expect(fonts.some((f) => f.selector.includes('.ok'))).toBe(false);
        expect(fonts.some((f) => f.selector.includes('.v'))).toBe(false);
    });

    test('选择器含 id / 标签 / 伪类 / 后代选择器均可解析且去重', () => {
        const html = `<style>
#log .msg .m-text { font-size: 13.5px; }
.msg:hover { font-size: 12px; }
.msg .m-text { font-size: 13.5px; }
.think-box summary::before { font-size: 9px; }
</style>`;
        const { fonts } = extractGameClasses(html);
        expect(fonts).toContainEqual({ selector: '#log .msg .m-text', size: '13.5px', important: false });
        expect(fonts).toContainEqual({ selector: '.msg:hover', size: '12px', important: false });
        expect(fonts).toContainEqual({ selector: '.msg .m-text', size: '13.5px', important: false });
        // 伪元素 ::before 不作用于日志元素本体，跳过
        expect(fonts.some((f) => f.selector.includes('::before'))).toBe(false);
        // 去重：同选择器同字号只留一条
        expect(fonts.filter((f) => f.selector === '#log .msg .m-text')).toHaveLength(1);
    });

    test('非日志体系类选择器不进入 fonts 面（业务类不误报）', () => {
        const html = `<style>
.btn { font-size: 11px; }
.card .title { font-size: 12px; }
</style>`;
        expect(extractGameClasses(html).fonts).toEqual([]);
    });

    test('非 px 单位字号（em/百分数/inherit）不进入 fonts 面', () => {
        const html = `<style>
.log-entry .x { font-size: 0.9em; }
.log-entry .y { font-size: 80%; }
.log-entry .z { font-size: inherit; }
</style>`;
        expect(extractGameClasses(html).fonts).toEqual([]);
    });
});

describe('compareCoverage：覆盖判定', () => {
    const baseCss = synthCss(`
# sim-pc:
样本 | classes=msg | fonts=.msg code:13px!
`);

    test('全绿：游戏三面全部被覆盖层规则覆盖 → 空清单', () => {
        const html = `<style>.log-entry { font-size: 12.5px; } .log-entry.system { font-size: 10px; } .msg .m-text { font-size: 12.5px; }</style>
<div class="log-entry">x</div>`;
        const game = extractGameClasses(html);
        const items = compareCoverage(game, '样本', parseCoverageRecords(synthCss(`
# sim-pc:
样本 | classes=log-entry,msg
`)));
        expect(items).toEqual([]);
    });

    test('容错：缺字段的游戏对象（{}）不抛异常，仅报记录缺失', () => {
        const items = compareCoverage({}, '新游戏', parseCoverageRecords(baseCss));
        expect(items).toEqual([{ kind: 'record', item: '新游戏' }]);
    });

    test('证伪：`.log-entry .content` 显式 12px 且无记录 → 输出该未覆盖项（font + record）', () => {
        const html = `<!doctype html><html><head><style>.log-entry .content { font-size: 12px; }</style></head>
<body><div class="log-entry"><div class="content">x</div></div></body></html>`;
        const game = extractGameClasses(html);
        const items = compareCoverage(game, '新游戏', parseCoverageRecords(baseCss));
        expect(items.some((i) => i.kind === 'record' && i.item === '新游戏')).toBe(true);
        const font = items.find((i) => i.kind === 'font');
        expect(font).toBeTruthy();
        expect(font.item).toBe('.log-entry .content');
        expect(font.size).toBe('12px');
    });

    test('字号豁免：记录 fonts 豁免清单命中 → 不报', () => {
        const html = `<style>.msg code { font-size: 13px; }</style>`;
        const game = extractGameClasses(html);
        const items = compareCoverage(game, '样本', parseCoverageRecords(baseCss));
        expect(items.filter((i) => i.kind === 'font')).toEqual([]);
    });

    test('变量豁免：--sub! 记录 + 游戏定义 --sub → 不报；无豁免 → 报', () => {
        const exempted = parseCoverageRecords(synthCss(`
# sim-pc:
仿微 | classes=msg | vars=--sub!
`));
        const game = extractGameClasses('<style>:root { --sub: #888; }</style>');
        expect(compareCoverage(game, '仿微', exempted)).toEqual([]);

        const notExempted = parseCoverageRecords(synthCss('# sim-pc:\n仿微 | classes=msg'));
        const items = compareCoverage(game, '仿微', notExempted);
        expect(items.some((i) => i.kind === 'var' && i.item === '--sub')).toBe(true);
    });

    test('变量覆盖：family 变量在覆盖层有声明 → 不报', () => {
        const html = `<style>:root { --t2: #abc; --border: #123; }</style>`;
        const game = extractGameClasses(html);
        const items = compareCoverage(game, '样本', parseCoverageRecords(synthCss('# sim-pc:\n样本 | classes=log-entry')));
        expect(items.filter((i) => i.kind === 'var')).toEqual([]);
    });

    test('类名覆盖判定：覆盖层删除某条目类规则 → 游戏使用该类即报', () => {
        const cssWithoutMsg = synthCss().replace('.msg,', '').replace(/\.msg /g, '.msgX ').replace(/\.msg\./g, '.msgX.');
        const coverage = parseCoverageRecords(cssWithoutMsg);
        const game = extractGameClasses('<style>.msg { font-size: 13px; }</style>');
        const items = compareCoverage(game, '样本', coverage);
        expect(items.some((i) => i.kind === 'class' && i.item === 'msg')).toBe(true);
        expect(items.some((i) => i.kind === 'font')).toBe(true); // 字号规则一并缺位
    });

    test('记录 classes 补充覆盖：类在记录中即视为已核对（即使规则集缺位）', () => {
        const coverage = parseCoverageRecords(synthCss(`
# sim-pc:
样本 | classes=msg,自定义条目
`));
        const game = extractGameClasses('<div class="log-entry">x</div>');
        // 自定义条目 只出现在记录中 → 不报；log-entry 全局覆盖 → 不报
        const items = compareCoverage(game, '样本', coverage);
        expect(items.filter((i) => i.kind === 'class')).toEqual([]);
    });

    test('记录 fonts 非豁免项也算覆盖（文档覆盖：已核对在案）', () => {
        const coverage = parseCoverageRecords(synthCss(`
# sim-pc:
样本 | classes=msg | fonts=.msg .r-box:12.5px
`));
        const game = extractGameClasses('<style>.msg .r-box { font-size: 12.5px; }</style>');
        expect(compareCoverage(game, '样本', coverage)).toEqual([]);
    });

    test('级联覆盖：内层选择器被 F3 规则结构匹配（.log-entry.system .wrap → .log-entry .wrap）→ 不报', () => {
        const html = `<style>.log-entry.system .wrap { font-size: 12px; }</style>`;
        const game = extractGameClasses(html);
        const items = compareCoverage(game, '样本', parseCoverageRecords(synthCss('# sim-pc:\n样本 | classes=log-entry')));
        expect(items.filter((i) => i.kind === 'font')).toEqual([]);
    });

    test('非重要规则同特异性后加载覆盖：.log-entry.system 10px 被 13px 规则压过 → 不报', () => {
        const html = `<style>.log-entry.system { font-size: 10px; }</style>`;
        const game = extractGameClasses(html);
        const items = compareCoverage(game, '样本', parseCoverageRecords(synthCss('# sim-pc:\n样本 | classes=log-entry')));
        expect(items.filter((i) => i.kind === 'font')).toEqual([]);
    });

    test('非重要规则特异性比较分支：R2 专属选择器（无 R1 命中）→ spec 比较走通', () => {
        // 合成 CSS 只保留 R2（.log-entry.system 非重要）—— R1 不匹配时
        // specificityGte 分支必须独立判覆盖
        const css = '.log-entry.system { font-size: 13px; }\n# sim-pc:\n样本 | classes=log-entry';
        const html = `<style>.log-entry.system { font-size: 10px; }</style>`;
        const game = extractGameClasses(html);
        expect(compareCoverage(game, '样本', parseCoverageRecords(css))).toEqual([]);

        // 特异性不足（#log 提权）→ 覆盖失败必报
        const css2 = '.log-entry.system { font-size: 13px; }\n# sim-pc:\n样本 | classes=log-entry';
        const html2 = `<style>#log .log-entry.system { font-size: 10px; }</style>`;
        const items2 = compareCoverage(extractGameClasses(html2), '样本', parseCoverageRecords(css2));
        expect(items2.some((i) => i.kind === 'font' && i.item === '#log .log-entry.system')).toBe(true);
    });

    test('游戏字号带 !important（覆盖层契约三前提外）→ 提取标记 + 必报未覆盖', () => {
        const html = `<style>.log-entry .content { font-size: 12px !important; }</style>`;
        const game = extractGameClasses(html);
        expect(game.fonts[0]).toEqual({ selector: '.log-entry .content', size: '12px', important: true });
        const items = compareCoverage(game, '样本', parseCoverageRecords(baseCss));
        const font = items.find((i) => i.kind === 'font' && i.important);
        expect(font).toBeTruthy();
        expect(font.item).toBe('.log-entry .content');
    });
});

describe('check-simulator-css.mjs CLI（真实文件集成）', () => {
    const nodeBin = process.execPath;

    test('22 款全绿：真实 simulators 目录 + 真实覆盖层 → 退出码 0 且输出不含「未覆盖」', () => {
        const r = spawnSync(nodeBin, [CLI_PATH], { encoding: 'utf8', cwd: path.resolve(here, '..') });
        expect(r.status).toBe(0);
        expect(r.stdout + r.stderr).not.toContain('未覆盖');
    }, 30000);

    test('证伪：含未覆盖类名的样本 HTML → 输出该未覆盖项且退出码非 0', () => {
        const tmp = mkdtempSync(path.join(os.tmpdir(), 'sim-adapt-'));
        const sample = path.join(tmp, 'falsify.html');
        writeFileSync(sample, `<!doctype html><html><head><style>.log-entry .content { font-size: 12px; }</style></head>
<body><div class="log-entry"><div class="content">x</div></div></body></html>`, 'utf8');
        const r = spawnSync(nodeBin, [CLI_PATH, sample], { encoding: 'utf8', cwd: path.resolve(here, '..') });
        expect(r.status).not.toBe(0);
        expect(r.stdout).toContain('未覆盖');
        expect(r.stdout).toContain('.log-entry .content');
    }, 30000);

    test('强制校验：无映射记录的游戏（即使无内容缺口）→ 报「无映射记录」且退出码非 0', () => {
        const tmp = mkdtempSync(path.join(os.tmpdir(), 'sim-adapt-'));
        const sample = path.join(tmp, 'empty.html');
        writeFileSync(sample, '<!doctype html><html><head></head><body>hi</body></html>', 'utf8');
        const r = spawnSync(nodeBin, [CLI_PATH, sample], { encoding: 'utf8', cwd: path.resolve(here, '..') });
        expect(r.status).not.toBe(0);
        expect(r.stdout).toContain('无映射记录');
        expect(r.stdout).not.toContain('.log-entry .content');
    }, 30000);

    test('容错：文件不存在 → 报 [错误] 且退出码非 0（无堆栈崩溃）', () => {
        const missing = path.join(os.tmpdir(), 'sim-adapt-missing.html');
        const r = spawnSync(nodeBin, [CLI_PATH, missing], { encoding: 'utf8', cwd: path.resolve(here, '..') });
        expect(r.status).not.toBe(0);
        expect(r.stdout + r.stderr).toContain('[错误]');
        expect(r.stdout + r.stderr).not.toContain('at ');
    }, 30000);
});

describe('check-simulator-css.mjs 直调（覆盖 CLI 输出分支）', () => {
    test('main() 无参数 → 返回 0（22 款全绿）', async () => {
        const { main } = await import('../../scripts/check-simulator-css.mjs');
        expect(main([])).toBe(0);
    });

    test('main() 带证伪样本 → 返回 1', async () => {
        const { main } = await import('../../scripts/check-simulator-css.mjs');
        const tmp = mkdtempSync(path.join(os.tmpdir(), 'sim-adapt-'));
        const sample = path.join(tmp, 'falsify.html');
        writeFileSync(sample, '<style>.log-entry .content { font-size: 12px; }</style>', 'utf8');
        expect(main([sample])).toBe(1);
    });

    test('runCheck() 三面全缺 → class/var/font/record 四类项齐出（renderItem 全分支）', async () => {
        const { runCheck } = await import('../../scripts/check-simulator-css.mjs');
        const tmp = mkdtempSync(path.join(os.tmpdir(), 'sim-adapt-'));
        const sample = path.join(tmp, '新游戏.html');
        writeFileSync(sample, `<style>.msg { font-size: 12px; } :root { --t2: #abc; }</style>
<div class="msg">x</div>`, 'utf8');
        // 无规则无记录的空 CSS → 全部缺口现形
        const { items } = runCheck([sample], '# sim-pc:');
        expect(items.map((i) => i.kind).sort()).toEqual(['class', 'font', 'record', 'var']);
        expect(items.find((i) => i.kind === 'font').item).toBe('.msg');
    });

    test('node -e 直 import：argv[1] 缺失不抛 TypeError（CLI 自执行判定容错）', () => {
        const nodeBin = process.execPath;
        const cliUrl = pathToFileURL(CLI_PATH).href;
        const r = spawnSync(nodeBin, ['-e', `import(${JSON.stringify(cliUrl)}).then(() => console.log('imported'))`], {
            encoding: 'utf8',
            cwd: path.resolve(here, '..'),
        });
        expect(r.stderr).not.toContain('TypeError');
        expect(r.stdout).toContain('imported');
        expect(r.status).toBe(0);
    });
});
