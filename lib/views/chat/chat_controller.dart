/// ChatController — 聊天 tab 的回合状态机（发送 / 停止 / 重生成 / 断流提示）。
///
/// 语义锚点（桌面，逐字对齐）：
/// - `desktop/frontend/js/stream-session.js`：onToken 累积全文 + streamSettled
///   终态守卫 + 停止（AbortError）写回「已停止」语义 + 普通错误非阻塞上抛
///   （不写入消息缓存）；
/// - `desktop/frontend/js/chat.js`：发送↔停止两态由 isStreaming 派生（单一
///   事实来源）、重生成仅末条已结算 assistant、错误条独立于消息列表。
///
/// 移动端两级降频（R4 定案）：streaming 期间维护 [streamingText] 纯文本占位
/// 气泡（不进 Markdown 渲染），完成 / 停止 / 断流落库后经 [_reloadMessages]
/// 一次切回 DB 权威列表（assistant 静态 Markdown 由 UI 渲染）。
///
/// 层级：ChangeNotifier 视图模型。唯一依赖 [ChatService] + 会话 / 角色 /
/// 消息仓储抽象（不触碰数据库具体实现 / 平台存储——`layer_boundary_test`
/// 契约）。ChatView 经 provider 注入本控制器，回合状态与落库可观察状态全部
/// 收敛于此，UI 只做呈现。
///
/// 回合语义（对齐 ChatService 编排）：
/// - 发送：[send] 置 isStreaming → 乐观追加在途 user + 流式占位气泡 →
///   [ChatToken] 累积 [streamingText] → 终态（[ChatDone] / [ChatInterrupted] /
///   [ChatError]）触发重载 DB 列表替换占位；
/// - 停止：[stop] 取消流订阅（ChatService 幂等落库已累积部分）→ 重载后把末条
///   assistant 标「已停止」（[ChatUiMessage.stopped]）；无部分内容仅保留已发
///   user；
/// - 重生成：[regenerate] 走 ChatService 延迟删除（失败不删行、旧回复保留），
///   成功重载列表；[isRegenerating] 防并发；
/// - 断流：[ChatInterrupted] → 非阻塞 [notice]「回复已中断」（可
///   [dismissNotice]，不挡后续操作）。
library;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（构造语义由下方 docstring 说明）。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

// 只引出 drift 生成的类型化行类（Message / Conversation / Character），
// 不触碰数据层具体实现标识符（layer_boundary_test：视图层不得引用数据层具体
// 实现）。
import '../../data/database/app_database.dart'
    show Message, Conversation, Character;
import '../../data/database/tables.dart' show Role;
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../services/chat_service.dart';
import '../../services/llm/errors.dart';

/// 单条聊天 UI 显示消息（视图层模型，由 [ChatController.messages] 组装）。
///
/// [id] 为 DB 消息 id；在途（未落库）的 user / 流式占位气泡为**合成**消息，
/// id 为负值——仅供 ListView key 与角色 / 停止标记消费，不用于重生成或落库。
class ChatUiMessage {
  const ChatUiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.stopped = false,
    this.streaming = false,
  });

  /// DB 消息 id；在途合成消息为负值。
  final int id;

  /// 消息角色（user / assistant / system）。
  final Role role;

  /// 消息内容（已完成消息为最终文本；流式占位为已累积纯文本）。
  final String content;

  /// 主动停止：UI 侧「已停止」标记（DB 不写标记）。
  final bool stopped;

  /// 流式进行中：渲染纯文本 + 闪烁光标（两级降频 streaming 侧）。
  final bool streaming;
}

/// 聊天 tab 的回合状态机控制器。
///
/// 用法：装配层构造后经 provider 注入；ChatView 首次挂载时若
/// [hasLoadedEntry] 为 false 则调用 [loadEntry]（幂等）。
class ChatController extends ChangeNotifier {
  /// [chatService] 为回合编排服务；
  /// [conversationRepository] / [characterRepository] /
  /// [messageRepository] 提供列表 / 角色来源 / 消息重载；
  /// [highlightDuration] 为跳转定位高亮的自动清除时长（默认 3s，对齐桌面
  /// `chat.js HIGHLIGHT_DURATION=3000`；测试注入短时长验证定时清除）。
  ChatController({
    required ChatService chatService,
    required ConversationRepository conversationRepository,
    required CharacterRepository characterRepository,
    required MessageRepository messageRepository,
    this.highlightDuration = const Duration(seconds: 3),
  })  : _chatService = chatService,
        _conversationRepository = conversationRepository,
        _characterRepository = characterRepository,
        _messageRepository = messageRepository;

