/// 空态共享组件（M6-01）——空态三段式（线性图标 + 主文案 + 可选提示 + 可选动作）。
///
/// 语义锚点（spec §4.2 + 共识 §0.3/§2.2）：
/// - 线性 Material 轮廓图标 40px（ink4）+ 主文案（ink3，bodyMedium）+ 可选
///   提示（ink4，bodySmall）+ 可选动作；收编角色列表 / 对话入口 / 模拟器空态
///   与筛选空四处既有同构私有实现（纯搬迁零行为，文案逐字不动）；
/// - 操作入口不加（TP-4 定案：角色/对话入口头部创建入口已备，空态再加按钮属
///   重复入口），[action] 参数保留供未来；
/// - 装饰图标 ExcludeSemantics（spec §4.4 语义覆盖清单 ②：装饰图标不产生
///   语义噪音，归属本组件契约）。
library;

import 'package:flutter/material.dart';

import '../theme/colors.dart' show ConverSpacing;
import '../theme/conver_palette.dart' show ConverPalette;

/// 空态共享组件：图标 + 主文案 + 可选提示 + 可选动作。
///
/// 调用方负责居中与滚动容器（空态在列表页通常位于可下拉刷新的滚动面内）；
/// 组件本身只渲染三段式内容列。
class EmptyState extends StatelessWidget {
  /// 构造空态。[icon] 为装饰性线性图标（Material 轮廓），[message] 为主文案
  /// （ink3），[hint] / [action] 可空。
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
    this.action,
  });

  /// 装饰性线性图标（Material 轮廓；语义由 ExcludeSemantics 排除）。
  final IconData icon;

  /// 主文案（ink3，bodyMedium，居中）。
  final String message;

  /// 可选提示（ink4，bodySmall，居中）。
  final String? hint;

  /// 可选动作（TP-4 定案：空态不加操作入口，参数保留供未来需要）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 40, color: palette.ink4)),
        const SizedBox(height: ConverSpacing.space2),
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: palette.ink3),
        ),
        if (hint != null) ...[
          const SizedBox(height: ConverSpacing.space1),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: palette.ink4),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: ConverSpacing.space3),
          action!,
        ],
      ],
    );
  }
}
