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
}