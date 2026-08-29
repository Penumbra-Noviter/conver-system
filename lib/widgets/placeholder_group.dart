import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/conver_palette.dart';

/// 占位视图共用骨架：页标题 + 一句话说明 + 分隔线信息组。
///
/// 仅服务 M0 的五个空壳占位页（后续里程碑由真实页面替换）。视觉遵循
/// 设计文档 §5.2：无渐变、无发光、无大圆角果冻卡，以 1px 边框分割与
/// 四级 ink 文字层级呈现"专业工具感"。
class PlaceholderGroup extends StatelessWidget {
  const PlaceholderGroup({
    super.key,
    required this.title,
    required this.description,
    required this.items,
  });

  /// 页面标题（与所属 tab 的中文文案一致，测试锚点）。
  final String title;

  /// 一句话说明当前占位页的用途。
  final String description;

  /// 计划落地的内容分组，逐行展示。
  final List<PlaceholderItem> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          ConverSpacing.space4,
          ConverSpacing.space5,
          ConverSpacing.space4,
          ConverSpacing.space6,
        ),
        children: [
          Text(
            title,
            style: textTheme.titleLarge?.copyWith(
              color: Theme.of(context).extension<ConverPalette>()!.ink1,
            ),
          ),
          const SizedBox(height: ConverSpacing.space1),
          Text(
            description,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).extension<ConverPalette>()!.ink3,
            ),
          ),
          const SizedBox(height: ConverSpacing.space6),
          for (var i = 0; i < items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ConverSpacing.space2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      items[i].label,
                      style: textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context)
                            .extension<ConverPalette>()!
                            .ink2,
                      ),
                    ),
                  ),
                  const SizedBox(width: ConverSpacing.space2),
                  Text(
                    items[i].note,
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).extension<ConverPalette>()!.ink4,
                    ),
                  ),
                ],
              ),
            ),
            if (i != items.length - 1)
              Divider(
                thickness: 1,
                color: Theme.of(context).extension<ConverPalette>()!.border,
              ),
          ],
        ],
      ),
    );
  }
}

/// 信息组的单行条目：左侧条目名，右侧状态备注。
class PlaceholderItem {
  const PlaceholderItem(this.label, this.note);

  /// 条目名（计划落地的分组或能力）。
  final String label;

  /// 状态备注（当前为占位说明）。
  final String note;
}
