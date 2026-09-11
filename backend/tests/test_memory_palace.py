"""
记忆宫殿契约锁（WL-5，spec §WL-5）

锁定语义：
1. should_summarize 阈值矩阵（每 N 轮=2N 条消息 或 字符数达标）
2. summarize_turn 对 LLM 输出严格 JSON 解析（剥围栏）；非法 JSON / 缺字段 /
   LLM 异常 → 降级返回 None 且不抛（错误日志）
3. persist_drafts：keys 空跳过；同 keys+同 content 去重不重复入库；返回计数
4. 归纳失败对话主流程不受影响（异常隔离：summarize_turn 不向上抛）
5. auto 条目 position='world'、depth=20、source='auto' 固定（契约锁）
"""

from __future__ import annotations

import logging

import pytest
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.lorebook import LorebookEntry
from backend.app.services.memory_palace import (
    AUTO_DEPTH,
    AUTO_POSITION,
    MEMORY_DRAFT_SCHEMA,
    MemoryDraft,
    persist_drafts,
    should_summarize,
    summarize_turn,
)

__all__: list[str] = []


# ════════════════════════════════════════════════════════════════
# 一、阈值矩阵
# ════════════════════════════════════════════════════════════════


def test_should_summarize_matrix() -> None:
    """轮数达标（每轮 2 条消息）/ 字符数达标 / 均不达标"""
    # 轮数达标：every_rounds=1 → 2 条消息即归纳
    assert should_summarize(2, 10, every_rounds=1, char_threshold=10000) is True
    assert should_summarize(3, 10, every_rounds=1, char_threshold=10000) is True
    # 字符数达标：参考阈值
    assert should_summarize(0, 10001, every_rounds=5, char_threshold=10000) is True
    assert should_summarize(0, 10000, every_rounds=5, char_threshold=10000) is True  # 等于阈值
    # 均不达标
    assert should_summarize(1, 10, every_rounds=1, char_threshold=10000) is False
    assert should_summarize(0, 9, every_rounds=2, char_threshold=10) is False
    # every_rounds=0（每回合）→ 恒真（0 消息也归纳？不——message_count>=0 恒真）
    assert should_summarize(0, 0, every_rounds=0, char_threshold=1) is True


# ════════════════════════════════════════════════════════════════
# 二、summarize_turn JSON 解析与降级
# ════════════════════════════════════════════════════════════════


class _FakeProvider:
    """可配置回复/异常的假 Provider（async generate）"""

    def __init__(self, reply: str = "", error: Exception | None = None) -> None:
        self.reply = reply
        self.error = error
        self.calls: list[tuple] = []

    async def generate(self, messages, temperature=0.7, max_tokens=2048, model=None) -> str:
        self.calls.append((messages, temperature, max_tokens, model))
        if self.error is not None:
            raise self.error
        return self.reply


def _history(*contents: str) -> list[object]:
    """历史消息（role/content 双属性假对象）"""
    from types import SimpleNamespace

    out = []
    for i, text in enumerate(contents):
        out.append(SimpleNamespace(role="user" if i % 2 == 0 else "assistant", content=text))
    return out


async def _summarize(provider) -> MemoryDraft | None:
    return await summarize_turn(
        _history("第一轮", "回复一", "第二轮", "回复二"),
        provider=provider,
        model="test-model",
        user_name="小明",
        char_name="莉莉",
    )


def test_summarize_valid_json() -> None:
    """合法 JSON（含 ```json 围栏）→ MemoryDraft 三字段齐全"""
    provider = _FakeProvider(reply='```json\n{"title": "酒馆之约", "keys": ["酒馆", "莉莉"], "content": "他们约在酒馆见面。"}\n```')
    draft = _loop(_summarize(provider))
    assert draft is not None
    assert draft.title == "酒馆之约"
    assert draft.keys == ["酒馆", "莉莉"]
    assert draft.content == "他们约在酒馆见面。"
    # model 透传给 generate
    assert provider.calls[0][3] == "test-model"


