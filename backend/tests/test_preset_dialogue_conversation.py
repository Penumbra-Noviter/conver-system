"""
NPD-05 预设对话快照列与创建固化 — 契约锁

覆盖（spec .scratch/narrative-preset-dialogue/issues/05-*）：
    1. create_conversation 传 preset_dialogue 非空 → 落库为原样快照，响应体序列化一致
    2. create_conversation 不传 preset_dialogue → 落库 null，响应体序列化 null
    3. create_conversation 传 preset_dialogue=""（显式空）→ 归一为 null（不落伪值）
    4. 迁移幂等：存量 conversations 表缺列 → 补 TEXT 可空列，连续两次调用无副作用

Falsify 补强：
    5. preset_dialogue 含中文/换行/引号 → 原样往返（快照不加工、不截断）

依赖：pytest + SQLite 内存库（conftest.db_session）。
"""

from __future__ import annotations

from sqlalchemy import create_engine, text

from backend.app.models.character import Character
from backend.app.schemas.conversation import ConversationCreate, ConversationResponse
from backend.app.services import conversation as conversation_service

__all__: list[str] = []


def _create_character(db_session, **overrides: object) -> Character:
    """落库一个角色，返回持久化实例"""
    base = {
        "name": "测试角色",
        "description": "一个用于测试的角色",
        "personality": "冷静、睿智",
        "scenario": "月下竹林",
        "first_mes": "你好，久等了。",
        "mes_example": "",
        "system_prompt": "",
        "post_history_instructions": "",
        "alternate_greetings": [],
        "tags": [],
        "creator": "",
        "version": "1.0",
        "creator_notes": {},
        "extensions": {},
        "avatar": None,
        "temperature": 0.7,
    }
    base.update(overrides)
    char = Character(**base)
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char


class TestPresetDialogueSnapshot:
    def test_create_with_preset_dialogue_stores_and_serializes(self, db_session) -> None:
        """传 preset_dialogue 非空 → 原样固化到 ORM 列，响应体经 from_attributes 序列化该值"""
        char = _create_character(db_session)

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id, preset_dialogue="预设对话内容")
        )

        assert conv.preset_dialogue == "预设对话内容"
        resp = ConversationResponse.model_validate(conv)
        assert resp.preset_dialogue == "预设对话内容"

    def test_create_without_preset_dialogue_is_null(self, db_session) -> None:
        """不传 preset_dialogue → 落库 null，响应体序列化 null"""
        char = _create_character(db_session)

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id)
        )

        assert conv.preset_dialogue is None
        resp = ConversationResponse.model_validate(conv)
        assert resp.preset_dialogue is None

    def test_create_with_empty_preset_dialogue_is_null(self, db_session) -> None:
        """传 preset_dialogue=""（显式空）→ 归一为 null（不落伪值空串）"""
        char = _create_character(db_session)

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id, preset_dialogue="")
        )

        assert conv.preset_dialogue is None
        resp = ConversationResponse.model_validate(conv)
        assert resp.preset_dialogue is None

    def test_preset_dialogue_roundtrips_verbatim(self, db_session) -> None:
        """含中文/换行/引号的快照 → 原样往返（快照语义：不加工、不截断）"""
        char = _create_character(db_session)
        raw = '她说："你好。\n我们走吧。"'

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id, preset_dialogue=raw)
        )

        assert conv.preset_dialogue == raw


class TestPresetDialogueMigration:
    def _legacy_engine(self):
        """模拟存量库：conversations 表不含 preset_dialogue 列（历史 schema 形态）"""
        engine = create_engine("sqlite://")
        with engine.connect() as conn:
            conn.execute(text(
                "CREATE TABLE conversations ("
                " id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL,"
                " title VARCHAR(200), model_provider VARCHAR(50), model_name VARCHAR(100),"
                " created_at DATETIME, updated_at DATETIME)"
            ))
            conn.commit()
        return engine

    def test_migration_adds_column_idempotent(self) -> None:
        """核心契约：首次补列 + 幂等再跑无事；列类型 TEXT、可空（无 NOT NULL/默认值）"""
        from backend.app.database import _ensure_conversation_preset_dialogue

        engine = self._legacy_engine()
        _ensure_conversation_preset_dialogue(engine)  # 首次补列
        _ensure_conversation_preset_dialogue(engine)  # 幂等：再跑无事

        with engine.connect() as conn:
            columns = {
                row[1]: row
                for row in conn.execute(text("PRAGMA table_info(conversations)")).fetchall()
            }
            assert "preset_dialogue" in columns
            # PRAGMA 列序：type=2, notnull=3, dflt=4；可空 TEXT、无默认值
            assert columns["preset_dialogue"][2] == "TEXT"
            assert columns["preset_dialogue"][3] == 0
            assert columns["preset_dialogue"][4] is None
            # 存量行零影响（旧行 preset_dialogue 为 NULL）
            conn.execute(text("INSERT INTO conversations (character_id, title) VALUES (1, '旧行')"))
            conn.commit()
            assert conn.execute(
                text("SELECT preset_dialogue FROM conversations WHERE title='旧行'")
            ).scalar() is None


class TestCharacterPresetDialogueMigration:
    """PD-4 character.preset_dialogues 自愈迁移（波 1 修复缺口补登记）"""

    def _legacy_engine(self):
        """模拟存量库：characters 表不含 preset_dialogues 列"""
        engine = create_engine("sqlite://")
        with engine.connect() as conn:
            conn.execute(text(
                "CREATE TABLE characters ("
                " id INTEGER PRIMARY KEY, name VARCHAR(100) NOT NULL)"
            ))
            conn.commit()
        return engine

    def test_migration_adds_column_idempotent(self) -> None:
        """首次补列 + 幂等再跑无事；存量行 preset_dialogues 为 NULL 零影响"""
        from backend.app.database import _ensure_character_preset_dialogue_column

        engine = self._legacy_engine()
        _ensure_character_preset_dialogue_column(engine)  # 首次补列
        _ensure_character_preset_dialogue_column(engine)  # 幂等：再跑无事

        with engine.connect() as conn:
            columns = {
                row[1]: row
                for row in conn.execute(text("PRAGMA table_info(characters)")).fetchall()
            }
            assert "preset_dialogues" in columns
            conn.execute(text("INSERT INTO characters (name) VALUES ('旧行')"))
            conn.commit()
            assert conn.execute(
                text("SELECT preset_dialogues FROM characters WHERE name='旧行'")
            ).scalar() is None
