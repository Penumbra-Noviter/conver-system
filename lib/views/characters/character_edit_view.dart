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
/// 层级：呈现层。经 [CharactersController]（app 装配注入）持有数据访问，
/// 本层不触碰数据层 / 平台存储。
library;

import 'package:flutter/material.dart';

import 'package:drift/drift.dart' show Value;

import '../../data/database/app_database.dart' show Character, CharactersCompanion;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import 'characters_controller.dart';

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

  @override
  void initState() {
    super.initState();
    final character = widget.character;
    _name = TextEditingController(text: character.name);
    _description = TextEditingController(text: character.description);
    _personality = TextEditingController(text: character.personality);
    _firstMes = TextEditingController(text: character.firstMes);
    _temperature = character.temperature;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _personality.dispose();
    _firstMes.dispose();
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
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
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