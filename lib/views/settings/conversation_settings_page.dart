/// 「对话」设置子页（工单 03）——全局 temperature / max_tokens 编辑、保存与回显。
///
/// 语义锚点（spec §U-2 / US-2.1 / US-2.4）：
/// - temperature：slider 0–2（对齐 character_wizard temperatureMin/Max），缺省
///   0.7；写入 `temperature` 键（mobile 先行，桌面 ALLOWED_KEYS 无此键）。
/// - max_tokens：数字输入，缺省 2048；合法区间
///   [SettingsRepository.maxTokensMin, SettingsRepository.maxTokensMax]
///   （mobile 先行，无桌面锚点；负数/非数字回退缺省、超上限 clamp）。
///
/// 视图层只做展示编排 + 输入校验，读写经 [SettingsRepository]（数据层），
/// 不触碰平台存储。
///
/// 阶段 2（PS2-09）：「主动消息」与「内心独白」两开关，沿「后台反思」先例
/// 同构——加载回显、即时写入 `proactive_message_enabled` /
/// `inner_thought_enabled` 键、写失败回滚 + SnackBar。
///
/// F-84：开关 true 且落库成功后，请求 Android 13+ 运行时通知权限——优先
/// 走 [ConversationSettingsPage.requestNotificationsPermission] seam，未注入
/// 时经 `FlutterLocalNotificationsScheduler` provider 兜底（对齐 characters_view
/// `_maybeProvider` 先例）；权限被拒/平台异常仅 debugPrint 降级，开关语义与
/// 权限正交（不回滚）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/notifications/notification_service.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 「对话」设置子页。
class ConversationSettingsPage extends StatefulWidget {
  const ConversationSettingsPage({
    super.key,
    required this.settingsRepository,
    this.requestNotificationsPermission,
  });

  /// 设置仓储（应用级统一实例，settings_view 注入）。
  final SettingsRepository settingsRepository;

  /// 通知权限请求 seam（F-84）：注入时优先；未注入时经
  /// [FlutterLocalNotificationsScheduler] provider 兜底。返回
  /// true = 已授予；false = 被拒；null = 平台无此能力。结果与开关状态正交。
  final Future<bool?> Function()? requestNotificationsPermission;

  @override
  State<ConversationSettingsPage> createState() =>
      _ConversationSettingsPageState();
}