  final ChatService _chatService;
  final ConversationRepository _conversationRepository;
  final CharacterRepository _characterRepository;
  final MessageRepository _messageRepository;

  /// 跳转定位高亮的自动清除时长（对齐桌面 `HIGHLIGHT_DURATION=3000`）。
  final Duration highlightDuration;

  // ── 入口状态 ──

  bool _hasLoadedEntry = false;
  bool _loadingEntry = false;
  List<ConversationWithCount> _conversations = const [];
  Character? _firstCharacter;
  bool _creatingConversation = false;

  // ── 导航状态 ──

  int? _activeConversationId;
  Conversation? _activeConversation;

  // ── 会话状态（DB 权威列表）──

  List<Message> _dbMessages = const [];

  /// 主动停止后落库的 assistant 消息 id 集合（UI 侧「已停止」标记）。
  final Set<int> _stoppedMessageIds = <int>{};

  // ── 回合状态 ──

  StreamSubscription<ChatEvent>? _subscription;
  bool _isStreaming = false;
  bool _streamingStopped = false;
  bool _reloadPending = false;
  String _streamingText = '';
  String? _pendingUserText;
  bool _isRegenerating = false;
  String? _notice;

  /// 当前回合所属对话 id（[send] 时记录）。入口态 / 后台流停止（
  /// `_activeConversationId` 为 null）时仍可定位本轮会话（F3b）。
  int? _roundConversationId;

  /// 当前回合已发 user 文本（[send] 时记录，生命周期随回合）——stop 后在途
  /// user 落库确认的目标（F1；backToEntry 清 `_pendingUserText` 不清此值）。
  String? _roundUserText;

  /// 当前回合是否已累积过 token（ChatToken 到达即置位，生命周期随回合）——
  /// 「已停止」标记判定的「已累积内容是否存在」依据（F3b：不随 backToEntry
  /// 清空，入口态/后台流停止仍可判定部分内容已落库）。
  bool _roundStreamedAnything = false;

  /// 入口态/后台流停止后待补「已停止」标记的会话（stop 时该会话部分内容已
  /// 落库；重进该会话补标一次，F3b）。
  final Set<int> _backgroundStoppedConversationIds = <int>{};

  /// 合成消息 id 计数器（负值递减）。
  int _syntheticSeq = 0;

  // ── 跳转定位高亮（M3-04c）──

  /// 当前高亮目标消息 id 集合（DB 正 id；流式合成负 id 永不进入——正 id 判定，
  /// 对齐 spec §Implementation Decisions 定位落实）。
  final Set<int> _highlightMessageIds = <int>{};

  /// 高亮请求序号：每次打开/重开会话带高亮 +1（视图据此识别新高亮请求并
  /// 触发一次定位滚动；清除不递增）。
  int _highlightRequestSeq = 0;

  /// 高亮自动清除定时器（超时移除 [highlightMessageIds] 并通知；dispose 取消防
  /// 泄漏、防「notify after dispose」）。
  Timer? _highlightTimer;

  /// F4：在途 user 合成 id——[send] 进入缓冲时一次性分配并缓存（messages
  /// getter 纯读，不再每帧递减漂移）。
  int? _pendingUserSyntheticId;

  /// F4：assistant 流式占位合成 id——[send] 进入缓冲时一次性分配并缓存；不随
  /// `_clearInFlight` 清空（入口态后台流仍会渲染占位，id 须保持稳定）。
  int? _assistantSyntheticId;

  // ── 入口面 ──

  /// 是否已完成首次入口加载（ChatView initState 幂等触发 [loadEntry]）。
  bool get hasLoadedEntry => _hasLoadedEntry;

