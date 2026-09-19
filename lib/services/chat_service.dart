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
/// ## 重生成（A4，延迟删除）
/// 目标 = 末条 assistant（缺省，PK 锚定）；截断锚定 target.id；组装走
/// `append_current_input=False`（无幽灵 user）；先校验/组装 + non-streaming 生成
/// （网络在事务外），成功后 `db.transaction` 删旧 + 插新一次提交；失败不删行、
/// 旧消息保留。
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

import 'package:flutter/foundation.dart' show debugPrint;

import '../data/database/app_database.dart';
import '../data/database/tables.dart' show Role;
import '../data/repositories/character_repository.dart';
import '../data/repositories/companion_repository.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'companion/relationship_service.dart';
import 'companion/thought_service.dart';
import 'llm/credentials_resolver.dart';
import 'llm/errors.dart';
import 'llm/llm_provider.dart';
import 'llm/prompt.dart';
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
class RegenerateResult {
  const RegenerateResult({
    required this.reply,
    required this.messageId,
    required this.replacedMessageId,
    required this.conversationId,
  });

  /// 新生成的完整回复文本。
  final String reply;

  /// 新落库的 assistant 消息 id。
  final int messageId;

  /// 被替换的旧 assistant 目标行 id（= regenerate 有界删旧前解析的实际替换
  /// 目标，F-64 截断结算键）——客户端以本字段作结算键，零预解析。
  final int replacedMessageId;

  /// 所属对话 id。
  final int conversationId;
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
/// 构造依赖：drift 数据库（重生成单事务）+ 四仓储（消息 / 对话 / 角色 / 设置）
/// + [LLMProviderFactory]（Provider 装配抽象）。无平台存储 / 视图依赖。
class ChatService {
  /// [database] 供重生成的「删旧 + 插新」单事务（drift 嵌套事务 = savepoint）；
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
    List<EndOfTurnHook> endOfTurnHooks = const [],
    List<Duration> connectRetryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) : _db = database,
       _endOfTurnHooks = List<EndOfTurnHook>.unmodifiable(endOfTurnHooks),
       _connectRetryDelays = List<Duration>.unmodifiable(connectRetryDelays) {
    _credentialsResolver = credentialsResolver ?? _wireCredentialsResolver();
  }

  final AppDatabase _db;
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

  /// F4：重生成 in-flight 对话集（并发双触发守卫——同对话 in-flight 期间
  /// 第二次调用抛 [RegenerateBusyError]，防第二次事务删掉第一次的新回复）。
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

