/// 主题组 — auto / light / dark 三值切换（用户拍板①）。
///
/// 语义契约（工单 06 A4）：切换经 [ThemeController.setThemeMode] 持久化
/// `theme_mode` 并 notifyListeners；MaterialApp 级随动归工单 07 装配 +
/// G6 冒烟（本票验收到控制器行为为止）。
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../view_models/theme_controller.dart';

/// 主题组：三值分段选择器，选中态由 [ThemeController] 驱动。
class ThemeSection extends StatelessWidget {
  const ThemeSection({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('主题',
            style:
                textTheme.titleMedium?.copyWith(color: ConverColors.ink1)),
        const SizedBox(height: ConverSpacing.space1),
        Text('跟随系统 / 浅色 / 深色（首启为深色）',
            style:
                textTheme.bodySmall?.copyWith(color: ConverColors.ink4)),
        const SizedBox(height: ConverSpacing.space2),
        ListenableBuilder(
          listenable: themeController,
          builder: (context, _) {
            return SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined, size: 16),
                  label: Text('跟随系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined, size: 16),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 16),
                  label: Text('深色'),
                ),
              ],
              selected: {themeController.themeMode},
              onSelectionChanged: (selection) {
                final mode = selection.first;
                if (mode != themeController.themeMode) {
                  themeController.setThemeMode(mode);
                }
              },
            );
          },
        ),
      ],
    );
  }
}
