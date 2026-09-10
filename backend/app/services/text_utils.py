"""
文本/角色归一容错工具 — 跨模块共享（F-93/F-94 收敛）

协议表面（__all__）：as_str_list / role_str。字符卡转换层（character_card._as_list
前身）、世界书仓库层（lorebook._as_str_list 前身）与消息角色归一
（prompt._role_str / chat._msg_role 前身）的逐行重复收敛至此单点；
行为语义保持不变（契约由 character_card / lorebook / prompt / chat 既有测试锁定）。
"""

from __future__ import annotations

__all__ = ["as_str_list", "role_str"]


def as_str_list(value) -> list[str]:
    """容忍脏数据：None → []，list → str 化列表，其它 → 单值包裹

    应用于 tags / alternate_greetings / keys 等「可能是数组也可能是脏值」的字段：
        None 或空串 → []
        list      → 逐元素 str 化
        其它      → 单值包裹（[str(value)]）

    Args:
        value: 任意输入（None / list / str / 标量）

    Returns:
        str 化列表（永不返回 None）
    """
    if value is None or value == "":
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


def role_str(value) -> str:
    """消息/角色值 → 纯字符串（兼容 str 与带 .value 的枚举，如 models.message.Role）

    统一消息角色归一（prompt._role_str / chat._msg_role 前身）：带 .value 的
    枚举解包为值，纯字符串/其它原样 str 化（None → "None" 兜底不抛）。

    Args:
        value: 任意输入（str / 带 .value 的枚举 / 标量）

    Returns:
        归一后的角色字符串
    """
    if hasattr(value, "value"):
        return str(value.value)
    return str(value)
