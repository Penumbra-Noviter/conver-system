"""
T5 重生成后端端点 — 端到端 / 服务层 / 下层函数的契约测试

覆盖（验收语义契约，按 T0 spike 定稿）：
    1. assemble_chat_context（prepare_chat 抽出的下层函数）：不插入 user、
       不自动插入 greeting；current_input 时追加输入、None 时（重生成）不追加
    2. delete_messages_from：锚定 PK id 截断（target 及之后全部），不 commit
    3. create_message_no_commit：不 commit 的 create 辅助（事务原子性）
    4. regenerate_chat 编排：截断 → 组装（不插入 user）→ 生成 → 落库（单事务）；
       无幽灵重复 user；LLM 失败回滚截断
    5. 端点 POST /api/conversations/{id}/regenerate：无 body / 带 message_id；
       响应体与既有非流式 ChatResponse 同构（reply/message_id/conversation_id）；
       错误语义 404（conversation/message 不存在）/ 400（target 非 assistant / 无 user）

依赖：pytest + SQLite 内存库（conftest.db_session）+ monkeypatch LLMFactory.get_provider。
不构造真实网络请求。
"""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy.orm import Session

from backend.app.api.routes import conversations as conversations_route
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.message import ChatResponse, RegenerateRequest
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ConversationNotFoundError,
    InvalidRegenerateTargetError,
    MessageNotFoundError,
)
from backend.app.services.llm import resolver as llm_resolver
from backend.app.services.llm.errors import LLMAuthError

__all__: list[str] = []


# ── 测试基础设施（与 test_chat_service.py 同模式）──


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

    def __init__(self, reply: str = "这是重生成回复", error: Exception | None = None) -> None:
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
    """替代 LLMFactory.get_provider 的工厂（与 test_p35 同模式，不污染真实工厂）"""

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


def _setup_regenerate_pair(
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
    provider: _FakeProvider,
):
    """组装一次重生成回合环境：对话 + [user, assistant] 两轮，返回 (conv, target_id)"""
    _patch_api_key(monkeypatch)
    conv = _create_conversation(db)
    _add_messages(
        db, conv.id,
        ("user", "第一轮问"), ("assistant", "第一轮答"),
        ("user", "第二轮问"), ("assistant", "第二轮答"),
    )
    _patch_factory(monkeypatch, provider)
    return conv, _message_id(db, conv.id, "第二轮答")


# ── 1. assemble_chat_context 下层函数 ──


