"""
脏数据容错工具契约锁（F-93/F-94 收敛）

行为语义与 character_card._as_list / lorebook._as_str_list 前身逐字一致
（由 character_card / lorebook 既有测试锁定零回归）；本文件直接锁定共享函数本体。
"""

from __future__ import annotations

import pytest

from backend.app.services.text_utils import as_str_list, role_str

__all__: list[str] = []


@pytest.mark.parametrize(
    "value, expected",
    [
        (None, []),
        ("", []),
        (["a", 2, None], ["a", "2", "None"]),  # list → 逐元素 str 化
        ("单标签", ["单标签"]),  # 非 list → 单值包裹
        (123, ["123"]),
        ([], []),  # 空 list → []
    ],
)
def test_as_str_list_matrix(value: object, expected: list[str]) -> None:
    """脏数据容错矩阵：None/空 → []；list → str 化；其它 → 单值包裹"""
    assert as_str_list(value) == expected


class _EnumLike:
    """带 .value 的枚举形态（如 models.message.Role）"""

    def __init__(self, value: str) -> None:
        self.value = value


@pytest.mark.parametrize(
    "value, expected",
    [
        ("user", "user"),
        (_EnumLike("assistant"), "assistant"),  # .value 解包
        ("", ""),
        (None, "None"),  # str(None) 兜底（不抛）
    ],
)
def test_role_str_matrix(value: object, expected: str) -> None:
    """角色归一：带 .value 枚举解包为值；纯字符串原样（F-94 收敛锁）"""
    assert role_str(value) == expected
