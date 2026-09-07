/// F-M5-08b AI 生成对话框 widget 测试——描述必填（空拦截）/ 标题可选 /
/// 生成中进度态（禁用提交防重复）/ 成功关闭 + toast + 列表刷新回调 / 校验
/// 失败展示 [{field}] {message} + 建议 + 重试/关闭（耗尽文案）/ 取消中止在途
/// 重试。
///
/// 测试 seam（公共接口边界）：[GenerateDialog]（generator 注入 fake LLM 编排
/// 脚本化路径；onGenerated 注入探针断言成功回调）——[ConverTheme.dark] 包裹
/// （F-7 教训），永不触真实网络与平台通道。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/llm/errors.dart' show LLMError;
import 'package:conver_system_mobile/services/llm/llm_provider.dart'
    show LLMProvider, LlmMessage;
import 'package:conver_system_mobile/services/simulator/game_generator.dart'
    show GameGenerator, GenerationCredentials;
import 'package:conver_system_mobile/services/simulator/import_service.dart'
    show ImportResult;
import 'package:conver_system_mobile/services/simulator/manifest_parser.dart'
    show ManifestParseResult;
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart'
    show SimulatorDataDir;
import 'package:conver_system_mobile/services/simulator/simulator_server.dart'
    show SimulatorServer;
import 'package:conver_system_mobile/theme/conver_theme.dart' show ConverTheme;
import 'package:conver_system_mobile/view_models/simulators_controller.dart'
    show SimulatorsController, SimulatorsState;
import 'package:conver_system_mobile/views/simulators/generate_dialog.dart'
    show GenerateDialog;
import 'package:conver_system_mobile/views/simulators/simulators_hooks.dart'
    show SimulatorsHooks;
import 'package:conver_system_mobile/views/simulators/simulators_view.dart'
    show SimulatorsView;

import '../../support/fake_llm_for_generation.dart'
    show
        FixedGenerationFactory,
        ScriptedFakeLLMProvider,
        buildInvalidGeneratedHtml,
        buildValidGeneratedHtml;

/// 对话框 harness：按钮 → showDialog 打开 [GenerateDialog]（真实 Navigator
/// 栈，对话框可 pop；toast 落在 MaterialApp 的 ScaffoldMessenger）。
class _DialogHarness extends StatelessWidget {
  const _DialogHarness({required this.dialog});

