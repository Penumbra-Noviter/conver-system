"""
图片任务 / CG 回顾 Schema（CG-3 / T2）

CG schema 单一来源：CgTimelineItem（剧情回顾时间线条目）与 CgImageCreate /
CgImageResponse（T2 路由三件套请求 / 响应体）同居本文件。
"""

from __future__ import annotations

import datetime

from pydantic import BaseModel, Field

__all__ = [
    "ImageTaskCreate",
    "ImageTaskResponse",
    "CgTimelineItem",
    "CgImageCreate",
    "CgImageResponse",
]


class ImageTaskCreate(BaseModel):
    """提交图片生成任务请求体（POST /api/images/tasks）

    provider 不再由请求体指定——从 settings（image_provider）解析（MD-3）；
    生成参数对齐 ImageGenParams（prompt/negative_prompt/width/height/steps）。
    message_id 为出图锚消息（缺省 None → 会话级 CG，不挂具体消息）。
    """
    conversation_id: int = Field(..., description="产出会话")
    prompt: str = Field(..., min_length=1, description="生成提示词")
    negative_prompt: str = Field("", description="负面提示词")
    width: int = Field(512, ge=32, le=2048, description="图片宽")
    height: int = Field(512, ge=32, le=2048, description="图片高")
    steps: int = Field(20, ge=1, le=150, description="采样步数")
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


class CgImageCreate(BaseModel):
    """手工录入 CG 请求体（POST /api/characters/{character_id}/cg，T2）

    初始默认锁定契约：不收 unlocked 字段（服务层 add_cg 默认 unlocked=False），
    录入端点无法直接产生已解锁 CG——解锁只走 unlock 路径（T6 / T2·T5 手工）。
    url 仅 URL / 本地路径引用（multipart 上传明确排除，spec §3）。
    """
    url: str = Field(..., min_length=1, description="图片地址（URL 或本地路径，非空）")
    group_name: str = Field("", description="分组（空 = 默认分组）")
    weight: int = Field(100, ge=0, description="加权抽选权重（0 = 永不抽中）")
    unlock_hint: str = Field("", description="未解锁时提示")
    is_special: bool = Field(False, description="特殊 CG 标记")


class CgImageResponse(BaseModel):
    """CG 图资产行（T2 路由三件套共用响应体：录入 / 解锁 / 列表）"""
    id: int
    character_id: int
    url: str
    group_name: str
    weight: int
    unlock_hint: str
    is_special: bool
    unlocked: bool
    conversation_id: int | None = None
    message_id: int | None = None
    created_at: datetime.datetime

    model_config = {"from_attributes": True}
