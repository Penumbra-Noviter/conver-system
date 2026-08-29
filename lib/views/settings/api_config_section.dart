/// API 配置组 — claude / openai 双槽位（Key 密码态 + base_url）。
///
/// 语义契约（工单 06 A1/A2/A6 + T05）：
/// - Key 保存经 [SecretStore] 槽位直写（键名逐字 `claude_api_key` /
///   `openai_api_key`）；**清空字段保存 = 删除槽位键**（A1，非写空串）
/// - base_url 经设置仓储落设置表（A2；键 `claude_base_url` / `openai_base_url`）
/// - 回显直读对应槽位（不做跨协议兜底——避免 claude 槽值显示进 openai 槽）
/// - **测试连接**（T05 / A6）：每 provider「测试连接」按钮用表单当前
///   Key / base_url 现值（不入库、独立于 `_save`；清空字段按未配置处理）
///   经 [providerFactory] 实例化后调 `testConnection`；成功 / 失败 SnackBar +
///   debugPrint（不静默吞错）。文案逐字对齐
///   `desktop/backend/app/api/routes/settings.py::test_connection`：
///   未提供 Key →「未提供 API Key，请在设置中填写后再测试」；LLM 族错误 →
///   str(e)（`errors.dart::translate_sdk_error` 消息模板逐字）；其余 →
///   「连接失败: {error}」。
///
/// 依赖注记：SecretStore 直持用于槽位写/删/回显；base_url 与其余键走
/// 设置仓储。F-9 起 [secretStore] 为构造 required 注入，由装配链单一提供
/// （home_shell ← app.dart provider），不再视图内缺省构造；[providerFactory]
/// 为 T05 的可注入 factory seam（生产默认 LLMFactory，测试注入 fake——
/// 测试注入点与装配链一致，均经本构造参数）。
library;

import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/llm/errors.dart';
import '../../services/llm/factory.dart';
import '../../services/llm/llm_provider.dart';
import '../../services/secure_store.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 槽位表单的初始回显值（键 = settings/槽位键名）。
typedef ApiEchoValues = Map<String, String>;

/// API 配置组：claude / openai 两个槽位表单 + 整组保存 + 每 provider 测试连接。
class ApiConfigSection extends StatefulWidget {
  const ApiConfigSection({
    super.key,
    required this.settingsRepository,
    required this.secretStore,
    this.providerFactory = const LLMFactory(),
    this.initialValues = const <String, String>{},
  });

  final SettingsRepository settingsRepository;

  /// 槽位直写/删通道 — 装配链注入（home_shell ← app.dart provider）；
  /// 测试注入内存 fake。
  final SecretStore secretStore;

  /// LLM Provider 工厂 seam — 测试连接经本工厂实例化 provider。
  ///
  /// 生产走默认 [LLMFactory]（工单「生产走 app 装配或默认 LLMFactory」）；
  /// 测试注入 fake factory（成功 / 失败播放），注入点与装配链一致。
  final LLMProviderFactory providerFactory;

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

