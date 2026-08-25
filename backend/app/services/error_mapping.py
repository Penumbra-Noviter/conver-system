"""
领域与 LLM 错误映射 — 服务层单一入口（B1 共识 D2）

领域异常族（DomainError）与 LLM 异常族（LLMError）→ (HTTP 状态码, 用户可见消息)
的唯一映射表。聊天服务的错误映射分支（services/chat.py::chat_error_response）与 API
全局异常处理器（api/errors.py::domain_error_handler / llm_error_handler）共同委托
本模块，映射表不再双份维护。

422 家族 detail 构造（导入格式提示、「导入失败：」前缀）随映射一并下沉，
wire 文案与合并前逐字一致。

协议表面（__all__）：domain_error_response / IMPORT_FORMAT_HINT / llm_error_response。
"""

from __future__ import annotations

from fastapi import status

from backend.app.services.exceptions import (
    ApiKeyMissingError,
    CardFormatError,
    CardValidationError,
    CharacterNotFoundError,
    ConversationNotFoundError,
    DocParseError,
    DomainError,
    ProviderNotSupportedError,
)
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)

__all__ = ["domain_error_response", "IMPORT_FORMAT_HINT", "llm_error_response"]

#: 角色卡导入失败时的支持格式说明（随 B1 迁入，422 detail 拼接用）
IMPORT_FORMAT_HINT = (
    "支持格式：SillyTavern V2 角色卡（spec=chara_card_v2）、data 信封、"
    "裸 data（含 name 字段）、V1 旧卡（含 char_name 字段）；"
    "也可改用「创建角色」向导（智能导入/模板/手动）"
)


def domain_error_response(exc: DomainError) -> tuple[int, str]:
    """领域异常 → (HTTP 状态码, 用户可见消息) 单一映射入口

    - ConversationNotFoundError/CharacterNotFoundError→404、
      ApiKeyMissingError/ProviderNotSupportedError→400，detail 一律 str(exc)
    - 422 家族：CardFormatError→422 + 导入失败：{e}。{hint}（含支持格式说明）、
      CardValidationError→422 + 导入失败：{e}（纯原因）、DocParseError→422 + str(e)（纯原因）
    - 未知 DomainError 子类 → 400 + str(e) 兜底（防御性；异常层次冻结，当前无生产者）

    Args:
        exc: 待映射的领域异常

    Returns:
        (HTTP 状态码, 用户可见消息)
    """
    if isinstance(exc, (ConversationNotFoundError, CharacterNotFoundError)):
        return status.HTTP_404_NOT_FOUND, str(exc)
    if isinstance(exc, (ApiKeyMissingError, ProviderNotSupportedError)):
        return status.HTTP_400_BAD_REQUEST, str(exc)
    if isinstance(exc, CardFormatError):
        return status.HTTP_422_UNPROCESSABLE_CONTENT, f"导入失败：{exc}。{IMPORT_FORMAT_HINT}"
    if isinstance(exc, CardValidationError):
        return status.HTTP_422_UNPROCESSABLE_CONTENT, f"导入失败：{exc}"
    if isinstance(exc, DocParseError):
        return status.HTTP_422_UNPROCESSABLE_CONTENT, str(exc)
    return status.HTTP_400_BAD_REQUEST, str(exc)


# LLM 错误 → (HTTP 状态码, 用户可见消息) 映射（由 chat.py 迁入，T-01）
_LLM_ERROR_MAP: dict[type[LLMError], tuple[int, str | None]] = {
    LLMAuthError: (status.HTTP_401_UNAUTHORIZED, None),
    LLMRateLimitError: (
        status.HTTP_429_TOO_MANY_REQUESTS,
        "API 请求频率超限，请稍后再试",
    ),
    LLMTimeoutError: (
        status.HTTP_504_GATEWAY_TIMEOUT,
        "API 请求超时，请检查网络后重试",
    ),
    LLMContentFilterError: (status.HTTP_400_BAD_REQUEST, None),
    LLMError: (status.HTTP_502_BAD_GATEWAY, None),
}


def llm_error_response(e: LLMError, provider: str | None) -> tuple[int, str]:
    """将 LLMError 转为 (HTTP 状态码, 用户可见消息)

    映射规则：
    - LLMAuthError → 401，provider 非空时输出 "{provider} API Key 无效，请在设置中更新"，
      provider 为空时输出 "API Key 无效，请在设置中更新"（无前缀、无前导空格）
    - LLMRateLimitError → 429 + 固定消息「API 请求频率超限，请稍后再试」
    - LLMTimeoutError → 504 + 固定消息「API 请求超时，请检查网络后重试」
    - LLMContentFilterError → 400 + str(e)
    - LLMError 基类/未知子类 → 502 + str(e) 兜底

    Args:
        e: 待映射的 LLM 异常
        provider: Provider 名（Auth 消息模板使用；为空时输出无前缀基础文案）

    Returns:
        (HTTP 状态码, 用户可见消息)
    """
    for exc_type, (status_code, fixed_msg) in _LLM_ERROR_MAP.items():
        if isinstance(e, exc_type):
            if fixed_msg is not None:
                return status_code, fixed_msg
            if isinstance(e, LLMAuthError):
                # Provider 非空带前缀、为空时输出基础文案（按构造消除前导空格，ARC10-1）
                prefix = f"{provider} " if provider else ""
                return status_code, f"{prefix}API Key 无效，请在设置中更新"
            return status_code, str(e)
    return status.HTTP_502_BAD_GATEWAY, str(e)
