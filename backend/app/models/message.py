"""
消息 ORM 模型（MS-1：swipes 多候选 + active_swipe_index 自愈迁移列）
"""

from __future__ import annotations

import datetime
import enum

from sqlalchemy import Column, DateTime, Enum, ForeignKey, Integer, Text, UniqueConstraint, func

from backend.app.database import Base

__all__ = ["Role", "Message", "MessageSwipe"]


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
    # MS-1：当前激活候选序号（0=首条候选/原始内容；自愈迁移见 database.py::_ensure_messages_active_swipe_index）
    active_swipe_index = Column(Integer, nullable=False, default=0, server_default="0", comment="激活候选序号")

    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())

    def __repr__(self) -> str:
        return f"<Message(id={self.id}, conversation_id={self.conversation_id}, role='{self.role.value if self.role else None}')>"


class MessageSwipe(Base):
    """消息候选（MS-1：重生成等操作追加候选而非覆盖）

    序号 index 0 起、(message_id, index) 唯一；删除消息级联删候选。
    """
    __tablename__ = "message_swipes"
    __table_args__ = (
        UniqueConstraint("message_id", "index", name="uq_message_swipes_message_index"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    message_id = Column(Integer, ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    index = Column(Integer, nullable=False, comment="候选序号（0 起）")
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())

    def __repr__(self) -> str:
        return f"<MessageSwipe(id={self.id}, message_id={self.message_id}, index={self.index})>"
