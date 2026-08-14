#!/usr/bin/env node
/**
 * Conver System — 模拟器模块端到端冒烟（U7-T5，Playwright）
 *
 * 覆盖真实用户路径（spec U7「端到端冒烟」验收，T4 选择器清单复用）：
 *   入口（侧栏模拟器导航）→ 列表 22 卡 + 计数 → 类型筛选（AI 驱动 / 全部）
 *   → 预置 openai 凭证 → 打开 AI 游戏（提示条 + iframe 加载 + 游戏内配置
 *     面板控件可见）→ SIM-API-1 配置同步（load 自动同步已填主应用
 *     key/endpoint/model：端点按 manifest endpointMode 口径转换 / 受管
 *     model option 追加 → 点击「重新同步」手动路径「已填入」→ 游戏自身
 *     保存路径接受注入值 → 恢复原设置）
 *   → 返回列表（iframe 卸载）→ 重进游戏 localStorage 存档保留
 *   → 运行中再点导航回列表（TD-53：再点侧栏「模拟器」= 返回列表，
 *     iframe 卸载、列表面板恢复，与「返回」同语义）
 *   → 纯本地游戏路径（manifest 驱动：无 local 条目时 SKIP 并报偏离说明）
 *   → 存档面板（U9-T2）：导出 → 清档 → 导入恢复（localStorage 键值断言）。
 *
 * 运行前提（后端静态托管在线 — spec：后端零改动，静态挂载已覆盖）：
 *   .venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
 *   脚本启动时探测 BASE URL：后端已在运行 → 复用且冒烟结束后不停止；
 *   未运行 → 自动拉起 uvicorn（退出时 taskkill /T /F 树杀 + netstat 复核
 *   端口无 LISTENING）。参考先例：scripts/smoke-desktop.ps1 的端口限定
 *   启停纪律（ARC9-T05：清理按端口判据，绝不按全局进程名）。
 *
 * 用法：
 *   node scripts/smoke-simulators.mjs [--base-url http://127.0.0.1:8000]
 *                                     [--no-start] [--backend-timeout 60]
 *   --base-url        后端地址（默认 http://127.0.0.1:8000；端口随地址变化）
 *   --no-start        后端未运行时不自动拉起，直接报错（运行前提由调用方保证）
 *   --backend-timeout 自动拉起后端的最长就绪等待秒数（默认 60）
 *   环境变量：
 *     CONVER_SMOKE_PYTHON  自动拉起后端时使用的 python 可执行文件
 *                          （默认 <仓库根>/.venv/Scripts/python.exe）
 *     CONVER_PLAYWRIGHT    playwright 包 index.mjs 的绝对路径
 *                          （默认按仓库布局解析 frontend/node_modules）
 *
 * 退出码：0 全部通过（含 SKIP 偏离）；1 任一步骤/清理失败；2 环境失败
 *   （playwright 缺失 / 后端无法就绪 / manifest 不可读 / 浏览器无法启动）。
 *
 * 冒烟纪律：
 *   - 全链路真实请求，不做任何 mock/请求拦截（glob 通配陷阱不适用——本脚本
 *     不拦截请求；若未来引入拦截须注意：形如「** 通配 + /api/chats/**」的
 *     拦截模式不会匹配裸路径 /api/chats，尾斜杠差异需显式处理）。
 *   - 后端启停：仅停止本脚本拉起的进程（按 PID 树杀）；复用实例绝不停止；
 *     停止后 netstat -ano 复核目标端口无 LISTENING（先于启动的空闲预检，
 *     端口判据安全）。
 *   - localStorage 探针：写入游戏前缀下的探针键，验证后删除（不留痕）。
 *   - settings 预置/恢复（U8-T2 注入段）：预置 smoke key 后**不**在预置步骤内
 *     恢复 —— 恢复统一在全部步骤结束后执行（main 尾部）。原因：get_all 只回读
 *     DB 已存在的键、set_many 只增改不删，步骤内恢复会让 DB 残留 smoke key
 *     污染后续运行；恢复过早则点击步骤拿到回退链（.env/残留）旧 key，注入
 *     保存路径断言必挂。恢复时对快照缺失/冒烟残留键显式置空（空串与无键对
 *     解析链行为等价），用户真实配置保留。
 *
 * 桌面壳复核：本脚本覆盖网页版链路；桌面壳（tauri dev + WebView2 CDP）
 * 为一次性复核流程（见工单 U7-T5），不固化进本脚本。
 */

import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { SAVE_KEY_META_RE } from '../frontend/js/save-key-meta.js';

// ══════════════════════════════════════════════════
// 常量与路径
// ══════════════════════════════════════════════════

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.dirname(SCRIPT_DIR);

const DEFAULT_BASE_URL = 'http://127.0.0.1:8000';
/** 单步元素等待超时（游戏文件 50~330KB，本地静态托管秒级完成） */
const WAIT_MS = 10000;
/** 后端就绪探测单次请求超时 */
const PROBE_MS = 5000;
/** AI 游戏提示条固定文案（spec 逐字，与 simulator-view.js HINT_AI 一致） */
const HINT_AI = '此游戏需自行配置 AI 接口';
/** spec 契约：入包模拟器总款数（与 T2 数据完整性测试同源） */
const EXPECTED_TOTAL = 22;
/** 「重新同步」按钮初始文案（与 key-injector.js TEXT_RESYNC 一致） */
const TEXT_RESYNC = '重新同步';
/** 注入成功反馈文案（与 key-injector.js TEXT_INJECTED 一致） */
const TEXT_INJECTED = '已填入';
// 正则元字符集（存档面板种子键须选精确键）：单一来源 frontend/js/save-key-meta.js
// （契约之家，TD-67/68）—— SAVE_KEY_META_RE 由上方 import 消费，本脚本不持副本。

/** 环境失败（退出码 2）：运行前提缺失，非被测应用缺陷 */
class EnvError extends Error {}

