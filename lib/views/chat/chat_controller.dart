/// ChatController — 聊天 tab 编排控制器（入口 / 导航 / 高亮 / 导出 / 消息
/// 组装；回合状态机委托 [ChatRound]，2026-09-07 架构深化候选 5 分离）。
///
/// 语义锚点（桌面，逐字对齐）：
/// - `desktop/frontend/js/stream-session.js`：onToken 累积全文 + streamSettled
///   终态守卫 + 停止（AbortError）写回「已停止」语义 + 普通错误非阻塞上抛
///   （不写入消息缓存）——回合细节见 `chat_round.dart`；
/// - `desktop/frontend/js/chat.js`：发送↔停止两态由 isStreaming 派生（单一
///   事实来源）、重生成仅末条已结算 assistant、错误条独立于消息列表。
///
/// 移动端两级降频（R4 定案）：streaming 期间维护 [streamingText] 纯文本占位
/// 气泡（不进 Markdown 渲染），完成 / 停止 / 断流落库后经 [_reloadMessages]
/// 一次切回 DB 权威列表（assistant 静态 Markdown 由 UI 渲染）。
///
/// 层级：ChangeNotifier 视图模型。唯一依赖 [ChatService] + 会话 / 角色 /
/// 消息仓储抽象（不触碰数据库具体实现 / 平台存储——`layer_boundary_test`
/// 契约）+ [ChatRound]（回合状态机，注入 chatService / messageRepository /
/// notice 槽 / 重载回调，经 notify 回调驱动本控制器通知）。ChatView 经
/// provider 注入本控制器，回合状态与落库可观察状态全部收敛于此，UI 只做
/// 呈现。
///
/// 编辑 / 职责边界：
/// - 回合状态机（send / stop / regenerate / 流订阅 / 合成消息 / 停止竞态
///   F1 / 后台补标 F3b）在 [ChatRound]（深模块，纯搬迁不动行为）；
/// - 本控制器负责：入口列表加载与建会话、导航（open/back）、跳转高亮、
///   导出编排、DB 权威消息列表与展示消息组装、非阻塞 notice 槽。
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
import '../../services/conversation_export_file_exchange.dart';
import '../../services/conversation_export_service.dart';
import '../../services/notice_runner.dart';
import 'chat_round.dart';

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
    this.interrupted = false,
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

  /// 断流截断：UI 侧「回复中断」标记（DB 不写标记；与 [stopped] 区分并列，
  /// 停止/断流为互斥终态不会同时命中）。
  final bool interrupted;

  /// 流式进行中：渲染纯文本 + 闪烁光标（两级降频 streaming 侧）。
  final bool streaming;
}

/// 聊天 tab 编排控制器。
///
/// 用法：装配层构造后经 provider 注入；ChatView 首次挂载时若
/// [hasLoadedEntry] 为 false 则调用 [loadEntry]（幂等）。
class ChatController extends ChangeNotifier {
  /// [chatService] 为回合编排服务（注入 [ChatRound]）；
  /// [conversationRepository] / [characterRepository] /
  /// [messageRepository] 提供列表 / 角色来源 / 消息重载；
  /// [highlightDuration] 为跳转定位高亮的自动清除时长（默认 3s，对齐桌面
  /// `chat.js HIGHLIGHT_DURATION=3000`；测试注入短时长验证定时清除）。
  ///
  /// 导出装配（M4-03）：[exportService] + [exportFileExchange] 为可选依赖——
  /// 不传（既有测试装配不变）时导出方法给出「导出功能未配置」错误 notice，
  /// 不触真正平台通道；装配层（app.dart / chat_test_env）注入真实现或 fake。
  ChatController({
    required ChatService chatService,
    required ConversationRepository conversationRepository,
    required CharacterRepository characterRepository,
    required MessageRepository messageRepository,
    this.highlightDuration = const Duration(seconds: 3),
    ConversationExportService? exportService,
    ConversationExportFileExchange? exportFileExchange,
  })  : _chatService = chatService,
        _conversationRepository = conversationRepository,
        _characterRepository = characterRepository,
        _messageRepository = messageRepository,
        _exportService = exportService,
        _exportFileExchange = exportFileExchange;

  final ChatService _chatService;
  final ConversationRepository _conversationRepository;
  final CharacterRepository _characterRepository;
  final MessageRepository _messageRepository;

  /// 导出纯逻辑服务（M4-01）；可选——null 时导出降级为错误 notice。
  final ConversationExportService? _exportService;

  /// 导出文件 seam（M4-02）；可选——null 时导出降级为错误 notice。
  final ConversationExportFileExchange? _exportFileExchange;

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

  /// 当前会话角色名缓存（assistant/system 气泡语义 label「角色名: 内容」
  /// 用，M6-03 验收 2 语义来源）；入口页 / 会话加载失败为 null。
  String? _activeCharacterName;

