/// F-M5-03 SimulatorsController — 懒启动编排 + 列表四态 + 筛选 + 钩子持有。
///
/// 测试 seam（公共接口边界，装配注入 fake 不触平台通道——经验先例：真
/// path_provider/服务器在测试宿主挂起）：
/// 1. [SimulatorDataDir]（注入 resolver → 临时目录）；
/// 2. seed 回调（记录调用/抛错/挂起 Completer——模拟 F-25 rootBundle 裸抛）；
/// 3. server 工厂（桩子类报端口 / 抛 [SimulatorPortInUseException]）；
/// 4. manifest 拉取回调（成功/失败/抛错/挂起——挂起 + 注入短超时验证 15s
///    守卫语义）；5. port（真实链测试传 0）；6. [SimulatorsHooks] 缺省/接线。
///
/// 契约锁（工单验收语义契约逐条）：
/// - 编排契约：seed → server.start → 回环 HTTP 拉 manifest → 宽容解析 → ready；
/// - App 存续期幂等：重复 ensureStarted 不重启 server 不重种（成功路径）；
/// - 端口被占 → 错误态，retry() 重试成功后进入 ready；
/// - 空 manifest → empty 态；解析/拉取失败 → error 态（文案可读）；
/// - F-25 兜底：种子单游戏缺失（裸抛）→ 不中止列表，继续编排；
/// - filter 三档筛选；refresh 轻量重拉（ready/empty）/ 错误态回退重跑。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/manifest_parser.dart';
import 'package:conver_system_mobile/services/simulator/seed_service.dart';
import 'package:conver_system_mobile/services/simulator/simulator_contracts.dart';
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart';
import 'package:conver_system_mobile/services/simulator/simulator_server.dart';
import 'package:conver_system_mobile/view_models/simulators_controller.dart';
import 'package:conver_system_mobile/views/simulators/simulators_hooks.dart';

/// 两游戏 fixture（ai + local/imported）——source 判据与筛选可测。
const String manifestJson = '''
{"version":2,"simulators":[
  {"id":"life-sim","file":"人生模拟器v3.html","name":"人生模拟器 v3","type":"ai",
   "description":"AI 驱动的生命模拟","saveKeys":["ls_autosave"],"endpointMode":"full"},
  {"id":"local-x","file":"local-x.html","name":"本地示例","type":"local",
   "description":"纯本地游戏","source":"imported"}
]}
''';

/// 空 manifest（合法空态）。
const String emptyManifestJson = '{"version":2,"simulators":[]}';

/// 结构性损坏 manifest（拉取成功但解析失败 → error 态）。
const String brokenManifestJson = '{"version":2,"simulators":"oops"}';

/// 记录调用与端口的 manifest 拉取 fake。
class _RecordingManifestLoader {
  int calls = 0;
  int? lastPort;
  ManifestParseResult result = const ManifestParseResult.success([]);
  Object? error; // 非空则抛
  Completer<ManifestParseResult>? hang; // 非空则挂起（配合短超时测守卫）

  Future<ManifestParseResult> call(int port) async {
    calls++;
    lastPort = port;
    final h = hang;
    if (h != null) {
      return h.future;
    }
    final err = error;
    if (err != null) {
      throw err;
    }
    return result;
  }
}

/// 记录调用次数的 seed fake（可抛错模拟 F-25 单游戏缺失 rootBundle 裸抛）。
class _RecordingSeeder {
  int calls = 0;
  bool result = false;
  Object? error;
  Completer<bool>? hang;

  Future<bool> call(Directory simDir) async {
    calls++;
    final h = hang;
    if (h != null) {
      return h.future;
    }
    final err = error;
    if (err != null) {
      throw err;
    }
    return result;
  }
}

/// 桩服务器（不 bind 真 socket）：报告端口 / 记录 start 调用 / 可抛错；
/// start 成功后 isRunning = true（复用判据与真实服务器语义一致）。
class _StubServer extends SimulatorServer {
  _StubServer({required this.reportPort, this.startError})
      : super(Directory.systemTemp);

