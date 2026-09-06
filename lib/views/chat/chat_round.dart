/// ChatRound — 聊天回合状态机（2026-09-07 架构深化候选 5：自 ChatController
/// 分离，纯搬迁不动行为）。
///
/// 深模块：协议表面 = [send] / [stop] / [regenerate] 三操作 + 合成消息只读
/// 状态面 + [resetForNavigation] / [applyBackgroundStoppedMark] / [isStopped]；
/// 实现内含流订阅、合成消息 id、停止竞态（F1）、入口态/后台流停止补标
/// （F3b）等回合生命周期逻辑。
///
/// 语义锚点（逐字对齐 ChatController 既有回合行为）：
/// - 发送：[send] 置 isStreaming → 乐观追加在途 user + 流式占位气泡 →
///   [ChatToken] 累积 [streamingText] → 终态（done / interrupted / error）
///   触发 [reloadMessages] 重载 DB 列表替换占位；
/// - 停止：[stop] 取消流订阅（ChatService 幂等落库已累积部分）→ 会话内重载
///   后末条 assistant 标「已停止」（[isStopped]）；无部分内容仅保留已发
///   user；入口态/后台流停止（[currentConversationId] 非本轮会话）记待补
///   集合，重进会话时经 [applyBackgroundStoppedMark] 补标（F3b）；
/// - 重生成：[regenerate] 走 ChatService 延迟删除（失败不删行、旧回复保留），
///   成功经 [reloadMessages] 重载；[isRegenerating] 防并发；
/// - 断流：[ChatInterrupted] → notice「回复已中断」（经共享 [NoticeRunner]
///   先错者胜，不挡后续操作）。
library;

import 'dart:async';

// 只引出 drift 生成的类型化行类（Message），不触碰数据层具体实现标识符
// （layer_boundary_test：视图层不得引用数据层具体实现）。
import '../../data/database/app_database.dart' show Message;
import '../../data/database/tables.dart' show Role;
import '../../data/repositories/message_repository.dart';
import '../../services/chat_service.dart';
import '../../services/llm/errors.dart';
import '../../services/notice_runner.dart';

/// 聊天回合状态机（一条消息回合的发送 / 停止 / 重生成 / 断流提示生命周期）。
///
/// 非 ChangeNotifier：状态变化经 [notify] 回调通知（controller 接入
/// `notifyListeners`，与 [NoticeRunner.onChanged] 惯用同构）。reload 与
/// notice 槽由 controller 注入——本类不导航、不持会话列表，纯回合。
// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 chat_controller.dart 惯例）。
// ignore_for_file: prefer_initializing_formals
class ChatRound {
  /// [chatService] 回合编排服务；[messageRepository] 停止竞态确认（F1）与
  /// 后台流末条判定（F3b）数据源；[noticeRunner] 共享 notice 槽（断流 /
  /// 错误先错者胜，发送起始清空）；[reloadMessages] 终态 / 停止后重载当前
  /// 会话 DB 列表——返回最新列表供「已停止」标记判定（会话内停止路径）；
  /// [notify] 状态变化通知（controller 接入 notifyListeners）。
  ChatRound({
    required ChatService chatService,
    required MessageRepository messageRepository,
    required NoticeRunner noticeRunner,
    required Future<List<Message>> Function() reloadMessages,
    required void Function() notify,
  })  : _chatService = chatService,
        _messageRepository = messageRepository,
        _noticeRunner = noticeRunner,
        _reloadMessages = reloadMessages,
        _notify = notify;

  final ChatService _chatService;
  final MessageRepository _messageRepository;
  final NoticeRunner _noticeRunner;
  final Future<List<Message>> Function() _reloadMessages;
  final void Function() _notify;

  // ── 回合状态 ──

  StreamSubscription<ChatEvent>? _subscription;
  bool _isStreaming = false;
  bool _streamingStopped = false;
  bool _reloadPending = false;
  String _streamingText = '';
  String? _pendingUserText;
  bool _isRegenerating = false;

  /// 主动停止后落库的 assistant 消息 id 集合（UI 侧「已停止」标记）。
  final Set<int> _stoppedMessageIds = <int>{};