class TestAssembleChatContext:
    """prepare_chat 抽出的下层函数：不插 user / 不插 greeting；current_input 语义"""

    def test_conversation_not_found_raises(self, db_session: Session) -> None:
        """对话不存在 → ConversationNotFoundError（路由层转 404）"""
        with pytest.raises(ConversationNotFoundError):
            chat_service.assemble_chat_context(db_session, 99999, current_input="你好")

    def test_no_user_insert_no_greeting_insert(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """核心契约：组装不落库——不插入 user、不自动插入 greeting"""
        _patch_api_key(monkeypatch)
        _patch_factory(monkeypatch, _FakeProvider())
        # 用 first_mes="" 确保 create_conversation 不预插 greeting
        char_id = _create_character(db_session, first_mes="")
        conv = _create_conversation(db_session, character_id=char_id)
        # 组装前对话无任何消息
        assert message_service.get_messages(db_session, conv.id) == []

        chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

        # 把关：没有自动插 greeting、没有落库 user
        assert message_service.get_messages(db_session, conv.id) == []

    def test_happy_path_appends_current_input(self, db_session: Session, monkeypatch: pytest.MonkeyPatch) -> None:
        """current_input 提供时：消息列表末条为当前输入，且不落库"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session, temperature=0.9)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "历史消息"), ("assistant", "历史回复"))
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="当前输入")

        assert ctx.conversation.id == conv.id
        assert ctx.temperature == 0.9
        assert ctx.provider is fake
        assert ctx.messages[-1] == {"role": "user", "content": "当前输入"}
        # 把关：组装本身不落库（消息数不增）
        assert len(message_service.get_messages(db_session, conv.id)) == 2

    def test_current_input_none_does_not_duplicate_last_user(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """核心契约：current_input=None（重生成路径）→ 不追加、不重复末条 user"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        # 截断后的场景：history 只剩 [user(触发), assistant(上一轮答)]
        # 构造 user 末条在前的状态：模拟截断 target 后的时间线
        _add_messages(db_session, conv.id, ("user", "触发消息"), ("assistant", "上一轮回复"))
        db_session.query(Message).filter(Message.content == "上一轮回复").delete()
        db_session.commit()
        _patch_factory(monkeypatch, _FakeProvider())

        ctx = chat_service.assemble_chat_context(db_session, conv.id)

        # 消息列表不重复 "触发消息"（history + 追加仅一次）
        user_msgs = [m for m in ctx.messages if m["role"] == "user"]
        assert len(user_msgs) == 1
        assert user_msgs[0]["content"] == "触发消息"
        # 末条为触发 user（LLM 以它为待回复目标）
        assert ctx.messages[-1] == {"role": "user", "content": "触发消息"}

    def test_current_input_none_empty_history(self, db_session: Session, monkeypatch: pytest.MonkeyPatch) -> None:
        """防御：空历史 + current_input=None → 不抛错（消息列表无重复）"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _patch_factory(monkeypatch, _FakeProvider())

        ctx = chat_service.assemble_chat_context(db_session, conv.id)

        user_msgs = [m for m in ctx.messages if m["role"] == "user"]
        assert user_msgs == []

    def test_missing_api_key_raises(self, db_session: Session) -> None:
        """未配置 API Key → ApiKeyMissingError（路由层转 400）"""
        from backend.app.services.exceptions import ApiKeyMissingError

        conv = _create_conversation(db_session)
        with pytest.raises(ApiKeyMissingError):
            chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")


# ── 2. delete_messages_from 截断服务函数 ──


class TestDeleteMessagesFrom:
    """时间线截断：锚定 PK id，删除 target 及其后全部，不 commit"""

    def test_deletes_target_and_after(self, db_session: Session) -> None:
        """截断语义：删除 target 及所有 id >= target 的消息"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv.id,
            ("user", "问题"), ("assistant", "旧回复"),
            ("user", "额外问题"), ("assistant", "额外回复"),
        )
        target_id = _message_id(db_session, conv.id, "旧回复")

        deleted = message_service.delete_messages_from(db_session, conv.id, target_id)
        db_session.commit()

        assert deleted == 3  # 旧回复 + 额外问题 + 额外回复
        assert _contents(db_session, conv.id) == ["问题"]

    def test_anchor_is_pk_id_not_created_at(self, db_session: Session) -> None:
        """回归锁：created_at 微秒 tie 时不误删邻居——锚定 id 只删 target 自身"""
        import datetime

        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"), ("user", "触发"),
        )
        # 强制全部共享同一微秒时间戳（真实运行中相邻 create_message 可能 tie）
        rows = db_session.query(Message).filter(Message.conversation_id == conv.id).all()
        shared = datetime.datetime(2026, 1, 1, 12, 0, 0, 1)
        for r in rows:
            r.created_at = shared
        db_session.commit()

        target_id = _message_id(db_session, conv.id, "触发")

        message_service.delete_messages_from(db_session, conv.id, target_id)
        db_session.commit()

        # 只删触发（id 锚），同刻的前两轮全部保留
        assert _contents(db_session, conv.id) == ["第一轮问", "第一轮答"]

    def test_no_commit_write_when_rolled_back(self, db_session: Session) -> None:
        """事务原子性：不 commit 的删除可整体回滚（LLM 失败路径）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问题"), ("assistant", "回复"))
        target_id = _message_id(db_session, conv.id, "回复")

        message_service.delete_messages_from(db_session, conv.id, target_id)
        db_session.rollback()

        assert _contents(db_session, conv.id) == ["问题", "回复"]


# ── 3. create_message_no_commit 原子性辅助 ──


class TestCreateMessageNoCommit:
    """不 commit 的 create 辅助：供删除+重建同一事务使用"""

    def test_creates_without_committing(self, db_session: Session) -> None:
        """不 commit：对象尚未持久化（id 为 None），回滚后不残留"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)

        msg = message_service.create_message_no_commit(db_session, conv.id, Role.ASSISTANT, "新回复")

        assert msg.role == Role.ASSISTANT
        assert msg.content == "新回复"
        # 未 commit：对象 pending，id 尚未分配
        assert msg.id is None
        db_session.rollback()
        assert _contents(db_session, conv.id) == []

    def test_commits_and_refreshes_after_explicit_commit(self, db_session: Session) -> None:
        """显式 commit + refresh 后可见并拿到 id"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)

        msg = message_service.create_message_no_commit(db_session, conv.id, Role.ASSISTANT, "新回复")
        db_session.commit()
        db_session.refresh(msg)

        assert msg.id is not None
        assert _contents(db_session, conv.id) == ["新回复"]


# ── 4. regenerate_chat 编排 ──


class TestRegenerateChatService:
    """编排契约：截断 → 组装（不插 user）→ 生成 → 落库（单事务）"""

    async def test_happy_path_no_message_id_uses_last_assistant(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """缺省 message_id → 以末条 assistant 为 target 重生成，返回 ChatResponse"""
        fake = _FakeProvider(reply="新的回复")
        conv, _ = _setup_regenerate_pair(db_session, monkeypatch, fake)

        resp = await chat_service.regenerate_chat(db_session, conv.id)

        assert isinstance(resp, ChatResponse)
        assert resp.reply == "新的回复"
        assert resp.conversation_id == conv.id
        assert isinstance(resp.message_id, int)
        # 时间线截断：末条 assistant（第二轮答）被删，第二轮问保留，追加新的回复
        assert _contents(db_session, conv.id) == ["第一轮问", "第一轮答", "第二轮问", "新的回复"]
        # 无幽灵重复 user（仍为原有 2 条 user，重生成不新增）
        user_count = db_session.query(Message).filter(
            Message.conversation_id == conv.id, Message.role == Role.USER
        ).count()
        assert user_count == 2

    async def test_happy_path_with_message_id_truncates_all_after(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """显式 message_id 指向非末条 assistant → 删除 target 及其后全部再重生成"""
        fake = _FakeProvider(reply="重写第一轮答")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        _patch_factory(monkeypatch, fake)
        target_id = _message_id(db_session, conv.id, "第一轮答")

        resp = await chat_service.regenerate_chat(db_session, conv.id, message_id=target_id)

        assert resp.reply == "重写第一轮答"
        # 删掉 [第一轮答, 第二轮问, 第二轮答]，保留 [第一轮问]，重生成一条
        assert _contents(db_session, conv.id) == ["第一轮问", "重写第一轮答"]

    async def test_generate_input_is_trigger_user_without_duplicate(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """组装契约：generate 收到的消息列表不重复触发 user（第二轮问只出现一次），末条即触发 user"""
        fake = _FakeProvider(reply="新的回复")
        conv, _ = _setup_regenerate_pair(db_session, monkeypatch, fake)

        await chat_service.regenerate_chat(db_session, conv.id)

        messages, _, _, _ = fake.calls[0]
        # 截断后剩余 [第一轮问, 第一轮答, 第二轮问]，触发源 = 第二轮问
        assert messages[-1] == {"role": "user", "content": "第二轮问"}
        # 触发源在消息列表中只出现一次（不重复）
        trigger_occurrences = [
            m for m in messages if m["role"] == "user" and m["content"] == "第二轮问"
        ]
        assert len(trigger_occurrences) == 1

    async def test_llm_error_rolls_back_truncation(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """LLM 失败 → HTTPException 上抛，且截断被回滚（单事务原子性）"""
        fake = _FakeProvider(error=LLMAuthError("bad key"))
        conv, _ = _setup_regenerate_pair(db_session, monkeypatch, fake)

        with pytest.raises(HTTPException) as exc:
            await chat_service.regenerate_chat(db_session, conv.id)

        assert exc.value.status_code == 401
        # 截断回滚：原始时间线完整保留
        assert _contents(db_session, conv.id) == [
            "第一轮问", "第一轮答", "第二轮问", "第二轮答",
        ]

    async def test_phi_role_trigger_is_last_user_not_phi(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """带 post_history_instructions（PHI）的角色重生成：generate 收到的末条必须
        是触发 user（第二轮问），而非 PHI（system）——W2 增量审核 BREAKS-高修复：
        `messages[:-1]` 丢弃 "" user 后须再移除末尾 system（PHI）恢复触发源"""
        fake = _FakeProvider(reply="新的回复")
        _patch_api_key(monkeypatch)
        char_id = _create_character(
            db_session, post_history_instructions="请始终保持角色人设与第一人称。"
        )
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        _patch_factory(monkeypatch, fake)

        await chat_service.regenerate_chat(db_session, conv.id)

        messages, _, _, _ = fake.calls[0]
        # 末条 = 触发 user（非 PHI/system）；触发 user 在列表中只出现一次
        assert messages[-1] == {"role": "user", "content": "第二轮问"}
        trigger_occurrences = [
            m for m in messages if m["role"] == "user" and m["content"] == "第二轮问"
        ]
        assert len(trigger_occurrences) == 1

    async def test_non_llm_error_after_truncation_rolls_back(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """截断后 resolve_llm/组装抛非 LLMError（如 ProviderNotSupportedError）→
        同样回滚截断（不落半截断）——W2 增量审核 BREAKS-中修复：异常边界扩到
        截断后全部 Exception，不只 LLMError"""
        from backend.app.services.exceptions import ProviderNotSupportedError

        _patch_api_key(monkeypatch)
        fake = _FakeProvider()
        conv, _ = _setup_regenerate_pair(db_session, monkeypatch, fake)

        # 让截断后（步骤 5）的 assemble_chat_context 抛非 LLMError 领域异常
        monkeypatch.setattr(
            chat_service,
            "assemble_chat_context",
            lambda *a, **k: (_ for _ in ()).throw(ProviderNotSupportedError("模拟 provider 移除")),
        )

        with pytest.raises(ProviderNotSupportedError):
            await chat_service.regenerate_chat(db_session, conv.id)

        # 截断回滚：原始时间线完整保留（无半截断持久化）
        assert _contents(db_session, conv.id) == [
            "第一轮问", "第一轮答", "第二轮问", "第二轮答",
        ]

    async def test_conversation_not_found(self, db_session: Session) -> None:
        """对话不存在 → ConversationNotFoundError（路由层转 404）"""
        with pytest.raises(ConversationNotFoundError):
            await chat_service.regenerate_chat(db_session, 99999)

    async def test_message_id_not_found(self, db_session: Session) -> None:
        """message_id 不存在 → MessageNotFoundError（路由层转 404）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        with pytest.raises(MessageNotFoundError):
            await chat_service.regenerate_chat(db_session, conv.id, message_id=99999)

    async def test_message_id_of_other_conversation_404(self, db_session: Session) -> None:
        """message_id 属于其他对话 → MessageNotFoundError（不得跨会话截断）"""
        char_id = _create_character(db_session)
        conv_a = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv_a.id, ("user", "问A"), ("assistant", "答A"))
        conv_b = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv_b.id, ("user", "问B"), ("assistant", "答B"))
        target_id = _message_id(db_session, conv_a.id, "答A")

        with pytest.raises(MessageNotFoundError):
            await chat_service.regenerate_chat(db_session, conv_b.id, message_id=target_id)

    async def test_target_is_user_400(self, db_session: Session) -> None:
        """target 非 assistant（user）→ InvalidRegenerateTargetError（路由层转 400）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        target_id = _message_id(db_session, conv.id, "问")

        with pytest.raises(InvalidRegenerateTargetError):
            await chat_service.regenerate_chat(db_session, conv.id, message_id=target_id)

    async def test_no_assistant_at_all_400(self, db_session: Session) -> None:
        """缺省 message_id 但对话没有 assistant 消息 → InvalidRegenerateTargetError"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "只有问题"))

        with pytest.raises(InvalidRegenerateTargetError):
            await chat_service.regenerate_chat(db_session, conv.id)

    async def test_no_trigger_user_after_truncation_400(self, db_session: Session) -> None:
        """截断后无 user（仅 greeting）→ InvalidRegenerateTargetError（无触发源）"""
        char_id = _create_character(db_session, first_mes="欢迎！")
        conv = _create_conversation(db_session, character_id=char_id)
        # 仅 greeting 一条 assistant 消息（无 user）
        message_service.auto_insert_greeting(db_session, conv.id, user_name="User")

        with pytest.raises(InvalidRegenerateTargetError):
            await chat_service.regenerate_chat(db_session, conv.id)

    async def test_prepare_chat_reuse_no_ghost_regression(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """防回归：重生成不产生幽灵重复 user（复用 prepare_chat 的假设性回归锁）"""
        fake = _FakeProvider(reply="新的回复")
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session, first_mes="")  # 无 greeting 隔离
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "原始消息"), ("assistant", "原始回复"))
        _patch_factory(monkeypatch, fake)

        await chat_service.regenerate_chat(db_session, conv.id)

        users = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv.id, Message.role == Role.USER)
            .all()
        )
        assert len(users) == 1
        assert users[0].content == "原始消息"


