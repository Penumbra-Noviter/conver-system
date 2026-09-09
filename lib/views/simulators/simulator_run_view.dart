/// 模拟器运行页（F-M5-04）——全屏 WebView 运行任意游戏卡片 + 官方端点提示条
/// + 「重新同步」手动兜底 + 15s 加载超时错误态。
///
/// 语义锚点（桌面，逐字）：
/// - `desktop/frontend/js/simulator-view.js`：状态机（opening → loaded | error，
///   15s 超时守卫；参数非法直接 error 不建 iframe）+ 错误文案（参数非法 /
///   加载超时秒数派生）+ 重试复用当前游戏；load 竞态守卫（陈旧 iframe 迟到
///   load 忽略）；
/// - `desktop/frontend/js/key-injector.js`：按钮反馈状态机（成功「已填入」
///   2s / claude·none 禁用文案 / 失败静默复位）+ 自动同步静默不闪反馈 +
///   TEXT_RESYNC / TEXT_INJECTED / MSG_CLAUDE_ONLY / MSG_NO_CREDENTIALS 逐字；
/// - 共识 Q8 / spec §4.2-6：官方端点提示条逐字文案 [officialEndpointBannerText]，
///   提示时注入照常静默（claude 不注入）。
///
/// 平台薄层隔离（U1）：本组件不直接调用 webview_flutter——WebView 能力经统一
/// seam [WebViewCapability] + 工厂注入点 [WebViewCapabilityFactory] 隔离
/// （平台薄层收口 `services/simulator/webview_capability.dart`）；生产装配默认
/// 工厂 [createWebViewCapability]，widget 测试注入共享假件
/// `test/support/fake_web_view_capability.dart`，真通道归 F-M5-09 AVD 冒烟。
///
/// 层级：呈现层。凭证组装 / 官方端点检测 / 注入脚本全部经构造注入的闭包与
/// 服务模块消费（layer_boundary_test 与 view_theme_tokens_test 静态不变量：
/// 视图源不得出现数据层 / 平台存储实现标识符，色彩一律经 ConverPalette /
/// Theme.colorScheme 消费，不直接引用色值常量表）。
///
/// 协议表面：`SimulatorRunView` / `officialEndpointBannerText` / `textResync` /
/// `textInjected` / `msgClaudeOnly` / `msgNoCredentials` / `errorInvalidFile`。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/simulator/injection.dart'
    show
        InjectedCredentials,
        hasConfigTriplet,
        resolveButtonState;
import '../../services/simulator/injection_script.dart' show InjectionScript;
import '../../services/simulator/simulator_contracts.dart'
    show SimulatorContracts;
import '../../services/simulator/webview_capability.dart'
    show WebViewCapability, WebViewCapabilityFactory, createWebViewCapability;
import '../../theme/conver_palette.dart' show ConverPalette;
import '../../view_models/simulators_controller.dart' show SimulatorGame;
import '../../widgets/status_view.dart';

/// 官方端点提示条逐字文案（共识 Q8：defaultProvider=claude 或 base_url 命中
/// 官方域 → 运行页顶部提示条）。
const String officialEndpointBannerText =
    '当前官方端点不支持游戏直连；请使用 DeepSeek/Kimi/GLM/Qwen '
    '等国产兼容端点，或改用桌面版运行';

/// 重新同步按钮文案（桌面 TEXT_RESYNC 逐字）。
const String textResync = '重新同步';

/// 注入成功后的短暂反馈文案（桌面 TEXT_INJECTED 逐字）。
const String textInjected = '已填入';

/// claude-only 禁用文案（桌面 MSG_CLAUDE_ONLY 逐字）。
const String msgClaudeOnly = '游戏仅支持 OpenAI 兼容 Key';

/// none 禁用文案（桌面 MSG_NO_CREDENTIALS 逐字）。
const String msgNoCredentials = '未配置 OpenAI 兼容 Key';

