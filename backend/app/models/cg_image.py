"""
CG 图片资产模型（CG-2：cg_images 新表）

归属与生命周期契约：
    - character_id → characters.id ON DELETE CASCADE（删除作品级联删图）
    - conversation_id → conversations.id ON DELETE SET NULL（会话删除后图保留）
    - message_id → messages.id ON DELETE SET NULL（消息随会话级联删除时图保留）
    - url：图片地址（本地文件路径或 HTTP URL，CG-1 ImageResult.url 契约）
"""

from __future__ import annotations

import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text, func

from backend.app.database import Base


class CgImage(Base):
    """CG 图片资产（CG-2）"""
    __tablename__ = "cg_images"

    id = Column(Integer, primary_key=True, autoincrement=True)
    character_id = Column(
        Integer, ForeignKey("characters.id", ondelete="CASCADE"), nullable=False, index=True,
        comment="归属作品",
    )
    conversation_id = Column(
        Integer, ForeignKey("conversations.id", ondelete="SET NULL"), nullable=True, index=True,
        comment="产出会话（会话删除后图保留 → SET NULL）",
    )
    message_id = Column(
        Integer, ForeignKey("messages.id", ondelete="SET NULL"), nullable=True,
        comment="产出自哪条消息（消息删除后图保留 → SET NULL）",
    )
    url = Column(Text, nullable=False, comment="图片地址（本地文件路径或 URL）")
    # T1：加权抽选权重（自愈迁移见 database.py::_ensure_cg_images_weight）
    weight = Column(Integer, nullable=False, default=100, server_default="100",
                    comment="加权抽选权重（0 = 永不抽中；概率池候选门槛 weight>0）")
    group_name = Column(String(100), default="", comment="分组（空 = 默认分组，展示层映射）")
    is_special = Column(Boolean, default=False, comment="特殊 CG（画廊置顶语义，CG-3 消费）")
    unlocked = Column(Boolean, default=False, comment="是否已解锁")
    unlock_hint = Column(Text, default="", comment="未解锁时提示")
    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())

    def __repr__(self) -> str:
        return (
            f"<CgImage(id={self.id}, character_id={self.character_id}, "
            f"url={self.url!r}, unlocked={self.unlocked})>"
        )