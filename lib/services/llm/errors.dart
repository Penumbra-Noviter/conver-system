/// LLM 错误族 + 领域错误族 + 传输异常翻译 — 纯 Dart，零 I/O 依赖（不依赖
/// dio / dart:io，传输异常以 [translateSdkError] 原语入参）。
///
/// 桌面权威源（只读，语义锚点）：
/// - `desktop/backend/app/services/llm/errors.py::translate_sdk_error`（LLM 族模板）
/// - `desktop/backend/app/services/exceptions.py`（领域错误族）
/// - `desktop/backend/app/services/llm/resolver.py`（ApiKeyMissing / ProviderNotSupported 文案）
/// - `desktop/backend/app/services/chat.py`（InvalidRegenerateTarget / MessageNotFound 文案）
library;

/// LLM 调用错误基类（同时充当未分类兜底）。
class LLMError implements Exception {
  LLMError(this.message, {this.originalError});

  /// 用户可读消息（逐字对齐桌面 errors.py 模板）。
  final String message;

  /// 引发本次失败的下层异常（wire 层原始异常 / 原语 cause），可空。
  final Object? originalError;

  @override
  String toString() => message;
}

/// API Key 无效或未配置。
class LLMAuthError extends LLMError {
  LLMAuthError(String provider, {super.originalError})
      : super('$provider API Key 无效或未配置');
}

/// 请求频率超限。
class LLMRateLimitError extends LLMError {
  LLMRateLimitError(String provider, {super.originalError})
      : super('$provider API 请求频率超限');
}

/// 请求超时。
class LLMTimeoutError extends LLMError {
  LLMTimeoutError(String provider, {super.originalError})
      : super('$provider API 请求超时');
}

/// 内容被 Provider 内容过滤器拦截。
class LLMContentFilterError extends LLMError {
  LLMContentFilterError(String provider, {super.originalError})
      : super('内容被 $provider 内容过滤器拦截');
}

/// 请求本身被拒（HTTP 400 类）。
class LLMBadRequestError extends LLMError {
  LLMBadRequestError(String provider, String error, {super.originalError})
      : super('$provider API 请求错误: $error');
}

/// 响应解析失败（如 relay 返回非标准结构）。
class LLMResponseParseFailedError extends LLMError {
  LLMResponseParseFailedError(String provider, String detail, {super.originalError})
      : super(
          '$provider API 返回格式异常：$detail。'
          '请检查 API 地址是否为兼容 $provider 协议的端点（应返回标准响应结构）',
        );
}

/// 流在终态前中断（EOF 未收终态帧 / 连接重置）的可区分连接异常基类——两相位
/// 叶子（[ConnectPhaseInterruptedError] / [ReadPhaseInterruptedError]）共享的
/// **断流伞**。
///
/// 共享于 Claude（message_stop 前 EOF / 连接重置）与 OpenAI（[DONE] 前 EOF /
/// 连接重置）双协议 wire 层，供服务层（T03 ChatService `_isConnectionDrop`）
/// 与 UI 统一捕获：继承 LLM 错误族（[LLMError]），`translateError` 直通不
/// 二次翻译；区别于正常完成与鉴权 / 限流 / 超时 / 内容过滤等业务错误——业务
/// 错误不落部分内容（F-45），连接中断走「回复已中断」部分落库分支。
///
/// **语义**：concrete 保留为**不可重试的断流兜底信号**——生产抛点全部迁移到
/// 两相位叶子；聊天链路自动重试（M6-06）只认 [ConnectPhaseInterruptedError]，
/// 基类 / [ReadPhaseInterruptedError] 一律走既有断流收束（B2 行为变更点）。
class LLMConnectionInterruptedError extends LLMError {
  LLMConnectionInterruptedError({super.originalError})
      : super('连接中断，回复未完成');
}

/// **连接相位 (connect phase)** 传输失败：wire 连接建立段（postUrl → 写请求体
/// → close 等到响应头，**未收到状态码**）的失败——DNS / 拒连 / 连接超时 /
/// 响应头前断。确定未产生服务端生成。
///
/// 编码为 [ConnectPhaseInterruptedError]（stream_wire.dart connect 段 2 catch
/// 收敛）；是聊天链路自动重试（M6-06）的**唯一可重试面**（重试判据 = 本类型
/// + 次数上限；构造性保证无 token——token 必在 read 段产出）。
class ConnectPhaseInterruptedError extends LLMConnectionInterruptedError {
  ConnectPhaseInterruptedError({super.originalError});
}

/// **读取相位 (read phase)** 失败：已收到响应头后读 SSE 段期间的失败——流中途
/// EOF（未收终态帧）/ 连接重置 / idle 超时 / 空 200 体非终态 EOF。不可重试。
///
/// 编码为 [ReadPhaseInterruptedError]（stream_wire.dart 读段 2 catch +
/// `!reachedTerminated` 非终态 EOF 收敛）；服务层断流收束（部分落库 +
/// [ChatInterrupted]）对基类与两叶子同判（断流伞判型）。
class ReadPhaseInterruptedError extends LLMConnectionInterruptedError {
  ReadPhaseInterruptedError({super.originalError});
}

/// 非 HTTP 响应的传输失败类别（wire 层从传输异常解出的原语，见 [translateSdkError]）。
enum LlmTransportFailure {
  /// 连接/读取超时。
  timeout,

