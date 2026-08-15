"""
角色字段常量映射 — 单一映射深模块

集中维护角色 V2 字段清单及各视角的字段投影子集，
消除 8 处重复硬编码（C5 架构评审候选，Strong）：

    1. models/character.py Column 声明
    2. schemas/character.py CharacterCreate 声明
    3. schemas/character.py CharacterUpdate 声明
    4. schemas/character.py CharacterResponse 声明
    5. schemas/conversation.py ConversationExportCharacter 声明
    6. services/character_card.py to_v2_card 手写字段映射
    7. services/character_card.py from_v2_card 手写字段映射
    8. services/character_card.py _V1_TO_V2 映射

模块内所有符号为纯常量（零依赖，仅 import typing），
通过 `__all__` 导出 6 个公开符号供测试与其它模块引用校验。

领域术语见仓库根 CONTEXT.md 术语表。
"""

from __future__ import annotations

from typing import Final

__all__ = [
    "CHARACTER_V2_FIELDS",
    "PROMPT_FIELDS",
    "PARSE_FIELDS",
    "EXPORT_FIELDS",
    "V2_KEY_MAP",
    "V1_TO_V2_MAP",
]

# ── V2 全部内容字段（16 项） ──
# 顺序与 ORM models/character.py Column 声明一致（排除 id/created_at/updated_at）
CHARACTER_V2_FIELDS: Final[list[str]] = [
    "name",
    "description",
    "personality",
    "scenario",
    "first_mes",
    "mes_example",
    "system_prompt",
    "post_history_instructions",
    "alternate_greetings",
    "tags",
    "creator",
    "version",
    "creator_notes",
    "extensions",
    "avatar",
    "temperature",
]

# ── Prompt 组装视角（6 项） ──
# 用于构建 LLM 系统提示词的角色字段子集
PROMPT_FIELDS: Final[list[str]] = [
    "name",
    "system_prompt",
    "personality",
    "scenario",
    "mes_example",
    "post_history_instructions",
]

# ── 文档解析视角（10 项） ──
# 文档解析可提取的角色字段
PARSE_FIELDS: Final[list[str]] = [
    "name",
    "description",
    "personality",
    "scenario",
    "first_mes",
    "mes_example",
    "system_prompt",
    "post_history_instructions",
    "tags",
    "creator",
]

# ── 导出视角（9 项） ──
# 对话 JSON 导出中 character 段的字段子集
EXPORT_FIELDS: Final[list[str]] = [
    "id",
    "name",
    "description",
    "personality",
    "scenario",
    "first_mes",
    "system_prompt",
    "avatar",
    "temperature",
]

# ── DB 字段名 → V2 协议键名映射 ──
# 仅登记真正换名的字段；temperature 走 extensions.conver_system 命名空间，
# 不在此处直接映射；其余大多同名，由 to_v2_card 直接引用。
V2_KEY_MAP: Final[dict[str, str]] = {
    "version": "character_version",
}

# ── V1 旧卡字段名 → V2/DB 字段名映射（8 项） ──
# 从 character_card.py _V1_TO_V2 迁入，保持原样。
V1_TO_V2_MAP: Final[dict[str, str]] = {
    "char_name": "name",
    "char_persona": "personality",
    "char_greeting": "first_mes",
    "example_dialogue": "mes_example",
    "world_scenario": "scenario",
    "creatorcomment": "creator_notes",
    "char_version": "character_version",
    "description": "description",
}