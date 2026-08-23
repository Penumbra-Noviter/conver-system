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
 *   4. 导入契约（工单 04）：IMPORT_URL 与后端 03 端点契约逐字一致
 *      （POST /api/simulators/import）；WARNING_LABELS 键集与后端
 *      SUSPICIOUS_PATTERNS 键集锚定一致（eval / document.cookie /
 *      cross-origin-fetch），文案为中文映射（前端展示单一来源）。
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
    IMPORT_URL,
    WARNING_LABELS,
    __all__,
} from '../js/simulator-contracts.js';

// 契约锁锚点：迁移前两视图本地副本的一致值（仅测试文件持有，产品代码不得复制）
const LEGACY_SIM_DIR = 'simulators';
const LEGACY_MANIFEST_URL = 'simulators/manifest.json';
const LEGACY_TIMEOUT_MS = 15000;
const LEGACY_TIMEOUT_REASON = '模拟器清单加载超时（15 秒未收到响应）';

// 导入契约锚点（与后端工单 03 端点契约逐字一致 — backend/app/api/routes/simulators.py）
const BACKEND_IMPORT_URL = '/api/simulators/import';
// 后端 SUSPICIOUS_PATTERNS 键集锚点（simulator_store.py 常量单源；前端映射以此为键集）
const BACKEND_WARNING_KEYS = ['eval', 'document.cookie', 'cross-origin-fetch'];

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

describe('IMPORT_URL — 导入端点契约（工单 04，锚定后端 03 端点）', () => {
    it('与后端 POST /api/simulators/import 逐字一致', () => {
        expect(IMPORT_URL).toBe(BACKEND_IMPORT_URL);
    });

    it('以 /api 前缀开头（前端 API 统一前缀约定，api.js API_BASE）', () => {
        expect(IMPORT_URL.startsWith('/api/')).toBe(true);
    });
});

describe('WARNING_LABELS — 恶意模式键集中文映射（键集锚定后端 SUSPICIOUS_PATTERNS）', () => {
    it('键集与后端 SUSPICIOUS_PATTERNS 完全一致（增删键必联动后端）', () => {
        expect(Object.keys(WARNING_LABELS).sort()).toEqual([...BACKEND_WARNING_KEYS].sort());
    });

    it('每个键的中文文案为非空字符串（提示弹窗直接消费）', () => {
        for (const key of BACKEND_WARNING_KEYS) {
            expect(typeof WARNING_LABELS[key]).toBe('string');
            expect(WARNING_LABELS[key].length).toBeGreaterThan(0);
        }
    });

    it('文案包含安全语义关键词（第三方可读取本地数据并调用 API 的威胁模型传达）', () => {
        // 威胁模型衔接（spec：明显恶意模式粗筛命中弹警告不拦截，定位知情提示）——
        // 各文案须传达「本地数据/会话/外部发送」任一风险面，防止退化成语焉不详
        const riskMarkers = ['本地', '会话', '外部', '数据'];
        for (const key of BACKEND_WARNING_KEYS) {
            const hasRisk = riskMarkers.some((m) => WARNING_LABELS[key].includes(m));
            expect(hasRisk, `WARNING_LABELS[${key}] 文案未传达风险面：${WARNING_LABELS[key]}`).toBe(true);
        }
    });
});

describe('simulator-contracts __all__ 协议表面', () => {
    it('__all__ 收口全部常量与纯函数', () => {
        expect(__all__.sort()).toEqual([
            'GENERATE_URL',
            'IMPORT_URL',
            'MANIFEST_URL',
            'SIM_DIR',
            'TIMEOUT_MS',
            'TIMEOUT_REASON',
            'WARNING_LABELS',
            'isValidSimulatorFile',
        ]);
    });
});