/** 步骤结果收集（逐步 PASS/FAIL/SKIP 清单） */
const results = [];
function record(name, status, detail) {
    results.push({ name, status, detail });
    console.log(`[${status}] ${name}：${detail}`);
}

function logEnv(msg) {
    console.log(`[ENV] ${msg}`);
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

// ══════════════════════════════════════════════════
// 命令行参数与 playwright / python 解析
// ══════════════════════════════════════════════════

function parseArgs(argv) {
    const args = {};
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (!a.startsWith('--')) continue;
        const eq = a.indexOf('=');
        const key = eq === -1 ? a.slice(2) : a.slice(2, eq);
        const val = eq === -1 ? argv[i + 1] : a.slice(eq + 1);
        args[key] = val === undefined ? true : val;
        if (eq === -1) i++;
    }
    return args;
}

/** 解析 playwright 模块（ESM 动态导入；无依赖文件路径可读错误） */
async function loadPlaywright() {
    const candidates = [];
    if (process.env.CONVER_PLAYWRIGHT) {
        candidates.push(path.resolve(process.env.CONVER_PLAYWRIGHT));
    }
    // 从脚本目录向上找 node_modules/playwright（覆盖仓库根 / 前端目录安装）
    let dir = SCRIPT_DIR;
    for (;;) {
        candidates.push(path.join(dir, 'node_modules', 'playwright', 'index.mjs'));
        const parent = path.dirname(dir);
        if (parent === dir) break;
        dir = parent;
    }
    // 仓库约定布局：frontend/ 的 devDependencies 含 playwright（package.json）
    candidates.push(path.join(ROOT, 'frontend', 'node_modules', 'playwright', 'index.mjs'));

    const tried = [];
    for (const c of candidates) {
        tried.push(c);
        if (fs.existsSync(c)) {
            const mod = await import(pathToFileURL(c).href);
            if (mod.chromium) return mod;
        }
    }
    throw new EnvError(
        `未找到 playwright 模块。已尝试：\n  ${tried.join('\n  ')}\n` +
        `修复：在 frontend/ 下执行 npm install（devDependencies 含 playwright），\n` +
        `或设置 CONVER_PLAYWRIGHT 指向 playwright 包的 index.mjs。`
    );
}

/** 解析自动拉起后端使用的 python（env 覆盖 > 仓库 .venv > PATH） */
function resolvePython() {
    if (process.env.CONVER_SMOKE_PYTHON) return path.resolve(process.env.CONVER_SMOKE_PYTHON);
    const win = path.join(ROOT, '.venv', 'Scripts', 'python.exe');
    const posix = path.join(ROOT, '.venv', 'bin', 'python');
    if (fs.existsSync(win)) return win;
    if (fs.existsSync(posix)) return posix;
    return 'python';
}

// ══════════════════════════════════════════════════
// 后端就绪 / 启停 / 端口复核（端口限定判据，ARC9-T05）
// ══════════════════════════════════════════════════

/** 探测后端是否就绪（GET manifest 静态文件，200 即视为在线） */
async function backendReady(baseUrl, timeoutMs) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        try {
            const res = await fetch(`${baseUrl}/simulators/manifest.json`, {
                signal: AbortSignal.timeout(PROBE_MS),
            });
            if (res.ok) return true;
        } catch {
            // 未就绪，继续轮询
        }
        await sleep(500);
    }
    return false;
}

/** netstat 中监听指定端口的行（Windows netstat 状态词固定英文 LISTENING） */
function netstatLines(port) {
    const out = spawnSync('netstat', ['-ano'], { encoding: 'utf8' });
    if (out.error) return [];
    const re = new RegExp(`:${port}\\b`);
    return out.stdout
        .split(/\r?\n/)
        .filter((l) => /LISTENING/.test(l) && re.test(l));
}

/** 监听指定端口的 PID 列表（去重） */
function netstatPids(port) {
    return [...new Set(
        netstatLines(port)
            .map((l) => l.trim().split(/\s+/).pop())
            .filter(Boolean),
    )];
}

async function waitPortFree(port, timeoutMs) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        if (netstatLines(port).length === 0) return true;
        await sleep(300);
    }
    return netstatLines(port).length === 0;
}

/** 按 PID 树杀（Windows taskkill /T /F；POSIX 进程组兜底） */
function killTree(pid) {
    if (process.platform === 'win32') {
        spawnSync('taskkill', ['/pid', String(pid), '/T', '/F'], { stdio: 'ignore' });
    } else {
        try {
            process.kill(-pid, 'SIGKILL');
        } catch {
            try {
                process.kill(pid, 'SIGKILL');
            } catch {
                // 进程已不存在
            }
        }
    }
}

/**
 * 确保后端在线。返回 { reuse: true } 或 { pid, port }。
 * 自动拉起失败时清理自身进程并抛出可读 EnvError（附手动启动命令与 stderr 尾部）。
 */
