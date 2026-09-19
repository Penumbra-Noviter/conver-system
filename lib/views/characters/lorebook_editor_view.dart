/// LorebookEditorView — 角色世界书编辑器（WL-04）。
///
/// 双视图：列表页（标题/前 3 关键词+计数/常驻标记/order/开关/来源 badge +
/// 搜索过滤 + 删除确认）+ 编辑表单页（关键词 chips/内容/匹配模式/位置三选/
/// order/probability/group_weight/depth/group_name/常驻/启用 + 内联校验 +
/// 泛词告警）。布局语义对齐桌面 `frontend/js/components/lorebook-editor.js`
/// （列表行要素、表单字段、泛词告警文案、保存/取消动作）。
///
/// 层级：呈现层。业务判定（校验/chips/泛词/数值边界）在 controller 纯函数核，
/// 本层只做展示编排与导航。增删改经 [LorebookEditorController]（装配注入），
/// 不触碰数据层 / 平台存储。
library;

import 'package:flutter/material.dart';

import '../../data/database/app_database.dart' show LorebookEntry;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/notice_banner.dart';
import 'lorebook_editor_controller.dart';

/// 世界书编辑器列表页。
class LorebookEditorView extends StatefulWidget {
  /// [controller] 装配注入（worldbook CRUD + 搜索 + 开关状态持有者）。
  const LorebookEditorView({super.key, required this.controller});

  /// 世界书编辑器状态持有者（装配注入）。
  final LorebookEditorController controller;

  @override
  State<LorebookEditorView> createState() => _LorebookEditorViewState();
}

class _LorebookEditorViewState extends State<LorebookEditorView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.load();
      }
    });
  }

  void _onChanged() {
    final message = widget.controller.snackMessage;
    if (message != null && mounted) {
      widget.controller.consumeSnackMessage();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  /// 打开条目编辑页（[entry] null = 新增）。
  void _openEditor(LorebookEntry? entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LorebookEntryEditView(
          controller: widget.controller,
          entry: entry,
        ),
      ),
    );
  }

  /// 删除确认（对齐桌面 showConfirm 语义）；确认后经 controller 删除。
  Future<void> _confirmDelete(LorebookEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条世界书条目？'),
        content: const Text('删除后不可恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.deleteEntry(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final entries = controller.entries;
    final filtered = controller.filteredEntries;
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('世界书'),
        actions: [
          IconButton(
            tooltip: '新增条目',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(null),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NoticeBanner(
            notice: controller.notice,
            onDismiss: controller.dismissNotice,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space2,
              ConverSpacing.space4,
              ConverSpacing.space2,
            ),
            child: TextField(
              key: const Key('lorebook-search'),
              onChanged: controller.setSearchQuery,
              decoration: const InputDecoration(
                hintText: '按标题/关键词过滤…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: controller.loading && entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? const EmptyState(
                        icon: Icons.menu_book_outlined,
                        message: '暂无世界书条目',
                        hint: '为角色添加触发关键词与注入内容，对话中自动命中注入',
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              '无匹配条目',
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: palette.ink3),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ConverSpacing.space4,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final entry = filtered[index];
                              return _LorebookRow(
                                entry: entry,
                                onToggle: () =>
                                    controller.toggleEnabled(entry),
                                onEdit: () => _openEditor(entry),
                                onDelete: () => _confirmDelete(entry),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// 世界书条目行：标题（+ 常驻/记忆 badge）+ 关键词预览 + order + 开关 + 编辑/删除。
class _LorebookRow extends StatelessWidget {
  const _LorebookRow({
    required this.entry,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final LorebookEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final keys = entry.keys;
    final keysPreview = keys.take(3).join('、');
    final extraCount = keys.length > 3 ? keys.length - 3 : 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: ConverSpacing.space1),
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space3,
        vertical: ConverSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(ConverRadii.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.title.isEmpty ? '（未命名）' : entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: palette.ink1),
                      ),
                    ),
                    if (entry.constant) ...[
                      const SizedBox(width: ConverSpacing.space2),
                      _Badge(label: '常驻', emphasized: true),
                    ],
                    if (entry.source == 'auto') ...[
                      const SizedBox(width: ConverSpacing.space2),
                      _Badge(label: '记忆', emphasized: false),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        keysPreview.isEmpty ? '（常驻/无关键词）' : keysPreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: palette.ink3),
                      ),
                    ),
                    if (extraCount > 0)
                      Text(
                        '+$extraCount',
                        style: textTheme.bodySmall
                            ?.copyWith(color: palette.ink4),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: ConverSpacing.space2),
          Text(
            '${entry.order}',
            style: textTheme.labelMedium?.copyWith(color: palette.ink3),
          ),
          Switch(
            value: entry.enabled,
            onChanged: (_) => onToggle(),
          ),
          IconButton(
            tooltip: '编辑',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.edit_outlined, size: 20, color: palette.ink3),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 行内小徽标（常驻/记忆来源）。
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.emphasized});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: emphasized
            ? colorScheme.primary.withValues(alpha: 0.13)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(ConverRadii.sm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: emphasized
                  ? colorScheme.primary
                  : ConverPalette.of(context).ink3,
              fontSize: 11,
            ),
      ),
    );
  }
}