def test_summarize_invalid_json_degrades() -> None:
    """非法 JSON → None 且不抛（记错误日志）"""
    provider = _FakeProvider(reply="抱歉，我无法总结。")
    draft = _loop(_summarize(provider))  # 不应抛
    assert draft is None


def test_summarize_missing_keys_degrades(caplog) -> None:
    """JSON 缺 keys/字段 → None（降级不抛）"""
    provider = _FakeProvider(reply='{"title": "无关键词"}')
    with caplog.at_level(logging.WARNING):
        draft = _loop(_summarize(provider))
    assert draft is None
    assert any("记忆宫殿" in r.message for r in caplog.records)  # 错误日志


def test_summarize_llm_error_degrades(caplog) -> None:
    """LLM 异常 → None 不抛（异常隔离：对话主流程不受影响）"""
    class _LLMError(Exception):
        pass

    provider = _FakeProvider(error=_LLMError("超时"))
    with caplog.at_level(logging.WARNING):
        draft = _loop(_summarize(provider))
    assert draft is None


# ════════════════════════════════════════════════════════════════
# 三、persist_drafts
# ════════════════════════════════════════════════════════════════


def _create_character(db_session: Session) -> Character:
    char = Character(name="记忆角色", personality="测试", first_mes="")
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char


def test_persist_skips_empty_keys(db_session: Session) -> None:
    """keys 空 → 跳过（不落库）"""
    char = _create_character(db_session)
    n = persist_drafts(db_session, char.id, [MemoryDraft(title="无关键词", keys=[], content="c")])
    assert n == 0
    assert db_session.query(LorebookEntry).count() == 0


def test_persist_dedup_and_position(db_session: Session) -> None:
    """去重：同 keys+同 content 二次调用不重复；position/depth/source 固定"""
    char = _create_character(db_session)
    drafts = [MemoryDraft(title="酒馆", keys=["酒馆"], content="酒馆的老板是莉莉。")]
    assert persist_drafts(db_session, char.id, drafts) == 1
    assert persist_drafts(db_session, char.id, drafts) == 0  # 去重

    entries = db_session.query(LorebookEntry).all()
    assert len(entries) == 1
    e = entries[0]
    assert e.source == "auto"
    assert e.position == AUTO_POSITION == "world"
    assert e.depth == AUTO_DEPTH == 20
    assert e.keys == ["酒馆"]
    assert e.title == "酒馆"
    assert e.character_id == char.id

    # 不同 content 同 keys → 允许入库（仅完全相同才去重）
    assert persist_drafts(db_session, char.id, [MemoryDraft(title="酒馆2", keys=["酒馆"], content="不同内容")]) == 1


def test_persist_multiple_and_dedup(db_session: Session) -> None:
    """多条：去重后的净新增计数"""
    char = _create_character(db_session)
    drafts = [
        MemoryDraft(title="A", keys=["a"], content="甲"),
        MemoryDraft(title="B", keys=["b"], content="乙"),
        MemoryDraft(title="A 重复", keys=["a"], content="甲"),  # 与第一条重复
    ]
    assert persist_drafts(db_session, char.id, drafts) == 2


# ════════════════════════════════════════════════════════════════
# 四、schema 契约
# ════════════════════════════════════════════════════════════════


def test_memory_draft_schema_fields() -> None:
    """MEMORY_DRAFT_SCHEMA 恰含 title/keys/content 三键（prompt 组装与解析共用）"""
    assert set(MEMORY_DRAFT_SCHEMA.keys()) == {"title", "keys", "content"}


# ════════════════════════════════════════════════════════════════
# 工具
# ════════════════════════════════════════════════════════════════


def _loop(awaitable):
    """同步测试里跑协程"""
    import asyncio
    return asyncio.run(awaitable)

# ════════════════════════════════════════════════════════════════
# 五、chat 集成（完整回合后触发 / 开关 / 失败隔离）
# ════════════════════════════════════════════════════════════════

