/**
 * simulator-contracts 契约锁（C8 单一来源 — 常量断言 + file 安全判据纯函数矩阵）。
 *
 * 锁的内容：
 *   1. 静态目录（SIM_DIR）与清单 URL（MANIFEST_URL）：与迁移前两视图本地字面量
 *      逐字等价（'simulators' / 'simulators/manifest.json'），且 MANIFEST_URL
 *      由 SIM_DIR 派生（非独立硬编码 — 改目录只改一处）；
 *   2. 加载超时毫秒数（TIMEOUT_MS = 15000）与清单域超时文案（TIMEOUT_REASON）：
 *      文案与 spec 逐字一致，且文案中秒数由 TIMEOUT_MS 派生（非硬编码 15 —
 *      改毫秒数必改文案秒数）；
 *   3. isValidSimulatorFile 纯函数矩阵：非空字符串 + 不含 / \ % #（等价迁移前
 *      simulator-view.js 内联判据；# 为 URL fragment 分隔符，iframe src 截断
 *      防线）；null / undefined / 数字 / 空串 → false；
 *      'a.html' → true；含路径分隔符 / 百分号编码 / # → false。
 *
 * 本测试文件是契约锁的锚点：产品代码（simulator-contracts.js 之外）不得再出现
 * 模拟器域常量字面量 / file 判据内联实现（运行视图与列表视图均须 import 本模块）。
 */
import { describe, it, expect } from 'vitest';
import {
    SIM_DIR,
    MANIFEST_URL,
    TIMEOUT_MS,
    TIMEOUT_REASON,
    isValidSimulatorFile,
    __all__,
} from '../js/simulator-contracts.js';

// 契约锁锚点：迁移前两视图本地副本的一致值（仅测试文件持有，产品代码不得复制）
const LEGACY_SIM_DIR = 'simulators';
const LEGACY_MANIFEST_URL = 'simulators/manifest.json';
const LEGACY_TIMEOUT_MS = 15000;
const LEGACY_TIMEOUT_REASON = '模拟器清单加载超时（15 秒未收到响应）';

describe('simulator-contracts 常量契约（C8 单一来源）', () => {
    it('SIM_DIR 与迁移前运行视图字面量逐字等价', () => {
        expect(SIM_DIR).toBe(LEGACY_SIM_DIR);
    });

    it('MANIFEST_URL 与迁移前列表视图字面量逐字等价，且由 SIM_DIR 派生', () => {
        expect(MANIFEST_URL).toBe(LEGACY_MANIFEST_URL);
        // 派生关系锁：改 SIM_DIR 必联动 MANIFEST_URL（非独立硬编码副本）
        expect(MANIFEST_URL).toBe(`${SIM_DIR}/manifest.json`);
    });

    it('TIMEOUT_MS 与迁移前两视图字面量逐字等价（15000）', () => {
        expect(TIMEOUT_MS).toBe(LEGACY_TIMEOUT_MS);
    });

    it('TIMEOUT_REASON 与迁移前列表视图文案逐字等价，且秒数由 TIMEOUT_MS 派生', () => {
        expect(TIMEOUT_REASON).toBe(LEGACY_TIMEOUT_REASON);
        // 派生关系锁：文案中秒数 = TIMEOUT_MS/1000（改毫秒数必改文案秒数，非硬编码 15）
        expect(TIMEOUT_REASON).toContain(`${TIMEOUT_MS / 1000} 秒未收到响应`);
    });
});

describe('isValidSimulatorFile — file 安全判据纯函数', () => {
    // ── 非法输入（Falsify：任意类型不得炸，一律 false）──
    it('null → false', () => {
        expect(isValidSimulatorFile(null)).toBe(false);
    });

    it('undefined → false', () => {
        expect(isValidSimulatorFile(undefined)).toBe(false);
    });

    it('数字 → false', () => {
        expect(isValidSimulatorFile(42)).toBe(false);
    });

    it('空串 → false', () => {
        expect(isValidSimulatorFile('')).toBe(false);
    });

    it('布尔 / 对象 / 数组 → false（Falsify 防御）', () => {
        expect(isValidSimulatorFile(true)).toBe(false);
        expect(isValidSimulatorFile({})).toBe(false);
        expect(isValidSimulatorFile([])).toBe(false);
    });

    // ── happy path ──
    it("'a.html' → true（合法游戏文件名）", () => {
        expect(isValidSimulatorFile('a.html')).toBe(true);
    });

    it('中文文件名 → true（manifest 真实资产形态）', () => {
        expect(isValidSimulatorFile('人生模拟器v3.html')).toBe(true);
    });

    // ── iframe src 注入守卫（等价迁移前运行视图内联判据）──
    it("'a/b.html'（含 / 路径分隔符）→ false", () => {
        expect(isValidSimulatorFile('a/b.html')).toBe(false);
    });

    it("'a\\\\b.html'（含 \\ 路径分隔符）→ false", () => {
        expect(isValidSimulatorFile('a\\b.html')).toBe(false);
    });

    it("'a%b.html'（含百分号编码）→ false", () => {
        expect(isValidSimulatorFile('a%b.html')).toBe(false);
    });

    it("'a#b.html'（含 # fragment 分隔符）→ false", () => {
        expect(isValidSimulatorFile('a#b.html')).toBe(false);
    });
});

describe('simulator-contracts __all__ 协议表面', () => {
    it('__all__ 收口全部常量与纯函数', () => {
        expect(__all__.sort()).toEqual([
            'MANIFEST_URL',
            'SIM_DIR',
            'TIMEOUT_MS',
            'TIMEOUT_REASON',
            'isValidSimulatorFile',
        ]);
    });
});
