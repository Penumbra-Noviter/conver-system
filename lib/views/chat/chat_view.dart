/// 聊天 tab 真实 UI（M2 版：入口 + 对话面板，打字机）。
///
/// 语义锚点（桌面，逐字对齐）：
/// - `desktop/frontend/js/stream-session.js`：onToken 打字机逐 token 增量渲染
///   + streamSettled 终态守卫——运动状态收敛于 [ChatController]，本层只呈现；
/// - `desktop/frontend/js/chat.js`：发送 ↔ 停止两态由 [ChatController.isStreaming]
///   派生、重生成仅末条已结算 assistant、错误/断流为非阻塞提示。
///
/// 两级降频（R4 定案，spec §Implementation Decisions 5）：已完成消息静态
/// [MarkdownBody]（warm_markdown_style 深浅两套）；streaming 占位气泡为**纯
/// 文本**逐 token 拼接 + 单点闪烁光标（[Text] `▍`，非三点 typing），完成 /
/// 停止 / 断流落库后经事件链一次切回 DB 权威列表。
///
/// 层级：呈现层。经 [ChatController]（装配于 home_shell / app provider 图）
/// 注入，不触碰数据层 / 平台存储（layer_boundary_test 契约）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../data/database/tables.dart' show Role;
import '../../theme/chat_markdown_style.dart'
    show warmStoneMarkdownDark, warmStoneMarkdownLight;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../theme/motion.dart' show ConverDurations;
import '../../widgets/notice_banner.dart';
import 'chat_controller.dart';
import 'chat_entry.dart';
import 'conversation_sampling_sheet.dart';

/// 聊天 tab：入口（最近对话 + 新建）与对话面板之间按
/// [ChatController.isEntry] 切换。
class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.controller});

  /// 回合 / 入口状态持有者（装配注入，单一事实来源）。
  final ChatController controller;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // 首次挂载幂等触发 loadEntry；推迟到本帧 build 之后（initState 期间同步
    // notifyListeners 会命中「markNeedsBuild during build」）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureEntryLoaded();
      }
    });
  }

  void _onControllerChanged() => setState(() {});

  /// 首次挂载幂等触发 [ChatController.loadEntry]（入口导航每次回来也刷新）。
  ///
  /// 防挂兜底在控制器内（各步查询 3s 超时复位 loading 态）；此处仅透传异常
  /// 日志，保持缺省空列表（对齐设置页回显模式）。
  Future<void> _ensureEntryLoaded() async {
    final controller = widget.controller;
    if (controller.hasLoadedEntry) {
      return;
    }
    try {
      await controller.loadEntry();
    } catch (error) {
      debugPrint('聊天入口加载失败，保持缺省空列表: $error');
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.isEntry
        ? ChatEntry(controller: widget.controller)
        : _ConversationView(controller: widget.controller);
  }
}

/// 对话面板：顶栏（返回 + 标题）+ 断流/错误提示条 + 消息列表 + 输入栏。
class _ConversationView extends StatelessWidget {
  const _ConversationView({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _ConversationHeader(controller: controller),
          // W5 B1：NoticeBanner 始终渲染（notice 可空），进出过渡 140ms 由
          // 组件自身 AnimatedOpacity 管理——dismiss 后播放出口 Fade，过渡
          // 完成才回调 dismissNotice（提示条不硬切卸载）。
          NoticeBanner(
            notice: controller.notice,
            // F-65④：notice 身份 seq 随文案同步传递（同文案新旧 notice 经
            // 身份区分，陈旧出口 dismiss 不误清新 notice）。
            noticeId: controller.noticeId,
            onDismiss: controller.dismissNotice,
            // T3 流式级可操作提示（M6-08）：仅「回复已中断」且存在可重试截断
            // 目标时传入「重试」动作；其它 notice 零动作（关闭-only）。
            actionLabel: controller.hasRetryableInterrupted ? '重试' : null,
            onAction: controller.hasRetryableInterrupted
                ? controller.retryInterrupted
                : null,
          ),
          Expanded(child: _MessageList(controller: controller)),
          _Composer(controller: controller),
        ],
      ),
    );
  }
}

/// 对话顶栏导出动作（menu 值表）。
enum _ConversationExportAction { json, markdown }

