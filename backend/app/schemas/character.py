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
    alternate_greetings: list[str] = Field(default_factory=list, description="备选开场白")
    tags: list[str] = Field(default_factory=list, description="标签")
    creator: str = Field("", description="创作者")
    version: str = Field("1.0", description="版本")
    creator_notes: dict = Field(default_factory=dict, description="创作者备注")
    extensions: dict = Field(default_factory=dict, description="扩展字段")
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
    alternate_greetings: Optional[list[str]] = None
    tags: Optional[list[str]] = None
    creator: Optional[str] = None
    version: Optional[str] = None
    creator_notes: Optional[dict] = None
    extensions: Optional[dict] = None
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
    alternate_greetings: list[str]
    tags: list[str]
    creator: str
    version: str
    creator_notes: dict
    extensions: dict
    avatar: Optional[str] = None
    temperature: float
    conversation_count: int = 0
    created_at: datetime.datetime
    updated_at: datetime.datetime

    model_config = {"from_attributes": True}


# ── 文档解析 ──


class DocParseRequest(BaseModel):
    """文档解析请求"""
    text: str = Field(..., min_length=1, max_length=50000, description="用户文档文本")
    provider: Optional[str] = Field(None, description="LLM Provider（留空则用默认）")
    model: Optional[str] = Field(None, description="LLM 模型名（留空则用默认）")


class DocParseResponse(BaseModel):
    """文档解析响应"""
    name: str = ""
    description: str = ""
    personality: str = ""
    scenario: str = ""
    first_mes: str = ""
    mes_example: str = ""
    system_prompt: str = ""
    post_history_instructions: str = ""
    tags: list[str] = []
    creator: str = ""
    parsed_fields: list[str] = Field(default_factory=list, description="成功提取的字段列表")