  /// 入口列表加载中。
  bool get loadingEntry => _loadingEntry;

  /// 最近对话列表（`updated_at` 倒序，随 [loadEntry] 刷新）。
  List<ConversationWithCount> get conversations => _conversations;

  /// 是否存在可用于「新建对话」的首个角色（characters 首条）。
  bool get canCreateConversation => _firstCharacter != null;

  /// 无可新建角色时的禁用提示文案（[canCreateConversation] false 时非空）。
  String? get createDisabledReason =>
      _firstCharacter == null ? '请先在角色页创建角色' : null;

  /// 「新建对话」提交中（防连点重复建会话）。
  bool get creatingConversation => _creatingConversation;

  /// 加载最近对话 + 首个角色（新建来源；入口导航每次回来都调用以刷新）。
  ///
  /// 每步查询带 3s 防挂兜底（平台存储通道在宿主测试环境可能挂起——widget
  /// 测试实证；query 超时 → catch 复位 loading 态与空列表，不产生永不结束的
  /// 加载态 spinner）。
  Future<void> loadEntry() async {
    _loadingEntry = true;
    notifyListeners();
    try {
      _conversations = await _conversationRepository
          .listConversations()
          .timeout(const Duration(seconds: 3));
      final characters =
          await _characterRepository.listCharacters().timeout(const Duration(seconds: 3));
      _firstCharacter = characters.isEmpty ? null : characters.first.character;
      _hasLoadedEntry = true;
    } catch (error) {
      _notice = _notice ?? '加载对话失败: $error';
      _conversations = const [];
      _firstCharacter = null;
      _hasLoadedEntry = true;
    } finally {
      _loadingEntry = false;
      notifyListeners();
    }
  }

  /// 新建对话：取首个角色；无角色 → [notice] 提示（M2 最小入口，M3 替换）。
  ///
  /// 创建成功随即进入新会话（createConversation 蓝本预插开场白）。
  Future<void> createConversation() async {
    final character = _firstCharacter;
    if (character == null) {
      _notice = '请先在角色页创建角色';
      notifyListeners();
      return;
    }
    if (_creatingConversation) {
      return;
    }
    _creatingConversation = true;
    notifyListeners();
    final int conversationId;
    try {
      final conversation =
          await _conversationRepository.createConversation(characterId: character.id);
      conversationId = conversation.id;
    } catch (error) {
      _creatingConversation = false;
      _notice = '新建对话失败: $error';
      notifyListeners();
      return;
    }
    _creatingConversation = false;
    await openConversation(conversationId);
  }

  /// 以指定角色建会话并直达（M3-01 角色卡「开始对话」入口）。
  ///
  /// 与 [createConversation]（取入口首角色）的差异：会话归属显式传入的
  /// [characterId]，不依赖 [loadEntry] 缓存的首角色快照；角色不存在 / 已
  /// 删除 → [notice] 提示且停留入口，零残留会话。两者共用
  /// [_creatingConversation] 防连点标志（任一建会话流程进行中互相忽略）。
  Future<void> createConversationFor(int characterId) async {
    if (_creatingConversation) {
      return;
    }
    _creatingConversation = true;
    notifyListeners();
    final int conversationId;
    try {
      final character = await _characterRepository
          .getCharacter(characterId)
          .timeout(const Duration(seconds: 3));
      if (character == null) {
        _creatingConversation = false;
        _notice = '角色不存在或已删除：无法新建对话';
        notifyListeners();
        return;
      }
      final conversation =
          await _conversationRepository.createConversation(characterId: characterId);
      conversationId = conversation.id;
    } catch (error) {
      _creatingConversation = false;
      _notice = '新建对话失败: $error';
      notifyListeners();
      return;
    }
    _creatingConversation = false;
    await openConversation(conversationId);
  }

  // ── 导航面 ──

  /// 当前是否停留在入口（最近对话列表）页。
  bool get isEntry => _activeConversationId == null;

  /// 当前打开的对话 id；入口页为 null。
  int? get activeConversationId => _activeConversationId;

