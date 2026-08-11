#!/usr/bin/env node
/**
 * render-logo-icon.mjs — 从网页版品牌 SVG logo 渲染 1024x1024 透明背景 PNG。
 *
 * 用途（spec P6.4 D9）：生成 tauri icon 的源图，产出全套桌面图标（P6.4-5 工单）。
 *
 * 数据流：
 *   1. 从 frontend/index.html 提取 `class="logo-icon"` 的内联 SVG（只读源，不改）；
 *   2. 从 frontend/css/style.css 读取品牌色 `--accent`（当前为 #d29a47），
 *      替换 SVG 中的 `currentColor`，保证颜色与网页版单一来源一致；
 *   3. 渲染为 1024x1024 PNG（透明背景、居中、保留 viewBox 自带留边）。
 *
 * 渲染机制（按序降级）：
 *   a. Playwright chromium（frontend devDependency，浏览器缓存于 ms-playwright 目录，
 *      脚本会自动探测缓存路径兜底 executablePath）；
 *   b. chromium 无头 CLI（--headless --screenshot），复用同一份渲染 HTML；
 *   c. 两者皆不可用 → 明确报错并给出修复指引。
 *
 * 用法：
 *   node scripts/render-logo-icon.mjs [--output <png 路径>]
 *   默认输出到系统临时目录 conver-logo-1024.png。
 *
 * 生成全套图标：
 *   node frontend/node_modules/@tauri-apps/cli/tauri.js icon \
 *     --output src-tauri/icons <本脚本输出的 png>
 */
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import zlib from 'node:zlib';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');
const FRONTEND_DIR = join(REPO_ROOT, 'frontend');
const ICON_CLASS = 'logo-icon';
const CANVAS = 1024; // 目标 PNG 边长
const LOGO_VIEWBOX = '0 0 20 20'; // 网页版 logo 的 viewBox（index.html 内联 SVG 原值）

/** 从 index.html 提取 logo SVG 的内部内容（两个 path），结构变化时明确报错。 */
function extractLogoSvg(html) {
  const re = new RegExp(`<svg\\b[^>]*class="${ICON_CLASS}"[^>]*>([\\s\\S]*?)<\\/svg>`);
  const m = html.match(re);
  if (!m) {
    throw new Error(
      `未在 frontend/index.html 中找到 class="${ICON_CLASS}" 的内联 SVG。` +
        `index.html 结构可能已变化；请核对 logo 标记（如 class 改名/移入 JS 模板）后重试。`,
    );
  }
  return m[1];
}

