"""
T6 — 回合末概率触发 CG 自动解锁链契约锁

覆盖：
    1. _maybe_auto_cg 概率判定：0 关闭 / 100 必触发 / 概率未命中零变更
    2. 候选池过滤：解锁项排除、weight=0 排除、空池 no-op
    3. 锚定语义：unlock 后 cg.message_id = assistant_message_id、
       cg.conversation_id = conversation_id
    4. 隔离：触发链内 DB 异常 → logger.exception 且对话响应正常返回
    5. 双路径接线：complete_chat 与 stream_reply 均调用 _maybe_auto_cg
    6. settings 键：cg_auto_trigger_probability 读/写/默认值/白名单

依赖：pytest + SQLite 内存库（conftest.db_session）+ monkeypatch
random.randint 与 pick_cg_by_weight 随机源。
"""

from __future__ import annotations

import random

import pytest

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.cg_image import CgImage
from backend.app.models.message import Message, Role
from backend.app.models.mods import Mod
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.message import ChatRequest
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.llm import resolver as llm_resolver

__all__: list[str] = []


# ── 测试基础设施 ──


def _create_character(db_session, name: str = "CG角色", temperature: float = 0.7) -> int:
    """落库一个无 greeting 的角色，返回 id"""
    char = Character(
        name=name,
        personality="冷静、睿智",
        first_mes="",
        temperature=temperature,
    )
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char.id


def _create_conversation(db_session, character_id: int) -> int:
    """落库一个绑定角色的对话，返回 conversation id"""
    conv = conversation_service.create_conversation(
        db_session,
        ConversationCreate(character_id=character_id),
    )
    return conv.id


def _add_cg(db_session, character_id: int, *, weight: int = 100, unlocked: bool = False) -> int:
    """入库一张 CG 图，返回其 id"""
    cg = CgImage(
        character_id=character_id,
        url="http://example.com/cg.png",
        weight=weight,
        unlocked=unlocked,
    )
    db_session.add(cg)
    db_session.commit()
    db_session.refresh(cg)
    return cg.id


def _patch_api_key(monkeypatch) -> None:
    """让 setting_service.api_key 恒返回测试 Key"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")


class _FakeProvider:
    """固定回复的假 Provider"""

    def __init__(self, reply: str = "这是测试回复") -> None:
        self.reply = reply
        self.calls: list[tuple] = []

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        self.calls.append((messages, temperature, max_tokens, model))
        return self.reply

    async def stream_generate(self, messages, temperature=0.7, max_tokens=2048, model=None):
        yield self.reply


def _patch_factory(monkeypatch, provider: _FakeProvider) -> None:
    """让 llm_resolver.LLMFactory.get_provider 返回指定假 Provider"""
    class _FakeLLMFactory:
        def get_provider(self, name: str, api_key: str, base_url: str | None = None) -> _FakeProvider:
            return provider
    monkeypatch.setattr(llm_resolver, "LLMFactory", _FakeLLMFactory)


# ── 1. settings 键契约 ──


class TestCGAutoTriggerSetting:
    """cg_auto_trigger_probability getter：默认/读/写/钳制/白名单"""

    def test_default_returns_zero(self, db_session) -> None:
        """键缺省 → getter 返回默认 0（关闭）"""
        assert setting_service.cg_auto_trigger_probability(db_session) == 0

    def test_read_write_roundtrip(self, db_session) -> None:
        """写入 100 → 读取为 100"""
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        assert setting_service.cg_auto_trigger_probability(db_session) == 100

    def test_clamp_above_100(self, db_session) -> None:
        """值 200 → 钳制到 100"""
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "200"})
        assert setting_service.cg_auto_trigger_probability(db_session) == 100

    def test_clamp_below_zero(self, db_session) -> None:
        """值 -1 → 钳制到 0"""
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "-1"})
        assert setting_service.cg_auto_trigger_probability(db_session) == 0

    def test_non_numeric_returns_zero(self, db_session) -> None:
        """非数字值 → 返回默认 0"""
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "abc"})
        assert setting_service.cg_auto_trigger_probability(db_session) == 0

    def test_allowed_key_present_in_get_all(self, db_session) -> None:
        """cg_auto_trigger_probability 出现在 get_all 白名单中"""
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "50"})
        all_settings = setting_service.get_all(db_session)
        assert "cg_auto_trigger_probability" in all_settings
        assert all_settings["cg_auto_trigger_probability"] == "50"


# ── 2. _maybe_auto_cg 概率判定 ──


class TestMaybeAutoCGProbability:
    """概率判定契约锁：0 关闭 / 100 必触发 / 未命中零变更"""

    @pytest.mark.asyncio
    async def test_probability_zero_no_op(
        self, db_session, monkeypatch
    ) -> None:
        """概率 0 → 不触发，CG 表零写（无论历史深度）"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)

        cg = db_session.query(CgImage).filter(CgImage.id == cg_id).first()
        assert cg is not None
        assert cg.unlocked is False
        assert cg.message_id is None
        assert cg.conversation_id is None

    @pytest.mark.asyncio
    async def test_probability_hundred_triggers(
        self, db_session, monkeypatch
    ) -> None:
        """概率 100 → 必解锁一张锁定且 weight>0 的 CG；锚定到本回合助手消息"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        # 用 monkeypatch.random.randint 强制命中
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)
        saved = message_service.get_messages(db_session, conv_id)[-1]
        assert saved.role.name == "ASSISTANT"

        cg = db_session.query(CgImage).filter(CgImage.id == cg_id).first()
        assert cg is not None
        assert cg.unlocked is True
        assert cg.message_id == saved.id
        assert cg.conversation_id == conv_id

    @pytest.mark.asyncio
    async def test_unlock_uses_unlock_cg_seam(
        self, db_session, monkeypatch
    ) -> None:
        """SP2/A1 防复发：解锁经 gallery.unlock_cg 单一 seam（非内联 unlocked=True）"""
        import backend.app.services.gallery as gallery_module

        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        real_unlock = gallery_module.unlock_cg
        calls: list[int] = []

        def _spy(db, cg_id_arg: int):
            calls.append(cg_id_arg)
            return real_unlock(db, cg_id_arg)

        monkeypatch.setattr(gallery_module, "unlock_cg", _spy)

        await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )

        assert calls == [cg_id]

    @pytest.mark.asyncio
    async def test_probability_miss_no_change(
        self, db_session, monkeypatch
    ) -> None:
        """概率未命中 → CG 表零变更（monkeypatch random.randint 复现）"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        # randint 始终返回 101（> prob），强制未命中
        monkeypatch.setattr(random, "randint", lambda a, b: 101)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)

        cg = db_session.query(CgImage).filter(CgImage.id == cg_id).first()
        assert cg is not None
        assert cg.unlocked is False
        assert cg.message_id is None

    @pytest.mark.asyncio
    async def test_isolation_db_error_does_not_break_response(
        self, db_session, monkeypatch
    ) -> None:
        """触发链内 DB 异常 → logger.exception 记录且对话响应正常返回"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        # 让 unlock_cg 抛异常：解锁后 commit 失败
        def _boom(db, cg_id: int):
            raise RuntimeError("db boom")
        monkeypatch.setattr(
            "backend.app.services.gallery.unlock_cg", _boom
        )
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)
        assert resp.reply == "这是测试回复"


# ── 3. 候选池过滤 ──


class TestMaybeAutoCGPoolFiltering:
    """候选池过滤契约锁：解锁项排除 / weight=0 排除 / 空池 no-op"""

    @pytest.mark.asyncio
    async def test_unlocked_cg_excluded(
        self, db_session, monkeypatch
    ) -> None:
        """已解锁的 CG 不进候选池 → 触发时跳过（池空 no-op）"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100, unlocked=True)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)

        cg = db_session.query(CgImage).filter(CgImage.id == cg_id).first()
        assert cg.unlocked is True

    @pytest.mark.asyncio
    async def test_zero_weight_cg_excluded(
        self, db_session, monkeypatch
    ) -> None:
        """weight=0 的锁定 CG 不进候选池 → 永不解锁"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=0)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)

        cg = db_session.query(CgImage).filter(CgImage.id == cg_id).first()
        assert cg.unlocked is False
        assert cg.message_id is None

    @pytest.mark.asyncio
    async def test_empty_pool_no_op(
        self, db_session, monkeypatch
    ) -> None:
        """池空（全解锁或全 weight=0）→ no-op，不抛警告，响应正常"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=0)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)


