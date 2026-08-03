"""
pytest 共享 fixture

- `make_character`：构造角色 ORM 瞬时实例的工厂（纯对象，转换层测试用，无需 DB session）
- `db_session`：内存 SQLite 会话（每次测试独立建库/删库，端点/服务层测试用；
  StaticPool 保证同一连接，避免 threading 限制）

共享 fixture 一律收口于此，禁止在测试文件中复制副本（见 docs/documentation-standards.md §三 测试规范）。
"""

from __future__ import annotations

from collections.abc import Callable, Iterator

import pytest
from sqlalchemy.orm import Session

from backend.app.database import Base
from backend.app.models.character import Character

__all__ = ["make_character", "db_session"]


@pytest.fixture
def db_session() -> Iterator[Session]:
    """内存 SQLite 会话（每次测试独立建库/删库）"""
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    SessionFactory = sessionmaker(bind=engine)
    session = SessionFactory()
    yield session
    session.close()
    Base.metadata.drop_all(engine)


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
