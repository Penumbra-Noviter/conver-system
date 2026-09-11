"""
MS-3 「继续」生成（append 续写）— 端到端 / 服务层 / 下层函数的契约测试

覆盖（验收语义契约，spec §MS-3）：
    1. 续写前后消息条数不变、内容为「原内容 + 续写片段」
    2. 不追加 user 消息（与正常发送区分；DB 层零新增消息行）
    3. 失败时原内容不被破坏（原消息零改动断言：失败不落库、不新增候选）
    4. 续写触发形态锁定：尾随 user 消息 = 续写指令 + 原消息末段，不新增 system
       （适配器 _prepare_messages「last system wins」锁定契约下，尾随 system
       会挤掉角色 persona/system 链 → 续写出戏；user 形态与普通路径 system 链一致）
    5. 上下文契约：末条 user 触发前一条即被续写目标（full 原文），触发 user 仅一次
    6. 端点 POST /api/conversations/{id}/continue：响应体与 ChatResponse 同构
       （reply/message_id/conversation_id）；错误语义 404（对话不存在）/
       400（末条非 assistant / 无可续写目标）

依赖：pytest + SQLite 内存库（conftest.db_session）+ monkeypatch LLMFactory.get_provider。
不构造真实网络请求。
"""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy.orm import Session

from backend.app.api.routes import conversations as conversations_route
from backend.app.models.message import Message, MessageSwipe, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.message import ChatResponse
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    ConversationNotFoundError,
    InvalidContinueTargetError,
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
    from backend.app.models.character import Character

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
    provider: str = "claude",
    model: str = "claude-test",
    character_id: int | None = None,
):
    """落库一个绑定角色的对话，返回 Conversation 实例"""
    if character_id is None:
        character_id = _create_character(db)
    return conversation_service.create_conversation(
        db,
        ConversationCreate(
            character_id=character_id,
            model_provider=provider,
            model_name=model,
        ),
    )


