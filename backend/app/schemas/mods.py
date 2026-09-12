"""
Mod Pydantic Schema — 请求/响应模型（MD-1 + MD-2/01）

字段规格见 docs/chat-simulator-upgrade-spec.md §MD-1 表格。target_area 用
Literal 收口三值（prompt|memory|css）、source 用 Literal 收口（manual|imported）；
边界在 Schema 层「拒」，服务层只存取（与 lorebook 双轨分界同构）。

MD-2/01 补响应与挂载模型：ModResponse（from_attributes 驱动 ORM→JSON 序列化）、
ModBindingResponse（挂载响应不嵌套 Mod 详情，前端按 mod_id 客户端关联）、
ModBindCreate（mod_id 必填，enabled/sort_order 可选）、ModBindingUpdate
（enabled 必填）、ModBindSortUpdate（sort_order 必填）。F-102 后端补
ModsOrderUpdate（批量重排请求，RootModel[list[int]] 原始数组 + 去重校验）。
"""

from __future__ import annotations

import datetime
from typing import Literal

from pydantic import BaseModel, Field, RootModel, model_validator

__all__ = [
    "ModCreate",
    "ModUpdate",
    "ModResponse",
    "ModBindingResponse",
    "ModBindCreate",
    "ModBindingUpdate",
    "ModBindSortUpdate",
    "ModsOrderUpdate",
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
    sort_order: int | None = Field(None, ge=0, le=9999, description="叠加排序（None = 自动续尾）")


class ModBindingUpdate(BaseModel):
    """挂载开关更新请求（enabled 必填）"""
    enabled: bool = Field(..., description="目标开关态")


class ModBindSortUpdate(BaseModel):
    """挂载排序更新请求（sort_order 必填）"""
    sort_order: int = Field(..., ge=0, le=9999, description="目标排序值")


class ModsOrderUpdate(RootModel[list[int]]):
    """批量重排请求体：按新序排列的 binding_id 原始 JSON 数组（F-102 后端）

    RootModel 使 body 直接为数组（`[binding_id, ...]`），非对象包裹。Schema 层只做
    形状与去重校验：
        - 非数组 / 含非整数 → 422（FastAPI 原生 RequestValidationError）
        - 重复 binding_id → 422（model_validator 拒绝）
    空列表留给服务层 reorder_character_mods 抛 ModReorderError（→ 400 明确拒绝，
    避免误清空）。
    """

    @model_validator(mode="after")
    def _reject_duplicate_ids(self) -> "ModsOrderUpdate":
        """重复 binding_id → ValueError（FastAPI 转 422）"""
        if len(self.root) != len(set(self.root)):
            raise ValueError("ordered_binding_ids 含重复 binding_id")
        return self
