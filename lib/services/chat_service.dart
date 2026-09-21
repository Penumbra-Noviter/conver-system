/// ChatService — 一次聊天回合的编排大脑（发送 / 停止 / 重生成 / 断流 / 错误映射）。
///
/// 桌面权威源（只读，语义锚点，逐字对齐）：
/// - `desktop/backend/app/services/chat.py`（prepare_chat / stream_reply /
///   regenerate_chat / chat_error_response）
/// - `desktop/backend/app/services/message.py`（auto_insert_greeting /
///   build_message_list / delete_messages_from）
/// - `desktop/backend/app/services/llm/resolver.py`（Key 解析链 / ApiKeyMissing 文案）
/// - `desktop/backend/app/services/error_mapping.py`（llm_error_response /
///   domain_error_response 映射表）
///
/// 服务层三层划分中的「回合编排」层：只依赖 [LLMProvider] / [LLMProviderFactory]
/// 抽象与既有仓储（Message / Conversation / Character / Settings），不触碰具体
/// Provider。错误映射纯函数（[llmErrorResponse] / [domainErrorResponse]）与
/// 编排同文件，供 UI（T04）与测试复用，逐字对齐桌面单一映射入口。
///
/// ## 发送链路（streamReply）
/// autoGreeting 零消息守卫 → 落库 user → buildMessages 组装（角色字段映射
/// CharacterData + 滑窗 sliding_window_rounds）→ provider 解析（Key 解析链经
/// 设置仓储；空 → ApiKeyMissingError）→ streamGenerate → 流结束落库完整
/// assistant。零 token 空流不落库；LLM 业务错误不落部分内容（F-45）。
///
/// ## 停止（A3）
/// 调用方取消返回流的订阅 → 生成器 [finally] 兜底把已累积部分落库；无部分
/// 内容 → 仅保留已发 user。DB 存纯文本部分内容，不写「已停止」标记（UI 侧标）。
/// **停止完成契约**：取消订阅的完成 Future 保证本轮在途 user 写尝试已结算
/// （成功落库 / 回合已终态不再写）——`_StreamRunState.userWriteSettled` 门 +
/// `_runStreamReply` 写后 complete + 终态 finally 兜底。
///
/// ## 重生成（A4，候选追加语义，MS-02）
/// 目标 = 末条 assistant（缺省，PK 锚定）；组装锚定 target.id、走
/// `append_current_input=False`（无幽灵 user）；先校验/组装 + non-streaming
/// 生成（网络在事务外），成功后 `MessageRepository.addSwipe` **候选追加**（候选
/// 0 = 原回复播种、新回复 = index 1、make_active 置激活）——消息数不变
/// （1 assistant + N 候选），无「有界删旧」（F1 退化为并发写保护，F4 守卫承保）；
/// 失败零落库、旧消息保留。
///
/// ## 续写（MS-02，continueReply）
/// 目标 = 末条 assistant（对齐桌面「末条须为 AI 回复」）；组装历史**含目标**
/// （`id <= target.id`，桌面 history_limit 含边界）+ 尾随 **user** 触发消息
/// （续写指令 + 原消息末段锚，不落库）；成功后候选追加
/// 「原 active 内容 + 续写片段」置激活；失败 / 空续写零落库（空续写 no-op，
/// `swipeIndex = -1` 哨兵）。
///
/// ## 编辑重发（MS-03，editAndRegenerate）
/// 仅 user 消息：目标解析（归属 + role 校验，失败零副作用）→ 单事务
/// 「就地替换 content + 物理截断后续（候选随 FK CASCADE）」→ non-streaming
/// 生成新 assistant 消息（候选 0 = 回复本体，swipeIndex = 0，不实际
/// addSwipe）。**失败边界锁定**（spec §4.3）：生成失败保留「已替换 + 已截断」
/// 状态——截断后状态即未来状态，用户可再 regenerate；与桌面「失败回滚
/// 零落库」的差异为移动端拍板语义。
///
/// ## 删除（MS-03，deleteMessage）
/// 角色感知：删 user → 截断含自身及后续（候选级联）；删 assistant /
/// system 等非 user → 仅删该条 + swipes 级联；InnerThoughts CASCADE、
/// ProactivePlans.messageId setNull 由 FK 承保（SR-28 消费者级断言锁定）。
/// 目标归属校验：不存在 / 跨对话 → [MessageNotFoundError] 零副作用。
///
/// ## 候选切换（MS-01，switchSwipe，F-140 契约补位）
/// 归属校验与 [deleteMessage] 同构（不存在 / 跨对话 → [MessageNotFoundError]）；
/// 越界 [index] 由仓库层原样上抛 [SwipeIndexOutOfRangeError]（服务层零捕获、
/// 零重映射）。成功返回切换后的 [Message]（content 已被覆写为选中候选）。
///
/// ## 断流（A5）
/// 流终止未到终态（连接异常 / 未收终态帧）→ 已累积部分落库 + 非阻塞
/// [ChatInterrupted]「回复已中断」。R3 seam 契约：wire 层（T02）把**连接建立
/// 段**传输失败（DNS / 拒连 / 连接超时 / 响应头前断——stream_wire.dart 连接
/// 相位收敛为 [ConnectPhaseInterruptedError]）与**读取段**断连（EOF 未到终态 /
/// 连接重置 / idle 超时——读取相位收敛为 [ReadPhaseInterruptedError]）统一
/// 编码为 [LLMConnectionInterruptedError] 伞下两叶子（errors.dart 共享）；
/// 业务错误（Auth / RateLimit / Timeout / ContentFilter 等）为其它的子类/
/// 基类，不算断流。故 [_isConnectionDrop] 以「伞下判型」即断流判定。
///
/// ## 连接阶段自动重试（M6-06，仅聊天链路）
/// 连接建立阶段失败（[ConnectPhaseInterruptedError]，未收到状态码、确定未
/// 产生服务端生成）在「首 token 前」窗口内自动重试（缺省 2 次，指数退避
/// [1s, 2s]；[connectRetryDelays] 可注入）。**不重试**：已收到状态码
/// （4xx/5xx，含 Auth / RateLimit / Timeout / BadRequest / ContentFilter 映射）
/// 与读取相位中断（已收响应头后断流，含首 token 前 idle——行为变更点 B1）。
/// user 行在落库后才调用 provider，重试仅重放 provider 段、不重复落库；重试
/// 耗尽 → 既有断流语义收束。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../data/database/app_database.dart';
import '../data/database/tables.dart' show Role;
import '../data/repositories/character_repository.dart';
import '../data/repositories/companion_repository.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/lorebook_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'companion/relationship_service.dart';
import 'companion/thought_service.dart';
import 'llm/credentials_resolver.dart';
import 'llm/errors.dart';
import 'llm/llm_provider.dart';
import 'llm/prompt.dart';
import 'llm/temperature.dart';
import 'lorebook/lorebook_engine.dart';
import 'memory/memory_prompt.dart';
import 'memory/memory_service.dart';
import 'template_vars.dart';

/// 流式回合的产出事件（sealed：token / done / interrupted / error）。
sealed class ChatEvent {
  const ChatEvent();
}

/// 一个已生成的 token（UI 追加到打字机占位气泡）。
final class ChatToken extends ChatEvent {
  const ChatToken(this.token);

  /// 本步 token 文本。
  final String token;
}

/// 流正常完成（provider 侧收到终态帧）。
///
/// [messageId] 为完整回复落库后的消息 id；**零 token 空流不落库**，此时为 null。
final class ChatDone extends ChatEvent {
  const ChatDone(this.messageId);

  /// 落库后的 assistant 消息 id；空流时为 null。
  final int? messageId;
}

/// 断流：流终止未到终态（连接异常 / 未收终态帧）。
///
/// 已累积部分落库（非阻塞「回复已中断」）；[messageId] 为部分落库的消息 id，
/// 无部分内容时为 null（不落空 assistant）。
final class ChatInterrupted extends ChatEvent {
  const ChatInterrupted(this.messageId);

  /// 部分内容落库后的消息 id；无部分内容时为 null。
  final int? messageId;
}

/// 领域 / LLM 业务错误 → 用户可见文案（不落部分内容，F-45）。
final class ChatError extends ChatEvent {
  const ChatError(this.message);

  /// 经 [llmErrorResponse] / [domainErrorResponse] 映射的用户可见文案。
  final String message;
}

/// 重生成结果（桌面 `ChatResponse` 对应物：reply / message_id / conversation_id）。
///
/// MS-02 候选语义扩展：`messageId` 与 `replacedMessageId` 均为**候选归属
/// 消息 id**（= 目标 assistant 行；候选追加不删行），新增 [swipeIndex]（新候选
/// index）。既有字段名保留保证调用点编译链不断（chat_round.dart
/// `_regenerateTarget` 以 [replacedMessageId] 结算截断标记仍成立——旧 id 不再
/// 被删，结算键恒命中）。MS-04 起 UI 结算键 = `(messageId, swipeIndex)`。
class RegenerateResult {
  const RegenerateResult({
    required this.reply,
    required this.messageId,
    required this.replacedMessageId,
    required this.conversationId,
    required this.swipeIndex,
  });

  /// 新生成的完整回复文本。
  final String reply;

  /// 候选归属消息 id（= 目标 assistant 行；候选追加不产生新消息行）。
  final int messageId;

  /// 候选归属消息 id 兼容字段（= [messageId]，语义随候选追加更新）。
  final int replacedMessageId;

  /// 所属对话 id。
  final int conversationId;

  /// 新候选 index（候选 0 = 原回复播种，首次追加 = 1）；**-1 = 未追加候选**
  /// （continueReply 空续写 no-op 哨兵，MS-04 消费前须判 `>= 0`）。
  final int swipeIndex;
}

/// prompt-debug 追溯结果（PD-04；只读见证，SR-31）。
///
/// 与真实发送走同一 `_assemble` 组装核心与同一上游（history 滑窗、世界书扫描、
/// narrative/preset/expert 参数），segments 逐条含来源标注（[PromptSegment]），
/// 仅 debug 路径消费——零 LLM、零落库、本地渲染零外发。
class PromptDebugResult {
  const PromptDebugResult({
    required this.characterName,
    required this.model,
    required this.promptMode,
    required this.segments,
  });

  /// 角色名（空回退 ''；桌面 `build_prompt_debug` 同名语义）。
  final String characterName;

  /// 模型 `provider/model`（对齐桌面 `f"{conv.model_provider}/{conv.model_name}"`）。
  final String model;

  /// 组装模式（simple/expert，对齐桌面 prompt_mode）。
  final String promptMode;

  /// 带来源标注的组装分段（content/role 序列与真实发送 messages 逐条一致）。
  final List<PromptSegment> segments;
}