  final int reportPort;
  final Object? startError;
  int startCalls = 0;
  int? recordedPort;
  bool _running = false;

  @override
  Future<int> start({required int port}) async {
    startCalls++;
    recordedPort = port;
    final err = startError;
    if (err != null) {
      throw err;
    }
    _running = true;
    return reportPort;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  @override
  bool get isRunning => _running;
}

/// 按队列产出的 server 工厂（首个抛端口占 → 重试成功路径可测）。
class _ServerSequenceFactory {
  _ServerSequenceFactory(this.servers);

  final List<SimulatorServer> servers;
  int _created = 0;

  SimulatorServer call(Directory simDir) {
    final index = _created < servers.length ? _created : servers.length - 1;
    _created++;
    return servers[index];
  }
}

Future<Directory> makeTempParent() async {
  final parent = await Directory.systemTemp.createTemp('m5-03-ctrl-');
  addTearDown(() => parent.delete(recursive: true));
  return parent;
}

/// F-33（TD-1）fake：永不响应的 HttpClient——getUrl 永久挂起，但 close 被
/// 记录。经 HttpOverrides.runZoned 注入 [loadManifestViaHttp]，验证超时后
/// 底层请求被取消（force close 在途连接，杜绝悬挂连接累积）。
class _NeverRespondingHttpClient implements HttpClient {
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => Completer<HttpClientRequest>().future;

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory parent;
  late SimulatorDataDir dataDir;
  late _RecordingSeeder seeder;
  late _RecordingManifestLoader loader;
  late SimulatorsController controller;

  SimulatorsController buildController({
    SimulatorServerFactory? createServer,
    int port = SimulatorContracts.defaultPort,
    Duration manifestTimeout =
        const Duration(milliseconds: SimulatorContracts.timeoutMs),
    SimulatorsHooks hooks = const SimulatorsHooks(),
  }) {
    controller = SimulatorsController(
      dataDir: dataDir,
      seed: seeder.call,
      createServer: createServer ?? (dir) => _StubServer(reportPort: 4321),
      loadManifest: loader.call,
      port: port,
      manifestTimeout: manifestTimeout,
      hooks: hooks,
    );
    return controller;
  }

  setUp(() async {
    parent = await makeTempParent();
    dataDir = SimulatorDataDir(resolveDocumentsDir: () async => parent);
    seeder = _RecordingSeeder();
    loader = _RecordingManifestLoader();
  });

  tearDown(() {
    try {
      controller.dispose();
    } catch (_) {
      // 用例未 create（创建于首行，仅失败于创建前）→ 无泄漏可清理。
    }
  });

  group('懒启动编排 · seed → server → HTTP manifest → ready', () {
    test('首启成功：seed/server.start/manifest 按序执行，state=ready，游戏归一化', () async {
      final stub = _StubServer(reportPort: 8642);
      buildController(createServer: (dir) => stub);
      loader.result = parseManifest(manifestJson);

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.ready);
      expect(controller.errorMessage, isNull);
      expect(seeder.calls, 1, reason: '首启执行一次种子');
      expect(stub.startCalls, 1, reason: '首启 bind 一次');
      expect(stub.recordedPort, SimulatorContracts.defaultPort,
          reason: '生产装配固定 8642（绝不换端口）');
      expect(loader.calls, 1);
      expect(loader.lastPort, stub.reportPort,
          reason: 'manifest 经回环 HTTP 拉取，port = 实际监听端口');
      expect(controller.games, hasLength(2));
      expect(controller.games.map((g) => g.id), ['life-sim', 'local-x']);
      expect(controller.games.first.name, '人生模拟器 v3');
      expect(controller.games.first.type, SimulatorGameType.ai);
      expect(controller.games.last.type, SimulatorGameType.local);
      expect(controller.games.last.source, SimulatorGameSource.imported,
          reason: 'source=imported 归一化为导入判据');
    });

    test('空 manifest → state=empty（合法空态，非错误）', () async {
      buildController();
      loader.result = parseManifest(emptyManifestJson);

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.empty);
      expect(controller.games, isEmpty);
      expect(controller.errorMessage, isNull);
    });

