"""
消息 Pydantic Schema
"""

from __future__ import annotations

import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class MessageResponse(BaseModel):
    """消息响应体（MS-2：含候选集与激活序号）"""
    id: int
    conversation_id: int
    role: str
    content: str
    created_at: datetime.datetime
    swipes: list[str] = Field(default_factory=list, description="候选集（index 升序；含原始内容候选 0）")
    active_swipe_index: int = Field(0, description="当前激活候选序号")

    model_config = {"from_attributes": True}


class SwitchSwipeRequest(BaseModel):
    """切换候选请求体"""
    index: int = Field(..., ge=0, description="目标候选序号")


class SearchResult(BaseModel):
    """消息搜索结果条目（跨对话搜索，附带对话与角色上下文）"""
    message_id: int
    conversation_id: int
    conversation_title: str
    character_id: int
    character_name: str
    character_avatar: Optional[str] = None
    role: str
    content_preview: str
    created_at: Optional[str] = None


class ChatRequest(BaseModel):
    """聊天请求"""
    conversation_id: int = Field(..., description="对话 ID")
    content: str = Field(..., min_length=1, description="用户消息内容")

class ChatResponse(BaseModel):
    """非流式聊天响应"""
    reply: str
    message_id: int
    conversation_id: int


class RegenerateRequest(BaseModel):
    """重生成请求体（可选指定要重生成的目标 assistant 消息）

    Attributes:
        message_id: 目标 assistant 消息 ID（缺省=末条 AI 回复）
    """
    message_id: int | None = None


class EditMessageRequest(BaseModel):
    """编辑重发请求体（仅 user；content 就地替换后重新生成后续回复）"""
    content: str = Field(..., min_length=1, description="修正后的用户消息内容")

    @field_validator("content")
    @classmethod
    def _reject_blank(cls, value: str) -> str:
        """strip 后拒绝全空白（min_length=1 拦不住 "   "，F-137 后端防御补强）

        Field 约束先于 validator 运行：纯空白串通过 min_length=1 后才到此处，
        strip 后为空即拒绝。合法内容 strip 后返回（去首尾空白，对齐前端 trim 语义）。
        """
        value = value.strip()
        if not value:
            raise ValueError("消息内容不能为空")
        return value
