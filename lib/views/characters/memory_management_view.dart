/// MemoryManagementView — 角色记忆管理页（AC-05）。
///
/// 展示指定角色的记忆条目（人格事实 / 情景记忆，可编辑 / 删除 / 新增）与
/// 人设演化历史（只读快照列表）。纯展示编排：数据经
/// [MemoryManagementController]（注入），不触碰数据层 / 平台存储。
library;

import 'package:flutter/material.dart';

import '../../data/database/app_database.dart'
    show MemoryEntry, PersonaRevision;
import '../../data/database/tables.dart' show MemoryKind;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/notice_banner.dart';
import 'memory_management_controller.dart';

/// 记忆管理页。
class MemoryManagementView extends StatefulWidget {
  const MemoryManagementView({super.key, required this.controller});

  /// 记忆管理状态持有者（装配注入）。
  final MemoryManagementController controller;

  @override
  State<MemoryManagementView> createState() => _MemoryManagementViewState();
}

class _MemoryManagementViewState extends State<MemoryManagementView> {
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆管理'),
        actions: [
          IconButton(
            tooltip: '提出人设演化',
            icon: controller.proposing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            // proposing 期间禁用（防重复触发重复消费 LLM）。
            onPressed: controller.proposing
                ? null
                : controller.proposeEvolution,
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
          Expanded(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : _MemoryList(controller: controller),
          ),
        ],
      ),
    );
  }
}

/// 记忆内容列表：条目 + 演化历史。
class _MemoryList extends StatelessWidget {
  const _MemoryList({required this.controller});

  final MemoryManagementController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.entries;
    final revisions = controller.revisions;

    if (entries.isEmpty && revisions.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyState(
            icon: Icons.psychology_outlined,
            message: '暂无记忆',
            hint: '与角色对话中，AI 会自动记录人格事实与情景记忆',
          ),
          const SizedBox(height: ConverSpacing.space3),
          _AddEntryButton(onPressed: () => _showAddDialog(context)),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: ConverSpacing.space6),
      children: [
        // 无记忆条目但存在演化历史：入口仍需可见（F-121 语义完整）。
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space1,
              ConverSpacing.space4,
              ConverSpacing.space2,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _AddEntryButton(onPressed: () => _showAddDialog(context)),
            ),
          ),
        if (entries.isNotEmpty) ...[
          _SectionHeader(
            title: '记忆条目',
            action: IconButton(
              tooltip: '新增记忆',
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => _showAddDialog(context),
            ),
          ),
          for (final entry in entries)
            _EntryTile(
              entry: entry,
              onEdit: () => _showEditDialog(context, entry),
              onDelete: () => _confirmDelete(context, entry),
            ),
        ],
        if (revisions.isNotEmpty) ...[
          const _SectionHeader(title: '人设演化历史'),
          for (final revision in revisions)
            _RevisionTile(
              revision: revision,
              applied: controller.appliedRevisionIds.contains(revision.id),
              onApply: () => controller.applyRevision(revision.id),
              onDiscard: () => controller.discardRevision(revision.id),
            ),
        ],
        // 标题说明色来自 palette（无 header 时不影响）。
        const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final kind = await _pickKind(context);
    if (kind == null || !context.mounted) {
      return;
    }
    final content = await _promptContent(context, title: '新增记忆', initial: '');
    if (content != null && content.isNotEmpty) {
      await controller.createEntry(kind, content);
    }
  }

  Future<void> _showEditDialog(BuildContext context, MemoryEntry entry) async {
    final content = await _promptContent(
      context,
      title: '编辑记忆',
      initial: entry.content,
    );
    if (content != null && content.isNotEmpty) {
      await controller.updateEntry(entry.id, content: content);
    }
  }

  Future<void> _confirmDelete(BuildContext context, MemoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记忆'),
        content: Text('删除记忆条目「${entry.content}」？此操作不可撤销。'),
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
      await controller.deleteEntry(entry.id);
    }
  }
}

/// 选择记忆类型。
Future<MemoryKind?> _pickKind(BuildContext context) async {
  return showDialog<MemoryKind>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('选择记忆类型'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(MemoryKind.personaFact),
          child: const Text('人格事实'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(MemoryKind.episodic),
          child: const Text('情景记忆'),
        ),
      ],
    ),
  );
}

/// 弹出内容输入框。
Future<String?> _promptContent(
  BuildContext context, {
  required String title,
  required String initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(title: title, initial: initial),
  );
}

/// 内容输入对话框。
///
/// controller 生命周期由 State 持有并在 [dispose] 释放——State.dispose 在
/// 路由退场动画结束、widget 真正 unmount 时触发，避免在动画期间访问已
/// dispose 的 controller（widget 测试实证的既有缺陷修复）。
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(hintText: '输入记忆内容'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 「新增记忆」入口按钮（F-121）。
///
/// 空态（无条目无版本）与边界态（无条目有演化历史）使用；非空态沿用
/// section header 的 IconButton action，不重复渲染本按钮。
class _AddEntryButton extends StatelessWidget {
  const _AddEntryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('新增记忆'),
    );
  }
}

/// 记忆类型标签文案。
String _kindLabel(MemoryKind kind) =>
    kind == MemoryKind.personaFact ? '人格事实' : '情景记忆';

/// section 标题（+ 可选操作）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        ConverSpacing.space4,
        ConverSpacing.space4,
        ConverSpacing.space2,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: palette.ink1),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// 单条记忆条目。
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final MemoryEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ConverSpacing.space2,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(ConverRadii.xs),
        ),
        child: Text(
          _kindLabel(entry.kind),
          style: textTheme.labelSmall?.copyWith(color: palette.ink3),
        ),
      ),
      title: Text(entry.content, style: textTheme.bodyMedium),
      subtitle: Text(
        '重要性 ${entry.importance}',
        style: textTheme.labelSmall?.copyWith(color: palette.ink4),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '编辑',
            icon: Icon(Icons.edit_outlined, size: 18, color: palette.ink3),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: '删除',
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 单条人设演化历史。
///
/// [applied] = 快照 == 当前人格（Q7 启发式，controller 判定）：已应用只读；
/// 未应用（待确认）显示「应用」「拒绝」内联操作。
class _RevisionTile extends StatelessWidget {
  const _RevisionTile({
    required this.revision,
    required this.applied,
    required this.onApply,
    required this.onDiscard,
  });

  final PersonaRevision revision;
  final bool applied;
  final VoidCallback onApply;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final snapshot = revision.personalitySnapshot.trim();
    final preview = snapshot.length > 80
        ? '${snapshot.substring(0, 80)}…'
        : snapshot;
    return ListTile(
      leading: Icon(Icons.history, color: palette.ink3),
      title: Text(
        revision.reason.isEmpty ? '人设演化' : revision.reason,
        style: textTheme.bodyMedium,
      ),
      subtitle: Text(
        preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.labelSmall?.copyWith(color: palette.ink4),
      ),
      trailing: applied
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: onApply, child: const Text('应用')),
                TextButton(onPressed: onDiscard, child: const Text('拒绝')),
              ],
            ),
    );
  }
}
