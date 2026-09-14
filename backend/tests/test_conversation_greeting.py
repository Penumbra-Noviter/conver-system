"""
PD-1 预设开场白后端（指定开场白 override）契约锁

覆盖 create_conversation 的开场白预插语义（spec docs/prompt-polish-spec.md §PD-1）：
    1. 未传 greeting → 预插 character.first_mes（模板变量替换，零回归）
    2. 传 greeting="自定义" → 预插该内容
    3. 传 greeting=None（显式）→ 不预插，消息表为空
    4. 传 greeting=""（显式空）→ 不预插
    5. greeting 含 {{user}}/{{char}} → 正确替换
    6. character.first_mes 为空 + 未传 greeting → 不预插（既有语义不变）

Falsify 补强：
    7. character_id 不存在 + greeting 非空 → 不崩溃（{{char}} 回落默认 "Character"）

依赖：pytest + SQLite 内存库（conftest.db_session）。
"""

from __future__ import annotations

from backend.app.models.character import Character
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
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


def _messages(db_session, conversation_id: int) -> list[Message]:
    """按插入序返回会话全部消息"""
    return (
        db_session.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.id.asc())
        .all()
    )


class TestGreetingDefault:
    def test_unset_uses_first_mes_with_template_vars(self, db_session) -> None:
        """未传 greeting → 预插 first_mes，模板变量替换（零回归）"""
        char = _create_character(db_session, first_mes="你好，{{user}}！我是{{char}}。")

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id)
        )

        messages = _messages(db_session, conv.id)
        assert len(messages) == 1
        assert messages[0].role == Role.ASSISTANT
        assert messages[0].content == "你好，User！我是测试角色。"


class TestGreetingOverride:
    def test_explicit_greeting_preinserts(self, db_session) -> None:
        """传 greeting 非空 → 预插该内容（覆盖 first_mes）"""
        char = _create_character(db_session, first_mes="默认开场白")

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id, greeting="自定义开场白")
        )

        messages = _messages(db_session, conv.id)
        assert len(messages) == 1
        assert messages[0].role == Role.ASSISTANT
        assert messages[0].content == "自定义开场白"

    def test_greeting_template_vars_replaced(self, db_session) -> None:
        """greeting 含 {{user}}/{{char}} → 正确替换"""
        char = _create_character(db_session)

        conv = conversation_service.create_conversation(
            db_session,
            ConversationCreate(character_id=char.id, greeting="嗨{{user}}，我是{{char}}哦"),
        )

        messages = _messages(db_session, conv.id)
        assert len(messages) == 1
        assert messages[0].content == "嗨User，我是测试角色哦"


class TestGreetingSuppressed:
    def test_explicit_none_greeting_skips(self, db_session) -> None:
        """传 greeting=None（显式）→ 不预插，消息表为空"""
        char = _create_character(db_session, first_mes="默认开场白")

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id, greeting=None)
        )

        assert _messages(db_session, conv.id) == []

    def test_explicit_empty_greeting_skips(self, db_session) -> None:
        """传 greeting=""（显式空）→ 不预插"""
        char = _create_character(db_session, first_mes="默认开场白")

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id, greeting="")
        )

        assert _messages(db_session, conv.id) == []

    def test_empty_first_mes_unset_skips(self, db_session) -> None:
        """first_mes 为空 + 未传 greeting → 不预插（既有语义不变）"""
        char = _create_character(db_session, first_mes="")

        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char.id)
        )

        assert _messages(db_session, conv.id) == []


class TestGreetingFalsify:
    def test_missing_character_with_greeting_does_not_crash(self, db_session) -> None:
        """character_id 不存在 + greeting 非空 → 不崩溃，{{char}} 回落默认值"""
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=99999, greeting="我是{{char}}")
        )

        messages = _messages(db_session, conv.id)
        assert len(messages) == 1
        assert messages[0].content == "我是Character"