  /// 当前对话行；null（未打开 / 对话被删）时 UI 回退占位标题。
  Conversation? get activeConversation => _activeConversation;

  // ── 跳转定位高亮面（M3-04c）──

  /// 当前高亮目标消息 id 集合（DB 正 id；高亮清除 / 换会话时清空）。
  ///
  /// 视图据此渲染琥珀高亮样式与定位目标；只读面，写入经 [clearHighlight] /
  /// [openConversation] 的高亮参数。
  Set<int> get highlightMessageIds => Set<int>.unmodifiable(_highlightMessageIds);

  /// 高亮请求序号：每次新的高亮请求 +1（不同目标 / 空→有转换时），视图以
  /// 序号变化触发一次定位滚动（清除不递增，防重复滚动）。
  int get highlightRequestSeq => _highlightRequestSeq;

  /// 立即清除当前高亮（取消定位定时器）：返回入口 / 会话切换后不残留高亮。
  void clearHighlight() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    if (_highlightMessageIds.isEmpty) {
      return;
    }
    _highlightMessageIds.clear();
    notifyListeners();
  }

  /// 打开 [conversationId]：清空在途回合 → 加载消息。
  ///
  /// [highlightMessageId] 非空时高亮该 DB 正 id 消息（3s 自动清除；视图按
  /// [highlightRequestSeq] 变化定位滚动）；省略时仅清除既有的高亮状态
  /// （默认时序/语义与 M2 完全一致）。已在目标会话：
  /// - 带高亮 → 幂等重开（重复点击同一结果：重设高亮计时，不重载消息）；
  /// - 不带高亮 → 幂等返回（M2 零回归）。
  ///
  /// 流式中打开其他会话 → 先 [stop]（已累积部分落库，「已停止」标记交给该
  /// 会话自身重载）。
  Future<void> openConversation(int conversationId, {int? highlightMessageId}) async {
    if (_activeConversationId == conversationId) {
      if (highlightMessageId != null) {
        // 同会话重复点击同一结果：重设高亮（3s 计时重启），不重载消息——幂等。
        _applyHighlight(highlightMessageId);
        notifyListeners();
      }
      return;
    }
    if (_isStreaming) {
      await stop();
    }
    _activeConversationId = conversationId;
    _activeConversation = null;
    _dbMessages = const [];
    _stoppedMessageIds.clear();
    _clearInFlight();
    _reloadPending = false;
    _notice = null;
    notifyListeners();
    try {
      // F2：DB 异常收口为 notice（对齐 _reloadMessages / loadEntry 兜底），
      // 不产生未处理异步异常（调用方 fire-and-forget）。
      _activeConversation =
          await _conversationRepository.getConversation(conversationId);
    } catch (error) {
      _notice = _notice ?? '加载对话失败: $error';
      _activeConversation = null;
    }
    await _reloadMessages();
    // 入口态/后台流停止的待补「已停止」标记：重进该会话且末条为 assistant
    // → 补标一次（F3b，标记判定不依赖停止时 reload 目标）。
    if (_backgroundStoppedConversationIds.remove(conversationId) &&
        _dbMessages.isNotEmpty &&
        _dbMessages.last.role == Role.assistant) {
      _stoppedMessageIds.add(_dbMessages.last.id);
    }
    // M3-04c：消息加载完成后再落高亮（正 id 判定；开 B 会话自动清除 A 的高亮，
    // 负 id 合成消息永不进入——验收 5/7）。
    _applyHighlight(highlightMessageId);
    notifyListeners();
  }

  /// 返回入口页并刷新最近对话（标题 / 消息数已随回合变化）。
  ///
  /// 在途流式**不**中止（对齐桌面 P6.5 后台流语义）：回合继续落库，
  /// 回到会话时经重载恢复最终状态。返回时清除跳转定位高亮（3s 内返回入口
  /// 再进入无残留——验收 7）。
  Future<void> backToEntry() async {
    clearHighlight();
    _activeConversationId = null;
    _activeConversation = null;
    _dbMessages = const [];
    _stoppedMessageIds.clear();
    _clearInFlight();
    _reloadPending = false;
    _notice = null;
    notifyListeners();
    await loadEntry();
  }

  // ── 会话面 ──

  /// 组装展示消息列表：DB 权威消息 + 在途合成消息（user + 流式/停止占位）。
  ///
  /// 已完成 assistant 由 UI 静态 Markdown 渲染；流式占位为纯文本。
  List<ChatUiMessage> get messages {
    final result = <ChatUiMessage>[
      for (final m in _dbMessages)
        ChatUiMessage(
          id: m.id,
          role: m.role,
          content: m.content,
          stopped: _stoppedMessageIds.contains(m.id),
        ),
    ];
    final pendingUser = _pendingUserText;
    if (pendingUser != null && pendingUser.isNotEmpty) {
      // 合成 id 在本条进入缓冲时已分配（send），此处纯读（F4：getter 副作用
      // 已移除，ListView key 不再每帧漂移）。
      result.add(ChatUiMessage(
        id: _pendingUserSyntheticId!,
        role: Role.user,
        content: pendingUser,
      ));
    }
    if (_isStreaming || _streamingStopped || _reloadPending) {
      result.add(ChatUiMessage(
        id: _assistantSyntheticId!,
        role: Role.assistant,
        content: _streamingText,
        streaming: _isStreaming,
        stopped: _streamingStopped,
      ));
    }
    return List<ChatUiMessage>.unmodifiable(result);
  }

  // ── 回合面 ──

  /// 流式生成进行中（发送↔停止两态判据，单一事实来源）。
  bool get isStreaming => _isStreaming;

  /// 重生成进行中（disabled 重生成小图标）。
  bool get isRegenerating => _isRegenerating;

  /// 流式占位气泡已累积的纯文本（逐 token 追加）。
  String get streamingText => _streamingText;

  /// 非阻塞提示（断流「回复已中断」/ 错误映射文案 / 基础设施失败）；null 无。
  String? get notice => _notice;

  /// 关闭当前非阻塞提示。
  void dismissNotice() {
    if (_notice == null) {
      return;
    }
    _notice = null;
    notifyListeners();
  }

  /// 发送一条用户消息并开启流式回合（A2 UI 面）。
  ///
  /// 守卫：空文本 / 无会话 / 流式中 / 重生成中 / 终态重载未完成 → 忽略
  /// （发送↔停止两态由 [isStreaming] 派生，避免生成中重复发送）。
  ///
  /// 回合编排委托 [ChatService.streamReply]（落库 user → 组装 → 流式生成）；
  /// 本层只订阅事件流：token 累积、终态重载 DB、错误映射 [notice]。
  Future<void> send(String text) async {
    final trimmed = text.trim();
    final cid = _activeConversationId;
    if (trimmed.isEmpty ||
        cid == null ||
        _isStreaming ||
        _isRegenerating ||
        _reloadPending) {
      return;
    }
    _notice = null;
    _isStreaming = true;
    _streamingStopped = false;
    _reloadPending = false;
    _streamingText = '';
    _pendingUserText = trimmed;
    // F4：合成 id 在消息进入缓冲时一次性分配（getter 纯读，稳定不漂移）。
    _pendingUserSyntheticId = _nextSyntheticId();
    _assistantSyntheticId = _nextSyntheticId();
    _roundConversationId = cid;
    _roundUserText = trimmed;
    _roundStreamedAnything = false;
    notifyListeners();

    final stream =
        _chatService.streamReply(conversationId: cid, content: trimmed);
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
  /// → 重载后末条 assistant 标「已停止」；无部分内容仅保留已发 user。
  Future<void> stop() async {
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
    notifyListeners();
    await sub?.cancel(); // ChatService onCancel：已累积部分落库后关闭流
    // F1：cancel 完成不保证在途 user 已落库（服务层落库为独立异步路径）——
    // 有界等待其落库后再 reload，保证本路径任何窗口下 stop 后 UI 显示已发
    // user（不依赖「reload 恰好在落库后执行」的时序巧合；超时兜底防挂起）。
    if (roundCid != null && pendingUser != null && pendingUser.isNotEmpty) {
      await _awaitInFlightUserLanded(roundCid, pendingUser);
    }
    if (roundCid != null && _activeConversationId == roundCid) {
      // 会话内停止：重载当前会话并按「本轮已累积过 token 且 DB 末条为
      // assistant」判「已停止」（原有路径 + 已累积内容判据）。
      await _reloadMessages();
      if (_roundStreamedAnything &&
          _dbMessages.isNotEmpty &&
          _dbMessages.last.role == Role.assistant) {
        _stoppedMessageIds.add(_dbMessages.last.id);
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
    notifyListeners();
  }

  /// 重生成末条 assistant（A4 UI 面）：委托 [ChatService.regenerate]（延迟
  /// 删除：失败不删行、旧回复保留），成功重载列表；失败仅 [notice]。
  Future<void> regenerate() async {
    final cid = _activeConversationId;
    if (cid == null || _isStreaming || _isRegenerating || _reloadPending) {
      return;
    }
    _isRegenerating = true;
    notifyListeners();
    try {
      await _chatService.regenerate(conversationId: cid);
      await _reloadMessages();
    } catch (error) {
      // 重生成失败：旧回复保留（服务层保证），仅给出非阻塞提示。
      _notice = _descriptiveError(error);
      notifyListeners();
    } finally {
      _isRegenerating = false;
      notifyListeners();
    }
  }

  // ── 服务/生命周期 ──

  /// 释放时取消在途流式订阅（ChatService 停止语义：已累积部分落库）与
  /// 高亮定位定时器，并清空高亮状态（防泄漏 / 防「notify after dispose」）。
  @override
  void dispose() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _highlightMessageIds.clear();
    _subscription?.cancel();
    super.dispose();
  }

  // ── 内部 ──

  /// 应用跳转定位高亮（M3-04c）。
  ///
  /// [highlightMessageId] 为 DB 正 id 目标（负 id 合成消息永不进入——永远按
  /// 正 id 判定）；null → 仅清除既有高亮（取消定时器）。高亮自动清除定时器
  /// 每次重设；同目标重复请求（幂等重开）不递增 [highlightRequestSeq]（不触发
  /// 视图重复定位），不同目标 / 空→有转换会递增。
  void _applyHighlight(int? highlightMessageId) {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    final hadHighlight = _highlightMessageIds.isNotEmpty;
    final sameTarget = hadHighlight &&
        highlightMessageId != null &&
        _highlightMessageIds.single == highlightMessageId;
    _highlightMessageIds.clear();
    if (highlightMessageId == null) {
      return;
    }
    _highlightMessageIds.add(highlightMessageId);
    if (!sameTarget) {
      _highlightRequestSeq++;
    }
    _highlightTimer = Timer(highlightDuration, () {
      // 定时清除：集合移除 + 通知（视图离开高亮样式）。
      if (_highlightMessageIds.isEmpty) {
        return;
      }
      _highlightMessageIds.clear();
      notifyListeners();
    });
  }

  void _onChatEvent(ChatEvent event) {
    switch (event) {
      case ChatToken token:
        _streamingText += token.token;
        _roundStreamedAnything = true;
      case ChatDone():
        _finishRound();
      case ChatInterrupted():
        _notice = _notice ?? '回复已中断';
        _finishRound();
      case ChatError error:
        _notice = _notice ?? error.message;
        _finishRound();
    }
    notifyListeners();
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
      notifyListeners();
    }
  }

  /// 从 DB 重载当前会话消息（不 notify，调用方统一收尾通知）。
  Future<void> _reloadMessages() async {
    final cid = _activeConversationId;
    if (cid == null) {
      _dbMessages = const [];
      _clearInFlight();
      return;
    }
    try {
      _dbMessages = await _messageRepository.getMessages(cid);
    } catch (error) {
      _notice = _notice ?? '加载消息失败: $error';
      _dbMessages = const [];
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

  /// 合成消息 id（负值递减，ListView key 唯一）。F4：仅在消息进入缓冲时
/// （[send] 分配两条合成 id）调用并缓存，不随 messages getter 反复取用。
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