  /// 正在测试连接的 provider 集（在途期间禁用对应「测试连接」按钮防重入）。
  final _testing = <String>{};

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
        await widget.settingsRepository.setMany({
          '${provider}_base_url': baseUrl,
        });
      }
      _showSnackBar('API 配置已保存');
    } catch (error) {
      debugPrint('API 配置保存失败: $error');
      _showSnackBar('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 测试连接：用表单当前 Key / base_url 现值（不入库、独立于 [_save]；
  /// F-10 边界）经 [LLMProviderFactory] 实例化后调 `testConnection`。
  ///
  /// 清空字段按未配置处理：Key 空 → 提示「未提供 API Key，请在设置中填写后再测试」
  /// 且不发任何请求；base_url 空 → null（Provider 官方默认端点）。错误映射逐字
  /// 对齐 `desktop/backend/app/api/routes/settings.py::test_connection` 局部
  /// 400 语义：[LLMError] 族 → str(e)（即 `errors.dart::translateSdkError`
  /// 消息模板）；其余异常 → 「连接失败: {error}」。成功 → 「连接成功」SnackBar +
  /// debugPrint（不静默吞错）。在途期间置 [_testing] 禁用对应按钮防重入。
  Future<void> _testConnection(String provider) async {
    final key = _keyControllers[provider]!.text.trim();
    final baseUrl = _baseUrlControllers[provider]!.text.trim();

    // 表单现值校验（未配置 Key 按未配置处理，工厂不触发、不发任何请求）。
    if (key.isEmpty) {
      debugPrint('测试连接跳过($provider): 未提供 API Key');
      _showSnackBar('未提供 API Key，请在设置中填写后再测试');
      return;
    }

    setState(() => _testing.add(provider));
    try {
      final llm = widget.providerFactory.create(
        provider: provider,
        apiKey: key,
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
      );
      await llm.testConnection();
      debugPrint('测试连接成功($provider)');
      _showSnackBar('连接成功');
    } on LLMError catch (error) {
      // LLM 族错误：str(e) 逐字（errors.dart 消息模板）。
      debugPrint('测试连接失败($provider): $error');
      _showSnackBar('$error');
    } catch (error) {
      // 其余异常兜底对齐 settings.py `except Exception`。
      debugPrint('测试连接失败($provider): $error');
      _showSnackBar('连接失败: $error');
    } finally {
      if (mounted) setState(() => _testing.remove(provider));
    }
  }

  /// 展示 SnackBar（先 hide 当前，避免与前一条排队导致反馈延迟）。
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'API 配置',
          style: textTheme.titleMedium?.copyWith(
            color: Theme.of(context).extension<ConverPalette>()!.ink1,
          ),
        ),
        const SizedBox(height: ConverSpacing.space1),
        Text(
          '服务地址与密钥（密钥存系统安全存储）',
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).extension<ConverPalette>()!.ink4,
          ),
        ),
        const SizedBox(height: ConverSpacing.space2),
        for (final provider in _providers.keys) ...[
          _fieldLabel(textTheme, '${_providers[provider]!.label} 密钥'),
          TextField(
            key: ValueKey('api-key-$provider'),
            controller: _keyControllers[provider],
            obscureText: !_visible[provider]!,
            autofillHints: const [],
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).extension<ConverPalette>()!.ink1,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: '未配置',
              suffixIcon: IconButton(
                icon: Icon(
                  _visible[provider]!
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: Theme.of(context).extension<ConverPalette>()!.ink3,
                ),
                onPressed: () =>
                    setState(() => _visible[provider] = !_visible[provider]!),
              ),
            ),
          ),
          const SizedBox(height: ConverSpacing.space2),
          _fieldLabel(textTheme, '${_providers[provider]!.label} Base URL'),
          TextField(
            key: ValueKey('base-url-$provider'),
            controller: _baseUrlControllers[provider],
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).extension<ConverPalette>()!.ink1,
            ),
            decoration: const InputDecoration(isDense: true, hintText: '官方默认'),
          ),
          const SizedBox(height: ConverSpacing.space2),
          _testButton(provider),
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
    child: Text(
      text,
      style: textTheme.bodySmall?.copyWith(
        color: Theme.of(context).extension<ConverPalette>()!.ink3,
      ),
    ),
  );

  /// 每 provider 的「测试连接」按钮（key `test-connection-<provider>`）；在途
  /// （[_testing] 含该 provider）期间禁用防重入，并以小进度指示反馈。
  Widget _testButton(String provider) {
    final inFlight = _testing.contains(provider);
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        key: ValueKey('test-connection-$provider'),
        onPressed: inFlight ? null : () => _testConnection(provider),
        icon: inFlight
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.wifi_tethering, size: 16),
        label: const Text('测试连接'),
      ),
    );
  }
}