/// LLM 错误族 → (HTTP 状态码, 用户可见消息) 映射（逐字对齐
/// `error_mapping.py::llm_error_response`，列表顺序即匹配优先级）。
///
/// 映射规则（锚）：
/// - [LLMAuthError] → 401，[provider] 非空时「{provider} API Key 无效，请在
///   设置中更新」，为空时输出无前缀基础文案；
/// - [LLMRateLimitError] → 429 固定「API 请求频率超限，请稍后再试」；
/// - [LLMTimeoutError] → 504 固定「API 请求超时，请检查网络后重试」；
/// - [LLMContentFilterError] → 400 + str(e)；
/// - 其余（[LLMBadRequestError] / [LLMResponseParseFailedError] / 基类与未注册
///   子类）→ 兜底 502 + str(e)（对齐桌面基类 LLMError 置于末尾的兜底条目）。
///
/// [provider] 为 Provider 名（Auth 消息模板使用；空 → 无前缀基础文案）。
({int status, String message}) llmErrorResponse(
  LLMError error,
  String provider,
) {
  if (error is LLMAuthError) {
    final prefix = provider.isNotEmpty ? '$provider ' : '';
    return (status: 401, message: '${prefix}API Key 无效，请在设置中更新');
  }
  if (error is LLMRateLimitError) {
    return (status: 429, message: 'API 请求频率超限，请稍后再试');
  }
  if (error is LLMTimeoutError) {
    return (status: 504, message: 'API 请求超时，请检查网络后重试');
  }
  if (error is LLMContentFilterError) {
    return (status: 400, message: error.message);
  }
  return (status: 502, message: error.message);
}

/// 领域错误族 → (HTTP 状态码, 用户可见消息) 映射（对齐
/// `error_mapping.py::domain_error_response` 的聊天相关分支；422 家族与
/// 角色卡导入无关，不在此迁移）。
///
/// - [ConversationNotFoundError] / [CharacterNotFoundError] /
///   [MessageNotFoundError] → 404 + str(exc)；
/// - [ApiKeyMissingError] / [ProviderNotSupportedError] /
///   [InvalidRegenerateTargetError] / [RegenerateBusyError] → 400 + str(exc)；
/// - 未知 [DomainError] 子类 → 400 + str(e) 兜底（防御性）。
({int status, String message}) domainErrorResponse(DomainError error) {
  if (error is ConversationNotFoundError ||
      error is CharacterNotFoundError ||
      error is MessageNotFoundError) {
    return (status: 404, message: error.message);
  }
  if (error is ApiKeyMissingError ||
      error is ProviderNotSupportedError ||
      error is InvalidRegenerateTargetError ||
      error is RegenerateBusyError) {
    return (status: 400, message: error.message);
  }
  return (status: 400, message: error.message);
}

/// 聊天链错误 → 用户可见文案单源（F-124：chat_service 三叉 catch 与
/// chat_round 判型共 4 处收敛，断流语义变更只需改本函数）。
///
/// 领域错误 → [domainErrorResponse] 文案；LLM 错误 → [llmErrorResponse]
/// 文案（[providerName] 非空时 Auth 消息带前缀）；其余（未预期异常）→
/// 「生成回复失败: $error」兜底（对齐桌面 O3 语义）。
String chatErrorMessage(Object error, {String providerName = ''}) {
  if (error is DomainError) {
    return domainErrorResponse(error).message;
  }
  if (error is LLMError) {
    return llmErrorResponse(error, providerName).message;
  }
  return '生成回复失败: $error';
}

/// 判定 provider 流异常是否为「连接中断」（断流，R3 seam）。
///
/// 契约（T02 wire 层遵守）：**连接建立段**传输失败（DNS / 拒连 / 连接超时 /
/// 响应头前断——stream_wire.dart 连接相位收敛为 [ConnectPhaseInterruptedError]）
/// 与**读取段**断连（EOF 未收终态帧 / 连接重置 / idle 超时——读取相位收敛为
/// [ReadPhaseInterruptedError]）统一编码为 [LLMConnectionInterruptedError] 伞
/// 下两叶子（errors.dart 共享，Claude / OpenAI wire 一致抛出）。**伞下判型**
/// 即断流判定：HTTP 状态码路径（403 / 404 / 422 等经 `translateSdkError` 兜底
/// 翻译）与业务错误（Auth / RateLimit / Timeout / ContentFilter / BadRequest /
/// ResponseParseFailed）均为**基类** [LLMError] 或其非中断子类，不算断流 →
/// 走业务错误 [ChatError]（F-45 不落部分内容）。M6-06：仅连接相位叶子
/// （[ConnectPhaseInterruptedError]）属自动重试窗口，重试耗尽后复用本判定走
/// 断流收束。
bool _isConnectionDrop(LLMError error) =>
    error is LLMConnectionInterruptedError;

/// 续写指令行（对齐桌面 `chat.py::CONTINUE_INSTRUCTION`，L89-92 逐字）。
///
/// 触发形态拍板（桌面实证）：尾随 **user** 消息而非 system——适配器
/// 「last system wins」契约下尾随 system 会挤掉角色 persona 链（桌面
/// `_prepare_messages` 锁定），user 形态与普通路径 system 链完全一致。
const String continueInstruction =
    '（请继续书写上一条 AI 回复：保持角色人设、语气与文风，'
    '不要重复或概括已经写过的内容，直接从停下的地方接续）';

/// 续写触发的「原消息末段」锚点长度上限（UTF-16 code unit，对齐桌面
/// `_CONTINUATION_TAIL_CHARS = 200` 字符口径）。
const int _continuationTailCodeUnits = 200;

/// 回合末副作用上下文（S1 集合契约）：一次完整 assistant 落库后的回合快照。
///
/// [characterId] 为校验失败路径可空的角色 id（null → 回合末副作用跳过）；
/// [memoryChangedThisTurn] 记录本回合 `<add:>`/`<persona:>` 是否有落库
/// （VR-07 懒补嵌触发语义，`_applyMemoryCommands` 返回值置位）。
class EndOfTurnContext {
  const EndOfTurnContext({
    required this.characterId,
    required this.conversationId,
    required this.memoryChangedThisTurn,
  });

  /// 对话所属角色 id（校验失败路径保持 null）。
  final int? characterId;

  /// 回合所属对话 id。
  final int conversationId;

  /// 本回合记忆指令是否有落库（`<add:>`/`<persona:>`）。
  final bool memoryChangedThisTurn;
}

/// 回合末副作用钩子（S1）：装配层注册的有序闭包，消费方依列表序 `unawaited`
/// 执行。降级契约 = 服务内吞错（闭包不得上抛）；集合层只做顺序编排，
/// 不 try/catch。backfill 双触发（memoryChanged 门 + reflect 落库成功后）以
/// 闭包内协作表达，集合层不承载因果边。
typedef EndOfTurnHook = Future<void> Function(EndOfTurnContext ctx);

/// [streamReply] 一次运行的共享可变状态（onData / onCancel / 收尾 handler 间
/// 传递：完整内容累积、是否已落库、provider 订阅句柄、停止标志）。
class _StreamRunState {
  _StreamRunState({required this.conversationId, required this.content});

  /// 目标对话 id。
  final int conversationId;

  /// 用户输入内容。
  final String content;

  /// 对话所属角色 id（`_runStreamReply` 校验通过后赋值，供记忆指令落库用；
  /// 校验失败路径保持 null，记忆链路跳过）。
  int? characterId;

  /// 已停止：调用方取消订阅（或停止收尾完成）后置位。
  bool stopped = false;

  /// 部分/完整内容是否已落库（幂等防护，防 onDone 与 onCancel 双重保存）。
  bool saved = false;

  /// 已累积的流式内容（逐 token 追加；完成态即完整回复）。
  String fullContent = '';

  /// 本回合记忆指令是否有落库（VR-07 懒补嵌触发语义：`<add:>`/`<persona:>`
  /// 落库后 fire-and-forget 补嵌；`_persistAssistant` 经
  /// `_applyMemoryCommands` 返回值置位）。
  bool memoryChangedThisTurn = false;

  /// 本次回合已发生的连接阶段失败次数（重试编排计数；耗尽后走终态收束）。
  int connectFailures = 0;

  /// provider 流订阅（停止时直接 cancel，不等待待处理元素）。
  StreamSubscription<String>? providerSub;

  /// user 写尝试的结算门（停止完成契约，AR-2）：`_runStreamReply` 在 user
  /// 消息落库成功后 complete；写失败 / 终态错路径经外层 finally 兜底
  /// （`!isCompleted` 守卫防双重 complete）。`_stopStreamReply` 置 stopped 后
  /// 先 await 本门（3s 有界）——`sub.cancel()` resolve 即保证「已发 user 写已
  /// 结算（成功落库 / 回合已终态不再写）」。
  final Completer<void> userWriteSettled = Completer<void>();
}

