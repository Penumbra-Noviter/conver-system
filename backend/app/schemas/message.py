"""
消息 Pydantic Schema
"""

from __future__ import annotations

import datetime

from pydantic import BaseModel, Field


class MessageResponse(BaseModel):
    """消息响应体"""
    id: int
    conversation_id: int
    role: str
    content: str
    created_at: datetime.datetime

    model_config = {"from_attributes": True}


class ChatRequest(BaseModel):
    """聊天请求"""
    conversation_id: int = Field(..., description="对话 ID")
    content: str = Field(..., min_length=1, description="用户消息内容")

class ChatResponse(BaseModel):
    """非流式聊天响应"""
    reply: str
    message_id: int
    conversation_id: int