  // ── 会话状态（DB 权威列表）──

  List<Message> _dbMessages = const [];

  // ── 回合状态机（委托 ChatRound）──

  // late：字段初始化器需引用实例方法（notifyListeners / _reloadMessages）与
  // 其它 late 字段（_noticeRunner），首次访问时 this 可用（与 NoticeRunner
  // 同款惯用）。
  late final NoticeRunner _noticeRunner =
      NoticeRunner(onChanged: notifyListeners);
  late final ChatRound _round = ChatRound(
    chatService: _chatService,
    messageRepository: _messageRepository,
    noticeRunner: _noticeRunner,
    reloadMessages: _reloadMessages,
    notify: notifyListeners,
  );

  /// 导出进行中（防连点：重复触发被忽略，完成复位）。
  bool _exporting = false;

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
    final conversations = await _noticeRunner.guard(
      op: () => _conversationRepository.listConversations(),
      onError: (e) => '加载对话失败: $e',
    );
    if (conversations == null) {
      // 失败：notice 已折叠（先错者胜），清空列表并复位加载态（不产生
      // 永不结束的加载态 spinner）。
      _conversations = const [];
      _firstCharacter = null;
      _hasLoadedEntry = true;
      _loadingEntry = false;
      notifyListeners();
      return;
    }
    _conversations = conversations;
    final characters = await _noticeRunner.guard(
      op: () => _characterRepository.listCharacters(),
      onError: (e) => '加载对话失败: $e',
    );
    if (characters == null) {
      _firstCharacter = null;
      _hasLoadedEntry = true;
      _loadingEntry = false;
      notifyListeners();
      return;
    }
    _firstCharacter = characters.isEmpty ? null : characters.first.character;
    _hasLoadedEntry = true;
    _loadingEntry = false;
    notifyListeners();
  }

  /// 新建对话：取首个角色；无角色 → [notice] 提示（M2 最小入口，M3 替换）。
  ///
  /// 创建成功随即进入新会话（createConversation 蓝本预插开场白）。
  Future<void> createConversation() async {
    final character = _firstCharacter;
    if (character == null) {
      _noticeRunner.setFirst('请先在角色页创建角色');
      notifyListeners();
      return;
    }
    if (_creatingConversation) {
      return;
    }
    _creatingConversation = true;
    notifyListeners();
    final conversation = await _noticeRunner.guard<Conversation>(
      op: () =>
          _conversationRepository.createConversation(characterId: character.id),
      onError: (e) => '新建对话失败: $e',
    );
    _creatingConversation = false;
    if (conversation == null) {
      // 失败：notice 已折叠（先错者胜），不复位残局。
      notifyListeners();
      return;
    }
    await openConversation(conversation.id);
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
    final character = await _noticeRunner.guard<Character?>(
      op: () => _characterRepository.getCharacter(characterId),
      onError: (e) => '新建对话失败: $e',
    );
    if (character == null) {
      // 角色不存在（guard 成功返回 null，无 notice）或查询失败（已折叠）。
      _noticeRunner.setFirst('角色不存在或已删除：无法新建对话');
      _creatingConversation = false;
      notifyListeners();
      return;
    }
    final conversation = await _noticeRunner.guard<Conversation>(
      op: () =>
          _conversationRepository.createConversation(characterId: characterId),
      onError: (e) => '新建对话失败: $e',
    );
    _creatingConversation = false;
    if (conversation == null) {
      notifyListeners();
      return;
    }
    await openConversation(conversation.id);
  }

  // ── 导航面 ──

  /// 当前是否停留在入口（最近对话列表）页。
  bool get isEntry => _activeConversationId == null;

  /// 当前打开的对话 id；入口页为 null。
  int? get activeConversationId => _activeConversationId;

  /// 当前对话行；null（未打开 / 对话被删）时 UI 回退占位标题。
  Conversation? get activeConversation => _activeConversation;

  /// 当前会话角色名（assistant/system 气泡语义 label「角色名: 内容」用）；
  /// 入口页 / 会话加载失败为 null。
  String? get activeCharacterName => _activeCharacterName;

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
    if (_round.isStreaming) {
      await _round.stop(currentConversationId: _activeConversationId);
    }
    _activeConversationId = conversationId;
    _activeConversation = null;
    _dbMessages = const [];
    _round.resetForNavigation();
    _noticeRunner.clear();
    notifyListeners();
    try {
      // F2：DB 异常收口为 notice（对齐 _reloadMessages / loadEntry 兜底），
      // 不产生未处理异步异常（调用方 fire-and-forget）。
      _activeConversation =
          await _conversationRepository.getConversation(conversationId);
    } catch (error) {
      _noticeRunner.setFirst('加载对话失败: $error');
      _activeConversation = null;
    }
    // M6-03：缓存角色名供气泡语义 label（失败 / 会话缺失 → null，UI 回退）。
    _activeCharacterName = await _resolveActiveCharacterName();
    await _reloadMessages();
    // 入口态/后台流停止的待补「已停止」标记：重进该会话且末条为 assistant
    // → 补标一次（F3b，标记判定不依赖停止时 reload 目标）。
    _round.applyBackgroundStoppedMark(conversationId, _dbMessages);
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
    _activeCharacterName = null;
    _dbMessages = const [];
    _round.resetForNavigation();
    _noticeRunner.clear();
    notifyListeners();
    await loadEntry();
  }

  /// 失效入口缓存（角色被删后调用）：重置 [hasLoadedEntry] 与首角色快照，
  /// 下次进入聊天 tab 时 [loadEntry] 重载——避免「新建对话」沿用已删角色 id
  /// 触发 FK 约束失败（M3-01 增量审核 F1 陈旧缓存缺口修复）。
  void invalidateEntryCache() {
    _hasLoadedEntry = false;
    _firstCharacter = null;
    _noticeRunner.clear();
    notifyListeners();
  }

  // ── 会话面 ──

  /// 解析当前会话角色名（label「角色名: 内容」语义来源）；会话缺失 / 查询
  /// 失败 → null（UI 回退占位，不抛错不弹 notice——装饰性语义面）。
  Future<String?> _resolveActiveCharacterName() async {
    final conversation = _activeConversation;
    if (conversation == null) {
      return null;
    }
    try {
      final character =
          await _characterRepository.getCharacter(conversation.characterId);
      return character?.name;
    } catch (_) {
      return null;
    }
  }

  /// 组装展示消息列表：DB 权威消息 + 在途合成消息（user + 流式/停止占位）。
  ///
  /// 已完成 assistant 由 UI 静态 Markdown 渲染；流式占位为纯文本。合成消息
  /// 状态（在途 user / 占位气泡 / 已停止标记）读自 [ChatRound] 状态面。
  List<ChatUiMessage> get messages {
    final result = <ChatUiMessage>[
      for (final m in _dbMessages)
        ChatUiMessage(
          id: m.id,
          role: m.role,
          content: m.content,
          stopped: _round.isStopped(m.id),
          interrupted: _round.isInterrupted(m.id),
        ),
    ];
    final pendingUser = _round.pendingUserText;
    if (pendingUser != null && pendingUser.isNotEmpty) {
      // 合成 id 在本条进入缓冲时已分配（send），此处纯读（F4：getter 副作用
      // 已移除，ListView key 不再每帧漂移）。
      result.add(ChatUiMessage(
        id: _round.pendingUserSyntheticId!,
        role: Role.user,
        content: pendingUser,
      ));
    }
    if (_round.hasSyntheticAssistant) {
      result.add(ChatUiMessage(
        id: _round.assistantSyntheticId!,
        role: Role.assistant,
        content: _round.streamingText,
        streaming: _round.isStreaming,
        stopped: _round.streamingStopped,
      ));
    }
    return List<ChatUiMessage>.unmodifiable(result);
  }

  // ── 回合面（委托 ChatRound）──

  /// 流式生成进行中（发送↔停止两态判据，单一事实来源）。
  bool get isStreaming => _round.isStreaming;

  /// 重生成进行中（disabled 重生成小图标）。
  bool get isRegenerating => _round.isRegenerating;

  /// 流式占位气泡已累积的纯文本（逐 token 追加）。
  String get streamingText => _round.streamingText;

  /// 非阻塞提示（断流「回复已中断」/ 错误映射文案 / 基础设施失败）；null 无。
  String? get notice => _noticeRunner.notice;

  /// 当前 notice 的身份 seq（F-65④，转发 [NoticeRunner.noticeId]）：新 notice
  /// （含同文案重现值）分配新值，NoticeBanner 据此区分同文案新旧 notice。
  int? get noticeId => _noticeRunner.noticeId;

  /// 关闭当前非阻塞提示。
  void dismissNotice() {
    if (!_noticeRunner.hasNotice) {
      return;
    }
    _noticeRunner.clear();
    notifyListeners();
  }

  /// 发送一条用户消息并开启流式回合（A2 UI 面）。
  ///
  /// 守卫：无会话（其余空文本 / 流式中 / 重生成中 / 终态重载未完成 → 忽略，
  /// 均委托 [ChatRound.send]）。回合编排（落库 user → 组装 → 流式生成）与
  /// 事件处理全部在 [ChatRound]。
  Future<void> send(String text) async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    _round.send(conversationId: cid, text: text);
  }

  /// 停止当前回合（A3 UI 面）：委托 [ChatRound.stop]（取消流订阅 → 已累积
  /// 部分落库 → 重载后末条 assistant 标「已停止」）。
  Future<void> stop() async {
    await _round.stop(currentConversationId: _activeConversationId);
  }

  /// 重生成末条 assistant（A4 UI 面）：委托 [ChatRound.regenerate]（延迟
  /// 删除：失败不删行、旧回复保留，成功重载列表；失败仅 [notice]）。
  Future<void> regenerate() async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    await _round.regenerate(conversationId: cid);
  }

  /// 当前提示是否为「回复已中断」且该提示存在可重试的截断目标——NoticeBanner
  /// 「重试」动作渲染判据（仅截断通知传动作；其它 notice / 零内容断流不传，
  /// 防动作误挂）。判据单一归属 [ChatRound]，本处纯转发（组合逻辑已收敛）。
  bool get hasRetryableInterrupted => _round.hasRetryableInterrupted;

  /// 重试最近一次截断回复（T3 NoticeBanner「重试」，M6-08）：委托
  /// [ChatRound.retryInterrupted]——对截断目标触发 regenerate（replace 语义：
  /// 不新增 user 行）；复用 isRegenerating 防并发与 notice 先错者胜。
  Future<void> retryInterrupted() async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    await _round.retryInterrupted(conversationId: cid);
  }

  // ── 服务/生命周期 ──

  // ── 导出面（M4-03）──

  /// 导出进行中（[exportJson] / [exportMarkdown] 防连点；完成复位）。
  bool get exporting => _exporting;

  /// 导出当前对话为 JSON：服务生成 → seam 写临时文件并分享 → 非阻塞
  /// [notice] 反馈（成功 → seam 文案；对话不存在 → 「对话不存在」不触 seam；
  /// seam/服务异常 → 「导出失败: {e}」）。
  Future<void> exportJson() => _export(_exportService?.exportJson);

  /// 导出当前对话为 Markdown（同上，走 `exportMarkdown`）。
  Future<void> exportMarkdown() => _export(_exportService?.exportMarkdown);

  /// 导出编排公共腿：服务生成 → seam 分享，全程经非阻塞 notice 反馈。
  ///
  /// [produce] 为服务导出入口（json / markdown 分腿）；[exporting] 防连点
  /// 复用 [_exporting] 标志，导出期间重复触发被忽略；对话不存在 →
  /// [produce] 返回 null → notice「对话不存在」且**不触 seam**（归零副作用）。
  Future<void> _export(
    Future<ConversationExportResult?> Function(int conversationId)? produce,
  ) async {
    final cid = _activeConversationId;
    if (cid == null) {
      return; // 菜单仅在会话态出现；防御性兜底（零副作用）。
    }
    final service = _exportService;
    final seam = _exportFileExchange;
    if (service == null || seam == null || produce == null) {
      _noticeRunner.setFirst('导出功能未配置');
      notifyListeners();
      return;
    }
    if (_exporting) {
      return; // 防连点：导出进行中重复触发被忽略。
    }
    _exporting = true;
    notifyListeners();
    try {
      final result = await _noticeRunner.guard<ConversationExportResult?>(
        op: () => produce(cid),
        onError: (e) => '导出失败: $e',
      );
      if (result == null) {
        // 对话不存在（服务成功返回 null）或失败（notice 已折叠）。
        _noticeRunner.setFirst('对话不存在');
        return;
      }
      final message = await _noticeRunner.guard<String>(
        op: () => seam.exportFile(result),
        onError: (e) => '导出失败: $e',
      );
      if (message != null) {
        _noticeRunner.set(message);
      }
    } finally {
      _exporting = false;
      notifyListeners();
    }
  }

  /// 释放时取消在途流式订阅（[ChatRound.dispose]，ChatService 停止语义：已
  /// 累积部分落库）与高亮定位定时器，并清空高亮状态（防泄漏 / 防「notify
  /// after dispose」）。
  @override
  void dispose() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _highlightMessageIds.clear();
    _round.dispose();
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

  /// 从 DB 重载当前会话消息（[ChatRound] 的 reloadMessages 回调；不 notify，
  /// 调用方统一收尾通知），返回最新列表供「已停止」标记判定。
  ///
  /// 只置 [_dbMessages]：null 会话（入口态）清空列表即可——在途合成清理由
  /// [ChatRound] 调用方（如 [_onStreamDone]）各自负责，本回调不越权。
  Future<List<Message>> _reloadMessages() async {
    final cid = _activeConversationId;
    if (cid == null) {
      _dbMessages = const [];
      return _dbMessages;
    }
    try {
      _dbMessages = await _messageRepository.getMessages(cid);
    } catch (error) {
      _noticeRunner.setFirst('加载消息失败: $error');
      _dbMessages = const [];
    }
    return _dbMessages;
  }
}