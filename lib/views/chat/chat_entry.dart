/// 聊天首页完整入口（U-1 工单 01：角色选择条 + 会话管理列表 + 最近对话）。
///
/// 界面语义（spec U-1 + 工单 01 验收标准 7 条）：
/// - 标题「聊天」（无「临时」标注、无「后续里程碑替换」副标题文案）；
/// - 角色选择条：横向滑动渲染全部角色名，选中高亮，tap 调
///   [ChatController.selectCharacter]；
/// - 「新建对话」以 [ChatController.selectedCharacterId] 为底，先弹选择面板
///   （开场白 + 预设对话，NPD-03）再创建并直达；无角色 → 禁用 + 提示
///   「请先在角色页创建角色」；创建中防连点；
/// - 会话列表项长按弹出「重命名 / 删除」：重命名经预填标题对话框委托
///   [ChatController.renameConversation]；删除经确认对话框委托
///   [ChatController.removeConversation]；
/// - 最近对话列表：标题 + 消息数，tap 进会话。
///
/// 层级：纯呈现 widget，回合 / 列表状态全部由 [ChatController] 持有，
/// 本层只做「读状态 + 触发动作」（不触碰数据层 / 平台存储）。
library;

import 'package:flutter/material.dart';

import '../../data/database/app_database.dart'
    show Character, Conversation;
