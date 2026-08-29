/// API 配置组 — claude / openai 双槽位（Key 密码态 + base_url）。
///
/// 语义契约（工单 06 A1/A2/A6）：
/// - Key 保存经 [SecretStore] 槽位直写（键名逐字 `claude_api_key` /
///   `openai_api_key`）；**清空字段保存 = 删除槽位键**（A1，非写空串）
/// - base_url 经设置仓储落设置表（A2；键 `claude_base_url` / `openai_base_url`）
/// - 回显直读对应槽位（不做跨协议兜底——避免 claude 槽值显示进 openai 槽）
/// - 无任何 LLM 网络请求（A6；test_connection 归 M2）
///
/// 依赖注记：SecretStore 直持用于槽位写/删/回显；base_url 与其余键走
/// 设置仓储。F-9 起 [secretStore] 为构造 required 注入，由装配链单一提供
/// （home_shell ← app.dart provider），不再视图内缺省构造。
library;

import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/secure_store.dart';
import '../../theme/colors.dart';

/// 槽位表单的初始回显值（键 = settings/槽位键名）。
typedef ApiEchoValues = Map<String, String>;

/// API 配置组：claude / openai 两个槽位表单 + 整组保存。
class ApiConfigSection extends StatefulWidget {
  const ApiConfigSection({
    super.key,
    required this.settingsRepository,
    required this.secretStore,
    this.initialValues = const <String, String>{},
  });

  final SettingsRepository settingsRepository;

  /// 槽位直写/删通道 — 装配链注入（home_shell ← app.dart provider）；
  /// 测试注入内存 fake。
  final SecretStore secretStore;

  /// 回显初值：`claude_api_key` / `openai_api_key` / `claude_base_url` /
  /// `openai_base_url`（缺键 = 未配置，显示为空）。
  final ApiEchoValues initialValues;

  @override
  State<ApiConfigSection> createState() => _ApiConfigSectionState();
}

class _ApiConfigSectionState extends State<ApiConfigSection> {
  /// provider 名 → 安全存储槽位键 / 展示名（双槽位，与桌面 _CRED_SLOTS 同序）。
  static const _providers = <String, ({String slotKey, String label})>{
    'claude': (slotKey: SecretStore.claudeApiKeySlot, label: 'Claude'),
    'openai': (slotKey: SecretStore.openaiApiKeySlot, label: 'OpenAI'),
  };

  late final SecretStore _secretStore = widget.secretStore;
  final _keyControllers = <String, TextEditingController>{};
  final _baseUrlControllers = <String, TextEditingController>{};
  final _visible = <String, bool>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final provider in _providers.keys) {
      _keyControllers[provider] = TextEditingController(
        text: widget.initialValues[_providers[provider]!.slotKey] ?? '',
      );
      _visible[provider] = false;
      _baseUrlControllers[provider] = TextEditingController(
        text: widget.initialValues['${provider}_base_url'] ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    for (final c in _baseUrlControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final provider in _providers.keys) {
        final slotKey = _providers[provider]!.slotKey;
        final keyValue = _keyControllers[provider]!.text.trim();
        if (keyValue.isEmpty) {
          await _secretStore.delete(slotKey); // A1：清空 = 删槽位键
        } else {
          await _secretStore.write(key: slotKey, value: keyValue);
        }
        final baseUrl = _baseUrlControllers[provider]!.text.trim();
        await widget.settingsRepository.setMany({'${provider}_base_url': baseUrl});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 配置已保存')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('API 配置',
            style:
                textTheme.titleMedium?.copyWith(color: ConverColors.ink1)),
        const SizedBox(height: ConverSpacing.space1),
        Text('服务地址与密钥（密钥存系统安全存储）',
            style:
                textTheme.bodySmall?.copyWith(color: ConverColors.ink4)),
        const SizedBox(height: ConverSpacing.space2),
        for (final provider in _providers.keys) ...[
          _fieldLabel(textTheme, '${_providers[provider]!.label} 密钥'),
          TextField(
            controller: _keyControllers[provider],
            obscureText: !_visible[provider]!,
            autofillHints: const [],
            style: textTheme.bodyMedium?.copyWith(color: ConverColors.ink1),
            decoration: InputDecoration(
              isDense: true,
              hintText: '未配置',
              suffixIcon: IconButton(
                icon: Icon(
                  _visible[provider]!
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: ConverColors.ink3,
                ),
                onPressed: () =>
                    setState(() => _visible[provider] = !_visible[provider]!),
              ),
            ),
          ),
          const SizedBox(height: ConverSpacing.space2),
          _fieldLabel(textTheme, '${_providers[provider]!.label} Base URL'),
          TextField(
            controller: _baseUrlControllers[provider],
            style: textTheme.bodyMedium?.copyWith(color: ConverColors.ink1),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '官方默认',
            ),
          ),
          const SizedBox(height: ConverSpacing.space3),
        ],
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('保存 API 配置'),
        ),
      ],
    );
  }

  Widget _fieldLabel(TextTheme textTheme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: ConverSpacing.space1),
        child:
            Text(text, style: textTheme.bodySmall?.copyWith(color: ConverColors.ink3)),
      );
}
