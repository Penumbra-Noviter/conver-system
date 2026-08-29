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
///
/// ## 重生成（A4，延迟删除）
/// 目标 = 末条 assistant（缺省，PK 锚定）；截断锚定 target.id；组装走
/// `append_current_input=False`（无幽灵 user）；先校验/组装 + non-streaming 生成
/// （网络在事务外），成功后 `db.transaction` 删旧 + 插新一次提交；失败不删行、
/// 旧消息保留。
///
/// ## 断流（A5）
/// 流终止未到终态（连接异常 / 未收终态帧）→ 已累积部分落库 + 非阻塞
/// [ChatInterrupted]「回复已中断」。R3 seam 契约：wire 层（T02）把流中途
/// 断连（EOF 未到终态 / 连接重置）翻译为可区分的 [LLMConnectionInterruptedError]
/// （LLM 族子类，errors.dart 共享）；连接阶段失败（SocketException / HTTP
/// 403 / 404 / 422 等经 `translateSdkError` 兜底）与业务错误（Auth /
/// RateLimit / Timeout / ContentFilter 等）为其子类/基类，不算断流。故
/// [_isConnectionDrop] 以「严格子类」判型即断流判定。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../data/database/app_database.dart';
import '../data/database/tables.dart' show Role;
import '../data/repositories/character_repository.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'llm/errors.dart';
import 'llm/llm_provider.dart';
import 'llm/prompt.dart';
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
    required this.conversationId,
  });

  /// 新生成的完整回复文本。
  final String reply;

  /// 新落库的 assistant 消息 id。
  final int messageId;

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
/// - [ConversationNotFoundError] / [MessageNotFoundError] → 404 + str(exc)；
/// - [ApiKeyMissingError] / [ProviderNotSupportedError] /
///   [InvalidRegenerateTargetError] / [RegenerateBusyError] → 400 + str(exc)；
/// - 未知 [DomainError] 子类 → 400 + str(e) 兜底（防御性）。
({int status, String message}) domainErrorResponse(DomainError error) {
  if (error is ConversationNotFoundError || error is MessageNotFoundError) {
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
/// 契约（T02 wire 层遵守）：流中途断连（EOF 未收终态帧 / 连接重置）→ 可区分
/// 的 [LLMConnectionInterruptedError]（LLM 族子类，errors.dart 共享，Claude /
/// OpenAI wire 一致抛出）。**严格子类判型**：连接阶段失败（SocketException /
/// HTTP 403 / 404 / 422 等经 `translateSdkError` 兜底翻译）为**基类**
/// [LLMError]，不算断流 → 走业务错误 [ChatError]（F-45 不落部分内容）；业务
/// 错误（Auth / RateLimit / Timeout / ContentFilter / BadRequest /
/// ResponseParseFailed）为其子类，同样不走断流分支。
bool _isConnectionDrop(LLMError error) => error is LLMConnectionInterruptedError;

/// [streamReply] 一次运行的共享可变状态（onData / onCancel / 收尾 handler 间
/// 传递：完整内容累积、是否已落库、provider 订阅句柄、停止标志）。
class _StreamRunState {
  _StreamRunState({required this.conversationId, required this.content});

  /// 目标对话 id。
  final int conversationId;

  /// 用户输入内容。
  final String content;

  /// 已停止：调用方取消订阅（或停止收尾完成）后置位。
  bool stopped = false;

  /// 部分/完整内容是否已落库（幂等防护，防 onDone 与 onCancel 双重保存）。
  bool saved = false;

  /// 已累积的流式内容（逐 token 追加；完成态即完整回复）。
  String fullContent = '';

  /// provider 流订阅（停止时直接 cancel，不等待待处理元素）。
  StreamSubscription<String>? providerSub;
}

/// 一次聊天回合的编排服务。
///
/// 构造依赖：drift 数据库（重生成单事务）+ 四仓储（消息 / 对话 / 角色 / 设置）
/// + [LLMProviderFactory]（Provider 装配抽象）。无平台存储 / 视图依赖。
class ChatService {
  /// [database] 供重生成的「删旧 + 插新」单事务（drift 嵌套事务 = savepoint）；
  /// [settingsRepository] 提供 Key 解析链与滑窗轮数等设置。
  ChatService({
    required AppDatabase database,
    required this._conversationRepository,
    required this._characterRepository,
    required this._messageRepository,
    required this._settingsRepository,
    required this._providerFactory,
  }) : _db = database;

  final AppDatabase _db;
  final ConversationRepository _conversationRepository;
  final CharacterRepository _characterRepository;
  final MessageRepository _messageRepository;
  final SettingsRepository _settingsRepository;
  final LLMProviderFactory _providerFactory;

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
  /// 断流（A5）：provider 流抛出 [LLMConnectionInterruptedError]（流中途断连）
  /// → 已累积部分落库 + 非阻塞 [ChatInterrupted]「回复已中断」；无部分 →
  /// [ChatInterrupted(null)]。
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
      final conv =
          await _conversationRepository.getConversation(state.conversationId);
      if (conv == null) {
        throw ConversationNotFoundError();
      }
      final character = await _characterRepository.getCharacter(conv.characterId);
      if (character == null) {
        throw StateError('角色不存在: ${conv.characterId}');
      }
      final userName = await _settingsRepository.userName;

      // 2. autoGreeting 零消息守卫。
      await _autoInsertGreeting(conv, character, userName);

      // 3. 落库 user 消息。
      await _messageRepository.createMessage(
        conversationId: state.conversationId,
        role: Role.user,
        content: state.content,
      );

      // 4. 组装消息列表。
      final maxRounds = await _settingsRepository.slidingWindowRounds;
      final messages = await _assembleMessages(
        conv: conv,
        character: character,
        historyBeforeId: null,
        maxRounds: maxRounds,
        userName: userName,
        appendCurrentInput: true,
        userContent: state.content,
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
      //    不再触发 onDone 造成双处置。
      final sub = resolved.llm
          .streamGenerate(messages: messages, model: resolved.model)
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
                _onProviderStreamError(state, controller, providerName, error),
              );
            },
            onDone: () {
              unawaited(_onProviderStreamDone(state, controller));
            },
            cancelOnError: true,
          );
      state.providerSub = sub;
    } on DomainError catch (e) {
      // F3：调用方可能在解析失败瞬间取消订阅（controller 已 close），
      // add 到已关闭 controller 抛 StateError → 未处理异步异常；守卫跳过。
      if (!controller.isClosed) {
        controller.add(ChatError(domainErrorResponse(e).message));
        await controller.close();
      }
    } on LLMError catch (e) {
      // 组装/解析阶段不产生 LLMError（Provider 尚未调用）；防御性兜底。
      if (!controller.isClosed) {
        state.saved = true; // F-45。
        controller.add(ChatError(llmErrorResponse(e, providerName).message));
        await controller.close();
      }
    } catch (e) {
      // 未预期异常 → ChatError（对齐桌面 O3 语义），不落部分内容。
      if (!controller.isClosed) {
        state.saved = true;
        controller.add(ChatError('生成回复失败: $e'));
        await controller.close();
      }
    }
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
      // F3 同类硬化：onDone 与 onCancel 竞态（收尾瞬间取消）下 controller 可能
      // 已关闭，add 前守卫避免 add-after-close 的未处理异常。
      if (!controller.isClosed) {
        controller.add(
            msg != null ? ChatDone(msg.id) : const ChatDone(null));
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

  /// provider 流异常收尾：断流（[LLMConnectionInterruptedError]）/ 业务错误 /
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
            msg != null
                ? ChatInterrupted(msg.id)
                : const ChatInterrupted(null),
          );
        } else {
          // LLM 业务错误：F-45 不落部分内容。
          state.saved = true;
          controller.add(ChatError(llmErrorResponse(error, providerName).message));
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
  /// 元素），已累积部分落库（无部分 → 仅保留已发 user），关闭事件流。
  Future<void> _stopStreamReply(
    _StreamRunState state,
    StreamController<ChatEvent> controller,
  ) async {
    if (state.stopped) {
      return; // 幂等。
    }
    state.stopped = true;
    await state.providerSub?.cancel();
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

  /// 幂等落库已累积部分/完整内容为 assistant 消息（A3 停止 / A5 断流 / done
  /// 共用）。无内容或已落库 → 返回 null；落库成功 → 返回消息行。
  ///
  /// 调用方负责错误处理（DB 写失败按各路径语义收口）。
  Future<Message?> _persistAssistant(_StreamRunState state) async {
    if (state.fullContent.isEmpty || state.saved) {
      return null;
    }
    state.saved = true;
    return _messageRepository.createMessage(
      conversationId: state.conversationId,
      role: Role.assistant,
      content: state.fullContent,
    );
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
  /// 抛出：领域错误（[ConversationNotFoundError] / [MessageNotFoundError] /
  /// [InvalidRegenerateTargetError] / [RegenerateBusyError] /
  /// [ApiKeyMissingError] / [ProviderNotSupportedError]）与 [LLMError]
  /// （生成失败，UI 经 [llmErrorResponse] 映射）。
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
      final conv = await _conversationRepository.getConversation(conversationId);
      if (conv == null) {
        throw ConversationNotFoundError();
      }

      // F1：快照当前最大消息 id。网络生成期间并发写入的新消息 id 严格递增
      // （> snapshotMaxId），必须在事务删旧时保留，否则无界删除会连带删掉
      // 这条新 user 消息（静默数据丢失）。
      final snapshotMaxId = await _messageRepository.maxMessageId(conversationId);

      // 2. 解析并校验目标。
      final target = await _resolveRegenerateTarget(conversationId, messageId);

      // 3. 校验触发源（截断后必须存在 user 消息）。
      final trigger = await _lastUserBefore(conversationId, target.id);
      if (trigger == null) {
        throw InvalidRegenerateTargetError.noTriggerUser();
      }

      // 4. 组装（append_current_input=False）+ provider 解析。延迟删除：此步抛错
      //    不触碰 DB，旧消息保留。
      final character = await _characterRepository.getCharacter(conv.characterId);
      if (character == null) {
        throw StateError('角色不存在: ${conv.characterId}');
      }
      final userName = await _settingsRepository.userName;
      final maxRounds = await _settingsRepository.slidingWindowRounds;
      final messages = await _assembleMessages(
        conv: conv,
        character: character,
        historyBeforeId: target.id,
        maxRounds: maxRounds,
        userName: userName,
        appendCurrentInput: false,
      );
      final resolved = await _resolveProvider(conv);

      // 5. 生成（网络在事务外；LLM 失败 → 异常上抛，未删行、旧消息保留）。
      final reply =
          await resolved.llm.generate(messages: messages, model: resolved.model);

      // 6. 单事务：有界删旧（target.id <= id <= snapshotMaxId）+ 插新一次提交
      //    （drift 嵌套事务 = savepoint，任一失败整体回滚，防半截断持久化）。
      final saved = await _db.transaction(() async {
        await _messageRepository.deleteMessagesFrom(conversationId, target.id,
            toId: snapshotMaxId);
        return _messageRepository.createMessage(
          conversationId: conversationId,
          role: Role.assistant,
          content: reply,
        );
      });

      return RegenerateResult(
        reply: reply,
        messageId: saved.id,
        conversationId: conversationId,
      );
    } finally {
      _regenerateInFlight.remove(conversationId);
    }
  }

  /// autoGreeting 零消息守卫（对齐 `message.py::auto_insert_greeting`）。
  ///
  /// 对话无任何消息且角色有非空 first_mes → 首条 assistant 开场白（模板变量
  /// `{{user}}/{{char}}` 替换后落库）；否则零副作用。
  Future<void> _autoInsertGreeting(
    Conversation conv,
    Character character,
    String userName,
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
    );
    return [
      for (final m in built) LlmMessage(role: m.role, content: m.content),
    ];
  }

  /// provider 解析（对齐 `resolver.py::resolve_llm`）：Key 解析链经设置仓储，
  /// 空 → [ApiKeyMissingError]「未配置 {provider} API Key，请在设置中填写」；
  /// base_url 空 → null；model 缺省回退设置默认。工厂派生抛
  /// [ProviderNotSupportedError]（未知 Provider）。
  Future<({String provider, String model, LLMProvider llm})>
      _resolveProvider(Conversation conv) async {
    final provider = conv.modelProvider.isNotEmpty
        ? conv.modelProvider
        : await _settingsRepository.defaultProvider;
    final key = await _settingsRepository.apiKey(provider);
    if (key.isEmpty) {
      throw ApiKeyMissingError(provider);
    }
    final baseUrl = await _settingsRepository.baseUrl(provider);
    final model = conv.modelName.isNotEmpty
        ? conv.modelName
        : await _settingsRepository.defaultModel;
    final llm = _providerFactory.create(
      provider: provider,
      apiKey: key,
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
    );
    return (provider: provider, model: model, llm: llm);
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