/// 参数非法错误原因（桌面 simulator-view renderError 逐字）。
const String errorInvalidFile = '参数非法：缺少有效的游戏文件';

/// 「已填入」反馈时长（毫秒；桌面 FEEDBACK_MS=2000 逐字）。
const int feedbackMs = 2000;

/// 运行页状态机相位：opening（加载中）→ loaded（可注入）| error（重试）。
enum _RunPhase { opening, loaded, error }

/// 全屏 WebView 运行页：加载 `http://127.0.0.1:<port>/simulators/<file>`，
/// `onPageFinished` 静默自动注入一次；「重新同步」手动兜底 + 反馈；官方端点
/// 提示条；15s 加载超时 → 错误态 + 重试（复用当前游戏）。
class SimulatorRunView extends StatefulWidget {
  /// 构造运行页。依赖全部经构造注入（测试 seam）：[webViewFactory]（WebView
  /// 能力工厂，缺省生产平台薄层）、[loadCredentials]（凭证组装闭包）、
  /// [checkOfficialEndpoint]（官方端点检测闭包）；[port] 为本地托管端口
  /// （生产固定 [SimulatorContracts.defaultPort]）；[loadTimeout] 加载超时
  /// 守卫（生产 15s）。
  const SimulatorRunView({
    super.key,
    required this.game,
    required this.loadCredentials,
    required this.checkOfficialEndpoint,
    this.webViewFactory = createWebViewCapability,
    this.port = SimulatorContracts.defaultPort,
    this.loadTimeout =
        const Duration(milliseconds: SimulatorContracts.timeoutMs),
  });

  /// 目标游戏条目（URL 基址 = `simulators/<file>`；file 经安全判据守卫）。
  final SimulatorGame game;

  /// 凭证组装闭包（SecretStore 双槽位 + settings → InjectedCredentials）。
  final Future<InjectedCredentials> Function() loadCredentials;

  /// 官方端点检测闭包（provider=claude 或 base_url 命中官方域 → 提示条）。
  final Future<bool> Function() checkOfficialEndpoint;

  /// WebView 能力工厂（统一 U1 seam；构造期注入页面就绪委托；测试注入共享
  /// 假件，生产默认平台薄层 [createWebViewCapability]）。
  final WebViewCapabilityFactory webViewFactory;

  /// 本地托管端口（URL 基址 127.0.0.1:port 来源；生产 8642）。
  final int port;

  /// 加载超时守卫时长（15s 默认；错误文案秒数由本值派生）。
  final Duration loadTimeout;

  @override
  State<SimulatorRunView> createState() => _SimulatorRunViewState();
}

class _SimulatorRunViewState extends State<SimulatorRunView> {
  _RunPhase _phase = _RunPhase.opening;

  /// 当前 WebView 能力（创建完成前为 null；重试替换为新实例）。
  WebViewCapability? _controller;

  /// 加载超时守卫计时器（opening 期间持有；loaded/error 清空）。
  Timer? _timeoutTimer;

  /// 「已填入」反馈计时器（无在途反馈为 null）。
  Timer? _feedbackTimer;

  /// 官方端点提示条可见性（initState 异步检测）。
  bool _bannerVisible = false;

  /// 在途凭证获取 + 注入守卫（反馈期间/在途时忽略重复点击）。
  bool _injecting = false;

  /// 重新同步按钮可用态（openai 态 true；claude/none 恒 false）。
  bool _syncEnabled = true;

  /// 重新同步按钮文案（`重新同步` / 反馈期 `已填入`）。
  String _syncLabel = textResync;

  /// claude/none 禁用原因文案（仅禁用态非空；openai 态 null）。
  String? _syncMessage;

  /// 错误态原因文案（仅 error 相位非空）。
  String? _errorReason;

  /// 是否渲染同步控件 + 执行注入（仅 ai 游戏且 config 三元组完整）。
  bool get _showSyncControls =>
      widget.game.isAi && hasConfigTriplet(widget.game.config);