class _ConversationSettingsPageState extends State<ConversationSettingsPage> {
  double _temperature = SettingsRepository.defaultTemperature;
  final TextEditingController _maxTokensController = TextEditingController();
  bool _reflectionEnabled = false;
  bool _proactiveEnabled = false;
  bool _innerThoughtEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxTokensController.dispose();
    super.dispose();
  }

  /// 加载已保存值回显；读取失败保持缺省（不阻塞页面渲染）。
  Future<void> _load() async {
    try {
      final temperature = await widget.settingsRepository.getTemperature();
      final maxTokens = await widget.settingsRepository.getMaxTokens();
      final reflectionEnabled =
          await widget.settingsRepository.memoryReflectionEnabled;
      final proactiveEnabled =
          await widget.settingsRepository.proactiveMessageEnabled;
      final innerThoughtEnabled =
          await widget.settingsRepository.innerThoughtEnabled;
      if (!mounted) {
        return;
      }
      setState(() {
        _temperature = temperature;
        _maxTokensController.text = maxTokens.toString();
        _reflectionEnabled = reflectionEnabled;
        _proactiveEnabled = proactiveEnabled;
        _innerThoughtEnabled = innerThoughtEnabled;
        _loaded = true;
      });
    } catch (e) {
      debugPrint('对话参数加载失败，保持缺省: $e');
      if (!mounted) {
        return;
      }
      setState(() => _loaded = true);
    }
  }

  /// 保存 temperature / max_tokens 到设置表；max_tokens 非数字回退缺省、
  /// 越界 clamp 到合法区间。
  Future<void> _save() async {
    final parsed = int.tryParse(_maxTokensController.text.trim());
    final maxTokens = parsed == null
        ? SettingsRepository.defaultMaxTokens
        : parsed
              .clamp(
                SettingsRepository.maxTokensMin,
                SettingsRepository.maxTokensMax,
              )
              .toInt();
    try {
      await widget.settingsRepository.setMany({
        'temperature': _temperature.toString(),
        'max_tokens': maxTokens.toString(),
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      debugPrint('对话参数保存失败: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换后台反思开关（即时写入 `memory_reflection_enabled` 键，ADR-0004）。
  ///
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。
  Future<void> _setReflection(bool value) async {
    setState(() => _reflectionEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.memoryReflectionEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('后台反思开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _reflectionEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换主动消息开关（阶段 2，PS2-09，即时写入
  /// `proactive_message_enabled` 键）。
  ///
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。落库成功后
  /// 沿启用路径请求通知权限（F-84），权限结果不影响开关状态。
  Future<void> _setProactiveMessage(bool value) async {
    setState(() => _proactiveEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.proactiveMessageEnabledKey: value.toString(),
      });
      await _requestNotificationPermissionIfNeeded(value);
    } catch (e) {
      debugPrint('主动消息开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _proactiveEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 启用路径的 Android 13+ 通知权限请求（F-84，仅 `value == true`）。
  ///
  /// seam 注入优先；未注入时经 [FlutterLocalNotificationsScheduler] provider
  /// 兜底（缺位 → null 跳过）。请求被拒 / 返回 null / 抛错均只 debugPrint
  /// 降级——权限与开关语义正交，绝不回滚开关也不冒泡到写仓储的 catch。
  Future<void> _requestNotificationPermissionIfNeeded(bool value) async {
    if (!value || !mounted) {
      return;
    }
    try {
      final request =
          widget.requestNotificationsPermission ??
          _maybeSchedulerPermission(context);
      final granted = (request == null) ? null : await request();
      debugPrint('主动消息通知权限请求结果（F-84）: $granted');
    } catch (e) {
      debugPrint('主动消息通知权限请求降级（开关不受影响）: $e');
    }
  }

  /// 从装配图（app.dart 单一落点）读取
  /// [FlutterLocalNotificationsScheduler.requestNotificationsPermission]；
  /// provider 缺位（既有测试无 stage2 装配）→ null，调用方降级（零回归契约，
  /// 对齐 characters_view `_maybeProvider` 先例）。
  Future<bool?> Function()? _maybeSchedulerPermission(BuildContext context) {
    try {
      return context
          .read<FlutterLocalNotificationsScheduler>()
          .requestNotificationsPermission;
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 切换内心独白开关（阶段 2，PS2-09，即时写入
  /// `inner_thought_enabled` 键）。
  ///
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。
  Future<void> _setInnerThought(bool value) async {
    setState(() => _innerThoughtEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.innerThoughtEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('内心独白开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _innerThoughtEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('对话')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  ConverSpacing.space4,
                  ConverSpacing.space5,
                  ConverSpacing.space4,
                  ConverSpacing.space6,
                ),
                children: [
                  Text(
                    '温度',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '采样随机性（0–2，默认 0.7）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  const SizedBox(height: ConverSpacing.space2),
                  Slider(
                    value: _temperature,
                    min: SettingsRepository.temperatureMin,
                    max: SettingsRepository.temperatureMax,
                    divisions: 20,
                    label: _temperature.toStringAsFixed(2),
                    onChanged: (value) => setState(() => _temperature = value),
                  ),
                  Text(
                    _temperature.toStringAsFixed(2),
                    style: textTheme.bodyLarge?.copyWith(color: palette.ink2),
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space4),
                  Text(
                    '最大 token 数',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '单次回复长度上限（1–100000，默认 2048）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  const SizedBox(height: ConverSpacing.space2),
                  TextField(
                    controller: _maxTokensController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '输入最大 token 数'),
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '后台反思',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '每 6 回合后台提炼人格事实，增强记忆（需额外 LLM 调用）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('后台反思记忆'),
                    value: _reflectionEnabled,
                    onChanged: _setReflection,
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '主动消息',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '角色会在合适时机主动发消息',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('主动消息'),
                    value: _proactiveEnabled,
                    onChanged: _setProactiveMessage,
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '内心独白',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '角色以 <thought> 形式表达内心想法',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('内心独白'),
                    value: _innerThoughtEnabled,
                    onChanged: _setInnerThought,
                  ),
                  const SizedBox(height: ConverSpacing.space5),
                  FilledButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
      ),
    );
  }
}
