/// 非阻塞提示条共享组件（M6-02）——T3 流式级提示的唯一挂载点
/// （notice 文案 + 关闭按钮 + 预留动作槽）。
///
/// 语义锚点（spec §4.3 + 共识 §3.3）：
/// - 收编聊天页与角色页两处逐字同构的私有 `_NoticeBanner`（断流「回复已中断」
///   / 错误映射 / 基础设施失败 / 导出占位 / 加载失败 / 删除反馈）；
/// - 纯搬迁零行为：文案逐字不动（锚桌面 + 测试锚），关闭按钮与 tooltip
///   「关闭提示」不动，surfaceContainerHigh 底 + ink2 文案（色彩经既有
///   colorScheme / ConverPalette 消费）；
/// - 动作槽（重试按钮）本票只预留契约参数，不接业务（归 Issue 08 接线）。
library;

import 'package:flutter/material.dart';

import '../theme/colors.dart' show ConverSpacing;
import '../theme/conver_palette.dart' show ConverPalette;

/// 非阻塞提示条：notice 文案 + 关闭按钮 + 可选动作（重试）槽。
class NoticeBanner extends StatelessWidget {
  /// 构造提示条。[notice] 为提示文案（ink2，bodyMedium），[onDismiss] 为关闭
  /// 回调；[actionLabel] / [onAction] 供 T3「重试」动作接线（本票仅定义契约，
  /// 不接业务——两者须同时提供才渲染动作区）。
  const NoticeBanner({
    super.key,
    required this.notice,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  /// 提示文案（断流「回复已中断」/ 错误映射 / 导出占位等，逐字锚桌面）。
  final String notice;

  /// 关闭回调（如 [ChatController.dismissNotice] / [CharactersController.dismissNotice]）。
  final VoidCallback onDismiss;

  /// 可选动作文案（T3「重试」；本票仅契约，不接业务）。
  final String? actionLabel;

  /// 可选动作回调（与 [actionLabel] 须成对提供；缺一不渲染动作区）。
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final showAction = actionLabel != null && onAction != null;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
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
                notice,
                style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
              ),
            ),
            if (showAction)
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            IconButton(
              tooltip: '关闭提示',
              icon: Icon(Icons.close, size: 18, color: palette.ink4),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}