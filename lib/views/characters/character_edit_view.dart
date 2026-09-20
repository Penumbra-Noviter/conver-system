/// 角色编辑表单（M3-01 新增）：预填角色字段 → 部分更新保存。
///
/// 语义锚点（工单 01 验收 4）：
/// - 打开编辑表单并预填角色字段（名称 / 描述 / 人格 / 开场白 / 温度）；
/// - 保存走 [CharactersController.saveCharacter] →
///   [CharacterRepository.updateCharacter] 部分更新（仅显式提供字段，
///   `updated_at` 前移由仓储契约保证）；
/// - 无角色名保存拦截（锚文案「角色名称不能为空」）；
/// - 取消零副作用（不触发任何仓储写入）。
///
/// 预设对话编辑（NPD-03 验收 5）：
/// - 预设对话列表编辑：每行 名称 + 正文 两字段 + 删除按钮；「添加预设对话」
///   追加空行，行数达 [presetDialogueMax]（10）时禁用（超出阻止）；
/// - 保存 payload 归一化对齐 `character_card.dart::_normalizePresetDialogues`
///   语义（桌面 `character_card.py::_normalize_preset_dialogues`）：name /
///   content trim 后任一为空 → 过滤；按 name 去重保留首个；截断至
///   [presetDialogueMax]；归一化结果随 [CharactersCompanion.presetDialogues]
///   落库（conver_system 命名空间往返由 character_card 承载）；
/// - 重开面板字段还原：行状态自 [Character.presetDialogues] 初始化。
///
/// 层级：呈现层。经 [CharactersController]（app 装配注入）持有数据访问，
/// 本层不触碰数据层 / 平台存储。
library;

import 'package:flutter/material.dart';

import 'package:drift/drift.dart' show Value;

import '../../data/database/app_database.dart' show Character, CharactersCompanion;
import '../../services/character_card.dart' show presetDialogueMax;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import 'characters_controller.dart';

/// 预设对话编辑行：名称 + 正文两个输入控制器（行态，保存时归一化落库）。
class _PresetRow {
  _PresetRow({required this.name, required this.content});

  final TextEditingController name;
  final TextEditingController content;

  void dispose() {
    name.dispose();
    content.dispose();
  }
}

/// 角色编辑页：全屏表单，保存 / 取消。
class CharacterEditView extends StatefulWidget {
  const CharacterEditView({
    super.key,
    required this.controller,
    required this.character,
  });

  /// 列表控制器（保存 / 取消经此与仓储互动）。
  final CharactersController controller;

  /// 待编辑角色的初始快照（表单预填；保存后由列表刷新反映最新值）。
  final Character character;

  @override
  State<CharacterEditView> createState() => _CharacterEditViewState();
}

