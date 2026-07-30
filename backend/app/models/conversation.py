"""
对话 ORM 模型
"""

from __future__ import annotations

import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, func

from backend.app.database import Base


class Conversation(Base):
    """对话模型"""
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    character_id = Column(Integer, ForeignKey("characters.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String(200), default="新对话")
    model_provider = Column(String(50), default="claude", comment="模型提供商")
    model_name = Column(String(100), default="claude-sonnet-4-20250514", comment="具体模型名")

    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())
    updated_at = Column(DateTime, default=datetime.datetime.now, onupdate=datetime.datetime.now, server_default=func.now())

    def __repr__(self) -> str:
        return f"<Conversation(id={self.id}, character_id={self.character_id}, title='{self.title}')>"