  /// 收到的响应无法按协议结构解析（非标准端点）。
  responseParse,
}

/// 将传输层失败原语统一翻译为 LLM 错误族（对应桌面 `translate_sdk_error`）。
///
/// 移动端 wire 层不持有 SDK 异常类，因此以（HTTP 状态码 / 消息文本 / 失败类别 /
/// 原始 cause）原语入参；映射语义逐条对齐桌面锚：
/// - `401` → Auth「{provider} API Key 无效或未配置」；
/// - `429` → RateLimit「{provider} API 请求频率超限」；
/// - [LlmTransportFailure.timeout] → Timeout「{provider} API 请求超时」；
/// - `400` 且消息含 `content_filter` → ContentFilter「内容被 {provider} 内容过滤器拦截」，
///   否则 BadRequest「{provider} API 请求错误: {error}」；
/// - [LlmTransportFailure.responseParse] → ResponseParseFailed「{provider} API 返回格式
///   异常：…。请检查 API 地址是否为兼容 {provider} 协议的端点（应返回标准响应结构）」；
/// - 其余（401/429/400 之外的 4xx 如 403/404/422、5xx、连接失败、无信号）→ 兜底
///   「{provider} API 调用失败: {error}」（对齐桌面 SDK 仅 400/401/429 归专属错误类）。
LLMError translateSdkError(
  String provider, {
  int? statusCode,
  String message = '',
  LlmTransportFailure? failure,
  Object? cause,
}) {
  if (failure == LlmTransportFailure.timeout) {
    return LLMTimeoutError(provider, originalError: cause);
  }
  if (statusCode == 401) {
    return LLMAuthError(provider, originalError: cause);
  }
  if (statusCode == 429) {
    return LLMRateLimitError(provider, originalError: cause);
  }
  if (statusCode == 400) {
    if (message.toLowerCase().contains('content_filter')) {
      return LLMContentFilterError(provider, originalError: cause);
    }
    return LLMBadRequestError(provider, _detail(message, cause), originalError: cause);
  }
  if (failure == LlmTransportFailure.responseParse) {
    return LLMResponseParseFailedError(provider, _detail(message, cause), originalError: cause);
  }
  return LLMError('$provider API 调用失败: ${_detail(message, cause)}', originalError: cause);
}

/// 错误文本原语：优先消息文本，空则回退 cause 字符串化，避免模板出现空尾。
String _detail(String message, Object? cause) =>
    message.isNotEmpty ? message : (cause?.toString() ?? '');

/// 领域异常基类。
class DomainError implements Exception {
  DomainError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 对话不存在。
class ConversationNotFoundError extends DomainError {
  ConversationNotFoundError() : super('对话不存在');
}

/// 角色不存在（孤立对话引用缺失角色：FK 关闭 / 损坏态）。
class CharacterNotFoundError extends DomainError {
  CharacterNotFoundError(int characterId) : super('角色不存在: $characterId');
}

/// 未配置 API Key。
class ApiKeyMissingError extends DomainError {
  ApiKeyMissingError(String provider) : super('未配置 $provider API Key，请在设置中填写');
}

/// 不支持的 Provider。
class ProviderNotSupportedError extends DomainError {
  ProviderNotSupportedError(String provider) : super('不支持的 Provider: $provider');
}

/// 消息不存在（重生成端点引用不存在的 message_id）。
class MessageNotFoundError extends DomainError {
  MessageNotFoundError() : super('消息不存在');
}

/// 重生成目标非法。
class InvalidRegenerateTargetError extends DomainError {
  /// 没有可重生成的 AI 回复（对话中不存在 assistant 消息）。
  InvalidRegenerateTargetError.noAssistantReply() : super('没有可重生成的 AI 回复');

  /// 目标不是 AI 回复（只能重生成 AI 回复）。
  InvalidRegenerateTargetError.notAssistant() : super('只能重生成 AI 回复');

  /// 截断后没有可重生成的用户消息（无触发源）。
  InvalidRegenerateTargetError.noTriggerUser() : super('没有可重生成的用户消息');

  /// 编辑目标不是用户消息（MS-03：只能编辑用户消息）。
  InvalidRegenerateTargetError.notUser() : super('只能编辑用户消息');
}

/// 重生成进行中（F4 并发双触发守卫：同对话 in-flight 期间拒绝第二次调用）。
class RegenerateBusyError extends DomainError {
  RegenerateBusyError() : super('重生成进行中');
}

/// 文档解析失败（LLM 文档解析错误面：未配 Key / Provider 不支持 / LLM 调用
/// 失败 / 响应不可解析，全部折叠为单一 [DocParseError]，文案对桌面
/// `document_parser.py` 逐字）。
class DocParseError extends DomainError {
  DocParseError(super.message);
}

/// swipes 候选序号越界（MS-01）：switchSwipe / deleteSwipe 目标 index
/// 不存在于该消息候选集时抛（桌面 `SwipeIndexError` 对应物，命名对齐
/// chat-polish spec §4.8 领域错误新增清单）。
class SwipeIndexOutOfRangeError extends DomainError {
  SwipeIndexOutOfRangeError(int index) : super('候选序号不存在: $index');
}