import asyncio as _asyncio

from backend.app.models.message import Role as _Role
from backend.app.schemas.conversation import ConversationCreate as _ConvCreate
from backend.app.schemas.message import ChatRequest as _ChatRequest
from backend.app.services import chat as _chat_service
from backend.app.services import conversation as _conv_service
from backend.app.services import lorebook as _lorebook_service
from backend.app.services import message as _message_service
from backend.app.services import setting as _setting_service
from backend.app.services.llm import resolver as _llm_resolver


class _ScriptedProvider(_FakeProvider):
    """按调用顺序返回预置回复（首条=聊天回复，次条=归纳 JSON）"""

    def __init__(self, replies: list[str]) -> None:
        super().__init__()
        self.replies = list(replies)

    async def generate(self, messages, temperature=0.7, max_tokens=2048, model=None) -> str:
        self.calls.append((messages, temperature, max_tokens, model))
        return self.replies.pop(0) if self.replies else ""


class _FakeFactory:
    def __init__(self, provider) -> None:
        self.provider = provider

    def get_provider(self, name, api_key, base_url=None):
        return self.provider


def _patch_chat_env(monkeypatch, provider) -> None:
    monkeypatch.setattr(_setting_service, "api_key", lambda db, provider: "test-key")
    monkeypatch.setattr(_llm_resolver, "LLMFactory", _FakeFactory(provider))


def _setup_conv(db_session, monkeypatch) -> tuple[Session, int, int]:
    char = _create_character(db_session)
    conv = _conv_service.create_conversation(db_session, _ConvCreate(character_id=char.id))
    return db_session, conv.id, char.id


def test_complete_chat_triggers_memory_palace(db_session, monkeypatch) -> None:
    """记忆增强开 + 阈值达标 → 完整回合后自动归纳入库（source=auto）"""
    db, conv_id, char_id = _setup_conv(db_session, monkeypatch)
    provider = _ScriptedProvider(["这是回复", '{"title": "酒馆", "keys": ["酒馆"], "content": "约在酒馆见面。"}'])
    _patch_chat_env(monkeypatch, provider)
    monkeypatch.setattr(_setting_service, "memory_palace_enabled", lambda db: True)
    monkeypatch.setattr(_setting_service, "memory_palace_every_rounds", lambda db: 1)

    resp = _asyncio.run(_chat_service.complete_chat(db, _ChatRequest(conversation_id=conv_id, content="我们去酒馆吧")))
    assert resp.reply == "这是回复"

    entries = _lorebook_service.list_entries(db, char_id)
    assert any(e.source == "auto" and e.keys == ["酒馆"] for e in entries)
    auto = [e for e in entries if e.source == "auto"][0]
    assert auto.position == "world" and auto.depth == 20


def test_memory_palace_disabled_no_entry(db_session, monkeypatch) -> None:
    """开关关 → 回合正常完成，不产生 auto 条目"""
    db, conv_id, char_id = _setup_conv(db_session, monkeypatch)
    provider = _ScriptedProvider(["这是回复"])
    _patch_chat_env(monkeypatch, provider)
    monkeypatch.setattr(_setting_service, "memory_palace_enabled", lambda db: False)

    resp = _asyncio.run(_chat_service.complete_chat(db, _ChatRequest(conversation_id=conv_id, content="你好")))
    assert resp.reply == "这是回复"
    assert _lorebook_service.list_entries(db, char_id) == []


def test_memory_palace_failure_does_not_break_chat(db_session, monkeypatch, caplog) -> None:
    """归纳 JSON 非法 → 回合正常完成（异常隔离），无 auto 条目且不抛"""
    db, conv_id, char_id = _setup_conv(db_session, monkeypatch)
    provider = _ScriptedProvider(["这是回复", "无法总结"])
    _patch_chat_env(monkeypatch, provider)
    monkeypatch.setattr(_setting_service, "memory_palace_enabled", lambda db: True)
    monkeypatch.setattr(_setting_service, "memory_palace_every_rounds", lambda db: 1)

    resp = _asyncio.run(_chat_service.complete_chat(db, _ChatRequest(conversation_id=conv_id, content="你好")))
    assert resp.reply == "这是回复"  # 主流程不受影响
    assert _lorebook_service.list_entries(db, char_id) == []
    assert len(_message_service.get_messages(db, conv_id)) == 2  # user + assistant（角色无 greeting）


