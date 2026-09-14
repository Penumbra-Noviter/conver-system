"""
消息级编辑 / 删除 —— service 契约锁（message-edit-resend 工单 01）

锁定语义（spec §edit-resend / §delete message）：
1. update_message：就地替换 content 持久化；不存在 → MessageNotFoundError；
   commit=False 供 edit_and_resend 参与原子落库（回滚后原内容保留）
2. delete_message 删 USER：该条及 id >= 目标 的全部消息删除
3. delete_message 删 ASSISTANT：仅删该条，其 swipes 级联删除，触发 user 保留
4. delete_message bump 所属会话 updated_at（排序置顶不变量）

依赖：pytest + SQLite 内存库（conftest.db_session）。级联测试在测试内执行
PRAGMA foreign_keys=ON（db_session fixture 用独立 create_engine 未开 FK，
镜像 test_message_swipes 的级联锁模式）。
"""

from __future__ import annotations

import datetime as _dt

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, MessageSwipe, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services.exceptions import MessageNotFoundError

__all__: list[str] = []


# ── 测试布景辅助（与 test_regenerate.py 同模式）──


def _create_character(db: Session, first_mes: str = "") -> int:
    """落库一个角色（默认无 greeting），返回 id"""
    char = Character(name="编辑删除角色", personality="测试", first_mes=first_mes)
    db.add(char)
    db.commit()
    db.refresh(char)
    return char.id


def _create_conversation(
    db: Session,
    *,
    character_id: int | None = None,
) -> Conversation:
    """落库一个绑定角色的对话，返回 Conversation 实例"""
    if character_id is None:
        character_id = _create_character(db)
    return conversation_service.create_conversation(
        db,
        ConversationCreate(
            character_id=character_id,
            model_provider="claude",
            model_name="claude-test",
        ),
    )


def _add_messages(db: Session, conversation_id: int, *pairs: tuple[str, str]) -> None:
    """按顺序追加消息：每对为 (role, content)"""
    for role, content in pairs:
        message_service.create_message(db, conversation_id, Role(role), content)


def _message_id(db: Session, conversation_id: int, content: str) -> int:
    """按内容取消息 id（测试布景辅助）"""
    msg = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id, Message.content == content)
        .one()
    )
    return msg.id


def _contents(db: Session, conversation_id: int) -> list[str]:
    """按 id 升序返回对话全部消息内容"""
    rows = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.id.asc())
        .all()
    )
    return [row.content for row in rows]


# ── update_message ──


class TestUpdateMessage:
    """就地替换 content 持久化 + commit=False 原子性辅助契约"""

    def test_persists_content(self, db_session: Session) -> None:
        """就地替换 content 并持久化（fresh 查询仍见新内容），返回更新后的 Message"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "原始内容"))
        msg_id = _message_id(db_session, conv.id, "原始内容")

        updated = message_service.update_message(db_session, msg_id, "修正后的内容")

        assert updated.id == msg_id
        assert updated.content == "修正后的内容"
        # 持久化：expire 后 fresh 查询仍见新内容
        db_session.expire_all()
        assert _contents(db_session, conv.id) == ["修正后的内容"]

    def test_missing_raises(self, db_session: Session) -> None:
        """不存在 → MessageNotFoundError"""
        with pytest.raises(MessageNotFoundError):
            message_service.update_message(db_session, 99999, "内容")

    def test_no_commit_defers(self, db_session: Session) -> None:
        """commit=False：就地替换但不提交，回滚后原内容保留（供 edit_and_resend 原子落库）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "原始内容"))
        msg_id = _message_id(db_session, conv.id, "原始内容")

        msg = message_service.update_message(db_session, msg_id, "新内容", commit=False)

        assert msg.content == "新内容"
        db_session.rollback()  # 模拟 session close 回滚未提交变更
        db_session.expire_all()
        assert _contents(db_session, conv.id) == ["原始内容"]


# ── delete_message ──


