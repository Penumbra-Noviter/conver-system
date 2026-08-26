/**
 * Conver System — style.css 静态 CSS 契约测试（F-73：.gg-config-warning-nav 对比度）
 *
 * 职责：把 F-73 工单验收标准落成可机器验证的断言：
 *   - `.gg-config-warning-nav` 规则存在且含 color 声明，值不再是 light 下的
 *     `var(--warning)`（#d29a47 琥珀浅色，对浅底约 2.3~3:1，低于 WCAG AA 4.5:1）
 *   - color 为字面加深色值（6 位 hex），对 light 主题底（--bg 实测 #f8f5ef）
 *     的 WCAG 相对亮度对比度 ≥ 4.5:1
 *   - light 底读自 `:root[data-theme="light"]` 块的 --bg 声明（与渲染读源一致，
 *     避免测试硬编码与主题文件双源漂移）
 *   - `--warning` 变量单源声明（默认 :root，style.css:39）未被改动——其被多处
 *     共享，改动影响面大，F-73 只加深本选择器
 *
 * 测试方式为静态契约断言（postcss 解析 + 语义锚）：沿用
 * simulator-pc-css.test.js 的文本锚点模式；CSS 文件不在 vitest v8 JS 覆盖率
 * 采集范围，本文件不套 JS 覆盖率阈值。
 */

import { describe, it as test, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import postcss from 'postcss';

const cssPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../css/style.css');
const css = readFileSync(cssPath, 'utf8');
const ast = postcss.parse(css);

/** 递归收集所有 rule 节点（含 atrule 嵌套） */
function collectRules(nodes, out = []) {
    for (const n of nodes ?? []) {
        if (n.type === 'rule') out.push(n);
        if (n.type === 'atrule' && n.nodes) collectRules(n.nodes, out);
    }
    return out;
}

const allRules = collectRules(ast.nodes);

/** 找第一条 selectors 数组恰好包含目标选择器的 rule */
function ruleWithSelector(selector) {
    return allRules.find((r) => (r.selectors ?? []).includes(selector));
}

/** 在 rule 内找声明 */
function decl(rule, prop) {
    return rule.nodes.find((n) => n.type === 'decl' && n.prop === prop);
}

/** 读 :root[data-theme="light"] 块内的自定义属性值（强制浅色主题读源） */
function lightThemeVar(name) {
    const root = allRules.find((r) => (r.selectors ?? []).some((s) => s === ':root[data-theme="light"]'));
    expect(root, ':root[data-theme="light"] 块应存在').toBeTruthy();
    const d = decl(root, name);
    expect(d, `light 主题应声明 ${name}`).toBeTruthy();
    return d.value.trim();
}

/** WCAG 2.x 相对亮度（6 位 hex → sRGB 线性化） */
function luminance(hex) {
    const m = /^#(?:[0-9a-f]{6})$/i.exec(hex);
    expect(m, `颜色对比度计算需要 6 位 hex 字面色值，got "${hex}"`).toBeTruthy();
    const rgb = [0, 2, 4].map((i) => parseInt(hex.slice(i + 1, i + 3), 16) / 255);
    for (let i = 0; i < 3; i++) {
        rgb[i] = rgb[i] <= 0.04045 ? rgb[i] / 12.92 : Math.pow((rgb[i] + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
}

/** WCAG 对比度（前景/背景，与顺序无关） */
function contrastRatio(a, b) {
    const la = luminance(a);
    const lb = luminance(b);
    const hi = Math.max(la, lb);
    const lo = Math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
}

/** 默认 :root 块内 --warning 的声明（单源） */
function warningDecl() {
    const root = allRules.find(
        (r) => (r.selectors ?? []).includes(':root') && (r.nodes ?? []).some((n) => n.type === 'decl' && n.prop === '--warning'),
    );
    expect(root, '默认 :root 块应含 --warning 声明').toBeTruthy();
    return decl(root, '--warning');
}

describe('style.css .gg-config-warning-nav 对比度契约（F-73）', () => {
    test('规则存在且 color 声明已不再是 var(--warning) 变量引用', () => {
        const rule = ruleWithSelector('.gg-config-warning-nav');
        expect(rule, '.gg-config-warning-nav 规则应存在').toBeTruthy();
        const color = decl(rule, 'color');
        expect(color, '.gg-config-warning-nav 应声明 color').toBeTruthy();
        expect(color.value.trim()).not.toBe('var(--warning)');
    });

    test('color 为字面加深色值（6 位 hex，非浅琥珀 #d29a47）', () => {
        const rule = ruleWithSelector('.gg-config-warning-nav');
        const color = decl(rule, 'color').value.trim();
        expect(color).toMatch(/^#[0-9a-f]{6}$/i);
        expect(color.toLowerCase()).not.toBe('#d29a47');
    });

    test('color 对 light 主题底对比度 ≥ 4.5:1（WCAG AA）', () => {
        const rule = ruleWithSelector('.gg-config-warning-nav');
        const color = decl(rule, 'color').value.trim().toLowerCase();
        const bg = lightThemeVar('--bg').toLowerCase();
        const ratio = contrastRatio(color, bg);
        expect(ratio).toBeGreaterThanOrEqual(4.5);
    });

    test('--warning 变量单源声明未被改动（仍为 #d29a47）', () => {
        expect(warningDecl().value.trim().toLowerCase()).toBe('#d29a47');
    });

    test('dark 语境恢复琥珀高对比：显式 dark 选择器回退 var(--warning)（W1 直修，防浅色加深波及 dark 底 3.45:1）', () => {
        const darkRule = ruleWithSelector(':root[data-theme="dark"] .gg-config-warning-nav');
        expect(darkRule, ':root[data-theme="dark"] .gg-config-warning-nav 应存在').toBeTruthy();
        expect(decl(darkRule, 'color').value.trim()).toBe('var(--warning)');
        // OS dark 默认态（:root:not([data-theme="light"])）同样回退
        const autoDarkRule = allRules.find(
            (r) => (r.selectors ?? []).includes(':root:not([data-theme="light"]) .gg-config-warning-nav'),
        );
        expect(autoDarkRule, 'OS dark 默认态 override 应存在').toBeTruthy();
        expect(decl(autoDarkRule, 'color').value.trim()).toBe('var(--warning)');
    });
});