/**
 * Conver System — simulator-pc.css 契约测试（PC 阅读覆盖层）
 *
 * 职责：把 T1 工单验收标准（6 分区/选择器覆盖/B 类变量锚/降级块）落成
 *   可机器验证的断言，并锁定期末四轴 Falsify 修复的语义（防复发回归
 *   断言）：
 *   - F1（降级块死代码）：@media (max-width:1100px) 内字号必须带
 *     !important——否则被分区 1 的 15px !important 压死，窄屏降级失效。
 *   - F2（内层文本继承阻断）：分区 1 必须含 .msg/.bubble/.m-text/.wrap
 *     内层选择器的 15px !important 规则——否则 10+ 游戏正文停留在
 *     13-14.5px 移动端字号。
 *
 * 测试方式为静态契约断言（postcss 解析 + 文本锚点）：jsdom 不加载外部
 *   样式表且无 matchMedia，媒体查询语义无法在单测层验证，故以「声明
 *   存在性 + !important 携带性」锁定契约；浏览器级行为由冒烟脚本
 *   （scripts/smoke-simulators.mjs / 主应用 iframe 实测）验证。
 */

import { describe, it as test, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import postcss from 'postcss';
import { parseCoverageRecords } from '../js/simulator-adapt.js';

const cssPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../css/simulator-pc.css');
const css = readFileSync(cssPath, 'utf8');
const ast = postcss.parse(css);

/** 递归收集所有 rule 节点 */
function collectRules(nodes, out = []) {
    for (const n of nodes ?? []) {
        if (n.type === 'rule') out.push(n);
        if (n.type === 'atrule' && n.nodes) collectRules(n.nodes, out);
    }
    return out;
}

/** 收集所有 atrule（含嵌套内） */
function collectAtRules(nodes, out = []) {
    for (const n of nodes ?? []) {
        if (n.type === 'atrule') {
            out.push(n);
            if (n.nodes) collectAtRules(n.nodes, out);
        }
    }
    return out;
}

const allRules = collectRules(ast.nodes);
/** 顶层规则（不嵌套在 atrule 内——双源检查只针对顶层） */
const topRules = ast.nodes.filter((n) => n.type === 'rule');

/** 找 selectors 数组同时包含全部给定选择器的 rule（含嵌套 atrule 内） */
function ruleWithAll(...selectors) {
    return allRules.find((r) => selectors.every((s) => (r.selectors ?? []).includes(s)));
}

describe('simulator-pc.css 契约（T1 验收标准）', () => {
    test('文件存在且可被 postcss 解析（无语法错误）', () => {
        expect(css.length).toBeGreaterThan(500);
        expect(ast.nodes.length).toBeGreaterThan(0);
    });

    test('7 分区注释锚点各出现一次', () => {
        for (let i = 1; i <= 7; i++) {
            const matches = css.match(new RegExp(`/\\* 分区 ${i} ·`, 'g')) ?? [];
            expect(matches.length).toBe(1);
        }
    });

    test('日志容器 id 变体全部命中（#game-log/#chat-log/#log）', () => {
        expect(ruleWithAll('#game-log', '#chat-log', '#log')).toBeTruthy();
    });

    test('日志条目类名全覆盖（.log-entry/.chat-msg/.msg/.ency-entry/.mem-entry）', () => {
        expect(ruleWithAll('.log-entry', '.chat-msg', '.msg', '.ency-entry', '.mem-entry')).toBeTruthy();
    });

    test('A 类变量覆盖：--t2/--t3/--bg-deep/--border 在 :root 选择器集内', () => {
        const root = allRules.find((r) => (r.selectors ?? []).some((s) => s.includes('[data-theme]')) && r.selectors.some((s) => s.includes(':root')));
        const decls = root.nodes.filter((n) => n.type === 'decl').map((d) => d.prop);
        expect(decls).toEqual(expect.arrayContaining(['--t2', '--t3', '--bg-deep', '--border']));
    });

    test('B 类 7 组私有变量锚全部存在（仿微 --sub 为显式类色等价实现）', () => {
        for (const v of ['--muted', '--text2', '--text3', '--tx2', '--tx3', '--fs-s']) {
            expect(css).toContain(`${v}:`);
        }
        // --sub 变量覆盖已废弃（全局 :root 注入会污染无 --sub 的游戏，
        // 2026-08-19 分区 7 实测）—— 仿微说明类显式压深为其等价物
        expect(css).toContain('.pc-note');
        expect(css).toContain('#5f5f5f');
    });

    test('#side-panel 与 #right-panel 并列于状态面板规则', () => {
        expect(ruleWithAll('#right-panel', '#side-panel')).toBeTruthy();
    });

    test('窄屏降级 @media (max-width: 1100px) 存在', () => {
        const media = collectAtRules(ast.nodes).filter((a) => a.params.includes('max-width: 1100px'));
        expect(media.length).toBeGreaterThan(0);
    });

    test('不引用游戏私有选择器（#wz-logo 等）', () => {
        expect(css).not.toContain('#wz-logo');
        expect(css).not.toContain('#moon');
    });
});

describe('simulator-pc.css 分区 7 契约（AI 配置面板基线）', () => {
    test('分区 7 注释锚点存在', () => {
        expect(css).toContain('/* 分区 7 · AI 配置面板基线');
    });

    test('配置面板 label 字号抬升为 13px !important', () => {
        const labelRule = ruleWithAll('.setup-box label', '.wizard label', '.panel-card label');
        expect(labelRule).toBeTruthy();
        const fs = labelRule.nodes.find((n) => n.type === 'decl' && n.prop === 'font-size');
        expect(fs.value).toBe('13px');
        expect(fs.important).toBe(true);
    });

    test('说明文字 .hint/.note 字号抬升为 12.5px !important', () => {
        const hintRule = ruleWithAll('.setup-box .hint', '.wizard .hint');
        expect(hintRule).toBeTruthy();
        const fs = hintRule.nodes.find((n) => n.type === 'decl' && n.prop === 'font-size');
        expect(fs.value).toBe('12.5px');
        expect(fs.important).toBe(true);
    });

    test('输入控件字号 14px + 占位符提亮', () => {
        const inputRule = allRules.find((r) => (r.selectors ?? []).includes('input'));
        const fs = inputRule.nodes.find((n) => n.type === 'decl' && n.prop === 'font-size');
        expect(fs.value).toBe('14px');
        const phRule = allRules.find((r) => (r.selectors ?? []).some((s) => s.includes('::placeholder')));
        expect(phRule).toBeTruthy();
        const phColor = phRule.nodes.find((n) => n.type === 'decl' && n.prop === 'color');
        expect(phColor.value).toContain('#8e8ea8');
    });

    test('配置卡片居中规则（margin-inline: auto）', () => {
        const centerRule = ruleWithAll('.setup-box', '.setup-wrap', '.wizard');
        expect(centerRule).toBeTruthy();
        const mi = centerRule.nodes.find((n) => n.type === 'decl' && n.prop === 'margin-inline');
        expect(mi.value).toBe('auto');
    });
});

describe('simulator-pc.css 期末四轴修复回归锁（Falsify F1/F2）', () => {    test('F1：降级块内 html,body 字号必须带 !important（否则被分区 1 压死）', () => {
        const media = collectAtRules(ast.nodes).find((a) => a.params.includes('max-width: 1100px'));
        const htmlBody = media.nodes.find((n) => n.type === 'rule' && (n.selectors ?? []).some((s) => s.includes('html')));
        expect(htmlBody).toBeTruthy();
        const fs = htmlBody.nodes.find((n) => n.type === 'decl' && n.prop === 'font-size');
        expect(fs.value).toBe('14px');
        expect(fs.important).toBe(true);
    });

    test('F1：降级块内内层文本字号也带 !important', () => {
        const media = collectAtRules(ast.nodes).find((a) => a.params.includes('max-width: 1100px'));
        const inner = media.nodes.find((n) => n.type === 'rule' && (n.selectors ?? []).some((s) => s.includes('.msg .bubble')));
        expect(inner).toBeTruthy();
        const fs = inner.nodes.find((n) => n.type === 'decl' && n.prop === 'font-size');
        expect(fs.value).toBe('14px');
        expect(fs.important).toBe(true);
    });

    test('F2：分区 1 内层正文规则（.msg .m-text 等）为 15px !important', () => {
        const inner = ruleWithAll('.msg .m-text', '.msg .bubble', '.msg .wrap');
        expect(inner).toBeTruthy();
        const fs = inner.nodes.find((n) => n.type === 'decl' && n.prop === 'font-size');
        expect(fs.value).toBe('15px');
        expect(fs.important).toBe(true);
        const lh = inner.nodes.find((n) => n.type === 'decl' && n.prop === 'line-height');
        expect(lh.value).toBe('1.85');
    });

    test('F2：仿微组无残留 .msg .bubble 14px 双源（统一走分区 1，顶层规则检查）', () => {
        const bubbleRules = topRules.filter((r) => (r.selectors ?? []).includes('.msg .bubble'));
        for (const r of bubbleRules) {
            const fs = r.nodes.find((n) => n.type === 'decl' && n.prop === 'font-size');
            if (fs) expect(fs.value).not.toBe('14px');
        }
    });
});

describe('simulator-pc.css 映射记录契约（T-01 结构化）', () => {
    const coverage = parseCoverageRecords(css);
    const simDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../simulators');
    const gameNames = readdirSync(simDir)
        .filter((f) => f.endsWith('.html'))
        .map((f) => f.slice(0, -'.html'.length))
        .sort();

    test('`# sim-pc:` 标记行出现一次且 postcss 可解析（注释块内不产生规则）', () => {
        const markerLines = css.split(/\r?\n/).filter((l) => l.trim() === '# sim-pc:');
        expect(markerLines).toHaveLength(1);
        expect(ast.nodes.length).toBeGreaterThan(0);
        expect(css).toContain('映射记录（机器契约');
        expect(css).toContain('# sim-pc:');
    });

    test('记录 22 款游戏与 frontend/simulators/*.html 文件干名一一对应（双向）', () => {
        const recordNames = coverage.games.map((g) => g.name).sort();
        expect(recordNames).toHaveLength(gameNames.length);
        expect(recordNames).toEqual(gameNames);
        expect(new Set(recordNames).size).toBe(recordNames.length);
    });

    test('记录 classes 项全部出现在覆盖层实际规则选择器类名中', () => {
        for (const g of coverage.games) {
            for (const cls of g.classes) {
                expect(coverage.covered.classes, `${g.name} 记录类名 ${cls} 应存在对应规则`).toContain(cls);
            }
        }
    });

    test('记录 vars 非豁免项全部有覆盖层变量声明；豁免项仅 --sub（决策面单源）', () => {
        for (const g of coverage.games) {
            for (const v of g.vars) {
                if (v.exempt) {
                    expect(v.name).toBe('--sub'); // 唯一决策面豁免（分区 7 注释在案）
                } else {
                    expect(coverage.covered.vars, `${g.name} 记录变量 ${v.name} 应存在对应声明`).toContain(v.name);
                }
            }
        }
        // --sub 豁免恰好一次（仿微）
        const subExempts = coverage.games.flatMap((g) => g.vars.filter((v) => v.exempt));
        expect(subExempts).toHaveLength(1);
        expect(subExempts[0].name).toBe('--sub');
    });

    test('记录 fonts 项格式合法且豁免项未被覆盖层规则选择器覆盖（豁免不冗余）', () => {
        const ruleSelectors = new Set(coverage.covered.fontRules.map((r) => r.selector));
        for (const g of coverage.games) {
            for (const f of g.fonts) {
                expect(f.size).toMatch(/^\d+(\.\d+)?px$/);
                expect(f.selector).toMatch(/^([.#]?[a-zA-Z][a-zA-Z0-9_-]*)+([ ]([.#]?[a-zA-Z][a-zA-Z0-9_-]*)+)*$/);
                if (f.exempt) {
                    // 豁免 = 覆盖层明确不覆盖：选择器不得与任何覆盖层字号规则
                    // 选择器完全相同（否则豁免冗余）。祖先选择器前缀不算冗余
                    // —— 规则命中容器元素而非被修饰元素本身（如
                    // `.log-entry.think summary` 与规则 `.log-entry.think`）
                    expect(ruleSelectors.has(f.selector), `${g.name} 豁免项 ${f.selector} 不应与规则重复`).toBe(false);
                }
            }
        }
        // 全部 22 款记录 fonts 均为豁免项（当前覆盖层无逐游戏非豁免字号记录）
        const allFonts = coverage.games.flatMap((g) => g.fonts);
        expect(allFonts.length).toBeGreaterThan(0);
        expect(allFonts.every((f) => f.exempt)).toBe(true);
    });

    test('记录 fonts 豁免项的选择器含日志体系类（核对面自洽）', () => {
        const logClasses = ['log-entry', 'chat-msg', 'msg', 'ency-entry', 'mem-entry', 'm-text', 'm-bubble', 'bubble', 'wrap', 'm-main'];
        for (const g of coverage.games) {
            for (const f of g.fonts) {
                expect(logClasses.some((c) => f.selector.split(/\s+/).some((part) => part.split('.').includes(c))),
                    `${g.name} 豁免选择器 ${f.selector} 应含日志体系类`).toBe(true);
            }
        }
    });
});