# ── 5. 端点契约 ──


class TestRegenerateRoute:
    """POST /api/conversations/{id}/regenerate：响应同构 + 领域异常上抛"""

    async def test_success_no_body(self, db_session: Session, monkeypatch: pytest.MonkeyPatch) -> None:
        """无 body → 缺省末条 assistant，返回 ChatResponse 同构字段"""
        fake = _FakeProvider(reply="路由重生成")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        _patch_factory(monkeypatch, fake)

        resp = await conversations_route.regenerate(conv.id, None, db_session)

        assert isinstance(resp, ChatResponse)
        assert resp.reply == "路由重生成"
        assert resp.conversation_id == conv.id
        assert isinstance(resp.message_id, int)

    async def test_success_with_message_id_body(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """带 body message_id → 以指定 assistant 为 target"""
        fake = _FakeProvider(reply="路由重写")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        _patch_factory(monkeypatch, fake)
        target_id = _message_id(db_session, conv.id, "答")

        body = RegenerateRequest(message_id=target_id)
        resp = await conversations_route.regenerate(conv.id, body, db_session)

        assert resp.reply == "路由重写"
        # 截断：target(答) 被删，仅剩 问 + 新回复
        assert _contents(db_session, conv.id) == ["问", "路由重写"]

    async def test_conversation_not_found_404(self, db_session: Session) -> None:
        """对话不存在 → 上抛 ConversationNotFoundError（统一 handler 转 404）"""
        with pytest.raises(ConversationNotFoundError):
            await conversations_route.regenerate(99999, None, db_session)

    async def test_regenerate_request_schema_defaults(self) -> None:
        """请求体 schema：message_id 缺省为 None（=末条 assistant）"""
        req = RegenerateRequest()
        assert req.message_id is None
        req2 = RegenerateRequest(message_id=42)
        assert req2.message_id == 42