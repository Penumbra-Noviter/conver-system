/// 「模板变量」编辑子页（工单 04）——用户自定义注入变量的增删改、保存与回显。
///
/// 语义锚点（spec §U-3）：
/// - 每行 `key=value` 可增删改；「保存」把非空 key 行序列化为 JSON 存入 Settings
///   表单一键 `template_vars`（值为 `{"key":"value",...}`，非敏感、不进
///   secure_storage）；
/// - 重进页面经 [SettingsRepository.templateVars] 反序列化回显；
/// - 空 key 行（key 去除首尾空白后为空）在保存时被过滤，不产生空键；
/// - 保留 key（`user` / `char`）不做 UI 拦截——替换层 [applyTemplateVars] 已跳过
///   同名 key（保留 key 优先），本页只负责键值编辑。
///
/// 视图层只做展示编排 + 输入收集，读写经 [SettingsRepository]（数据层），
/// 不触碰平台存储。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 「模板变量」编辑子页。
class TemplateVarsPage extends StatefulWidget {
  const TemplateVarsPage({super.key, required this.settingsRepository});

  /// 设置仓储（应用级统一实例，settings_view 注入）。
  final SettingsRepository settingsRepository;

  @override
  State<TemplateVarsPage> createState() => _TemplateVarsPageState();
}

/// 单行变量编辑态：key / value 两输入控制器（dispose 随行移除）。
class _VarRow {
  _VarRow(String key, String value)
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  /// 变量名输入控制器。
  final TextEditingController keyController;

  /// 变量值输入控制器。
  final TextEditingController valueController;

  /// 释放两个输入控制器。
  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _TemplateVarsPageState extends State<TemplateVarsPage> {
  final List<_VarRow> _rows = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  /// 加载已保存变量回显；读取失败保持空（不阻塞页面渲染）。
  Future<void> _load() async {
    try {
      final vars = await widget.settingsRepository.templateVars;
      if (!mounted) {
        return;
      }
      setState(() {
        _rows
          ..clear()
          ..addAll(vars.entries.map((e) => _VarRow(e.key, e.value)));
        _loaded = true;
      });
    } catch (e) {
      debugPrint('模板变量加载失败，保持空: $e');
      if (!mounted) {
        return;
      }
      setState(() => _loaded = true);
    }
  }

  /// 追加一行空变量编辑态。
  void _addRow() {
    setState(() => _rows.add(_VarRow('', '')));
  }

  /// 移除指定行并释放其控制器。
  void _removeRow(int index) {
    setState(() => _rows.removeAt(index).dispose());
  }

  /// 收集非空 key 行序列化 JSON 写入 `template_vars` 键；空 key 行被过滤。
  Future<void> _save() async {
    final vars = <String, String>{};
    for (final row in _rows) {
      final key = row.keyController.text.trim();
      if (key.isEmpty) {
        continue;
      }
      vars[key] = row.valueController.text;
    }
    try {
      await widget.settingsRepository.setMany({'template_vars': jsonEncode(vars)});
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      debugPrint('模板变量保存失败: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('模板变量')),
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
                    '自定义注入变量',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '聊天中 {{key}} 将被替换为对应值。',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: ConverSpacing.space4,
                      ),
                      child: Text(
                        '尚未添加变量',
                        style: textTheme.bodyMedium?.copyWith(color: palette.ink4),
                      ),
                    )
                  else
                    for (var i = 0; i < _rows.length; i++) _buildRow(i),
                  const SizedBox(height: ConverSpacing.space3),
                  OutlinedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    label: const Text('添加变量'),
                  ),
                  const SizedBox(height: ConverSpacing.space5),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
      ),
    );
  }

  /// 构建第 [index] 行：key + value 输入框 + 删除按钮。
  Widget _buildRow(int index) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: ConverSpacing.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: row.keyController,
              decoration: const InputDecoration(hintText: '变量名'),
            ),
          ),
          const SizedBox(width: ConverSpacing.space2),
          Expanded(
            child: TextField(
              controller: row.valueController,
              decoration: const InputDecoration(hintText: '变量值'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () => _removeRow(index),
          ),
        ],
      ),
    );
  }
}
