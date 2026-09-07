/// SimulatorsController — 模拟器列表懒启动编排 + 四态状态机 + 筛选 + 钩子持有
/// （F-M5-03）。
///
/// 懒启动编排契约（spec §4.2-4 / 工单验收语义契约逐条）：
/// 首次进模拟器 tab → [ensureStarted] 依次执行：
///   1. seed（F-M5-01 [ensureSeeded] 幂等：manifest 存在 = 已种子）；
///   2. server start（F-M5-02 [SimulatorServer]，固定 [SimulatorContracts.defaultPort]
///      = 8642，绝不静默换端口）；
///   3. 经回环 HTTP GET `/simulators/manifest.json` 拉取（15s 超时守卫，
///      [SimulatorContracts.timeoutMs] 复用）→ [parseManifest] 宽容解析；
/// 成功 → ready（有游戏）/ empty（无游戏）；失败 → error（文案可读 +
/// [retry]）。**服务器 App 存续期常驻**：实例由 app.dart 装配在应用级
/// provider，不随 tab 销毁；成功后重复 [ensureStarted] 短路（不重种不重启
/// 不重拉）。
///
/// 错误路径分级：
/// - 端口被占（[SimulatorPortInUseException]）→ error 文案含「端口被占用」
///   语义（不静默换端口，换端口 = 换 origin = 存档丢失）；
/// - manifest 拉取超时 / HTTP 错误 / 解析失败 → error（文案可读）；
/// - **F-25 兜底**（W1 审核 F-2 落债）：种子单游戏资产缺失（rootBundle 裸抛
///   FlutterError）→ 不中止整个列表——捕获后继续 server + manifest 拉取，
///   由盘面真实结果决定终态（数据目录已有先前 manifest 则列表照常可用）。
///
/// [refresh] 为轻量重拉（不重种不重启，仅重拉 manifest；ready/empty 态下拉
/// 刷新可用，error 态回退全链重跑）；loading 态并发调用合并 in-flight。
///
/// 四钩子（onOpen / onSaveTap / onImportTap / onGenerateTap）经
/// [SimulatorsHooks] 注入（缺省未接线 = null = UI 禁用态）；后续票经
/// [registerHooks] 接线，不触碰 app.dart / home_shell.dart（装配纪律）。
///
/// 装配（唯一落点 = app.dart）：构造注入 dataDir / seed / server 工厂 /
/// manifest 拉取 + 端口，测试注入 fake 与临时目录（不触平台通道）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/simulator/manifest_parser.dart'
    show ManifestParseResult, parseManifest;
import '../services/simulator/simulator_contracts.dart'
    show SimulatorContracts;
import '../services/simulator/simulator_data_dir.dart' show SimulatorDataDir;
import '../services/simulator/simulator_server.dart'
    show SimulatorPortInUseException, SimulatorServer;
import '../views/simulators/simulators_hooks.dart' show SimulatorsHooks;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 characters_controller.dart 惯例）。
// ignore_for_file: prefer_initializing_formals

/// 列表四态（loading / ready / error / empty）。
enum SimulatorsState {
  /// 编排 / 重拉进行中（首启或重试）。
  loading,

  /// 编排成功且游戏列表非空（含筛选后）。
  ready,

  /// 编排 / 拉取失败（文案见 [SimulatorsController.errorMessage]）。
  error,

  /// 编排成功但无任何游戏（合法空态，可下拉刷新）。
  empty,
}

/// 类型筛选三档（all · ai · local）。
enum SimulatorFilter {
  /// 全部游戏。
  all,

  /// 仅 AI 驱动（manifest type = 'ai'）。
  ai,

  /// 仅纯本地（manifest type = 'local'）。
  local,
}

/// 游戏类型（manifest `type` 白名单，F-M5-01 parseManifest 已校验）。
enum SimulatorGameType {
  /// AI 驱动（需配置 AI 接口）。
  ai,

  /// 纯本地（无需外部接口）。
  local,
}

/// 游戏来源判据（manifest `source`，导入/生成 badge 依据）。
enum SimulatorGameSource {
  /// 导入（file_picker 链，F-M5-07 产）。
  imported,

  /// AI 生成（生成对话框，F-M5-08b 产）。
  generated,
}

/// 归一化游戏条目（显示模型）——manifest 条目 → 类型化字段。
///
/// parseManifest 已保证 id / file / name / description / type 恒合法存在；
/// source / endpointMode / saveKeys / saveKeyPrefix / config 为宽容降级后
/// 的可空字段（F-M5-04 注入 / F-M5-06 存档按需消费）。
class SimulatorGame {
  const SimulatorGame({
    required this.id,
    required this.file,
    required this.name,
    required this.description,
    required this.type,
    this.source,
    this.endpointMode,
    this.saveKeys,
    this.saveKeyPrefix,
    this.config,
  });

