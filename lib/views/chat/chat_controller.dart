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

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

// 只引出 drift 生成的类型化行类（Message / Conversation / Character）与
// 部分更新的 companion（ConversationsCompanion），不触碰数据层具体实现标识符
// （layer_boundary_test：视图层不得引用数据层具体实现）。
import '../../data/database/app_database.dart'
    show Message, Conversation, Character, ConversationsCompanion;
import '../../data/database/tables.dart' show Role;
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../services/branch/branch_service.dart';
import '../../services/branch/branch_snapshot.dart';
import '../../services/chat_service.dart';
import '../../services/conversation_export_file_exchange.dart';
import '../../services/conversation_export_service.dart';
import '../../services/llm/errors.dart' show DomainError;
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
    this.swipeCount = 0,
    this.activeSwipeIndex = 0,
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

  /// 候选数（`message_swipes` 行数；无候选行 = 0，不变量退化态）。候选控制条
  /// 渲染判据：> 1 才渲染（单选 / 无候选不渲染，对齐桌面 MS-2 契约锁）。
  final int swipeCount;

  /// 当前激活候选 index（[content] 即该候选内容；无候选行时恒 0）。
  final int activeSwipeIndex;
}

/// 分支来源标记数据（[ChatController.branchSources] 项）：父会话标题 + 锚
/// 消息预览。会话列表行「分支自「父标题」· 锚预览」标记渲染用。
class BranchSource {
  const BranchSource({required this.parentTitle, required this.anchorPreview});

  /// 父会话标题。
  final String parentTitle;

  /// 锚消息内容预览（截断；父/锚缺失时为空串，降级不显示预览）。
  final String anchorPreview;
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
  ///
  /// 分支装配（BR-02）：[branchService] 为可选依赖——不传时分支 / 快照导入
  /// 导出方法给出「功能未配置」notice（既有测试装配不变）；装配层注入真实现。
  ChatController({
    required ChatService chatService,
    required ConversationRepository conversationRepository,
    required CharacterRepository characterRepository,
    required MessageRepository messageRepository,
    this.highlightDuration = const Duration(seconds: 3),
    ConversationExportService? exportService,
    ConversationExportFileExchange? exportFileExchange,
    BranchService? branchService,
  })  : _chatService = chatService,
        _conversationRepository = conversationRepository,
        _characterRepository = characterRepository,
        _messageRepository = messageRepository,
        _exportService = exportService,
        _exportFileExchange = exportFileExchange,
        _branchService = branchService;

  final ChatService _chatService;
  final ConversationRepository _conversationRepository;
  final CharacterRepository _characterRepository;
  final MessageRepository _messageRepository;

  /// 导出纯逻辑服务（M4-01）；可选——null 时导出降级为错误 notice。
  final ConversationExportService? _exportService;

  /// 导出文件 seam（M4-02）；可选——null 时导出降级为错误 notice。
  final ConversationExportFileExchange? _exportFileExchange;

  /// 分支服务（BR-02）；可选——null 时分支 / 快照导入导出降级为「功能未配置」
  /// notice（装配层注入真实现；测试注入真实 / 门控子类）。
  final BranchService? _branchService;

  /// 跳转定位高亮的自动清除时长（对齐桌面 `HIGHLIGHT_DURATION=3000`）。
  final Duration highlightDuration;

  // ── 入口状态 ──

  bool _hasLoadedEntry = false;
  bool _loadingEntry = false;
  List<ConversationWithCount> _conversations = const [];
  List<Character> _characters = const [];
  int? _selectedCharacterId;
  bool _creatingConversation = false;

  // ── 导航状态 ──

  int? _activeConversationId;
  Conversation? _activeConversation;

  /// 当前会话角色名缓存（assistant/system 气泡语义 label「角色名: 内容」
  /// 用，M6-03 验收 2 语义来源）；入口页 / 会话加载失败为 null。
  String? _activeCharacterName;

  // ── 会话状态（DB 权威列表）──

  List<Message> _dbMessages = const [];

