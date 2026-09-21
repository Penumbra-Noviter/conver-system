"""
角色 Pydantic Schema — 请求/响应模型

为兼容 V2 规范，Schema 字段与 ORM 模型一一对应，
conversation_count 为计算字段（非 ORM 列），由 JOIN 查询填充。
"""

from __future__ import annotations

import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


# ── 预设对话（few-shot 示范，项目自有字段，不进 V2 规范清单）──

# 预设对话数量上限（单一来源：character_card 归一化截断消费）
PRESET_DIALOGUE_MAX = 10


class PresetDialogue(BaseModel):
    """预设对话条目（few-shot 示范）：标题 + 正文"""
    name: str = Field(..., description="对话标题")
    content: str = Field(..., description="对话正文")


# ── 基类（16 个 V2 内容字段 ── 单一来源）──


class CharacterBase(BaseModel):
    """角色 V2 内容字段基类（16 字段，所有 Schema 从此派生，消除字段清单重复重声明）"""
    name: str = Field(..., min_length=1, max_length=100, description="角色名称")
    description: str = Field("", description="角色简短描述")
    personality: str = Field("", description="人格设定（核心 system prompt）")
    scenario: str = Field("", description="场景设定")
    first_mes: str = Field("", description="开场白")
    mes_example: str = Field("", description="对话范例")
    system_prompt: str = Field("", description="覆盖系统提示词")
    post_history_instructions: str = Field("", description="历史后指令")
    alternate_greetings: list[str] = Field(default_factory=list, description="备选开场白")
    tags: list[str] = Field(default_factory=list, description="标签")
    creator: str = Field("", description="创作者")
    version: str = Field("1.0", description="版本")
    creator_notes: dict = Field(default_factory=dict, description="创作者备注")
    extensions: dict = Field(default_factory=dict, description="扩展字段")
    avatar: Optional[str] = Field(None, description="头像 base64 / 路径")
    temperature: float = Field(0.7, ge=0.0, le=2.0, description="LLM 温度参数")
    # 采样参数（SP-1）：None = 不覆盖 provider 默认；仅 OpenAI 系生效
    top_p: Optional[float] = Field(None, ge=0.0, le=1.0, description="LLM top_p 采样参数（OpenAI 系）")
    presence_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0, description="LLM presence_penalty（OpenAI 系）")
    frequency_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0, description="LLM frequency_penalty（OpenAI 系）")
    max_tokens: Optional[int] = Field(None, ge=1, le=131072, description="LLM 最大输出 token（None=provider 默认）")
    # PD-5 专家模式（项目自有字段，不进 V2 规范清单）
    prompt_mode: str = Field("simple", description="专家模式开关（simple/expert）")
    expert_prompt: str = Field("", description="专家模式整段 system prompt")
    # PD-4 预设对话（项目自有字段，不进 V2 规范清单，经 conver_system 命名空间往返）
    preset_dialogues: list[PresetDialogue] = Field(default_factory=list, description="预设对话（few-shot 示范）")

    @field_validator("preset_dialogues", mode="before")
    @classmethod
    def _coerce_none_preset_dialogues(cls, value: object) -> object:
        """存量行 NULL 归一：preset_dialogues 为 None 时按 [] 处理（默认值仅字段缺席生效）

        旧库升级（_ensure_character_preset_dialogue_column 补列无回填）与显式 null
        写库都会产出 NULL 行；list 型必填字段遇 None 令 FastAPI serialize_response
        抛 ResponseValidationError（GET /api/characters 500，2026-09-21 冒烟实测）。
        """
        return [] if value is None else value


# ── 请求体（继承基类，字段清单由 CharacterBase 唯一定义）──


class CharacterCreate(CharacterBase):
    """创建角色请求（继承 CharacterBase 16 字段）"""
    pass


class CharacterUpdate(CharacterBase):
    """更新角色请求（所有字段可选）"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    personality: Optional[str] = None
    scenario: Optional[str] = None
    first_mes: Optional[str] = None
    mes_example: Optional[str] = None
    system_prompt: Optional[str] = None
    post_history_instructions: Optional[str] = None
    alternate_greetings: Optional[list[str]] = None
    tags: Optional[list[str]] = None
    creator: Optional[str] = None
    version: Optional[str] = None
    creator_notes: Optional[dict] = None
    extensions: Optional[dict] = None
    avatar: Optional[str] = None
    temperature: Optional[float] = Field(None, ge=0.0, le=2.0)
    top_p: Optional[float] = Field(None, ge=0.0, le=1.0)
    presence_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0)
    frequency_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0)
    max_tokens: Optional[int] = Field(None, ge=1, le=131072)
    prompt_mode: Optional[str] = None
    expert_prompt: Optional[str] = None
    preset_dialogues: Optional[list[PresetDialogue]] = None

    @field_validator("name", "prompt_mode", "expert_prompt", mode="before")
    @classmethod
    def _reject_null_for_not_null_columns(cls, value: object) -> object:
        """拒绝显式 null：三列 `nullable=False`，显式 None 经 `update_character` 的
        `exclude_unset` 写库路径 `setattr(char, field, None)` → IntegrityError(500)。

        省略字段（partial update 语义）走 Pydantic 默认值 None，因
        `validate_default=False` 不触发本 validator，仍可安全省略。
        """
        if value is None:
            raise ValueError("NOT NULL 列不接受 null，请省略该字段")
        return value


# ── 响应体（继承基类 + 元数据字段）──


class CharacterResponse(CharacterBase):
    """角色响应体（继承 CharacterBase 16 字段 + 元数据）"""
    id: int
    conversation_count: int = 0
    created_at: datetime.datetime
    updated_at: datetime.datetime

    model_config = {"from_attributes": True}


# ── 文档解析 ──


class DocParseRequest(BaseModel):
    """文档解析请求"""
    text: str = Field(..., min_length=1, max_length=50000, description="用户文档文本")
    provider: Optional[str] = Field(None, description="LLM Provider（留空则用默认）")
    model: Optional[str] = Field(None, description="LLM 模型名（留空则用默认）")


class DocParseResponse(BaseModel):
    """文档解析响应"""
    name: str = ""
    description: str = ""
    personality: str = ""
    scenario: str = ""
    first_mes: str = ""
    mes_example: str = ""
    system_prompt: str = ""
    post_history_instructions: str = ""
    tags: list[str] = []
    creator: str = ""
    parsed_fields: list[str] = Field(default_factory=list, description="成功提取的字段列表")
