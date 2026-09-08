/// F-M5-04 SimulatorRunView widget 行为契约——WebView 运行页（fake seam 隔离
/// 平台通道）+ 自动注入（静默）/ 重新同步（反馈）/ 官方端点提示条 / 非法 file
/// 守卫 / 15s 超时错误态。
///
/// 测试 seam（公共接口边界）：[SimulatorRunView]（注入 fake WebView 控制器
/// 工厂 + fake 凭证/官方端点装载闭包），永不触真实 webview_flutter 平台通道
/// （U1 三件套：控制器抽象隔离；JS 常量串金样断言在 injection_test.dart；
/// AVD 冒烟读回归 F-M5-09）。
///
/// 安全纪律：本测试只用 fake key（`sk-test-run-1`）占位，永不携带真实密钥。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:drift/native.dart';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/services/simulator/injection.dart';
import 'package:conver_system_mobile/services/simulator/simulator_contracts.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/simulators_controller.dart';
import 'package:conver_system_mobile/views/simulators/simulator_run_view.dart';
import 'package:conver_system_mobile/views/simulators/simulators_hooks.dart';

import '../../helpers/in_memory_secret_store.dart';

const String _bannerText =
    '当前官方端点不支持游戏直连；请使用 DeepSeek/Kimi/GLM/Qwen '
    '等国产兼容端点，或改用桌面版运行';

const String _claudeOnlyText = '游戏仅支持 OpenAI 兼容 Key';
const String _noCredentialsText = '未配置 OpenAI 兼容 Key';
const String _resyncText = '重新同步';
const String _injectedText = '已填入';

/// Fake WebView 控制器：记录 runJavaScript 调用 + 可手动触发 onPageFinished
/// + 调用序 spy（setOnPageFinished / navigate，F-43）+ 最严苛竞态窗口开关。
class _FakeWebViewController implements SimulatorWebViewController {
  _FakeWebViewController({
    this.instantFinish = false,
    this.throwOnNavigate = false,
  });

  /// 最严苛竞态开关：navigate 发起即完成 → onPageFinished 在挂载后的第一
  /// 时间派发（委托若未先于 navigate 挂载即静默丢事件 → 15s 超时错误态）。
  final bool instantFinish;

  /// navigate 抛错开关（loadRequest 失败路径：即时错误态，不靠超时兜底）。
  final bool throwOnNavigate;

  final List<String> scripts = <String>[];
  final List<Uri> navigatedUrls = <Uri>[];
  final List<String> callOrder = <String>[];
  VoidCallback? onPageFinished;

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  @override
  void setOnPageFinished(VoidCallback onPageFinished) {
    callOrder.add('setOnPageFinished');
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> navigate(Uri url) async {
    callOrder.add('navigate');
    navigatedUrls.add(url);
    if (throwOnNavigate) {
      throw StateError('loadRequest 失败');
    }
    if (instantFinish) {
      // 导航发起即完成：事件在「挂载后、任何补救窗口前」立即派发。
      onPageFinished?.call();
    }
  }

  @override
  Widget buildView() => const SizedBox.expand();
}

/// Fake 控制器工厂：暴露已创建的控制器（URL 断言移入 navigate 记录）。
class _FakeWebViewFactory {
  final List<_FakeWebViewController> created = <_FakeWebViewController>[];
  bool instantFinish = false;
  bool throwOnNavigate = false;
  bool throwOnCreate = false;

