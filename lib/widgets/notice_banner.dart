/// 非阻塞提示条共享组件（M6-02/07）——T3 流式级提示的唯一挂载点
/// （notice 文案 + 关闭按钮 + 预留动作槽）。
///
/// 语义锚点（spec §4.3 + 共识 §3.3）：
/// - 收编聊天页与角色页两处逐字同构的私有 `_NoticeBanner`（断流「回复已中断」
///   / 错误映射 / 基础设施失败 / 导出占位 / 加载失败 / 删除反馈）；
/// - 纯搬迁零行为：文案逐字不动（锚桌面 + 测试锚），关闭按钮与 tooltip
///   「关闭提示」不动，surfaceContainerHigh 底 + ink2 文案（色彩经既有
///   colorScheme / ConverPalette 消费）；
/// - 动作槽（重试按钮）本票只预留契约参数，不接业务（归 Issue 08 接线）；
/// - 动效（M6-07 克制动效 ② + W5 审核 B1 修复）：出现/消失过渡 140ms 内建于
///   组件自身——[notice] 可空，null 时组件渲染空占位；点关闭先经
///   `AnimatedOpacity` + `AnimatedSize` 播放 140ms 出口过渡，**过渡完成后**
///   才回调 [onDismiss]（真实通知语义不变，父级 [NoticeBanner.onDismiss]
///   在动画收尾后触发，提示条不硬切卸载）。
///
/// 消费契约：父级**始终渲染**本组件（notice 可空；移除 `if (notice != null)`
/// 条件），进出动画由组件自持。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/colors.dart' show ConverSpacing;
import '../theme/conver_palette.dart' show ConverPalette;
import '../theme/motion.dart' show ConverDurations;

/// 非阻塞提示条：notice 文案 + 关闭按钮 + 可选动作（重试）槽。
///
/// [notice] 可空：为 null 时渲染空占位（宽度撑满，布局不跳动）；非 null 时
/// 渲染提示条。关闭动作先播放 140ms 出口过渡，动画结束后回调 [onDismiss]。
class NoticeBanner extends StatefulWidget {
  /// 构造提示条。[notice] 为提示文案（ink2，bodyMedium；null → 空占位），
  /// [onDismiss] 为关闭回调（**出口过渡完成后触发**）；[actionLabel] /
  /// [onAction] 供 T3「重试」动作接线（仅定义契约，不接业务——两者须同时
  /// 提供才渲染动作区）。
  const NoticeBanner({
    super.key,
    this.notice,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  /// 提示文案（断流「回复已中断」/ 错误映射 / 导出占位等，逐字锚桌面）；
  /// null 时组件渲染空占位（出口过渡后隐藏）。
  final String? notice;

  /// 关闭回调（如 [ChatController.dismissNotice] / [CharactersController.dismissNotice]）；
  /// 出口过渡完成后触发。
  final VoidCallback onDismiss;

  /// 可选动作文案（T3「重试」；本票仅契约，不接业务）。
  final String? actionLabel;

  /// 可选动作回调（与 [actionLabel] 须成对提供；缺一不渲染动作区）。
  final VoidCallback? onAction;

  @override
  State<NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<NoticeBanner> {
  /// 出口过渡进行中（点关闭后置 true，触发 140ms 淡出 + 收缩）。
  bool _exiting = false;

  /// 出口过渡定时器（动画完成后回调 [NoticeBanner.onDismiss] 并复位）。
  Timer? _exitTimer;

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  /// 关闭：播放 140ms 出口过渡（AnimatedOpacity/AnimatedSize），过渡结束
  /// 后回调真实 [NoticeBanner.onDismiss]。若 notice 已被外部清空（幂等），
  /// 直接回调不重复播放。
  void _handleDismiss() {
    if (widget.notice == null || _exiting) {
      return; // 已在过渡/已完成 —— 幂等。
    }
    setState(() => _exiting = true);
    _exitTimer?.cancel();
    _exitTimer = Timer(ConverDurations.fast, () {
      if (!mounted) {
        return;
      }
      setState(() => _exiting = false);
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final noticeText = widget.notice;
    final showAction =
        noticeText != null && widget.actionLabel != null && widget.onAction != null;
    final visible = noticeText != null && !_exiting;
    return AnimatedSize(
      // W5 B1：出口过渡（淡出 + 收缩）140ms，内建于组件自身。
      duration: ConverDurations.fast,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: ConverDurations.fast,
        opacity: visible ? 1.0 : 0.0,
        // 提示条始终在树中（null/退出态为透明空占位），保证过渡本体可见。
        child: noticeText == null
            ? const SizedBox(width: double.infinity)
            : IgnorePointer(
                ignoring: !visible,
                child: Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  padding: const EdgeInsets.fromLTRB(
                    ConverSpacing.space4,
                    ConverSpacing.space1,
                    ConverSpacing.space1,
                    ConverSpacing.space1,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          noticeText,
                          style:
                              textTheme.bodyMedium?.copyWith(color: palette.ink2),
                        ),
                      ),
                      if (showAction)
                        TextButton(
                          onPressed: widget.onAction,
                          child: Text(widget.actionLabel!),
                        ),
                      IconButton(
                        tooltip: '关闭提示',
                        icon: Icon(Icons.close, size: 18, color: palette.ink4),
                        onPressed: _handleDismiss,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}