/// F-M5-02 模拟器域契约常量单源 — 锚桌面 simulator-contracts.test.js 矩阵。
///
/// 语义逐字锚点（只读）：`desktop/frontend/js/simulator-contracts.js` 及其契约锁
/// `desktop/frontend/tests/simulator-contracts.test.js`（SIM_DIR / MANIFEST_URL /
/// TIMEOUT_MS / isValidSimulatorFile 判据矩阵）。
///
/// 测例锁定契约（工单验收语义契约第 1 条）：
/// - `SimulatorContracts.simDir` / `manifestFile` / `timeoutMs` / `defaultPort`
///   值字面量（'simulators' / 'manifest.json' / 15000 / 8642）与既有单一归属
///   （F-M5-01 `SimulatorDataDir.subdirectory` / `manifestFileName`）同值派生
///   ——本模块不复制字面量，避免双源漂移；
/// - `scriptReadyPollMs` 就绪轮询预留常量必须 ≤5000ms（注入票 F-M5-04 消费）；
/// - `isValidSimulatorFile` 判据矩阵（含桌面 15 类样本）：非字符串（null/数字/
///   布尔/对象/数组）与空串 → false；合法文件名（含中文）→ true；含 `/` `\`
///   `%` `#` 分隔符/编码/fragment 字符 → false。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/seed_service.dart'
    show manifestFileName;
import 'package:conver_system_mobile/services/simulator/simulator_contracts.dart';
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart'
    show SimulatorDataDir;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SimulatorContracts 常量单源', () {
    test('simDir = simulators，与 F-M5-01 SimulatorDataDir.subdirectory 派生一致', () {
      expect(SimulatorContracts.simDir, 'simulators',
          reason: '桌面 SIM_DIR 字面量逐字等价');
      expect(SimulatorContracts.simDir, SimulatorDataDir.subdirectory,
          reason: '单一来源派生：字面量归 F-M5-01 所有，本模块不复制');
    });

    test('manifestFile = manifest.json，与 F-M5-01 seed_service manifestFileName 派生一致', () {
      expect(SimulatorContracts.manifestFile, 'manifest.json',
          reason: '桌面 MANIFEST_FILE 字面量逐字等价');
      expect(SimulatorContracts.manifestFile, manifestFileName,
          reason: '单一来源派生：字面量归 F-M5-01 所有，本模块不复制');
    });

    test('timeoutMs = 15000（桌面 TIMEOUT_MS 逐字）', () {
      expect(SimulatorContracts.timeoutMs, 15000);
    });

    test('scriptReadyPollMs 就绪轮询预留常量 ≤ 5000ms（注入票消费上限）', () {
      expect(SimulatorContracts.scriptReadyPollMs, greaterThan(0));
      expect(SimulatorContracts.scriptReadyPollMs, lessThanOrEqualTo(5000));
    });

    test('defaultPort = 8642（固定端口，锚共识 D5；换端口=换 origin=存档丢失）', () {
      expect(SimulatorContracts.defaultPort, 8642);
    });
  });

  group('isValidSimulatorFile — file 安全判据矩阵（锚桌面 15 类样本）', () {
    // ── 非字符串输入（Falsify：任意类型不得炸，一律 false）──
    test('null → false', () {
      expect(SimulatorContracts.isValidSimulatorFile(null), isFalse);
    });

    test('数字 → false', () {
      expect(SimulatorContracts.isValidSimulatorFile(42), isFalse);
    });

    test('布尔 → false', () {
      expect(SimulatorContracts.isValidSimulatorFile(true), isFalse);
    });

    test('对象 / 数组 → false（Falsify 防御）', () {
      expect(SimulatorContracts.isValidSimulatorFile(<String, dynamic>{}), isFalse);
      expect(SimulatorContracts.isValidSimulatorFile(<Object?>[]), isFalse);
    });

    test('空串 → false', () {
      expect(SimulatorContracts.isValidSimulatorFile(''), isFalse);
    });

    // ── happy path ──
    test("'a.html' → true（合法游戏文件名）", () {
      expect(SimulatorContracts.isValidSimulatorFile('a.html'), isTrue);
    });

    test("'人生模拟器v3.html' → true（中文文件名，manifest 真实资产形态）", () {
      expect(SimulatorContracts.isValidSimulatorFile('人生模拟器v3.html'), isTrue);
    });

    test("'.a.html' → true（点开头的普通文件名，非段穿越）", () {
      expect(SimulatorContracts.isValidSimulatorFile('.a.html'), isTrue);
    });

    // ── iframe src 注入守卫（含 `/` `\` 路径分隔符 / `%` 编码 / `#` fragment）──
    test("'a/b.html'（含 / 路径分隔符）→ false", () {
      expect(SimulatorContracts.isValidSimulatorFile('a/b.html'), isFalse);
    });

    test(r"'a\b.html'（含 \ 路径分隔符）→ false", () {
      expect(SimulatorContracts.isValidSimulatorFile(r'a\b.html'), isFalse);
    });

    test("'a%b.html'（含百分号编码）→ false", () {
      expect(SimulatorContracts.isValidSimulatorFile('a%b.html'), isFalse);
    });

    test("'a#b.html'（含 # fragment 分隔符）→ false", () {
      expect(SimulatorContracts.isValidSimulatorFile('a#b.html'), isFalse);
    });

    test("'./a.html'（含 / 起始相对段）→ false", () {
      expect(SimulatorContracts.isValidSimulatorFile('./a.html'), isFalse);
    });
  });
}