async function ensureBackend(baseUrl, noStart, backendTimeoutMs) {
    if (await backendReady(baseUrl, PROBE_MS + 1000)) {
        logEnv(`后端已在线：${baseUrl}（复用运行实例，冒烟结束时不停止）`);
        return { reuse: true };
    }
    if (noStart) {
        throw new EnvError(
            `后端未运行（${baseUrl} 不可达）且指定了 --no-start。请先启动：\n` +
            `  ${resolvePython()} -m uvicorn backend.app.main:app --host ${new URL(baseUrl).hostname} --port ${new URL(baseUrl).port}\n` +
            `（或去掉 --no-start 让脚本自动拉起）`
        );
    }

    const url = new URL(baseUrl);
    const python = resolvePython();
    logEnv(`后端未运行，自动拉起 uvicorn（${python} -m uvicorn backend.app.main:app --port ${url.port}）`);
    const child = spawn(
        python,
        ['-m', 'uvicorn', 'backend.app.main:app', '--host', url.hostname, '--port', url.port],
        { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true },
    );
    const outBuf = [];
    const errBuf = [];
    child.stdout.on('data', (d) => {
        outBuf.push(d.toString());
        if (outBuf.length > 40) outBuf.shift();
    });
    child.stderr.on('data', (d) => {
        errBuf.push(d.toString());
        if (errBuf.length > 40) errBuf.shift();
    });
    let exited = null;
    child.on('exit', (code, sig) => {
        exited = { code, sig };
    });
    child.on('error', (err) => {
        exited = { error: err };
    });

    const ready = await backendReady(baseUrl, backendTimeoutMs);
    if (!ready) {
        killTree(child.pid);
        const why = exited
            ? (exited.error ? `spawn 失败：${exited.error.message}`
                : `进程提前退出（code=${exited.code}）`)
            : `就绪超时（${backendTimeoutMs / 1000}s 内未收到 manifest 响应）`;
        const tail = [...errBuf, ...outBuf].join('').trim().split('\n').slice(-8).join('\n');
        throw new EnvError(
            `自动拉起后端失败：${why}。\n请手动启动排查：\n` +
            `  ${python} -m uvicorn backend.app.main:app --host ${url.hostname} --port ${url.port}\n` +
            `子进程输出尾部：\n${tail}`
        );
    }
    logEnv(`后端就绪：${baseUrl}（本脚本拉起 pid=${child.pid}，冒烟结束将停止并复核端口）`);
    return { pid: child.pid, port: Number(url.port) };
}

/** 停止本脚本拉起的后端：树杀 → 端口无 LISTENING 复核（失败补杀残留 PID） */
async function stopBackend(handle) {
    logEnv(`停止本脚本拉起的 uvicorn（pid=${handle.pid}，taskkill /T /F 树杀）`);
    killTree(handle.pid);
    if (await waitPortFree(handle.port, 10000)) {
        record('清理：端口释放', 'PASS', `端口 ${handle.port} 无 LISTENING（netstat 复核）`);
        return;
    }
    // 端口在本脚本启动前为空闲，此刻监听者只能是本次拉起的残留 —— 定向补杀
    const pids = netstatPids(handle.port);
    for (const p of pids) killTree(p);
    if (await waitPortFree(handle.port, 5000)) {
        record('清理：端口释放', 'PASS', `补杀残留 pid=${pids.join(', ')} 后端口 ${handle.port} 无 LISTENING`);
        return;
    }
    record('清理：端口释放', 'FAIL', `端口 ${handle.port} 仍有 LISTENING（netstat 原始行）：\n${netstatLines(handle.port).join('\n')}`);
}

/** 读取 manifest（数据驱动断言基准；失败视为环境失败） */
async function fetchManifest(baseUrl) {
    try {
        const res = await fetch(`${baseUrl}/simulators/manifest.json`, {
            signal: AbortSignal.timeout(PROBE_MS),
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (!data || !Array.isArray(data.simulators)) {
            throw new Error('manifest 顶层缺少 simulators 数组');
        }
        return data;
    } catch (err) {
        throw new EnvError(
            `读取 manifest 失败（${baseUrl}/simulators/manifest.json）：${err.message}\n` +
            `请确认后端静态托管在线（模拟器静态目录由根挂载覆盖）。`
        );
    }
}

// ══════════════════════════════════════════════════
// 断言助手（失败消息定位到步骤与期望值）
// ══════════════════════════════════════════════════

async function waitVisible(locator, timeoutMs, label) {
    try {
        await locator.waitFor({ state: 'visible', timeout: timeoutMs });
    } catch (err) {
        throw new Error(`${label}：等待可见超时（${timeoutMs}ms）—— ${String(err.message).split('\n')[0]}`);
    }
}

async function waitForCount(locator, expected, timeoutMs, label) {
    const start = Date.now();
    let last = -1;
    while (Date.now() - start < timeoutMs) {
        last = await locator.count();
        if (last === expected) return last;
        await sleep(100);
    }
    throw new Error(`${label}：期望 ${expected} 个元素，超时前最后观察到 ${last}（等待 ${timeoutMs}ms）`);
}

async function waitForText(locator, expected, timeoutMs, label) {
    const start = Date.now();
    let last = '';
    while (Date.now() - start < timeoutMs) {
        last = (await locator.innerText().catch(() => '')).trim();
        if (last === expected) return last;
        await sleep(100);
    }
    throw new Error(`${label}：期望文本「${expected}」，超时前最后读到「${last}」（等待 ${timeoutMs}ms）`);
}

/** 等待游戏 iframe 加载完成（按 file 名匹配 frame URL），返回该 frame */
async function waitForGameFrame(page, fileName, timeoutMs) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const frame = page.frames().find((f) => {
            if (f === page.mainFrame()) return false;
            try {
                return decodeURIComponent(f.url()).includes(fileName);
            } catch {
                return false;
            }
        });
        if (frame) return frame;
        await sleep(100);
    }
    throw new Error(`等待游戏 iframe 加载超时（${timeoutMs}ms）：未发现 src 含「${fileName}」的 frame`);
}

/** 等待视图元素满足谓词（true 为止） */
async function waitForCondition(predicate, timeoutMs, label) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        if (await predicate()) return;
        await sleep(100);
    }
    throw new Error(`${label}：条件在 ${timeoutMs}ms 内未满足`);
}

/** 运行单个冒烟步骤：fn 返回详情文本（PASS）或 { skip }（SKIP）；抛错 → FAIL */
async function runStep(name, fn) {
    let out;
    try {
        out = await fn();
    } catch (err) {
        record(name, 'FAIL', err instanceof Error ? err.message : String(err));
        return;
    }
    if (out && typeof out === 'object' && out.skip) {
        record(name, 'SKIP', out.skip);
    } else {
        record(name, 'PASS', out === undefined ? '' : String(out));
    }
}

// ══════════════════════════════════════════════════
// 冒烟步骤（真实用户路径，T4 选择器清单）
// ══════════════════════════════════════════════════