  Future<SimulatorWebViewController> create() async {
    if (throwOnCreate) {
      throw StateError('WebView 平台不可用');
    }
    final controller = _FakeWebViewController(
      instantFinish: instantFinish,
      throwOnNavigate: throwOnNavigate,
    );
    created.add(controller);
    return controller;
  }
}

/// openai 凭证（fake key 占位）。
Future<InjectedCredentials> Function() _openaiCreds() => () async =>
    const InjectedCredentials(
      protocol: 'openai',
      key: 'sk-test-run-1',
      endpoint: 'https://api.deepseek.com/v1',
      model: 'deepseek-v4-flash',
    );

Future<InjectedCredentials> Function() _claudeCreds() => () async =>
    const InjectedCredentials(protocol: 'claude', key: '', endpoint: '', model: '');

Future<InjectedCredentials> Function() _noneCreds() => () async =>
    const InjectedCredentials(protocol: 'none', key: '', endpoint: '', model: '');

SimulatorGame _aiGame({String file = 'life-sim.html'}) => SimulatorGame(
      id: 'life-sim',
      file: file,
      name: '人生模拟器 v3',
      description: 'AI 驱动的生命模拟',
      type: SimulatorGameType.ai,
      endpointMode: 'full',
      config: const <String, dynamic>{
        'endpoint': 'cfg-endpoint',
        'apikey': 'cfg-apikey',
        'model': 'cfg-model',
      },
    );

SimulatorGame _localGame() => SimulatorGame(
      id: 'local-x',
      file: 'local-x.html',
      name: '本地示例',
      description: '纯本地游戏',
      type: SimulatorGameType.local,
    );

void main() {
  Future<void> pumpRunView(
    WidgetTester tester, {
    required SimulatorGame game,
    required _FakeWebViewFactory factory,
    required Future<InjectedCredentials> Function() loadCredentials,
    Future<bool> Function()? checkOfficialEndpoint,
    Duration? loadTimeout,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: SimulatorRunView(
          game: game,
          webViewFactory: factory.create,
          loadCredentials: loadCredentials,
          checkOfficialEndpoint:
              checkOfficialEndpoint ?? () async => false,
          port: 8642,
          loadTimeout: loadTimeout ??
              const Duration(milliseconds: SimulatorContracts.timeoutMs),
        ),
      ),
    );
    // 工厂 create + 初始化 microtask 落定。
    await tester.pump();
  }

