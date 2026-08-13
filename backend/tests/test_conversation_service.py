"""
对话/角色「不存在」require 深函数 + 附件下载响应头 helper 单测（BE-2）

覆盖：
    1. require_conversation：命中返回 ORM 对象 / 未命中抛 ConversationNotFoundError（逐字）
    2. require_character：命中返回（附带对话数量）/ 未命中抛 CharacterNotFoundError（逐字）
    3. build_content_disposition：ASCII 兜底 + RFC 5987 filename* 并存；
       UTF-8 编码采用最严格安全参数（空格 / 斜杠 / 中文一律百分号编码），
       产出字符串恒为 latin-1 可编码（HTTP header 契约）

依赖：pytest + SQLite 内存库（conftest.db_session）。
"""

from __future__ import annotations

import pytest

from backend.app.api.headers import build_content_disposition
from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.services import character as character_service
from backend.app.services import conversation as conversation_service
from backend.app.services.exceptions import (
    CharacterNotFoundError,
    ConversationNotFoundError,
)

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


def _create_conversation(db_session, character_id: int, **overrides: object) -> Conversation:
    """落库一个对话，返回持久化实例"""
    base = {
        "character_id": character_id,
        "title": "关于诗歌的讨论",
        "model_provider": "claude",
        "model_name": "claude-sonnet-5",
    }
    base.update(overrides)
    conv = Conversation(**base)
    db_session.add(conv)
    db_session.commit()
    db_session.refresh(conv)
    return conv


# ── 1. require_conversation ──


class TestRequireConversation:
    def test_returns_existing_conversation(self, db_session) -> None:
        """命中 → 返回同一 ORM 对象"""
        char = _create_character(db_session)
        conv = _create_conversation(db_session, char.id)

        got = conversation_service.require_conversation(db_session, conv.id)

        assert got is conv
        assert got.title == "关于诗歌的讨论"

    def test_missing_raises_not_found(self, db_session) -> None:
        """未命中 → ConversationNotFoundError + 逐字文案（路由层 404 的语义来源）"""
        with pytest.raises(ConversationNotFoundError) as excinfo:
            conversation_service.require_conversation(db_session, 99999)
        assert str(excinfo.value) == "对话不存在"

    def test_update_missing_returns_none(self, db_session) -> None:
        """防御契约：update_conversation 对不存在 id 返回 None（路由不再消费，保留给内部调用）"""
        from backend.app.schemas.conversation import ConversationUpdate

        result = conversation_service.update_conversation(
            db_session, 99999, ConversationUpdate(title="x")
        )
        assert result is None

    def test_delete_missing_returns_false(self, db_session) -> None:
        """防御契约：delete_conversation 对不存在 id 返回 False（路由不再消费，保留给内部调用）"""
        assert conversation_service.delete_conversation(db_session, 99999) is False


# ── 2. require_character ──


class TestRequireCharacter:
    def test_returns_existing_character_with_count(self, db_session) -> None:
        """命中 → 返回同一 ORM 对象（附带对话数量，供响应体 conversation_count）"""
        char = _create_character(db_session)

        got = character_service.require_character(db_session, char.id)

        assert got is char
        assert got.conversation_count == 0

    def test_missing_raises_not_found(self, db_session) -> None:
        """未命中 → CharacterNotFoundError + 逐字文案（路由层 404 的语义来源）"""
        with pytest.raises(CharacterNotFoundError) as excinfo:
            character_service.require_character(db_session, 99999)
        assert str(excinfo.value) == "角色不存在"

    def test_update_missing_returns_none(self, db_session) -> None:
        """防御契约：update_character 对不存在 id 返回 None（路由不再消费，保留给内部调用）"""
        from backend.app.schemas.character import CharacterUpdate

        result = character_service.update_character(db_session, 99999, CharacterUpdate(name="x"))
        assert result is None

    def test_delete_missing_returns_false(self, db_session) -> None:
        """防御契约：delete_character 对不存在 id 返回 False（路由不再消费，保留给内部调用）"""
        assert character_service.delete_character(db_session, 99999) is False


# ── 3. build_content_disposition ──


class TestBuildContentDisposition:
    def test_ascii_fallback_and_rfc5987(self) -> None:
        """ASCII 兜底 + RFC 5987 filename* 并存（附件语义 + 中文名可往返）"""
        header = build_content_disposition("conversation-1.json", "conversation-1-艾莉.json")
        assert header.startswith("attachment; ")
        assert 'filename="conversation-1.json"' in header
        assert "filename*=UTF-8''conversation-1-" in header
        assert "%E8%89%BE%E8%8E%89" in header  # 「艾莉」UTF-8 百分号编码

    def test_strict_quote_safe_params(self) -> None:
        """最严格安全参数：空格 / 斜杠 / 中文一律编码（斜杠不再原样保留）"""
        header = build_content_disposition("a.json", "a/b c中文.json")
        assert "a%2Fb%20c%E4%B8%AD%E6%96%87.json" in header
        assert "/" not in header[header.index("filename*"):]

    def test_header_always_latin1_encodable(self) -> None:
        """产出字符串恒为 latin-1 可编码（HTTP header 契约，中文只出现在 filename* 编码段）"""
        header = build_content_disposition("character-7.json", "角色卡-测试·毒舌助手.json")
        header.encode("latin-1")  # 不抛 UnicodeEncodeError 即通过