  final Widget dialog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => dialog,
            ),
            child: const Text('打开生成对话框'),
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  GameGenerator generator, {
  Future<void> Function()? onGenerated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ConverTheme.dark(),
      home: _DialogHarness(
        dialog: GenerateDialog(
          generator: generator,
          onGenerated: onGenerated,
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开生成对话框'));
  await tester.pumpAndSettle();
}

/// 对话框测试用生成器装配（脚本化 fake LLM；resolve 全 seam 注入）。
GameGenerator dialogGenerator({
  List<String> scripts = const [],
  Object? providerError,
  Future<Object?> Function({
    required LLMProvider provider,
    required List<LlmMessage> messages,
    required int maxTokens,
    required String model,
  })?
      callGenerate,
}) {
  final fake = ScriptedFakeLLMProvider(scripts: scripts);
  fake.error = providerError;
  return GameGenerator(
    providerFactory: FixedGenerationFactory(fake),
    resolveCredentials: () async => const GenerationCredentials(
      provider: 'claude',
      apiKey: 'sk-test',
      model: 'claude-sonnet-5',
    ),
    // 注意：testWidgets 运行于 FakeAsync zone，真实文件 IO（createTemp）future
    // 永不完成——resolveSimDir 返回已存在目录对象（同步构造不触 IO）。
    resolveSimDir: () async => Directory.systemTemp,
    callGenerate: callGenerate,
    persistGame: (dir, name, bytes) async => ImportResult(
      game: <String, dynamic>{
        'id': 'gen',
        'file': name,
        'name': '生成',
        'type': 'ai',
        'source': 'generated',
      },
      renamed: false,
      warnings: const <String>[],
    ),
  );
}

/// 输入描述并点击生成（enterText 后先 pump 使空拦截按钮启用，再 tap）。
Future<void> _enterDescription(
  WidgetTester tester,
  String description, {
  String? title,
}) async {
  if (title != null) {
    await tester.enterText(find.byKey(const Key('generate-title-field')), title);
  }
  await tester.enterText(
    find.byKey(const Key('generate-description-field')),
    description,
  );
  await tester.pump(); // setState 生效（生成按钮由禁用转启用）。
  await tester.tap(find.text('生成'));
  await tester.pump();
}

void main() {
  testWidgets('描述为空 → 生成按钮禁用（空拦截）；标题为可选项不阻塞',
      (tester) async {
    await _pumpDialog(tester, dialogGenerator());

    FilledButton generateButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '生成'),
        );
    expect(generateButton().onPressed, isNull,
        reason: '描述必填：空描述时提交禁用');

    // 标题可选：仅填标题仍禁用；填入描述后启用。
    await tester.enterText(
      find.byKey(const Key('generate-title-field')),
      '我的世界',
    );
    await tester.pump();
    expect(generateButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('generate-description-field')),
      '一个雾中的小镇',
    );
    await tester.pump();
    expect(generateButton().onPressed, isNotNull);
  });

  testWidgets('生成中：进度态出现 + 提交禁用防重复 + 取消可用', (tester) async {
    // callGenerate 挂起（永不完结）以稳定断言进度态。
    final generator = dialogGenerator(
      callGenerate:
          ({required provider, required messages, required maxTokens, required model}) {
        return Completer<Object?>().future;
      },
    );
    await _pumpDialog(tester, generator);
    await _enterDescription(tester, '海底世界');

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('正在生成'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '生成'), findsNothing,
        reason: '生成中提交不可重复触发');
    expect(find.text('取消'), findsOneWidget,
        reason: '生成中取消可用（中止在途重试）');
    // fake 未被真正调用（callGenerate 注入接管）；此处仅验证 UI 状态。
  });

  testWidgets('成功：对话框关闭 + toast「生成成功」+ onGenerated 刷新回调被调用',
      (tester) async {
    var refreshCalls = 0;
    final generator = dialogGenerator(
      scripts: [buildValidGeneratedHtml()],
    );
    await _pumpDialog(
      tester,
      generator,
      onGenerated: () async => refreshCalls++,
    );
    await _enterDescription(tester, '雾中镇', title: '雾中镇');

    await tester.pumpAndSettle();
    expect(find.text('AI 生成游戏'), findsNothing,
        reason: '成功 → 对话框关闭');
    expect(find.text('生成成功'), findsOneWidget, reason: '成功 toast');
    expect(refreshCalls, 1, reason: '落盘后列表刷新回调');
  });

  testWidgets('校验失败耗尽：错误列表 [{field}] {message} + 建议 + 耗尽文案 + '
      '「关闭」（无重试）', (tester) async {
    final generator = dialogGenerator(
      scripts: [buildInvalidGeneratedHtml()],
    );
    await _pumpDialog(tester, generator);
    await _enterDescription(tester, '注定失败');

    await tester.pumpAndSettle();
    expect(find.text('AI 生成游戏'), findsOneWidget,
        reason: '失败 → 对话框保留');
    expect(find.text('重试次数已用尽'), findsOneWidget);
    expect(find.textContaining('[template]'), findsOneWidget,
        reason: '错误列表展示 [{field}] {message}');
    expect(find.textContaining('[data]'), findsOneWidget);
    expect(find.textContaining('请确保已替换所有 <!-- GEN:config -->'),
        findsOneWidget,
        reason: '修正建议展示');
    expect(find.widgetWithText(FilledButton, '重试'), findsNothing,
        reason: '耗尽后按钮转「关闭」');
    expect(find.widgetWithText(FilledButton, '关闭'), findsOneWidget);

    // 关闭 → 对话框消失。
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('AI 生成游戏'), findsNothing);
  });

  testWidgets('LLM 调用异常 → 失败文案 + 「重试」按钮（未超重试次数时）',
      (tester) async {
    final generator = dialogGenerator(
      providerError: LLMError('claude API 请求超时'),
    );
    await _pumpDialog(tester, generator);
    await _enterDescription(tester, '网络不佳');

    await tester.pumpAndSettle();
    expect(find.textContaining('claude API 请求超时'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget,
        reason: '未进入编排计数的失败 → 重试可用');
    expect(find.widgetWithText(TextButton, '关闭'), findsOneWidget,
        reason: '非耗尽失败 → 关闭按钮（TextButton）');
  });

  testWidgets('重试按钮：点击重新发起新一轮生成 → 成功关闭', (tester) async {
    // 第一次调用抛 LLM 错误，第二次成功（脚本重试后通过）。
    var throws = true;
    final generator = dialogGenerator(
      callGenerate:
          ({required provider, required messages, required maxTokens, required model}) {
        if (throws) {
          throws = false;
          return Future<Object?>.error(LLMError('claude API 请求超时'));
        }
        return Future<Object?>.value(buildValidGeneratedHtml());
      },
    );
    await _pumpDialog(tester, generator);
    await _enterDescription(tester, '雾中镇');

    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('AI 生成游戏'), findsNothing, reason: '重试成功 → 关闭');
    expect(find.text('生成成功'), findsOneWidget);
  });

  testWidgets('取消：生成中取消 → 中止在途重试 + 对话框关闭', (tester) async {
    // 第二次调用挂起（gate）模拟在途生成；取消后释放 gate → 校验失败 →
    // 重试入口断言 cancel → 中止（不再发起第 3 次调用）。
    final gate = Completer<Object?>();
    var calls = 0;
    final generator = GameGenerator(
      providerFactory: FixedGenerationFactory(ScriptedFakeLLMProvider.empty()),
      resolveCredentials: () async => const GenerationCredentials(
        provider: 'claude',
        apiKey: 'sk-test',
        model: 'claude-sonnet-5',
      ),
      resolveSimDir: () async => Directory.systemTemp,
      callGenerate:
          ({required provider, required messages, required maxTokens, required model}) {
        calls++;
        if (calls == 1) {
          return Future<Object?>.value(buildInvalidGeneratedHtml());
        }
        return gate.future;
      },
      persistGame: (dir, name, bytes) async => ImportResult(
        game: <String, dynamic>{
          'id': 'gen',
          'file': name,
          'name': '生成',
          'type': 'ai',
          'source': 'generated',
        },
        renamed: false,
        warnings: const <String>[],
      ),
    );
    await _pumpDialog(tester, generator);
    await _enterDescription(tester, '取消测试');

    // 首试坏 HTML → 第二次调用在途（gate 挂起）→ 用户点「取消」。
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(calls, 2, reason: '首试 + 第二次在途（取消时已发起）');

    // 释放在途调用 → 校验失败 → 重试入口断言 cancel → 中止后续重试并关闭。
    gate.complete(buildInvalidGeneratedHtml());
    await tester.pumpAndSettle();

    expect(find.text('AI 生成游戏'), findsNothing, reason: '取消 → 对话框关闭');
    expect(calls, 2, reason: '取消后不再发起第 3 次 LLM 调用（不泄漏在途调用）');
  });

  group('hooks 接线 — SimulatorsView AI 生成入口派发到对话框打开器', () {
    late Directory parentDir;
    late SimulatorDataDir dataDir;

    setUp(() async {
      parentDir = await Directory.systemTemp.createTemp('m5-08b-view-');
      dataDir = SimulatorDataDir(resolveDocumentsDir: () async => parentDir);
    });

    testWidgets('默认 hooks 下：AppBar「AI 生成」启用 → 点击派发注入 opener',
        (tester) async {
      var opened = 0;
      final controller = SimulatorsController(
        dataDir: dataDir,
        seed: (_) async => false,
        createServer: (_) => _GenViewStubServer(),
        loadManifest: (_) async => const ManifestParseResult.success([]),
        port: 0,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: SimulatorsView(
            controller: controller,
            openGenerateDialog: (context) async => opened++,
          ),
        ),
      );
      await _settleView(tester, controller);
      final generateButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.auto_awesome_outlined),
      );
      expect(generateButton.onPressed, isNotNull,
          reason: 'F-M5-08b 接线后「AI 生成」入口不再禁用');

      await tester.tap(find.byTooltip('AI 生成'));
      await tester.pump();
      expect(opened, 1, reason: 'AppBar AI 生成入口派发到对话框打开器');
    });

    testWidgets('既有注入钩子优先：constructor hooks.onGenerateTap 不被覆盖',
        (tester) async {
      var injectedTaps = 0;
      final controller = SimulatorsController(
        dataDir: dataDir,
        seed: (_) async => false,
        createServer: (_) => _GenViewStubServer(),
        loadManifest: (_) async => const ManifestParseResult.success([]),
        port: 0,
        hooks: SimulatorsHooks(onGenerateTap: () => injectedTaps++),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: SimulatorsView(controller: controller),
        ),
      );
      await _settleView(tester, controller);
      await tester.tap(find.byTooltip('AI 生成'));
      await tester.pump();
      expect(injectedTaps, 1, reason: 'constructor 注入钩子优先于默认接线');
    });
  });
}

/// pump 至控制器离开 loading（flush 懒启动编排的零延迟 timer 与微任务链）。
Future<void> _settleView(
  WidgetTester tester,
  SimulatorsController controller,
) async {
  for (var i = 0; i < 200 && controller.state == SimulatorsState.loading; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pump();
}

/// 服务器桩（真实监听能力不在生成接线测试范围）。
class _GenViewStubServer extends SimulatorServer {
  _GenViewStubServer() : super(Directory.systemTemp);

  bool _running = false;

  @override
  Future<int> start({required int port}) async {
    _running = true;
    return port;
  }

  @override
  Future<void> stop() async {}

  @override
  bool get isRunning => _running;
}
