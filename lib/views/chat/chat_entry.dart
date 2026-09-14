/// 聊天首页完整入口（U-1 工单 01：角色选择条 + 会话管理列表 + 最近对话）。
///
/// 界面语义（spec U-1 + 工单 01 验收标准 7 条）：
/// - 标题「聊天」（无「临时」标注、无「后续里程碑替换」副标题文案）；
/// - 角色选择条：横向滑动渲染全部角色名，选中高亮，tap 调
///   [ChatController.selectCharacter]；
/// - 「新建对话」以 [ChatController.selectedCharacterId] 建会话并直达；无角色
///   → 禁用 + 提示「请先在角色页创建角色」；创建中防连点；
/// - 会话列表项长按弹出「重命名 / 删除」：重命名经预填标题对话框委托
///   [ChatController.renameConversation]；删除经确认对话框委托
///   [ChatController.removeConversation]；
/// - 最近对话列表：标题 + 消息数，tap 进会话。
///
/// 层级：纯呈现 widget，回合 / 列表状态全部由 [ChatController] 持有，
/// 本层只做「读状态 + 触发动作」（不触碰数据层 / 平台存储）。
library;

import 'package:flutter/material.dart';

import '../../data/database/app_database.dart' show Conversation;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../widgets/empty_state.dart';
import 'chat_controller.dart';

/// 角色选择条 + 最近对话列表 + 新建的完整入口页。
class ChatEntry extends StatelessWidget {
  const ChatEntry({super.key, required this.controller});

  /// 入口状态持有者（聊天 tab 装配注入）。
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final canCreate =
        controller.canCreateConversation && !controller.creatingConversation;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space5,
              ConverSpacing.space4,
              0,
            ),
            child: Text(
              '聊天',
              style: textTheme.titleLarge?.copyWith(color: palette.ink1),
            ),
          ),
          const SizedBox(height: ConverSpacing.space2),
          _CharacterSelector(controller: controller),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space3,
              ConverSpacing.space4,
              0,
            ),
            child: FilledButton.icon(
              key: const Key('new-conversation'),
              onPressed: canCreate ? controller.createConversation : null,
              icon: const Icon(Icons.add),
              label: const Text('新建对话'),
            ),
          ),
          if (!controller.canCreateConversation)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ConverSpacing.space4,
                ConverSpacing.space1,
                ConverSpacing.space4,
                0,
              ),
              child: Text(
                controller.createDisabledReason ?? '',
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: ConverSpacing.space4),
          Divider(
            thickness: 1,
            height: 1,
            color: ConverPalette.of(context).border,
          ),
          Expanded(child: _ConversationList(controller: controller)),
        ],
      ),
    );
  }
}

/// 角色选择条：横向滑动，选中高亮（amber 底 + 深字），tap 切换选中态。
class _CharacterSelector extends StatelessWidget {
  const _CharacterSelector({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final characters = controller.characters;
    if (characters.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ConverSpacing.space4),
        itemCount: characters.length,
        separatorBuilder: (_, _) => const SizedBox(width: ConverSpacing.space2),
        itemBuilder: (context, index) {
          final character = characters[index];
          final selected = controller.selectedCharacterId == character.id;
          return ChoiceChip(
            key: Key('character-chip-${character.id}'),
            label: Text(character.name),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => controller.selectCharacter(character.id),
            selectedColor: colorScheme.primary,
            backgroundColor: Colors.transparent,
            labelStyle: TextStyle(
              color: selected ? colorScheme.onPrimary : palette.ink3,
              fontSize: 13,
            ),
            side: BorderSide(
              color: selected ? colorScheme.primary : palette.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ConverRadii.lg),
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }
}

/// 会话列表项长按动作（「重命名 / 删除」底部菜单）。
enum _ConversationItemAction { rename, delete }

/// 最近对话列表（`listConversations`，updated_at 倒序）+ 空态 + 长按管理菜单。
class _ConversationList extends StatelessWidget {
  const _ConversationList({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final conversations = controller.conversations;
    if (conversations.isEmpty && !controller.loadingEntry) {
      return Center(
        child: EmptyState(
          icon: Icons.chat_bubble_outline,
          message: '还没有对话',
          hint: '点「新建对话」开始第一段聊天',
        ),
      );
    }
    if (controller.loadingEntry) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.separated(
      itemCount: conversations.length,
      separatorBuilder: (_, _) => Divider(
        thickness: 1,
        height: 1,
        indent: ConverSpacing.space4,
        endIndent: ConverSpacing.space4,
        color: ConverPalette.of(context).border,
      ),
      itemBuilder: (context, index) {
        final item = conversations[index];
        return ListTile(
          onTap: () => controller.openConversation(item.conversation.id),
          onLongPress: () => _showItemMenu(context, item.conversation),
          title: Text(
            item.conversation.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyLarge?.copyWith(color: palette.ink2),
          ),
          subtitle: Text(
            '${item.messageCount} 条消息',
            style: textTheme.bodySmall?.copyWith(color: palette.ink4),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: ConverPalette.of(context).ink4,
          ),
        );
      },
    );
  }

  /// 长按菜单：底部 sheet「重命名 / 删除」，按选择分发到对应对话框。
  Future<void> _showItemMenu(
    BuildContext context,
    Conversation conversation,
  ) async {
    final action = await showModalBottomSheet<_ConversationItemAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ConversationItemAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ConversationItemAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }
    switch (action) {
      case _ConversationItemAction.rename:
        await _renameConversation(context, conversation);
      case _ConversationItemAction.delete:
        await _confirmDeleteConversation(context, conversation);
    }
  }

  /// 重命名：预填当前标题的输入对话框，确认后委托 [ChatController.renameConversation]。
  Future<void> _renameConversation(
    BuildContext context,
    Conversation conversation,
  ) async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameConversationDialog(initialTitle: conversation.title),
    );
    if (newTitle == null) {
      return;
    }
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await controller.renameConversation(conversation.id, trimmed);
  }

  /// 删除：确认对话框，确认后委托 [ChatController.removeConversation]。
  Future<void> _confirmDeleteConversation(
    BuildContext context,
    Conversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除对话'),
        content: const Text('删除后对话与消息将一并移除，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeConversation(conversation.id);
    }
  }
}

/// 重命名对话框：预填 [initialTitle] 的输入框，确认返回新标题文本。
class _RenameConversationDialog extends StatefulWidget {
  const _RenameConversationDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名对话'),
      content: TextField(
        key: const Key('rename-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '对话标题'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('rename-confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
