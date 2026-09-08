/// 状态页共享组件（M6-01）——图标 + 可选标题 + 原因/文案 + 可选提示 + 动作区。
///
/// 语义锚点（spec §4.3 + 共识 §3.3）：
/// - 替代模拟器列表 `_StatusColumn`（无标题：图标 + 原因 + 可选动作）与运行页
///   `_ErrorView`（带标题：图标 + 标题 + 原因 + 重试/返回动作区）两处逐字同构
///   私有拷贝（T1 页面级错误页契约：图标 + 标题/原因 + 「重试」）；
/// - 布局逐字保两形：有标题态（错误页）图标后 12px、动作前 16px；无标题态
///   （状态列）8px / 12px（对齐两处原私有实现间距）；
/// - 装饰图标 ExcludeSemantics（spec §4.4 语义覆盖清单 ②：装饰图标不产生
///   语义噪音，归属本组件契约）。
library;

import 'package:flutter/material.dart';

import '../theme/colors.dart' show ConverSpacing;
import '../theme/conver_palette.dart' show ConverPalette;

/// 状态页共享组件：图标 + 可选标题 + 原因/文案 + 可选提示 + 动作区。
///
/// 调用方负责居中与滚动容器（错误态通常位于可下拉刷新的滚动面内）；组件本身
/// 只渲染状态内容列。[actions] 内的动作按钮以 space3 间距水平排布。
class StatusView extends StatelessWidget {
  /// 构造状态页。[icon] 为装饰性线性图标（Material 轮廓），[message] 为
  /// 原因/文案（ink2），[title] / [hint] 可空，[actions] 缺省不渲染。
  const StatusView({
    super.key,
    required this.icon,
    this.title,
    required this.message,
    this.hint,
    this.actions = const [],
  });

  /// 装饰性线性图标（Material 轮廓；语义由 ExcludeSemantics 排除）。
  final IconData icon;

  /// 可选标题（ink1，titleSmall，居中）。
  final String? title;

  /// 原因/文案（ink2，bodyMedium，居中）。
  final String message;

  /// 可选提示（ink4，bodySmall，居中）。
  final String? hint;

  /// 动作区（如「重试」「返回」按钮组；缺省空列表不渲染动作行）。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final hasTitle = title != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 40, color: palette.ink4)),
        // 图标后间距：错误页（带标题）原 12px / 状态列（无标题）原 8px。
        SizedBox(
          height: hasTitle ? ConverSpacing.space3 : ConverSpacing.space2,
        ),
        if (hasTitle) ...[
          Text(
            title!,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(color: palette.ink1),
          ),
          // 标题与原因间距（运行页 _ErrorView 原值）。
          const SizedBox(height: 6),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
        ),
        if (hint != null) ...[
          const SizedBox(height: ConverSpacing.space1),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: palette.ink4),
          ),
        ],
        if (actions.isNotEmpty) ...[
          // 动作前间距：错误页（带标题）原 16px / 状态列（无标题）原 12px。
          SizedBox(
            height: hasTitle ? ConverSpacing.space4 : ConverSpacing.space3,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: ConverSpacing.space3),
                actions[i],
              ],
            ],
          ),
        ],
      ],
    );
  }
}