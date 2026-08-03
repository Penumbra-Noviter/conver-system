"""
角色 ORM 模型 — 兼容 SillyTavern Character Card V2 规范

字段映射关系：
    V2 字段名          →  DB 字段
    ─────────────────────────────────────
    data.name          →  name
    data.description   →  description
    data.personality   →  personality
    data.scenario      →  scenario
    data.first_mes     →  first_mes (原 greeting)
    data.mes_example   →  mes_example
    data.system_prompt       →  system_prompt
    data.post_history_instructions → post_history_instructions
    data.alternate_greetings  →  alternate_greetings (JSON)
    data.tags           →  tags (JSON)
    data.creator        →  creator
    data.version        →  version
    data.creator_notes  →  creator_notes (JSON)
    data.extensions     →  extensions (JSON)
"""

from __future__ import annotations

import datetime

from sqlalchemy import JSON, Column, DateTime, Float, Integer, String, Text, func

from backend.app.database import Base


class Character(Base):
    """角色模型 — 完整映射 V2 规范"""
    __tablename__ = "characters"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False, index=True)

    # ── V2 核心字段 ──
    description = Column(Text, default="", comment="角色简短描述")
    personality = Column(Text, default="", comment="人格设定（核心 system prompt）")
    scenario = Column(Text, default="", comment="场景设定")
    first_mes = Column(Text, default="", comment="开场白（V2: first_mes）")
    mes_example = Column(Text, default="", comment="对话范例（few-shot）")

    # ── V2 高级字段 ──
    system_prompt = Column(Text, default="", comment="覆盖系统提示词")
    post_history_instructions = Column(Text, default="", comment="历史后指令")
    alternate_greetings = Column(JSON, default=list, comment="备选开场白 (list)")
    tags = Column(JSON, default=list, comment="标签 (list)")

    # ── 元数据 ──
    creator = Column(String(100), default="")
    version = Column(String(50), default="1.0")
    creator_notes = Column(JSON, default=dict, comment="创作者备注 (dict)")
    extensions = Column(JSON, default=dict, comment="扩展字段 (dict)")

    # ── 项目原有字段 ──
    avatar = Column(Text, nullable=True, comment="头像（base64 或路径）")
    temperature = Column(Float, default=0.7, comment="LLM 温度参数")

    created_at = Column(DateTime, default=datetime.datetime.now, server_default=func.now())
    updated_at = Column(DateTime, default=datetime.datetime.now, onupdate=datetime.datetime.now, server_default=func.now())

    def __repr__(self) -> str:
        return f"<Character(id={self.id}, name='{self.name}')>"
