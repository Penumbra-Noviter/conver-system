"""
脏数据容错工具 — 跨模块共享（F-93 收敛）

协议表面（__all__）：as_str_list。字符卡转换层（character_card._as_list 前身）
与世界书仓库层（lorebook._as_str_list 前身）的逐行重复收敛至此单点；
行为语义保持不变（契约由 character_card / lorebook 既有测试锁定）。
"""

from __future__ import annotations

__all__ = ["as_str_list"]


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