  /// 当前回合所属对话 id（[send] 时记录）。入口态/后台流停止时仍可定位本轮
  /// 会话（F3b）。
  int? _roundConversationId;

  /// 当前回合已发 user 文本（[send] 时记录，生命周期随回合）——stop 后在途
  /// user 落库确认的目标（F1）。
  String? _roundUserText;

  /// 当前回合是否已累积过 token（ChatToken 到达即置位，生命周期随回合）——
  /// 「已停止」标记判定的「已累积内容是否存在」依据（F3b）。
  bool _roundStreamedAnything = false;

  /// 入口态/后台流停止后待补「已停止」标记的会话（stop 时该会话部分内容已
  /// 落库；重进该会话经 [applyBackgroundStoppedMark] 补标一次，F3b）。
  final Set<int> _backgroundStoppedConversationIds = <int>{};

  /// 合成消息 id 计数器（负值递减）。
  int _syntheticSeq = 0;

  /// 在途 user 合成 id——[send] 进入缓冲时一次性分配并缓存（getter 纯读，
  /// 不再每帧递减漂移）。
  int? _pendingUserSyntheticId;

  /// assistant 流式占位合成 id——[send] 进入缓冲时一次性分配并缓存；不随
  /// 清在途（[_clearInFlight]）清空（入口态后台流仍会渲染占位，id 须保持
  /// 稳定）。
  int? _assistantSyntheticId;

  // ── 只读状态面 ──

  /// 流式生成进行中（发送↔停止两态判据，单一事实来源）。
  bool get isStreaming => _isStreaming;

  /// 重生成进行中（disabled 重生成小图标）。
  bool get isRegenerating => _isRegenerating;

  /// 流式占位气泡已累积的纯文本（逐 token 追加）。
  String get streamingText => _streamingText;

  /// 主动停止：UI 侧「已停止」标记（DB 不写标记）。
  bool get streamingStopped => _streamingStopped;

  /// 在途 user 合成文本（send 缓冲后未落库）；null 无。
  String? get pendingUserText => _pendingUserText;

  /// 在途 user 合成 id（进入缓冲时已分配，纯读）。
  int? get pendingUserSyntheticId => _pendingUserSyntheticId;

  /// 是否渲染流式占位气泡（流式中 / 已停止 / 终态重载待办）。
  bool get hasSyntheticAssistant =>
      _isStreaming || _streamingStopped || _reloadPending;

  /// assistant 流式占位合成 id（进入缓冲时已分配，纯读）。
  int? get assistantSyntheticId => _assistantSyntheticId;

  /// [messageId] 是否已被标记「已停止」（UI 渲染「已停止」标记）。
  bool isStopped(int messageId) => _stoppedMessageIds.contains(messageId);

  // ── 回合操作 ──

  /// 发送 [text] 并开启流式回合（A2 UI 面）。
  ///
  /// 守卫：空文本 / 流式中 / 重生成中 / 终态重载未完成 → 忽略（发送↔停止
  /// 两态由 [isStreaming] 派生，避免生成中重复发送）。[conversationId] 为
  /// 当前会话（controller 导航面提供）。
  ///
  /// 回合编排委托 [ChatService.streamReply]（落库 user → 组装 → 流式生成）；
  /// 本层只订阅事件流：token 累积、终态重载 DB、错误映射 notice。
  void send({required int conversationId, required String text}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isStreaming || _isRegenerating || _reloadPending) {
      return;
    }
    _noticeRunner.clear();
    _isStreaming = true;
    _streamingStopped = false;
    _reloadPending = false;
    _streamingText = '';
    _pendingUserText = trimmed;
    // 合成 id 在消息进入缓冲时一次性分配（getter 纯读，稳定不漂移）。
    _pendingUserSyntheticId = _nextSyntheticId();
    _assistantSyntheticId = _nextSyntheticId();
    _roundConversationId = conversationId;
    _roundUserText = trimmed;
    _roundStreamedAnything = false;
    _notify();

