/// 模拟器 tab 交互钩子注入单点（F-M5-03）——open / save / import / generate
/// 四回调登记 + 缺省未接线（null = UI 禁用态，不崩）。
///
/// 解耦契约（工单高不确定实现点「四钩子解耦设计跨票一致性」）：
/// - 回调签名固定：open = `void Function(SimulatorGame)`（F-M5-04 运行页
///   接线：push 运行页）；save / import / generate = `VoidCallback`（F-M5-06
///   存档半屏 sheet / F-M5-07 导入流 / F-M5-08b 生成对话框各自接线）；
/// - 本票缺省 = 全 null（未接线 = 禁用/空操作不崩，桌面 G7 注入钩子模式
///   移植）；后续票以其 file-scope 实现经 [SimulatorsController.registerHooks]
///   注入，不触碰 app.dart / home_shell.dart（装配纪律）。
///
/// 本文件仅定义契约类型；[SimulatorGame] 显示模型与 [SimulatorsController]
/// 状态机在 `lib/view_models/simulators_controller.dart`（本文件 import 之；
/// controller 亦 import 本文件持 hooks 槽位——双向引用为「契约类型与持有方
/// 按票面文件落点约束」下的最小交叉，Dart 库级环引用合法，analyzer 无告警）。
///
/// F-M5-04 顺序追加：run 页 open 钩子的**接线实现**——[buildRunPageLauncher]
/// 供 [SimulatorsView] 首挂载时经 [SimulatorsController.registerHooks] 注入
/// onOpen（卡片 onTap → push 全屏运行页）；运行页依赖在 route builder 内从
/// app provider 图读取或经参数注入（测试 seam），不触碰 app.dart /
/// home_shell.dart（装配纪律）。
library;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/material.dart'
    show BuildContext, MaterialPageRoute, Navigator;
import 'package:provider/provider.dart' show ReadContext;

import '../../data/repositories/settings_repository.dart'
    show SettingsRepository;
import '../../services/secure_store.dart' show SecretStore;
import '../../services/simulator/injection.dart'
    show
        CredentialSettings,
        InjectedCredentials,
        assembleCredentials,
        isOfficialEndpoint;
import '../../services/simulator/simulator_contracts.dart'
    show SimulatorContracts;
import '../../view_models/simulators_controller.dart'
    show SimulatorGame;
import 'simulator_run_view.dart'
    show
        SimulatorRunView,
        SimulatorWebViewControllerFactory,
        createFlutterWebViewController;

/// 四钩子槽位：本票只做渲染 + 钩子派发；具体流程由后续票接线实现。
class SimulatorsHooks {
  /// 构造可传部分回调；缺省（不传）即未接线（null）。
  const SimulatorsHooks({
    this.onOpen,
    this.onSaveTap,
    this.onImportTap,
    this.onGenerateTap,
  });

  /// 打开游戏回调（F-M5-04 接线：push 全屏运行页）；null = 未接线（卡片
  /// 点击不导航、不崩）。
  final void Function(SimulatorGame game)? onOpen;

  /// 存档管理入口（F-M5-06 接线：底部半屏 sheet 一次管全部游戏）。
  final VoidCallback? onSaveTap;

  /// 导入入口（F-M5-07 接线：picker → 校验 → 落盘 + manifest 原子写）。
  final VoidCallback? onImportTap;

  /// AI 生成入口（F-M5-08b 接线：种子模板 + prompt → 生成对话框）。
  final VoidCallback? onGenerateTap;
}

