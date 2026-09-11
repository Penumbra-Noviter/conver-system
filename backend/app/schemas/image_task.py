"""
图片任务 / CG 回顾 Schema（CG-3）
"""

from __future__ import annotations

import datetime

from pydantic import BaseModel, Field


class ImageTaskCreate(BaseModel):
    """提交图片生成任务请求体（POST /api/images/tasks）

    provider 缺省 "local"（零配置占位后端，链路可用）；生成参数对齐
    ImageGenParams（prompt/negative_prompt/width/height/steps）。
    message_id 为出图锚消息（缺省 None → 会话级 CG，不挂具体消息）。
    """
    conversation_id: int = Field(..., description="产出会话")
    prompt: str = Field(..., min_length=1, description="生成提示词")
    negative_prompt: str = Field("", description="负面提示词")
    width: int = Field(512, ge=32, le=2048, description="图片宽")
    height: int = Field(512, ge=32, le=2048, description="图片高")
    steps: int = Field(20, ge=1, le=150, description="采样步数")
    provider: str = Field("local", description="图片 Provider 标识")
    message_id: int | None = Field(None, description="出图锚消息 id（可选）")


class ImageTaskResponse(BaseModel):
    """图片任务状态（提交 / 轮询共用响应体）"""
    id: int
    conversation_id: int
    status: str
    result_url: str | None = None
    error: str | None = None
    created_at: datetime.datetime
    completed_at: datetime.datetime | None = None

    model_config = {"from_attributes": True}


class CgTimelineItem(BaseModel):
    """剧情回顾时间线条目（已解锁 CG + 对应消息片段）"""
    cg_id: int
    url: str
    group_name: str
    message_content: str | None = None
    message_created_at: datetime.datetime | None = None
    cg_created_at: datetime.datetime