  group('加载 + 自动注入（onPageFinished 静默）', () {
    testWidgets('页面加载完成 → 自动注入一次且无「已填入」反馈', (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );

      expect(factory.created, hasLength(1));
      final controller = factory.created.single;
      expect(controller.onPageFinished, isNotNull);

      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      expect(controller.scripts, hasLength(1), reason: '自动注入一次（静默）');
      expect(controller.scripts.single, contains('sk-test-run-1'));
      // 配置三元组与就绪轮询 marker 随真 InjectionScript 进脚本。
      expect(controller.scripts.single, contains("'apikey', 'endpoint', 'model'"));
      // 静默自动注入不闪「已填入」。
      expect(find.text(_injectedText), findsNothing);
      expect(find.text(_resyncText), findsOneWidget, reason: 'openai 态按钮可点');
    });

    testWidgets('URL 组装：http://127.0.0.1:8642/simulators/<file>（端口 8642）',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );

      expect(
        factory.created.single.navigatedUrls.single,
        Uri.parse(
          'http://127.0.0.1:8642/${SimulatorContracts.simDir}/life-sim.html',
        ),
      );
    });

    testWidgets('endpointMode 组成：原始 endpoint + full 标志随真脚本进页面（转换在页内执行）',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );

      factory.created.single.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      final script = factory.created.single.scripts.single;
      // 原始 base URL 进凭证 JSON（口径转换在页内 convertEndpoint 执行，
      // 与桌面 injectCredentialsIntoGame 同构；转换语义由纯函数 + JS 金样
      // marker 双层锁）。
      expect(script, contains('"endpoint":"https://api.deepseek.com/v1"'));
      expect(script, contains('endpointMode = "full"'));
      expect(script, contains("'/chat/completions'"));
      expect(script, contains('function convertEndpoint'));
    });
  });

  group('重新同步 · 手动注入 + 反馈状态机', () {
    testWidgets('点击重新同步 → 再注入一次 + 「已填入」2s 后复位为重新同步',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );
      final controller = factory.created.single;
      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();
      expect(controller.scripts, hasLength(1));

      await tester.tap(find.text(_resyncText));
      await tester.pump();
      await tester.pump();

      expect(controller.scripts, hasLength(2), reason: '手动注入追加一次');
      expect(find.text(_injectedText), findsOneWidget, reason: '成功反馈「已填入」');
      expect(find.text(_resyncText), findsNothing);

      // 反馈期间按钮禁用：不可重复注入。
      await tester.tap(find.text(_injectedText), warnIfMissed: false);
      await tester.pump();
      expect(controller.scripts, hasLength(2), reason: '反馈期间禁点');

      // 2s 后复位可点。
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_resyncText), findsOneWidget);
      expect(find.text(_injectedText), findsNothing);
    });

    testWidgets('claude 态：按钮禁用 + 禁用文案，自动/手动均不注入（claude key 不进游戏）',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _claudeCreds(),
      );
      final controller = factory.created.single;

      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      expect(controller.scripts, isEmpty, reason: 'claude 不注入');
      expect(find.text(_claudeOnlyText), findsOneWidget);
      expect(find.text('sk-ant-anything'), findsNothing, reason: 'claude key 不得出现在任何界面');

      await tester.tap(find.text(_resyncText));
      await tester.pump();
      await tester.pump();
      expect(controller.scripts, isEmpty, reason: 'claude 手动重同步亦不注入');
    });

    testWidgets('none 态：禁用文案「未配置 OpenAI 兼容 Key」', (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _noneCreds(),
      );
      final controller = factory.created.single;

      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      expect(controller.scripts, isEmpty);
      expect(find.text(_noCredentialsText), findsOneWidget);
    });

    testWidgets('openai 但空 key（防御）→ none 禁用文案', (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: () async => const InjectedCredentials(
          protocol: 'openai',
          key: '',
          endpoint: 'https://api.deepseek.com/v1',
          model: 'deepseek-v4-flash',
        ),
      );
      final controller = factory.created.single;

      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      expect(controller.scripts, isEmpty);
      expect(find.text(_noCredentialsText), findsOneWidget);
    });

    testWidgets('凭证装载失败（安全存储异常等）→ 静默降级：不弹错、按钮复位可点',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: () async => throw Exception('secure storage error'),
      );
      final controller = factory.created.single;

      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '失败静默不崩');
      expect(controller.scripts, isEmpty);
      expect(find.text(_resyncText), findsOneWidget, reason: '降级为可点');
      expect(find.text(_claudeOnlyText), findsNothing);
    });
  });

  group('官方端点提示条（Q8）', () {
    testWidgets('checkOfficialEndpoint true → 顶部提示条逐字文案；注入照常静默',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
        checkOfficialEndpoint: () async => true,
      );

      expect(find.text(_bannerText), findsOneWidget, reason: '官方端点提示条逐字文案');

      final controller = factory.created.single;
      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();
      expect(controller.scripts, hasLength(1), reason: '提示时注入照常');
    });

    testWidgets('checkOfficialEndpoint false → 无提示条', (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
        checkOfficialEndpoint: () async => false,
      );

      expect(find.text(_bannerText), findsNothing);
    });
  });

  group('非法 file → 错误态不建页', () {
    testWidgets('file 含路径分隔符 → 错误文案，工厂不创建控制器', (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(file: '../evil.html'),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );

      expect(find.text('游戏加载失败'), findsOneWidget);
      expect(find.text('参数非法：缺少有效的游戏文件'), findsOneWidget);
      expect(factory.created, isEmpty, reason: '非法 file 不建页不放行');
      expect(find.text(_resyncText), findsNothing);
    });
  });

  group('15s 超时 → 错误态 + 重试', () {
    testWidgets('超时（15 秒未收到响应）→ 错误态；重试复用当前游戏重新加载注入',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );

      // 不触发 onPageFinished，推进 16s 越过 15s 守卫。
      await tester.pump(const Duration(seconds: 16));

      expect(find.text('游戏加载失败'), findsOneWidget);
      expect(find.text('加载超时（15 秒未收到响应）'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
      expect(factory.created, hasLength(1));

      // 「返回」按钮（根路由 maybePop 空操作不崩）。
      await tester.tap(find.text('返回'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 重试复用当前游戏：重建控制器 → 新注入周期。
      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();

      expect(factory.created, hasLength(2), reason: '重试重建控制器');
      final retried = factory.created.last;
      expect(retried.navigatedUrls.last, Uri.parse(
        'http://127.0.0.1:8642/${SimulatorContracts.simDir}/life-sim.html',
      ));
      retried.onPageFinished?.call();
      await tester.pump();
      await tester.pump();
      expect(retried.scripts, hasLength(1), reason: '重试后加载完成照常注入');
    });
  });

  group('F-43 · onPageFinished 委托先于导航挂载（对齐 save_sheet W5 B1）', () {
    testWidgets('调用序 spy：setOnPageFinished 在 navigate 之前', (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );
      final controller = factory.created.single;
      final mountAt = controller.callOrder.indexOf('setOnPageFinished');
      final navigateAt = controller.callOrder.indexOf('navigate');
      expect(mountAt, greaterThanOrEqualTo(0), reason: '委托必须被挂载');
      expect(navigateAt, greaterThan(mountAt),
          reason: 'F-43：挂委托先于 navigate——onPageFinished 只派发给挂载时'
              '已存在的委托（不回放挂载前事件），先导航后挂委托即事件丢失'
              '→ 秒开页面走 15s 超时错误态（有兜底不挂死）');
    });

    testWidgets('秒开页面：navigate 发起即完成事件仍送达 → loaded + 注入，零超时',
        (tester) async {
      final factory = _FakeWebViewFactory()..instantFinish = true;
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
        loadTimeout: const Duration(milliseconds: 100),
      );
      await tester.pump();
      await tester.pump();

      final controller = factory.created.single;
      // 事件在「导航发起即完成」的最严苛时序下仍被送达（委托先挂载 → 不丢）。
      expect(controller.scripts, hasLength(1),
          reason: '秒开页自动注入照常（注入仍 onPageFinished 后）');
      expect(find.text('游戏加载失败'), findsNothing);
      // 越过超时窗口不降级（事件未丢，无 15s 超时错误态）。
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('游戏加载失败'), findsNothing);
      expect(find.textContaining('加载超时'), findsNothing);
    });
  });

  group('工厂 / 导航失败路径（即时错误态，不靠超时兜底）', () {
    testWidgets('工厂抛错（平台不可用）→ 错误态文案「加载模拟器页面失败」',
        (tester) async {
      final factory = _FakeWebViewFactory()..throwOnCreate = true;
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );
      await tester.pump();

      expect(find.text('游戏加载失败'), findsOneWidget);
      expect(find.textContaining('加载模拟器页面失败'), findsOneWidget);
      expect(find.textContaining('加载超时'), findsNothing,
          reason: '工厂抛错即时降级，不等待 15s 超时');
    });

    testWidgets('navigate 抛错（loadRequest 失败）→ 即时错误态', (tester) async {
      final factory = _FakeWebViewFactory()..throwOnNavigate = true;
      await pumpRunView(
        tester,
        game: _aiGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );
      await tester.pump();

      expect(find.textContaining('加载模拟器页面失败'), findsOneWidget);
      expect(find.textContaining('加载超时'), findsNothing,
          reason: 'loadRequest 失败即时降级，不等待 15s 超时');
      expect(tester.takeException(), isNull);
    });
  });

  group('非 AI 游戏（纯本地）', () {
    testWidgets('无同步控件不注入：无重新同步按钮、无脚本', (tester) async {
      final factory = _FakeWebViewFactory();
      await pumpRunView(
        tester,
        game: _localGame(),
        factory: factory,
        loadCredentials: _openaiCreds(),
      );
      final controller = factory.created.single;

      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      expect(controller.scripts, isEmpty, reason: '纯本地游戏不注入');
      expect(find.text(_resyncText), findsNothing);
      expect(find.text(_claudeOnlyText), findsNothing);
      expect(find.text(_noCredentialsText), findsNothing);
    });
  });

  group('runPageLauncher 接线（hooks.onOpen → push 运行页）', () {
    testWidgets('launcher 回调 → push SimulatorRunView；加载完成照常自动注入',
        (tester) async {
      final factory = _FakeWebViewFactory();
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    // 装配点同构：卡片 onTap 经 hooks.open 调用本 launcher。
                    buildRunPageLauncher(
                      context,
                      webViewFactory: factory.create,
                      loadCredentials: _openaiCreds(),
                      checkOfficialEndpoint: () async => false,
                    )(_aiGame());
                  },
                  child: const Text('打开游戏'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开游戏'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SimulatorRunView), findsOneWidget, reason: 'push 运行页');
      expect(factory.created, hasLength(1));
      final controller = factory.created.single;
      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();
      expect(controller.scripts, hasLength(1), reason: '运行页加载完成静默注入');
      expect(find.text(_bannerText), findsNothing, reason: 'launcher 透传官方端点检测');
    });

    testWidgets('launcher 未注入依赖时缺省生产装配（读 app provider 图）——路由正常 push 运行页', (tester) async {
      // 生产装配 = route builder 内 context.read<SecretStore>() /
      // SettingsRepository()：无 provider 时 push 仍成功（凭证读取在加载期，
      // 由运行页错误兜底吸收，不炸路由）。
      final factory = _FakeWebViewFactory();
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    buildRunPageLauncher(context,
                        webViewFactory: factory.create)(_localGame());
                  },
                  child: const Text('打开本地游戏'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开本地游戏'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SimulatorRunView), findsOneWidget);

      // 纯本地游戏不触发凭证读取（无同步控件），加载期无 provider 也不炸。
      final controller = factory.created.single;
      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.scripts, isEmpty);
    });

    testWidgets('缺省装配：凭证 / 官方端点检测从 provider 图读取（SecretStore 双槽位 + settings 组装）',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = InMemorySecretStore();
      await secretStore.write(
        key: SecretStore.openaiApiKeySlot,
        value: 'sk-test-assembled-1',
      );
      final repo = SettingsRepository(database: db, secretStore: secretStore);
      await repo.setMany(<String, String>{
        'default_provider': 'deepseek',
        'default_model': 'deepseek-v4-flash',
        'openai_base_url': 'https://api.deepseek.com/v1',
      });

      final factory = _FakeWebViewFactory();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SecretStore>.value(value: secretStore),
            Provider<SettingsRepository>.value(value: repo),
          ],
          child: MaterialApp(
            theme: ConverTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      buildRunPageLauncher(
                        context,
                        webViewFactory: factory.create,
                      )(_aiGame());
                    },
                    child: const Text('打开AI游戏'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开AI游戏'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SimulatorRunView), findsOneWidget);
      final controller = factory.created.single;
      controller.onPageFinished?.call();
      await tester.pump();
      await tester.pump();

      // 生产装配凭证（SecretStore openai 槽 + SettingsRepository 链）进脚本。
      expect(controller.scripts, hasLength(1));
      final script = controller.scripts.single;
      expect(script, contains('sk-test-assembled-1'));
      expect(script, contains('"endpoint":"https://api.deepseek.com/v1"'));
      expect(script, contains('"model":"deepseek-v4-flash"'));
      // claude 槽为空的场景：no claude key 泄漏。
      expect(script, isNot(contains('sk-ant')));

      // 官方端点检测缺省走 provider 图（deepseek + deepseek 域 → 非官方）。
      await tester.pump();
      expect(find.text(_bannerText), findsNothing);
    });
  });
}