  /// 从 [parseManifest] 归一化条目构造（后续票新增 manifest 字段只需在此
  /// 扩展，不改动列表 / hooks 消费者）。
  factory SimulatorGame.fromManifest(Map<String, dynamic> data) {
    return SimulatorGame(
      id: data['id'] as String,
      file: data['file'] as String,
      name: data['name'] as String,
      description: data['description'] as String,
      type: data['type'] == 'local'
          ? SimulatorGameType.local
          : SimulatorGameType.ai,
      source: switch (data['source']) {
        'imported' => SimulatorGameSource.imported,
        'generated' => SimulatorGameSource.generated,
        _ => null,
      },
      endpointMode: data['endpointMode'] as String?,
      saveKeys: (data['saveKeys'] as List<dynamic>?)?.cast<String>(),
      saveKeyPrefix: data['saveKeyPrefix'] as String?,
      config: (data['config'] as Map<dynamic, dynamic>?)
          ?.cast<String, dynamic>(),
    );
  }

  /// 唯一标识（manifest `id`）。
  final String id;

  /// 服务器相对路径文件名（serve 于 `/simulators/<file>`）。
  final String file;

  /// 展示名（缺省空串由 parseManifest 归一化）。
  final String name;

  /// 一句话描述（缺省空串由 parseManifest 归一化）。
  final String description;

  /// AI 驱动 / 纯本地（类型徽标 + 筛选判据）。
  final SimulatorGameType type;

  /// 导入 / 生成徽标判据；内置条目为 null（无 badge）。
  final SimulatorGameSource? source;

  /// endpointMode（base / full；F-M5-04 注入按此口径转换端点）。
  final String? endpointMode;

  /// 存档键白名单（F-M5-06 存档收集/校验消费；缺省 = 无存档管理信号）。
  final List<String>? saveKeys;

  /// 退役字段（仅 v1 数据携带；透传不参与存档语义）。
  final String? saveKeyPrefix;

  /// 配置三元组控件 id（F-M5-04 注入定位）。
  final Map<String, dynamic>? config;

  /// 是否 AI 驱动。
  bool get isAi => type == SimulatorGameType.ai;
}

/// 首启种子回调：对已解析数据目录 [simDir] 执行幂等种子，返回本次是否执行
/// 了拷贝（false = 已种子 / 源缺降级）。生产 = [ensureSeeded] 装配，测试 fake。
typedef SimulatorSeeder = Future<bool> Function(Directory simDir);

/// 服务器工厂：按数据目录构造 [SimulatorServer]（生产实类，测试注入桩）。
typedef SimulatorServerFactory = SimulatorServer Function(Directory simDir);

/// manifest 拉取回调：经回环 HTTP 拉取并宽容解析；[port] = 实际监听端口。
/// 生产 = [loadManifestViaHttp]，测试 fake（成功/失败/抛错/挂起）。
typedef ManifestLoader = Future<ManifestParseResult> Function(int port);

/// 生产 manifest 拉取：回环 HTTP GET `/simulators/manifest.json` →
/// [parseManifest] 宽容解析。非 200 → failure 文案；超时守卫由
/// [SimulatorsController] 在加载路径统一施加（TIMEOUT_MS 复用）。
Future<ManifestParseResult> loadManifestViaHttp(int port) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(
      'http://127.0.0.1:$port/${SimulatorContracts.simDir}/'
      '${SimulatorContracts.manifestFile}',
    );
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      return ManifestParseResult.failure(
        '游戏清单加载失败（HTTP ${response.statusCode}）',
      );
    }
    return parseManifest(body);
  } finally {
    client.close(force: true);
  }
}

/// 模拟器列表控制器（懒启动编排 + 四态 + 筛选 + 钩子持有）。
///
/// App 存续期常驻：实例由 app.dart 装配于应用级 provider；服务器不随
/// tab 销毁（tab 往返只重建视图，不重建本控制器）。
class SimulatorsController extends ChangeNotifier {
  /// [dataDir] 数据目录解析 seam（生产 path_provider，测试注入临时目录）；
  /// [seed] 首启种子（F-25 兜底在编排内）；[createServer] 服务器工厂；
  /// [loadManifest] 清单拉取；[port] 固定端口（生产 8642，测试可传 0）；
  /// [manifestTimeout] 拉取超时守卫（缺省 TIMEOUT_MS=15s，测试注入短值）；
  /// [hooks] 四钩子（缺省未接线）。
  SimulatorsController({
    required SimulatorDataDir dataDir,
    required SimulatorSeeder seed,
    required SimulatorServerFactory createServer,
    required ManifestLoader loadManifest,
    SimulatorsHooks hooks = const SimulatorsHooks(),
    int port = SimulatorContracts.defaultPort,
    Duration manifestTimeout =
        const Duration(milliseconds: SimulatorContracts.timeoutMs),
  })  : _dataDir = dataDir,
        _seed = seed,
        _createServer = createServer,
        _loadManifest = loadManifest,
        _hooks = hooks,
        _externalHooks = hooks,
        _port = port,
        _manifestTimeout = manifestTimeout;

