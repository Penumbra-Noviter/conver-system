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
    model_name: str = Field("claude-sonnet-5", description="具体模型名")
    greeting: Optional[str] = Field(None, description="指定开场白（显式传入时覆盖角色 first_mes；None/空串表示不预插）")


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
    # BR-2 分支来源元数据（F-100 能力 2：列表分支来源标记的最小暴露）
    #   普通会话四字段均为 None；branch_from_message_preview 为锚消息 content 的
    #   截断预览（~60 字符，服务层 list_conversations 经关联查询带出，非表列，
    #   同 message_count 的序列化面扩展，不涉及表结构变更）。
    parent_conversation_id: Optional[int] = None
    branch_from_message_id: Optional[int] = None
    branch_title: Optional[str] = None
    branch_from_message_preview: Optional[str] = None

    model_config = {"from_attributes": True}


class PromptDebugSegment(BaseModel):
    """prompt-debug 分段（role / content / source，PD-3）"""
    role: str
    content: str
    source: str


class PromptDebugResponse(BaseModel):
    """prompt-debug 只读追溯响应（不落库、不触发 LLM）

    来源枚举 source ∈ {character/world/memory/mod/history/user}（见
    services/llm/prompt.py SOURCE_* 常量）。segments 的 content 序列与
    assemble_chat_context 产出 messages 逐条一致（debug 只见证、不改线上）。
    """
    conversation_id: int
    character_name: str
    model: str
    prompt_mode: str
    segments: list[PromptDebugSegment]


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