/// 对话顶栏：返回（回入口刷新最近列表）+ 会话标题 + 导出菜单（⋯）。
///
/// M4-03 导出入口：`PopupMenuButton` 两项「导出 JSON」/「导出 Markdown」
/// （spec A1 逐字；菜单仅在对话态渲染——入口页由 [ChatView] 分发给
/// `ChatEntry`，本组件不出现）。导出进行中（[ChatController.exporting]）
/// 按钮禁用防连点（控制器层另有防连点守卫双保险）。
class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: controller.backToEntry,
        ),
        Expanded(
          child: Text(
            controller.activeConversation?.title ?? '聊天',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(color: palette.ink1),
          ),
        ),
        IconButton(
          tooltip: '对话设置',
          key: const Key('conversation-settings-button'),
          icon: const Icon(Icons.tune),
          onPressed: () => _openConversationSamplingSettings(context, controller),
        ),
        PopupMenuButton<_ConversationExportAction>(
          tooltip: '导出对话',
          enabled: !controller.exporting,
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            switch (action) {
              case _ConversationExportAction.json:
                controller.exportJson();
              case _ConversationExportAction.markdown:
                controller.exportMarkdown();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _ConversationExportAction.json,
              child: Text('导出 JSON'),
            ),
            PopupMenuItem(
              value: _ConversationExportAction.markdown,
              child: Text('导出 Markdown'),
            ),
          ],
        ),
        const SizedBox(width: ConverSpacing.space2),
      ],
    );
  }
}

/// 会话消息列表（DB 权威 + 在途合成占位），逐消息渲染角色气泡。
///
/// M3-04c 跳转定位高亮：消息气泡挂 `GlobalObjectKey('msg-<id>')`（DB 正 id；
/// 流式合成负 id 天然不冲突），目标经 [Scrollable.ensureVisible]（alignment
/// 0.5 居中）定位；目标不存在回落滚动到底（对齐桌面 `locateAndHighlight`）。
///
/// 生命周期：持有 ScrollController（回落滚底）与气泡 key 集合，监听控制器
/// 的高亮请求序号变化调度定位；视图侧 3s 高亮清除 timer（desktop chat.js
/// highlightTimer 语义）经 [ChatController.clearHighlight] 收口，dispose 取消。
class _MessageList extends StatefulWidget {
  const _MessageList({required this.controller});

  final ChatController controller;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  /// ListView 滚动控制器（回落滚底 / 未挂树时估位跳近用）。
  final ScrollController _scrollController = ScrollController();

  /// 气泡 GlobalObjectKey 持有容器：同一 id 复用**同一实例**作 widget key 与
  /// `currentContext` 查找（GlobalObjectKey 按 `identical(value)` 判等，运行时
  /// 插值字符串不 canonical，重建 key 将查不到已挂载 context）。
  final Map<int, GlobalObjectKey> _messageKeys = <int, GlobalObjectKey>{};

  /// 已处理的高亮请求序号（防同请求重复定位滚动）。
  int? _lastHandledSeq;

  /// 当前归属会话 id（切换会话时清理气泡 key 集合，防跨会话串键）。
  int _lastConversationId = -1;

  /// 平均条目估高（px）：目标气泡未挂树（长列表懒构建）时估位跳近的粗估，
  /// 跳近后下一帧经 ensureVisible 精确居中（不引入 ScrollablePositionedList）。
  static const double _estimatedItemExtent = 88.0;

  /// 估位跳近重试上限（防御异常数据；正常 1-2 帧收敛）。
  static const int _maxScrollAttempts = 6;

