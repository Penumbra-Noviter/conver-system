import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/secure_store.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../view_models/theme_controller.dart';
import '../../widgets/placeholder_group.dart';
import 'about_page.dart';
import 'api_config_section.dart';
import 'conversation_settings_page.dart';
import 'default_model_section.dart';
import 'desktop_note_page.dart';
import 'manual_page.dart';
import 'theme_section.dart';

/// 设置视图 — 三组真实化（API 配置 / 默认模型 / 主题）+「对话」设置子页入口
/// （工单 03）+ 一占位（模板变量）+「我」页收口三入口（用户手册 / 关于 /
/// 桌面版说明，F-M5-10）。
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
  /// 「模板变量」占位不在本票范围（锚共识 D1）；「对话」已真实化为导航入口
  /// （工单 03，见 [_openConversationSettings]）。
  static const _placeholderItems = <PlaceholderItem>[
    PlaceholderItem('模板变量', '自定义注入变量'),
  ];

  /// 「我」页收口三入口（F-M5-10）：行文案 + 目标静态页实例（可共享复用）。
  static const _profileEntries = <({String label, String note, Widget page})>[
    (label: '用户手册', note: '使用说明', page: ManualPage()),
    (label: '关于', note: '版本信息', page: AboutPage()),
    (label: '桌面版说明', note: '桌面端获取指引', page: DesktopNotePage()),
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
  void _openProfilePage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// 打开「对话」设置子页（工单 03；子页自带 Scaffold + AppBar 返回）。
  void _openConversationSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationSettingsPage(
          settingsRepository: _settings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
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
                style: textTheme.titleLarge?.copyWith(color: palette.ink1),
              ),
              const SizedBox(height: ConverSpacing.space1),
              Text(
                '应用配置集中管理',
                style: textTheme.bodyMedium?.copyWith(color: palette.ink3),
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
                Divider(thickness: 1, color: palette.border),
                DefaultModelSection(
                  settingsRepository: _settings,
                  initialProvider: loaded.$2,
                  initialModel: loaded.$3,
                ),
                Divider(thickness: 1, color: palette.border),
                ThemeSection(themeController: _themeController),
                Divider(thickness: 1, color: palette.border),
              ],
              // 「对话」导航入口（工单 03）+「模板变量」占位（锚共识 D1）。
              _SettingsRow(
                label: '对话',
                note: '生成参数与行为',
                onTap: _openConversationSettings,
              ),
              Divider(thickness: 1, color: palette.border),
              for (var i = 0; i < _placeholderItems.length; i++) ...[
                _SettingsRow(
                  label: _placeholderItems[i].label,
                  note: _placeholderItems[i].note,
                ),
                if (i != _placeholderItems.length - 1)
                  Divider(thickness: 1, color: palette.border),
              ],
              // 「我」页收口三入口（F-M5-10）：共享行组件、整行可点 + chevron。
              for (var i = 0; i < _profileEntries.length; i++) ...[
                _SettingsRow(
                  label: _profileEntries[i].label,
                  note: _profileEntries[i].note,
                  onTap: () => _openProfilePage(_profileEntries[i].page),
                ),
                if (i != _profileEntries.length - 1)
                  Divider(thickness: 1, color: palette.border),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 设置页共享行组件：label + note（导航行追加 chevron + 整行可点）。
///
/// [onTap] 非空 → 导航行（InkWell 触达 + chevron 触达语义）；为空 →
/// 占位行（不可点、无 chevron）。两路复用同一视觉层级（F-M5-10）。
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.note,
    this.onTap,
  });

  /// 行名称（设置页展示文案，测试锚点）。
  final String label;

  /// 一句话说明（次级文案）。
  final String note;

  /// 整行点击动作；null = 占位行（不可点、无 chevron）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ConverSpacing.space2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyLarge?.copyWith(color: palette.ink2),
              ),
            ),
            const SizedBox(width: ConverSpacing.space2),
            Text(
              note,
              style: textTheme.bodySmall?.copyWith(color: palette.ink4),
            ),
            if (onTap != null) ...[
              const SizedBox(width: ConverSpacing.space1),
              Icon(Icons.chevron_right, size: 18, color: palette.ink4),
            ],
          ],
        ),
      ),
    );
  }
}