class _CharacterEditViewState extends State<CharacterEditView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _personality;
  late final TextEditingController _firstMes;
  late double _temperature;
  late final List<_PresetRow> _presetRows;

  @override
  void initState() {
    super.initState();
    final character = widget.character;
    _name = TextEditingController(text: character.name);
    _description = TextEditingController(text: character.description);
    _personality = TextEditingController(text: character.personality);
    _firstMes = TextEditingController(text: character.firstMes);
    _temperature = character.temperature;
    // 重开面板字段还原：从角色 presetDialogues 初始化各行。
    _presetRows = [
      for (final preset in character.presetDialogues)
        _PresetRow(
          name: TextEditingController(text: preset['name'] ?? ''),
          content: TextEditingController(text: preset['content'] ?? ''),
        ),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _personality.dispose();
    _firstMes.dispose();
    for (final row in _presetRows) {
      row.dispose();
    }
    super.dispose();
  }

  /// 保存（部分更新）：校验通过 → [CharactersController.saveCharacter] →
  /// 弹回列表（列表经 controller 刷新）。校验失败仅拦在本页，零副作用。
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await widget.controller.saveCharacter(
      widget.character.id,
      CharactersCompanion(
        name: Value(_name.text.trim()),
        description: Value(_description.text.trim()),
        personality: Value(_personality.text.trim()),
        firstMes: Value(_firstMes.text.trim()),
        temperature: Value(_temperature),
        presetDialogues: Value(_normalizePresetRows()),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 添加一个预设对话空行（上限 [presetDialogueMax] 时由按钮禁用阻止，此处
  /// 防御性 no-op）。
  void _addPresetRow() {
    if (_presetRows.length >= presetDialogueMax) {
      return;
    }
    setState(() {
      _presetRows.add(
        _PresetRow(
          name: TextEditingController(),
          content: TextEditingController(),
        ),
      );
    });
  }

  /// 删除第 [index] 行（零行时 no-op）。
  void _removePresetRow(int index) {
    if (index < 0 || index >= _presetRows.length) {
      return;
    }
    setState(() {
      final row = _presetRows.removeAt(index);
      row.dispose();
    });
  }

  /// 编辑行 → 保存 payload 归一化（对齐 character_card.dart
  /// `_normalizePresetDialogues` 语义：任一字段 trim 后为空 → 过滤；按 name
  /// 去重保留首个；截断至 [presetDialogueMax]）。
  List<Map<String, String>> _normalizePresetRows() {
    final result = <Map<String, String>>[];
    final seen = <String>{};
    for (final row in _presetRows) {
      final name = row.name.text.trim();
      final content = row.content.text.trim();
      if (name.isEmpty || content.isEmpty) {
        continue;
      }
      if (!seen.add(name)) {
        continue;
      }
      result.add({'name': name, 'content': content});
      if (result.length >= presetDialogueMax) {
        break;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑角色'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(ConverSpacing.space4),
            children: [
              Text(
                '基本信息',
                style: textTheme.titleMedium?.copyWith(color: palette.ink1),
              ),
              const SizedBox(height: ConverSpacing.space2),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '角色名称',
                  hintText: '必填',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) {
                    return '角色名称不能为空';
                  }
                  return null;
                },
              ),
              const SizedBox(height: ConverSpacing.space3),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: ConverSpacing.space3),
              TextFormField(
                controller: _personality,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '人格',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: ConverSpacing.space3),
              TextFormField(
                controller: _firstMes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '开场白',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: ConverSpacing.space4),
              Text(
                '预设对话',
                style: textTheme.titleMedium?.copyWith(color: palette.ink1),
              ),
              const SizedBox(height: ConverSpacing.space1),
              Text(
                '用于新建对话时选择的预设情景（最多 $presetDialogueMax 条）',
                style: textTheme.bodySmall?.copyWith(color: palette.ink3),
              ),
              const SizedBox(height: ConverSpacing.space2),
              for (var i = 0; i < _presetRows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: ConverSpacing.space2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          key: Key('preset-name-$i'),
                          controller: _presetRows[i].name,
                          decoration: const InputDecoration(
                            labelText: '名称',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: ConverSpacing.space2),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          key: Key('preset-content-$i'),
                          controller: _presetRows[i].content,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: '正文',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('preset-delete-$i'),
                        tooltip: '删除该预设对话',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removePresetRow(i),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: ConverSpacing.space1),
              OutlinedButton.icon(
                key: const Key('preset-add'),
                onPressed:
                    _presetRows.length >= presetDialogueMax ? null : _addPresetRow,
                icon: const Icon(Icons.add),
                label: const Text('添加预设对话'),
              ),
              const SizedBox(height: ConverSpacing.space4),
              Text(
                '对话温度',
                style: textTheme.titleMedium?.copyWith(color: palette.ink1),
              ),
              const SizedBox(height: ConverSpacing.space1),
              Text(
                '${_temperature.toStringAsFixed(2)}（0–2，默认 0.7）',
                style: textTheme.bodySmall?.copyWith(color: palette.ink3),
              ),
              Slider(
                value: _temperature.clamp(0, 2).toDouble(),
                min: 0,
                max: 2,
                divisions: 40,
                label: _temperature.toStringAsFixed(2),
                onChanged: (value) => setState(() => _temperature = value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