    final stream = _chatService.streamReply(
      conversationId: conversationId,
      content: trimmed,
    );
    // 防御面：事件流理论上只发 ChatEvent（服务层错误经 ChatError 事件收口）；
    // onError 兜底映射为 ChatError 语义，避免未处理异步异常。
    _subscription = stream.listen(
      _onChatEvent,
      onError: (Object error, StackTrace stackTrace) =>
          _onChatEvent(ChatError(_descriptiveError(error))),
      onDone: _onStreamDone,
    );
  }

  /// 停止当前回合（A3 UI 面）：取消流订阅 → ChatService 幂等落库已累积部分
  /// → 会话内重载后末条 assistant 标「已停止」；无部分内容仅保留已发 user。
  ///
  /// [currentConversationId] 为停止时刻的当前会话（controller 导航面提供；
  /// null = 入口态）——与本轮会话一致 → 重载 + 标记；不一致（入口态/后台流
  /// 停止）→ 记待补标记，重进时经 [applyBackgroundStoppedMark] 补标（F3b）。
  Future<void> stop({int? currentConversationId}) async {
    if (!_isStreaming) {
      return;
    }
    final sub = _subscription;
    _subscription = null;
    final roundCid = _roundConversationId;
    final pendingUser = _roundUserText;
    _reloadPending = false;
    _isStreaming = false;
    _streamingStopped = true; // 占位气泡保留纯文本 +「已停止」标记
    _notify();
    await sub?.cancel(); // ChatService onCancel：已累积部分落库后关闭流
    // F1：cancel 完成不保证在途 user 已落库（服务层落库为独立异步路径）——
    // 有界等待其落库后再 reload，保证本路径任何窗口下 stop 后 UI 显示已发
    // user（不依赖「reload 恰好在落库后执行」的时序巧合；超时兜底防挂起）。
    if (roundCid != null && pendingUser != null && pendingUser.isNotEmpty) {
      await _awaitInFlightUserLanded(roundCid, pendingUser);
    }
    if (roundCid != null && currentConversationId == roundCid) {
      // 会话内停止：重载当前会话并按「本轮已累积过 token 且 DB 末条为
      // assistant」判「已停止」（原有路径 + 已累积内容判据）。
      final dbMessages = await _reloadMessages();
      if (_roundStreamedAnything &&
          dbMessages.isNotEmpty &&
          dbMessages.last.role == Role.assistant) {
        _stoppedMessageIds.add(dbMessages.last.id);
      }
    } else if (roundCid != null) {
      // 入口态/后台流停止（reload 目标为空）：基于 round 会话「已累积过 token」
      // + DB 末条 assistant 判定部分内容已落库 → 记录待补标记，重进该会话时
      // 补标（F3b）。
      final latest = await _lastMessageOrNull(roundCid);
      if (_roundStreamedAnything &&
          latest != null &&
          latest.role == Role.assistant) {
        _backgroundStoppedConversationIds.add(roundCid);
      }
    }
    _clearInFlight();
    _notify();
  }

  /// 重生成末条 assistant（A4 UI 面）：委托 [ChatService.regenerate]（延迟
  /// 删除：失败不删行、旧回复保留），成功经 [reloadMessages] 重载；失败仅
  /// notice（先错者胜）。
  Future<void> regenerate({required int conversationId}) async {
    if (_isStreaming || _isRegenerating || _reloadPending) {
      return;
    }
    _isRegenerating = true;
    _notify();
    await _noticeRunner.guard<void>(
      op: () async {
        await _chatService.regenerate(conversationId: conversationId);
        await _reloadMessages();
      },
      onError: (e) => _descriptiveError(e),
    );
    _isRegenerating = false;
    _notify();
  }

  // ── 导航 / 生命周期面 ──

  /// 导航切换清理（openConversation / backToEntry 共用）：清在途合成 / 已
  /// 停止标记 / 终态重载待办。不触碰 round 生命周期字段（入口态后台流继续
  /// 时仍可判定部分内容已落库，F3b 语义）。
  void resetForNavigation() {
    _clearInFlight();
    _reloadPending = false;
    _stoppedMessageIds.clear();
  }

  /// 重进 [conversationId] 时补后台停止标记（F3b）：该会话有待补标记且
  /// [dbMessages] 末条为 assistant → 标记末条并返回 true（控制器在重载后
  /// 调用；无待补标记 / 末条非 assistant → false 零副作用）。
  bool applyBackgroundStoppedMark(int conversationId, List<Message> dbMessages) {
    if (!_backgroundStoppedConversationIds.remove(conversationId)) {
      return false;
    }
    if (dbMessages.isNotEmpty && dbMessages.last.role == Role.assistant) {
      _stoppedMessageIds.add(dbMessages.last.id);
      return true;
    }
    return false;
  }

  /// 释放：取消在途流式订阅（ChatService 停止语义：已累积部分落库）。
  void dispose() {
    _subscription?.cancel();
  }

  // ── 内部 ──

  void _onChatEvent(ChatEvent event) {
    switch (event) {
      case ChatToken token:
        _streamingText += token.token;
        _roundStreamedAnything = true;
      case ChatDone():
        _finishRound();
      case ChatInterrupted():
        _noticeRunner.setFirst('回复已中断');
        _finishRound();
      case ChatError error:
        _noticeRunner.setFirst(error.message);
        _finishRound();
    }
    _notify();
  }

  /// 终态（done / interrupted / error）：停止流式，等流关闭后重载 DB。
  ///
  /// [streamingText] 在 [_onStreamDone] 重载后清空（替换为 DB 权威列表）。
  void _finishRound() {
    _isStreaming = false;
    _reloadPending = true;
  }

  /// 流关闭收尾：终态重载 DB 列表并清空在途合成占位（一次 notify，无闪烁）。
  Future<void> _onStreamDone() async {
    _subscription = null;
    if (_reloadPending) {
      _reloadPending = false;
      await _reloadMessages();
      _clearInFlight();
      // 自然终态回合已结算：后续回合从新 send 重建 round 记录。
      _roundConversationId = null;
      _roundUserText = null;
      _roundStreamedAnything = false;
      _notify();
    }
  }

  /// 清空在途合成状态（占位 user / 流式文本 / 停止标记），不触碰
  /// [_stoppedMessageIds]（落库消息标记的生命周期随会话）与 [_roundConversationId]
  /// / [_roundUserText] / [_assistantSyntheticId]（入口态后台流仍可能渲染占位，
  /// 停止标记与占位 id 的生命周期随整个回合）。
  void _clearInFlight() {
    _pendingUserText = null;
    _pendingUserSyntheticId = null;
    _streamingText = '';
    _streamingStopped = false;
  }

  /// F1：有界等待 [conversationId] 出现内容为 [content] 的 user 行落库——stop
  /// 后 reload 前补足「cancel 完成 ≠ 在途 user 已落库」的竞态窗口。已落库
  /// 立即返回；未落库轮询至 3s 总 deadline 兜底（单轮查询 1s 超时，真实网络
  /// 停滞不挂起 stop 路径）。
  Future<void> _awaitInFlightUserLanded(int conversationId, String content) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final messages = await _messageRepository
            .getMessages(conversationId)
            .timeout(const Duration(seconds: 1));
        if (messages.any((m) => m.role == Role.user && m.content == content)) {
          return;
        }
      } catch (_) {
        // 查询超时/异常：跳过本轮继续轮询（以总 deadline 兜底）。
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// 返回 [conversationId] 当前最后一条消息（无则 null；查询异常按 null 处理
  /// ——标记判定为尽力而为，不因 DB 读取失败阻塞）。
  Future<Message?> _lastMessageOrNull(int conversationId) async {
    try {
      final messages = await _messageRepository.getMessages(conversationId);
      return messages.isEmpty ? null : messages.last;
    } catch (_) {
      return null;
    }
  }

  /// 合成消息 id（负值递减，ListView key 唯一）。仅在消息进入缓冲时
  /// （[send] 分配两条合成 id）调用并缓存，不随 getter 反复取用。
  int _nextSyntheticId() {
    _syntheticSeq -= 1;
    return _syntheticSeq;
  }

  /// 领域 / LLM / 未预期异常的展示文案（重生成与事件流防御面共用）。
  String _descriptiveError(Object error) {
    if (error is DomainError) {
      return domainErrorResponse(error).message;
    }
    if (error is LLMError) {
      // 重生成路径 ChatService 不暴露 provider 名 → 无前缀基础文案。
      return llmErrorResponse(error, '').message;
    }
    return '生成回复失败: $error';
  }
}