async function smokeSteps(page, manifest, baseUrl) {
    const total = manifest.simulators.length;
    const aiGames = manifest.simulators.filter((g) => g.type === 'ai');
    const localGames = manifest.simulators.filter((g) => g.type === 'local');
    const aiGame = manifest.simulators.find((g) => g.id === 'life-sim') ?? aiGames[0];
    if (!aiGame) throw new EnvError('manifest 中无 AI 游戏条目，无法执行冒烟主路径');

    // 1. 入口：侧栏「模拟器」导航
    await runStep('入口：侧栏模拟器导航', async () => {
        const nav = page.locator('.nav-btn[data-view="simulators"]');
        await waitVisible(nav, WAIT_MS, '侧栏「模拟器」按钮');
        await nav.click();
        await waitForCondition(
            () => page.evaluate(() => document.querySelector('#view-simulators')?.classList.contains('active') ?? false),
            WAIT_MS,
            '点击导航后 #view-simulators 未获得 active 类（视图切换失败）',
        );
        return '按钮可见可点，点击后模拟器视图激活';
    });

    // 2. 列表：卡片数 + 计数（与 manifest 条数一致）
    await runStep('列表：卡片数与计数', async () => {
        if (total !== EXPECTED_TOTAL) {
            throw new Error(`spec 契约断言：manifest 应恰 ${EXPECTED_TOTAL} 条，实际 ${total} 条（manifest 变更须同步更新本脚本）`);
        }
        const cards = page.locator('.sim-card');
        await waitForCount(cards, total, WAIT_MS, '列表卡片');
        const countText = await waitForText(page.locator('.sim-count'), `共 ${total} 款`, WAIT_MS, '列表计数');
        return `卡片 ${total} 张，计数「${countText}」（与 manifest ${total} 条一致）`;
    });

    // 3. 筛选：AI 驱动 → 切回全部
    await runStep('筛选：AI 驱动档', async () => {
        const aiBtn = page.locator('.sim-filter-btn[data-filter="ai"]');
        await waitVisible(aiBtn, WAIT_MS, '「AI 驱动」筛选按钮');
        await aiBtn.click();
        await waitForCount(page.locator('.sim-card'), aiGames.length, WAIT_MS, 'AI 筛选后卡片');
        const t = await waitForText(page.locator('.sim-count'), `共 ${aiGames.length} 款`, WAIT_MS, 'AI 筛选后计数');
        return `卡片 ${aiGames.length} 张（manifest ai 数），计数「${t}」`;
    });
    await runStep('筛选：切回全部档', async () => {
        await page.locator('.sim-filter-btn[data-filter="all"]').click();
        await waitForCount(page.locator('.sim-card'), total, WAIT_MS, '切回全部后卡片');
        const t = await waitForText(page.locator('.sim-count'), `共 ${total} 款`, WAIT_MS, '切回全部后计数');
        return `卡片恢复 ${total} 张，计数「${t}」`;
    });

    // 4. 预置 openai 凭证（SIM-API-1：先于打开游戏 — load 自动同步需要
    // openai 凭证在 iframe load 时已就位；与旧「点击注入」流程顺序相反）。
    // 预置步骤负责写入 smoke key + 端点 + 默认模型并复核凭证端点；恢复原
    // 设置延迟到全部步骤结束后（main 尾部）执行 —— 若过早恢复，自动同步
    // 会拿到回退链（.env / 残留）的旧 key，注入保存路径断言必挂；且
    // get_all 只回读 DB 已存在的键、set_many 只增改不删，过早恢复还会让
    // DB 残留 smoke key 污染后续运行。
    const smokeApiKey = `sk-smoke-u8t2-${Date.now()}`;
    let preloadedSettings = null;
    await runStep('注入：预置 openai 凭证（settings 写入 + 凭证端点复核）', async () => {
        const getRes = await fetch(`${baseUrl}/api/settings`, { signal: AbortSignal.timeout(PROBE_MS) });
        if (!getRes.ok) throw new Error(`读取现有设置失败 HTTP ${getRes.status}`);
        preloadedSettings = await getRes.json();
        const put = await fetch(`${baseUrl}/api/settings`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ...preloadedSettings,
                openai_api_key: smokeApiKey,
                openai_base_url: 'https://api.smoke-test.com/v1', // 端点口径转换断言确定性
                default_provider: 'openai',
                default_model: 'smoke-test-model',
            }),
        });
        if (!put.ok) throw new Error(`预置 openai_api_key 失败 HTTP ${put.status}`);
        const creds = await (await fetch(`${baseUrl}/api/settings/credentials`, { signal: AbortSignal.timeout(PROBE_MS) })).json();
        if (creds.protocol !== 'openai' || !creds.key) {
            throw new Error(`凭证端点未返回 openai 凭证（protocol=${creds.protocol}）—— 预置未生效`);
        }
        return `openai_api_key 已预置（${smokeApiKey.slice(0, 12)}…），凭证端点 protocol=openai`;
    });

    // 5. 打开 AI 游戏：提示条 + iframe 加载 + 游戏内配置面板控件（manifest config 三元组）
    await runStep(`打开 AI 游戏：${aiGame.name}`, async () => {
        const card = page.locator(`.sim-card[data-id="${aiGame.id}"]`);
        await waitVisible(card, WAIT_MS, `卡片 ${aiGame.id}`);
        await card.click();
        await waitVisible(page.locator('.sim-run-hint'), WAIT_MS, 'AI 提示条');
        const hint = (await page.locator('.sim-run-hint').innerText()).trim();
        if (hint !== HINT_AI) {
            throw new Error(`提示条文案不符：期望「${HINT_AI}」，实际「${hint}」`);
        }
        await waitVisible(page.locator('.sim-run-frame'), WAIT_MS, '游戏 iframe（load 后可见）');
        await waitForGameFrame(page, aiGame.file, WAIT_MS);
        const cfg = aiGame.config ?? {};
        const ids = [cfg.endpoint, cfg.apikey, cfg.model].filter(Boolean);
        if (ids.length !== 3) {
            throw new Error(`manifest 条目 ${aiGame.id} 缺少完整 config 三元组（endpoint/apikey/model）—— T2 数据契约被破坏`);
        }
        for (const id of ids) {
            await waitVisible(
                page.frameLocator('.sim-run-frame').locator(`#${id}`),
                WAIT_MS,
                `游戏内配置控件 #${id}`,
            );
        }
        return `提示条「${hint}」可见；iframe 已加载（${aiGame.file}）；配置面板控件 ${ids.join(' / ')} 可见`;
    });

    // 6. 配置同步（SIM-API-1）：load 自动同步已填值（端点口径转换 + 受管
    // model option）→ 点击「重新同步」手动路径 → 游戏自身保存路径接受注入值
    await runStep('配置同步：load 自动同步 + 手动重新同步（SIM-API-1）', async () => {
        const creds = await (await fetch(`${baseUrl}/api/settings/credentials`, { signal: AbortSignal.timeout(PROBE_MS) })).json();
        if (creds.protocol !== 'openai' || !creds.key) {
            throw new Error(`凭证端点未返回 openai 凭证（protocol=${creds.protocol}）`);
        }

        const frame = await waitForGameFrame(page, aiGame.file, WAIT_MS);
        const cfg = aiGame.config ?? {};
        const details = [];

        // load 自动同步是异步的（load 后取凭证）→ 以 apikey 填值为就绪信号等待
        await waitForCondition(
            async () => (await frame.locator(`#${cfg.apikey}`).inputValue()) === creds.key,
            WAIT_MS,
            'load 自动同步未生效（apikey 未填主应用 key）',
        );
        details.push(`load 自动同步已生效：#${cfg.apikey} = 主应用 key`);

        // 端点口径按 manifest endpointMode 转换（凭证端点恒为 base URL）
        if (creds.endpoint) {
            const expectedEndpoint = aiGame.endpointMode === 'full'
                ? `${creds.endpoint.replace(/\/+$/, '')}/chat/completions`
                : creds.endpoint.replace(/\/+$/, '');
            const epVal = await frame.locator(`#${cfg.endpoint}`).inputValue();
            if (epVal !== expectedEndpoint) {
                throw new Error(`端点口径转换失败：期望「${expectedEndpoint}」（endpointMode=${aiGame.endpointMode}），实际「${epVal}」`);
            }
            details.push(`endpoint 已按 ${aiGame.endpointMode} 口径转换（${epVal}）`);
        } else {
            details.push('endpoint 为空 → 保持游戏默认（口径转换未断言）');
        }

        // 模型名取自主应用设置（默认模型）：select 缺目标 option → 受管 option 追加
        const modelLoc = frame.locator(`#${cfg.model}`);
        const mVal = await modelLoc.inputValue();
        const tag = await modelLoc.evaluate((el) => el.tagName);
        if (tag === 'SELECT') {
            const opts = await modelLoc.locator('option').evaluateAll((els) => els.map((o) => o.value));
            if (mVal !== creds.model) {
                throw new Error(`model 未同步：期望「${creds.model}」，实际「${mVal}」`);
            }
            if (!opts.includes(creds.model)) {
                throw new Error(`受管 option 缺失：select 已选中「${creds.model}」但选项集无此项（宿主未追加受管 option）`);
            }
            details.push(`model 已同步（${creds.model}；受管 option 已追加，选项集 ${opts.length} 项）`);
        } else {
            if (mVal !== creds.model) {
                throw new Error(`model 未同步：期望「${creds.model}」，实际「${mVal}」`);
            }
            details.push(`model 已同步（${creds.model}）`);
        }

        // 手动重新同步路径：按钮「重新同步」→「已填入」反馈 → 值幂等保持
        const btn = page.locator('.sim-key-btn');
        await waitVisible(btn, WAIT_MS, '「重新同步」按钮');
        if ((await btn.innerText()).trim() !== TEXT_RESYNC) {
            throw new Error(`按钮文案不符：期望「${TEXT_RESYNC}」，实际「${(await btn.innerText()).trim()}」`);
        }
        await btn.click();
        await waitForText(btn, TEXT_INJECTED, WAIT_MS, '按钮「已填入」反馈');
        details.push('手动「重新同步」点击 → 「已填入」反馈（值幂等保持）');

        // 可发起对话：走游戏自身保存路径（cfg-* 族保存按钮落盘 — 注入值经游戏
        // 自身读取链路进入其聊天配置；life-sim 保存路径已知，其它游戏无统一
        // 保存入口 → 该断言 SKIP 并报偏离说明，由单测覆盖）
        if (aiGame.id === 'life-sim') {
            const saved = await frame.evaluate(() => {
                LS.saveApiConfig();
                return localStorage.getItem('ls_cfg') ?? '';
            });
            if (!saved.includes(smokeApiKey)) {
                throw new Error('游戏自身保存路径未接受注入 key（ls_cfg 未含 smoke key）—— 可对话性未达');
            }
            details.push('游戏保存路径接受注入值（ls_cfg 已含 key，可直接对话）');
        } else {
            details.push(`游戏 ${aiGame.id} 非 life-sim — 保存路径断言 SKIP（单测覆盖）`);
        }
        return details.join('；');
    });

    // 7. 存档保留：游戏内写探针 → 返回（iframe 卸载）→ 重进 → 探针仍在 → 清理
    // 探针键前缀固定 'smoke_'（TD-48 关闭配套清理：manifest 已 v2 化无
    // saveKeyPrefix 字段，遗留表达式移除；键不在任何 saveKeys 白名单内，
    // 冒烟结束后删除不留痕）
    const probeKey = `smoke_u7t5_probe_${Date.now()}`;
    const probeValue = 'u7t5-smoke-probe';
    await runStep('存档保留：写探针 → 返回 → 重进 → 仍在', async () => {
        const frame = await waitForGameFrame(page, aiGame.file, WAIT_MS);
        const before = await frame.evaluate((k) => localStorage.getItem(k), probeKey);
        if (before !== null) {
            throw new Error(`探针键 ${probeKey} 在全新浏览器上下文（无痕）中应不存在，实际值「${before}」`);
        }
        await frame.evaluate(([k, v]) => localStorage.setItem(k, v), [probeKey, probeValue]);

        // 返回：运行面板隐藏、iframe 卸载、列表恢复
        const back = page.locator('.sim-run-back');
        await waitVisible(back, WAIT_MS, '返回按钮');
        await back.click();
        await waitForCondition(
            () => page.evaluate(() => {
                const run = document.querySelector('#simulator-run-panel');
                const list = document.querySelector('#simulator-list-panel');
                return run?.hasAttribute('hidden') === true
                    && list?.hasAttribute('hidden') === false;
            }),
            WAIT_MS,
            '点击返回后运行面板未隐藏 / 列表面板未恢复',
        );
        if ((await page.locator('.sim-run-frame').count()) !== 0) {
            throw new Error('返回后 iframe 未卸载（.sim-run-frame 仍存在）');
        }
        await waitForCount(page.locator('.sim-card'), total, WAIT_MS, '返回后列表卡片');

        // 重进 → 探针仍在（同源 localStorage 保留）
        await page.locator(`.sim-card[data-id="${aiGame.id}"]`).click();
        await waitVisible(page.locator('.sim-run-hint'), WAIT_MS, '重进后提示条');
        const frame2 = await waitForGameFrame(page, aiGame.file, WAIT_MS);
        const after = await frame2.evaluate((k) => localStorage.getItem(k), probeKey);
        if (after !== probeValue) {
            throw new Error(`重进后探针键丢失：期望「${probeValue}」，实际「${after}」（同源 localStorage 未保留）`);
        }
        await frame2.evaluate((k) => localStorage.removeItem(k), probeKey);

        // 返回列表（F2 修复）：步骤 5 若以重进后的运行面板状态结束，后续步骤
        // 会被卡住 —— 全 AI 时步骤 6 SKIP 不经过返回，步骤 7 在隐藏的列表
        // 面板内点击 .sim-save-manage-btn 触发 actionability 超时。故重进验证
        // 后显式返回列表（运行面板隐藏、列表卡片可见）再结束本步骤。
        const back2 = page.locator('.sim-run-back');
        await waitVisible(back2, WAIT_MS, '重进后返回按钮');
        await back2.click();
        await waitForCondition(
            () => page.evaluate(() => {
                const run = document.querySelector('#simulator-run-panel');
                const list = document.querySelector('#simulator-list-panel');
                return run?.hasAttribute('hidden') === true
                    && list?.hasAttribute('hidden') === false;
            }),
            WAIT_MS,
            '重进后返回：运行面板未隐藏 / 列表面板未恢复',
        );
        await waitForCount(page.locator('.sim-card'), total, WAIT_MS, '返回列表后列表卡片');
        return `探针键 ${probeKey} 重进后仍存在（同源 localStorage 保留），已清理探针；返回列表`;
    });

    // 7.5 运行中再点导航回列表（TD-53）：运行中的游戏再点侧栏「模拟器」
    // = 返回列表（iframe 卸载、列表面板恢复），与「返回」同语义；随后
    // 视图内重复进入仍走既有刷新语义（列表重新渲染）。
    await runStep('运行中再点导航：返回列表（TD-53）', async () => {
        const card = page.locator(`.sim-card[data-id="${aiGame.id}"]`);
        await waitVisible(card, WAIT_MS, `卡片 ${aiGame.id}`);
        await card.click();
        await waitVisible(page.locator('.sim-run-hint'), WAIT_MS, '运行中提示条');
        await waitForGameFrame(page, aiGame.file, WAIT_MS);
        if ((await page.locator('.sim-run-frame').count()) !== 1) {
            throw new Error(`前置：运行中 iframe 未就绪（.sim-run-frame 数量 ${await page.locator('.sim-run-frame').count()}）`);
        }

        const nav = page.locator('.nav-btn[data-view="simulators"]');
        await nav.click();

        await waitForCondition(
            () => page.evaluate(() => {
                const run = document.querySelector('#simulator-run-panel');
                const list = document.querySelector('#simulator-list-panel');
                return run?.hasAttribute('hidden') === true
                    && list?.hasAttribute('hidden') === false;
            }),
            WAIT_MS,
            '运行中再点导航后运行面板未隐藏 / 列表面板未恢复',
        );
        if ((await page.locator('.sim-run-frame').count()) !== 0) {
            throw new Error('运行中再点导航后 iframe 未卸载（.sim-run-frame 仍存在）');
        }
        // 视图内重复进入保持刷新语义：列表卡片重新渲染
        await waitForCount(page.locator('.sim-card'), total, WAIT_MS, '再点导航后列表卡片');
        return '运行中再点「模拟器」导航 → iframe 卸载、列表面板恢复（与「返回」同语义），列表已刷新';
    });

    // 8. 纯本地游戏：无提示条（manifest 驱动；全 AI 时 SKIP 并报偏离说明）
    await runStep('纯本地游戏：无提示条', async () => {
        if (localGames.length === 0) {
            return {
                skip: `manifest ${total}/${total} 全为 AI 驱动，无纯本地游戏可断言「无提示条」——` +
                    `按工单 U7-T5 申报偏离；local 分支（不渲染提示条）由 simulator-view.js 单测覆盖`,
            };
        }
        const g = localGames[0];
        const card = page.locator(`.sim-card[data-id="${g.id}"]`);
        await waitVisible(card, WAIT_MS, `本地游戏卡片 ${g.id}`);
        await card.click();
        await waitForGameFrame(page, g.file, WAIT_MS);
        if ((await page.locator('.sim-run-hint').count()) !== 0) {
            throw new Error(`纯本地游戏 ${g.id} 不应显示提示条，实际出现 ${(await page.locator('.sim-run-hint').count())} 个`);
        }
        await page.locator('.sim-run-back').click();
        await waitForCondition(
            () => page.evaluate(() => document.querySelector('#simulator-list-panel')?.hasAttribute('hidden') === false),
            WAIT_MS,
            '本地游戏返回后列表面板未恢复',
        );
        return `本地游戏 ${g.name}：iframe 加载成功且无提示条，返回列表正常`;
    });

    // 9. 存档面板：导出 → 清档（删除）→ 导入恢复（localStorage 断言）
    //    种子写入 saveKeys 白名单精确键 → 面板导出 Blob 下载 → 删除（确认弹窗）
    //    → 键清除 → 导入下载文件 → 键恢复 → 清理探针键。
    const saveGame = manifest.simulators.find((g) => Array.isArray(g.saveKeys)
        && g.saveKeys.some((k) => !SAVE_KEY_META_RE.test(k)));
    if (!saveGame) {
        throw new EnvError('manifest 无带精确键 saveKeys 的游戏条目，无法执行存档面板冒烟路径');
    }
    const saveKey = saveGame.saveKeys.find((k) => !SAVE_KEY_META_RE.test(k));
    const saveValue = '{"smoke":"u9t2-save-panel"}';
    await runStep(`存档面板：导出 → 清档 → 导入恢复（${saveGame.id}）`, async () => {
        // 种子：白名单精确键写入（全新浏览器上下文，键不存在）
        const seeded = await page.evaluate(([k, v]) => {
            const existed = localStorage.getItem(k);
            localStorage.setItem(k, v);
            return existed;
        }, [saveKey, saveValue]);
        if (seeded !== null) {
            throw new Error(`探针键 ${saveKey} 在全新浏览器上下文（无痕）中应不存在，实际值「${seeded}」`);
        }

        // 前置（F2 修复）：存档面板入口按钮（.sim-save-manage-btn）位于列表
        // 面板内 —— 步骤 7 末已返回列表，此处断言列表可见，防御未来步骤
        // 顺序变化再次踩 hidden 元素 actionability 超时
        await waitForCondition(
            () => page.evaluate(() => document.querySelector('#simulator-list-panel')?.hasAttribute('hidden') === false),
            WAIT_MS,
            '存档面板步骤前置：列表面板不可见（步骤顺序被破坏？）',
        );

        // 打开存档面板：列表隐藏、存档面板可见、游戏行含键数
        await page.locator('.sim-save-manage-btn').click();
        await waitVisible(page.locator('#simulator-save-panel'), WAIT_MS, '存档面板');
        await waitForCondition(
            () => page.evaluate(() => document.querySelector('#simulator-list-panel')?.hasAttribute('hidden') === true
                && document.querySelector('#simulator-save-panel')?.hasAttribute('hidden') === false),
            WAIT_MS,
            '打开存档面板后列表未隐藏 / 存档面板未显示',
        );
        const row = page.locator(`#simulator-save-panel .sim-save-game[data-id="${saveGame.id}"]`);
        await waitVisible(row, WAIT_MS, `存档面板游戏行 ${saveGame.id}`);
        await waitForCondition(
            () => row.locator('.sim-save-meta').innerText().then((t) => t.includes('1 个存档')).catch(() => false),
            WAIT_MS,
            '种子写入后游戏行键数未显示「1 个存档」',
        );

        // 导出：捕获 Blob 下载 → 断言 JSON 形状（game_id + 键值对，键值原样）
        const downloadPromise = page.waitForEvent('download');
        await row.locator('[data-action="export"]').click();
        const download = await downloadPromise;
        const dlPath = await download.path();
        if (!dlPath) throw new Error('导出下载未产生本地文件（download.path() 为空）');
        if (download.suggestedFilename() !== `${saveGame.id}-saves.json`) {
            throw new Error(`导出文件名不符：期望「${saveGame.id}-saves.json」，实际「${download.suggestedFilename()}」`);
        }
        const exported = JSON.parse(fs.readFileSync(dlPath, 'utf8'));
        if (exported.game_id !== saveGame.id) {
            throw new Error(`导出 game_id 不符：期望「${saveGame.id}」，实际「${exported.game_id}」`);
        }
        if (exported.keys[saveKey] !== saveValue) {
            throw new Error(`导出键值不符：期望 ${saveKey}=「${saveValue}」，实际「${exported.keys[saveKey]}」`);
        }

        // 清档：删除（确认弹窗）→ localStorage 键清除 + 行键数归零
        await row.locator('[data-action="delete"]').click();
        await waitVisible(page.locator('.modal-overlay .confirm-ok'), WAIT_MS, '删除确认弹窗');
        await page.locator('.modal-overlay .confirm-ok').click();
        await waitForCondition(
            () => page.evaluate((k) => localStorage.getItem(k) === null, saveKey),
            WAIT_MS,
            '删除确认后存档键未清除',
        );
        await waitForCondition(
            () => row.locator('.sim-save-meta').innerText().then((t) => t.includes('0 个存档')).catch(() => false),
            WAIT_MS,
            '删除后游戏行键数未归零',
        );

        // 导入恢复：文件选择器选择下载的导出文件 → 键恢复 + 行键数回 1
        const [chooser] = await Promise.all([
            page.waitForEvent('filechooser'),
            row.locator('[data-action="import"]').click(),
        ]);
        await chooser.setFiles(dlPath);
        await waitForCondition(
            () => page.evaluate(([k, expected]) => localStorage.getItem(k) === expected, [saveKey, saveValue]),
            WAIT_MS,
            '导入后存档键未恢复（localStorage 值不符）',
        );
        await waitForCondition(
            () => row.locator('.sim-save-meta').innerText().then((t) => t.includes('1 个存档')).catch(() => false),
            WAIT_MS,
            '导入后游戏行键数未回「1 个存档」',
        );

        // 清理探针键 + 返回列表（不留痕）
        await page.evaluate((k) => localStorage.removeItem(k), saveKey);
        await page.locator('#simulator-save-panel .sim-save-back').click();
        await waitForCondition(
            () => page.evaluate(() => document.querySelector('#simulator-save-panel')?.hasAttribute('hidden') === true
                && document.querySelector('#simulator-list-panel')?.hasAttribute('hidden') === false),
            WAIT_MS,
            '存档面板返回后列表未恢复',
        );
        return `导出 JSON（${exported.game_id}，${Object.keys(exported.keys).length} 键）→ 删除清档 → 导入恢复，localStorage 键值断言通过，探针已清理`;
    });

    return { preloadedSettings };
}