  GlobalObjectKey _keyFor(int messageId) => _messageKeys.putIfAbsent(
    messageId,
    () => GlobalObjectKey('msg-$messageId'),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // 首次挂载时高亮可能已就绪（openConversation 在装配前完成）：帧后检查。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeHandleHighlight(),
    );
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeHandleHighlight(),
    );
  }

  /// 按高亮请求序号处理定位：切换会话清 key 集合；新请求 → 视图侧 3s 清除
  /// timer + 帧后 ensureVisible；无高亮集合时清空本地状态。
  void _maybeHandleHighlight() {
    if (!mounted) {
      return;
    }
    final controller = widget.controller;
    final conversationId = controller.activeConversationId;
    if (conversationId != _lastConversationId) {
      _lastConversationId = conversationId ?? -1;
      _messageKeys.clear();
    }
    final targets = controller.highlightMessageIds;
    if (targets.isEmpty) {
      _lastHandledSeq = null;
      return;
    }
    final seq = controller.highlightRequestSeq;
    if (seq == _lastHandledSeq) {
      return;
    }
    _lastHandledSeq = seq;
    final targetId = targets.single;
    // F-127：3s 自动清除由控制器 [_applyHighlight] 定时器单一归属（notify →
    // 本监听刷新）；视图不再自持 timer。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureTargetVisible(targetId),
    );
  }

  /// 定位 [targetId] 气泡到视口中部（alignment 0.5 居中）。
  ///
  /// - 目标已挂树（GlobalObjectKey currentContext 可用）→ ensureVisible 居中；
  /// - 目标在列表但未挂树（懒构建/深位）→ 按 index 估位跳近后下一帧精确定位
  ///   （有界重试）；
  /// - 目标不在已加载列表（删除/未加载）→ 回落滚动到底（桌面语义，不出错）。
  void _ensureTargetVisible(int targetId, {int attempt = 0}) {
    if (!mounted) {
      return;
    }
    final bubbleContext = _messageKeys[targetId]?.currentContext;
    if (bubbleContext != null) {
      Scrollable.ensureVisible(bubbleContext, alignment: 0.5);
      return;
    }
    final messages = widget.controller.messages;
    final index = messages.indexWhere((m) => m.id == targetId);
    if (index < 0) {
      _scrollToBottom();
      return;
    }
    if (attempt >= _maxScrollAttempts || !_scrollController.hasClients) {
      return; // 防御：目标可达但异常（测试环境不挂起）；下轮高亮请求会重试。
    }
    final position = _scrollController.position;
    final targetOffset = (index * _estimatedItemExtent).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((targetOffset - position.pixels).abs() > 1.0) {
      position.jumpTo(targetOffset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTargetVisible(targetId, attempt: attempt + 1);
    });
  }

  /// 回落滚动到底（目标不存在 / 未加载）。
  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    position.jumpTo(position.maxScrollExtent);
    // 懒构建列表：首跳可能基于未布局区段的估算 extent（MS-05 操作按钮使
    // 12 条消息列表越过 cacheExtent 边界后实证），次帧补跳至修正后的真实底部。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final p = _scrollController.position;
      if (p.pixels != p.maxScrollExtent) {
        p.jumpTo(p.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    // F-127：高亮 3s 清除 timer 已单一归属控制器，视图无需取消。
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.messages;
    // 语义 label 前缀（assistant / system 气泡「角色名: 内容」）；会话缺失 /
    // 角色解析失败回退占位词（装饰性语义面，不抛错）。
    final roleName = widget.controller.activeCharacterName?.trim() ?? '角色';
    final roleLabel = roleName.isEmpty ? '角色' : roleName;
    if (messages.isEmpty) {
      final palette = ConverPalette.of(context);
      final textTheme = Theme.of(context).textTheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '还没有消息',
              style: textTheme.bodyMedium?.copyWith(color: palette.ink3),
            ),
            const SizedBox(height: ConverSpacing.space1),
            Text(
              '发送第一条消息开始对话',
              style: textTheme.bodySmall?.copyWith(color: palette.ink4),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space4,
        vertical: ConverSpacing.space3,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        // 高亮命中：controller 集合按 DB 正 id 判定（合成负 id 永不命中）。
        final highlighted = widget.controller.highlightMessageIds.contains(
          message.id,
        );
        final isLast = index == messages.length - 1;
        // 消息操作入口可达性（MS-05 验收 5）：生成中 / 重生成中 / 终态重载窗口 /
        // 瞬时变更进行中（isBusy 聚合）或行未落库（合成负 id）/ 流式占位 →
        // 入口不可达（按钮禁用）。
        final showActions = message.id > 0;
        final actionsEnabled =
            showActions && !widget.controller.isBusy && !message.streaming;
        return Padding(
          key: _keyFor(message.id),
          padding: const EdgeInsets.symmetric(vertical: ConverSpacing.space2),
          child: switch (message.role) {
            Role.user => _UserBubble(
              controller: widget.controller,
              message: message,
              isLast: isLast,
              showActions: showActions,
              actionsEnabled: actionsEnabled,
              highlighted: highlighted,
            ),
            Role.assistant => _AssistantBubble(
              controller: widget.controller,
              roleName: roleLabel,
              message: message,
              isLast: isLast,
              showActions: showActions,
              actionsEnabled: actionsEnabled,
              highlighted: highlighted,
            ),
            Role.system => _SystemBubble(
              roleName: roleLabel,
              content: message.content,
              highlighted: highlighted,
            ),
          },
        );
      },
    );
  }
}