# ── 4. 双路径接线 ──


class TestMaybeAutoCGWiring:
    """complete_chat 与 stream_reply 双路径均接线"""

    @pytest.mark.asyncio
    async def test_complete_chat_wired(
        self, db_session, monkeypatch
    ) -> None:
        """complete_chat 路径：助手消息落库后 _maybe_auto_cg 被调用"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        resp = await chat_service.complete_chat(
            db_session, ChatRequest(conversation_id=conv_id, content="你好")
        )
        assert isinstance(resp, chat_service.ChatResponse)
        saved = message_service.get_messages(db_session, conv_id)[-1]
        assert saved.role.name == "ASSISTANT"

        cg = db_session.query(CgImage).filter(CgImage.id == cg_id).first()
        assert cg is not None and cg.unlocked is True
        assert cg.message_id == saved.id

    def test_stream_reply_wired(
        self, db_session, monkeypatch
    ) -> None:
        """stream_reply 路径：助手消息落库后 _maybe_auto_cg 被调用（done 帧路径）"""
        import asyncio

        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session)
        conv_id = _create_conversation(db_session, char_id)
        cg_id = _add_cg(db_session, char_id, weight=100)
        setting_service.set_many(db_session, {"cg_auto_trigger_probability": "100"})
        monkeypatch.setattr(random, "randint", lambda a, b: 1)
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)

        ctx = chat_service.ChatContext(
            conversation=db_session.query(Conversation).filter(Conversation.id == conv_id).first(),
            temperature=0.7,
            messages=[{"role": "user", "content": "你好"}],
            provider=fake,
        )

        async def _is_disconnected() -> bool:
            return False

        async def _run() -> list[dict]:
            return [
                event
                async for event in chat_service.stream_reply(
                    db_session, conv_id, ctx, is_disconnected=_is_disconnected
                )
            ]

        events = asyncio.run(_run())

        assert any(e["type"] == "done" for e in events)
        done_event = next(e for e in events if e["type"] == "done")
        assert done_event["message_id"] is not None

        cg = db_session.query(CgImage).filter(CgImage.id == cg_id).first()
        assert cg is not None and cg.unlocked is True
        assert cg.message_id == done_event["message_id"]