      // 4b. 组装生成参数（工单 03）：温度按「角色为主、全局兜底」，max_tokens
      // 取全局设置。
      final globalTemperature = await _settingsRepository.getTemperature();
      final temperature = _resolveTemperature(character, globalTemperature);
      final maxTokens = await _settingsRepository.getMaxTokens();

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
        temperature: temperature,
        maxTokens: maxTokens,
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
        controller.add(ChatError(domainErrorResponse(e).message));
        await controller.close();
      }
    } on LLMError catch (e) {
      // 组装/解析阶段不产生 LLMError（Provider 尚未调用）；防御性兜底。
      _settleUserWriteGate(state);
      if (!controller.isClosed) {
        state.saved = true; // F-45。
        controller.add(ChatError(llmErrorResponse(e, providerName).message));
        await controller.close();
      }
    } catch (e) {
      // 未预期异常 → ChatError（对齐桌面 O3 语义），不落部分内容。
      _settleUserWriteGate(state);
      if (!controller.isClosed) {
        state.saved = true;
        controller.add(ChatError('生成回复失败: $e'));
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
            ChatError(llmErrorResponse(error, providerName).message),
          );
        }
      } else if (error is DomainError) {
        controller.add(ChatError(domainErrorResponse(error).message));
      } else {
        state.saved = true; // F-45。
        controller.add(ChatError('生成回复失败: $error'));
      }
    } catch (e) {
      // 断流部分落库失败（如流式中对话被删）→ 收口为 ChatError。
      // 挂起期间用户停止 → controller 已关闭 → 跳过发事件（对齐外层守卫）。
      if (!controller.isClosed) {
        controller.add(ChatError('生成回复失败: $e'));
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

  /// 重生成对话中目标 AI 回复（A4，缺省末条 assistant）。
  ///
  /// 编排（对齐 `chat.py::regenerate_chat` + 移动端**延迟删除**定案）：
  /// 0. F4 并发守卫：同对话 in-flight 期间第二次调用抛 [RegenerateBusyError]；
  /// 1. 校验对话存在，并捕获 `snapshotMaxId`（当前最大消息 id，F1 有界删除上界）；
  /// 2. 解析目标：显式 [messageId] 或末条 assistant；目标非 assistant →
  ///    [InvalidRegenerateTargetError.notAssistant]；不存在 → [MessageNotFoundError]
  ///    / [InvalidRegenerateTargetError.noAssistantReply]；
  /// 3. 校验触发源：目标之前须有 user 消息，否则拒绝「没有可重生成的用户消息」；
  /// 4. 组装（`append_current_input=False`，历史截断锚定 target.id——桌面「先截
  ///    断后组装」在延迟删除下以读侧过滤等价实现）+ provider 解析（Key 链）；
  /// 5. non-streaming 生成（网络在事务外）；**失败不删行，旧消息保留**；
  /// 6. 成功后 `db.transaction` **有界删旧**（`target.id <= id <= snapshotMaxId`）
  ///    + 插新一次提交；生成期间并发写入的新消息（id > snapshotMaxId）保留，
  ///    新回复以新 id 落在其后（F1 数据完整性）。
  ///
  /// 返回 [RegenerateResult.replacedMessageId] = 步骤 2 解析的实际替换目标行 id
  /// （有界删旧前已知）——客户端截断结算键（F-64 单一来源），无需预解析。
  ///
  /// 抛出：领域错误（[ConversationNotFoundError] / [CharacterNotFoundError] /
  /// [MessageNotFoundError] / [InvalidRegenerateTargetError] /
  /// [RegenerateBusyError] / [ApiKeyMissingError] / [ProviderNotSupportedError]）
  /// 与 [LLMError]（生成失败，UI 经 [llmErrorResponse] 映射）。
  Future<RegenerateResult> regenerate({
    required int conversationId,
    int? messageId,
  }) async {
    // F4：并发双触发守卫。网络生成可挂起（秒级），第二次调用基于同一快照解析
    // 目标会把第一次的新回复当截断目标删掉；in-flight 期间直接拒绝。
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

      // F1：快照当前最大消息 id。网络生成期间并发写入的新消息 id 严格递增
      // （> snapshotMaxId），必须在事务删旧时保留，否则无界删除会连带删掉
      // 这条新 user 消息（静默数据丢失）。
      final snapshotMaxId = await _messageRepository.maxMessageId(
        conversationId,
      );

      // 2. 解析并校验目标。
      final target = await _resolveRegenerateTarget(conversationId, messageId);

      // 3. 校验触发源（截断后必须存在 user 消息）。
      final trigger = await _lastUserBefore(conversationId, target.id);
      if (trigger == null) {
        throw InvalidRegenerateTargetError.noTriggerUser();
      }

      // 4. 组装（append_current_input=False）+ provider 解析。延迟删除：此步抛错
      //    不触碰 DB，旧消息保留。
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

      // 4b. 组装生成参数（工单 03）：温度按「角色为主、全局兜底」，max_tokens
      // 取全局设置（与 streamReply 同组装语义）。
      final globalTemperature = await _settingsRepository.getTemperature();
      final temperature = _resolveTemperature(character, globalTemperature);
      final maxTokens = await _settingsRepository.getMaxTokens();

      // 5. 生成（网络在事务外；LLM 失败 → 异常上抛，未删行、旧消息保留）。
      final reply = await resolved.llm.generate(
        messages: messages,
        model: resolved.model,
        temperature: temperature,
        maxTokens: maxTokens,
      );

      // 6. 单事务：有界删旧（target.id <= id <= snapshotMaxId）+ 插新一次提交
      //    （drift 嵌套事务 = savepoint，任一失败整体回滚，防半截断持久化）。
      final saved = await _db.transaction(() async {
        await _messageRepository.deleteMessagesFrom(
          conversationId,
          target.id,
          toId: snapshotMaxId,
        );
        return _messageRepository.createMessage(
          conversationId: conversationId,
          role: Role.assistant,
          content: reply,
        );
      });

      return RegenerateResult(
        reply: reply,
        messageId: saved.id,
        replacedMessageId: target.id,
        conversationId: conversationId,
      );
    } finally {
      _regenerateInFlight.remove(conversationId);
    }
  }

  /// autoGreeting 零消息守卫（对齐 `message.py::auto_insert_greeting`）。
  ///
  /// 对话无任何消息且角色有非空 first_mes → 首条 assistant 开场白（模板变量
  /// `{{user}}/{{char}}` 与 [extraVars] 自定义变量替换后落库）；否则零副作用。
  Future<void> _autoInsertGreeting(
    Conversation conv,
    Character character,
    String userName,
    Map<String, String> extraVars,
  ) async {
    final existing = await _messageRepository.getMessages(conv.id);
    if (existing.isNotEmpty) {
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

  /// 组装发送给 LLM 的消息列表（角色字段 → CharacterData + 滑窗 + 历史）。
  ///
  /// [historyBeforeId] 非空（重生成路径）时历史只取 `id < historyBeforeId`
  /// 的消息——桌面「先 delete_messages_from 截断、后组装」在**延迟删除**下以
  /// 读侧过滤等价实现，保证被重生成目标（及其后）不进入自身上下文。
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
    final charData = CharacterData(
      name: character.name,
      systemPrompt: character.systemPrompt,
      personality: character.personality,
      scenario: character.scenario,
      mesExample: character.mesExample,
      postHistoryInstructions: character.postHistoryInstructions,
    );
    final allHistory = await _messageRepository.getMessages(conv.id);
    final history = historyBeforeId == null
        ? allHistory
        : allHistory.where((m) => m.id < historyBeforeId);
    final built = buildMessages(
      charData,
      history: history.map(
        (m) => HistoryMessage(role: m.role, content: m.content),
      ),
      userContent: userContent,
      maxRounds: maxRounds,
      userName: userName,
      appendCurrentInput: appendCurrentInput,
      extraVars: extraVars,
    );
    final messages = [
      for (final m in built) LlmMessage(role: m.role, content: m.content),
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

  /// 组装采样温度：角色 `character.temperature` 为主、全局 [globalTemperature]
  /// 兜底（工单 03 判定契约，spec §U-2 高不确定点）。
  ///
  /// 角色温度 == [SettingsRepository.defaultTemperature]（0.7，DB 默认）判定为
  /// 「未显式覆盖」→ 回退全局值；接受「显式设 0.7 会被全局覆盖」的边界。
  ///
  /// 防御（F-76）：DB 层无 CHECK 约束，`character.temperature` 可能为
  /// NaN/Infinity（`==` 对 NaN 恒 false 会误判「已覆盖」透传致 API 400）或
  /// 越界值——NaN/Infinity 回退全局、越界 clamp 到合法区间
  /// [SettingsRepository.temperatureMin, temperatureMax]（对齐
  /// `SettingsRepository.getTemperature` 契约）。
  double _resolveTemperature(Character character, double globalTemperature) {
    final temperature = character.temperature;
    if (temperature.isNaN ||
        temperature.isInfinite ||
        temperature == SettingsRepository.defaultTemperature) {
      return globalTemperature;
    }
    return temperature
        .clamp(
          SettingsRepository.temperatureMin,
          SettingsRepository.temperatureMax,
        )
        .toDouble();
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
  Future<Message> _resolveRegenerateTarget(
    int conversationId,
    int? messageId,
  ) async {
    final messages = await _messageRepository.getMessages(conversationId);
    if (messageId != null) {
      Message? target;
      for (final m in messages) {
        if (m.id == messageId) {
          target = m;
          break;
        }
      }
      if (target == null) {
        throw MessageNotFoundError();
      }
      if (target.role != Role.assistant) {
        throw InvalidRegenerateTargetError.notAssistant();
      }
      return target;
    }
    // 缺省：末条 assistant（getMessages 为 created_at 正序 / id 兜底）。
    for (final m in messages.reversed) {
      if (m.role == Role.assistant) {
        return m;
      }
    }
    throw InvalidRegenerateTargetError.noAssistantReply();
  }

  /// 返回 [targetId] 之前最近的一条 user 消息（重生成触发源）；无则 null
  /// （对齐 `chat.py::_last_user_before`）。
  Future<Message?> _lastUserBefore(int conversationId, int targetId) async {
    final messages = await _messageRepository.getMessages(conversationId);
    Message? last;
    for (final m in messages) {
      if (m.role == Role.user && m.id < targetId) {
        last = m;
      }
    }
    return last;
  }
}