/// user 消息气泡：右对齐 + 面板层底色（M3-04c 高亮时为琥珀 wash 底）+
/// 内联「消息操作」入口（MS-05：编辑 / 删除；与文本同行，不额外增加条目高度）。
class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.controller,
    required this.message,
    required this.isLast,
    required this.showActions,
    required this.actionsEnabled,
    this.highlighted = false,
  });

  final ChatController controller;

  final ChatUiMessage message;

  /// 是否末条消息（消息操作菜单项裁剪依据）。
  final bool isLast;

  /// 是否渲染操作入口（仅已落库消息；在途合成负 id 不渲染）。
  final bool showActions;

  /// 操作入口是否可点（生成中 / 终态重载窗口 / 流式占位 → false）。
  final bool actionsEnabled;

  /// 跳转定位高亮命中（琥珀 wash 底色，对齐桌面 `search-highlight`）。
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: ConverSpacing.space8),
        padding: const EdgeInsets.symmetric(
          horizontal: ConverSpacing.space3,
          vertical: ConverSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: highlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.13)
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(ConverRadii.bubble),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // MergeSemantics 只包内容（label「你: 内容」整体朗读，spec §4.4
            // 覆盖清单 ①）——操作按钮保持独立语义节点（不被内容 label 吞掉）。
            Flexible(
              child: MergeSemantics(
                child: Semantics(
                  label: '你: ${message.content}',
                  excludeSemantics: true,
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: palette.ink1,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (showActions) ...[
              const SizedBox(width: ConverSpacing.space1),
              _MessageActionsButton(
                controller: controller,
                message: message,
                isLast: isLast,
                enabled: actionsEnabled,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 消息操作入口按钮（⋯）：打开消息操作菜单。
///
/// 形态决策（工单 05 高不确定点，best judgment）：气泡内显式菜单按钮而非长按
/// ——assistant 气泡内容为可选中 Markdown（`MarkdownBody(selectable: true)`），
/// 长按被文本选择优先消费，长按入口在两类气泡上行为不一致；显式按钮触屏可
/// 发现、a11y 语义可达（[Semantics] label「消息操作」），契约锁只锁行为不锁
/// 形态。菜单项按角色与位置裁剪：末条 assistant 有「继续生成」，user 有
/// 「编辑」，两者均有「删除」。
///
/// 生成中 / 终态重载窗口 / 瞬时变更进行中时禁用（[enabled] false → onPressed
/// null）；流式占位与在途合成消息由调用方以 [show] 判据不渲染。
class _MessageActionsButton extends StatelessWidget {
  const _MessageActionsButton({
    required this.controller,
    required this.message,
    required this.isLast,
    required this.enabled,
    this.compact = false,
  });

  final ChatController controller;
  final ChatUiMessage message;
  final bool isLast;
  final bool enabled;

  /// 紧凑形态（user 气泡内联：与文本同行，不额外增加条目高度）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    // 尺寸守在既有气泡底部图标行高度之下（user 气泡内联 22 / assistant 与
    // 重生成图标同行 24）：新增入口不改变条目高度，既有滚动/定位契约零回归。
    final size = compact ? 22.0 : 24.0;
    final iconSize = compact ? 14.0 : 16.0;
    return Align(
      alignment: Alignment.centerLeft,
      // widthFactor 贴合按钮宽：在 assistant 底部 Row 中不吞掉整行剩余宽度，
      // 在 user 气泡内联 Row 中同样只占按钮宽。
      widthFactor: 1,
      child: Semantics(
        label: '消息操作',
        button: true,
        // container: 强制独立语义节点——无 container 时本配置合并进兄弟/祖先
        // 语义节点，实测会吞掉同气泡「回复中断」小标 label（F-66 语义断言
        // 先红后绿实证）；container 后按钮节点与内容/小标互不干扰。
        container: true,
        child: IconButton(
          key: Key('message-actions-${message.id}'),
          visualDensity: VisualDensity.compact,
          iconSize: iconSize,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          icon: Icon(
            Icons.more_horiz,
            color: enabled ? palette.ink3 : palette.ink4,
          ),
          onPressed: enabled ? () => unawaited(_openMenu(context)) : null,
        ),
      ),
    );
  }

  /// 打开操作菜单（[showMenu] 定位到按钮下方；与既有导出菜单同族的 popup
  /// route）。菜单关闭后让出一帧再开后续对话框：popup route 退场动画期间直接
  /// push 对话框会与其 FocusScope 收尾竞争（framework `_dependents.isEmpty`
  /// 断言，widget 测试实证）。
  Future<void> _openMenu(BuildContext context) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = context.findRenderObject() as RenderBox;
    final action = await showMenu<_MessageAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        if (message.role == Role.assistant && isLast)
          const PopupMenuItem(
            value: _MessageAction.continueReply,
            child: Text('继续生成'),
          ),
        if (message.role == Role.user)
          const PopupMenuItem(
            value: _MessageAction.edit,
            child: Text('编辑'),
          ),
        const PopupMenuItem(
          value: _MessageAction.delete,
          child: Text('删除'),
        ),
      ],
    );
    await Future<void>.microtask(() {});
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case _MessageAction.continueReply:
        await controller.continueReply();
      case _MessageAction.edit:
        await _promptEditMessage(context, controller, message);
      case _MessageAction.delete:
        await _confirmDeleteMessage(context, controller, message);
      case null:
        return;
    }
  }
}

