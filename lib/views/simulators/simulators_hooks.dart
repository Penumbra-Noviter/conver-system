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
library;

import 'package:flutter/foundation.dart' show VoidCallback;

import '../../view_models/simulators_controller.dart'
    show SimulatorGame;

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