def test_memory_palace_trigger_exception_isolated(db_session, monkeypatch, caplog) -> None:
    """summarize_turn 之外意外（DB 异常）→ 主流程不受影响（maybe_memory_palace 外层隔离）"""
    db, conv_id, char_id = _setup_conv(db_session, monkeypatch)
    provider = _ScriptedProvider(["这是回复"])
    _patch_chat_env(monkeypatch, provider)
    monkeypatch.setattr(_setting_service, "memory_palace_enabled", lambda db: True)
    monkeypatch.setattr(_setting_service, "memory_palace_every_rounds", lambda db: 1)

    # summarize_turn 抛意外（provider 无脚本回复 → 返回空串 → JSON 解析失败走 None）；
    # 此处直接让 should_summarize 抛异常验证外层兜底
    monkeypatch.setattr(
        _setting_service, "memory_palace_char_threshold", lambda db: (_ for _ in ()).throw(RuntimeError("boom"))
    )
    resp = _asyncio.run(_chat_service.complete_chat(db, _ChatRequest(conversation_id=conv_id, content="你好")))
    assert resp.reply == "这是回复"  # 记忆触发层的意外不影响回合


# ════════════════════════════════════════════════════════════════
# 六、期末审核修复锁（Falsify / Spec）
# ════════════════════════════════════════════════════════════════


def test_title_truncated_to_200(db_session) -> None:
    """LLM 超长 title 截断到 200（Falsify 修复：防 list 路由 response_model 500）"""
    provider = _FakeProvider(reply='{"title": "' + "很" * 300 + '", "keys": ["酒馆"], "content": "内容"}')
    draft = _loop(_summarize(provider))
    assert draft is not None
    assert len(draft.title) == 200

    char = _create_character(db_session)
    assert persist_drafts(db_session, char.id, [draft]) == 1
    entry = db_session.query(LorebookEntry).first()
    assert len(entry.title) == 200  # 入库即截断，路由序列化不 500


def test_every_rounds_rhythm_incremental(db_session, monkeypatch) -> None:
    """每 N 轮节奏（F1 修复）：增量计数——N=2 时每两回合归纳一次，非累计恒触发"""
    db, conv_id, char_id = _setup_conv(db_session, monkeypatch)
    # 序列：回合1回复、回合2回复、回合2后归纳 JSON
    provider = _ScriptedProvider([
        "回复一", "回复二",
        '{"title": "要点", "keys": ["酒馆"], "content": "约在酒馆。"}',
    ])
    _patch_chat_env(monkeypatch, provider)
    monkeypatch.setattr(_setting_service, "memory_palace_enabled", lambda db: True)
    monkeypatch.setattr(_setting_service, "memory_palace_every_rounds", lambda db: 2)

    _asyncio.run(_chat_service.complete_chat(db, _ChatRequest(conversation_id=conv_id, content="第一轮")))
    # 回合1后：增量 2 < 4 → 不归纳（provider 只被调 1 次=聊天回复）
    assert len(provider.calls) == 1
    assert _lorebook_service.list_entries(db, char_id) == []

    _asyncio.run(_chat_service.complete_chat(db, _ChatRequest(conversation_id=conv_id, content="第二轮")))
    # 回合2后：增量 4 ≥ 4 → 归纳（provider 再调 2 次：回复 + 归纳）
    assert len(provider.calls) == 3
    entries = _lorebook_service.list_entries(db, char_id)
    assert len(entries) == 1 and entries[0].source == "auto"