  @override
  void initState() {
    super.initState();
    unawaited(_checkBanner());
    if (!SimulatorContracts.isValidSimulatorFile(widget.game.file)) {
      // 非法 file：错误态不建页（工厂不调用、不启超时）。
      _enterError(errorInvalidFile);
      return;
    }
    _startOpening();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  /// 异步检测官方端点（失败静默降级为不提示；mounted 守卫防挂起帧）。
  Future<void> _checkBanner() async {
    bool visible;
    try {
      visible = await widget.checkOfficialEndpoint();
    } catch (_) {
      visible = false;
    }
    if (!mounted) {
      return;
    }
    setState(() => _bannerVisible = visible);
  }

  /// 进入 opening：复位同步控件态 → 创建能力（构造期挂委托）→ 起 15s 超时守卫。
  ///
  /// 首次 initState 调用（build 前，无需 setState）；重试时先由调用方
  /// [setState] 复位相位再调用。load 竞态守卫：仅接受当前 `_controller` 身份
  /// 的 onPageFinished（桌面「e.target !== frame」忽略陈旧迟到 load 同构）。
  Future<void> _startOpening() async {
    final url = Uri.parse(
      'http://127.0.0.1:${widget.port}/${SimulatorContracts.simDir}/'
      '${widget.game.file}',
    );
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(widget.loadTimeout, _handleTimeout);
    try {
      // 构造期委托注入（F-43 对齐 save_sheet W5 B1 的结构化形态）：页面就绪
      // 委托由工厂构造期挂载、先于任何 navigate——onPageFinished 只派发给挂载
      // 时已存在的委托（不回放挂载前事件），先导航后挂委托即丢失事件（极小/
      // 秒开页面在委托挂载前完成加载 → 15s 超时错误态）。装配 = create(挂委托)
      // → navigate 一步。
      final controller = await widget.webViewFactory(_handlePageFinished);
      if (!mounted) {
        return;
      }
      setState(() => _controller = controller);
      await controller.navigate(url);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      setState(() => _enterError('加载模拟器页面失败: $error'));
    }
  }

  /// 页面加载完成：opening → loaded（清超时守卫）→ 静默自动注入一次。
  void _handlePageFinished(WebViewCapability source) {
    if (!mounted) {
      return;
    }
    if (_phase != _RunPhase.opening) {
      return; // 兜底：已 loaded/error 后迟到 load 忽略。
    }
    if (source != _controller) {
      return; // 陈旧控制器迟到 load（重试替换后旧回调）忽略。
    }
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    setState(() => _phase = _RunPhase.loaded);
    if (_showSyncControls) {
      unawaited(_applyCredentials(feedback: false));
    }
  }

  /// 超时守卫到期（loadTimeout 内未收到 onPageFinished）→ 错误态。
  void _handleTimeout() {
    if (!mounted) {
      return;
    }
    if (_phase != _RunPhase.opening) {
      return; // 兜底：已 loaded/closed 的残留计时器忽略。
    }
    _timeoutTimer = null;
    setState(() {
      _enterError('加载超时（${widget.loadTimeout.inSeconds} 秒未收到响应）');
    });
  }

  /// 进入错误态（相位 error + 原因文案；同步控件回退禁用）。
  void _enterError(String reason) {
    _phase = _RunPhase.error;
    _errorReason = reason;
    _syncEnabled = false;
    _syncLabel = textResync;
    _syncMessage = null;
  }

  /// 复位到 opening（重试路径；调用方已包 setState）。
  void _resetToOpening() {
    _phase = _RunPhase.opening;
    _errorReason = null;
    _controller = null;
    _syncEnabled = true;
    _syncLabel = textResync;
    _syncMessage = null;
    _feedbackTimer?.cancel();
  }

  /// 重试按钮：复用当前游戏重建控制器（等价桌面 openSimulator(currentGame)）。
  void _handleRetry() {
    setState(_resetToOpening);
    _startOpening();
  }

  /// 手动「重新同步」点击：反馈路径注入（在途/禁用态忽略）。
  void _handleResyncTap() {
    if (!_syncEnabled || _injecting) {
      return;
    }
    unawaited(_applyCredentials(feedback: true));
  }

  /// 凭证获取 → 三态分流 → 注入 + 按钮状态机（自动同步静默 / 手动反馈）。
  ///
  /// openai：注入 [InjectionScript]（endpoint 按 endpointMode 口径转换后入
  /// 脚本）；按钮复位可点；feedback 且真注入 → 「已填入」2s。claude/none：
  /// 不注入（claude key 绝不进游戏）+ 按钮禁用 + 原因文案。失败（凭证获取 /
  /// 注入异常）→ 静默降级按钮复位可点（桌面 runSync catch 语义）。
  Future<void> _applyCredentials({required bool feedback}) async {
    if (_injecting) {
      return;
    }
    _injecting = true;
    try {
      final creds = await widget.loadCredentials();
      if (!mounted) {
        return;
      }
      final state = resolveButtonState(creds);
      if (!state.enabled) {
        setState(() {
          _syncEnabled = false;
          _syncLabel = textResync;
          _syncMessage =
              state.reason == 'claude' ? msgClaudeOnly : msgNoCredentials;
        });
        return;
      }
      var injected = false;
      final controller = _controller;
      if (controller != null) {
        final script = InjectionScript.build(
          config: widget.game.config!,
          credentials: creds,
          endpointMode: widget.game.endpointMode,
        );
        await controller.runJavaScript(script);
        injected = true;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _syncEnabled = true;
        _syncLabel = textResync;
        _syncMessage = null;
      });
      if (feedback && injected) {
        setState(() {
          _syncLabel = textInjected;
          _syncEnabled = false;
        });
        _feedbackTimer?.cancel();
        _feedbackTimer =
            Timer(const Duration(milliseconds: feedbackMs), _resetSyncLabel);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncEnabled = true;
        _syncLabel = textResync;
      });
    } finally {
      _injecting = false;
    }
  }

  /// 「已填入」反馈到期：按钮复位可点。
  void _resetSyncLabel() {
    if (!mounted) {
      return;
    }
    setState(() {
      _syncLabel = textResync;
      _syncEnabled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.game.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_showSyncControls && _phase != _RunPhase.error)
            TextButton(
              onPressed: _syncEnabled ? _handleResyncTap : null,
              child: Text(_syncLabel),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_bannerVisible) const _OfficialEndpointBanner(),
            if (_showSyncControls &&
                _phase == _RunPhase.loaded &&
                _syncMessage != null)
              _SyncMessageStrip(message: _syncMessage!),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  /// 正文三态：error（错误文案 + 重试/返回）/ opening（WebView + 加载占位）/
  /// loaded（WebView）。
  Widget _buildBody() {
    if (_phase == _RunPhase.error) {
      return Center(
        child: StatusView(
          icon: Icons.error_outline,
          title: '游戏加载失败',
          message: _errorReason ?? '未知错误',
          actions: [
            FilledButton(onPressed: _handleRetry, child: const Text('重试')),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: _controller?.buildView() ?? const SizedBox.shrink(),
        ),
        if (_phase == _RunPhase.opening)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

/// 官方端点提示条（共识 Q8 逐字文案；暖色底 + 信息图标，色彩经 Theme
/// colorScheme / ConverPalette 消费——视图层静态不变量约束）。
class _OfficialEndpointBanner extends StatelessWidget {
  const _OfficialEndpointBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = ConverPalette.of(context);
    return Container(
      color: colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              officialEndpointBannerText,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 同步按钮禁用原因条（claude / none 文案）。
class _SyncMessageStrip extends StatelessWidget {
  const _SyncMessageStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: palette.ink3),
      ),
    );
  }
}