    test('App 存续期幂等：成功后重复 ensureStarted 不重种不重启不重拉', () async {
      final stub = _StubServer(reportPort: 4321);
      buildController(createServer: (dir) => stub);
      loader.result = parseManifest(manifestJson);

      await controller.ensureStarted();
      await controller.ensureStarted();
      await controller.ensureStarted();

      expect(seeder.calls, 1, reason: '不重种');
      expect(stub.startCalls, 1, reason: '不重启 server');
      expect(loader.calls, 1, reason: '不重拉 manifest');
      expect(controller.state, SimulatorsState.ready);
    });

    test('loading 并发合并：in-flight 期间重复 ensureStarted 只发起一次编排', () async {
      final stub = _StubServer(reportPort: 4321);
      buildController(createServer: (dir) => stub);
      loader.result = parseManifest(manifestJson);
      seeder.hang = Completer<bool>();

      final f1 = controller.ensureStarted();
      final f2 = controller.ensureStarted();

      expect(controller.state, SimulatorsState.loading);
      seeder.hang!.complete(true);
      await Future.wait([f1, f2]);

      expect(seeder.calls, 1, reason: '并发调用合并为一次种子');
      expect(stub.startCalls, 1);
      expect(controller.state, SimulatorsState.ready);
    });
  });

  group('错误态 · 文案 + retry', () {
    test('数据目录解析失败 → error（文案含解析失败）', () async {
      final failing = SimulatorDataDir(
        resolveDocumentsDir: () async => throw StateError('docs unavailable'),
      );
      controller = SimulatorsController(
        dataDir: failing,
        seed: seeder.call,
        createServer: (dir) => _StubServer(reportPort: 4321),
        loadManifest: loader.call,
      );

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('解析模拟器数据目录失败'));
      expect(controller.games, isEmpty);
    });

    test('数据目录解析挂起（平台通道）→ 超时守卫 → error 文案含超时', () async {
      final hanging = SimulatorDataDir(
        resolveDocumentsDir: () => Completer<Directory>().future,
      );
      controller = SimulatorsController(
        dataDir: hanging,
        seed: seeder.call,
        createServer: (dir) => _StubServer(reportPort: 4321),
        loadManifest: loader.call,
        manifestTimeout: const Duration(milliseconds: 30),
      );

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('超时'),
          reason: '平台通道挂起被超时守卫拦截，不阻塞不裸崩');
    });

    test('manifest 拉取抛错 → error（文案含加载游戏清单失败）', () async {
      buildController();
      loader.error = StateError('http down');

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('加载游戏清单失败'));
    });

    test('manifest 解析失败（损坏 JSON/结构）→ error 文案为解析原因', () async {
      buildController();
      loader.result = parseManifest(brokenManifestJson);

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('simulators 列表'));
      expect(controller.games, isEmpty);
    });

    test('manifest 拉取挂起 → 超时守卫（TIMEOUT_MS 语义）→ error 文案含超时', () async {
      buildController(manifestTimeout: const Duration(milliseconds: 30));
      loader.hang = Completer<ManifestParseResult>();

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('超时'));
      // 清理未完成 future（避免泄漏）。
      loader.hang!.complete(const ManifestParseResult.failure('timeout'));
    });

    test('端口被占（SimulatorPortInUseException）→ error 文案含端口占用语义，绝不换端口', () async {
      buildController(
        createServer: (dir) =>
            _StubServer(reportPort: 8642, startError: SimulatorPortInUseException(8642)),
      );

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('8642'));
      expect(controller.errorMessage, contains('占用'));
      expect(controller.errorMessage, contains('绝不静默换端口'),
          reason: '换端口 = 换 origin = 存档丢失语义不静默绕过');
    });

    test('retry：端口占后重试成功 → ready（重试不残留错误态）', () async {
      final failing = _StubServer(
        reportPort: 8642,
        startError: SimulatorPortInUseException(8642),
      );
      final ok = _StubServer(reportPort: 8642);
      buildController(createServer: _ServerSequenceFactory([failing, ok]).call);
      loader.result = parseManifest(manifestJson);

      await controller.ensureStarted();
      expect(controller.state, SimulatorsState.error);

      await controller.retry();

      expect(controller.state, SimulatorsState.ready);
      expect(controller.errorMessage, isNull);
      expect(controller.games, hasLength(2));
      expect(ok.startCalls, 1, reason: '重试以新实例重新 bind');
    });

    test('retry 复用已运行 server：首次 server 成功但 manifest 失败 → 重试不重复 bind', () async {
      final stub = _StubServer(reportPort: 4321);
      buildController(createServer: (dir) => stub);
      loader.result = const ManifestParseResult.failure('transient');

      await controller.ensureStarted();
      expect(controller.state, SimulatorsState.error);
      expect(stub.startCalls, 1);

      loader.result = parseManifest(manifestJson);
      await controller.retry();

      expect(controller.state, SimulatorsState.ready);
      expect(stub.startCalls, 1, reason: 'server 仍在运行 → 复用不重复 bind（常驻语义）');
      expect(loader.calls, 2);
    });
  });

  group('F-25 兜底 · 种子单游戏缺失（rootBundle 裸抛）不中止列表', () {
    test('种子挂起（平台通道）→ 超时兜底继续启动链路，不中止编排（F-32 收窄未误伤超时路径）', () async {
      buildController(manifestTimeout: const Duration(milliseconds: 30));
      seeder.hang = Completer<bool>();
      loader.result = parseManifest(manifestJson);

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.ready,
          reason: '种子挂起超时降级继续链路（与目录不可写阻塞性错误区分）');
      seeder.hang!.complete(false); // 清理未完成 future
    });
    test('seed 抛错但数据目录已有 manifest → 继续编排 → ready', () async {
      // 模拟先前成功种子：数据目录已有 manifest。
      final simDir = Directory('${parent.path}${Platform.pathSeparator}simulators');
      simDir.createSync(recursive: true);
      File('${simDir.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync(manifestJson);
      buildController();
      seeder.error = FlutterErrorLike('未登记资产 仿微.html'); // F-2 裸抛形态
      loader.result = parseManifest(manifestJson);

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.ready, reason: '单游戏缺失不中止整个列表');
      expect(controller.games, hasLength(2));
      expect(controller.errorMessage, isNull);
    });

    test('seed 抛错且数据目录无 manifest → 列表经 manifest 拉取失败进 error（非裸崩）', () async {
      buildController();
      seeder.error = FlutterErrorLike('未登记资产');
      loader.error = StateError('manifest 不存在');

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('加载游戏清单失败'),
          reason: '种子兜底后由 manifest 面决定终态，链路不裸崩');
    });
  });

  group('F-32 · 种子错误捕获面收窄（TD-1）', () {
    test('种子目录不可写（带路径 FileSystemException）→ error 文案含路径，不吞成清单失败', () async {
      final simDir = Directory('${parent.path}${Platform.pathSeparator}simulators');
      buildController();
      seeder.error = FileSystemException('目录只读，无法写入', simDir.path);
      loader.result = parseManifest(manifestJson); // 即便 manifest 可拉，也不该盖掉种子阻塞性错误

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains('模拟器数据目录不可用'),
          reason: '种子明确错误文案（非清单面泛化错误）');
      expect(controller.errorMessage, contains(simDir.path),
          reason: '目录不可写错误带完整路径（F-32 契约要求，不吞并）');
      expect(controller.errorMessage, isNot(contains('游戏清单加载失败')),
          reason: '不被吞成清单加载/HTTP 404 泛化错误');
      expect(loader.calls, 0, reason: '种子阻塞性错误先失败，不再进入 manifest 拉取');
    });

    test('种子 FileSystemException 不带路径（意外形态）→ 文案仍含数据目录路径（自有兜底）', () async {
      final simDir = Directory('${parent.path}${Platform.pathSeparator}simulators');
      buildController();
      seeder.error = const FileSystemException('写入失败');
      loader.result = parseManifest(manifestJson);

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.error);
      expect(controller.errorMessage, contains(simDir.path),
          reason: '路径文案由 controller 以 simDir 兜底，不依赖异常自带路径');
      expect(loader.calls, 0);
    });
  });

  group('refresh · 轻量重拉（ready/empty）与错误态回退', () {
    test('ready 后 refresh：不重种不重启，仅重拉 manifest 并更新列表', () async {
      final stub = _StubServer(reportPort: 4321);
      buildController(createServer: (dir) => stub);
      loader.result = parseManifest(manifestJson);

      await controller.ensureStarted();
      expect(controller.games, hasLength(2));

      // 数据源新增一款（模拟导入落盘）后下拉刷新。
      loader.result = parseManifest('''
{"version":2,"simulators":[
  {"id":"life-sim","file":"人生模拟器v3.html","name":"人生模拟器 v3","type":"ai","description":"x"},
  {"id":"new-game","file":"new.html","name":"新游戏","type":"ai","description":"y","source":"generated"}
]}
''');

      await controller.refresh();

      expect(seeder.calls, 1, reason: '刷新不重种');
      expect(stub.startCalls, 1, reason: '刷新不重启 server');
      expect(loader.calls, 2);
      expect(controller.games, hasLength(2));
      expect(controller.games.last.source, SimulatorGameSource.generated);
    });

    test('empty 态 refresh：仍可重拉（下拉刷新在空态可用）', () async {
      buildController();
      loader.result = parseManifest(emptyManifestJson);
      await controller.ensureStarted();
      expect(controller.state, SimulatorsState.empty);

      loader.result = parseManifest(manifestJson);
      await controller.refresh();

      expect(controller.state, SimulatorsState.ready);
      expect(controller.games, hasLength(2));
    });

    test('error 态 refresh：回退全链重跑（等同 retry）', () async {
      final stub = _StubServer(reportPort: 4321);
      buildController(createServer: (dir) => stub);
      loader.result = const ManifestParseResult.failure('boom');
      await controller.ensureStarted();
      expect(controller.state, SimulatorsState.error);

      loader.result = parseManifest(manifestJson);
      await controller.refresh();

      expect(controller.state, SimulatorsState.ready);
      expect(controller.games, hasLength(2));
    });

    test('loading 态 refresh 合并 in-flight', () async {
      final stub = _StubServer(reportPort: 4321);
      buildController(createServer: (dir) => stub);
      loader.result = parseManifest(manifestJson);
      seeder.hang = Completer<bool>();

      final f1 = controller.ensureStarted();
      final f2 = controller.refresh();
      expect(controller.state, SimulatorsState.loading);
      // 等 _doStart 进入 seed 挂起点（Future 延迟一个微任务执行正文）。
      await Future<void>.delayed(Duration.zero);
      expect(seeder.calls, 1, reason: 'refresh 并入 in-flight 编排，只发起一条链');
      seeder.hang!.complete(true);
      await Future.wait([f1, f2]);
      expect(seeder.calls, 1);
      expect(controller.state, SimulatorsState.ready);
    });

    test('F-31（TD-1）: 重叠 refresh 合并 in-flight——挂起期间二次 refresh 不发起第二次拉取', () async {
      buildController();
      loader.result = parseManifest(manifestJson);
      await controller.ensureStarted();
      expect(controller.state, SimulatorsState.ready);
      final callsAfterStart = loader.calls;

      // A：挂起中的 refresh（模拟慢拉）。
      loader.hang = Completer<ManifestParseResult>();
      final fA = controller.refresh();
      await Future<void>.delayed(Duration.zero); // 进入 loader 挂起点
      // B：A 完成前二次 refresh（旧实现直调 _fetchManifest → 第二次独立拉取）。
      final fB = controller.refresh();

      expect(loader.calls, callsAfterStart + 1,
          reason: '重叠 refresh 合并 in-flight，不发起第二次拉取（无 last-writer-wins）');

      loader.hang!.complete(parseManifest(manifestJson));
      await Future.wait([fA, fB]);
      expect(controller.state, SimulatorsState.ready);
      expect(loader.calls, callsAfterStart + 1);
    });

    test('F-31（TD-1）: 重叠 refresh 共享失败——迟到失败不盖掉先前成功结果', () async {
      buildController();
      loader.result = parseManifest(manifestJson);
      await controller.ensureStarted();
      expect(controller.state, SimulatorsState.ready);

      // A 挂起中，B 合并；A 完成后（成功）——B 只能是同一条链同一结果。
      loader.hang = Completer<ManifestParseResult>();
      final fA = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final fB = controller.refresh();

      loader.hang!.complete(parseManifest(manifestJson));
      await Future.wait([fA, fB]);

      // 若旧实现（无守卫）：B 独立拉取可在 A 之后单独失败/成功竞争终态；
      // 守卫后只有一条链，B 与 A 结果一致，ready 结果不被任何迟到失败覆盖。
      expect(controller.state, SimulatorsState.ready);
      expect(controller.errorMessage, isNull);
      expect(loader.calls, 2, reason: '首启 1 次 + 合并后仅 1 次 refresh 拉取');
    });
  });

  group('filter · all/ai/local 三档筛选', () {
    test('默认 all；切 ai 只余 AI 驱动；切 local 只余纯本地', () async {
      buildController();
      loader.result = parseManifest(manifestJson);
      await controller.ensureStarted();
      expect(controller.games, hasLength(2));

      controller.selectFilter(SimulatorFilter.ai);
      expect(controller.games.map((g) => g.id), ['life-sim']);
      expect(controller.games.single.type, SimulatorGameType.ai);

      controller.selectFilter(SimulatorFilter.local);
      expect(controller.games.map((g) => g.id), ['local-x']);

      controller.selectFilter(SimulatorFilter.all);
      expect(controller.games, hasLength(2));
    });

    test('allGames 不过滤：筛选态下存档面板仍可一次管全部（Q12）', () async {
      buildController();
      loader.result = parseManifest(manifestJson);
      await controller.ensureStarted();

      controller.selectFilter(SimulatorFilter.local);
      expect(controller.games.map((g) => g.id), ['local-x']);
      expect(controller.allGames.map((g) => g.id), ['life-sim', 'local-x'],
          reason: '存档入口读 allGames——不随筛选漏游戏');
    });
  });

  group('hooks · 四钩子经 SimulatorsHooks 注入', () {
    test('缺省 SimulatorsHooks → 四槽位均为 null（未接线 = UI 禁用）', () async {
      buildController();
      expect(controller.onOpen, isNull);
      expect(controller.onSaveTap, isNull);
      expect(controller.onImportTap, isNull);
      expect(controller.onGenerateTap, isNull);
    });

    test('wireViewDefaults：填充视图默认槽位 + 外部构造注入槽位恒优先（W6 B1）',
        () async {
      var externalTaps = 0;
      buildController(
        hooks: SimulatorsHooks(onGenerateTap: () => externalTaps++),
      );
      var defaultTaps = 0;
      controller.wireViewDefaults(SimulatorsHooks(
        onGenerateTap: () => defaultTaps++,
        onSaveTap: () {},
        onImportTap: () {},
        onOpen: (_) {},
      ));

      // 外部槽位优先：onGenerateTap 派发到构造注入钩子，视图默认不覆盖。
      controller.onGenerateTap!();
      expect(externalTaps, 1);
      expect(defaultTaps, 0,
          reason: '外部构造注入槽位恒优先（既有注入钩子优先契约）');
      // 未接线槽位被视图默认填充（UI 不再禁用）。
      expect(controller.onSaveTap, isNotNull);
      expect(controller.onImportTap, isNotNull);
      expect(controller.onOpen, isNotNull);
    });

    test('wireViewDefaults：重复调用刷新视图默认槽位（tab 往返后最新闭包生效）',
        () async {
      buildController();
      var first = 0;
      controller.wireViewDefaults(SimulatorsHooks(
        onGenerateTap: () => first++,
      ));
      // 模拟切回 tab 后新 State 挂载再次接线。
      var second = 0;
      controller.wireViewDefaults(SimulatorsHooks(
        onGenerateTap: () => second++,
      ));

      controller.onGenerateTap!();
      expect(first, 0, reason: '视图默认槽位每次挂载刷新为最新闭包');
      expect(second, 1,
          reason: 'W6 B1：重挂载接线后点击派发到新闭包（不持有旧 State）');
    });
  });

  group('真实链 · seed(fake asset) + 真实 server(port 0) + 真实回环 HTTP manifest', () {
    test('端到端：ensureSeeded 落盘 → server bind port 0 → HTTP 拉取解析 → ready',
        () async {
      final files = <String, Uint8List>{
        'assets/fixture/manifest.json': Uint8List.fromList(utf8.encode(manifestJson)),
        'assets/fixture/人生模拟器v3.html': Uint8List.fromList(utf8.encode('<html>a</html>')),
        'assets/fixture/local-x.html': Uint8List.fromList(utf8.encode('<html>b</html>')),
      };
      SimulatorServer? server;
      controller = SimulatorsController(
        dataDir: SimulatorDataDir(resolveDocumentsDir: () async => parent),
        seed: (dir) => ensureSeeded(
          simDir: dir,
          assetRoot: 'assets/fixture',
          loadAsset: (path) async => files[path]!,
        ),
        createServer: (dir) {
          server = SimulatorServer(dir);
          return server!;
        },
        loadManifest: loadManifestViaHttp,
        port: 0,
      );

      await controller.ensureStarted();

      expect(controller.state, SimulatorsState.ready);
      expect(controller.games, hasLength(2));
      expect(controller.games.first.name, '人生模拟器 v3');
      await server!.stop();
    });
  });

  group('F-33（TD-1）· 拉取超时取消底层 HttpClient 请求', () {
    test('挂起请求超时 → 底层 HttpClient 被 force close（取消在途连接，杜绝悬挂累积）', () async {
      final fakeClient = _NeverRespondingHttpClient();
      await HttpOverrides.runZoned(
        () async {
          await expectLater(
            loadManifestViaHttp(4321, timeout: const Duration(milliseconds: 30)),
            throwsA(isA<TimeoutException>()),
            reason: '挂起阶段由函数内超时守卫拦截（不再依赖 controller 层）',
          );
        },
        createHttpClient: (_) => fakeClient,
      );
      expect(fakeClient.closed, isTrue,
          reason: '超时后取消底层请求：finally force close 在途 HttpClient');
    });

    test('正常返回（200 + 合法 manifest）路径不受超时参数影响，解析成功', () async {
      final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => httpServer.close(force: true));
      httpServer.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(manifestJson)
          ..close();
      });

      final result = await loadManifestViaHttp(httpServer.port,
          timeout: const Duration(milliseconds: 500));

      expect(result.ok, isTrue);
      expect(result.games, hasLength(2));
    });
  });
}

/// flutter_test 无法直接构造 [FlutterError]，用同形异常模拟 rootBundle 裸抛
/// （F-2 复现路径：未登记资产 → 非 FileSystemException → 链路裸抛）。
class FlutterErrorLike implements Exception {
  const FlutterErrorLike(this.message);

  final String message;

  @override
  String toString() => 'FlutterError: $message';
}
