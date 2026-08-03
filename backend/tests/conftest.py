"""
pytest 共享 fixture — 角色卡转换层测试

to_v2_card / from_v2_card 均为纯函数（ORM 对象只读属性，无需 DB session），
故本测试不建库、不开会话，全部走瞬时对象与纯字典。
"""

from __future__ import annotations

from collections.abc import Callable

import pytest

from backend.app.models.character import Character

__all__ = ["make_character"]


@pytest.fixture
def make_character() -> Callable[..., Character]:
    """构造角色 ORM 瞬时实例的工厂（字段可覆盖）"""

    def _make(**overrides: object) -> Character:
        base = {
            "name": "测试角色",
            "description": "一个用于测试的角色",
            "personality": "冷静、睿智",
            "scenario": "月下竹林",
            "first_mes": "你好，久等了。",
            "mes_example": "<START>\n{{user}}: 你好\n{{char}}: 欢迎",
            "system_prompt": "你是测试角色。",
            "post_history_instructions": "保持人设。",
            "alternate_greetings": ["备选开场白"],
            "tags": ["冒险", "奇幻"],
            "creator": "测试作者",
            "version": "1.0",
            "creator_notes": {"note": "创作者备注"},
            "extensions": {},
            "avatar": None,
            "temperature": 0.7,
        }
        base.update(overrides)
        return Character(**base)

    return _make