/** 从 style.css 读取品牌主色 `--accent`，取不到即报错（避免静默用错颜色）。 */
function readAccentColor(css) {
  const m = css.match(/--accent:\s*(#[0-9a-fA-F]{3,8})\s*;/);
  if (!m) {
    throw new Error(
      '未在 frontend/css/style.css 中找到 `--accent: #…;` 定义，无法确定品牌色。' +
        '请核对 CSS 变量定义后重试。',
    );
  }
  return m[1];
}

/** 组装独立 SVG：1024x1024 画布 + 原始 viewBox（自带留边），currentColor 替换为品牌色。 */
function buildStandaloneSvg(innerSvg, accent) {
  const content = innerSvg.replace(/currentColor/g, accent);
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${CANVAS}" height="${CANVAS}"`,
    ` viewBox="${LOGO_VIEWBOX}" fill="none">`,
    content,
    '</svg>',
  ].join('\n');
}

/** 组装渲染页 HTML：无 margin，SVG 撑满 1024x1024，背景透明。 */
function buildRenderHtml(svg) {
  return [
    '<!DOCTYPE html><html><head><meta charset="utf-8"></head>',
    '<body style="margin:0;background:transparent">',
    svg,
    '</body></html>',
  ].join('');
}

/** 探测 ms-playwright 缓存里的 chromium 可执行文件（供 executablePath / CLI 兜底）。 */
function findCachedChromium() {
  const envDir = process.env.PLAYWRIGHT_BROWSERS_PATH;
  const candidates = [envDir, join(process.env.LOCALAPPDATA || '', 'ms-playwright'), join(tmpdir(), 'ms-playwright')]
    .filter(Boolean)
    .map((d) => (process.platform === 'win32' ? d.replace(/\\/g, '/') : d));
  const platforms = {
    win32: ['chrome-win64/chrome.exe', 'chrome-win/chrome.exe', 'chrome-headless-shell-win64/chrome-headless-shell.exe'],
    linux: ['chrome-linux/chrome', 'chrome-headless-shell-linux/chrome-headless-shell'],
    darwin: ['chrome-mac/Chromium.app/Contents/MacOS/Chromium', 'chrome-headless-shell-mac/headless_shell'],
  };
  for (const base of candidates) {
    let entries = [];
    try {
      entries = readdirSync(base);
    } catch {
      continue; // 目录不存在，试下一个
    }
    const dirs = entries
      .filter((e) => e.startsWith('chromium'))
      .sort((a, b) => Number(b.match(/\d+/)?.[0] ?? 0) - Number(a.match(/\d+/)?.[0] ?? 0));
    for (const dir of dirs) {
      for (const sub of platforms[process.platform] || []) {
        const exe = join(base, dir, sub);
        if (existsSync(exe)) return exe;
      }
    }
  }
  return null;
}

/** 方式 a：Playwright 渲染（devDependency；库缺失或启动失败时返回 null 交给调用方降级）。 */
async function renderWithPlaywright(svgHtml, outFile) {
  let playwright;
  try {
    // playwright 装在 frontend/node_modules，需以 frontend 为解析基准（CJS require 走
    // createRequire，避免 ESM 动态 import 对 `module.exports = require(...)` 转发丢失命名导出）
    const requireFromFrontend = createRequire(pathToFileURL(join(FRONTEND_DIR, 'package.json')));
    playwright = requireFromFrontend('playwright');
  } catch {
    return null;
  }
  let browser;
  try {
    browser = await playwright.chromium.launch();
  } catch (err) {
    const exe = findCachedChromium();
    if (!exe) throw new Error(`Playwright 启动 chromium 失败且未找到缓存浏览器：${err.message}`);
    browser = await playwright.chromium.launch({ executablePath: exe });
  }
  try {
    const page = await browser.newPage({ viewport: { width: CANVAS, height: CANVAS } });
    await page.setContent(svgHtml, { waitUntil: 'load' });
    await page.screenshot({ path: outFile, omitBackground: true });
  } finally {
    await browser.close();
  }
  return outFile;
}

/** 方式 b：chromium 无头 CLI 渲染（复用同一份 HTML；写临时 HTML 文件供 file:// 加载）。 */
function renderWithChromiumCli(svgHtml, outFile) {
  const exe = findCachedChromium();
  if (!exe) {
    throw new Error(
      '未找到可用的 chromium 渲染器：Playwright 库不可用，且 ms-playwright 缓存目录下无 chromium。' +
        '修复：在 frontend 下执行 `npm i` 并 `npx playwright install chromium`（或安装 chromium 后重试）。',
    );
  }
  const tmpDir = mkdtempSync(join(tmpdir(), 'conver-icon-render-'));
  const htmlFile = join(tmpDir, 'render.html');
  writeFileSync(htmlFile, svgHtml, 'utf8');
  try {
    execFileSync(
      exe,
      [
        '--headless',
        '--disable-gpu',
        '--hide-scrollbars',
        '--default-background-color=00000000',
        `--window-size=${CANVAS},${CANVAS}`,
        `--screenshot=${outFile}`,
        pathToFileURL(htmlFile).href,
      ],
      { stdio: 'pipe' },
    );
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
  return outFile;
}

/** PNG 解码（仅支持 8bit RGBA / RGB，其余报错），返回 { width, height, rgba }。 */
function decodePng(buf) {
  if (buf.length < 33 || buf.readUInt32BE(0) !== 0x89504e47) {
    throw new Error('不是合法 PNG（签名不匹配）');
  }
  if (buf.readUInt32BE(12) !== 0x49484452) {
    throw new Error('PNG 缺 IHDR 块');
  }
  const width = buf.readUInt32BE(16);
  const height = buf.readUInt32BE(20);
  const bitDepth = buf[24];
  const colorType = buf[25];
  if (bitDepth !== 8 || (colorType !== 6 && colorType !== 2)) {
    throw new Error(`不支持的 PNG 像素格式（bitDepth=${bitDepth}, colorType=${colorType}），期望 8bit RGBA/RGB`);
  }
  const channels = colorType === 6 ? 4 : 3;
  let idat = Buffer.alloc(0);
  for (let off = 8; off + 8 <= buf.length; ) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    if (type === 'IDAT') idat = Buffer.concat([idat, buf.subarray(off + 8, off + 8 + len)]);
    off += 12 + len;
    if (type === 'IEND') break;
  }
  if (idat.length === 0) throw new Error('PNG 缺 IDAT 像素数据');
  const raw = zlib.inflateSync(idat);
  const stride = width * channels;
  const rgba = Buffer.alloc(width * height * 4);
  const prev = Buffer.alloc(stride);
  const cur = Buffer.alloc(stride);
  for (let y = 0, p = 0; y < height; y++) {
    const filter = raw[p++];
    raw.copy(cur, 0, p, p + stride);
    p += stride;
    // 还原行过滤（chromium 输出常见 filter 0/2/4，这里全支持以保健壮）
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? cur[x - channels] : 0;
      const b = prev[x];
      const c = x >= channels ? prev[x - channels] : 0;
      let v = cur[x];
      switch (filter) {
        case 1: v += a; break;
        case 2: v += b; break;
        case 3: v += (a + b) >> 1; break;
        case 4: {
          const pa = Math.abs(b - c);
          const pb = Math.abs(a - c);
          const pc = Math.abs(a + b - 2 * c);
          v += pa + pb + pc === pc ? a : pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          break;
        }
        default: break; // 0: 无过滤
      }
      cur[x] = v & 0xff;
    }
    for (let x = 0; x < width; x++) {
      for (let ch = 0; ch < channels; ch++) {
        rgba[(y * width + x) * 4 + ch] = cur[x * channels + ch];
      }
      if (channels === 3) rgba[(y * width + x) * 4 + 3] = 255;
    }
    prev.set(cur);
  }
  return { width, height, rgba };
}

