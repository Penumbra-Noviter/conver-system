/// 最小临时会话入口（M2 版，M3 由完整角色选择 / 会话管理替换）。
///
/// 界面语义（spec ID-2 + best-judgment ② 细化）：
/// - 标题「聊天」+「临时」标注（明确当前为临时入口）；
/// - 「新建对话」按钮：取首个角色建会话并进入；无角色 → 禁用 + 提示
///   「请先在角色页创建角色」；创建中防连点；
/// - 最近对话列表：`listConversations` 结果（标题 + 消息数），tap 进入会话。
///
/// 层级：纯呈现 widget，回合 / 列表状态全部由 [ChatController] 持有，
/// 本层只做「读状态 + 触发动作」（不触碰数据层 / 平台存储）。
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import 'chat_controller.dart';

/// 最近对话列表 + 新建的临时入口页。
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
            child: Row(
              children: [
                Text(
                  '聊天',
                  style: textTheme.titleLarge?.copyWith(color: palette.ink1),
                ),
                const SizedBox(width: ConverSpacing.space2),
                const _TemporaryBadge(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space1,
              ConverSpacing.space4,
              0,
            ),
            child: Text(
              '最近对话 · 临时入口（后续里程碑替换为角色选择与会话管理）',
              style: textTheme.bodySmall?.copyWith(color: palette.ink4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space4,
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

/// 「临时」标注 chip：克制 1px 边框 + ink3 小字（M3 移除）。
class _TemporaryBadge extends StatelessWidget {
  const _TemporaryBadge();

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(ConverRadii.xs),
      ),
      child: Text(
        '临时',
        style: textTheme.labelSmall?.copyWith(color: palette.ink3),
      ),
    );
  }
}

/// 最近对话列表（`listConversations`，updated_at 倒序）+ 空态。
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: ConverPalette.of(context).ink4,
            ),
            const SizedBox(height: ConverSpacing.space2),
            Text(
              '还没有对话',
              style: textTheme.bodyMedium?.copyWith(color: palette.ink3),
            ),
            const SizedBox(height: ConverSpacing.space1),
            Text(
              '点「新建对话」开始第一段聊天',
              style: textTheme.bodySmall?.copyWith(color: palette.ink4),
            ),
          ],
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
}