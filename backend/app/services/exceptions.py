"""
Conver System — 领域异常

服务层抛出的领域异常，由路由层捕获并转换为 HTTP 响应。
保持服务层与 HTTP 协议解耦，提升可测试性。

协议表面（__all__）：ConversationNotFoundError / ApiKeyMissingError / ProviderNotSupportedError /
CardFormatError / CardValidationError
"""

from __future__ import annotations

__all__ = [
    "ConversationNotFoundError",
    "ApiKeyMissingError",
    "ProviderNotSupportedError",
    "CardFormatError",
    "CardValidationError",
    "DocParseError",
    "DomainError",
]


class DomainError(Exception):
    """领域异常基类"""


class ConversationNotFoundError(DomainError):
    """对话不存在"""


class ApiKeyMissingError(DomainError):
    """未配置 API Key"""


class ProviderNotSupportedError(DomainError):
    """不支持的 Provider"""


class CardFormatError(DomainError):
    """角色卡格式无法识别"""


class CardValidationError(DomainError):
    """角色卡数据校验失败"""


class DocParseError(DomainError):
    """文档解析失败（LLM 调用失败 / 返回非 JSON / 字段提取失败）"""