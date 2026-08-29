/// 默认模型组 — provider / model 选择器（吃清单）+ 自定义模型输入。
///
/// 语义契约（工单 06 A3/A7）：
/// - provider 选择器恰为 [ModelCatalog.providers] 8 项按声明序；
///   model 选择器随 provider 联动展示该 provider 清单模型
/// - 「清单项 vs 自定义输入」归一规则提纯为 [resolveModelToSave]（A7 单测）
/// - 保存写 `default_provider` / `default_model`（经设置仓储）
///
/// 依赖注记：工单 07 装配后仓储由应用级注入统一。
library;

import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../models/model_catalog.dart';
import '../../theme/colors.dart';

/// 「清单项 vs 自定义输入」归一规则（A7 纯函数）。
///
/// 自定义输入 trim 后非空 → 原样采用（用户显式覆盖一切）；
/// 否则清单选择非空 → 采用清单项；两者皆空 → [fallbackModel]
/// （当前持久化值，避免"没动就保存"把已有配置清掉）。
String resolveModelToSave({
  required String customInput,
  required String catalogSelection,
  required String fallbackModel,
}) {
  final custom = customInput.trim();
  if (custom.isNotEmpty) {
    return custom;
  }
  final selected = catalogSelection.trim();
  if (selected.isNotEmpty) {
    return selected;
  }
  return fallbackModel;
}

/// 切换 provider 后的模型选择重置（A7 纯函数）。
///
/// 新 provider 清单非空 → 选中其首个模型；空清单 → null（清空选择，
/// 由自定义输入接管）。自定义输入的清理由调用方负责（跨控制器状态）。
String? resetModelOnProviderSwitch(List<String> models) =>
    models.isEmpty ? null : models.first;

/// 默认模型组：provider / model 联动选择器 + 自定义输入 + 保存。
class DefaultModelSection extends StatefulWidget {
  const DefaultModelSection({
    super.key,
    required this.settingsRepository,
    this.initialProvider = '',
    this.initialModel = '',
  });

  final SettingsRepository settingsRepository;

  /// 回显：当前持久化的 default_provider / default_model（空 = 未配置）。
  final String initialProvider;
  final String initialModel;

  @override
  State<DefaultModelSection> createState() => _DefaultModelSectionState();
}

class _DefaultModelSectionState extends State<DefaultModelSection> {
  late String _provider;
  late String? _catalogModel;

  /// 当前选中 provider 的清单项（providerByKey 不在 02 票公共面，本地派生）。
  ModelProvider get _currentProvider => ModelCatalog.providers.firstWhere(
        (p) => p.key == _provider,
        orElse: () => ModelCatalog.providers.first,
      );
  late final TextEditingController _customController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialProvider.isEmpty
        ? ModelCatalog.providers.first.key
        : widget.initialProvider;
    final known = ModelCatalog.providers.any((p) => p.key == initial);
    _provider = known ? initial : ModelCatalog.providers.first.key;
    final initialModels = _currentProvider.models;
    _customController = TextEditingController(
      // 初始模型不在当前 provider 清单内 → 视作自定义输入回显
      text: initialModels.contains(widget.initialModel) ? '' : widget.initialModel,
    );
    _catalogModel = initialModels.contains(widget.initialModel)
        ? widget.initialModel
        : resetModelOnProviderSwitch(initialModels);
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final model = resolveModelToSave(
        customInput: _customController.text,
        catalogSelection: _catalogModel ?? '',
        fallbackModel: widget.initialModel,
      );
      await widget.settingsRepository
          .setMany({'default_provider': _provider, 'default_model': model});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('默认模型已保存')),
        );
      }
    } catch (error) {
      debugPrint('默认模型保存失败: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final current = _currentProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('默认模型',
            style:
                textTheme.titleMedium?.copyWith(color: ConverColors.ink1)),
        const SizedBox(height: ConverSpacing.space1),
        Text('供应商与模型选择（新对话的缺省取值）',
            style:
                textTheme.bodySmall?.copyWith(color: ConverColors.ink4)),
        const SizedBox(height: ConverSpacing.space2),
        _fieldLabel(textTheme, '供应商'),
        DropdownButtonFormField<String>(
          initialValue: _provider,
          isDense: true,
          items: [
            for (final p in ModelCatalog.providers)
              DropdownMenuItem(value: p.key, child: Text(p.name)),
          ],
          onChanged: (value) {
            if (value == null || value == _provider) {
              return;
            }
            setState(() {
              _provider = value;
              _catalogModel = resetModelOnProviderSwitch(
                  ModelCatalog.providers
                      .firstWhere((p) => p.key == value)
                      .models);
              _customController.clear();
            });
          },
        ),
        const SizedBox(height: ConverSpacing.space2),
        _fieldLabel(textTheme, '模型（清单内）'),
        DropdownButtonFormField<String>(
          initialValue: _catalogModel,
          isDense: true,
          items: [
            for (final m in current.models)
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (value) => setState(() => _catalogModel = value),
        ),
        const SizedBox(height: ConverSpacing.space2),
        _fieldLabel(textTheme, '自定义模型（非空时覆盖清单选择）'),
        TextField(
          controller: _customController,
          style: textTheme.bodyMedium?.copyWith(color: ConverColors.ink1),
          decoration: const InputDecoration(
            isDense: true,
            hintText: '留空使用上方清单选择',
          ),
        ),
        const SizedBox(height: ConverSpacing.space3),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('保存默认模型'),
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
