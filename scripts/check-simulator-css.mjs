#!/usr/bin/env node
/**
 * Conver System — 模拟器接入契约核对脚本（T-01）
 *
 * 职责：新游戏接入把关 —— 对指定游戏 HTML（默认 frontend/simulators/
 *   全部 22 款）运行覆盖层适配分析（simulator-adapt.js 共享模块）：
 *   解析 simulator-pc.css 的映射记录（`# sim-pc:` 段）+ 提取游戏三面
 *   （日志条目类名 / CSS 变量体系 / 显式字号声明）+ 比对，输出
 *   「未覆盖清单」。退出码 0 = 全绿（无未覆盖）；非 0 = 有未覆盖项
 *   （含映射记录缺失 —— 新游戏接入强制先补记录）。
 *
 * 用法：
 *   node scripts/check-simulator-css.mjs              # 全部 22 款
 *   node scripts/check-simulator-css.mjs <game>.html  # 单款/多款
 *
 * 输出契约（工单 01 验收 grep 口径）：全绿时输出不含「未覆盖」；
 *   有未覆盖时每项一行 `[未覆盖] <游戏> · <类型> <细节>`。
 *
 * 依赖：frontend/js/simulator-adapt.js（Node ESM 零 DOM，冒烟直 import
 *   先例）；纯文本解析，无 eval / 无任意代码执行面。
 */

import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

import {
    parseCoverageRecords,
    extractGameClasses,
    compareCoverage,
} from '../frontend/js/simulator-adapt.js';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_SIM_DIR = path.resolve(SCRIPT_DIR, '../frontend/simulators');
const DEFAULT_CSS_PATH = path.resolve(SCRIPT_DIR, '../frontend/css/simulator-pc.css');

/** 未覆盖项 → 一行输出文本 */
function renderItem(item) {
    switch (item.kind) {
        case 'record':
            return `无映射记录（未接入核对，先补映射记录再验收）`;
        case 'class':
            return `类名 ${item.item}（覆盖层未覆盖该日志条目类）`;
        case 'var':
            return `变量 ${item.item}（覆盖层未覆盖该变量体系成员）`;
        case 'font':
            return item.important
                ? `字号 ${item.item} = ${item.size}（带 !important，覆盖层契约前提外必报）`
                : `字号 ${item.item} = ${item.size}（< 14px 未被覆盖层规则覆盖）`;
        default:
            return item.item;
    }
}

/**
 * 对一批游戏 HTML 运行覆盖核对（纯函数，测试 seam）。
 *
 * @param {string[]} gameFiles - 游戏 HTML 文件路径（绝对或相对）
 * @param {string} cssText - 覆盖层 CSS 全文
 * @returns {{items: Array<{game: string, kind: string, item: string,
 *   size?: string}>, checked: number}} 未覆盖清单（全绿 items 为空数组）
 */
export function runCheck(gameFiles, cssText) {
    const coverage = parseCoverageRecords(cssText);
    const items = [];
    for (const file of gameFiles) {
        const gameName = path.basename(file, '.html');
        const html = readFileSync(file, 'utf8');
        for (const item of compareCoverage(extractGameClasses(html), gameName, coverage)) {
            items.push({ ...item, game: gameName });
        }
    }
    return { items, checked: gameFiles.length };
}

/**
 * CLI 主入口：解析参数 → 读取 CSS 与游戏文件 → 输出未覆盖清单。
 *
 * @param {string[]} argv - CLI 参数（默认 process.argv 切片）
 * @returns {number} 退出码（0 = 全绿，1 = 有未覆盖项）
 */
export function main(argv = process.argv.slice(2)) {
    let cssText;
    let gameFiles;
    try {
        cssText = readFileSync(DEFAULT_CSS_PATH, 'utf8');
        gameFiles = argv.length > 0
            ? argv.map((f) => path.resolve(process.cwd(), f))
            : readdirSync(DEFAULT_SIM_DIR)
                .filter((f) => f.endsWith('.html'))
                .sort()
                .map((f) => path.join(DEFAULT_SIM_DIR, f));
    } catch (err) {
        console.error(`[错误] 读取失败：${err.message}`);
        return 1;
    }
    let result;
    try {
        result = runCheck(gameFiles, cssText);
    } catch (err) {
        console.error(`[错误] 核对失败：${err.message}`);
        return 1;
    }
    const { items, checked } = result;
    if (items.length === 0) {
        console.log(`已核对 ${checked} 款：全部通过`);
        return 0;
    }
    for (const item of items) {
        console.log(`[未覆盖] ${item.game} · ${renderItem(item)}`);
    }
    console.log(`共 ${items.length} 项未覆盖（覆盖层核对失败）`);
    return 1;
}

const entryPath = process.argv[1];
if (entryPath && import.meta.url === pathToFileURL(entryPath).href) {
    process.exitCode = main();
}
