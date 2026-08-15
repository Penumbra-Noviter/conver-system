"""
存键契约常量映射 — 契约锁测试

锁的内容：
1. 6 个公开符号的存在性（__all__ 与模块空间一致）
2. CHARACTER_V2_FIELDS 长度 16 + 成员集合与 ORM Column 名集合一致
3. PROMPT_FIELDS / PARSE_FIELDS / EXPORT_FIELDS 长度与成员精确匹配
4. V2_KEY_MAP / V1_TO_V2_MAP 键值对精确匹配
"""

from __future__ import annotations

import pytest
from backend.app.models.character import Character
from backend.app.services.character_fields import (
    CHARACTER_V2_FIELDS,
    PROMPT_FIELDS,
    PARSE_FIELDS,
    EXPORT_FIELDS,
    V2_KEY_MAP,
    V1_TO_V2_MAP,
    __all__,
)


class TestCharacterFieldsExports:
    """6 个公开符号的存在性与 __all__ 一致性"""

    def test_all_exported_symbols_exist(self):
        expected = {
            "CHARACTER_V2_FIELDS",
            "PROMPT_FIELDS",
            "PARSE_FIELDS",
            "EXPORT_FIELDS",
            "V2_KEY_MAP",
            "V1_TO_V2_MAP",
        }
        assert set(__all__) == expected, f"__all__ 应含 {expected}，实际 {set(__all__)}"

    def test_module_has_all_symbols(self):
        import backend.app.services.character_fields as m
        for sym in __all__:
            assert hasattr(m, sym), f"模块缺 {sym}"


class TestCharacterV2Fields:
    """CHARACTER_V2_FIELDS — 16 内容字段，与 ORM 声明的 V2 列集合一致"""

    # 从 ORM 提取 V2 内容字段名（排除 id / created_at / updated_at）
    ORM_V2_COLUMNS = {
        c.name for c in Character.__table__.columns
        if c.name not in ("id", "created_at", "updated_at")
    }

    def test_length(self):
        assert len(CHARACTER_V2_FIELDS) == 16

    def test_set_equals_orm_v2_columns(self):
        assert set(CHARACTER_V2_FIELDS) == self.ORM_V2_COLUMNS, (
            f"CHARACTER_V2_FIELDS 集合 {set(CHARACTER_V2_FIELDS)} 与 ORM V2 列 {self.ORM_V2_COLUMNS} 不一致"
        )

    def test_no_duplicates(self):
        assert len(CHARACTER_V2_FIELDS) == len(set(CHARACTER_V2_FIELDS))

    def test_first_field_is_name(self):
        assert CHARACTER_V2_FIELDS[0] == "name"

    def test_contains_core_fields(self):
        for f in ("name", "description", "personality", "scenario", "first_mes", "temperature", "avatar"):
            assert f in CHARACTER_V2_FIELDS, f"缺核心字段 {f}"


class TestPromptFields:
    """PROMPT_FIELDS — 6 字段 prompt 组装投影"""

    EXPECTED = frozenset({
        "name", "system_prompt", "personality", "scenario", "mes_example", "post_history_instructions",
    })

    def test_length(self):
        assert len(PROMPT_FIELDS) == 6

    def test_members(self):
        assert set(PROMPT_FIELDS) == self.EXPECTED, f"PROMPT_FIELDS 应为 {self.EXPECTED}，实际 {set(PROMPT_FIELDS)}"

    def test_no_duplicates(self):
        assert len(PROMPT_FIELDS) == len(set(PROMPT_FIELDS))

    def test_is_subset_of_v2(self):
        assert set(PROMPT_FIELDS).issubset(CHARACTER_V2_FIELDS)


class TestParseFields:
    """PARSE_FIELDS — 10 字段文档解析投影"""

    EXPECTED = frozenset({
        "name", "description", "personality", "scenario", "first_mes",
        "mes_example", "system_prompt", "post_history_instructions", "tags", "creator",
    })

    def test_length(self):
        assert len(PARSE_FIELDS) == 10

    def test_members(self):
        assert set(PARSE_FIELDS) == self.EXPECTED, f"PARSE_FIELDS 应为 {self.EXPECTED}，实际 {set(PARSE_FIELDS)}"

    def test_no_duplicates(self):
        assert len(PARSE_FIELDS) == len(set(PARSE_FIELDS))

    def test_is_subset_of_v2(self):
        assert set(PARSE_FIELDS).issubset(CHARACTER_V2_FIELDS)


class TestExportFields:
    """EXPORT_FIELDS — 9 字段导出投影（含 id，非 V2 内容字段子集）"""

    EXPECTED = frozenset({
        "id", "name", "description", "personality", "scenario",
        "first_mes", "system_prompt", "avatar", "temperature",
    })

    def test_length(self):
        assert len(EXPORT_FIELDS) == 9

    def test_members(self):
        assert set(EXPORT_FIELDS) == self.EXPECTED, f"EXPORT_FIELDS 应为 {self.EXPECTED}，实际 {set(EXPORT_FIELDS)}"

    def test_no_duplicates(self):
        assert len(EXPORT_FIELDS) == len(set(EXPORT_FIELDS))

    def test_contains_id(self):
        assert "id" in EXPORT_FIELDS, "EXPORT_FIELDS 应含 id"

    def test_content_fields_without_id_are_v2_subset(self):
        without_id = set(EXPORT_FIELDS) - {"id"}
        assert without_id.issubset(CHARACTER_V2_FIELDS), (
            f"EXPORT_FIELDS 不含 id 的字段 {without_id} 不在 CHARACTER_V2_FIELDS 中"
        )


class TestV2KeyMap:
    """V2_KEY_MAP — DB 字段名 → V2 协议键名映射"""

    def test_version_maps_to_character_version(self):
        assert V2_KEY_MAP["version"] == "character_version"

    def test_temperature_not_in_map(self):
        # temperature 走 extensions.conver_system 命名空间，不在直接映射中
        assert "temperature" not in V2_KEY_MAP

    def test_map_keys_are_v2_fields(self):
        for k in V2_KEY_MAP:
            assert k in CHARACTER_V2_FIELDS, f"V2_KEY_MAP 键 {k} 不在 CHARACTER_V2_FIELDS 中"


class TestV1ToV2Map:
    """V1_TO_V2_MAP — V1 旧卡字段名 → V2/DB 字段名映射（8 项，从 character_card.py 迁入）"""

    EXPECTED = {
        "char_name": "name",
        "char_persona": "personality",
        "char_greeting": "first_mes",
        "example_dialogue": "mes_example",
        "world_scenario": "scenario",
        "creatorcomment": "creator_notes",
        "char_version": "character_version",
        "description": "description",
    }

    def test_length(self):
        assert len(V1_TO_V2_MAP) == 8

    def test_members(self):
        assert V1_TO_V2_MAP == self.EXPECTED

    def test_values_are_v2_fields_or_character_version(self):
        for v in V1_TO_V2_MAP.values():
            assert v in CHARACTER_V2_FIELDS or v == "character_version", (
                f"V1_TO_V2_MAP 值 {v} 既不在 CHARACTER_V2_FIELDS 也不是 character_version"
            )
