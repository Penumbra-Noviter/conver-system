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
import '../../theme/chat_markdown_style.dart' show warmStoneMarkdownDark, warmStoneMarkdownLight;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import 'chat_controller.dart';
import 'chat_entry.dart';

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
          if (controller.notice != null)
            _NoticeBanner(
              notice: controller.notice!,
              onDismiss: controller.dismissNotice,
            ),
          Expanded(child: _MessageList(controller: controller)),
          _Composer(controller: controller),
        ],
      ),
    );
  }
}

/// 对话顶栏：返回（回入口刷新最近列表）+ 会话标题。
class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<ConverPalette>()!;
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
        const SizedBox(width: ConverSpacing.space2),
      ],
    );
  }
}

/// 非阻塞提示条（断流「回复已中断」/ 错误映射文案 / 基础设施失败）：
/// 可 [ChatController.dismissNotice]，不挡后续操作。
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice, required this.onDismiss});

  final String notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<ConverPalette>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ConverSpacing.space4,
          ConverSpacing.space1,
          ConverSpacing.space1,
          ConverSpacing.space1,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                notice,
                style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
              ),
            ),
            IconButton(
              tooltip: '关闭提示',
              icon: Icon(Icons.close, size: 18, color: palette.ink4),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// 会话消息列表（DB 权威 + 在途合成占位），逐消息渲染角色气泡。
class _MessageList extends StatelessWidget {
  const _MessageList({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final messages = controller.messages;
    if (messages.isEmpty) {
      final palette = Theme.of(context).extension<ConverPalette>()!;
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
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space4,
        vertical: ConverSpacing.space3,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: ConverSpacing.space2),
          child: switch (message.role) {
            Role.user => _UserBubble(content: message.content),
            Role.assistant => _AssistantBubble(
                controller: controller,
                message: message,
                isLast: index == messages.length - 1,
              ),
            Role.system => _SystemBubble(content: message.content),
          },
        );
      },
    );
  }
}

/// user 消息气泡：右对齐 + 面板层底色。
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<ConverPalette>()!;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: ConverSpacing.space8),
        padding: const EdgeInsets.symmetric(
          horizontal: ConverSpacing.space3,
          vertical: ConverSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(ConverRadii.bubble),
        ),
        child: Text(
          content,
          style: TextStyle(color: palette.ink1, fontSize: 15, height: 1.5),
        ),
      ),
    );
  }
}

/// assistant 气泡：已完成消息静态 Markdown（两级降频完成侧）；streaming 占位
/// 纯文本 + 单点闪烁光标；底部常驻重生成小图标（仅末条已结算可点）+
/// 主动停止「已停止」标记。
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.controller,
    required this.message,
    required this.isLast,
  });

  final ChatController controller;
  final ChatUiMessage message;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<ConverPalette>()!;
    final canRegenerate = !controller.isStreaming &&
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
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          border: Border.all(
            color: Theme.of(context).extension<ConverPalette>()!.border,
          ),
          borderRadius: BorderRadius.circular(ConverRadii.bubble),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.streaming)
              Row(
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
            else
              MarkdownBody(
                data: message.content,
                styleSheet: _markdownStyle(context),
                selectable: true,
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
            Padding(
              padding: const EdgeInsets.only(top: ConverSpacing.space1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// system 角色（开场白元信息等）：居中弱化小字。
class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<ConverPalette>()!;
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ConverSpacing.space8),
        child: Text(
          content,
          style: TextStyle(fontSize: 12.5, color: palette.ink4),
        ),
      ),
    );
  }
}

/// 单点闪烁光标（打字机占位气泡尾部，`▍` 半宽竖线；非三点 typing）。
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
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
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
    final palette = Theme.of(context).extension<ConverPalette>()!;
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
          top: BorderSide(
            color: Theme.of(context).extension<ConverPalette>()!.border,
          ),
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
                  fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
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
            if (streaming)
              IconButton(
                key: const Key('stop-button'),
                tooltip: '停止',
                iconSize: 26,
                icon: Icon(
                  Icons.stop,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: controller.stop,
              )
            else
              IconButton(
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