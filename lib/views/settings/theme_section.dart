/// 主题组 — auto / light / dark 三值切换（用户拍板①）。
///
/// 语义契约（工单 06 A4）：切换经 [ThemeController.setThemeMode] 持久化
/// `theme_mode` 并 notifyListeners；MaterialApp 级随动归工单 07 装配 +
/// G6 冒烟（本票验收到控制器行为为止）。
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../view_models/theme_controller.dart';

/// 主题组：三值分段选择器，选中态由 [ThemeController] 驱动。
///
/// F-13 重入守卫：切换持久化进行中（[ThemeController.setThemeMode] 未完成）
/// 时，[SegmentedButton] 禁用并吞掉后续点击——避免基于陈旧 `themeMode`
/// （in-flight 期间仍是旧值）触发第二次写入；守卫在进入 setThemeMode 前置位、
/// 完成后复位（[State] 生命周期与按钮重建对齐，非永久锁死）。
class ThemeSection extends StatefulWidget {
  const ThemeSection({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  State<ThemeSection> createState() => _ThemeSectionState();
}

class _ThemeSectionState extends State<ThemeSection> {
  /// 主题切换进行中标志（F-13 重入守卫；复位正确 → 完成后可再切换）。
  bool _switching = false;

  Future<void> _onSelectionChanged(Set<ThemeMode> selection) async {
    if (_switching) {
      return; // 重入守卫：in-flight 期间吞掉后续点击
    }
    final mode = selection.first;
    if (mode != widget.themeController.themeMode) {
      setState(() => _switching = true);
      try {
        await widget.themeController.setThemeMode(mode);
      } catch (error) {
        debugPrint('主题切换失败: $error');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('主题切换失败')));
        }
      } finally {
        if (mounted) {
          setState(() => _switching = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '主题',
          style: textTheme.titleMedium?.copyWith(
            color: ConverPalette.of(context).ink1,
          ),
        ),
        const SizedBox(height: ConverSpacing.space1),
        Text(
          '跟随系统 / 浅色 / 深色（首启为深色）',
          style: textTheme.bodySmall?.copyWith(
            color: ConverPalette.of(context).ink4,
          ),
        ),
        const SizedBox(height: ConverSpacing.space2),
        ListenableBuilder(
          listenable: widget.themeController,
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
              selected: {widget.themeController.themeMode},
              // F-13：in-flight 期间禁用按钮（onSelectionChanged 置 null），
              // 与 _onSelectionChanged 内首行守卫双保险，行为确定。
              onSelectionChanged:
                  _switching ? null : (selection) => _onSelectionChanged(selection),
            );
          },
        ),
      ],
    );
  }
}
