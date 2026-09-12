"""
Mod Pydantic Schema — 请求/响应模型（MD-1 + MD-2/01）

字段规格见 docs/chat-simulator-upgrade-spec.md §MD-1 表格。target_area 用
Literal 收口三值（prompt|memory|css）、source 用 Literal 收口（manual|imported）；
边界在 Schema 层「拒」，服务层只存取（与 lorebook 双轨分界同构）。

MD-2/01 补响应与挂载模型：ModResponse（from_attributes 驱动 ORM→JSON 序列化）、
ModBindingResponse（挂载响应不嵌套 Mod 详情，前端按 mod_id 客户端关联）、
ModBindCreate（mod_id 必填，enabled/sort_order 可选）、ModBindingUpdate
（enabled 必填）、ModBindSortUpdate（sort_order 必填）。
"""

from __future__ import annotations

import datetime
from typing import Literal

from pydantic import BaseModel, Field

__all__ = [
    "ModCreate",
    "ModUpdate",
    "ModResponse",
    "ModBindingResponse",
    "ModBindCreate",
    "ModBindingUpdate",
    "ModBindSortUpdate",
]


class ModCreate(BaseModel):
    """创建 Mod 请求"""
    name: str = Field("", max_length=200, description="Mod 名称")
    description: str = Field("", description="说明")
    target_area: Literal["prompt", "memory", "css"] = Field("prompt", description="目标区域")
    payload: str = Field("", description="注入内容（prompt 区为 JSON 三区域）")
    version: str = Field("1.0", max_length=50, description="版本")
    source: Literal["manual", "imported"] = Field("manual", description="来源")


class ModUpdate(BaseModel):
    """更新 Mod 请求（所有字段可选，仅提交显式字段；显式 None 跳过）"""
    name: str | None = Field(None, max_length=200)
    description: str | None = None
    target_area: Literal["prompt", "memory", "css"] | None = None
    payload: str | None = None
    version: str | None = Field(None, max_length=50)
    source: Literal["manual", "imported"] | None = None


class ModResponse(BaseModel):
    """Mod 响应体（库列表 / 单条 / 创建 / 更新）

    from_attributes 驱动 ORM → JSON 序列化；字段与 mods 表一一对应。
    """
    id: int
    name: str
    description: str
    target_area: str
    payload: str
    version: str
    source: str
    created_at: datetime.datetime

    model_config = {"from_attributes": True}


class ModBindingResponse(BaseModel):
    """角色挂载响应体（不嵌套 Mod 详情，前端按 mod_id 客户端关联）"""
    id: int
    character_id: int
    mod_id: int
    enabled: bool
    sort_order: int

    model_config = {"from_attributes": True}


class ModBindCreate(BaseModel):
    """挂载请求（mod_id 必填；enabled 默认开、sort_order None = 自动续尾）"""
    mod_id: int = Field(..., description="挂载的 Mod ID")
    enabled: bool = Field(True, description="绑定开关（默认开）")
    sort_order: int | None = Field(None, description="叠加排序（None = 自动续尾）")


class ModBindingUpdate(BaseModel):
    """挂载开关更新请求（enabled 必填）"""
    enabled: bool = Field(..., description="目标开关态")


class ModBindSortUpdate(BaseModel):
    """挂载排序更新请求（sort_order 必填）"""
    sort_order: int = Field(..., description="目标排序值")
