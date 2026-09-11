"""
Conver System — 领域异常

服务层抛出的领域异常，由路由层捕获并转换为 HTTP 响应。
保持服务层与 HTTP 协议解耦，提升可测试性。

协议表面（__all__）：ConversationNotFoundError / CharacterNotFoundError / ApiKeyMissingError /
ProviderNotSupportedError / CardFormatError / CardValidationError
"""

from __future__ import annotations

__all__ = [
    "ConversationNotFoundError",
    "CharacterNotFoundError",
    "ApiKeyMissingError",
    "ProviderNotSupportedError",
    "CardFormatError",
    "CardValidationError",
    "DocParseError",
    "DomainError",
    "MessageNotFoundError",
    "InvalidRegenerateTargetError",
    "InvalidContinueTargetError",
    "BranchSnapshotError",
    "LorebookEntryNotFoundError",
    "SwipeIndexError",
]


class DomainError(Exception):
    """领域异常基类"""


class ConversationNotFoundError(DomainError):
    """对话不存在"""


class CharacterNotFoundError(DomainError):
    """角色不存在"""


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


class MessageNotFoundError(DomainError):
    """消息不存在（重生成端点引用不存在的 message_id）"""


class InvalidRegenerateTargetError(DomainError):
    """重生成目标非法（target 非 assistant / 截断后无触发 user）"""


class InvalidContinueTargetError(DomainError):
    """续写目标非法（末条非 assistant / 对话无 message —— 只能在末条之后续写）"""


class BranchSnapshotError(DomainError):
    """分支快照非法（版本缺失/不支持/结构畸形 —— 导入拒绝并给明确错误）"""


class LorebookEntryNotFoundError(DomainError):
    """世界书条目不存在"""


class SwipeIndexError(DomainError):
    """候选序号非法（switch 越界 / 候选清空拒绝删除）"""