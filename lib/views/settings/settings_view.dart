import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/secure_store.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../view_models/theme_controller.dart';
import '../../widgets/placeholder_group.dart';
import 'about_page.dart';
import 'api_config_section.dart';
import 'default_model_section.dart';
import 'desktop_note_page.dart';
import 'manual_page.dart';
import 'theme_section.dart';

/// 设置视图 — 三组真实化（API 配置 / 默认模型 / 主题）+ 两占位（对话 /
/// 模板变量）+「我」页收口三入口（用户手册 / 关于 / 桌面版说明，F-M5-10）。
///
/// 依赖装配（F-9）：仓储 / 主题控制器 / 安全存储全部由 home_shell 沿
/// provider 注入（单一装配点），本视图不再现造任何数据层/平台存储实例。
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.settingsRepository,
    required this.themeController,
    required this.secretStore,
  });

  /// 设置仓储（应用级统一实例，home_shell 注入）。
  final SettingsRepository settingsRepository;

  /// 主题控制器（应用级共享实例，主题切换端到端生效）。
  final ThemeController themeController;

  /// 安全存储（app.dart provider 注入；透传给 [ApiConfigSection]）。
  final SecretStore secretStore;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  /// 「对话」「模板变量」两占位不在 M5 范围（锚共识 D1），保持占位。
  static const _placeholderItems = <PlaceholderItem>[
    PlaceholderItem('对话', '生成参数与行为'),
    PlaceholderItem('模板变量', '自定义注入变量'),
  ];

  /// 「我」页收口三入口（F-M5-10）：三占位行拆出为真实导航入口。
  ///
  /// 页面均为无状态静态文本页，实例可共享复用（push 时同一 const 实例）。
  static const _profileEntries = <_ProfileEntry>[
    _ProfileEntry('用户手册', '使用说明', ManualPage()),
    _ProfileEntry('关于', '版本信息', AboutPage()),
    _ProfileEntry('桌面版说明', '桌面端获取指引', DesktopNotePage()),
  ];

  late final SettingsRepository _settings = widget.settingsRepository;
  late final ThemeController _themeController = widget.themeController;

  Future<(Map<String, String>, String, String)>? _echoFuture;

  @override
  void initState() {
    super.initState();
    // 存储通道不可用（平台通道缺失挂起/读取失败）→ 超时兜底保持缺省 dark；
    // catchError 兜底「读失败即抛」路径——避免未处理 zone 异常（F-12）。
    _themeController.load().timeout(
      const Duration(seconds: 3),
      onTimeout: () => debugPrint('主题偏好加载超时，保持缺省 dark'),
    ).catchError((Object error) {
      debugPrint('主题偏好加载失败，保持缺省 dark: $error');
    });
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
    } catch (error) {
      debugPrint('设置页回显加载失败，返回空回显: $error');
      return (const <String, String>{}, '', '');
    }
  }

  /// 打开「我」页收口子页（与 characters_view 全屏下钻同一 Navigator push
  /// 模式；三页自带 Scaffold + AppBar 返回）。
  void _openProfilePage(_ProfileEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => entry.page),
    );
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
              Text(
                '设置',
                style: textTheme.titleLarge?.copyWith(
                  color: ConverPalette.of(context).ink1,
                ),
              ),
              const SizedBox(height: ConverSpacing.space1),
              Text(
                '应用配置集中管理',
                style: textTheme.bodyMedium?.copyWith(
                  color: ConverPalette.of(context).ink3,
                ),
              ),
              const SizedBox(height: ConverSpacing.space4),
              if (loaded == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: ConverSpacing.space6),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ApiConfigSection(
                  settingsRepository: _settings,
                  secretStore: widget.secretStore,
                  initialValues: loaded.$1,
                ),
                Divider(
                  thickness: 1,
                  color: ConverPalette.of(context).border,
                ),
                DefaultModelSection(
                  settingsRepository: _settings,
                  initialProvider: loaded.$2,
                  initialModel: loaded.$3,
                ),
                Divider(
                  thickness: 1,
                  color: ConverPalette.of(context).border,
                ),
                ThemeSection(themeController: _themeController),
                Divider(
                  thickness: 1,
                  color: ConverPalette.of(context).border,
                ),
              ],
              for (var i = 0; i < _placeholderItems.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: ConverSpacing.space2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _placeholderItems[i].label,
                          style: textTheme.bodyLarge?.copyWith(
                            color: ConverPalette.of(context).ink2,
                          ),
                        ),
                      ),
                      const SizedBox(width: ConverSpacing.space2),
                      Text(
                        _placeholderItems[i].note,
                        style: textTheme.bodySmall?.copyWith(
                          color: ConverPalette.of(context).ink4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i != _placeholderItems.length - 1)
                  Divider(
                    thickness: 1,
                    color: ConverPalette.of(context).border,
                  ),
              ],
              // 「我」页收口入口（F-M5-10）：三占位行 → 可点击导航行
              //（1px 边框分割 + chevron 触达语义，与占位行同一视觉层级）。
              for (var i = 0; i < _profileEntries.length; i++) ...[
                _SettingsNavRow(
                  label: _profileEntries[i].label,
                  note: _profileEntries[i].note,
                  onTap: () => _openProfilePage(_profileEntries[i]),
                ),
                if (i != _profileEntries.length - 1)
                  Divider(
                    thickness: 1,
                    color: ConverPalette.of(context).border,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 「我」页收口入口单行：label + note + chevron，整行可点（InkWell 触达）。
class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.label,
    required this.note,
    required this.onTap,
  });

  final String label;

  final String note;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ConverSpacing.space2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyLarge?.copyWith(
                  color: ConverPalette.of(context).ink2,
                ),
              ),
            ),
            const SizedBox(width: ConverSpacing.space2),
            Text(
              note,
              style: textTheme.bodySmall?.copyWith(
                color: ConverPalette.of(context).ink4,
              ),
            ),
            const SizedBox(width: ConverSpacing.space1),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: ConverPalette.of(context).ink4,
            ),
          ],
        ),
      ),
    );
  }
}

/// 「我」页收口入口元数据：行文案 + 目标静态页实例。
class _ProfileEntry {
  const _ProfileEntry(this.label, this.note, this.page);

  /// 入口行名称（设置页展示文案，测试锚点）。
  final String label;

  /// 一句话说明（次级文案）。
  final String note;

  /// 目标页面实例（无状态静态文本页，可共享复用）。
  final Widget page;
}
