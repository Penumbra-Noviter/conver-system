"""
对话 Pydantic Schema
"""

from __future__ import annotations

import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ConversationCreate(BaseModel):
    """创建对话请求"""
    character_id: int = Field(..., description="角色 ID")
    title: str = Field("新对话", max_length=200)
    model_provider: str = Field("claude", description="模型提供商")
    model_name: str = Field("claude-sonnet-4-20250514", description="具体模型名")


class ConversationUpdate(BaseModel):
    """更新对话请求"""
    title: Optional[str] = Field(None, max_length=200)
    model_provider: Optional[str] = None
    model_name: Optional[str] = None


class ConversationResponse(BaseModel):
    """对话响应体"""
    id: int
    character_id: int
    title: str
    model_provider: str
    model_name: str
    message_count: int = 0
    created_at: datetime.datetime
    updated_at: datetime.datetime

    model_config = {"from_attributes": True}


class ConversationExportCharacter(BaseModel):
    """对话导出 JSON 的 character 段

    Schema 即导出契约：字段名 / 顺序 / 类型由本类唯一定义，
    service 层经 model_validate + model_dump 驱动序列化，无需手写字段映射。
    字段子集为 CharacterResponse 的投影（不含 mes_example / 元数据等非导出字段）。
    """
    id: int
    name: str
    description: str
    personality: str
    scenario: str
    first_mes: str
    system_prompt: str
    avatar: Optional[str] = None
    temperature: float

    model_config = {"from_attributes": True}