  final SimulatorDataDir _dataDir;
  final SimulatorSeeder _seed;
  final SimulatorServerFactory _createServer;
  final ManifestLoader _loadManifest;
  SimulatorsHooks _hooks;

  /// 构造注入的外部钩子（测试注入 / 未来外部装配）：[wireViewDefaults] 合并时
  /// 恒优先，视图默认槽位不覆盖——「既有注入钩子优先」契约的单一来源。
  final SimulatorsHooks _externalHooks;
  final Duration _manifestTimeout;

  SimulatorsState _state = SimulatorsState.loading;
  String? _errorMessage;
  List<SimulatorGame> _games = const [];
  SimulatorFilter _filter = SimulatorFilter.all;

  /// 当前监听端口（start 返回的实际端口；未启动时 = 构造端口）。
  int _port;

  /// 常驻服务器实例（编排成功即持有；错误态重试复用运行中实例）。
  SimulatorServer? _server;

  /// in-flight 编排 future（并发 ensure/refresh/retry 合并）。
  Future<void>? _inFlight;

  /// 列表当前状态。
  SimulatorsState get state => _state;

  /// 错误态面向用户文案（仅 state == error 时非空）。
  String? get errorMessage => _errorMessage;

  /// 当前筛选档位。
  SimulatorFilter get filter => _filter;

  /// 归一化游戏条目（按 [filter] 过滤）。
  List<SimulatorGame> get games => switch (_filter) {
        SimulatorFilter.all => List.unmodifiable(_games),
        SimulatorFilter.ai => List.unmodifiable([
            for (final game in _games)
              if (game.type == SimulatorGameType.ai) game,
          ]),
        SimulatorFilter.local => List.unmodifiable([
            for (final game in _games)
              if (game.type == SimulatorGameType.local) game,
          ]),
      };

  /// 全部游戏（**不过滤**——存档管理 sheet「一次管全部游戏」入口用，Q12；
  /// 与 [games]（按筛选）区隔）。
  List<SimulatorGame> get allGames => List.unmodifiable(_games);

  /// 打开游戏回调（F-M5-04 接线）；null = 未接线（卡片禁用开放语义）。
  void Function(SimulatorGame game)? get onOpen => _hooks.onOpen;

  /// 存档管理入口（F-M5-06 接线）；null = 未接线（AppBar 禁用态）。
  VoidCallback? get onSaveTap => _hooks.onSaveTap;

  /// 导入入口（F-M5-07 接线）；null = 未接线（AppBar 禁用态）。
  VoidCallback? get onImportTap => _hooks.onImportTap;

  /// AI 生成入口（F-M5-08b 接线）；null = 未接线（AppBar 禁用态）。
  VoidCallback? get onGenerateTap => _hooks.onGenerateTap;

  /// 接线钩子（后续票 F-M5-04/06/07/08 经 file-scope 实现注入；部分接线时
  /// 未提供槽位保持 null）。替换既有槽位并通知监听者。
  void registerHooks(SimulatorsHooks hooks) {
    _hooks = hooks;
    notifyListeners();
  }

  /// 视图层默认接线（F-M5-04/06/07/08b 统一入口，**每次视图挂载调用**）：
  /// 构造注入的外部钩子槽位恒优先（绝不覆盖），未接线槽位以 [viewDefaults]
  /// 填充——视图默认槽位每次挂载刷新为最新实现。
  ///
  /// W6 B1 修复语义：HomeShell 按 tab switch 直接切换（无 IndexedStack），
  /// 每次切回模拟器 tab 都是新 State 挂载；若只接线一次，AppBar 四入口闭包
  /// 将持有首次已卸载 State 的死 context。本方法每次挂载重新刷新视图默认
  /// 槽位，使闭包绑定当前 State（配合视图层 `mounted` 守卫，死 context 永不
  /// 落入回调）；外部注入槽位不参与刷新（既有注入钩子优先契约不变）。
  void wireViewDefaults(SimulatorsHooks viewDefaults) {
    _hooks = SimulatorsHooks(
      onOpen: _externalHooks.onOpen ?? viewDefaults.onOpen,
      onSaveTap: _externalHooks.onSaveTap ?? viewDefaults.onSaveTap,
      onImportTap: _externalHooks.onImportTap ?? viewDefaults.onImportTap,
      onGenerateTap: _externalHooks.onGenerateTap ?? viewDefaults.onGenerateTap,
    );
    notifyListeners();
  }

