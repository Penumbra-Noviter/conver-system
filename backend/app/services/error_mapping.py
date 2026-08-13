"""
领域错误映射 — 服务层单一入口（B1 共识 D2）

领域异常族（DomainError）→ (HTTP 状态码, 用户可见消息) 的唯一映射表。
聊天服务的领域分支（services/chat.py::chat_error_response）与 API 全局
异常处理器（api/errors.py::domain_error_handler）共同委托本模块，映射表
不再双份维护（ARC10-4「领域/LLM 两路并存」决策由本批次取代，合并时机已到）。

422 家族 detail 构造（导入格式提示、「导入失败：」前缀）随映射一并下沉，
wire 文案与合并前逐字一致。

协议表面（__all__）：domain_error_response / IMPORT_FORMAT_HINT。
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

__all__ = ["domain_error_response", "IMPORT_FORMAT_HINT"]

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
