/// ChatRound — 聊天回合状态机（2026-09-07 架构深化候选 5：自 ChatController
/// 分离，纯搬迁不动行为）。
///
/// 深模块：协议表面 = [send] / [stop] / [regenerate] / [retryInterrupted]
/// 四操作 + 合成消息只读状态面 + [resetForNavigation] /
/// [applyBackgroundStoppedMark] / [isStopped] / [isInterrupted]；
/// 实现内含流订阅、合成消息 id、停止完成契约（ChatService streamReply onCancel
/// 保证 user 写已结算，替换原 UI 轮询补偿）、入口态/后台流停止补标
/// （F3b）、断流截断标记与重试（M6-08）等回合生命周期逻辑。
///
/// 语义锚点（逐字对齐 ChatController 既有回合行为）：
/// - 发送：[send] 置 isStreaming → 乐观追加在途 user + 流式占位气泡 →
///   [ChatToken] 累积 [streamingText] → 终态（done / interrupted / error）
///   触发 [reloadMessages] 重载 DB 列表替换占位；
/// - 停止：[stop] 取消流订阅——ChatService 停止完成契约保证 cancel resolve 时
///   已发 user 写已结算（成功落库 / 回合已终态不再写）+ 幂等落库已累积部分 →
///   会话内重载后末条 assistant 标「已停止」（[isStopped]）；无部分内容仅保留
///   已发 user；入口态/后台流停止（[currentConversationId] 非本轮会话）记待补
///   集合，重进会话时经 [applyBackgroundStoppedMark] 补标（F3b）；
/// - 重生成：[regenerate] 走 ChatService 延迟删除（失败不删行、旧回复保留），
///   成功经 [reloadMessages] 重载；[isRegenerating] 防并发；
/// - 断流：[ChatInterrupted] → notice「回复已中断」（经共享 [NoticeRunner]
///   先错者胜，不挡后续操作）+ 截断落库消息标「回复中断」（[isInterrupted]，
///   UI 侧标记、DB 不写，与「已停止」[isStopped] 区分并列）；零部分内容
///   （[ChatInterrupted] messageId 为 null）→ 仅提示、无标记；
/// - 断流重试：[retryInterrupted] 对截断目标消息触发 [ChatService.regenerate]
///   （replace 语义：不新增 user 行），复用 [isRegenerating] 防并发与 notice
///   先错者胜；重试成功以服务实际替换目标 id（[RegenerateResult.replacedMessageId]）
///   结算——余标推进 [interruptedNoticeTargetId] 目标、配对门 + 文案门条件清理
///   （F-65①/②，见 [interruptedNoticeTargetId]）。
library;

import 'dart:async';
import 'dart:math' show max;