  /// 候选数缓存（消息 id → swipes 行数），随 [_reloadMessages] 刷新（MS-05：
  /// 控制条渲染判据的数据面，与 [_dbMessages] 同生命周期，保证「列表与计数
  /// 同帧一致」）。
  ///
  /// 数据层无批量计数读面（本票文件范围为视图 + 控制器），故重载时对会话内
  /// assistant 消息逐条 [MessageRepository.listSwipes] 计数；重载频率为用户
  /// 操作级、查询为本地主键索引读，代价可接受。消息行自带的
  /// `activeSwipeIndex` 无需查询，直接随行读取。
  Map<int, int> _swipeCounts = const {};

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

  /// 分支编排进行中（[branchFromMessage] 防连点：重复触发被忽略，完成复位）。
  bool _branching = false;

  /// 快照导入进行中（[importSnapshot] 防连点：重复触发被忽略，完成复位）。
  bool _importing = false;

  /// 分支来源标记缓存（会话 id → 父标题 + 锚消息预览；随 [loadEntry] 刷新）。
  Map<int, BranchSource> _branchSources = const {};

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

  /// 入口角色列表（全量，`updated_at` 倒序，随 [loadEntry] 刷新）。
  List<Character> get characters => _characters;

  /// 当前选中的角色 id；无角色或尚未加载时为 null。
  int? get selectedCharacterId => _selectedCharacterId;

  /// 是否存在可用于「新建对话」的选中角色。
  bool get canCreateConversation => _selectedCharacterId != null;

  /// 无选中角色时的禁用提示文案（[canCreateConversation] false 时非空）。
  String? get createDisabledReason =>
      _selectedCharacterId == null ? '请先在角色页创建角色' : null;

  /// 「新建对话」提交中（防连点重复建会话）。
  bool get creatingConversation => _creatingConversation;

