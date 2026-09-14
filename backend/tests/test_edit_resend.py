"""
编辑重发（edit_and_resend）—— service 编排契约锁（message-edit-resend 工单 01）

锁定语义（spec §edit-resend 原子性契约）：
1. 编辑 user → 就地替换 content + 物理截断后续 + 新 assistant 落库
   （历史条数 = 编辑点(含)之前 + 1 新 assistant）
2. 编辑目标非 user → InvalidEditTargetError（400）
3. 目标不存在 / 不属于该会话 → MessageNotFoundError（404）
4. LLM 失败 → HTTPException 上抛，content 未变、无截断、无新消息（零落库，
   session close 回滚未提交变更）

依赖：pytest + SQLite 内存库（conftest.db_session）+ monkeypatch LLMFactory.get_provider。
不构造真实网络请求。
"""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.message import ChatResponse
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ConversationNotFoundError,
    InvalidEditTargetError,
    MessageNotFoundError,
)
from backend.app.services.llm import resolver as llm_resolver
from backend.app.services.llm.errors import LLMAuthError

__all__: list[str] = []


# ── 测试基础设施（与 test_regenerate.py 同模式）──


def _create_character(
    db: Session,
    first_mes: str = "",
    temperature: float = 0.7,
    post_history_instructions: str = "",
) -> int:
    """落库一个角色（默认无 greeting），返回 id"""
    char = Character(
        name="测试角色",
        personality="冷静、睿智",
        first_mes=first_mes,
        temperature=temperature,
        post_history_instructions=post_history_instructions,
    )
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


def _patch_api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    """让 setting_service.api_key 恒返回测试 Key（绕过 DB 设置表）"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")


class _FakeProvider:
    """记录 generate 调用参数的假 Provider（可配置固定回复或抛出 LLMError）"""

    def __init__(self, reply: str = "这是编辑重发回复", error: Exception | None = None) -> None:
        self.reply = reply
        self.error = error
        self.calls: list[tuple] = []

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        self.calls.append((messages, temperature, max_tokens, model))
        if self.error is not None:
            raise self.error
        return self.reply


class _FakeLLMFactory:
    """替代 LLMFactory.get_provider 的工厂（与 test_regenerate 同模式，不污染真实工厂）"""

    def __init__(self, provider: _FakeProvider) -> None:
        self.provider = provider

    def get_provider(self, name: str, api_key: str, base_url: str | None = None) -> _FakeProvider:
        return self.provider


def _patch_factory(monkeypatch: pytest.MonkeyPatch, provider: _FakeProvider) -> None:
    """让 llm_resolver.LLMFactory.get_provider 返回指定假 Provider"""
    monkeypatch.setattr(llm_resolver, "LLMFactory", _FakeLLMFactory(provider))


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


# ── edit_and_resend 编排 ──


class TestEditAndResend:
    """编排契约：替换 + 截断 + 新建，单 commit 原子落库；LLM 失败零落库"""

    async def test_happy_path_replaces_and_truncates(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """编辑首条 user → 就地替换 + 物理截断全部后续 + 新 assistant 落库"""
        fake = _FakeProvider(reply="新的回复")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        _patch_factory(monkeypatch, fake)
        target = _message_id(db_session, conv.id, "第一轮问")

        resp = await chat_service.edit_and_resend(db_session, conv.id, target, "修正后的问题")

        assert isinstance(resp, ChatResponse)
        assert resp.reply == "新的回复"
        assert resp.conversation_id == conv.id
        assert isinstance(resp.message_id, int)
        # 历史 = 编辑点(含)之前 + 1 新 assistant；后续全部截断
        assert _contents(db_session, conv.id) == ["修正后的问题", "新的回复"]
        # 无幽灵重复 user（仅保留被编辑的 1 条 user）
        user_count = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv.id, Message.role == Role.USER)
            .count()
        )
        assert user_count == 1

    async def test_edit_last_user_preserves_prior_messages(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """编辑末条 user → 之前消息保留，仅替换目标 + 截断其后 + 新 assistant"""
        fake = _FakeProvider(reply="新第二轮答")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        _patch_factory(monkeypatch, fake)
        target = _message_id(db_session, conv.id, "第二轮问")

        resp = await chat_service.edit_and_resend(db_session, conv.id, target, "修正后第二轮问")

        assert resp.reply == "新第二轮答"
        assert _contents(db_session, conv.id) == [
            "第一轮问", "第一轮答", "修正后第二轮问", "新第二轮答",
        ]

    async def test_generate_input_uses_edited_content(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """组装契约：generate 收到的末条 user = 修正后内容；后续不进上下文"""
        fake = _FakeProvider(reply="新的回复")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        _patch_factory(monkeypatch, fake)
        target = _message_id(db_session, conv.id, "第一轮问")

        await chat_service.edit_and_resend(db_session, conv.id, target, "修正后的问题")

        messages, _, _, _ = fake.calls[0]
        # 末条 = 修正后的触发 user；后续（第二轮问/答）不进上下文
        assert messages[-1] == {"role": "user", "content": "修正后的问题"}
        user_contents = [m["content"] for m in messages if m["role"] == "user"]
        assert "修正后的问题" in user_contents
        assert "第二轮问" not in user_contents

    async def test_target_not_user_raises_invalid_edit(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """编辑目标非 user（assistant）→ InvalidEditTargetError（路由层转 400）"""
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        target = _message_id(db_session, conv.id, "答")

        with pytest.raises(InvalidEditTargetError):
            await chat_service.edit_and_resend(db_session, conv.id, target, "新内容")

    async def test_target_not_found_raises(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """message_id 不存在 → MessageNotFoundError（404）"""
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        with pytest.raises(MessageNotFoundError):
            await chat_service.edit_and_resend(db_session, conv.id, 99999, "新内容")

    async def test_target_other_conversation_raises(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """message_id 属于其他对话 → MessageNotFoundError（不得跨会话编辑）"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_a = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv_a.id, ("user", "问A"), ("assistant", "答A"))
        conv_b = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv_b.id, ("user", "问B"), ("assistant", "答B"))
        target = _message_id(db_session, conv_a.id, "问A")

        with pytest.raises(MessageNotFoundError):
            await chat_service.edit_and_resend(db_session, conv_b.id, target, "新内容")

    async def test_conversation_not_found(self, db_session: Session) -> None:
        """对话不存在 → ConversationNotFoundError（404）"""
        with pytest.raises(ConversationNotFoundError):
            await chat_service.edit_and_resend(db_session, 99999, 1, "新内容")

    async def test_llm_error_zero_persistence(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """LLM 失败 → HTTPException 上抛；content 未变、无截断、无新消息（零落库）"""
        fake = _FakeProvider(error=LLMAuthError("bad key"))
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        _patch_factory(monkeypatch, fake)
        target = _message_id(db_session, conv.id, "第一轮问")
        before = _contents(db_session, conv.id)

        with pytest.raises(HTTPException) as exc:
            await chat_service.edit_and_resend(db_session, conv.id, target, "修正后的问题")

        assert exc.value.status_code == 401
        # 模拟 session close 回滚未提交变更 → 时间线原样保留（零落库）
        db_session.rollback()
        db_session.expire_all()
        assert _contents(db_session, conv.id) == before
        assert _contents(db_session, conv.id) == [
            "第一轮问", "第一轮答", "第二轮问", "第二轮答",
        ]