/// F-M5-04 顺序追加：open 钩子接线实现——把 [SimulatorGame] 接为「push 全屏
/// 运行页」。
///
/// [callerContext] 为模拟器列表页所在 [BuildContext]（提供 Navigator 与 app
/// provider 图访问）；运行页依赖在 route builder 内取用：凭证组装 /
/// 官方端点检测读 provider 图（或经 [loadCredentials] /
/// [checkOfficialEndpoint] 注入），WebView 平台 seam 经 [webViewFactory]
/// 注入（测试 fake 即不触平台通道）。
void Function(SimulatorGame game) buildRunPageLauncher(
  BuildContext callerContext, {
  SimulatorWebViewControllerFactory? webViewFactory,
  Future<InjectedCredentials> Function()? loadCredentials,
  Future<bool> Function()? checkOfficialEndpoint,
  int? port,
  Duration? loadTimeout,
}) {
  return (game) {
    Navigator.of(callerContext).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => SimulatorRunView(
          game: game,
          webViewFactory: webViewFactory ?? createFlutterWebViewController,
          loadCredentials:
              loadCredentials ?? () => _credentialsFromProviders(routeContext),
          checkOfficialEndpoint: checkOfficialEndpoint ??
              () => _isOfficialFromProviders(routeContext),
          port: port ?? SimulatorContracts.defaultPort,
          loadTimeout: loadTimeout ??
              const Duration(milliseconds: SimulatorContracts.timeoutMs),
        ),
      ),
    );
  };
}

/// 生产凭证组装（对齐桌面 setting.py credentials() 语义）：SecretStore 双槽位
/// + SettingsRepository（default_provider / default_model / configured_model /
/// openai 协议链 base_url）→ [assembleCredentials]。provider 读取在 await 前
/// 同步完成（routeContext 生命周期安全），之后的仓储读取为服务调用。
Future<InjectedCredentials> _credentialsFromProviders(
  BuildContext context,
) async {
  final secretStore = context.read<SecretStore>();
  final repo = context.read<SettingsRepository>();
  final provider = await repo.defaultProvider;
  final settings = CredentialSettings(
    defaultProvider: provider,
    defaultModel: await repo.defaultModel,
    configuredModel: await repo.getValue('default_model'),
    baseUrl: await repo.baseUrl('openai'),
  );
  return assembleCredentials(secretStore, settings);
}

/// 生产官方端点检测（共识 Q8）：默认 provider + openai 协议链 base_url →
/// [isOfficialEndpoint]（provider=claude 短路 / 官方域命中 → 提示条）。
Future<bool> _isOfficialFromProviders(BuildContext context) async {
  final repo = context.read<SettingsRepository>();
  final provider = await repo.defaultProvider;
  final baseUrl = await repo.baseUrl('openai');
  return isOfficialEndpoint(provider, baseUrl);
}

/// 合成带导入钩子的 hooks（F-M5-07，post-03 顺序追加）：在 [base] 槽位上叠加
/// [onImportTap]，其余槽位原样保留。
///
/// 装配契约：接线方读取控制器当前槽位合成后经
/// [SimulatorsController.registerHooks] 生效——既有注入钩子（constructor 注入
/// / 后续票先行接线）原文保留，绝不覆盖非空槽位（W3 视图测试以注入 hooks
/// 断言派发，本语义保证其不破）。
SimulatorsHooks appendImportHook(
  SimulatorsHooks base,
  VoidCallback onImportTap,
) {
  return SimulatorsHooks(
    onOpen: base.onOpen,
    onSaveTap: base.onSaveTap,
    onImportTap: onImportTap,
    onGenerateTap: base.onGenerateTap,
  );
}

/// 合成带存档钩子的 hooks（F-M5-06，post-03 顺序追加）：在 [base] 槽位上叠加
/// [onSaveTap]（AppBar「存档」→ 底部半屏 sheet），其余槽位原样保留。
///
/// 装配契约与 [appendImportHook] 同构：接线方读取控制器当前槽位合成后经
/// [SimulatorsController.registerHooks] 生效——既有注入钩子原文保留，绝不
/// 覆盖非空槽位。
SimulatorsHooks appendSaveHook(
  SimulatorsHooks base,
  VoidCallback onSaveTap,
) {
  return SimulatorsHooks(
    onOpen: base.onOpen,
    onSaveTap: onSaveTap,
    onImportTap: base.onImportTap,
    onGenerateTap: base.onGenerateTap,
  );
}
