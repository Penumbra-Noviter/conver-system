"""
Mod Pydantic Schema — 请求模型（MD-1）

字段规格见 docs/chat-simulator-upgrade-spec.md §MD-1 表格。target_area 用
Literal 收口三值（prompt|memory|css）、source 用 Literal 收口（manual|imported）；
边界在 Schema 层「拒」，服务层只存取（与 lorebook 双轨分界同构）。
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

__all__ = ["ModCreate", "ModUpdate"]


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
