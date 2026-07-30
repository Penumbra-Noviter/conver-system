"""
LLM 异常定义

Service 层捕获这些异常，转为对应的 HTTP 响应。
"""

from __future__ import annotations


class LLMError(Exception):
    """LLM 调用基类异常"""
    def __init__(self, message: str, original_error: Exception | None = None):
        self.original_error = original_error
        super().__init__(message)


class LLMAuthError(LLMError):
    """API Key 无效或未配置"""
    pass


class LLMRateLimitError(LLMError):
    """频率限制"""
    pass


class LLMTimeoutError(LLMError):
    """请求超时"""
    pass


class LLMContentFilterError(LLMError):
    """内容被过滤"""
    pass


def translate_sdk_error(
    error: Exception,
    provider_label: str,
    *,
    auth_cls: type,
    rate_cls: type,
    timeout_cls: type,
    bad_request_cls: type,
) -> LLMError:
    """将 SDK 异常统一转为 LLMError 层级

    Args:
        error: SDK 抛出的原始异常
        provider_label: 人类可读的 Provider 名称（如 "Claude", "OpenAI"）
        auth_cls: SDK 的身份验证异常类
        rate_cls: SDK 的频率限制异常类
        timeout_cls: SDK 的超时异常类
        bad_request_cls: SDK 的错误请求异常类

    Returns:
        对应的 LLMError 子类
    """
    if isinstance(error, auth_cls):
        return LLMAuthError(f"{provider_label} API Key 无效或未配置", original_error=error)
    if isinstance(error, rate_cls):
        return LLMRateLimitError(f"{provider_label} API 请求频率超限", original_error=error)
    if isinstance(error, timeout_cls):
        return LLMTimeoutError(f"{provider_label} API 请求超时", original_error=error)
    if isinstance(error, bad_request_cls):
        if "content_filter" in str(error).lower():
            return LLMContentFilterError(
                f"内容被 {provider_label} 内容过滤器拦截", original_error=error
            )
        return LLMError(f"{provider_label} API 请求错误: {error}", original_error=error)
    return LLMError(f"{provider_label} API 调用失败: {error}", original_error=error)
