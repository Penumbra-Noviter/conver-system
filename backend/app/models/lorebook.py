"""
世界书条目 ORM 模型 — 对齐 SillyTavern World Info 字段语义（WL-1）

字段规格见 docs/chat-simulator-upgrade-spec.md §WL-1 表格。`keys` 列按规格为
TEXT（JSON 数组），经 `JsonList` TypeDecorator 在 ORM 层暴露为 `list[str]`，
落库/读回自动序列化，消费方无需手工 json 解析。
"""

from __future__ import annotations

import datetime
import json

from sqlalchemy import Boolean, CheckConstraint, Column, DateTime, ForeignKey, Integer, String, Text, func, text
from sqlalchemy.types import TypeDecorator

from backend.app.database import Base

__all__ = ["LorebookEntry"]


class JsonList(TypeDecorator):
    """TEXT 列承载 JSON 数组：ORM 层暴露 list[str]，落库/读回自动序列化"""

    impl = Text
    cache_ok = True

    def process_bind_param(self, value, dialect) -> str:
        """list → JSON 文本；None → '[]'；已是 str（防御）→ 原样"""
        if value is None:
            return "[]"
        if isinstance(value, str):
            return value
        return json.dumps(list(value))

    def process_result_value(self, value, dialect) -> list[str]:
        """JSON 文本 → list；空/损坏 → []（容错，与模块脏数据哲学一致）"""
        if not value:
            return []
        try:
            parsed = json.loads(value)
        except (TypeError, ValueError):
            return []
        return parsed if isinstance(parsed, list) else []


class LorebookEntry(Base):
    """世界书条目模型（lorebook_entries 表）"""
    __tablename__ = "lorebook_entries"

    __table_args__ = (
        CheckConstraint('"order" >= 0 AND "order" <= 9999', name="ck_lorebook_entries_order"),
        CheckConstraint("probability >= 1 AND probability <= 100", name="ck_lorebook_entries_probability"),
        CheckConstraint("group_weight >= 1 AND group_weight <= 100", name="ck_lorebook_entries_group_weight"),
        CheckConstraint("depth >= 0 AND depth <= 20", name="ck_lorebook_entries_depth"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    character_id = Column(
        Integer, ForeignKey("characters.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title = Column(String(200), default="", comment="条目标题（可空）")
    keys = Column(JsonList(), nullable=False, default=list, server_default=text("'[]'"), comment="触发关键词（JSON 数组）")
    content = Column(Text, nullable=False, default="", comment="命中后注入内容")
    constant = Column(Boolean, default=False, comment="常驻（不判命中，直接注入）")
    order = Column(Integer, default=100, comment="命中条目排序（升序注入）")
    probability = Column(Integer, default=100, comment="独立命中概率")
    group_name = Column(String(100), default="", comment="互斥组名（空=不分组）")
    group_weight = Column(Integer, default=100, comment="组内权重（同组随机抽一）")
    match_mode = Column(String(8), default="or", comment="or / and")
    position = Column(String(16), default="world", comment="world / before_char / after_char")
    depth = Column(Integer, default=20, comment="参与命中的最近轮数（0=只看当前输入）")
    source = Column(String(16), default="manual", comment="manual / auto（记忆宫殿产出）")
    enabled = Column(Boolean, default=True, comment="单条开关")

    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())
    updated_at = Column(
        DateTime, default=datetime.datetime.now, onupdate=datetime.datetime.now, server_default=func.now()
    )

    def __repr__(self) -> str:
        return f"<LorebookEntry(id={self.id}, character_id={self.character_id}, title='{self.title}')>"