def _patch_api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    """让 setting_service.api_key 恒返回测试 Key（绕过 DB 设置表）"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")


class _FakeProvider:
    """记录 generate 调用参数的假 Provider（可配置固定回复或抛出 LLMError）"""

    def __init__(self, reply: str = "续写片段", error: Exception | None = None) -> None:
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
    """替代 LLMFactory.get_provider 的工厂（与 test_regenerate 同模式）"""

    def __init__(self, provider: _FakeProvider) -> None:
        self.provider = provider

    def get_provider(self, name: str, api_key: str, base_url: str | None = None) -> _FakeProvider:
        return self.provider


def _patch_factory(monkeypatch: pytest.MonkeyPatch, provider: _FakeProvider) -> None:
    """让 llm_resolver.LLMFactory.get_provider 返回指定假 Provider"""
    monkeypatch.setattr(llm_resolver, "LLMFactory", _FakeLLMFactory(provider))


def _add_messages(
    db: Session,
    conversation_id: int,
    *pairs: tuple[str, str],
) -> None:
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


def _setup_continue_pair(
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
    provider: _FakeProvider,
):
    """组装一次续写回合环境：对话 + [user, assistant] 一轮，返回 (conv, target_id)"""
    _patch_api_key(monkeypatch)
    conv = _create_conversation(db)
    _add_messages(
        db, conv.id,
        ("user", "第一轮问"), ("assistant", "第一轮答"),
    )
    _patch_factory(monkeypatch, provider)
    return conv, _message_id(db, conv.id, "第一轮答")


# ── 1. 续写触发形态（尾随 user 消息，spec 两可选实证拍板）──


class TestContinuationTail:
    """末段锚点纯函数（_continuation_tail）契约"""

    def test_short_content_returns_whole(self) -> None:
        """短内容（≤ 上限）→ 整体作为末段"""
        assert chat_service._continuation_tail("第一轮答") == "第一轮答"

    def test_long_content_returns_tail_window(self) -> None:
        """长内容 → 取末 200 字符（含末句）"""
        long = "长。" * 300
        tail = chat_service._continuation_tail(long)
        assert tail == long[-200:]

    def test_whitespace_stripped(self) -> None:
        """首尾空白剔除后取末段"""
        assert chat_service._continuation_tail("  第一轮答\n\n") == "第一轮答"

    def test_empty_content_returns_empty(self) -> None:
        """空 / None / 纯空白 → 空串（触发消息只含指令）"""
        assert chat_service._continuation_tail(None) == ""
        assert chat_service._continuation_tail("") == ""
        assert chat_service._continuation_tail("   ") == ""


class TestContinueTriggerShape:
    """被续写目标原文是上下文末条 assistant，其后尾随唯一 user 触发（指令 + 末段）"""

    async def test_trigger_is_trailing_user_with_instruction_and_tail(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """核心契约：末条 = user 触发（含续写指令与末段），前一条 = 目标 assistant；
        上下文中不新增任何 system（不挤掉 persona 链）"""
        fake = _FakeProvider()
        conv, target_id = _setup_continue_pair(db_session, monkeypatch, fake)

        await chat_service.continue_chat(db_session, conv.id)

        messages, _, _, _ = fake.calls[0]
        assert messages[-2] == {"role": "assistant", "content": "第一轮答"}
        last = messages[-1]
        assert last["role"] == "user"
        assert chat_service.CONTINUE_INSTRUCTION in last["content"]
        assert "第一轮答" in last["content"]  # 末段锚点
        # 目标原文只出现一次（无重复 user）
        target_occurrences = [
            m for m in messages if m["role"] == "assistant" and m["content"] == "第一轮答"
        ]
        assert len(target_occurrences) == 1
        # 不新增 system（尾随 system 会挤掉 persona — 适配器 last-system-wins 锁定契约）
        assert messages[-1]["role"] == "user"

    async def test_trigger_uses_tail_not_whole_for_long_reply(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """长回复 → 触发内容含原文末段（非整篇）"""
        long_reply = "字。" * 300
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", long_reply))
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        await chat_service.continue_chat(db_session, conv.id)

        last = fake.calls[0][0][-1]
        assert last["content"].endswith(long_reply[-200:])

    async def test_phi_character_no_trailing_system(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """带 post_history_instructions 的角色：继续路径剥离尾随 PHI（与重生成一致），
        末条仍为 user 触发（无 system 残留）"""
        fake = _FakeProvider()
        _patch_api_key(monkeypatch)
        char_id = _create_character(
            db_session, post_history_instructions="请始终保持角色人设与第一人称。"
        )
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        _patch_factory(monkeypatch, fake)

        await chat_service.continue_chat(db_session, conv.id)

        messages, _, _, _ = fake.calls[0]
        assert messages[-1]["role"] == "user"
        assert messages[-2] == {"role": "assistant", "content": "答"}


# ── 2. continue_chat 服务编排 ──


class TestContinueChatService:
    """编排契约：解析末条 assistant → 组装（不插 user）→ 生成 → add_swipe 追加候选"""

    async def test_happy_path_message_count_unchanged_and_content_extended(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """核心契约 1：续写前后消息条数不变；内容 = 原内容 + 续写片段"""
        fake = _FakeProvider(reply="，接着往下写的内容")
        conv, target_id = _setup_continue_pair(db_session, monkeypatch, fake)

        resp = await chat_service.continue_chat(db_session, conv.id)

        assert isinstance(resp, ChatResponse)
        assert resp.message_id == target_id
        assert resp.conversation_id == conv.id
        assert resp.reply == "第一轮答，接着往下写的内容"
        # 消息条数不变（仍为 user + assistant 两条，无新消息行）
        assert len(_contents(db_session, conv.id)) == 2
        # MS-1 swipes 语义：原内容保留为候选 0，续写结果追加为新候选并置激活
        target = db_session.query(Message).filter(Message.id == target_id).first()
        assert target.content == "第一轮答，接着往下写的内容"
        assert [s.content for s in message_service.list_swipes(db_session, target_id)] == [
            "第一轮答",
            "第一轮答，接着往下写的内容",
        ]
        assert target.active_swipe_index == 1

    async def test_no_user_message_appended(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """核心契约 2：不追加 user 消息（与正常发送区分）——user 条数不变、rows 总数不变"""
        fake = _FakeProvider()
        conv, _ = _setup_continue_pair(db_session, monkeypatch, fake)

        await chat_service.continue_chat(db_session, conv.id)

        user_count = db_session.query(Message).filter(
            Message.conversation_id == conv.id, Message.role == Role.USER
        ).count()
        assert user_count == 1
        assert len(_contents(db_session, conv.id)) == 2

    async def test_content_follows_active_swipe_when_existing_candidates(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """消息已有候选且激活非 0：续写基座 = 激活候选，追加其为新候选"""
        fake = _FakeProvider(reply="（续写）")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "原始答"))
        _patch_factory(monkeypatch, fake)
        target_id = _message_id(db_session, conv.id, "原始答")
        # 先重生成一次：候选 = [原始答, 重写答]，激活 1
        message_service.add_swipe(db_session, target_id, "重写答", make_active=True)
        assert db_session.query(Message).filter(Message.id == target_id).first().content == "重写答"

        await chat_service.continue_chat(db_session, conv.id)

        target = db_session.query(Message).filter(Message.id == target_id).first()
        assert target.content == "重写答（续写）"
        assert [s.content for s in message_service.list_swipes(db_session, target_id)] == [
            "原始答",
            "重写答",
            "重写答（续写）",
        ]
        assert target.active_swipe_index == 2

    async def test_empty_continuation_is_noop(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Provider 返回空白 → 零改动 no-op：不追加候选（防 base+""=base 重复候选行）"""
        fake = _FakeProvider(reply="   ")
        conv, target_id = _setup_continue_pair(db_session, monkeypatch, fake)

        resp = await chat_service.continue_chat(db_session, conv.id)

        assert resp.reply == "第一轮答"
        assert _contents(db_session, conv.id) == ["第一轮问", "第一轮答"]
        assert message_service.list_swipes(db_session, target_id) == []

    async def test_llm_error_leaves_original_untouched(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """核心契约 3：LLM 失败 → HTTPException 上抛，原内容零改动（无候选、无落库）"""
        fake = _FakeProvider(error=LLMAuthError("bad key"))
        conv, target_id = _setup_continue_pair(db_session, monkeypatch, fake)

        with pytest.raises(HTTPException) as exc:
            await chat_service.continue_chat(db_session, conv.id)

        assert exc.value.status_code == 401
        assert _contents(db_session, conv.id) == ["第一轮问", "第一轮答"]
        target = db_session.query(Message).filter(Message.id == target_id).first()
        assert target.content == "第一轮答"
        assert message_service.list_swipes(db_session, target_id) == []

    async def test_llm_error_with_existing_swipes_keeps_them(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """已有候选时失败：候选集原样保留（不追加、不修改）"""
        fake = _FakeProvider(error=LLMAuthError("bad key"))
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "原始答"))
        _patch_factory(monkeypatch, fake)
        target_id = _message_id(db_session, conv.id, "原始答")
        message_service.add_swipe(db_session, target_id, "重写答", make_active=True)

        with pytest.raises(HTTPException):
            await chat_service.continue_chat(db_session, conv.id)

        target = db_session.query(Message).filter(Message.id == target_id).first()
        assert target.content == "重写答"
        assert [s.content for s in message_service.list_swipes(db_session, target_id)] == [
            "原始答",
            "重写答",
        ]

    async def test_greeting_only_can_be_continued(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """仅有问候（assistant greeting）→ 续写基座 = greeting（末条 assistant 即可续写）"""
        fake = _FakeProvider(reply="（继续问候）")
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session, first_mes="欢迎你来到我的世界！")
        conv = _create_conversation(db_session, character_id=char_id)
        message_service.auto_insert_greeting(db_session, conv.id, user_name="User")
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.continue_chat(db_session, conv.id)

        assert resp.reply == "欢迎你来到我的世界！（继续问候）"
        assert _contents(db_session, conv.id) == ["欢迎你来到我的世界！（继续问候）"]
        assert len(_contents(db_session, conv.id)) == 1  # 条数不变（仍 1 条）

    async def test_conversation_not_found(self, db_session: Session) -> None:
        """对话不存在 → ConversationNotFoundError（路由层转 404）"""
        with pytest.raises(ConversationNotFoundError):
            await chat_service.continue_chat(db_session, 99999)

    async def test_empty_conversation_invalid_target(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """对话无任何消息 → InvalidContinueTargetError（无续写目标）"""
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        with pytest.raises(InvalidContinueTargetError):
            await chat_service.continue_chat(db_session, conv.id)

    async def test_last_message_not_assistant_invalid_target(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """末条非 assistant（user 在末尾）→ InvalidContinueTargetError（只能在末条之后续写）"""
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"), ("user", "追问"))

        with pytest.raises(InvalidContinueTargetError):
            await chat_service.continue_chat(db_session, conv.id)

    async def test_missing_api_key_raises(self, db_session: Session) -> None:
        """未配置 API Key → ApiKeyMissingError（路由层转 400）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        with pytest.raises(ApiKeyMissingError):
            await chat_service.continue_chat(db_session, conv.id)


# ── 3. 端点契约 ──


class TestContinueRoute:
    """POST /api/conversations/{id}/continue：响应同构 + 领域异常上抛"""

    async def test_success_returns_chat_response(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """成功 → ChatResponse 同构字段（reply/message_id/conversation_id）"""
        fake = _FakeProvider(reply="（路由续写）")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        _patch_factory(monkeypatch, fake)
        target_id = _message_id(db_session, conv.id, "答")

        resp = await conversations_route.continue_chat(conv.id, db_session)

        assert isinstance(resp, ChatResponse)
        assert resp.reply == "答（路由续写）"
        assert resp.message_id == target_id
        assert resp.conversation_id == conv.id

    async def test_conversation_not_found_404(self, db_session: Session) -> None:
        """对话不存在 → 上抛 ConversationNotFoundError（统一 handler 转 404）"""
        with pytest.raises(ConversationNotFoundError):
            await conversations_route.continue_chat(99999, db_session)

    async def test_no_continuable_target_400(self, db_session: Session) -> None:
        """末条非 assistant → 上抛 InvalidContinueTargetError（统一 handler 转 400）；
        目标校验先于 Provider 解析（无 Key 也不影响该错误分支）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "只有问题"))
        with pytest.raises(InvalidContinueTargetError):
            await conversations_route.continue_chat(conv.id, db_session)