/// assistant 气泡：已完成消息静态 Markdown（两级降频完成侧）；streaming 占位
/// 纯文本 + 单点闪烁光标；底部常驻重生成小图标（仅末条已结算可点）+
/// 候选切换控制条（候选数 > 1，MS-05）+「消息操作」入口 + 主动停止「已停止」
/// 标记。
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.controller,
    required this.roleName,
    required this.message,
    required this.isLast,
    required this.showActions,
    required this.actionsEnabled,
    this.highlighted = false,
  });

  final ChatController controller;

  /// 当前会话角色名（语义 label「角色名: 内容」前缀）。
  final String roleName;

  final ChatUiMessage message;
  final bool isLast;

  /// 是否渲染操作入口（仅已落库消息；流式占位负 id 不渲染）。
  final bool showActions;

  /// 操作入口是否可点（生成中 / 终态重载窗口 → false）。
  final bool actionsEnabled;

  /// 跳转定位高亮命中（琥珀 wash 底色，对齐桌面 `search-highlight`）。
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final canRegenerate =
        !controller.isStreaming &&
        !controller.isRegenerating &&
        !message.streaming &&
        isLast;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: ConverSpacing.space8),
        padding: const EdgeInsets.symmetric(
          horizontal: ConverSpacing.space3,
          vertical: ConverSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: highlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.13)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          border: Border.all(
            color: highlighted
                ? Theme.of(context).colorScheme.primary
                : ConverPalette.of(context).border,
          ),
          borderRadius: BorderRadius.circular(ConverRadii.bubble),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 气泡内容 MergeSemantics + label「角色名: 内容」（spec §4.4 覆盖
            // 清单 ①：屏幕阅读器整体朗读；`▍` 光标在 streaming 分支内被
            // ExcludeSemantics 排除，不产生噪音）。
            MergeSemantics(
              child: Semantics(
                label: '$roleName: ${message.content}',
                excludeSemantics: true,
                child: message.streaming
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              message.content,
                              style: TextStyle(
                                color: palette.ink1,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const _BlinkingCursor(),
                        ],
                      )
                    : MarkdownBody(
                        data: message.content,
                        styleSheet: _markdownStyle(context),
                        selectable: true,
                      ),
              ),
            ),
            if (message.stopped)
              Padding(
                padding: const EdgeInsets.only(top: ConverSpacing.space1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.stop_circle_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '已停止',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            if (message.interrupted)
              // 断流截断「回复中断」小标（M6-08）：danger 色族，与「已停止」
              // 样式族并列但文案/图标区分；停止/断流为互斥终态，两标不会同时
              // 出现在同一消息。
              Padding(
                padding: const EdgeInsets.only(top: ConverSpacing.space1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '回复中断',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: ConverSpacing.space1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // MS-05 候选控制条：候选数 > 1 才渲染（单选 / 无候选不渲染，
                  // 对齐桌面 MS-2 契约锁）。
                  if (message.swipeCount > 1) ...[
                    _SwipeBar(controller: controller, message: message),
                    const SizedBox(width: ConverSpacing.space1),
                  ],
                  IconButton(
                    key: ValueKey('regenerate-${message.id}'),
                    tooltip: '重生成',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.refresh,
                      size: 18,
                      color: canRegenerate ? palette.ink3 : palette.ink4,
                    ),
                    onPressed: canRegenerate ? controller.regenerate : null,
                  ),
                  if (showActions)
                    _MessageActionsButton(
                      controller: controller,
                      message: message,
                      isLast: isLast,
                      enabled: actionsEnabled,
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

/// 候选切换控制条（MS-05）：`‹ N/M ›`。
///
/// 渲染判据 = 候选数 > 1（由调用方把关）。交互：点击箭头 → 乐观切换（立即按
/// 新 index 渲染）→ [ChatController.switchSwipe] 落库 → 收尾清乐观值；失败
/// （领域错误 / 守卫拒绝）时 DB 未变，清乐观值即天然回滚到权威 active，
/// 无需另存快照。边界箭头禁用（策略锁定为禁用：触屏无 hover 提示，禁用态是
/// 唯一可视线索；桌面为 clamp no-op）；生成中 / 重生成中 / 终态重载窗口 /
/// 瞬时变更进行中（[ChatController.isBusy]）时箭头禁用（验收 5 同族守卫）。
class _SwipeBar extends StatefulWidget {
  const _SwipeBar({required this.controller, required this.message});

  final ChatController controller;
  final ChatUiMessage message;

  @override
  State<_SwipeBar> createState() => _SwipeBarState();
}

class _SwipeBarState extends State<_SwipeBar> {
  /// 乐观激活 index（null = 以 DB 权威值为准）。切换 await 收尾后清空：成功
  /// 时 DB 已更新（reload 后 [ChatUiMessage.activeSwipeIndex] 即新值），失败时
  /// DB 未变——两种情况清空后显示的都是权威值。
  int? _optimisticIndex;

  int get _activeIndex => _optimisticIndex ?? widget.message.activeSwipeIndex;

  Future<void> _switch(int delta) async {
    final count = widget.message.swipeCount;
    final next = _activeIndex + delta;
    if (next < 0 || next >= count || widget.controller.isBusy) {
      return; // 边界 / 忙态：按钮已禁用，此处为防御性 no-op。
    }
    setState(() => _optimisticIndex = next);
    await widget.controller.switchSwipe(widget.message.id, next);
    if (!mounted) {
      return;
    }
    setState(() => _optimisticIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final count = widget.message.swipeCount;
    final active = _activeIndex;
    final enabled = !widget.controller.isBusy;
    return Container(
      key: Key('swipe-bar-${widget.message.id}'),
      padding: const EdgeInsets.symmetric(horizontal: ConverSpacing.space1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(ConverRadii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SwipeArrow(
            icon: Icons.chevron_left,
            label: '上一个候选',
            onPressed: enabled && active > 0 ? () => _switch(-1) : null,
          ),
          Semantics(
            // 屏幕阅读器朗读「候选 2/3」而非裸「2/3」（装饰性计数语义化）。
            label: '候选 ${active + 1}/$count',
            excludeSemantics: true,
            child: Text(
              '${active + 1}/$count',
              style: TextStyle(
                fontSize: 12,
                color: palette.ink2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _SwipeArrow(
            icon: Icons.chevron_right,
            label: '下一个候选',
            onPressed: enabled && active < count - 1 ? () => _switch(1) : null,
          ),
        ],
      ),
    );
  }
}

/// 候选控制条箭头（紧凑视觉密度 + [Semantics] label 语义；禁用态 = onPressed
/// null）。
///
/// 语义用 [Semantics] label 而非 `IconButton.tooltip`：tooltip 会在按钮外挂
/// `RawTooltip` 并注册全局 pointer 路由（列表项内大量 tooltip 触发 framework
/// `RawTooltipState ... multiple tickers` 断言，widget 测试实证）；label 提供
/// 同等屏幕阅读器可读性且零额外监听。
class _SwipeArrow extends StatelessWidget {
  const _SwipeArrow({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final disabled = onPressed == null;
    return Semantics(
      label: label,
      button: true,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(icon, color: disabled ? palette.ink4 : palette.ink2),
        onPressed: onPressed,
      ),
    );
  }
}

/// 消息操作菜单项值表（长按气泡 / 「消息操作」按钮同一菜单）。
enum _MessageAction {
  /// 继续生成末条 assistant（候选追加；空续写 no-op）。
  continueReply,

  /// 编辑 user 消息并重发。
  edit,

  /// 删除消息（user 截断后续 / assistant 单删）。
  delete,
}

/// 编辑消息对话框（预填原内容）→ 提交返回新内容（取消 → null）。
///
/// 输入控制器归属本对话框 State（[State.dispose] 时机 = 路由真正卸载后）——
/// 父方在 `showDialog` await 返回时控制器仍在退场动画中挂树，此时 dispose 会
/// 触发「TextEditingController was used after being disposed」（widget 测试
/// 实证；与 F-109 修复的 `_PromptDialog` 同类）。
class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialText});

  /// 预填的原消息内容。
  final String initialText;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _editor = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑消息'),
      content: TextField(
        key: const Key('edit-message-field'),
        controller: _editor,
        minLines: 1,
        maxLines: 6,
        decoration: const InputDecoration(hintText: '编辑消息内容…'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('edit-message-confirm'),
          onPressed: () => Navigator.of(context).pop(_editor.text.trim()),
          child: const Text('保存并重发'),
        ),
      ],
    );
  }
}

/// 编辑消息对话框（预填原内容）→ 提交经 [ChatController.editMessage]
/// （仅 user 消息；服务层强校验，非 user → 领域错误 notice）。取消 / 空内容 /
/// 内容未变 → 零副作用（不触发无意义的截断重生成）。
Future<void> _promptEditMessage(
  BuildContext context,
  ChatController controller,
  ChatUiMessage message,
) async {
  final newContent = await showDialog<String>(
    context: context,
    builder: (_) => _EditMessageDialog(initialText: message.content),
  );
  if (newContent == null || newContent.isEmpty || newContent == message.content) {
    return;
  }
  await controller.editMessage(message.id, newContent);
}

/// 删除消息确认对话框（按角色区分语义警示文案，逐字对齐桌面 showConfirm）：
/// 删 user 明示连带截断其后的全部对话；删 assistant 明示仅删该条回复及候选。
Future<void> _confirmDeleteMessage(
  BuildContext context,
  ChatController controller,
  ChatUiMessage message,
) async {
  final isUser = message.role == Role.user;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除消息'),
      content: Text(
        isUser
            ? '删除该用户消息将连带删除其后的所有对话，确定要删除吗？'
            : '仅删除该条回复及其候选，保留触发它的用户消息。确定要删除吗？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('confirm-delete-button'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return;
  }
  await controller.deleteMessage(message.id);
}

/// 打开「对话采样参数」弹层（SP-02）：以当前会话四列回显，保存经
/// [ChatController.saveConversationSampling] 落四列（三态：覆盖 → clamp 后
/// 数值 / 清除/沿用全局 → NULL）。会话缺失（入口仅对话态渲染，防御兜底）→
/// 零副作用；弹层取消 → 零副作用。
Future<void> _openConversationSamplingSettings(
  BuildContext context,
  ChatController controller,
) async {
  final conversation = controller.activeConversation;
  if (conversation == null) {
    return;
  }
  final result = await showModalBottomSheet<ConversationSamplingInput>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: ConversationSamplingSheet(
        initial: ConversationSamplingInput(
          topP: conversation.topP,
          presencePenalty: conversation.presencePenalty,
          frequencyPenalty: conversation.frequencyPenalty,
          maxTokens: conversation.maxTokens,
        ),
      ),
    ),
  );
  if (result == null) {
    return; // 取消：零副作用。
  }
  await controller.saveConversationSampling(
    topP: result.topP,
    presencePenalty: result.presencePenalty,
    frequencyPenalty: result.frequencyPenalty,
    maxTokens: result.maxTokens,
  );
}

/// system 角色（开场白元信息等）：居中弱化小字（M3-04c 高亮时琥珀 wash 底）。
class _SystemBubble extends StatelessWidget {
  const _SystemBubble({
    required this.roleName,
    required this.content,
    this.highlighted = false,
  });

  /// 当前会话角色名（语义 label「角色名: 内容」前缀）。
  final String roleName;

  final String content;

  /// 跳转定位高亮命中（琥珀 wash 底色，对齐桌面 `search-highlight`）。
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final text = Text(
      content,
      style: TextStyle(fontSize: 12.5, color: palette.ink4),
    );
    return MergeSemantics(
      child: Semantics(
        // 屏幕阅读器整体朗读：label「角色名: 内容」（spec §4.4 覆盖清单 ①）。
        label: '$roleName: $content',
        excludeSemantics: true,
        child: Align(
          alignment: Alignment.center,
          child: highlighted
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ConverSpacing.space3,
                    vertical: ConverSpacing.space1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(ConverRadii.sm),
                  ),
                  child: text,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ConverSpacing.space8,
                  ),
                  child: text,
                ),
        ),
      ),
    );
  }
}

