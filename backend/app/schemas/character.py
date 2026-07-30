"""
角色 Pydantic Schema — 请求/响应模型

为兼容 V2 规范，Schema 字段与 ORM 模型一一对应，
conversation_count 为计算字段（非 ORM 列），由 JOIN 查询填充。
"""

from __future__ import annotations

import datetime
from typing import Optional

from pydantic import BaseModel, Field


# ── 请求体 ──


class CharacterCreate(BaseModel):
    """创建角色请求"""
    name: str = Field(..., min_length=1, max_length=100, description="角色名称")
    description: str = Field("", description="角色简短描述")
    personality: str = Field("", description="人格设定（核心 system prompt）")
    scenario: str = Field("", description="场景设定")
    first_mes: str = Field("", description="开场白")
    mes_example: str = Field("", description="对话范例")
    system_prompt: str = Field("", description="覆盖系统提示词")
    post_history_instructions: str = Field("", description="历史后指令")
    alternate_greetings: str = Field("[]", description="备选开场白 (JSON array)")
    tags: str = Field("[]", description="标签 (JSON array)")
    creator: str = Field("", description="创作者")
    version: str = Field("1.0", description="版本")
    creator_notes: str = Field("{}", description="创作者备注 (JSON)")
    extensions: str = Field("{}", description="扩展字段 (JSON)")
    avatar: Optional[str] = Field(None, description="头像 base64 / 路径")
    temperature: float = Field(0.7, ge=0.0, le=2.0, description="LLM 温度参数")


class CharacterUpdate(BaseModel):
    """更新角色请求（所有字段可选）"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    personality: Optional[str] = None
    scenario: Optional[str] = None
    first_mes: Optional[str] = None
    mes_example: Optional[str] = None
    system_prompt: Optional[str] = None
    post_history_instructions: Optional[str] = None
    alternate_greetings: Optional[str] = None
    tags: Optional[str] = None
    creator: Optional[str] = None
    version: Optional[str] = None
    creator_notes: Optional[str] = None
    extensions: Optional[str] = None
    avatar: Optional[str] = None
    temperature: Optional[float] = Field(None, ge=0.0, le=2.0)


# ── 响应体 ──


class CharacterResponse(BaseModel):
    """角色响应体"""
    id: int
    name: str
    description: str
    personality: str
    scenario: str
    first_mes: str
    mes_example: str
    system_prompt: str
    post_history_instructions: str
    alternate_greetings: str
    tags: str
    creator: str
    version: str
    creator_notes: str
    extensions: str
    avatar: Optional[str] = None
    temperature: float
    conversation_count: int = 0
    created_at: datetime.datetime
    updated_at: datetime.datetime

    model_config = {"from_attributes": True}
