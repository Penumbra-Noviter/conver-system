/// F-M5-03 SimulatorsView widget 行为契约——四态列表 + AppBar 三入口 + 筛选
/// + 下拉刷新 + 钩子派发。
///
/// 验收语义（工单验收语义契约逐条）：
/// - loading（进度指示）→ ready（卡片网格：名称 / 类型徽标〔AI 驱动·纯本地〕
///   / 导入·生成 badge〔source 判据〕/ 点击打开）；
/// - error（文案 + 「重试」按钮）；empty（「暂无游戏」文案）；ready 下拉刷新
///   触发 [SimulatorsController.refresh]；
/// - 类型筛选 chips 三档（全部 / AI 驱动 / 纯本地）；
/// - AppBar「存档 / 导入 / AI 生成」三入口渲染，钩子未接线（缺省 null）时呈
///   禁用态，接线后点击直达对应回调（本票只保证渲染 + 钩子派发）；
/// - 视图 init 后帧触发 [ensureStarted]（懒启动，仅首进发起）；
/// - 卡片 onTap → `hooks.onOpen(game)`（运行页导航本体归 F-M5-04）。
///
/// 测试 seam（公共接口边界）：[SimulatorsView]（controller 注入）+ 控制器
/// 四依赖全 fake（seed / server 工厂 / manifest 拉取 / dataDir 临时目录），
/// 永不触平台通道与真实 socket；[ConverTheme.dark] 包裹（ConverPalette 依赖）。
/// 装配基座内联于本文件（仓库惯例：不进 helpers）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/manifest_parser.dart';
import 'package:conver_system_mobile/services/simulator/save_bridge.dart';
import 'package:conver_system_mobile/services/simulator/simulator_contracts.dart';
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart';
import 'package:conver_system_mobile/services/simulator/simulator_server.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/simulators_controller.dart';
import 'package:conver_system_mobile/views/simulators/simulators_hooks.dart';
import 'package:conver_system_mobile/views/simulators/simulators_view.dart';

/// 三游戏 fixture：ai（内置无 badge）+ local/imported + ai/generated。
const String manifest3Json = '''
{"version":2,"simulators":[
  {"id":"life-sim","file":"人生模拟器v3.html","name":"人生模拟器 v3","type":"ai",
   "description":"AI 驱动的生命模拟"},
  {"id":"local-x","file":"local-x.html","name":"本地示例","type":"local",
   "description":"纯本地游戏","source":"imported"},
  {"id":"gen-game","file":"gen.html","name":"生成的冒险","type":"ai",
   "description":"AI 生成","source":"generated"}
]}
''';

class _SeedFake {
  int calls = 0;
  Completer<bool>? hang;

  Future<bool> call(Directory simDir) async {
    calls++;
    final h = hang;
    if (h != null) {
      return h.future;
    }
    return false;
  }
}

class _ManifestFake {
  int calls = 0;
  ManifestParseResult result = const ManifestParseResult.success([]);

  Future<ManifestParseResult> call(int port) async {
    calls++;
    return result;
  }
}

class _StubServer extends SimulatorServer {
  _StubServer({required this.reportPort}) : super(Directory.systemTemp);

  final int reportPort;
  bool _running = false;

  @override
  Future<int> start({required int port}) async {
    _running = true;
    return reportPort;
  }

  @override
  Future<void> stop() async {}

  @override
  bool get isRunning => _running;
}

/// 记录调用链的 hooks（断言 AppBar 入口派发 + 卡片 open 派发）。
class _RecordingHooks extends SimulatorsHooks {
  _RecordingHooks();

  int saveTaps = 0;
  int importTaps = 0;
  int generateTaps = 0;
  int openCalls = 0;
  SimulatorGame? openedGame;

  @override
  VoidCallback? get onSaveTap => () => saveTaps++;

  @override
  VoidCallback? get onImportTap => () => importTaps++;

  @override
  VoidCallback? get onGenerateTap => () => generateTaps++;

  @override
  void Function(SimulatorGame game)? get onOpen => (game) {
        openCalls++;
        openedGame = game;
      };
}

/// 探针存档 sheet：断言 AppBar「存档」入口已接线并收到换算后的游戏集。
class _ProbeSaveSheet extends StatelessWidget {
  const _ProbeSaveSheet({required this.games});

  final List<SaveGame> games;

  @override
  Widget build(BuildContext context) =>
      Text('存档 sheet 已打开（${games.length} 款）');
}

