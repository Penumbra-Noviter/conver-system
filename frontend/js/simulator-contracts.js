/**
 * Conver System — 模拟器域契约单一来源（C8 契约深模块，纯常量 + 纯函数，零副作用）
 *
 * 职责：模拟器域事实常量与 file 安全判据从运行视图 / 列表视图的本地副本收敛
 *   为单一来源 —— 静态目录（SIM_DIR）、清单 URL（由目录派生）、加载超时毫秒数
 *   （TIMEOUT_MS）、清单域超时文案（TIMEOUT_REASON，秒数由毫秒数派生）、file
 *   安全判据纯函数（isValidSimulatorFile）。消费方全部 import 本模块，不再各持
 *   字面量副本：
 *     - frontend/js/simulator-view.js （运行视图：SIM_DIR / TIMEOUT_MS /
 *       isValidSimulatorFile 委托；iframe 超时文案保留自身语义但秒数共享派生）
 *     - frontend/js/simulators.js     （列表视图：MANIFEST_URL / TIMEOUT_MS /
 *       TIMEOUT_REASON）
 *     - frontend/tests/simulator-contracts.test.js（契约锁：常量断言 + 判据矩阵）
 *   维护约定：新增 / 修改模拟器域契约常量只改本模块；各消费文件 docstring 的
 *   共享契约段指向本模块（不复制常量定义）。
 *
 * 文案语义分域：TIMEOUT_REASON 是清单域超时文案（列表视图 fetch 守卫消费）；
 *   运行视图 iframe 加载超时文案「加载超时（N 秒未收到响应）」保留自身语义，
 *   不共用 TIMEOUT_REASON —— 两处仅秒数由同一 TIMEOUT_MS 派生（改毫秒数
 *   必联动两处文案秒数）。
 *
 * 硬约束（Node ESM 真实消费者兼容 — 冒烟脚本直 import 先例，save-key-meta
 *   TD-67/68）：模块顶层零 DOM / 零浏览器 API / 零副作用，仅语言内建
 *   （String.prototype）。
 *
 * 协议表面（__all__）：SIM_DIR / MANIFEST_URL / TIMEOUT_MS / TIMEOUT_REASON /
 *   isValidSimulatorFile。
 */

// ══════════════════════════════════════════════════
// 常量（模拟器域事实 — 单一来源）
// ══════════════════════════════════════════════════

/** 模拟器静态目录（与列表模块 MANIFEST_URL 同源约定；T2 静态托管根挂载覆盖） */
export const SIM_DIR = 'simulators';

/** 清单 URL（由 SIM_DIR 派生，与原列表视图字面量逐字相同 — 改目录只改一处） */
export const MANIFEST_URL = `${SIM_DIR}/manifest.json`;

/** 加载超时守卫时长（spec 建议 15s；运行视图 iframe 守卫与列表清单守卫共用） */
export const TIMEOUT_MS = 15000;

/** 清单域超时文案（spec D1 逐字；秒数由 TIMEOUT_MS 派生，非硬编码 — 改毫秒数必联动秒数） */
export const TIMEOUT_REASON = `模拟器清单加载超时（${TIMEOUT_MS / 1000} 秒未收到响应）`;

// ══════════════════════════════════════════════════
// 纯函数：file 安全判据（iframe src 注入守卫）
// ══════════════════════════════════════════════════

/**
 * file 字段安全判据：非空字符串且不含路径分隔符 / 百分号编码 / #。
 *
 * iframe src 注入守卫（等价迁移前运行视图内联判据）：file 来自 manifest
 * 第三方数据，防御越界 / 外链 —— 含 `/` `\` 路径分隔符（TD-56：拒绝穿越与
 * 子路径）、`%` 百分号编码（TD-56：单点拒绝整个百分号编码面 — Starlette
 * 遍历防护与 manifest 可信资产为既有兜底，本判定为纵深加固）或 `#`（URL
 * fragment 分隔符 — iframe src 遇 # 请求截断 → 404，per-game CSS href
 * 同理截断）一律拒绝。对象判定与「参数非法：缺少有效的游戏文件」错误文案
 * 留在运行视图层。
 *
 * @param {unknown} file - 游戏条目的 file 字段值
 * @returns {boolean} 非空字符串且不含 / \ % # 为 true；否则 false
 */
export function isValidSimulatorFile(file) {
    return typeof file === 'string' && file !== ''
        && !file.includes('/') && !file.includes('\\')
        && !file.includes('%') && !file.includes('#');
}

// ══════════════════════════════════════════════════
// 协议表面收口（深模块：外部只通过这些符号与 simulator-contracts.js 交互）
// ══════════════════════════════════════════════════

export const __all__ = [
    'SIM_DIR',
    'MANIFEST_URL',
    'TIMEOUT_MS',
    'TIMEOUT_REASON',
    'isValidSimulatorFile',
];