/// 世界书条目编辑表单页（新增/编辑共用；[entry] null = 新增）。
class LorebookEntryEditView extends StatefulWidget {
  /// [controller] 数据源；[entry] 待编辑条目（null → 新增模式）。
  const LorebookEntryEditView({
    super.key,
    required this.controller,
    this.entry,
  });

  /// 世界书编辑器状态持有者（装配注入）。
  final LorebookEditorController controller;

  /// 待编辑条目；null 为新增。
  final LorebookEntry? entry;

  @override
  State<LorebookEntryEditView> createState() => _LorebookEntryEditViewState();
}

class _LorebookEntryEditViewState extends State<LorebookEntryEditView> {
  late final TextEditingController _title;
  late final TextEditingController _keysInput;
  late final TextEditingController _content;
  late final TextEditingController _order;
  late final TextEditingController _probability;
  late final TextEditingController _groupName;
  late final TextEditingController _groupWeight;
  late final TextEditingController _depth;
  late List<String> _keys;
  late bool _constant;
  late bool _enabled;
  late String _matchMode;
  late String _position;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    final entry = widget.entry;
    _title = TextEditingController(text: entry?.title ?? '');
    _keysInput = TextEditingController();
    _content = TextEditingController(text: entry?.content ?? '');
    _order = TextEditingController(text: '${entry?.order ?? 100}');
    _probability =
        TextEditingController(text: '${entry?.probability ?? 100}');
    _groupName = TextEditingController(text: entry?.groupName ?? '');
    _groupWeight =
        TextEditingController(text: '${entry?.groupWeight ?? 100}');
    _depth = TextEditingController(text: '${entry?.depth ?? 20}');
    _keys = [...?entry?.keys];
    _constant = entry?.constant ?? false;
    _enabled = entry?.enabled ?? true;
    _matchMode = entry?.matchMode ?? 'or';
    _position = entry?.position ?? 'world';
  }

  void _onControllerChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _title.dispose();
    _keysInput.dispose();
    _content.dispose();
    _order.dispose();
    _probability.dispose();
    _groupName.dispose();
    _groupWeight.dispose();
    _depth.dispose();
    super.dispose();
  }

  /// 录入关键词（逗号分隔解析 + 去重保序），清空输入框。
  void _addKeysFromInput() {
    final input = _keysInput.text;
    if (input.trim().isEmpty) {
      return;
    }
    var next = _keys;
    for (final key in parseKeyInput(input)) {
      next = addKeyChip(next, key);
    }
    setState(() {
      _keys = next;
      _keysInput.clear();
      _errors = const {};
    });
  }

  /// 删除单个关键词 chip。
  void _removeKey(String key) {
    setState(() {
      _keys = removeKeyChip(_keys, key);
      _errors = const {};
    });
  }

  /// 保存：校验失败 → 内联错误阻止提交；通过 → 构建 draft 走 CRUD 后返回列表。
  Future<void> _save() async {
    final errors = validateLorebookEntry(
      content: _content.text,
      keys: _keys,
      constant: _constant,
      order: _order.text,
      probability: _probability.text,
      groupWeight: _groupWeight.text,
      depth: _depth.text,
    );
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final draft = buildLorebookDraft(
      title: _title.text,
      keys: _keys,
      content: _content.text,
      constant: _constant,
      order: _order.text,
      probability: _probability.text,
      groupName: _groupName.text,
      groupWeight: _groupWeight.text,
      matchMode: _matchMode,
      position: _position,
      depth: _depth.text,
      enabled: _enabled,
    );
    final entry = widget.entry;
    if (entry == null) {
      await widget.controller.createEntry(draft);
    } else {
      await widget.controller.updateEntry(entry.id, draft);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final hasGenericKey = _keys.any(isGenericKey);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑条目' : '新增条目'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NoticeBanner(
              notice: widget.controller.notice,
              onDismiss: widget.controller.dismissNotice,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(ConverSpacing.space4),
                children: [
                  Text(
                    '基本信息',
                    style:
                        textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space2),
                  TextField(
                    key: const Key('lorebook-title'),
                    controller: _title,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      hintText: '条目标题（可空）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: ConverSpacing.space2),
                  TextField(
                    key: const Key('lorebook-keys-input'),
                    controller: _keysInput,
                    onSubmitted: (_) => _addKeysFromInput(),
                    decoration: InputDecoration(
                      labelText: '触发关键词',
                      hintText: '回车或点添加录入；支持逗号分隔',
                      errorText: _errors['keys'],
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        key: const Key('lorebook-keys-add'),
                        tooltip: '添加',
                        icon: const Icon(Icons.add),
                        onPressed: _addKeysFromInput,
                      ),
                    ),
                  ),
                  if (_keys.isNotEmpty) ...[
                    const SizedBox(height: ConverSpacing.space2),
                    Wrap(
                      spacing: ConverSpacing.space2,
                      runSpacing: ConverSpacing.space1,
                      children: [
                        for (final key in _keys)
                          InputChip(
                            label: Text(key),
                            onDeleted: () => _removeKey(key),
                            deleteIcon: const Icon(Icons.cancel, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                  if (hasGenericKey) ...[
                    const SizedBox(height: ConverSpacing.space1),
                    Text(
                      '关键词过泛，会显著增加注入量',
                      key: const Key('lorebook-generic-warning'),
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: ConverSpacing.space3),
                  TextField(
                    key: const Key('lorebook-content'),
                    controller: _content,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: '注入内容',
                      hintText: '命中后注入的世界书内容（上限 $contentMaxLength 字符）',
                      errorText: _errors['content'],
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: ConverSpacing.space3),
                  DropdownButtonFormField<String>(
                    key: const Key('lorebook-match-mode'),
                    initialValue: _matchMode,
                    decoration: const InputDecoration(
                      labelText: '匹配模式',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'or',
                        child: Text('或（任一命中）'),
                      ),
                      DropdownMenuItem(
                        value: 'and',
                        child: Text('与（全部命中）'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _matchMode = value);
                      }
                    },
                  ),
                  const SizedBox(height: ConverSpacing.space3),
                  DropdownButtonFormField<String>(
                    key: const Key('lorebook-position'),
                    initialValue: _position,
                    decoration: const InputDecoration(
                      labelText: '注入位置',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'world',
                        child: Text('世界知识'),
                      ),
                      DropdownMenuItem(
                        value: 'before_char',
                        child: Text('角色设定前'),
                      ),
                      DropdownMenuItem(
                        value: 'after_char',
                        child: Text('场景设定后'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _position = value);
                      }
                    },
                  ),
                  const SizedBox(height: ConverSpacing.space3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('lorebook-order'),
                          controller: _order,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '排序 order',
                            hintText: '0-9999',
                            errorText: _errors['order'],
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: ConverSpacing.space3),
                      Expanded(
                        child: TextField(
                          key: const Key('lorebook-probability'),
                          controller: _probability,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '命中概率 %',
                            hintText: '1-100',
                            errorText: _errors['probability'],
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ConverSpacing.space3),
                  TextField(
                    key: const Key('lorebook-group-name'),
                    controller: _groupName,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: '互斥组名',
                      hintText: '空=不分组',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: ConverSpacing.space3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('lorebook-group-weight'),
                          controller: _groupWeight,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '组内权重',
                            hintText: '1-100',
                            errorText: _errors['groupWeight'],
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: ConverSpacing.space3),
                      Expanded(
                        child: TextField(
                          key: const Key('lorebook-depth'),
                          controller: _depth,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '记忆深度',
                            hintText: '0-20',
                            errorText: _errors['depth'],
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ConverSpacing.space2),
                  SwitchListTile(
                    key: const Key('lorebook-constant'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('常驻'),
                    subtitle: const Text('不判命中，直接注入'),
                    value: _constant,
                    onChanged: (value) => setState(() => _constant = value),
                  ),
                  SwitchListTile(
                    key: const Key('lorebook-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用'),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