void main() {
  late Directory parent;
  late SimulatorDataDir dataDir;
  late _SeedFake seed;
  late _ManifestFake manifest;
  late SimulatorsController controller;

  SimulatorsController buildController({
    SimulatorsHooks hooks = const SimulatorsHooks(),
    _StubServer? stub,
    Duration manifestTimeout =
        const Duration(milliseconds: SimulatorContracts.timeoutMs),
  }) {
    controller = SimulatorsController(
      dataDir: dataDir,
      seed: seed.call,
      createServer: (dir) => stub ?? _StubServer(reportPort: 8642),
      loadManifest: manifest.call,
      port: 0,
      manifestTimeout: manifestTimeout,
      hooks: hooks,
    );
    return controller;
  }

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('m5-03-view-');
    addTearDown(() => parent.delete(recursive: true));
    dataDir = SimulatorDataDir(resolveDocumentsDir: () async => parent);
    seed = _SeedFake();
    manifest = _ManifestFake();
  });

  tearDown(() {
    controller.dispose();
  });

  /// 组装视图并往返 pump 至编排完成（或明确停在 loading 态）。
  Future<void> pumpView(
    WidgetTester tester, {
    bool settle = true,
    SaveSheetBuilder? saveSheetBuilder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: SimulatorsView(
          controller: controller,
          saveSheetBuilder: saveSheetBuilder,
        ),
      ),
    );
    if (settle) {
      for (var i = 0;
          i < 200 && controller.state == SimulatorsState.loading;
          i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();
    }
  }

  group('四态渲染', () {
    testWidgets('loading → 进度指示（首次编排完成前）', (tester) async {
      buildController();
      seed.hang = Completer<bool>();

      await pumpView(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('人生模拟器 v3'), findsNothing);

      seed.hang!.complete(true);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('ready：卡片网格含名称/描述/类型徽标/导入·生成 badge', (tester) async {
      buildController();
      manifest.result = parseManifest(manifest3Json);

      await pumpView(tester);

      expect(controller.state, SimulatorsState.ready);
      expect(find.text('人生模拟器 v3'), findsOneWidget);
      expect(find.text('本地示例'), findsOneWidget);
      expect(find.text('生成的冒险'), findsOneWidget);

      // 类型徽标（卡片内，排除 chips 行）。
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text('AI 驱动')),
        findsNWidgets(2),
        reason: '两枚 AI 卡片带「AI 驱动」徽标',
      );
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text('纯本地')),
        findsOneWidget,
      );
      // source 判据 badge。
      expect(find.text('导入'), findsOneWidget);
      expect(find.text('生成'), findsOneWidget);
      // AppBar 关闭后测试结束（路由安放由宿主处理）。
    });

    testWidgets('error：错误文案 + 重试按钮；点击重试后进入 ready', (tester) async {
      buildController();
      manifest.result = const ManifestParseResult.failure('manifest 损坏');

      await pumpView(tester);

      expect(controller.state, SimulatorsState.error);
      expect(find.text('manifest 损坏'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      manifest.result = parseManifest(manifest3Json);
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));

      expect(controller.state, SimulatorsState.ready);
      expect(find.text('人生模拟器 v3'), findsOneWidget);
    });

    testWidgets('empty：暂无游戏文案（合法空态）', (tester) async {
      buildController();
      manifest.result = parseManifest('{"version":2,"simulators":[]}');

      await pumpView(tester);

      expect(controller.state, SimulatorsState.empty);
      expect(find.text('暂无游戏'), findsOneWidget);
    });
  });

  group('筛选 chips · 三档', () {
    testWidgets('三档 chips 渲染；切「纯本地」过滤列表', (tester) async {
      buildController();
      manifest.result = parseManifest(manifest3Json);

      await pumpView(tester);

      expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'AI 驱动'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '纯本地'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '纯本地'));
      await tester.pump();

      expect(controller.filter, SimulatorFilter.local);
      expect(find.text('本地示例'), findsOneWidget);
      expect(find.text('人生模拟器 v3'), findsNothing, reason: 'AI 卡被过滤');
      expect(find.text('生成的冒险'), findsNothing);
    });
  });

  group('AppBar 三入口 · 渲染 / 禁用态 / 接线派发', () {
    testWidgets('默认接线：存档/导入入口可用（生成仍禁用）；点击存档 → 打开 sheet',
        (tester) async {
      buildController();
      manifest.result = parseManifest(manifest3Json);

      await pumpView(
        tester,
        // 探针 sheet（生产 SaveSheet 真渲染归 F-M5-06 save_sheet_test；此处
        // 只锚入口接线与游戏集映射）。
        saveSheetBuilder: (games) => _ProbeSaveSheet(games: games),
      );

      expect(find.byTooltip('存档管理'), findsOneWidget);
      expect(find.byTooltip('导入'), findsOneWidget);
      expect(find.byTooltip('AI 生成'), findsOneWidget);

      final saveButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.archive_outlined),
      );
      final importButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.file_open_outlined),
      );
      final generateButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.auto_awesome_outlined),
      );
      expect(saveButton.onPressed, isNotNull,
          reason: '存档已由 F-M5-06 自动接线（AppBar → 底部半屏 sheet）');
      expect(importButton.onPressed, isNotNull,
          reason: '导入已由 F-M5-07 接线（默认 hooks 下视图自动填充导入流）');
      expect(generateButton.onPressed, isNull,
          reason: '生成未接线（F-M5-08b）= 禁用态');

      // 点击存档 → 打开 sheet（演示注入 builder 收到全部游戏映射面）。
      await tester.tap(find.byTooltip('存档管理'));
      await tester.pumpAndSettle();
      expect(find.text('存档 sheet 已打开（3 款）'), findsOneWidget);
    });

    testWidgets('筛选态下打开存档面板仍收到全部游戏（Q12 一次管全部）',
        (tester) async {
      buildController();
      manifest.result = parseManifest(manifest3Json);
      await pumpView(
        tester,
        saveSheetBuilder: (games) => _ProbeSaveSheet(games: games),
      );

      // 纯本地筛选态只剩 1 款，但存档面板仍须收到全部 3 款。
      await tester.tap(find.widgetWithText(ChoiceChip, '纯本地'));
      await tester.pump();

      await tester.tap(find.byTooltip('存档管理'));
      await tester.pumpAndSettle();
      expect(find.text('存档 sheet 已打开（3 款）'), findsOneWidget);
    });

    testWidgets('接线后点击三入口 → 派发对应回调', (tester) async {
      final hooks = _RecordingHooks();
      buildController(hooks: hooks);
      manifest.result = parseManifest(manifest3Json);

      await pumpView(tester);

      await tester.tap(find.byTooltip('存档管理'));
      await tester.pump();
      expect(hooks.saveTaps, 1, reason: '存档入口派发 onSaveTap（F-M5-06 接线点）');

      await tester.tap(find.byTooltip('导入'));
      await tester.pump();
      expect(hooks.importTaps, 1, reason: '导入入口派发 onImportTap（F-M5-07 接线点）');

      await tester.tap(find.byTooltip('AI 生成'));
      await tester.pump();
      expect(hooks.generateTaps, 1, reason: '生成入口派发 onGenerateTap（F-M5-08b 接线点）');
    });
  });

  group('卡片打开 · hooks.onOpen', () {
    testWidgets('点击卡片 → 派发 onOpen(game)（F-M5-04 接线点）', (tester) async {
      final hooks = _RecordingHooks();
      buildController(hooks: hooks);
      manifest.result = parseManifest(manifest3Json);

      await pumpView(tester);
      await tester.tap(find.text('人生模拟器 v3'));
      await tester.pump();

      expect(hooks.openCalls, 1);
      expect(hooks.openedGame?.id, 'life-sim', reason: 'open 收到目标游戏归一化条目');
    });

    testWidgets('未接线（onOpen null）→ 点击卡片不崩不导航', (tester) async {
      buildController();
      manifest.result = parseManifest(manifest3Json);

      await pumpView(tester);
      await tester.tap(find.text('人生模拟器 v3'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('下拉刷新 · RefreshIndicator → controller.refresh', () {
    testWidgets('ready 态下拉 → 重新拉取 manifest 并展示新增游戏', (tester) async {
      buildController();
      manifest.result = parseManifest(manifest3Json);

      await pumpView(tester);
      expect(controller.games, hasLength(3));
      expect(manifest.calls, 1);

      // 数据源新增一款（模拟导入落盘）后下拉刷新。
      manifest.result = parseManifest('''
{"version":2,"simulators":[
  {"id":"life-sim","file":"人生模拟器v3.html","name":"人生模拟器 v3","type":"ai","description":"x"},
  {"id":"local-x","file":"local-x.html","name":"本地示例","type":"local","description":"y"},
  {"id":"gen-game","file":"gen.html","name":"生成的冒险","type":"ai","description":"z"},
  {"id":"new-game","file":"new.html","name":"新游戏","type":"ai","description":"w"}
]}
''');

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(manifest.calls, 2, reason: '下拉刷新触发 controller.refresh 重拉');
      expect(find.text('新游戏'), findsOneWidget);
    });
  });
}