// ══════════════════════════════════════════════════
// 主流程
// ══════════════════════════════════════════════════

/** 冒烟预置 key 前缀（恢复时识别前轮残留，避免污染持续） */
const SMOKE_KEY_PREFIX = 'sk-smoke-u8t2-';

/**
 * 恢复预置步骤写入的设置（全部冒烟步骤结束后、后端停止前调用）。
 *
 * 预置新增键（openai_api_key / default_provider / default_model）在快照中
 * 缺失时显式置空：settings API 只增改不删（set_many 无删除语义），而空串与
 * 「无键」对解析链行为等价（get_value 空值回退默认 / .env）—— 不置空会让
 * DB 残留 smoke key，污染后续运行（凭证端点回传上一轮 key，注入保存路径
 * 断言必挂）。快照中若含冒烟残留（sk-smoke-u8t2- 前缀 key / smoke-test-model
 * 默认模型 —— 前轮预置未清干净的历史污染），同样置空；用户真实配置保留。
 * @param {string} baseUrl - 后端地址
 * @param {object} snapshot - 预置前 get_all 快照（smokeSteps 返回）
 * @returns {Promise<boolean>} 恢复成功为 true；失败已记录 [FAIL] 清理步骤
 */
async function restorePreloadedSettings(baseUrl, snapshot) {
    try {
        const body = { ...snapshot };
        const polluted = (typeof body.openai_api_key === 'string' && body.openai_api_key.startsWith(SMOKE_KEY_PREFIX))
            || body.default_model === 'smoke-test-model';
        for (const key of ['openai_api_key', 'default_provider', 'default_model']) {
            if (!(key in snapshot) || polluted) body[key] = '';
        }
        const put = await fetch(`${baseUrl}/api/settings`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        if (!put.ok) {
            record('清理：恢复预置设置', 'FAIL', `恢复失败 HTTP ${put.status}`);
            return false;
        }
        record('清理：恢复预置设置', 'PASS', `settings 已恢复（${polluted ? '含前轮残留已清除，' : ''}后端将停止）`);
        return true;
    } catch (err) {
        record('清理：恢复预置设置', 'FAIL', err instanceof Error ? err.message : String(err));
        return false;
    }
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const baseUrl = String(args['base-url'] ?? DEFAULT_BASE_URL);
    const noStart = args['no-start'] === true;
    const backendTimeoutMs = Number(args['backend-timeout'] ?? 60) * 1000;
    let url;
    try {
        url = new URL(baseUrl);
    } catch {
        throw new EnvError(`base-url 不是合法 URL：${baseUrl}（示例：http://127.0.0.1:8000）`);
    }
    if (!url.port) {
        throw new EnvError(`base-url 必须显式携带端口（当前 ${baseUrl}），端口缺失无法确定后端监听地址`);
    }
    if (!Number.isFinite(backendTimeoutMs) || backendTimeoutMs <= 0) {
        throw new EnvError(`--backend-timeout 必须是正数（当前值 ${args['backend-timeout']}）`);
    }
    logEnv(`目标：${baseUrl}（${url.hostname}:${url.port}）`);

    const { chromium } = await loadPlaywright();

    let backendHandle = null;
    try {
        backendHandle = await ensureBackend(baseUrl, noStart, backendTimeoutMs);

        const manifest = await fetchManifest(baseUrl);
        const aiCount = manifest.simulators.filter((g) => g.type === 'ai').length;
        const localCount = manifest.simulators.filter((g) => g.type === 'local').length;
        logEnv(`manifest：${manifest.simulators.length} 条（ai=${aiCount} / local=${localCount}）`);

        let browser;
        try {
            browser = await chromium.launch({ headless: true });
        } catch (err) {
            throw new EnvError(
                `浏览器启动失败：${String(err.message).split('\n')[0]}\n` +
                `若浏览器未安装：cd frontend && npx playwright install chromium`
            );
        }
        try {
            const context = await browser.newContext();
            const page = await context.newPage();
            const pageErrors = [];
            page.on('pageerror', (e) => pageErrors.push(`pageerror: ${e.message}`));
            page.on('console', (m) => {
                if (m.type() === 'error') pageErrors.push(`console.error: ${m.text()}`);
            });
            await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
            const stepOut = await smokeSteps(page, manifest, baseUrl);
            if (pageErrors.length > 0) {
                logEnv(`页面报错 ${pageErrors.length} 条（仅记录，不判失败）：\n${pageErrors.slice(0, 10).join('\n')}`);
            }
            await context.close();
            // 恢复预置设置（后端仍在线）：预置快照缺失（预置步骤未执行）→ 跳过
            if (stepOut?.preloadedSettings) {
                const ok = await restorePreloadedSettings(baseUrl, stepOut.preloadedSettings);
                if (!ok) process.exitCode = 1;
            }
        } finally {
            await browser.close();
        }
    } finally {
        if (backendHandle && !backendHandle.reuse) {
            await stopBackend(backendHandle);
        } else if (backendHandle) {
            logEnv('后端为运行前已存在实例，本脚本不停止');
        }
    }

    const fails = results.filter((r) => r.status === 'FAIL');
    const skips = results.filter((r) => r.status === 'SKIP');
    const passes = results.length - fails.length - skips.length;
    console.log(`\n结果：共 ${results.length} 项 — ${passes} PASS / ${fails.length} FAIL / ${skips.length} SKIP`);
    if (fails.length > 0) {
        console.log('存在失败项（见上方 [FAIL]），退出码 1');
        process.exitCode = 1;
    } else {
        console.log('全部通过，退出码 0');
    }
}

main().catch((err) => {
    console.error(`\n[ENV-FAIL] ${err instanceof Error ? err.message : String(err)}`);
    console.error('退出码 2（环境失败：运行前提缺失，非被测应用缺陷）');
    process.exitCode = 2;
});
