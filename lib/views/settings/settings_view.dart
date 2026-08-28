import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../theme/colors.dart';
import '../../view_models/theme_controller.dart';
import 'api_config_section.dart';
import 'default_model_section.dart';
import 'theme_section.dart';
import '../../widgets/placeholder_group.dart';

/// 设置视图 — 三组真实化（API 配置 / 默认模型 / 主题）+ 其余五组占位。
///
/// 依赖装配：本票（06）先于工单 07 的应用级装配，故仓储/控制器在内部
/// 缺省构造（AppDatabase 惰性打开）；07 装配后改为注入（构造参数已预留）。
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    this.settingsRepository,
    this.themeController,
  });

  /// 缺省时内部构造（工单 07 装配后注入统一实例）。
  final SettingsRepository? settingsRepository;
  final ThemeController? themeController;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const _placeholderItems = <PlaceholderItem>[
    PlaceholderItem('对话', '生成参数与行为'),
    PlaceholderItem('模板变量', '自定义注入变量'),
    PlaceholderItem('用户手册', '使用说明'),
    PlaceholderItem('关于', '版本信息'),
    PlaceholderItem('桌面版说明', '桌面端获取指引'),
  ];

  late final SettingsRepository _settings = widget.settingsRepository ??
      SettingsRepository(database: AppDatabase.open());
  late final ThemeController _themeController = widget.themeController ??
      ThemeController(settingsRepository: _settings);

  Future<(Map<String, String>, String, String)>? _echoFuture;

  @override
  void initState() {
    super.initState();
    // 存储通道不可用（平台通道缺失挂起/读取失败）→ 超时兜底保持缺省 dark
    _themeController.load().timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    _echoFuture = _loadEcho().timeout(
      const Duration(seconds: 3),
      onTimeout: () => (const <String, String>{}, '', ''),
    );
  }

  /// 回显装配：双槽位 Key 直读 + base_url / 默认 provider+model（设置表）。
  ///
  /// 防御（双层）：异常 → 空回显；通道挂起 → initState 的 3s 超时兜底
  ///（页面以未配置态渲染，不卡加载圈；生产端安全存储读取远快于 3s）。
  Future<(Map<String, String>, String, String)> _loadEcho() async {
    try {
      final values = <String, String>{
        for (final key in const [
          'claude_api_key',
          'openai_api_key',
          'claude_base_url',
          'openai_base_url',
        ])
          key: await _settings.getValue(key),
      };
      return (
        values,
        await _settings.defaultProvider,
        await _settings.defaultModel,
      );
    } catch (_) {
      return (const <String, String>{}, '', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: FutureBuilder<(Map<String, String>, String, String)>(
        future: _echoFuture,
        builder: (context, snapshot) {
          final loaded = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space5,
              ConverSpacing.space4,
              ConverSpacing.space6,
            ),
            children: [
              Text('设置',
                  style: textTheme.titleLarge
                      ?.copyWith(color: ConverColors.ink1)),
              const SizedBox(height: ConverSpacing.space1),
              Text('应用配置集中管理',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: ConverColors.ink3)),
              const SizedBox(height: ConverSpacing.space4),
              if (loaded == null)
                const Padding(
                  padding:
                      EdgeInsets.symmetric(vertical: ConverSpacing.space6),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ApiConfigSection(
                  settingsRepository: _settings,
                  initialValues: loaded.$1,
                ),
                const Divider(thickness: 1, color: ConverColors.border),
                DefaultModelSection(
                  settingsRepository: _settings,
                  initialProvider: loaded.$2,
                  initialModel: loaded.$3,
                ),
                const Divider(thickness: 1, color: ConverColors.border),
                ThemeSection(themeController: _themeController),
                const Divider(thickness: 1, color: ConverColors.border),
              ],
              for (var i = 0; i < _placeholderItems.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: ConverSpacing.space2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_placeholderItems[i].label,
                            style: textTheme.bodyLarge
                                ?.copyWith(color: ConverColors.ink2)),
                      ),
                      const SizedBox(width: ConverSpacing.space2),
                      Text(_placeholderItems[i].note,
                          style: textTheme.bodySmall
                              ?.copyWith(color: ConverColors.ink4)),
                    ],
                  ),
                ),
                if (i != _placeholderItems.length - 1)
                  const Divider(thickness: 1, color: ConverColors.border),
              ],
            ],
          );
        },
      ),
    );
  }
}