// 只引出 drift 生成的类型化行类（Message），不触碰数据层具体实现标识符
// （layer_boundary_test：视图层不得引用数据层具体实现）。
import '../../data/database/app_database.dart' show Message;
import '../../data/database/tables.dart' show Role;
import '../../data/repositories/message_repository.dart';
import '../../services/chat_service.dart';
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
  /// 断流提示文案（NoticeBanner 展示 + 「重试」动作渲染判据的单一来源）。
  static const String interruptedNoticeText = '回复已中断';

  /// [chatService] 回合编排服务；[messageRepository] 后台流末条判定（F3b）与
  /// 重生成目标解析（[regenerate]）数据源；[noticeRunner] 共享 notice 槽（断流 /
  /// 错误先错者胜，发送起始清空）；[reloadMessages] 终态 / 停止后重载当前
  /// 会话 DB 列表——返回最新列表供「已停止」标记判定（会话内停止路径）；
  /// [notify] 状态变化通知（controller 接入 notifyListeners）。
  ChatRound({
    required ChatService chatService,
    required MessageRepository messageRepository,
    required NoticeRunner noticeRunner,
    required Future<List<Message>> Function() reloadMessages,
    required void Function() notify,
  }) : _chatService = chatService,
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

  /// 断流后落库的截断 assistant 消息 id 集合（UI 侧「回复中断」标记，DB 不
  /// 写）。事件驱动记录：ChatInterrupted 带截断 id 即加入（回合即当前会话的
  /// 流，天然限定会话内断流；后台流断流补标不做，重进会话经
  /// [resetForNavigation] 清空属已知限制——对齐 08 Further Notes）；随
  /// [resetForNavigation] 清空、随 regenerate / [retryInterrupted] 成功
  /// （目标为该消息时）移除（replace 后旧 id 已删除）。
  final Set<int> _interruptedMessageIds = <int>{};

  /// 当前「回复已中断」notice 对应的可重试截断消息 id（= 最近一次**有内容**
  /// 断流落库的消息；横幅「重试」目标的单一来源）。零内容断流
  /// （ChatInterrupted(null)）→ null（提示仍展示但无重试目标，防 notice 目标
  /// 指向上一轮截断）；结算（[_resolveInterruptedTarget]）后余标非空 → 推进为
  /// max(marks)（F-65①，横幅持续指向最近剩余截断），否则复位为 null；随
  /// [resetForNavigation] 清空。
  int? _interruptedNoticeTargetId;

  /// 当前回合所属对话 id（[send] 时记录）。入口态/后台流停止时仍可定位本轮
  /// 会话（F3b）。
  int? _roundConversationId;

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

  /// [messageId] 是否已被标记「回复中断」（UI 渲染「回复中断」小标；与
  /// [isStopped] 区分并列——停止/断流为互斥终态，不会同时命中同一消息）。
  bool isInterrupted(int messageId) =>
      _interruptedMessageIds.contains(messageId);

  /// 会话内是否存在未解决的截断回复标记（气泡「回复中断」小标面；与 notice
  /// 「可重试目标」面分离——零内容断流后仍可能有历史截断标记）。
  bool get hasInterrupted => _interruptedMessageIds.isNotEmpty;

  /// 当前「回复已中断」notice 的身份 seq（F-128：以 noticeId 配对替代文案
  /// 比较；置位时机 = ChatInterrupted 事件 setFirst 之后）。
  int? _interruptedNoticeId;

  /// 当前「回复已中断」notice 的可重试截断目标消息 id（null = 无可重试目标：
  /// 零内容断流 / 目标已解决 / 导航清理）——NoticeBanner「重试」动作渲染判据。
  int? get interruptedNoticeTargetId => _interruptedNoticeTargetId;

  /// 当前提示是否为「回复已中断」且该提示存在可重试的截断目标——NoticeBanner
  /// 「重试」动作渲染判据（仅截断通知传动作；其它 notice / 零内容断流不传，
  /// 防动作误挂）。判据（notice 身份 + notice 目标 + reload 窗口）单一归属
  /// 本回合。F-128：身份判据用 [NoticeRunner.noticeId] 与 [_interruptedNoticeId]
  /// 配对（不再比较文案字符串），同文案新旧 notice 天然可区分。
  ///
  /// F-65③：终态一帧 reload 窗口（[_reloadPending]，`_finishRound` 置位至
  /// `_onStreamDone` 收尾）内**不渲染**「重试」按钮——共享守卫期间点击原本是
  /// 静默 no-op（`_regenerateTarget` 直接 return）；窗口内按钮不可达，杜绝
  /// 无响应点击（接受窗口后按钮弹入微调）。
  bool get hasRetryableInterrupted =>
      _interruptedNoticeId != null &&
      _noticeRunner.noticeId == _interruptedNoticeId &&
      _interruptedNoticeTargetId != null &&
      !_reloadPending;

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

  /// 停止当前回合（A3 UI 面）：取消流订阅 → ChatService 停止完成契约（cancel
  /// resolve 保证已发 user 写已结算 + 幂等落库已累积部分）→ 会话内重载后末条
  /// assistant 标「已停止」；无部分内容仅保留已发 user。
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
    _reloadPending = false;
    _isStreaming = false;
    _streamingStopped = true; // 占位气泡保留纯文本 +「已停止」标记
    _notify();
    // 停止完成契约（AR-2）：cancel（onCancel = ChatService 门等待）resolve 即
    // 保证已发 user 写已结算——reload 必见已发 user，无需（也无从）再轮询。
    await sub?.cancel();
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

  /// 重生成末条 assistant（A4 UI 面，气泡「重生成」图标路径）：缺省目标 =
  /// 末条 assistant 由服务层解析（零预解析，`messageId: null` 走服务缺省
  /// [_resolveRegenerateTarget]；F-64 单一来源），委托共享 [_regenerateTarget]
  /// （延迟删除：失败不删行、旧回复保留；成功经 [reloadMessages] 重载）。
  ///
  /// 清理统一（B1=W6 F-1）：目标恰为该截断消息时，成功同样移除「回复中断」
  /// 标记并清「回复已中断」提示——与 [retryInterrupted] 后置条件一致，杜绝
  /// 「图标重生成成功后横幅死重试残留」。失败仅 notice（先错者胜）。
  Future<void> regenerate({required int conversationId}) async {
    await _regenerateTarget(conversationId: conversationId, messageId: null);
  }

  /// 重试当前「回复已中断」notice 的截断目标（T3 NoticeBanner「重试」动作，
  /// M6-08）：目标 = 最近一次有内容断流落库的消息；对目标触发 regenerate
  /// （replace 语义——不新增 user 行、无重复输入；复用延迟删除：失败旧截断
  /// 行保留）。无目标（零内容断流 / 目标已解决 / 导航清理）零副作用。守卫
  /// 与并发策略（isRegenerating 防并发、notice 先错者胜）在 [_regenerateTarget]
  /// 共享腿内统一。
  Future<void> retryInterrupted({required int conversationId}) async {
    final targetId = _interruptedNoticeTargetId;
    if (targetId == null) {
      return;
    }
    await _regenerateTarget(
      conversationId: conversationId,
      messageId: targetId,
    );
  }

  // ── 导航 / 生命周期面 ──

  /// 导航切换清理（openConversation / backToEntry 共用）：清在途合成 / 已
  /// 停止标记 / 截断标记与 notice 重试目标（M6-08：跨会话不串标）/ 终态
  /// 重载待办。不触碰 round 生命周期字段（入口态后台流继续时仍可判定部分
  /// 内容已落库，F3b 语义）。
  void resetForNavigation() {
    _clearInFlight();
    _reloadPending = false;
    _stoppedMessageIds.clear();
    _interruptedMessageIds.clear();
    _interruptedNoticeTargetId = null;
  }

  /// 重进 [conversationId] 时补后台停止标记（F3b）：该会话有待补标记且
  /// [dbMessages] 末条为 assistant → 标记末条并返回 true（控制器在重载后
  /// 调用；无待补标记 / 末条非 assistant → false 零副作用）。
  bool applyBackgroundStoppedMark(
    int conversationId,
    List<Message> dbMessages,
  ) {
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

  /// regenerate（图标路径）与 retryInterrupted（横幅路径）共享执行腿
  /// （B1=W6 F-1 收敛）：对 [messageId] 目标（null = 服务层缺省末条 assistant）
  /// 执行 [ChatService.regenerate] → 成功经 [reloadMessages] 重载 → 以服务
  /// 实际替换目标行 id（[RegenerateResult.replacedMessageId]）作结算键统一
  /// 结算标记/notice（F-64：客户端零预解析，消除调用前推断-执行间删行窗口）。
  ///
  /// 守卫（isStreaming / [isRegenerating] / 终态重载待办）与失败折叠
  /// （[NoticeRunner] 先错者胜——既有「回复已中断」不被失败文案覆盖）在共享
  /// 腿内，两路径并发策略一致。
  Future<void> _regenerateTarget({
    required int conversationId,
    required int? messageId,
  }) async {
    if (_isStreaming || _isRegenerating || _reloadPending) {
      return;
    }
    _isRegenerating = true;
    _notify();
    final result = await _noticeRunner.guard<RegenerateResult>(
      op: () async {
        final r = await _chatService.regenerate(
          conversationId: conversationId,
          messageId: messageId,
        );
        await _reloadMessages();
        return r;
      },
      onError: (e) => _descriptiveError(e),
    );
    final replacedId = result?.replacedMessageId;
    if (replacedId != null) {
      _resolveInterruptedTarget(replacedId);
    }
    _isRegenerating = false;
    _notify();
  }

  /// 目标消息被 regenerate replace 成功后的截断状态结算：从标记集移除该
  /// 消息（旧 id 已从 DB 删除）；仅当被解目标 == 当前「回复已中断」notice 的
  /// 可重试目标（配对门：F-4 零内容断流态 target==null 不误清横幅）才进入
  /// notice 目标结算：
  /// - 仍有余截断标记 → 目标推进为 max(marks)（F-65①，DB 主键单调即时序；
  ///   notice 保持不清——横幅持续指向最近剩余截断）；
  /// - 无余标 → notice 目标复位 null，且仅当 notice 身份仍为当前中断提示
  ///   （身份门 F-65②，F-128 改用 [NoticeRunner.noticeId] 与
  ///   [_interruptedNoticeId] 配对：重试期间被并发 `set` 覆盖的提示不清空）
  ///   才 [_noticeRunner.clear]（中断已全部解决，横幅不再残留）。
  /// 非 notice 目标的截断被修 → 仅清气泡标记、提示与目标保留。
  void _resolveInterruptedTarget(int messageId) {
    final removed = _interruptedMessageIds.remove(messageId);
    if (!removed || _interruptedNoticeTargetId != messageId) {
      return;
    }
    if (_interruptedMessageIds.isNotEmpty) {
      // F-65①：余标推进为最近剩余截断（notice 保持，横幅仍可重试）。
      _interruptedNoticeTargetId = _interruptedMessageIds.reduce(max);
      return;
    }
    _interruptedNoticeTargetId = null;
    if (_noticeRunner.noticeId == _interruptedNoticeId) {
      // F-65② 身份门：仅当 notice 仍为当前「回复已中断」才清（防吞并发提示）。
      _interruptedNoticeId = null;
      _noticeRunner.clear();
    }
  }

  void _onChatEvent(ChatEvent event) {
    switch (event) {
      case ChatToken token:
        _streamingText += token.token;
        _roundStreamedAnything = true;
      case ChatDone():
        _finishRound();
      case ChatInterrupted(:final messageId):
        _noticeRunner.setFirst(ChatRound.interruptedNoticeText);
        // F-128：置位后记录 notice 身份 seq（配对判据；同文案新旧 notice 可
        // 区分，替代文案字符串比较）。
        _interruptedNoticeId = _noticeRunner.noticeId;
        // 截断回复「回复中断」标记（UI 侧、DB 不写）与 notice 重试目标
        // （M6-08）：有内容断流 → 记录截断 id 为标记并作 notice 目标；零部分
        // 内容（messageId null）→ notice 目标复位（提示仍展示但无可重试目标，
        // F-4 防 notice 目标指向上一轮截断）。
        final truncatedId = messageId;
        if (truncatedId != null) {
          _interruptedMessageIds.add(truncatedId);
          _interruptedNoticeTargetId = truncatedId;
        } else {
          _interruptedNoticeTargetId = null;
        }
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
      _roundStreamedAnything = false;
      _notify();
    }
  }

  /// 清空在途合成状态（占位 user / 流式文本 / 停止标记），不触碰
  /// [_stoppedMessageIds]（落库消息标记的生命周期随会话）与 [_roundConversationId]
  /// / [_assistantSyntheticId]（入口态后台流仍可能渲染占位，
  /// 停止标记与占位 id 的生命周期随整个回合）。
  void _clearInFlight() {
    _pendingUserText = null;
    _pendingUserSyntheticId = null;
    _streamingText = '';
    _streamingStopped = false;
  }

  /// 返回 [conversationId] 当前最后一条消息（无则 null；查询异常按 null 处理
  /// ——标记判定为尽力而为，不因 DB 读取失败阻塞）。
  ///
  /// 末条读下推 [MessageRepository.lastMessage]（S6：不再全量拉取 + 线性
  /// 遍历）；仓库不吞错，异常在本调用方吞并（try/catch 语义保留）。
  Future<Message?> _lastMessageOrNull(int conversationId) async {
    try {
      return await _messageRepository.lastMessage(conversationId);
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

  /// 领域 / LLM / 未预期异常的展示文案（F-124：单源 [chatErrorMessage]，
  /// 与 ChatService 三叉 catch 收敛同源；重生成路径不暴露 provider 名）。
  String _descriptiveError(Object error) => chatErrorMessage(error);
}