/// 一次聊天回合的编排服务。
///
/// 构造依赖：四仓储（消息 / 对话 / 角色 / 设置）+ [LLMProviderFactory]
/// （Provider 装配抽象）。MS-02 起 regenerate 不再直接持有 drift 数据库——
/// 候选追加收口于 [MessageRepository.addSwipe]（仓库内事务）。无平台存储 /
/// 视图依赖。
class ChatService {
  /// [database] 参数保留以维持构造签名稳定（app.dart 装配零改动）；
  /// MS-02 起服务不再直接使用（regenerate 的「有界删旧 + 插新」单事务已删除，
  /// 候选追加收口于 [MessageRepository.addSwipe]）。
  ///
  /// [settingsRepository] 提供 Key 解析链与滑窗轮数等设置。
  ///
  /// [connectRetryDelays]：连接建立阶段失败的重试退避序列（M6-06），长度即
  /// 最大重试次数。生产默认 `[1s, 2s]`（重试 2 次，指数退避）；测试注入短值
  /// 以获得确定性退避时序。
  ChatService({
    required AppDatabase database,
    required this._conversationRepository,
    required this._characterRepository,
    required this._messageRepository,
    required this._settingsRepository,
    required this._providerFactory,
    CredentialsResolver? credentialsResolver,
    this._memoryService,
    this._thoughtService,
    this._companionRepository,
    LorebookRepository? lorebookRepository,
    this._lorebookRandom,
    List<EndOfTurnHook> endOfTurnHooks = const [],
    List<Duration> connectRetryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) : _endOfTurnHooks = List<EndOfTurnHook>.unmodifiable(endOfTurnHooks),
       _connectRetryDelays = List<Duration>.unmodifiable(connectRetryDelays) {
    // 服务层不直接持有 AppDatabase（wildcard）；例外：世界书仓储缺省需从
    // [database] 装配（app.dart 装配零改动约束，WL-03），显式注入可覆盖。
    var _ = database;
    _lorebookRepository = lorebookRepository ?? LorebookRepository(database);
    _credentialsResolver = credentialsResolver ?? _wireCredentialsResolver();
  }

  final ConversationRepository _conversationRepository;
  final CharacterRepository _characterRepository;
  final MessageRepository _messageRepository;
  final SettingsRepository _settingsRepository;
  final LLMProviderFactory _providerFactory;

  /// 记忆编排服务（人机恋 AC-02/AC-03）；null = 记忆功能未启用（既有装配零改动）。
  final MemoryService? _memoryService;

  /// 内心独白服务（阶段 2，PS2-04/07）；null = 独白未启用（既有装配零改动）。
  /// 剥离恒启用（经此服务），开关控制落库与 prompt 指令。
  final ThoughtService? _thoughtService;

  /// 关系状态读面（注入链需查 RelationshipStates 行；companion_repository 为
  /// 阶段 2 共享只读依赖，缺省 null 时关系注入跳过——既有装配零改动）。
  final CompanionRepository? _companionRepository;

  /// 世界书条目仓储（WL-03）：缺省由装配传入的 `database` 构造（app.dart
  /// 装配零改动约束见构造函数），调用方可显式注入覆盖。
  late final LorebookRepository _lorebookRepository;

  /// 世界书激活 RNG 注入点（WL-03 验收 4）：null → 引擎每次调用自建
  /// [Random]（非确定性，符合概率/互斥组语义）；测试注入同种子可复现。
  final Random? _lorebookRandom;

  /// 回合末副作用集合（S1）：装配层注册的有序闭包，列表序即执行序
  /// （backfill → reflect → plan → relate）。缺省 `const []`（零副作用）。
  /// 降级契约 = 服务内吞错；集合层只做顺序编排，不 try/catch。
  final List<EndOfTurnHook> _endOfTurnHooks;

  /// 凭据解析链（AR-3）：组合序单一归属 [CredentialsResolver]；缺省由
  /// [_settingsRepository] 装配 reader（测试可注入，既有装配零 churn）。
  late final CredentialsResolver _credentialsResolver;

  /// 从设置仓储装配缺省解析器 reader——委托仓储的
  /// [SettingsRepository.wireCredentialsResolver]（C2 装配收敛：四 reader 接线
  /// 单一归属仓储，本类仅消费，构造签名与可选注入参数零改动）。
  CredentialsResolver _wireCredentialsResolver() =>
      _settingsRepository.wireCredentialsResolver();

  /// 连接阶段失败的重试退避序列（长度 = 最大重试次数；M6-06 弱网重连）。
  final List<Duration> _connectRetryDelays;

  /// F4：生成类操作 in-flight 对话集（并发守卫——同对话 in-flight 期间第二次
  /// regenerate / [continueReply] 抛 [RegenerateBusyError]，防并发对同一目标
  /// 重复写候选）。MS-02 候选语义下无「第二次事务删第一次新回复」风险，守卫
  /// 退化为并发写保护（双触发防重复候选追加）。
  final Set<int> _regenerateInFlight = {};

  /// 发送一条用户消息并流式生成回复（A2）。
  ///
  /// 编排（对齐 `chat.py::prepare_chat` + `stream_reply`）：
  /// 1. 校验对话存在（不存在 → [ChatError]「对话不存在」）；
  /// 2. autoGreeting 零消息守卫：对话无任何消息且角色有 first_mes → 首条
  ///    assistant 开场白（`{{user}}/{{char}}` 已替换）；
  /// 3. 落库 user 消息；
  /// 4. buildMessages 组装（角色字段映射 CharacterData + 滑窗
  ///    `sliding_window_rounds`）；
  /// 5. provider 解析（Key 解析链经设置仓储；空 → [ApiKeyMissingError]「未配置
  ///    {provider} API Key，请在设置中填写」）；
  /// 6. streamGenerate 逐 token 产出 [ChatToken]；
  /// 7. 流结束：非空 → 落库完整 assistant 产出 [ChatDone(messageId)]；零 token
  ///    空流不落库 → [ChatDone(null)]。
  ///
  /// 停止（A3）：调用方取消返回流的订阅 → [StreamController.onCancel] 直接取消
  /// provider 订阅（**不等待**待处理元素——async* 取消会在内部流停滞时挂起，
  /// research 实证排除）→ 已累积部分落库（DB 存纯文本部分内容，UI 侧标「已停
  /// 止」）；无部分内容 → 仅保留已发 user。
  ///
  /// **停止完成契约（AR-2）**：取消返回流的订阅（停止）的完成 Future 保证本
  /// 轮在途 user 写尝试已结算（成功落库 / 回合已终态不再写）——`sub.cancel()`
  /// resolve 后 reload 必见已发 user（门等待 3s 有界 + 终态兜底，不挂起）。
  ///
  /// 断流（A5）：provider 流抛出 [LLMConnectionInterruptedError] 伞（连接相位
  /// [ConnectPhaseInterruptedError] / 读取相位 [ReadPhaseInterruptedError] 两
  /// 叶子均命中伞下判型）→ 已累积部分落库 + 非阻塞 [ChatInterrupted]「回复已
  /// 中断」；无部分 → [ChatInterrupted(null)]。
  ///
  /// 连接阶段自动重试（M6-06）：连接建立失败（wire 连接相位收敛为
  /// [ConnectPhaseInterruptedError]，未收到状态码、构造性保证未产出 token）→
  /// 自动重试 2 次、退避 [1s, 2s]（[connectRetryDelays] 可注入）；user 行落库
  /// 仅一次，重试不重复。读取相位 / 基类断流（已收状态码后失败，含首 token
  /// 前 idle——B1）→ 不重试，走既有断流收束。
  ///
  /// 错误（A2 错误面）：领域错误 / LLM 业务错误 → [ChatError] 事件（用户可见
  /// 文案），且**不落部分内容**（F-45，锚 `chat.py::stream_reply`）。
  Stream<ChatEvent> streamReply({
    required int conversationId,
    required String content,
  }) {
    final state = _StreamRunState(
      conversationId: conversationId,
      content: content,
    );
    final controller = StreamController<ChatEvent>();
    // 停止信号 = 调用方取消订阅；onCancel 直接取消 provider 订阅（provider 流
    // 对 dart:io HttpClient 而言即断开连接，立即返回），随后部分落库 + 关闭流。
    controller.onCancel = () => _stopStreamReply(state, controller);
    unawaited(_runStreamReply(state, controller));
    return controller.stream;
  }

  /// streamReply 编排主体：校验 → 开场白 → 落库 user → 组装 → 解析 → 订阅
  /// provider 流（`.listen`，停止时经 [state.providerSub] 直接取消）。
  Future<void> _runStreamReply(
    _StreamRunState state,
    StreamController<ChatEvent> controller,
  ) async {
    String providerName = '';
    try {
      // 1. 校验对话存在。
      final conv = await _conversationRepository.getConversation(
        state.conversationId,
      );
      if (conv == null) {
        throw ConversationNotFoundError();
      }
      final character = await _characterRepository.getCharacter(
        conv.characterId,
      );
      if (character == null) {
        throw CharacterNotFoundError(conv.characterId);
      }
      // 记忆指令落库依赖角色 id（assistant 落库前剥离标签 + add/persona 落库）。
      state.characterId = character.id;
      final userName = await _settingsRepository.userName;
      final extraVars = await _settingsRepository.templateVars;

      // 2. autoGreeting 零消息守卫。
      await _autoInsertGreeting(conv, character, userName, extraVars);

      // 3. 落库 user 消息。
      await _messageRepository.createMessage(
        conversationId: state.conversationId,
        role: Role.user,
        content: state.content,
      );
      // 停止完成契约（AR-2）：user 写已结算 → 放行停止门。此后（组装/解析/
      // 流式中）任意窗口 `sub.cancel()` 的门等待即时放行，不挂起。
      state.userWriteSettled.complete();

      // 4. 组装消息列表。
      final maxRounds = await _settingsRepository.slidingWindowRounds;
      final messages = await _assembleMessages(
        conv: conv,
        character: character,
        historyBeforeId: null,
        maxRounds: maxRounds,
        userName: userName,
        extraVars: extraVars,
        appendCurrentInput: true,
        userContent: state.content,
      );

      // 4b. 组装生成参数（SP-01）：conv 采样四列非空 → 覆盖；NULL → 既有链
      //（温度角色为主/全局兜底、max_tokens 全局、三采样参数 null 不覆盖
      // provider 默认）；SR-24 守卫在 _resolveSamplingParameters 单点承载。
      final globalTemperature = await _settingsRepository.getTemperature();
      final globalMaxTokens = await _settingsRepository.getMaxTokens();
      final params = _resolveSamplingParameters(
        conv: conv,
        character: character,
        globalTemperature: globalTemperature,
        globalMaxTokens: globalMaxTokens,
      );

      // 5. provider 解析（Key 缺失 → ApiKeyMissingError；未知 → 工厂抛）。
      final resolved = await _resolveProvider(conv);
      providerName = resolved.provider;

      // 停止可能发生在组装/解析期间（罕见）：无任何 token 已产出 → 不订阅，
      // 仅保留已发 user（_stopStreamReply 已收尾）。
      if (state.stopped) {
        return;
      }

      // 6. 订阅 provider 流。cancelOnError 保证错误后在 onError 一次性收尾，
      //    不再触发 onDone 造成双处置。onError 先走 M6-06 连接阶段重试判定。
      _subscribeStream(
        state: state,
        controller: controller,
        providerName: providerName,
        llm: resolved.llm,
        messages: messages,
        model: resolved.model,
        temperature: params.temperature,
        maxTokens: params.maxTokens,
        topP: params.topP,
        presencePenalty: params.presencePenalty,
        frequencyPenalty: params.frequencyPenalty,
      );
    } on DomainError catch (e) {
      // F3：调用方可能在解析失败瞬间取消订阅（controller 已 close），
      // add 到已关闭 controller 抛 StateError → 未处理异步异常；守卫跳过。
      // 停止完成契约（AR-2 修复）：门先于任何 await 结算——controller 层
      // `controller.close()` 的完成依赖 onCancel 收尾，而 onCancel 等待门；
      // 门若只在 finally 结算会与 close 形成闭环，终态错误路径取消卡满 3s
      // 有界窗口（S1 红态诊断实证）。
      _settleUserWriteGate(state);
      if (!controller.isClosed) {
        controller.add(ChatError(chatErrorMessage(e)));
        await controller.close();
      }
    } on LLMError catch (e) {
      // 组装/解析阶段不产生 LLMError（Provider 尚未调用）；防御性兜底。
      _settleUserWriteGate(state);
      if (!controller.isClosed) {
        state.saved = true; // F-45。
        controller.add(
          ChatError(chatErrorMessage(e, providerName: providerName)),
        );
        await controller.close();
      }
    } catch (e) {
      // 未预期异常 → ChatError（对齐桌面 O3 语义），不落部分内容。
      _settleUserWriteGate(state);
      if (!controller.isClosed) {
        state.saved = true;
        controller.add(ChatError(chatErrorMessage(e)));
        await controller.close();
      }
    } finally {
      // 终态兜底（停止完成契约，AR-2）：三条 catch 已在 `controller.close()`
      // 前独立结算门（避免与 onCancel 收尾形成闭环），finally 兜底其余任何
      // 终态退出路径（防御性，`!isCompleted` 守卫防双重 complete）。
      _settleUserWriteGate(state);
    }
  }

  /// 结算 user 写状态门（幂等）——`_runStreamReply` 各终态路径（写成功显式
  /// complete / 三条 catch / finally 兜底）统一的独立结算点。门必须出现在
  /// 任何可能阻塞于 onCancel 收尾的 await（如 `controller.close()`）之前：
  /// `_stopStreamReply`（onCancel）等待门、close 的完成又等待 onCancel 收尾,
  /// 若门只在 finally（close 返回之后）结算，终态错误路径的取消会等满 3s
  /// 有界窗口（AR-2 修复实证）。
  void _settleUserWriteGate(_StreamRunState state) {
    if (!state.userWriteSettled.isCompleted) {
      state.userWriteSettled.complete();
    }
  }

  /// 订阅 provider 流并接线事件（onData / onError / onDone）。
  ///
  /// 停止或事件流已关闭时不订阅（幂等守卫，重试/停止竞态下复用）。onError 先
  /// 走 [_onStreamError] 的 M6-06 连接阶段重试判定，重试耗尽的失败才落到
  /// [_onProviderStreamError] 终态收束。
  void _subscribeStream({
    required _StreamRunState state,
    required StreamController<ChatEvent> controller,
    required String providerName,
    required LLMProvider llm,
    required List<LlmMessage> messages,
    required String model,
    required double temperature,
    required int maxTokens,
    required double? topP,
    required double? presencePenalty,
    required double? frequencyPenalty,
  }) {
    if (state.stopped || controller.isClosed) {
      return;
    }
    final sub = llm
        .streamGenerate(
          messages: messages,
          model: model,
          temperature: temperature,
          maxTokens: maxTokens,
          topP: topP,
          presencePenalty: presencePenalty,
          frequencyPenalty: frequencyPenalty,
        )
        .listen(
          (token) {
            if (state.stopped) {
              return; // 停止后不再追加（_stopStreamReply 已处理部分落库）。
            }
            if (controller.isClosed) {
              return;
            }
            state.fullContent += token;
            controller.add(ChatToken(token));
          },
          onError: (Object error, StackTrace stackTrace) {
            unawaited(
              _onStreamError(
                state: state,
                controller: controller,
                providerName: providerName,
                llm: llm,
                messages: messages,
                model: model,
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                error: error,
              ),
            );
          },
          onDone: () {
            unawaited(_onProviderStreamDone(state, controller));
          },
          cancelOnError: true,
        );
    state.providerSub = sub;
  }

  /// M6-06 连接阶段失败处理：先判连接相位重试，再走终态收束。
  ///
  /// 重试条件（单行类型契约，全部满足）：
  /// - 失败为**连接相位**叶子 [ConnectPhaseInterruptedError]（wire connect 段
  ///   构造性保证：未收到状态码、未产出 token——见 stream_wire.dart）；
  /// - 重试次数未耗尽（[_connectRetryDelays] 长度 = 最大重试次数）。
  ///
  /// 重试安全（仅对连接相位声明）：连接建立阶段失败未收到状态码、确定未产生
  /// 服务端生成，重放不重复计费/生成；user 行已在 `_runStreamReply` 落库，
  /// 重试不重复落库。读取相位（[ReadPhaseInterruptedError]）与基类断流一律
  /// 不可重试（读段失败服务端已处理请求、可能已产生计费内容）。
  /// 退避期间停止/取消 → 不再订阅（无泄漏）；重试耗尽 → 既有断流/错误收束。
  Future<void> _onStreamError({
    required _StreamRunState state,
    required StreamController<ChatEvent> controller,
    required String providerName,
    required LLMProvider llm,
    required List<LlmMessage> messages,
    required String model,
    required double temperature,
    required int maxTokens,
    required double? topP,
    required double? presencePenalty,
    required double? frequencyPenalty,
    required Object error,
  }) async {
    if (state.stopped || controller.isClosed) {
      return;
    }
    if (error is ConnectPhaseInterruptedError &&
        state.connectFailures < _connectRetryDelays.length) {
      final delay = _connectRetryDelays[state.connectFailures];
      state.connectFailures++;
      await Future<void>.delayed(delay);
      if (state.stopped || controller.isClosed) {
        return; // 重试窗口内停止/取消：不再订阅（_stopStreamReply 已收尾）。
      }
      _subscribeStream(
        state: state,
        controller: controller,
        providerName: providerName,
        llm: llm,
        messages: messages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        presencePenalty: presencePenalty,
        frequencyPenalty: frequencyPenalty,
      );
      return;
    }
    await _onProviderStreamError(state, controller, providerName, error);
  }

  /// provider 流正常结束（终态帧收束）：非空落库完整 assistant；零 token 空
  /// 流不落库（`messageId` 为 null）。落库失败（如流式中对话被删）收口为
  /// [ChatError]，不产生未处理异步异常。
  Future<void> _onProviderStreamDone(
    _StreamRunState state,
    StreamController<ChatEvent> controller,
  ) async {
    if (state.stopped) {
      return; // 停止路径已收尾（幂等防护）。
    }
    try {
      final msg = await _persistAssistant(state);
      // 完整 assistant 落库后依列表序触发回合末副作用集合（S1）：装配层注册
      // backfill/reflect/plan/relate 四个闭包；服务内吞错（闭包不得上抛），
      // 集合层只做顺序编排、不 try/catch；零 token 空流（msg == null）不触发。
      if (msg != null) {
        _runEndOfTurnHooks(state);
      }
      // F3 同类硬化：onDone 与 onCancel 竞态（收尾瞬间取消）下 controller 可能
      // 已关闭，add 前守卫避免 add-after-close 的未处理异常。
      if (!controller.isClosed) {
        controller.add(msg != null ? ChatDone(msg.id) : const ChatDone(null));
      }
    } catch (e) {
      // 落库失败（如流式中对话被删）→ 收口为 ChatError，不产生未处理异步异常。
      if (!controller.isClosed) {
        controller.add(ChatError('生成回复失败: $e'));
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  /// provider 流异常收尾：断流（[LLMConnectionInterruptedError] 伞）/ 业务错误 /
  /// 未预期异常。
  Future<void> _onProviderStreamError(
    _StreamRunState state,
    StreamController<ChatEvent> controller,
    String providerName,
    Object error,
  ) async {
    if (state.stopped) {
      return; // 停止路径已收尾（幂等防护）。
    }
    if (controller.isClosed) {
      return; // F3 同类硬化：与 onCancel 竞态下 controller 已关闭 → 无事件可发。
    }
    try {
      if (error is LLMError) {
        if (_isConnectionDrop(error)) {
          // 断流：已累积部分落库 + 非阻塞「回复已中断」。
          final msg = await _persistAssistant(state);
          controller.add(
            msg != null ? ChatInterrupted(msg.id) : const ChatInterrupted(null),
          );
        } else {
          // LLM 业务错误：F-45 不落部分内容。
          state.saved = true;
          controller.add(
            ChatError(chatErrorMessage(error, providerName: providerName)),
          );
        }
      } else if (error is DomainError) {
        controller.add(ChatError(chatErrorMessage(error)));
      } else {
        state.saved = true; // F-45。
        controller.add(ChatError(chatErrorMessage(error)));
      }
    } catch (e) {
      // 断流部分落库失败（如流式中对话被删）→ 收口为 ChatError。
      // 挂起期间用户停止 → controller 已关闭 → 跳过发事件（对齐外层守卫）。
      if (!controller.isClosed) {
        controller.add(ChatError(chatErrorMessage(e)));
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  /// 停止（A3）：调用方取消订阅时触发。直接取消 provider 订阅（不等待待处理
  /// 元素，cancel 包 `.timeout` 有界完成——F-17 停滞流兜底），已累积部分落库
  /// （无部分 → 仅保留已发 user），关闭事件流。cancel 以错误完成（cancel-unwind
  /// 断流）仍走落库 + close 收尾（F-55 结构保证：try/catch + finally）。
  Future<void> _stopStreamReply(
    _StreamRunState state,
    StreamController<ChatEvent> controller,
  ) async {
    if (state.stopped) {
      return; // 幂等。
    }
    state.stopped = true;
    // 停止完成契约（AR-2）：先 await user 写结算门——`sub.cancel()` resolve
    // 保证「已发 user 写已结算（成功落库 / 回合已终态不再写）」，调用方据此
    // 删除 UI 轮询补偿后 reload 必见已发 user。3s 有界（F-17 同款）+ try/catch
    // 对齐 F-55 结构保证：门等待自身异常不跳过既有收尾；写成功即 try 内
    // complete、失败/早终态经 `_runStreamReply` 终态兜底，常态零回归（流中
    // 停止时 token ⟹ user 已写 ⟹ 门已完成）。
    try {
      await state.userWriteSettled.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('停止等待 user 落库超时，继续回合收尾');
        },
      );
    } catch (e) {
      debugPrint('停止等待 user 落库异常，继续回合收尾: $e');
    }
    // F-17：providerSub.cancel() 在真实网络 / 停滞 provider 流上无上界挂起
    // （cancel 等下一块/EOF）→ 包 `.timeout` 上界，onTimeout 兜底不抛错、返回
    // 后继续回合收尾。
    // F-55 事实校准：3s 窗口内连接以**错误**完成（cancel-unwind 断流——停滞
    // await 上 EOF 落错，经 wire `await for` 机制路由进生成器收尾，cancel()
    // 以错误完成）是真实路径，既有「挂起不抛错」前提被证伪；且 Dart
    // `Future.timeout` 无 `onError` 参数，onError 语义必须以 try/catch 实现。
    // 落库 + close 收尾进 finally：「停止收尾不可被任何前置步骤异常跳过」为
    // 结构不变量（F-55 修复前，cancel 错误穿透会跳过二者 + 产生未处理异步
    // 异常 + 卡住调用方 stop 收尾）。
    try {
      await state.providerSub?.cancel().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('停止 cancel 停滞，继续回合收尾');
        },
      );
    } catch (e) {
      // F-55：cancel 以错误完成（cancel-unwind 断流）→ 捕获继续回合收尾，不
      // 跳过部分落库与事件流关闭。
      debugPrint('停止 cancel 断流，继续回合收尾: $e');
    } finally {
      // 已累积部分落库（DB 存纯文本部分内容，不写「已停止」标记）。
      try {
        await _persistAssistant(state);
      } catch (e) {
        // 停止路径兜底保存失败不重抛（尽力而为），仅记录日志不静默吞错。
        debugPrint('停止路径部分内容落库失败: $e');
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  /// 幂等落库已累积部分/完整内容为 assistant 消息（A3 停止 / A5 断流 / done
  /// 共用）。无内容或已落库 → 返回 null；落库成功 → 返回消息行。
  ///
  /// 落库前经记忆链路剥离 `<add:>` / `<persona:>` / `<search:>` 标签（AC-02）：
  /// 剥离后的展示文本写入 messages.content，标签内容落库记忆（记忆失败降级，
  /// 保留原始文本，不阻断主回复）。
  ///
  /// 调用方负责错误处理（DB 写失败按各路径语义收口）。
  Future<Message?> _persistAssistant(_StreamRunState state) async {
    if (state.fullContent.isEmpty || state.saved) {
      return null;
    }
    state.saved = true;
    final raw = state.fullContent;
    // ① thought 剥离（恒启用）先于记忆（spec 判定②：thought 不进记忆链路）。
    final extracted = extractThought(raw);
    // ② 记忆只吃剥离后的正文（<add:> 等指令不受 thought 内容污染）。
    final applied = await _applyMemoryCommands(state, extracted.displayContent);
    state.memoryChangedThisTurn = applied.memoryChanged;
    // ③ 落库正文（thought 已剥；剥离后为空 → 空串消息，单测锁定）。
    final msg = await _messageRepository.createMessage(
      conversationId: state.conversationId,
      role: Role.assistant,
      content: applied.displayContent,
    );
    // ④ 补落 thought：ChatService 已在上文持有剥离结果（[extractThought]
    //    为全链路唯一剥离点，S5），服务只按开关落库，不再对原文重跑。
    final thoughtContent = extracted.thoughtContent;
    if (thoughtContent != null) {
      await _persistThought(state, msg.id, thoughtContent);
    }
    return msg;
  }

  /// 经 [ThoughtService.persistThought] 按开关落已剥离的内心独白（slot 4）。
  ///
  /// [thoughtContent] 来自 [extractThought]（上层唯一剥离点，S5）；开关关 →
  /// 服务侧 debugPrint 不落库；服务抛错 → 降级 log，正文不受影响（对齐
  /// 「记忆失败不阻断主回复」约束）。
  Future<void> _persistThought(
    _StreamRunState state,
    int messageId,
    String thoughtContent,
  ) async {
    final thoughtService = _thoughtService;
    final characterId = state.characterId;
    if (thoughtService == null || characterId == null) {
      return;
    }
    try {
      await thoughtService.persistThought(
        characterId: characterId,
        messageId: messageId,
        thoughtContent: thoughtContent,
      );
    } catch (e) {
      debugPrint('内心独白处理失败，保留正文: $e');
    }
  }

  /// 剥离 assistant 回复中的记忆标签并落库（AC-02/AC-03 记忆链路）。
  ///
  /// 返回剥离后的展示文本 + 本回合是否有记忆落库（`<add:>`/`<persona:>` 任一
  /// 落库即 true——VR-07 懒补嵌触发语义；search 指令不含落库不计入）。
  ///
  /// 记忆功能未启用（[_memoryService] == null）或角色 id 未知（校验失败路径）
  /// → 原样返回、无落库；记忆落库失败 → 降级返回原始文本（标签残留但主回复
  /// 可用，对齐「记忆失败不阻断主回复」约束）。
  Future<({String displayContent, bool memoryChanged})> _applyMemoryCommands(
    _StreamRunState state,
    String content,
  ) async {
    final memoryService = _memoryService;
    final characterId = state.characterId;
    if (memoryService == null || characterId == null) {
      return (displayContent: content, memoryChanged: false);
    }
    try {
      final result = await memoryService.applyAssistantReply(
        characterId,
        content,
      );
      return (
        displayContent: result.displayContent,
        memoryChanged: result.episodicAdded > 0 || result.personaAdded > 0,
      );
    } catch (e) {
      debugPrint('记忆指令处理失败，保留原始回复: $e');
      return (displayContent: content, memoryChanged: false);
    }
  }

  /// 依 [_endOfTurnHooks] 列表序逐个以 `unawaited` 触发回合末副作用（S1）。
  ///
  /// 集合层只做顺序编排：构造 [EndOfTurnContext] 后逐闭包调用，不 try/catch
  /// （降级契约 = 服务内吞错，闭包不得上抛）；列表序即执行序，装配层可见。
  void _runEndOfTurnHooks(_StreamRunState state) {
    final context = EndOfTurnContext(
      characterId: state.characterId,
      conversationId: state.conversationId,
      memoryChangedThisTurn: state.memoryChangedThisTurn,
    );
    for (final hook in _endOfTurnHooks) {
      unawaited(hook(context));
    }
  }

  /// 重生成对话中目标 AI 回复（A4，缺省末条 assistant）——MS-2 候选追加语义。
  ///
  /// 编排（对齐 `chat.py::regenerate_chat`，桌面 MS-1）：
  /// 0. F4 并发守卫：同对话生成类操作 in-flight（含 [continueReply]）期间
  ///    第二次调用抛 [RegenerateBusyError]；
  /// 1. 校验对话存在；
  /// 2. 解析目标：显式 [messageId] 或末条 assistant；目标非 assistant →
  ///    [InvalidRegenerateTargetError.notAssistant]；不存在 → [MessageNotFoundError]
  ///    / [InvalidRegenerateTargetError.noAssistantReply]；
  /// 3. 校验触发源：目标之前须有 user 消息，否则拒绝「没有可重生成的用户消息」；
  /// 4. 组装（`append_current_input=False`，历史截止锚定 target.id——桌面「先
  ///    截断后组装」在候选追加下以读侧过滤等价实现）+ provider 解析（Key 链）；
  /// 5. non-streaming 生成（网络在事务外）；**失败零落库**（候选不追加、
  ///    原消息保留）；
  /// 6. 成功后 [MessageRepository.addSwipe] **候选追加**（候选 0 = 原回复播种，
  ///    新回复 = index 1，`makeActive=true` 同步覆写 content 与
  ///    active_swipe_index）——消息数不变（1 assistant + N 候选），无
  ///    「有界删旧」；生成期间并发写入的新消息天然保留（F1 退化为并发写保护，
  ///    由步骤 0 守卫承保）。
  ///
  /// 返回 [RegenerateResult]：`messageId`/`replacedMessageId` = 目标行 id
  /// （候选归属消息，不删行）、`swipeIndex` = 新候选 index——客户端结算键
  /// （F-64 兼容：replacedMessageId 恒命中既有截断标记结算）。
  ///
  /// 抛出：领域错误（[ConversationNotFoundError] / [CharacterNotFoundError] /
  /// [MessageNotFoundError] / [InvalidRegenerateTargetError] /
  /// [RegenerateBusyError] / [ApiKeyMissingError] / [ProviderNotSupportedError]）
  /// 与 [LLMError]（生成失败，UI 经 [llmErrorResponse] 映射）。
  Future<RegenerateResult> regenerate({
    required int conversationId,
    int? messageId,
  }) async {
    // F4：并发双触发守卫。网络生成可挂起（秒级）；in-flight 期间直接拒绝，
    // 防第二次 trigger 基于同一快照对同一目标重复写候选（候选语义下无删行
    // 风险，但重复追加候选仍是数据污染）。
    if (_regenerateInFlight.contains(conversationId)) {
      throw RegenerateBusyError();
    }
    _regenerateInFlight.add(conversationId);
    try {
      // 1. 校验对话存在。
      final conv = await _conversationRepository.getConversation(
        conversationId,
      );
      if (conv == null) {
        throw ConversationNotFoundError();
      }

      // 2. 解析并校验目标。
      final target = await _resolveRegenerateTarget(conversationId, messageId);

      // 3. 校验触发源（候选追加同样要求触发 user 存在——无触发源的问候语
      //    重生成仍拒绝）。
      final trigger = await _lastUserBefore(conversationId, target.id);
      if (trigger == null) {
        throw InvalidRegenerateTargetError.noTriggerUser();
      }

      // 4. 组装（append_current_input=False）+ provider 解析。此步抛错不触碰
      //    DB，旧消息保留。
      final character = await _characterRepository.getCharacter(
        conv.characterId,
      );
      if (character == null) {
        throw CharacterNotFoundError(conv.characterId);
      }
      final userName = await _settingsRepository.userName;
      final extraVars = await _settingsRepository.templateVars;
      final maxRounds = await _settingsRepository.slidingWindowRounds;
      final messages = await _assembleMessages(
        conv: conv,
        character: character,
        historyBeforeId: target.id,
        maxRounds: maxRounds,
        userName: userName,
        extraVars: extraVars,
        appendCurrentInput: false,
      );
      final resolved = await _resolveProvider(conv);

      // 4b. 组装生成参数（SP-01）：与 streamReply 共享同一解析单点
      // _resolveSamplingParameters（conv 四列覆盖 / 既有链 + SR-24 守卫）。
      final globalTemperature = await _settingsRepository.getTemperature();
      final globalMaxTokens = await _settingsRepository.getMaxTokens();
      final params = _resolveSamplingParameters(
        conv: conv,
        character: character,
        globalTemperature: globalTemperature,
        globalMaxTokens: globalMaxTokens,
      );

      // 5. 生成（LLM 失败 → 异常上抛，零落库、原消息与候选均不变）。
      final reply = await resolved.llm.generate(
        messages: messages,
        model: resolved.model,
        temperature: params.temperature,
        maxTokens: params.maxTokens,
        topP: params.topP,
        presencePenalty: params.presencePenalty,
        frequencyPenalty: params.frequencyPenalty,
      );

      // 6. 候选追加单入口（仓库内事务：候选 0 播种 + 新候选置激活 + content
      //    跟随，原子落库）。消息数不变，无删除。
      final swipeIndex = await _messageRepository.addSwipe(
        target.id,
        reply,
        makeActive: true,
      );

      return RegenerateResult(
        reply: reply,
        messageId: target.id,
        replacedMessageId: target.id,
        conversationId: conversationId,
        swipeIndex: swipeIndex,
      );
    } finally {
      _regenerateInFlight.remove(conversationId);
    }
  }

  /// 续写对话中末条 AI 回复（MS-2；对齐 `chat.py::continue_chat`，桌面 MS-3）。
  ///
  /// 编排：
  /// 0. 并发守卫（同 [regenerate] 共享 `_regenerateInFlight`——continue 与
  ///    regenerate 同走 addSwipe 写候选，交错并发会产生候选追加竞态）；
  /// 1. 校验对话存在；
  /// 2. 解析目标：**末条消息须为 assistant**（对齐桌面
  ///    `_resolve_continue_target`——UI 续写按钮只渲染在末条 assistant 气泡）；
  ///    显式 [messageId] 时要求 == 末条消息 id，否则拒绝；
  /// 3. 组装（`append_current_input=False`，历史截止**含目标**：`target.id + 1`
  ///    对 [MessageRepository.messagesBefore] 的 `id < bound` 语义等价于桌面的
  ///    `id <= target.id` 含边界截止——消息主键为严格递增整数）+ provider 解析；
  /// 4. **尾随 user 触发消息**（桌面拍板形态：user 而非 system——尾随 system
  ///    会把 persona 链挤掉）= [continueInstruction] + 原消息末段锚
  ///    （[_continuationTail] 取末 200 code unit）；LLM 上下文内零新增 DB user 行；
  /// 5. non-streaming 生成；**失败零落库**（原内容与候选均不变）；
  /// 6. 成功：`content = 原 active 内容 + 续写片段` 候选追加置激活；**空续写
  ///    （LLM 零产出片段）no-op**——不追加重复候选（base + '' = base 会产生
  ///    内容相同候选行），返回 `swipeIndex = -1`（未追加哨兵）。
  ///
  /// 返回 [RegenerateResult]（同构）：`messageId`/`replacedMessageId` = 被续写
  /// 消息 id；`swipeIndex` 成功 = 新候选 index，空续写 = **-1**。
  ///
  /// 抛出：领域错误（[ConversationNotFoundError] / [MessageNotFoundError] /
  /// [InvalidRegenerateTargetError] / [RegenerateBusyError] /
  /// [ApiKeyMissingError] / [ProviderNotSupportedError]）与 [LLMError]。
  Future<RegenerateResult> continueReply({
    required int conversationId,
    int? messageId,
  }) async {
    if (_regenerateInFlight.contains(conversationId)) {
      throw RegenerateBusyError();
    }
    _regenerateInFlight.add(conversationId);
    try {
      // 1. 校验对话存在。
      final conv = await _conversationRepository.getConversation(
        conversationId,
      );
      if (conv == null) {
        throw ConversationNotFoundError();
      }

      // 2. 解析并校验目标（末条须为 assistant；显式 id 须 == 末条）。
      final target = await _resolveContinueTarget(conversationId, messageId);

      // 3. 组装（历史含目标——桌面 id <= target.id 对齐）+ provider 解析。
      final character = await _characterRepository.getCharacter(
        conv.characterId,
      );
      if (character == null) {
        throw CharacterNotFoundError(conv.characterId);
      }
      final userName = await _settingsRepository.userName;
      final extraVars = await _settingsRepository.templateVars;
      final maxRounds = await _settingsRepository.slidingWindowRounds;
      final messages = await _assembleMessages(
        conv: conv,
        character: character,
        // id < target.id + 1 ⇔ id <= target.id（严格递增整数主键）。桌面
        // `history_limit_message_id` 含边界（chat.py L141-142），逐字对齐。
        historyBeforeId: target.id + 1,
        maxRounds: maxRounds,
        userName: userName,
        extraVars: extraVars,
        appendCurrentInput: false,
      );
      final resolved = await _resolveProvider(conv);

      // 4. 尾随续写触发 user 消息（指令 + 原消息末段锚；不落库）。
      final tail = _continuationTail(target.content);
      final trigger =
          tail.isEmpty ? continueInstruction : '$continueInstruction\n$tail';
      messages.add(LlmMessage(role: 'user', content: trigger));

      // 4b. 组装生成参数（SP-01：conv 四列覆盖 / 既有链 + SR-24 守卫单点）。
      final globalTemperature = await _settingsRepository.getTemperature();
      final globalMaxTokens = await _settingsRepository.getMaxTokens();
      final params = _resolveSamplingParameters(
        conv: conv,
        character: character,
        globalTemperature: globalTemperature,
        globalMaxTokens: globalMaxTokens,
      );

      // 5. 生成（LLM 失败 → 异常上抛，零落库、原内容零改动）。
      final reply = await resolved.llm.generate(
        messages: messages,
        model: resolved.model,
        temperature: params.temperature,
        maxTokens: params.maxTokens,
        topP: params.topP,
        presencePenalty: params.presencePenalty,
        frequencyPenalty: params.frequencyPenalty,
      );

      // 6. 非空续写 → 候选追加；空续写 → no-op（不落重复候选）。
      final baseText = target.content;
      final continuation = reply.trim();
      if (continuation.isEmpty) {
        return RegenerateResult(
          reply: baseText,
          messageId: target.id,
          replacedMessageId: target.id,
          conversationId: conversationId,
          swipeIndex: -1,
        );
      }
      final newText = '$baseText$continuation';
      final swipeIndex = await _messageRepository.addSwipe(
        target.id,
        newText,
        makeActive: true,
      );
      return RegenerateResult(
        reply: newText,
        messageId: target.id,
        replacedMessageId: target.id,
        conversationId: conversationId,
        swipeIndex: swipeIndex,
      );
    } finally {
      _regenerateInFlight.remove(conversationId);
    }
  }

  /// 编辑重发（MS-03）：仅 user 消息——就地替换 content + 物理截断后续
  /// （候选随消息级联删）+ 重新生成**新** assistant 回复。
  ///
  /// 编排（对齐 `chat.py::edit_and_resend`；失败边界为移动端锁定语义）：
  /// 0. F4 并发守卫（与 [regenerate] / [continueReply] 共享 in-flight 集合——
  ///    SR-28：编辑重发与既有生成类操作共享生成链路与并发守卫）；
  /// 1. 校验对话存在；
  /// 2. 目标解析：显式 [messageId] 经 [MessageRepository.messageById] 归属
  ///    校验（不存在 / 跨对话 → [MessageNotFoundError]）；非 user →
  ///    [InvalidRegenerateTargetError.notUser]（校验失败零副作用）；
  /// 3. 角色存在性校验提前到破坏性写之前（校验类错误副作用最小化）；
  /// 4. [MessageRepository.replaceAndTruncateFollowing] 单事务原子：就地替换
  ///    content + 物理删除 `id > messageId` 的后续（候选随 FK CASCADE）；
  /// 5. 组装（`append_current_input=False`，历史截止**含**被编辑 user：
  ///    `messageId + 1` 对 `id < bound` 等价于桌面 `id <= messageId` 含边界）
  ///    + provider 解析（Key 缺失 → [ApiKeyMissingError]）；
  /// 6. non-streaming 生成；**失败保留「已替换 + 已截断」状态**——截断后
  ///    状态即未来状态，用户可再 regenerate（spec §4.3 锁定；与桌面
  ///    「失败回滚零落库」的差异为本工单拍板语义）；
  /// 7. 成功：新建 assistant 消息（新消息行；候选 0 = 回复本体，不实际
  ///    addSwipe），返回 [RegenerateResult]（`messageId`/`replacedMessageId`
  ///    = 新消息 id，`swipeIndex` = 0）。
  ///
  /// 抛出：领域错误（[ConversationNotFoundError] / [CharacterNotFoundError] /
  /// [MessageNotFoundError] / [InvalidRegenerateTargetError] /
  /// [RegenerateBusyError] / [ApiKeyMissingError] / [ProviderNotSupportedError]）
  /// 与 [LLMError]（生成失败，UI 经 [chatErrorMessage] / [llmErrorResponse]
  /// 映射文案）。
  Future<RegenerateResult> editAndRegenerate({
    required int conversationId,
    required int messageId,
    required String newContent,
  }) async {
    // F4：与 regenerate / continueReply 共享并发守卫（编辑同样写消息域）。
    if (_regenerateInFlight.contains(conversationId)) {
      throw RegenerateBusyError();
    }
    _regenerateInFlight.add(conversationId);
    try {
      // 1. 校验对话存在。
      final conv = await _conversationRepository.getConversation(
        conversationId,
      );
      if (conv == null) {
        throw ConversationNotFoundError();
      }

      // 2. 目标解析（归属校验 + 仅 user）——失败零副作用。
      final target = await _messageRepository.messageById(
        conversationId,
        messageId,
      );
      if (target == null) {
        throw MessageNotFoundError();
      }
      if (target.role != Role.user) {
        throw InvalidRegenerateTargetError.notUser();
      }

      // 3. 角色存在性校验（破坏性写之前——校验类错误不触碰 DB）。
      final character = await _characterRepository.getCharacter(
        conv.characterId,
      );
      if (character == null) {
        throw CharacterNotFoundError(conv.characterId);
      }

      // 4. 替换 + 截断单事务原子（生成前破坏性变更先行落库——失败保留）。
      await _messageRepository.replaceAndTruncateFollowing(
        conversationId: conversationId,
        messageId: messageId,
        content: newContent,
      );

      // 5. 组装（历史截止含被编辑 user）+ provider 解析。
      final userName = await _settingsRepository.userName;
      final extraVars = await _settingsRepository.templateVars;
      final maxRounds = await _settingsRepository.slidingWindowRounds;
      final messages = await _assembleMessages(
        conv: conv,
        character: character,
        historyBeforeId: messageId + 1, // id <= messageId 含边界（对齐桌面）
        maxRounds: maxRounds,
        userName: userName,
        extraVars: extraVars,
        appendCurrentInput: false,
      );
      final resolved = await _resolveProvider(conv);

      // 5b. 组装生成参数（SP-01：conv 四列覆盖 / 既有链 + SR-24 守卫单点）。
      final globalTemperature = await _settingsRepository.getTemperature();
      final globalMaxTokens = await _settingsRepository.getMaxTokens();
      final params = _resolveSamplingParameters(
        conv: conv,
        character: character,
        globalTemperature: globalTemperature,
        globalMaxTokens: globalMaxTokens,
      );

      // 6. 生成（LLM 失败 → 异常上抛；已替换 + 已截断状态保留）。
      final reply = await resolved.llm.generate(
        messages: messages,
        model: resolved.model,
        temperature: params.temperature,
        maxTokens: params.maxTokens,
        topP: params.topP,
        presencePenalty: params.presencePenalty,
        frequencyPenalty: params.frequencyPenalty,
      );

      // 7. 新建 assistant 消息（原 assistant 已随截断删除；候选 0 = 本体）。
      final saved = await _messageRepository.createMessage(
        conversationId: conversationId,
        role: Role.assistant,
        content: reply,
      );

      return RegenerateResult(
        reply: reply,
        messageId: saved.id,
        replacedMessageId: saved.id,
        conversationId: conversationId,
        swipeIndex: 0,
      );
    } finally {
      _regenerateInFlight.remove(conversationId);
    }
  }

  /// 归属校验（归属语义单一出处，[deleteMessage] / [switchSwipe] 双调用点共用）：
  /// [messageId] 必须属于 [conversationId] 且存在，否则 [MessageNotFoundError]
  /// （**跨对话同 id 视为不存在**，不外泄他对话行）；校验失败零副作用。
  ///
  /// 结构对齐桌面 message.py::_require_message：桌面把存在守卫早已抽成 helper、
  /// delete_message / switch_swipe 双路径共用，本 helper 为移动端追平该结构；
  /// 唯一差异 = 桌面 id-only（按 message_id 查，无对话过滤）vs 移动端带
  /// [conversationId] 过滤。
  Future<Message> _requireMessageOwnership({
    required int conversationId,
    required int messageId,
  }) async {
    final target = await _messageRepository.messageById(
      conversationId,
      messageId,
    );
    if (target == null) {
      throw MessageNotFoundError();
    }
    return target;
  }

  /// 删除单条消息（MS-03；对齐 `message.py::delete_message` 角色感知语义）。
  ///
  /// - 删 user → 截断含自身及后续（`id >= messageId`；候选随 FK CASCADE
  ///   级联，InnerThoughts CASCADE、ProactivePlans.messageId setNull 承保——
  ///   SR-28）；
  /// - 删 assistant / system 等非 user → 仅删该条（swipes 级联；该条之后
  ///   的消息保留——服务层不扩散删除范围）。
  ///
  /// 目标解析（破坏性操作防御）委托 [_requireMessageOwnership]——归属语义
  /// （不存在 / 跨对话拒绝、校验失败零副作用）见该 helper docstring（单一出处）。
  ///
  /// 返回实际删除条数（user 截断 = 截断消息总数；单删 = 1）。
  ///
  /// 抛出：[ConversationNotFoundError]（对话不存在）/
  /// [MessageNotFoundError]（目标不存在或跨对话）。
  Future<int> deleteMessage({
    required int conversationId,
    required int messageId,
  }) async {
    // 1. 校验对话存在（防御 FK 脏数据，正常不可达）。
    final conv = await _conversationRepository.getConversation(conversationId);
    if (conv == null) {
      throw ConversationNotFoundError();
    }

    // 2. 目标解析（归属校验，见 _requireMessageOwnership）。
    final target = await _requireMessageOwnership(
      conversationId: conversationId,
      messageId: messageId,
    );

    // 3. 角色感知删除范围（user 截断含自身；非 user 单删该条 + 级联）。
    if (target.role == Role.user) {
      return _messageRepository.deleteMessagesFrom(conversationId, messageId);
    }
    await _messageRepository.deleteMessage(messageId);
    return 1;
  }

  /// 切换 [conversationId] 内 [messageId] 的激活候选（F-140，契约表 §4.8 实现
  /// 补位；对齐 `message.py::switch_swipe`）。
  ///
  /// 归属校验委托 [_requireMessageOwnership]（存在性 / 跨对话拒绝语义单一出处，
  /// 与 [deleteMessage] 共用同一 helper）；越界 [index] 由仓库层
  /// [MessageRepository.switchSwipe] 原样上抛 [SwipeIndexOutOfRangeError]——
  /// 服务层零捕获、零重映射（仓库抛什么就是什么）。
  ///
  /// 成功返回切换后的 [Message]：`messages.content` 已被仓库层覆写为选中候选、
  /// `active_swipe_index` 已更新（契约表 `→ Message`）。
  Future<Message> switchSwipe({
    required int conversationId,
    required int messageId,
    required int index,
  }) async {
    // 目标解析（归属校验，见 _requireMessageOwnership）。
    await _requireMessageOwnership(
      conversationId: conversationId,
      messageId: messageId,
    );
    return _messageRepository.switchSwipe(messageId, index);
  }

  /// 解析续写目标并校验（对齐桌面 `_resolve_continue_target`：目标 = 末条消息
  /// 且须为 assistant）。
  ///
  /// 显式 [messageId] 时要求 == 末条消息 id（非末条 / 不存在 / 非 assistant
  /// 一律拒绝——续写只能在末条 assistant 之后进行）。错误族复用既有
  /// [InvalidRegenerateTargetError]（errors.dart 不在 MS-02 文件范围）：无消息
  /// / 末条非 assistant / 显式非末条 → [InvalidRegenerateTargetError.noAssistantReply]；
  /// 显式 id 非末条且不存在 → [MessageNotFoundError]（先定位后比较）。
  Future<Message> _resolveContinueTarget(
    int conversationId,
    int? messageId,
  ) async {
    final latest = await _messageRepository.lastMessage(conversationId);
    if (messageId != null) {
      if (latest == null || latest.id != messageId) {
        final explicit = await _messageRepository.messageById(
          conversationId,
          messageId,
        );
        if (explicit == null) {
          throw MessageNotFoundError();
        }
        throw InvalidRegenerateTargetError.noAssistantReply();
      }
    }
    if (latest == null || latest.role != Role.assistant) {
      throw InvalidRegenerateTargetError.noAssistantReply();
    }
    return latest;
  }

  /// 续写触发的「原消息末段」锚点：strip 后取末 [_continuationTailCodeUnits]
  /// 个 UTF-16 code unit（对齐桌面 `_continuation_tail` 的末 200 字符）；
  /// 短内容整体返回；空内容返回空串（触发只含指令）。
  ///
  /// 防劈代理对（F-114 先例）：截取窗口首 unit 为低位代理（0xDC00..0xDFFF，
  /// 其高代理在窗口外）时 +1 排除，避免孤立代理 → U+FFFD。桌面按 code point
  /// 计数，本实现按 code unit（含代理对内容时差 ≤1 unit），差异见
  /// concerns/02.md §4。
  String _continuationTail(String? content) {
    final text = (content ?? '').trim();
    if (text.isEmpty) {
      return '';
    }
    if (text.length <= _continuationTailCodeUnits) {
      return text;
    }
    final cut = text.substring(text.length - _continuationTailCodeUnits);
    final first = cut.codeUnitAt(0);
    if (first >= 0xDC00 && first <= 0xDFFF) {
      return text.substring(text.length - _continuationTailCodeUnits + 1);
    }
    return cut;
  }

  /// autoGreeting 零消息守卫（对齐 `message.py::auto_insert_greeting`）。
  ///
  /// 对话无任何消息且角色有非空 first_mes → 首条 assistant 开场白（模板变量
  /// `{{user}}/{{char}}` 与 [extraVars] 自定义变量替换后落库）；否则零副作用。
  /// F-139：判空读由 [MessageRepository.getMessages] 全量下推为
  /// [MessageRepository.lastMessage] 单值定位读（S6 语义化读面）。
  Future<void> _autoInsertGreeting(
    Conversation conv,
    Character character,
    String userName,
    Map<String, String> extraVars,
  ) async {
    final existing = await _messageRepository.lastMessage(conv.id);
    if (existing != null) {
      return; // 已有消息（含预插开场白）不重复插入。
    }
    if (character.firstMes.isEmpty) {
      return; // 角色无开场白。
    }
    final greeting = applyTemplateVars(
      character.firstMes,
      userName: userName,
      charName: character.name,
      extraVars: extraVars,
    );
    await _messageRepository.createMessage(
      conversationId: conv.id,
      role: Role.assistant,
      content: greeting,
    );
  }

  /// 组装上溯上下文共享段（F-149，C4）。
  ///
  /// 真实发送腿 [_assembleMessages] 与调试腿 [promptDebug] 各自重建的上溯段
  /// 单点收口：CharacterData 八字段投影 + 历史取数（[historyBeforeId] 非空 →
  /// `id < historyBeforeId` 定位读，重生成路径） + 世界书扫描（带来源、
  /// try/catch 降级）+ 叙述风格（开关/降级）——两端只付差异参，本段只跑一次。
  ///
  /// 共享段止于 `buildMessages` / `buildMessagesWithSource` 产物（两者共用
  /// 同一私有 `_assemble` 组装核心，content/role 序列逐条一致）：
  /// - **built**：经 `buildMessages` 的 `List<PromptMessage>`（send 腿用，
  ///   世界书块展平为纯字符串）；
  /// - **segments**：经 `buildMessagesWithSource` 的 `List<PromptSegment>`
  ///   （debug 腿用，世界书块带来源标注）。
  ///
  /// **注入豁免（有意声明，PD-04 契约面不变）**：memory 注入（AC-03）与
  /// 阶段 2 关系/thought 注入**不在本段**——它们只存在于 send 腿
  /// [_assembleMessages]（本就单源，非收敛对象）；debug 腿 [promptDebug]
  /// 维持注入豁免（「逐条一致」契约在 memory 缺省下成立）。
  Future<({List<PromptMessage> built, List<PromptSegment> segments})>
      _buildAssembleContext({
    required Conversation conv,
    required Character character,
    required int? historyBeforeId,
    required int maxRounds,
    required String userName,
    required bool appendCurrentInput,
    required String userContent,
    Map<String, String> extraVars = const {},
  }) async {
    final charData = CharacterData(
      name: character.name,
      systemPrompt: character.systemPrompt,
      personality: character.personality,
      scenario: character.scenario,
      mesExample: character.mesExample,
      postHistoryInstructions: character.postHistoryInstructions,
      // NPD-04：专家模式两字段透传 buildMessages（expert + 非空 → 单条
      // expert prompt 替代 system/scenario/PHI；expert + 空 → 回退 simple）。
      promptMode: character.promptMode,
      expertPrompt: character.expertPrompt,
    );
    final history = historyBeforeId == null
        ? await _messageRepository.getMessages(conv.id)
        : await _messageRepository.messagesBefore(conv.id, historyBeforeId);
    // WL-03：世界书扫描→激活→注入（与消息滑窗 maxRounds 解耦，扫描窗由条目
    // 最大 depth 决定）；世界书为空/全禁用 → 空块零注入。世界书读失败降级为
    // 空块不阻断主回复（对齐既有记忆注入降级先例）。
    // PD-04：带来源注入块（world/memory）在此透传（debug 腿）或展平为纯
    // 字符串（send 腿 buildMessages），逐字节零变化契约。
    Map<String, List<InjectedSegment>> world;
    try {
      world = await _buildLorebookInjection(
        character,
        history,
        userContent,
        userName,
      );
    } catch (e) {
      debugPrint('世界书注入失败，跳过: $e');
      world = const {};
    }
    // NPD-01 叙述风格：开关缺省开（opt-out）。开关开启 → 读取 rules（仓储内
    // 空回退默认常量）透传 buildMessages；开关关闭 → 不透传 rules（组装零注入
    // 且不读 rules）。设置读取失败 → 降级零注入不阻断主回复（对齐世界书注入
    // 降级先例）。
    String? narrativeStyle;
    try {
      if (await _settingsRepository.narrativeStyleEnabled) {
        narrativeStyle = await _settingsRepository.narrativeStyleRules;
      }
    } catch (e) {
      debugPrint('叙述风格读取失败，跳过: $e');
      narrativeStyle = null;
    }
    final historyMessages = [
      for (final m in history) HistoryMessage(role: m.role, content: m.content),
    ];
    final built = buildMessages(
      charData,
      history: historyMessages,
      userContent: userContent,
      maxRounds: maxRounds,
      userName: userName,
      appendCurrentInput: appendCurrentInput,
      extraVars: extraVars,
      world: {
        for (final entry in world.entries)
          entry.key: [for (final segment in entry.value) segment.content],
      },
      narrativeStyle: narrativeStyle,
      // NPD-02：会话快照透传（创建时固化的 presetDialogue；快照空/无 → null
      // 透传 → buildMessages 零注入。改角色卡 presetDialogues 实时值不影响
      // 已建会话——注入源恒为本快照列，验收 5/6）。
      presetDialogue: conv.presetDialogue,
    );
    final segments = buildMessagesWithSource(
      charData,
      history: historyMessages,
      userContent: userContent,
      maxRounds: maxRounds,
      userName: userName,
      appendCurrentInput: appendCurrentInput,
      extraVars: extraVars,
      world: world,
      narrativeStyle: narrativeStyle,
      presetDialogue: conv.presetDialogue,
    );
    return (built: built, segments: segments);
  }

  /// 组装发送给 LLM 的消息列表（角色字段 → CharacterData + 滑窗 + 历史 +
  /// 世界书注入 + 叙述风格 + 预设对话快照 + 专家模式分流）。
  ///
  /// 上溯段（CharacterData 八字段投影 / 历史 / 世界书 / 叙述风格）经
  /// [_buildAssembleContext] 与 debug 腿 [promptDebug] 共享单点；本方法在
  /// 共享产物之外追加 **send 腿独有**的 memory 注入（AC-03）与阶段 2
  /// 关系/thought 注入（见方法体，非 [_buildAssembleContext] 范围）。
  ///
  /// [historyBeforeId] 非空（重生成路径）时历史只取 `id < historyBeforeId`
  /// 的消息——桌面「先 delete_messages_from 截断、后组装」在**延迟删除**下以
  /// 定位读（[MessageRepository.messagesBefore]）等价实现，保证被重生成目标
  /// （及其后）不进入自身上下文。世界书扫描与消息列表共用该历史截止（桌面
  /// assemble_chat_context 逐字对齐）。
  ///
  /// NPD-02 预设对话：本方法为**唯一组装点**（streamReply / regenerate 共用），
  /// 读会话快照 `conv.presetDialogue` 透传 buildMessages——快照非空 → 注入；
  /// 快照空/会话无快照 → 不透传（buildMessages 零注入，验收 6）。
  ///
  /// NPD-04 专家模式：角色 [Character.promptMode] / [Character.expertPrompt]
  /// 原样透传 CharacterData → buildMessages（expert + 非空 → 单条 expert
  /// prompt 替代 system/scenario/PHI；expert + 空 → 回退 simple）。
  Future<List<LlmMessage>> _assembleMessages({
    required Conversation conv,
    required Character character,
    required int? historyBeforeId,
    required int maxRounds,
    required String userName,
    required bool appendCurrentInput,
    String userContent = '',
    Map<String, String> extraVars = const {},
  }) async {
    final context = await _buildAssembleContext(
      conv: conv,
      character: character,
      historyBeforeId: historyBeforeId,
      maxRounds: maxRounds,
      userName: userName,
      appendCurrentInput: appendCurrentInput,
      userContent: userContent,
      extraVars: extraVars,
    );
    final messages = [
      for (final m in context.built)
        LlmMessage(role: m.role, content: m.content),
    ];

    // AC-03 记忆注入：人格事实每轮重注入 + 记忆三模式指令 + 近期情景记忆。
    // 注入位置 = 人格 system（messages[0]）之后、scenario/few-shot 之前，保证
    // 抗 OOC 的事实紧随人设；记忆功能未启用（_memoryService == null）跳过。
    final memoryService = _memoryService;
    if (memoryService != null) {
      try {
        final mode = MemoryPromptMode.fromValue(
          await _settingsRepository.memoryPromptMode,
        );
        final injection = await memoryService.buildInjection(
          character.id,
          mode: mode,
        );
        if (injection.isNotEmpty) {
          final insertAt = messages.isEmpty ? 0 : 1;
          messages.insertAll(insertAt, injection);
        }
      } catch (e) {
        // 记忆注入失败不阻断主回复（降级：无记忆上下文，回复仍可用）。
        debugPrint('记忆注入失败，跳过: $e');
      }
    }

    // 阶段 2 注入：关系块（有状态行时，判定⑧）+ thought 指令（开关开时）。
    // 追加于消息尾部（行为指令，不干扰人设/记忆/场景结构）；任一失败降级跳过。
    final stage2Injections = <LlmMessage>[];
    final companionRepository = _companionRepository;
    if (companionRepository != null) {
      try {
        final state = await companionRepository.getRelationship(character.id);
        if (state != null) {
          stage2Injections.add(
            LlmMessage(
              role: 'system',
              content: RelationshipService.buildRelationshipInjection(
                stage: state.stage,
                affinity: state.affinity,
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('关系注入失败，跳过: $e');
      }
    }
    if (_thoughtService != null) {
      try {
        if (await _settingsRepository.innerThoughtEnabled) {
          stage2Injections.add(
            LlmMessage(role: 'system', content: buildThoughtInstruction()),
          );
        }
      } catch (e) {
        debugPrint('内心独白指令注入失败，跳过: $e');
      }
    }
    if (stage2Injections.isNotEmpty) {
      messages.addAll(stage2Injections);
    }

    return messages;
  }

  /// 构建 prompt-debug 追溯（PD-04；只读：零 LLM 零落库，SR-31）。
  ///
  /// 与真实发送走**同一组装核心与同一上游**（对齐桌面 `chat.py::
  /// build_prompt_debug`）：
  /// - 同一上游：[_buildAssembleContext] 共享段单点（[historyBeforeId]=null
  ///   全量历史 + 世界书扫描链路（手动→world / auto→memory 来源标注）+
  ///   叙述风格同一解析单点（`narrativeStyleEnabled` 门 + rules）+ 预设对话
  ///   快照 `conv.presetDialogue` + 专家模式两字段透传）；
  /// - 同一组装核心：[buildMessagesWithSource] 与 [buildMessages] 共用
  ///   `_assemble`（单一组装实现，不复制顺序），debug segments 的 content/role
  ///   序列与真实发送逐条一致（仅末条为 source=user 的空内容占位——桌面
  ///   build_prompt_debug 以 `user_content=""` + `append_current_input=True`
  ///   表达的「待回复输入槽」语义，验收 4/5）。
  ///
  /// **注入豁免（有意声明，PD-04 契约面不变）**：debug 腿**不含** memory 注入
  /// （AC-03）与阶段 2 关系/thought 注入——这两段仅存在于真实发送腿
  /// [_assembleMessages]（本就单源，非收敛对象）；「逐条一致」契约在 memory
  /// 缺省下成立（见 chat_service_test PD-04 验收 4），豁免为有意声明而非
  /// 静默缺口。
  ///
  /// 零外发保证：本方法只读仓储（会话/角色/设置/消息/世界书），不调用
  /// [_resolveProvider]（零 Provider 创建）、不落库任何消息（SR-31），本地
  /// 渲染零外发。
  ///
  /// 对话不存在 → [ConversationNotFoundError]；角色不存在 →
  /// [CharacterNotFoundError]（与真实发送路径同判）。
  Future<PromptDebugResult> promptDebug({required int conversationId}) async {
    final conv = await _conversationRepository.getConversation(conversationId);
    if (conv == null) {
      throw ConversationNotFoundError();
    }
    final character = await _characterRepository.getCharacter(conv.characterId);
    if (character == null) {
      throw CharacterNotFoundError(conv.characterId);
    }
    final userName = await _settingsRepository.userName;
    final extraVars = await _settingsRepository.templateVars;
    final maxRounds = await _settingsRepository.slidingWindowRounds;

    // 同一组装核心与同一上游：_buildAssembleContext 共享段（与真实发送腿同一
    // CharacterData 投影 / 历史 / 世界书扫描 / 叙述风格单点）；debug 参数面 =
    // historyBeforeId null（全量历史）+ userContent 空 + appendCurrentInput
    // true（桌面对齐的「待回复输入槽」）。
    final context = await _buildAssembleContext(
      conv: conv,
      character: character,
      historyBeforeId: null,
      maxRounds: maxRounds,
      userName: userName,
      appendCurrentInput: true,
      userContent: '',
      extraVars: extraVars,
    );

    return PromptDebugResult(
      characterName: character.name,
      // 对齐桌面 `f"{conv.model_provider}/{conv.model_name}"`。
      model: '${conv.modelProvider}/${conv.modelName}',
      promptMode: character.promptMode,
      segments: context.segments,
    );
  }

  /// 世界书扫描→激活→注入（WL-03 验收 4，对齐桌面 `chat.py::
  /// _lorebook_world_injection`）。
  ///
  /// 链路：listEntries → enabled 过滤 → 最大 depth → collectScanText（与消息
  /// 滑窗 maxRounds 解耦，扫描窗 = 最近 `max(depth)` 轮 = 2*depth 条对话 +
  /// 当前输入）→ activate（RNG 可注入，null 时引擎每次调用自建非确定性源）→
  /// buildWorldInjection（position 分组 + `{{user}}/{{char}}` 模板替换 + 来源
  /// 标注）→ 返回**带来源**注入块 `{before_char/after_char/system: [InjectedSegment]}`
  /// （world/memory 来源保真，PD-04 起不再展平——真实发送腿在
  /// [_assembleMessages] 处展平为纯字符串给 buildMessages，输出逐字节零变化）；
  /// debug 腿（[promptDebug]）直接透传 buildMessagesWithSource）。无启用条目
  /// → 空块零注入（不污染上下文）。
  Future<Map<String, List<InjectedSegment>>> _buildLorebookInjection(
    Character character,
    List<Message> history,
    String currentInput,
    String userName,
  ) async {
    final entries = await _lorebookRepository.listEntries(character.id);
    final enabled = [for (final e in entries) if (e.enabled) e];
    if (enabled.isEmpty) {
      return const {};
    }
    final depth = enabled.map((e) => e.depth).reduce(max);
    final scanText = collectScanText<Message>(
      history,
      currentInput,
      depth,
      roleOf: (m) => m.role.value,
      contentOf: (m) => m.content,
    );
    final dataEntries = [
      for (final e in enabled)
        LorebookEntryData(
          id: e.id,
          keys: e.keys,
          content: e.content,
          constant: e.constant,
          order: e.order,
          probability: e.probability,
          groupName: e.groupName,
          groupWeight: e.groupWeight,
          matchMode: e.matchMode,
          position: e.position,
          enabled: e.enabled,
        ),
    ];
    final activated = activateLorebookEntries(
      dataEntries,
      scanText,
      rng: _lorebookRandom,
    );
    final sourceById = {for (final e in enabled) e.id: e.source};
    return buildWorldInjection(
      activated,
      userName: userName,
      charName: character.name.isEmpty ? 'Character' : character.name,
      sourceById: sourceById,
    );
  }

  /// 组装生成参数组（SP-01）：conv 采样四列非空 → 覆盖；NULL → 走既有链
  /// （温度 = 角色为主、全局兜底 [resolveCharTemperature]；max_tokens = 全局
  /// [globalMaxTokens]；topP/presencePenalty/frequencyPenalty = null 不覆盖
  /// provider 默认）。
  ///
  /// SR-24 值域守卫（对齐 [resolveCharTemperature] F-76 防线）：conv 覆盖值非法
  /// （NaN / ±Infinity / 越界）clamp 或回退——**绝不透传**非法值给 wire。
  /// streamReply / regenerate / continueReply / editAndRegenerate 四路径共用
  /// 本单点（共享透传腿）。
  ({
    double temperature,
    int maxTokens,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  })
  _resolveSamplingParameters({
    required Conversation conv,
    required Character character,
    required double globalTemperature,
    required int globalMaxTokens,
  }) {
    return (
      temperature: resolveCharTemperature(character.temperature, globalTemperature),
      maxTokens: _resolveMaxTokens(conv.maxTokens, globalMaxTokens),
      topP: _guardSamplingRange(conv.topP, min: 0, max: 1),
      presencePenalty: _guardSamplingRange(
        conv.presencePenalty,
        min: -2,
        max: 2,
      ),
      frequencyPenalty: _guardSamplingRange(
        conv.frequencyPenalty,
        min: -2,
        max: 2,
      ),
    );
  }

  /// SR-24 值域守卫（SP-01）：可空采样覆盖值的 clamp/回退——NaN/±Infinity
  /// 回退 null（不覆盖 provider 默认）、越界 clamp 到 [min, max]（合法值
  /// 原样透传），绝不把非法值交给 wire。
  double? _guardSamplingRange(
    double? value, {
    required double min,
    required double max,
  }) {
    if (value == null || value.isNaN || value.isInfinite) {
      return null;
    }
    return value.clamp(min, max).toDouble();
  }

  /// SR-24 max_tokens 守卫（SP-01）：conv 覆盖值 < 1（0/负数非法）回退全局
  /// [globalMaxTokens]（沿 SettingsRepository「负数回退 defaultMaxTokens」
  /// 语义）；null 走全局既有链；合法值原样覆盖。
  int _resolveMaxTokens(int? value, int globalMaxTokens) {
    if (value == null || value < 1) {
      return globalMaxTokens;
    }
    return value;
  }

  /// provider 解析（AR-3：委派 [CredentialsResolver]——组合序单一归属
  /// `credentials_resolver.dart`，镜像 `resolver.py::resolve_llm`）。conv 的
  /// provider/model 覆盖非空优先，空回退设置默认；空 key 抛
  /// [ApiKeyMissingError]「未配置 {provider} API Key，请在设置中填写」；base_url
  /// 空 → null；工厂派生抛 [ProviderNotSupportedError]（未知 Provider）。
  Future<({String provider, String model, LLMProvider llm})> _resolveProvider(
    Conversation conv,
  ) async {
    final resolved = await _credentialsResolver.resolve(
      providerOverride: conv.modelProvider,
      modelOverride: conv.modelName,
    );
    final llm = _providerFactory.create(
      provider: resolved.provider,
      apiKey: resolved.apiKey,
      baseUrl: resolved.baseUrl,
    );
    return (provider: resolved.provider, model: resolved.model, llm: llm);
  }

  /// 解析重生成目标并校验（对话归属 + 必须为 assistant；对齐
  /// `chat.py::_resolve_regenerate_target`）。
  ///
  /// 显式 [messageId]：经 [MessageRepository.messageById] 定位（跨对话同 id
  /// 或不存在 → [MessageNotFoundError]，与原「对话内线性遍历未命中」逐位
  /// 等价）；缺省：经 [MessageRepository.lastAssistantMessage] 取末条
  /// assistant（无 → [InvalidRegenerateTargetError.noAssistantReply]）。
  Future<Message> _resolveRegenerateTarget(
    int conversationId,
    int? messageId,
  ) async {
    if (messageId != null) {
      final target = await _messageRepository.messageById(
        conversationId,
        messageId,
      );
      if (target == null) {
        throw MessageNotFoundError();
      }
      if (target.role != Role.assistant) {
        throw InvalidRegenerateTargetError.notAssistant();
      }
      return target;
    }
    // 缺省：末条 assistant（定位读 DESC 序首条，同秒 id 兜底）。
    final lastAssistant = await _messageRepository.lastAssistantMessage(
      conversationId,
    );
    if (lastAssistant == null) {
      throw InvalidRegenerateTargetError.noAssistantReply();
    }
    return lastAssistant;
  }

  /// 返回 [targetId] 之前最近的一条 user 消息（重生成触发源）；无则 null
  /// （对齐 `chat.py::_last_user_before`）。
  Future<Message?> _lastUserBefore(int conversationId, int targetId) {
    return _messageRepository.lastUserMessageBefore(conversationId, targetId);
  }
}