/** 校验渲染产物：尺寸、RGBA 格式、非空白（不透明像素占比）、四角透明。 */
function verifyPng(file) {
  const buf = readFileSync(file);
  const { width, height, rgba } = decodePng(buf);
  if (width !== CANVAS || height !== CANVAS) {
    throw new Error(`渲染尺寸不符：期望 ${CANVAS}x${CANVAS}，实际 ${width}x${height}`);
  }
  let opaque = 0;
  const corners = [
    [0, 0],
    [width - 1, 0],
    [0, height - 1],
    [width - 1, height - 1],
  ];
  for (const [x, y] of corners) {
    if (rgba[(y * width + x) * 4 + 3] !== 0) {
      throw new Error(`渲染背景非透明：角点 (${x},${y}) alpha=${rgba[(y * width + x) * 4 + 3]}`);
    }
  }
  for (let i = 0; i < width * height; i++) {
    if (rgba[i * 4 + 3] > 0) opaque++;
  }
  const ratio = opaque / (width * height);
  if (ratio < 0.01) {
    throw new Error(`渲染结果疑似空白：不透明像素占比仅 ${(ratio * 100).toFixed(2)}%`);
  }
  return { width, height, opaqueRatio: ratio };
}

function usage() {
  return `用法: node scripts/render-logo-icon.mjs [--output <png 路径>]
  默认输出: 系统临时目录下 conver-logo-1024.png`;
}

async function main() {
  const args = process.argv.slice(2);
  let outFile = join(tmpdir(), 'conver-logo-1024.png');
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--output') outFile = resolve(args[++i]);
    else if (args[i] === '--help' || args[i] === '-h') {
      console.log(usage());
      return;
    } else throw new Error(`未知参数: ${args[i]}\n${usage()}`);
  }

  const html = readFileSync(join(FRONTEND_DIR, 'index.html'), 'utf8');
  const css = readFileSync(join(FRONTEND_DIR, 'css', 'style.css'), 'utf8');
  const svg = buildStandaloneSvg(extractLogoSvg(html), readAccentColor(css));
  const renderHtml = buildRenderHtml(svg);

  const byPlaywright = await renderWithPlaywright(renderHtml, outFile);
  if (!byPlaywright) renderWithChromiumCli(renderHtml, outFile);

  const info = verifyPng(outFile);
  console.log(`已生成 ${outFile}（${info.width}x${info.height}，不透明占比 ${(info.opaqueRatio * 100).toFixed(1)}%）`);
}

// 直接执行入口；被 import 时仅暴露纯函数供测试
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error(`[render-logo-icon] 失败: ${err.message}`);
    process.exitCode = 1;
  });
}

export {
  buildRenderHtml,
  buildStandaloneSvg,
  decodePng,
  extractLogoSvg,
  findCachedChromium,
  readAccentColor,
  verifyPng,
};