/// 单点闪烁光标（打字机占位气泡尾部，`▍` 半宽竖线；非三点 typing）。
///
/// ExcludeSemantics：装饰光标不产生朗读噪音（spec §4.4 覆盖清单 ②）。
///
/// reduce-motion（spec §4.4 / 共识 4.5）：系统开启「减弱动效」
/// （[MediaQuery.disableAnimationsOf]）时停止循环闪烁——静态呈现完整不透明
/// ▍（保持占位宽度，列表布局不跳动）；常态 repeat(reverse) 闪烁行为不变。
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  /// 系统减弱动效：true 时停闪（静态 ▍）；didChangeDependencies 中随
  /// MediaQuery 同步（首次检测 / 运行时翻转均生效）。
  bool _reduceMotion = false;

  /// 是否已应用过动画状态（守卫：防**无关** didChangeDependencies 重跑
  /// else 分支导致光标闪断——repeat 会在当前 value 处重建循环，闪烁周期被
  /// 重置，产生肉眼可见的闪断）。与 Ticker 泄漏无关：repeat 内部先 stop()
  /// 收束上一 TickerFuture、stop() 幂等，SDK 层无兜底清理遗漏。
  /// 初始值 false → 首次 didChangeDependencies 必应用。
  bool _appliedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (!_appliedOnce || reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _appliedOnce = true;
      if (reduce) {
        _controller
          ..stop()
          ..value = 1.0; // 静态完全可见（不透明），占位宽度不变。
      } else {
        // 不重置 value（保持当前 opacity 连续性）：仅启动 repeat，从当前
        // value 继续循环。reduce→正常翻转瞬间不再出现 value=0.0 的暗帧。
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
        child: Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 3),
          child: Text(
            '▍',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// 输入栏：TextField + 发送 ↔ 停止两态按钮（生成中红色「停止」）。
class _Composer extends StatefulWidget {
  const _Composer({required this.controller});

  final ChatController controller;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String _) => setState(() {});

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty || widget.controller.isStreaming) {
      return;
    }
    _text.clear();
    setState(() {});
    unawaited(widget.controller.send(text));
  }

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final controller = widget.controller;
    final streaming = controller.isStreaming;
    final canSend = _text.text.trim().isNotEmpty && !streaming;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space3,
        ConverSpacing.space2,
        ConverSpacing.space2,
        ConverSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: ConverPalette.of(context).border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                onChanged: _onChanged,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '输入消息…',
                  hintStyle: TextStyle(fontSize: 15, color: palette.ink4),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ConverSpacing.space3,
                    vertical: ConverSpacing.space2,
                  ),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ConverRadii.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ConverRadii.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: ConverSpacing.space1),
            // M6-07 克制动效 ③：发送↔停止图标过渡 140ms（AnimatedSwitcher +
            // Fade；消费 ConverDurations.fast）。两个 Key 保留——既有测试
            // 按 Key 定位发送/停止按钮。
            AnimatedSwitcher(
              duration: ConverDurations.fast,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: streaming
                  ? IconButton(
                      key: const Key('stop-button'),
                      tooltip: '停止',
                      iconSize: 26,
                      icon: Icon(
                        Icons.stop,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: controller.stop,
                    )
                  : IconButton(
                      key: const Key('send-button'),
                      tooltip: '发送',
                      iconSize: 26,
                      icon: Icon(
                        Icons.send,
                        color: canSend
                            ? Theme.of(context).colorScheme.primary
                            : palette.ink4,
                      ),
                      onPressed: canSend ? _send : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 深浅两套 Warm Stone Markdown 样式的运行时选择（随主题 brightness）。
MarkdownStyleSheet _markdownStyle(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? warmStoneMarkdownDark() : warmStoneMarkdownLight();
}