  /// 加载最近对话 + 全部角色（新建来源 + 角色选择条；入口导航每次回来都调用
  /// 以刷新）。
  ///
  /// 选中态不跨启动持久化（U-1 假设）：[selectedCharacterId] 为空或已不在角色
  /// 列表时回退默认选中首角色；角色为空时选中态置 null（新建禁用）。
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
      _characters = const [];
      _selectedCharacterId = null;
      _branchSources = const {};
      _hasLoadedEntry = true;
      _loadingEntry = false;
      notifyListeners();
      return;
    }
    _conversations = conversations;
    // 分支来源标记随列表一起刷新（逐条失败降级不显示，不阻塞列表加载）。
    _branchSources = await _collectBranchSources(conversations);
    final characters = await _noticeRunner.guard(
      op: () => _characterRepository.listCharacters(),
      onError: (e) => '加载对话失败: $e',
    );
    if (characters == null) {
      _characters = const [];
      _selectedCharacterId = null;
      _hasLoadedEntry = true;
      _loadingEntry = false;
      notifyListeners();
      return;
    }
    _characters = [for (final entry in characters) entry.character];
    _selectedCharacterId = _resolveSelectedCharacterId();
    _hasLoadedEntry = true;
    _loadingEntry = false;
    notifyListeners();
  }

  /// 计算有效选中角色 id：现有选中仍在角色列表则保留，否则回退首角色
  /// （列表为空 → null，新建禁用）。
  int? _resolveSelectedCharacterId() {
    final current = _selectedCharacterId;
    if (current != null && _characters.any((c) => c.id == current)) {
      return current;
    }
    return _characters.isEmpty ? null : _characters.first.id;
  }

  /// 新建对话：以 [selectedCharacterId] 建会话并直达；无选中角色 → [notice]
  /// 提示（U-1 角色选择入口）。
  ///
  /// 委托 [createConversationFor]：防连点标志 [_creatingConversation] 单一归属
  /// 后者，不再本方法各自置位/复位（避免双重重置）。创建成功随即进入新会话
  /// （createConversation 蓝本预插开场白）。
  Future<void> createConversation() async {
    final characterId = _selectedCharacterId;
    if (characterId == null) {
      _noticeRunner.setFirst('请先在角色页创建角色');
      notifyListeners();
      return;
    }
    await createConversationFor(characterId);
  }

  /// 以指定角色建会话并直达（M3-01 角色卡「开始对话」入口；U-1 入口「新建
  /// 对话」的委托目标）。
  ///
  /// 会话归属显式传入的 [characterId]，不依赖入口选中态快照；角色不存在 / 已
  /// 删除 → [notice] 提示且停留入口，零残留会话。[createConversation] 以选中
  /// 角色委托本方法；[_creatingConversation] 防连点标志单一归属本处（任一建
  /// 会话流程进行中互相忽略）。
  ///
  /// [greeting] / [presetDialogue]（NPD-03）同形透传 [ConversationRepository
  /// .createConversation]：greeting 三态（null= first_mes 零回归 / 指定文本 /
  /// 显式空串=无开场白），presetDialogue 快照固化。三层调用语义：
  /// 无选中角色 → [createConversation]（本方法不触达）；指定角色（角色卡
  /// 「开始对话」）→ 不传新参数（first_mes 零回归）；选择 UI（新建对话
  /// 面板）→ 「无开场白」传 `''`、「默认」传 null、备选文本传 String。
  Future<void> createConversationFor(
    int characterId, {
    Object? greeting,
    String? presetDialogue,
  }) async {
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
      op: () => _conversationRepository.createConversation(
        characterId: characterId,
        greeting: greeting,
        presetDialogue: presetDialogue,
      ),
      onError: (e) => '新建对话失败: $e',
    );
    _creatingConversation = false;
    if (conversation == null) {
      notifyListeners();
      return;
    }
    await openConversation(conversation.id);
  }

  /// 切换入口角色选择条选中态（U-1）。
  ///
  /// 仅接受当前 [characters] 中存在的 id（不存在 → 零副作用，不破坏选中态）；
  /// 同 id 幂等（不重复通知）。
  void selectCharacter(int characterId) {
    if (_selectedCharacterId == characterId) {
      return;
    }
    if (!_characters.any((c) => c.id == characterId)) {
      return;
    }
    _selectedCharacterId = characterId;
    notifyListeners();
  }

  /// 重命名会话（U-1）：委托 [ConversationRepository.updateConversation]
  /// 部分更新标题落库，随后 [loadEntry] 刷新列表。
  ///
  /// 会话不存在 → [notice]「对话不存在」；仓储异常 → notice 折叠（先错者胜）。
  Future<void> renameConversation(int conversationId, String title) async {
    final updated = await _noticeRunner.guard<Conversation?>(
      op: () => _conversationRepository.updateConversation(
        conversationId,
        ConversationsCompanion(title: Value(title)),
      ),
      onError: (e) => '重命名失败: $e',
    );
    if (updated == null) {
      _noticeRunner.setFirst('对话不存在');
    }
    await loadEntry();
  }

  /// 保存当前会话的采样参数覆盖（SP-02）：经
  /// [ConversationRepository.updateConversation] 部分更新写 conversations 四列
  /// （topP / presencePenalty / frequencyPenalty / maxTokens），四参数可空
  /// 三态：
  /// - 非 null → 显式覆盖，`Value(x)` 落列；
  /// - null → 清除覆盖（沿用全局/默认），`Value(null)` 显式写 NULL——
  ///   契约锁「保存后 Conversations 列值 = 显式覆盖值 或 NULL」（drift
  ///   UpdateCompanion 显式 `Value(null)` 会写 SQL NULL，非忽略）。
  ///
  /// 成功 → [activeConversation] 刷新为仓储回读行（弹层回显立即生效）；
  /// 会话不存在（已删除）→ [notice]「对话不存在」（guard，不崩溃）；仓储
  /// 异常 → notice 折叠（先错者胜）。入口态（无活动会话，UI 不渲染入口）→
  /// 防御性 no-op。
  Future<void> saveConversationSampling({
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
    int? maxTokens,
  }) async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    final updated = await _noticeRunner.guard<Conversation?>(
      op: () => _conversationRepository.updateConversation(
        cid,
        ConversationsCompanion(
          topP: Value(topP),
          presencePenalty: Value(presencePenalty),
          frequencyPenalty: Value(frequencyPenalty),
          maxTokens: Value(maxTokens),
        ),
      ),
      onError: (e) => '保存采样参数失败: $e',
    );
    if (updated == null) {
      _noticeRunner.setFirst('对话不存在');
      return;
    }
    _activeConversation = updated;
    notifyListeners();
  }

  /// 删除会话（U-1）：委托 [ConversationRepository.deleteConversation]
  /// 落库，随后 [loadEntry] 刷新列表。
  ///
  /// 会话不存在（仓储返回 false）零副作用，刷新后列表自然不变；仓储异常 →
  /// notice 折叠（先错者胜）。
  Future<void> removeConversation(int conversationId) async {
    await _noticeRunner.guard<bool>(
      op: () => _conversationRepository.deleteConversation(conversationId),
      onError: (e) => '删除失败: $e',
    );
    await loadEntry();
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

  /// 失效入口缓存（角色被删后调用）：重置 [hasLoadedEntry] 与角色列表/选中态
  /// 快照，下次进入聊天 tab 时 [loadEntry] 重载——避免「新建对话」沿用已删角色
  /// id 触发 FK 约束失败（M3-01 增量审核 F1 陈旧缓存缺口修复）。
  void invalidateEntryCache() {
    _hasLoadedEntry = false;
    _characters = const [];
    _selectedCharacterId = null;
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
  /// 状态（在途 user / 占位气泡 / 已停止标记）读自 [ChatRound] 状态面；候选面
  /// （[ChatUiMessage.swipeCount] / [ChatUiMessage.activeSwipeIndex]）读自
  /// [_swipeCounts] 缓存（随 reload 刷新）与消息行的 `activeSwipeIndex` 列
  /// （MS-05：控制条渲染判据）。
  List<ChatUiMessage> get messages {
    final result = <ChatUiMessage>[
      for (final m in _dbMessages)
        ChatUiMessage(
          id: m.id,
          role: m.role,
          content: m.content,
          stopped: _round.isStopped(m.id),
          interrupted: _round.isInterrupted(m.id),
          swipeCount: _swipeCounts[m.id] ?? 0,
          activeSwipeIndex: m.activeSwipeIndex,
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

  /// 重生成末条 assistant（A4 UI 面）：委托 [ChatRound.regenerate]（候选
  /// 追加：消息行保留、旧回复保留为候选，成功重载列表；失败仅 [notice]）。
  Future<void> regenerate() async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    await _round.regenerate(conversationId: cid);
  }

  /// 继续生成末条 assistant（MS-02 入口，UI 挂点留 05 票）：委托
  /// [ChatRound.continueReply]（候选追加 + active 置激活；空续写 -1 哨兵
  /// no-op；防并发与 notice 单源在回合层）。
  Future<void> continueReply() async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    await _round.continueReply(conversationId: cid);
  }

  /// 切换 [messageId] 的激活候选（MS-02 入口，UI 挂点留 05 票）：委托
  /// [ChatRound.switchSwipe]（切换后 reload 反映新 active；越界/不存在 →
  /// notice 单源文案）。
  Future<void> switchSwipe(int messageId, int index) async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    await _round.switchSwipe(
      conversationId: cid,
      messageId: messageId,
      index: index,
    );
  }

  /// 删除单条消息（MS-03 入口，UI 挂点留 05 票）：委托 [ChatRound.deleteMessage]
  /// （删 user 截断后续、删 assistant 仅删该条；成功后 reload 列表并结算
  /// 被删范围内的截断标记）。
  Future<void> deleteMessage(int messageId) async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    await _round.deleteMessage(conversationId: cid, messageId: messageId);
  }

  /// 编辑重发（MS-03 入口，UI 挂点留 05 票）：委托 [ChatRound.editMessage]
  /// （仅 user；就地替换 + 截断后续 + 重新生成；失败保留已替换已截断状态、
  /// notice 单源文案）。
  Future<void> editMessage(int messageId, String newContent) async {
    final cid = _activeConversationId;
    if (cid == null) {
      return;
    }
    await _round.editMessage(
      conversationId: cid,
      messageId: messageId,
      newContent: newContent,
    );
  }

  /// 任意回合操作进行中（聚合状态面，UI 操作入口可达性判据）：流式 / 生成类
  /// / 终态重载窗口 / 瞬时变更任一进行中即 true（转发 [ChatRound.isBusy]）。
  bool get isBusy => _round.isBusy;

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
  /// [produce] 为服务导出入口（json / markdown / 分支快照分腿）；
  /// [exporting] 防连点复用 [_exporting] 标志，导出期间重复触发被忽略；
  /// 对话不存在 → [produce] 返回 null → notice「对话不存在」且**不触 seam**
  /// （归零副作用）。
  Future<void> _export(
    Future<ConversationExportResult?> Function(int conversationId)? produce,
  ) async {
    final cid = _activeConversationId;
    if (cid == null) {
      return; // 菜单仅在会话态出现；防御性兜底（零副作用）。
    }
    final seam = _exportFileExchange;
    if (seam == null || produce == null) {
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

  // ── 分支面（BR-02）──

  /// 分支编排进行中（[branchFromMessage] 防连点：重复触发被忽略）。
  bool get branching => _branching;

  /// 快照导入进行中（[importSnapshot] 防连点：重复触发被忽略）。
  bool get importing => _importing;

  /// 分支来源标记（会话 id → 父标题 + 锚消息预览；随 [loadEntry] 刷新）。
  ///
  /// 仅 parent 引用存活的会话有标记；父已删（置空策略——parent/锚置空、
  /// branch_title 保留，BR-01 契约）由视图按 [Conversation.branchTitle]
  /// 降级「分支」标记。
  Map<int, BranchSource> get branchSources => _branchSources;

  /// 从当前会话的 [messageId] 处派生分支并直达新会话（BR-02 消息菜单「分支」）。
  ///
  /// 编排：经 [BranchService.branchFromMessage]（校验源+锚 → 截断快照含锚 →
  /// 重建 → 记录 parent/锚/分支名 → 新会话）；成功 → [openConversation] 直达
  /// 新分支会话（内部处理在途流式停止）；失败 → notice 单源文案
  /// （[_branchErrorText]：领域错误自带文案 / 「分支失败: {e}」兜底）。
  /// 守卫：入口态 / 分支进行中（[_branching] 防连点）/ 回合忙态
  /// （[_round.isBusy] 复用 guard 腿）→ 零副作用忽略。
  Future<void> branchFromMessage(int messageId) async {
    final cid = _activeConversationId;
    if (cid == null || _branching || _round.isBusy) {
      return;
    }
    final branch = _branchService;
    if (branch == null) {
      _noticeRunner.setFirst('分支功能未配置');
      notifyListeners();
      return;
    }
    _branching = true;
    notifyListeners();
    try {
      final result = await _noticeRunner.guard<Conversation>(
        op: () => branch.branchFromMessage(cid, messageId),
        onError: _branchErrorText,
      );
      if (result != null) {
        await openConversation(result.id);
      }
    } finally {
      _branching = false;
      notifyListeners();
    }
  }

  /// 导入分支快照为克隆会话并直达（BR-02 顶栏「导入分支快照」）。
  ///
  /// 编排：文件 seam 选 `.json`（[ConversationExportFileExchange.importSnapshot]）
  /// → 解析校验（未知版本 / 格式无效拒绝，SR-30 文案映射）→
  /// [BranchService.cloneFromSnapshot] 重建（消息/候选/世界书条目复制）→
  /// [openConversation] 直达新会话。用户取消 → 零副作用；畸形文件 / 未知版本
  /// → notice「快照格式无效」/「快照版本不支持」，不崩溃、不影响现有会话。
  /// 守卫：入口态 / 导入进行中（[_importing] 防连点）/ 回合忙态 → 忽略。
  Future<void> importSnapshot() async {
    final cid = _activeConversationId;
    if (cid == null || _importing || _round.isBusy) {
      return;
    }
    final branch = _branchService;
    final seam = _exportFileExchange;
    if (branch == null || seam == null) {
      _noticeRunner.setFirst('导入功能未配置');
      notifyListeners();
      return;
    }
    _importing = true;
    notifyListeners();
    try {
      final snapshot = await _noticeRunner.guard<BranchSnapshot?>(
        op: () => seam.importSnapshot(),
        onError: _snapshotImportErrorText,
      );
      if (snapshot == null) {
        return; // 用户取消 / 解析失败（notice 已折叠）→ 零副作用。
      }
      final conversation = await _noticeRunner.guard<Conversation>(
        op: () => branch.cloneFromSnapshot(snapshot),
        onError: _snapshotImportErrorText,
      );
      if (conversation != null) {
        await openConversation(conversation.id);
      }
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  /// 导出当前会话为分支快照（`{title}-branch.json`；复用 M4 分享 seam）。
  ///
  /// 经 [BranchService.exportSnapshot] 产出 [ConversationExportResult]（文件名
  /// 净化 + JSON 载荷）→ seam 写临时文件并分享 → notice seam 文案；对话不存在
  /// → 「对话不存在」且不触 seam；branchService 未装配 → 「导出功能未配置」。
  Future<void> exportSnapshot() => _export(_branchService?.exportSnapshot);

  /// 分支失败 notice 文案单源（BR-02 验收 2）：领域错误 → 其自带文案
  /// （「对话不存在」/「消息不存在」）；其余 → 「分支失败: {e}」兜底。
  static String _branchErrorText(Object error) {
    if (error is DomainError) {
      return error.message;
    }
    return '分支失败: $error';
  }

  /// 快照导入失败 notice 文案单源（BR-02 验收 5/6，SR-30 文案映射，不泄露
  /// 解析细节）：未知版本 → 「快照版本不支持」；格式无效 →
  /// 「快照格式无效」；领域错误 → 其自带文案；其余 → 「导入快照失败: {e}」。
  static String _snapshotImportErrorText(Object error) {
    if (error is BranchSnapshotUnsupportedVersionError) {
      return '快照版本不支持';
    }
    if (error is InvalidBranchSnapshotError) {
      return '快照格式无效';
    }
    if (error is DomainError) {
      return error.message;
    }
    return '导入快照失败: $error';
  }

  /// 收集分支来源标记（父标题 + 锚消息预览）；逐条失败降级为不显示标记并记
  /// 日志——标记是展示增强面，单条读取异常不阻塞会话列表加载。
  Future<Map<int, BranchSource>> _collectBranchSources(
    List<ConversationWithCount> conversations,
  ) async {
    final sources = <int, BranchSource>{};
    for (final item in conversations) {
      final conversation = item.conversation;
      final parentId = conversation.parentConversationId;
      final anchorId = conversation.branchFromMessageId;
      if (parentId == null || anchorId == null) {
        continue;
      }
      try {
        final parent = await _conversationRepository.getConversation(parentId);
        if (parent == null) {
          continue; // 父引用残留但已删（删除路径已置空，理论不可达）：降级不显示。
        }
        final anchor = await _messageRepository.messageById(parentId, anchorId);
        sources[conversation.id] = BranchSource(
          parentTitle: parent.title,
          anchorPreview: anchor == null ? '' : _anchorPreview(anchor.content),
        );
      } catch (error) {
        debugPrint('分支来源标记读取失败（降级不显示）: $error');
      }
    }
    return sources;
  }

  /// 锚消息预览：首行去空白后截断到 [maxAnchorPreviewChars]（列表副标用，
  /// 超长以省略号收尾）。
  static String _anchorPreview(String content) {
    final line = content.split('\n').first.trim();
    if (line.length <= maxAnchorPreviewChars) {
      return line;
    }
    return '${line.substring(0, maxAnchorPreviewChars)}…';
  }

  /// 锚消息预览截断上限（列表副标单行空间，截断以省略号收尾）。
  static const int maxAnchorPreviewChars = 14;

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
  /// 只置 [_dbMessages]（附 [swipeCounts] 计数缓存）：null 会话（入口态）清空
  /// 列表即可——在途合成清理由 [ChatRound] 调用方（如 [_onStreamDone]）各自
  /// 负责，本回调不越权。
  Future<List<Message>> _reloadMessages() async {
    final cid = _activeConversationId;
    if (cid == null) {
      _dbMessages = const [];
      _swipeCounts = const {};
      return _dbMessages;
    }
    try {
      _dbMessages = await _messageRepository.getMessages(cid);
    } catch (error) {
      _noticeRunner.setFirst('加载消息失败: $error');
      _dbMessages = const [];
    }
    _swipeCounts = await _loadSwipeCounts();
    return _dbMessages;
  }

  /// 读取当前会话内 assistant 消息的候选数（[ChatUiMessage.swipeCount] 来源）。
  ///
  /// 只扫 assistant 行（候选仅由 regenerate / continueReply 挂在 assistant 上）；
  /// 单条读取失败按「无候选」降级并记日志——候选计数是展示增强面，不得因局部
  /// 读取异常阻塞消息列表呈现（列表本体已在调用方落位）。
  Future<Map<int, int>> _loadSwipeCounts() async {
    final counts = <int, int>{};
    for (final message in _dbMessages) {
      if (message.role != Role.assistant) {
        continue;
      }
      try {
        counts[message.id] =
            (await _messageRepository.listSwipes(message.id)).length;
      } catch (error) {
        debugPrint('候选数读取失败（按无候选处理）: $error');
      }
    }
    return counts;
  }
}