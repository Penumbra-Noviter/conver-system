/// 模拟器域契约常量单源（F-M5-02）——SIM_DIR / MANIFEST_FILE / TIMEOUT_MS /
/// 就绪轮询上限 / 固定端口 / file 安全判据单一归属。
///
/// 桌面权威源（只读，语义逐字锚点）：`desktop/frontend/js/simulator-contracts.js`
/// （SIM_DIR='simulators' / MANIFEST_URL 派生 / TIMEOUT_MS=15000 /
/// isValidSimulatorFile）及其契约锁 `desktop/frontend/tests/
/// simulator-contracts.test.js`（15 类判据矩阵）。消费方（F-M5-04 注入 /
/// F-M5-06 存档）只经本模块取模拟器域常量与判据，不各持字面量副本。
///
/// 单一归属派生（F-M5-01 汇报纪律「常量单一归属，后续票不得复制字面量」）：
/// 目录名与清单文件名的**字面量**已随 F-M5-01 合入——`simulator_data_dir.dart`
/// 的 [SimulatorDataDir.subdirectory] 与 `seed_service.dart` 的 [manifestFileName]。
/// 本模块按 SIM_DIR / MANIFEST_FILE 语义**别名消费**这两个既有常量（非复制
/// 字面量），杜绝「两份字面量碰巧相等」的静默破约；其余常量（超时 / 轮询 /
/// 端口）字面量在本模块单一归属。
///
/// 协议表面（深模块）：`SimulatorContracts`（常量 + 判据）。
library;

import 'seed_service.dart' show manifestFileName;
import 'simulator_data_dir.dart' show SimulatorDataDir;

/// 模拟器域契约常量与 file 安全判据——单一来源，零副作用。
abstract final class SimulatorContracts {
  /// 模拟器静态目录名（桌面 SIM_DIR 'simulators'）。URL 路由前缀
  /// `/simulators/`、数据目录名共用；字面量归 F-M5-01
  /// [SimulatorDataDir.subdirectory]，本常量按 SIM_DIR 语义派生，不复制。
  static const String simDir = SimulatorDataDir.subdirectory;

  /// 数据目录下清单文件名（桌面 MANIFEST_FILE 'manifest.json'）。种子标记、
  /// 清单路由、存档收集共用；字面量归 F-M5-01 [manifestFileName]，本常量
  /// 按 MANIFEST_FILE 语义派生，不复制。
  static const String manifestFile = manifestFileName;

  /// 加载超时守卫时长（毫秒；桌面 TIMEOUT_MS=15000 逐字）。列表清单加载
  /// 守卫与运行页 load 超时守卫共用（spec §4.2-4，F-M5-03 消费）。
  static const int timeoutMs = 15000;

  /// 注入脚本就绪轮询上限（毫秒；桌面注入脚本就绪轮询 ≤5s 逐字）。预留常量，
  /// 供 F-M5-04 注入票消费（自包含 JS 常量内的目标控件就绪轮询时长上限）。
  static const int scriptReadyPollMs = 5000;

  /// 本地托管固定端口（共识 D5 定案 8642）。回环监听无公网暴露；被占时
  /// 明确错误态 + 重试，**绝不静默换端口**——换端口 = 换 origin = localStorage
  /// 存档全部静默丢失（spec §3-1）。
  static const int defaultPort = 8642;

  /// 同源反代端点前缀（方案 A CORS 修复，T2/T3 单源）。注入脚本把真实
  /// OpenAI 兼容 base URL 改写为本地 server 同源反代地址 `/proxy/<path>`，
  /// 浏览器 fetch 落在本地 server 上由服务端转发（规避 CORS 拦截）。桌面
  /// 对应 `PROXY_PREFIX = '/api/simulators/proxy'`；移动端本地 server 路由
  /// 挂 `/proxy`（T3 读本常量，与模板占位符替换值共用）。
  static const String proxyPrefix = '/proxy';

  /// file 字段安全判据（锚桌面 simulator-contracts.js isValidSimulatorFile 逐字）：
  /// 非空字符串且不含 `/` `\`（路径分隔符，拒绝穿越与子路径）、`%`（百分号
  /// 编码面）、`#`（URL fragment 分隔符）→ true；其余一律 false。
  ///
  /// 入参取 [Object?] 以吸收 manifest 动态数据（json.decode 产出 Map 值可为
  /// 任意类型）：非字符串类型与空串恒 false，与桌面 typeof 检查语义逐字等价。
  static bool isValidSimulatorFile(Object? file) {
    if (file is! String || file.isEmpty) {
      return false;
    }
    return !file.contains('/') &&
        !file.contains(r'\') &&
        !file.contains('%') &&
        !file.contains('#');
  }
}