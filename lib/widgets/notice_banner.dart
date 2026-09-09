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
///   `AnimatedOpacity` 播放 140ms 出口淡出，**过渡完成后**才回调 [onDismiss]
///   （真实通知语义不变，父级 [NoticeBanner.onDismiss] 在动画收尾后触发，
///   提示条不硬切卸载）。仅用 Fade（不叠 AnimatedSize）：尺寸动画会改变命中
///   测试区域导致过渡窗口内按钮不可点，克制动效契约下淡出即足。
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
///
/// F-65④：出口过渡的陈旧回调以 **notice 身份 seq**（[noticeId]，由父级
/// NoticeRunner 单调递增分配）判定「是否仍是被关闭的那条」——同文案新旧
/// notice 可区分，陈旧 dismiss 不误清新 notice；未提供 [noticeId] 时回退
/// 文案相等守卫（既有语义）。
class NoticeBanner extends StatefulWidget {
  /// 构造提示条。[notice] 为提示文案（ink2，bodyMedium；null → 空占位），
  /// [noticeId] 为当前 notice 的**身份 seq**（随 [notice] 同步传递；同文案
  /// 新 notice 须配新 id，防陈旧 dismiss 误清——F-65④）；[onDismiss] 为关闭
  /// 回调（**出口过渡完成后触发**）；[actionLabel] / [onAction] 供 T3「重试」
  /// 动作接线（仅定义契约，不接业务——两者须同时提供才渲染动作区）。
  const NoticeBanner({
    super.key,
    this.notice,
    this.noticeId,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  /// 提示文案（断流「回复已中断」/ 错误映射 / 导出占位等，逐字锚桌面）；
  /// null 时组件渲染空占位（出口过渡后隐藏）。
  final String? notice;

  /// 当前 notice 的**身份 seq**（父级 NoticeRunner 单调递增；null = 无 /
  /// 未接入 seq）。出口过渡陈旧回调以此判定「仍是被关闭的那条」；同文案新旧
  /// notice 因 seq 不同而可区分（F-65④）。null 时回退文案相等守卫。
  final int? noticeId;

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
  /// 出口过渡进行中（点关闭后置 true，触发 140ms 淡出）。
  bool _exiting = false;

  /// 出口过渡定时器（动画完成后回调 [NoticeBanner.onDismiss] 并复位）。
  Timer? _exitTimer;

  /// 出口过渡窗口内被关闭的提示文案（防「过渡窗口内 notice 被替换 → 陈旧
  /// 回调误清新 notice」：仅当当前 notice 仍是它时才派发 [onDismiss]）。
  /// 未接入 [NoticeBanner.noticeId]（null）时回退文案相等判定（既有语义）。
  String? _dismissingNotice;

  /// 出口过渡窗口内被关闭的提示**身份 seq**（F-65④）：通知单点关闭时的
  /// [NoticeBanner.noticeId]，过渡完成后与当前 [NoticeBanner.noticeId]
  /// 比较——同文案新旧 notice 因 seq 不同而可区分，陈旧 dismiss 不误清新
  /// notice。
  int? _dismissingNoticeId;

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  /// 关闭：播放 140ms 出口淡出（AnimatedOpacity），过渡结束
  /// 后回调真实 [NoticeBanner.onDismiss]。若 notice 已被外部清空（幂等），
  /// 直接回调不重复播放。
  void _handleDismiss() {
    if (widget.notice == null || _exiting) {
      return; // 已在过渡/已完成 —— 幂等。
    }
    setState(() {
      _exiting = true;
      _dismissingNotice = widget.notice;
      _dismissingNoticeId = widget.noticeId;
    });
    _exitTimer?.cancel();
    _exitTimer = Timer(ConverDurations.fast, () {
      if (!mounted) {
        return;
      }
      setState(() => _exiting = false);
      // F-65④：双方均接入身份 seq → 按 seq 判定（同文案新旧可区分）；任一
      // 为 null（未接入）→ 回退文案相等判定（既有语义）。
      final stillSame =
          widget.noticeId != null && _dismissingNoticeId != null
              ? widget.noticeId == _dismissingNoticeId
              : widget.notice == _dismissingNotice;
      _dismissingNotice = null;
      _dismissingNoticeId = null;
      // 仅当被关闭的提示仍是当前 notice 才派发：过渡窗口内 notice 被替换
      // （含同文案新 seq）或已清空时，陈旧回调不得误清新鲜 notice。
      if (stillSame) {
        widget.onDismiss();
      }
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
    return AnimatedOpacity(
      // W5 B1：出口过渡（淡出）140ms，内建于组件自身。仅 Fade 不叠
      // AnimatedSize——尺寸动画会缩小命中区域导致过渡窗口内按钮不可点。
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
    );
  }
}
