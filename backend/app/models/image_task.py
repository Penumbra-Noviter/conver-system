"""
图片生成任务模型（CG-3：image_tasks 新表）

对话内出图的异步任务承载：提交（pending）→ 后台生成（running）→
succeeded（result_url = 本地文件路径/URL）/ failed（error 记录）。
- conversation_id → CASCADE（删会话级联删其任务）
- character_id → CASCADE（删作品级联删任务）
- message_id → SET NULL（锚消息删除后任务保留，出图归属仍成立）
"""

from __future__ import annotations

import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, func

from backend.app.database import Base


class ImageTask(Base):
    """图片生成任务（CG-3）"""
    __tablename__ = "image_tasks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True,
        comment="产出会话",
    )
    character_id = Column(
        Integer, ForeignKey("characters.id", ondelete="CASCADE"), nullable=False,
        comment="归属作品",
    )
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True,
        comment="锚消息（出图归属哪条消息；消息删除后图保留）",
    )
    provider = Column(String(50), default="local", comment="图片 Provider 标识")
    params = Column(Text, nullable=False, comment="生成参数 JSON（ImageGenParams.model_dump）")
    status = Column(String(20), default="pending", comment="pending/running/succeeded/failed")
    result_url = Column(Text, comment="成功后的图片地址（本地路径/URL）")
    error = Column(Text, comment="失败信息")
    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())
    completed_at = Column(DateTime, comment="终态时间（成功/失败）")

    def __repr__(self) -> str:
        return f"<ImageTask(id={self.id}, status={self.status!r}, conversation_id={self.conversation_id})>"