class TestDeleteMessage:
    """角色感知删除 + bump updated_at"""

    def test_delete_user_truncates_following(self, db_session: Session) -> None:
        """删 USER → 该条及 id >= 目标 的全部消息删除（后续 assistant 失去触发源）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        target = _message_id(db_session, conv.id, "第二轮问")

        message_service.delete_message(db_session, target)

        assert _contents(db_session, conv.id) == ["第一轮问", "第一轮答"]

    def test_delete_user_from_first_truncates_all(self, db_session: Session) -> None:
        """删首条 USER → 整段清空（id >= 目标 全删）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "第一轮问"), ("assistant", "第一轮答"))
        target = _message_id(db_session, conv.id, "第一轮问")

        message_service.delete_message(db_session, target)

        assert _contents(db_session, conv.id) == []

    def test_delete_user_cascades_following_swipes(self, db_session: Session) -> None:
        """删 USER 截断后续 → 被截断 assistant 的 swipes 级联删除（bulk delete 路径 FK 级联锁定）"""
        db_session.execute(text("PRAGMA foreign_keys=ON"))
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        first_assistant = _message_id(db_session, conv.id, "第一轮答")
        second_assistant = _message_id(db_session, conv.id, "第二轮答")
        message_service.add_swipe(db_session, first_assistant, "一候选", make_active=False)
        message_service.add_swipe(db_session, second_assistant, "二候选", make_active=False)
        target = _message_id(db_session, conv.id, "第二轮问")

        message_service.delete_message(db_session, target)

        assert _contents(db_session, conv.id) == ["第一轮问", "第一轮答"]
        # 被截断 assistant 的 swipes 级联删除（bulk delete 依赖 FK CASCADE）
        assert (
            db_session.query(MessageSwipe)
            .filter(MessageSwipe.message_id == second_assistant)
            .count()
            == 0
        )
        # 保留的第一轮 assistant 的 swipes 不受影响
        assert (
            db_session.query(MessageSwipe)
            .filter(MessageSwipe.message_id == first_assistant)
            .count()
            == 2
        )

    def test_delete_assistant_only_and_cascade_swipes(self, db_session: Session) -> None:
        """删 ASSISTANT → 仅删该条，候选级联删除，触发 user 保留"""
        db_session.execute(text("PRAGMA foreign_keys=ON"))
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        assistant_id = _message_id(db_session, conv.id, "答")
        # 追加候选（候选 0 播种 + 2 条新候选）
        message_service.add_swipe(db_session, assistant_id, "候选一", make_active=False)
        message_service.add_swipe(db_session, assistant_id, "候选二", make_active=False)
        assert (
            db_session.query(MessageSwipe)
            .filter(MessageSwipe.message_id == assistant_id)
            .count()
            == 3
        )

        message_service.delete_message(db_session, assistant_id)

        # 触发 user 保留，assistant 已删
        assert _contents(db_session, conv.id) == ["问"]
        # swipes 级联删除（FK ON DELETE CASCADE）
        assert (
            db_session.query(MessageSwipe)
            .filter(MessageSwipe.message_id == assistant_id)
            .count()
            == 0
        )

    def test_delete_assistant_keeps_trigger_user(self, db_session: Session) -> None:
        """删 assistant 后触发 user 保留（可再触发新回复）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        assistant_id = _message_id(db_session, conv.id, "答")

        message_service.delete_message(db_session, assistant_id)

        assert _contents(db_session, conv.id) == ["问"]

    def test_delete_bumps_updated_at(self, db_session: Session) -> None:
        """delete_message bump 所属会话 updated_at（会话列表排序置顶不变量）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        before = _dt.datetime(2000, 1, 1)
        conv.updated_at = before
        db_session.commit()
        target = _message_id(db_session, conv.id, "答")

        message_service.delete_message(db_session, target)

        db_session.refresh(conv)
        assert conv.updated_at > before

    def test_delete_missing_raises(self, db_session: Session) -> None:
        """不存在 → MessageNotFoundError"""
        with pytest.raises(MessageNotFoundError):
            message_service.delete_message(db_session, 99999)