import '../../theme/colors.dart'
    show ConverRadii, ConverSpacing;
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
              onPressed: canCreate ? () => _openNewConversationSheet(context) : null,
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

  /// 打开「新建对话」选择面板（NPD-03）：开场白 + 预设对话二选后确认建会话。
  ///
  /// 以 [ChatController.selectedCharacterId] 定位角色并从控制器已加载角色列表
  /// 取角色数据（firstMes / alternateGreetings / presetDialogues 供给下拉）；
  /// 面板确认回调 [ChatController.createConversationFor]（greeting/presetDialogue
  /// 三态透传）。选中态角色已从列表消失（陈旧缓存）→ 直接走既有 notice 路径
  /// （controller 内部 guard，零残留会话）。
  Future<void> _openNewConversationSheet(BuildContext context) async {
    final characterId = controller.selectedCharacterId;
    if (characterId == null) {
      return;
    }
    Character? selected;
    for (final character in controller.characters) {
      if (character.id == characterId) {
        selected = character;
        break;
      }
    }
    if (selected == null) {
      await controller.createConversationFor(characterId);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _NewConversationSheet(
        controller: controller,
        character: selected!,
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
///
/// BR-02 分支来源标记：parent 引用存活的会话在消息数下行追加
/// 「分支自「父标题」· 锚消息预览」；父会话已删（BR-01 删源置空策略——
/// parent/锚置空、branch_title 保留）降级显示「分支（来源会话已删除）」；
/// 普通会话无标记。
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
        final conversation = item.conversation;
        return ListTile(
          onTap: () => controller.openConversation(item.conversation.id),
          onLongPress: () => _showItemMenu(context, item.conversation),
          title: Text(
            item.conversation.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyLarge?.copyWith(color: palette.ink2),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${item.messageCount} 条消息',
                style: textTheme.bodySmall?.copyWith(color: palette.ink4),
              ),
              if (_branchMark(controller, conversation) case final mark?)
                Padding(
                  padding: const EdgeInsets.only(top: ConverSpacing.space1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.call_split,
                        size: 12,
                        color: palette.ink4,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          mark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.ink4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: ConverPalette.of(context).ink4,
          ),
        );
      },
    );
  }

  /// 分支来源标记文案（BR-02 验收 3 语义）：
  /// - parent 存活 → 「分支自「父标题」· 锚消息预览」（父/锚缺失降级空预览）；
  /// - parent 已删（置空策略）→ 按保留的 [Conversation.branchTitle] 降级
  ///   「分支（来源会话已删除）」；
  /// - 普通会话 → null（不显示标记）。
  String? _branchMark(ChatController controller, Conversation conversation) {
    if (conversation.parentConversationId != null) {
      final source = controller.branchSources[conversation.id];
      return '分支自「${source?.parentTitle ?? ''}」· ${source?.anchorPreview ?? ''}';
    }
    if (conversation.branchTitle != null) {
      return '分支（来源会话已删除）';
    }
    return null;
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

/// 开场白下拉选项（NPD-03）：label 为展示文本，value 为传入 greeting 的参数值。
///
/// value 语义（三态）：null = 默认（first_mes 零回归路径）、非空字符串 = 指定
/// 文本（模板替换后预插）、空串 = 无开场白（不预插）。由 [ChatController
/// .createConversationFor] 透传落库。
class _GreetingOption {
  const _GreetingOption(this.label, this.greeting);

  final String label;

  /// greeting 参数值：null / 指定文本 / 空串三态。
  final Object? greeting;
}

/// 预设对话下拉选项（NPD-03）：label 为预设名，content 为快照文本。
///
/// [content] 为 null 表示「不使用预设」（快照列不落伪值）；非空为选中预设的
/// content 原文（创建时固化快照）。
class _PresetOption {
  const _PresetOption(this.label, this.content);

  final String label;
  final String? content;
}

/// 「新建对话」选择面板（NPD-03 验收 4）：开场白下拉（默认/备选/无）+ 预设
/// 对话下拉（不使用/各预设）→ 「开始对话」经 [ChatController.createConversationFor]
/// 三态透传建会话并直达。
///
/// 契约锁（docstring 锚桌面 conversation.py::create_conversation 的 greeting /
/// preset_dialogue 语义）：
/// - 开场白「默认」→ greeting: null（first_mes 零回归）；备选文本 → greeting:
///   该文本（模板替换后）；「无开场白」→ greeting: 空串；
/// - 预设「不使用」→ presetDialogue: null；选中预设 → content 原样快照固化。
///
/// 角色数据（firstMes / alternateGreetings / presetDialogues）来自入口已加载
/// 的 [Character] 行（controller.characters 快照）；角色在面板打开期间被删 →
/// 确认动作仍经 controller 既有 guard（notice 路径），本面板零额外逻辑。
class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet({
    required this.controller,
    required this.character,
  });

  final ChatController controller;
  final Character character;

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  late final List<_GreetingOption> _greetings = _buildGreetings();
  late final List<_PresetOption> _presets = _buildPresets();
  int _greetingIndex = 0;
  int _presetIndex = 0;

  /// 开场白选项：默认（first_mes，标「默认」+ 内容预览）+ alternateGreetings
  /// 各项（trim 非空过滤）+ 「无开场白」。首项 = 默认（零回归路径）。
  List<_GreetingOption> _buildGreetings() {
    final firstMes = widget.character.firstMes;
    return [
      _GreetingOption(
        firstMes.isEmpty ? '默认' : '默认（$firstMes）',
        null,
      ),
      for (final text in widget.character.alternateGreetings)
        if (text.trim().isNotEmpty) _GreetingOption(text, text),
      const _GreetingOption('无开场白', ''),
    ];
  }

  /// 预设对话选项：首项「不使用」（content null）+ 各预设 {name, content}
  /// （name trim 非空过滤；快照取 content 原文）。
  List<_PresetOption> _buildPresets() {
    return [
      const _PresetOption('不使用', null),
      for (final preset in widget.character.presetDialogues)
        if ((preset['name'] ?? '').trim().isNotEmpty)
          _PresetOption(preset['name']!, preset['content'] ?? ''),
    ];
  }

  /// 确认：pop 面板 → 经 createConversationFor 三态透传建会话并直达。
  ///
  /// 角色删除 / 不存在守卫由 controller 既有路径承载（验收 6），层面无重复
  /// 逻辑；防连点（[_creatingConversation]）同 controller 单一归属。
  void _start() {
    Navigator.of(context).pop();
    widget.controller.createConversationFor(
      widget.character.id,
      greeting: _greetings[_greetingIndex].greeting,
      presetDialogue: _presets[_presetIndex].content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return SafeArea(
      child: Padding(
        key: const Key('new-conversation-sheet'),
        padding: const EdgeInsets.fromLTRB(
          ConverSpacing.space4,
          ConverSpacing.space3,
          ConverSpacing.space4,
          ConverSpacing.space4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '新建对话',
              style: textTheme.titleMedium?.copyWith(color: palette.ink1),
            ),
            const SizedBox(height: ConverSpacing.space2),
            Text('开场白', style: textTheme.bodySmall?.copyWith(color: palette.ink3)),
            DropdownButton<int>(
              key: const Key('greeting-select'),
              value: _greetingIndex,
              isExpanded: true,
              items: [
                for (var i = 0; i < _greetings.length; i++)
                  DropdownMenuItem<int>(
                    value: i,
                    child: Text(
                      _greetings[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (index) {
                if (index != null) {
                  setState(() => _greetingIndex = index);
                }
              },
            ),
            const SizedBox(height: ConverSpacing.space2),
            Text('预设对话', style: textTheme.bodySmall?.copyWith(color: palette.ink3)),
            DropdownButton<int>(
              key: const Key('preset-select'),
              value: _presetIndex,
              isExpanded: true,
              items: [
                for (var i = 0; i < _presets.length; i++)
                  DropdownMenuItem<int>(
                    value: i,
                    child: Text(
                      _presets[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (index) {
                if (index != null) {
                  setState(() => _presetIndex = index);
                }
              },
            ),
            const SizedBox(height: ConverSpacing.space3),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('start-conversation'),
                onPressed: _start,
                child: const Text('开始对话'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
