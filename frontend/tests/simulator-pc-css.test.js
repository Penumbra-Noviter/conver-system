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
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import postcss from 'postcss';

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
