"""
世界书条目 Pydantic Schema — 请求/响应模型（WL-1）

字段规格见 docs/chat-simulator-upgrade-spec.md §WL-1 表格；边界约束（order/
probability/depth/group_weight）寛式「拒」语义在 Field 上声明并锁定（见
test_lorebook_store.py::test_bounds_rejected）。`keys` 非 list 输入由 Pydantic
拒绝；空数组允许（constant 场景）。
"""

from __future__ import annotations

import datetime
from typing import Literal

from pydantic import BaseModel, Field

__all__ = ["LorebookEntryBase", "LorebookEntryCreate", "LorebookEntryUpdate", "LorebookEntryResponse"]


class LorebookEntryBase(BaseModel):
    """世界书条目公共字段（对齐 SillyTavern World Info）"""
    title: str = Field("", max_length=200, description="条目标题（可空）")
    keys: list[str] = Field(default_factory=list, description="触发关键词（JSON 数组，空允许：constant 场景）")
    content: str = Field("", description="命中后注入内容")
    constant: bool = Field(False, description="常驻（不判命中，直接注入）")
    order: int = Field(100, ge=0, le=9999, description="命中条目排序（升序注入）")
    probability: int = Field(100, ge=1, le=100, description="独立命中概率")
    group_name: str = Field("", max_length=100, description="互斥组名（空=不分组）")
    group_weight: int = Field(100, ge=1, le=100, description="组内权重（同组随机抽一）")
    match_mode: Literal["or", "and"] = Field("or", description="or：任一 key 命中；and：全部命中")
    position: Literal["world", "before_char", "after_char"] = Field(
        "world", description="world=合并为 [世界知识] system；before_char=角色 system 前；after_char=场景设定后"
    )
    depth: int = Field(20, ge=0, le=20, description="参与命中的最近轮数（0=只看当前输入）")
    source: Literal["manual", "auto"] = Field("manual", description="manual / auto（记忆宫殿产出）")
    enabled: bool = Field(True, description="单条开关")


class LorebookEntryCreate(LorebookEntryBase):
    """创建世界书条目请求"""
    pass


class LorebookEntryUpdate(BaseModel):
    """更新世界书条目请求（所有字段可选，仅提交显式字段）"""
    title: str | None = Field(None, max_length=200)
    keys: list[str] | None = None
    content: str | None = None
    constant: bool | None = None
    order: int | None = Field(None, ge=0, le=9999)
    probability: int | None = Field(None, ge=1, le=100)
    group_name: str | None = Field(None, max_length=100)
    group_weight: int | None = Field(None, ge=1, le=100)
    match_mode: Literal["or", "and"] | None = None
    position: Literal["world", "before_char", "after_char"] | None = None
    depth: int | None = Field(None, ge=0, le=20)
    source: Literal["manual", "auto"] | None = None
    enabled: bool | None = None


class LorebookEntryResponse(LorebookEntryBase):
    """世界书条目响应体（WL-4 编辑器路由用）"""
    id: int
    character_id: int
    created_at: datetime.datetime
    updated_at: datetime.datetime

    model_config = {"from_attributes": True}