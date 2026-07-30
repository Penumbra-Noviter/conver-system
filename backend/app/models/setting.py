"""
设置 ORM 模型（键值对存储）

用于管理运行时配置：API Key、默认模型、UI 偏好等。
支持通过设置面板 UI 即时读写。
"""

from __future__ import annotations

from sqlalchemy import Column, String, Text

from backend.app.database import Base


class Setting(Base):
    """设置模型（键值对）"""
    __tablename__ = "settings"

    key = Column(String(100), primary_key=True, comment="配置键")
    value = Column(Text, default="", comment="配置值")

    def __repr__(self) -> str:
        return f"<Setting(key='{self.key}')>"
