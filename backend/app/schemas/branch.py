"""
分支快照 Schema（BR-1：版本化导出结构；BR-2 导入/重建复用）

快照 JSON 为**版本化**结构（version 字段，SNAPSHOT_VERSION 单一来源）：未知版本
拒绝导入并给明确错误（validate_branch_snapshot，见 services/conversation_export.py）。
swipes 的 message_index 指向 messages 数组下标（截断后重新编号），重建按序填充。
lorebook_entries 携带重建用全部内容字段（character_id 由导入方按新会话设置）。
"""

from __future__ import annotations

import datetime

from pydantic import BaseModel, Field

__all__ = [
    "SNAPSHOT_VERSION",
    "BranchSnapshot",
    "BranchSnapshotLorebookEntry",
    "BranchSnapshotMessage",
    "BranchSnapshotSwipe",
]

#: 当前快照版本（版本化导出/导入契约；未知版本拒绝导入）
SNAPSHOT_VERSION = 1


class BranchSnapshotLorebookEntry(BaseModel):
    """世界书条目快照（重建用全部内容字段；character_id 由导入方设置）"""
    title: str = ""
    keys: list[str] = Field(default_factory=list)
    content: str = ""
    constant: bool = False
    order: int = 100
    probability: int = 100
    group_name: str = ""
    group_weight: int = 100
    match_mode: str = "or"
    position: str = "world"
    depth: int = 20
    source: str = "manual"
    enabled: bool = True


class BranchSnapshotMessage(BaseModel):
    """消息快照（role/content/created_at 往返保真）"""
    role: str
    content: str
    created_at: datetime.datetime | None = None


class BranchSnapshotSwipe(BaseModel):
    """消息候选快照（message_index = messages 数组下标；重建按序填充）"""
    message_index: int = Field(..., ge=0, description="messages 数组下标")
    swipes: list[str] = Field(default_factory=list)
    active_swipe_index: int = Field(0, ge=0, description="激活候选序号")


class BranchSnapshot(BaseModel):
    """分支快照（版本化导出/导入契约；BR-2 重建会话的唯一输入）"""
    version: int = SNAPSHOT_VERSION
    character_id: int
    model_provider: str | None = None
    model_name: str | None = None
    title: str | None = None
    messages: list[BranchSnapshotMessage] = Field(default_factory=list)
    lorebook_entries: list[BranchSnapshotLorebookEntry] = Field(default_factory=list)
    swipes: list[BranchSnapshotSwipe] = Field(default_factory=list)