  /// 切换类型筛选档位（三档；重复选择不通知）。
  void selectFilter(SimulatorFilter filter) {
    if (filter == _filter) {
      return;
    }
    _filter = filter;
    notifyListeners();
  }

  /// 懒启动编排（首次进模拟器 tab 触发）：
  /// seed → server.start(8642) → 回环 HTTP manifest → 宽容解析 → ready/empty。
  ///
  /// 幂等：ready / empty 后重复调用短路（App 存续期不重种不重启）；loading
  /// 并发调用合并；error 后再次调用自动重试（错误态可 [retry]，语义等价）。
  Future<void> ensureStarted() async {
    if (_state == SimulatorsState.ready ||
        _state == SimulatorsState.empty) {
      return; // 已就绪：常驻幂等。
    }
    return _chain();
  }

  /// 下拉刷新（ready/empty 轻量重拉 manifest，不重种不重启）；error 态回退
  /// 全链重跑（等同 [retry]）；loading 合并 in-flight。
  Future<void> refresh() async {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    if (_state == SimulatorsState.error) {
      return _chain();
    }
    await _fetchManifest(port: _port);
  }

  /// 错误态重试：重新跑全链编排（seed 幂等 + server 运行中实例复用 /
  /// 失败实例重建 + 重拉 manifest）。
  Future<void> retry() => _chain();

  /// 编排入口：in-flight 合并 + 清理（body 延迟到 _inFlight 就位后执行，
  /// 防监听者重入起第二条链）。
  Future<void> _chain() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = Future<void>(_doStart);
    _inFlight = future;
    unawaited(
      future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _inFlight = null;
      }),
    );
    return future;
  }

  /// 全链编排正文：loading → seed（F-25 兜底）→ server → fetch → 终态。
  ///
  /// 平台挂起兜底（工单测试纪律先例）：数据目录解析 / 种子涉及平台通道
  /// （path_provider / rootBundle），在测试宿主可能永久挂起——每步加
  /// [_manifestTimeout] 超时守卫，挂起即转可读错误态 / 兜底继续，不阻塞。
  Future<void> _doStart() async {
    _state = SimulatorsState.loading;
    _games = const [];
    _errorMessage = null;
    notifyListeners();

    final Directory simDir;
    try {
      simDir = await _dataDir.resolve().timeout(_manifestTimeout);
    } on TimeoutException {
      _fail('解析模拟器数据目录超时，请重试');
      return;
    } catch (error) {
      _fail('解析模拟器数据目录失败: $error');
      return;
    }

    // F-25 兜底（W1 F-2 落债）：种子单游戏资产缺失（rootBundle 裸抛 / 挂起）
    // → 捕获不中止列表，继续 server + manifest 拉取，由盘面真实结果定终态。
    try {
      final seeded = await _seed(simDir).timeout(_manifestTimeout);
      debugPrint('模拟器首启种子: $seeded（false = 已种子 / 源缺降级）');
    } on TimeoutException {
      debugPrint('模拟器种子超时，继续启动链路');
    } catch (error) {
      debugPrint('模拟器种子失败（单游戏缺失等），继续启动链路: $error');
    }

    try {
      final server = _server;
      if (server == null || !server.isRunning) {
        final fresh = _createServer(simDir);
        _port = await fresh.start(port: _port);
        _server = fresh;
      }
      await _fetchManifest(port: _port);
    } on SimulatorPortInUseException catch (error) {
      // 明确错误态（含端口占用语义），绝不静默换端口。
      _fail(error.toString());
    } catch (error) {
      _fail('启动模拟器服务器失败: $error');
    }
  }

  /// 轻量拉取 + 解析：成功 → ready/empty；失败（超时 / HTTP / 解析）→ error。
  Future<void> _fetchManifest({required int port}) async {
    final ManifestParseResult result;
    try {
      result = await _loadManifest(port).timeout(_manifestTimeout);
    } on TimeoutException {
      _fail('加载游戏清单超时（${_manifestTimeout.inMilliseconds}ms），请重试');
      return;
    } catch (error) {
      _fail('加载游戏清单失败: $error');
      return;
    }
    if (!result.ok) {
      _fail(result.error ?? '游戏清单解析失败');
      return;
    }
    _games = [
      for (final raw in result.games!) SimulatorGame.fromManifest(raw),
    ];
    _errorMessage = null;
    _state = _games.isEmpty ? SimulatorsState.empty : SimulatorsState.ready;
    notifyListeners();
  }

  /// 进入错误态（清空列表 + 文案 + 通知）。
  void _fail(String message) {
    _games = const [];
    _errorMessage = message;
    _state = SimulatorsState.error;
    notifyListeners();
  }
}
