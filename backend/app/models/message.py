"""
消息 ORM 模型
"""

from __future__ import annotations

import datetime
import enum

from sqlalchemy import Column, DateTime, Enum, ForeignKey, Integer, Text, func

from backend.app.database import Base


class Role(enum.Enum):
    """消息角色枚举"""
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"


class Message(Base):
    """消息模型"""
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, autoincrement=True)
    conversation_id = Column(Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True)
    role = Column(
        Enum(
            Role,
            native_enum=False,
            validate_strings=True,
            # 按枚举值（user/assistant/system）存取，兼容既有 VARCHAR 存量数据
            values_callable=lambda enum_cls: [member.value for member in enum_cls],
        ),
        nullable=False,
        comment="user / assistant / system",
    )
    content = Column(Text, nullable=False)

    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())

    def __repr__(self) -> str:
        return f"<Message(id={self.id}, conversation_id={self.conversation_id}, role='{self.role.value if self.role else None}')>"
