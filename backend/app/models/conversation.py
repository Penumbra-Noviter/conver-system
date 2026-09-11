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
    model_name = Column(String(100), default="claude-sonnet-5", comment="具体模型名")

    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())
    updated_at = Column(DateTime, default=datetime.datetime.now, onupdate=datetime.datetime.now, server_default=func.now())

    # BR-1 分支元数据（派生来源/分叉锚/分支显示名；均与 ORM create_all 同步的可空
    # 列——存量库经自愈迁移补列见 database.py::_ensure_conversation_branch_columns；
    # 删除源会话时 parent 置空为服务层语义（BR-2 锁定），此处不加 FK）
    parent_conversation_id = Column(Integer, nullable=True, comment="派生来源会话 id")
    branch_from_message_id = Column(Integer, nullable=True, comment="分叉锚消息 id（快照末条）")
    branch_title = Column(String(200), nullable=True, comment="分支显示名")

    def __repr__(self) -> str:
        return f"<Conversation(id={self.id}, character_id={self.character_id}, title='{self.title}')>"
