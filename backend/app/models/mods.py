"""
Mod 挂载层 ORM 模型（MD-1：mods + mod_bindings 新表）

字段规格见 docs/chat-simulator-upgrade-spec.md §MD-1。两张表：
    - mods：全局 Mod 库（目标区域 prompt|memory|css；payload 为注入内容，
      prompt 区为 JSON ``{"world"/"before_char"/"after_char": str}``）。
    - mod_bindings：作品级挂载（(character_id, mod_id) 唯一 + sort_order +
      enabled 开关）。生命周期：删作品/删 Mod 级联删绑定（FK CASCADE）。
"""

from __future__ import annotations

import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)

from backend.app.database import Base

__all__ = ["Mod", "ModBinding"]


class Mod(Base):
    """Mod 定义（mods 表）"""
    __tablename__ = "mods"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(200), nullable=False, default="", comment="Mod 名称")
    description = Column(Text, default="", comment="说明")
    target_area = Column(String(16), nullable=False, default="prompt", comment="prompt/memory/css")
    payload = Column(Text, nullable=False, default="", comment="注入内容（prompt 区为 JSON 三区域）")
    version = Column(String(50), default="1.0", comment="版本")
    source = Column(String(16), default="manual", comment="manual/imported")

    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())

    def __repr__(self) -> str:
        return f"<Mod(id={self.id}, name='{self.name}', target_area='{self.target_area}')>"


class ModBinding(Base):
    """作品级 Mod 挂载（mod_bindings 表）

    (character_id, mod_id) 唯一（同角色同 Mod 不重复）；sort_order 升序叠加、
    enabled 开关（false 不参与叠加）。删作品/删 Mod 级联删绑定。
    """
    __tablename__ = "mod_bindings"
    __table_args__ = (
        UniqueConstraint("character_id", "mod_id", name="uq_mod_bindings_character_mod"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    character_id = Column(
        Integer, ForeignKey("characters.id", ondelete="CASCADE"), nullable=False, index=True,
        comment="挂载作品",
    )
    mod_id = Column(
        Integer, ForeignKey("mods.id", ondelete="CASCADE"), nullable=False, index=True,
        comment="挂载的 Mod",
    )
    enabled = Column(Boolean, nullable=False, default=True, comment="绑定开关（false 不参与叠加）")
    sort_order = Column(Integer, nullable=False, default=0, comment="叠加排序（升序；同序按 mod_id 稳定）")

    def __repr__(self) -> str:
        return (
            f"<ModBinding(id={self.id}, character_id={self.character_id}, "
            f"mod_id={self.mod_id}, enabled={self.enabled}, sort_order={self.sort_order})>"
        )
