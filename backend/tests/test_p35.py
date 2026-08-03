"""
P3.5 单元测试 — 对话过程交互增强

覆盖：
    1. 标题规则截断纯函数 truncate_title
    2. 创建对话默认标题（与 {角色名} 的对话）
    3. 首条 user 消息替换占位默认标题
    4. 流式聊天客户端断开 → 停止生成并保存部分内容（stub provider + fake request）
    5. 流式聊天正常完成 / LLM 错误 / ClientDisconnect

依赖：pytest + SQLite 内存库（StaticPool 保证同一连接，避免 threading 限制）。
"""

from __future__ import annotations

import asyncio
import json

from starlette.requests import ClientDisconnect

from backend.app.models import Conversation, Message
from backend.app.models.message import Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.message import ChatRequest
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import chat as chat_service
from backend.app.services import setting as setting_service
from backend.app.api.routes import chat as chat_route

__all__: list[str] = []


# ── 测试基础设施 ──


def _create_character(db_session, name: str = "测试角色") -> int:
    """落库一个无 greeting 的角色，返回 id"""
    from backend.app.models.character import Character

    char = Character(
        name=name,
        personality="冷静、睿智",
        first_mes="",  # 关闭 greeting 自动插入，简化断言
        temperature=0.7,
    )
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char.id


# ── 1. truncate_title 纯函数 ──


class TestTruncateTitle:
    def test_short_text_unchanged(self) -> None:
        assert conversation_service.truncate_title("你好世界") == "你好世界"

    def test_exactly_max_len_no_ellipsis(self) -> None:
        text = "a" * 20
        assert conversation_service.truncate_title(text) == text

    def test_long_text_truncated_with_ellipsis(self) -> None:
        text = "这" * 25
        result = conversation_service.truncate_title(text)
        assert result == "这" * 20 + "…"
        assert len(result) == 21

    def test_collapse_whitespace(self) -> None:
        assert conversation_service.truncate_title("  a   b\n\tc  ") == "a b c"

    def test_markdown_not_stripped(self) -> None:
        # 不剥离 Markdown：长文本原样截断字符，语法符号保留
        text = "**加粗** 和 `代码` 一起" * 3
        result = conversation_service.truncate_title(text)
        assert "**" in result
        assert result.endswith("…")

    def test_empty_text(self) -> None:
        assert conversation_service.truncate_title("") == ""
        assert conversation_service.truncate_title("   ") == ""

    def test_custom_max_len(self) -> None:
        assert conversation_service.truncate_title("123456", max_len=3) == "123…"


# ── 2/3. 默认标题 + 首条 user 消息替换 ──


class TestAutoTitle:
    def test_default_title_uses_character_name(self, db_session) -> None:
        char_id = _create_character(db_session, name="艾莉")
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char_id)
        )
        assert conv.title == "与 艾莉 的对话"

    def test_explicit_title_preserved(self, db_session) -> None:
        char_id = _create_character(db_session)
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char_id, title="自定义标题")
        )
        assert conv.title == "自定义标题"

    def test_first_user_message_replaces_placeholder(self, db_session) -> None:
        char_id = _create_character(db_session, name="艾莉")
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char_id)
        )
        content = "  这就是  第一条很长很长的消息啊  "
        message_service.create_message(db_session, conv.id, Role.USER, content)
        db_session.refresh(conv)
        assert conv.title == conversation_service.truncate_title(content)
        assert conv.title != "与 艾莉 的对话"

    def test_second_user_message_keeps_title(self, db_session) -> None:
        char_id = _create_character(db_session)
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char_id)
        )
        message_service.create_message(db_session, conv.id, Role.USER, "第一条")
        first_title = conv.title
        message_service.create_message(db_session, conv.id, Role.USER, "第二条")
        db_session.refresh(conv)
        assert conv.title == first_title

    def test_explicit_title_not_overwritten(self, db_session) -> None:
        char_id = _create_character(db_session)
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char_id, title="我起的标题")
        )
        message_service.create_message(db_session, conv.id, Role.USER, "第一条消息")
        db_session.refresh(conv)
        assert conv.title == "我起的标题"

    def test_assistant_message_does_not_touch_title(self, db_session) -> None:
        char_id = _create_character(db_session, name="艾莉")
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char_id)
        )
        message_service.create_message(db_session, conv.id, Role.ASSISTANT, "开场白")
        db_session.refresh(conv)
        assert conv.title == "与 艾莉 的对话"  # 仍是占位默认值

    def test_default_conversation_title_helper(self, db_session) -> None:
        char_id = _create_character(db_session, name="艾莉")
        conv = conversation_service.create_conversation(
            db_session, ConversationCreate(character_id=char_id)
        )
        assert conversation_service.default_conversation_title(
            db_session, conv.id
        ) == "与 艾莉 的对话"
        assert conversation_service.default_conversation_title(
            db_session, 99999
        ) == "新对话"


# ── 4/5. 流式停止生成 ──


class _StubProvider:
    """桩 Provider：逐 token 产出；可选在指定 token 后抛 ClientDisconnect"""

    provider_name = "stub"

    def __init__(
        self,
        tokens: list[str],
        raise_disconnect_after: int | None = None,
    ) -> None:
        self.tokens = tokens
        self.raise_disconnect_after = raise_disconnect_after

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ):
        for i, tok in enumerate(self.tokens):
            yield tok
            if (
                self.raise_disconnect_after is not None
                and i == self.raise_disconnect_after
            ):
                raise ClientDisconnect()


class _FakeFactory:
    """替代 LLMFactory.get_provider 的工厂"""

    @staticmethod
    def get_provider(provider: str, api_key: str) -> _StubProvider:
        return _StubProvider(["你好", "世界"])


class _FakeRequest:
    """模拟 Starlette Request：is_disconnected 在第 N 次调用后返回 True"""

    def __init__(self, disconnect_call: int | None = None) -> None:
        self._calls = 0
        self._disconnect_call = disconnect_call

    async def is_disconnected(self) -> bool:
        self._calls += 1
        return (
            self._disconnect_call is not None
            and self._calls > self._disconnect_call
        )


def _make_stream_context(db_session, monkeypatch, tokens, **kwargs):
    """组装一次流式聊天所需的环境，返回 (response, request)"""
    char_id = _create_character(db_session, name="艾莉")
    conv = conversation_service.create_conversation(
        db_session,
        ConversationCreate(
            character_id=char_id,
            model_provider="claude",
            model_name="claude-test",
        ),
    )
    req = ChatRequest(conversation_id=conv.id, content="你好")

    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")
    monkeypatch.setattr(
        chat_service,
        "LLMFactory",
        type("_FakeLLMFactory", (), {"get_provider": staticmethod(lambda p, k: _StubProvider(tokens, **kwargs))}),
    )

    response = asyncio.run(chat_route.stream_chat(req, _FakeRequest(), db_session))
    return response, conv


async def _collect(response):
    chunks = []
    async for chunk in response.body_iterator:
        chunks.append(chunk)
    return chunks


def _parse_events(chunks: list[str]) -> list[dict]:
    """将 SSE chunk 解析为事件 dict 列表（忽略非 data: 行）"""
    events = []
    for chunk in chunks:
        for line in chunk.splitlines():
            line = line.strip()
            if line.startswith("data: "):
                events.append(json.loads(line[6:]))
    return events


def _assistant_contents(db_session, conv_id: int) -> list[str]:
    rows = (
        db_session.query(Message)
        .filter(Message.conversation_id == conv_id, Message.role == Role.ASSISTANT)
        .order_by(Message.created_at.asc())
        .all()
    )
    return [row.content for row in rows]


def test_stream_completion_saves_full(db_session, monkeypatch) -> None:
    """正常完成：收到 done 事件，DB 保存完整回复"""
    response, conv = _make_stream_context(db_session, monkeypatch, ["你好", "世界"])
    chunks = asyncio.run(_collect(response))
    events = _parse_events(chunks)

    assert [e["type"] for e in events] == ["token", "token", "done"]
    assert events[0]["content"] == "你好"
    assert events[1]["content"] == "世界"
    assert isinstance(events[2]["message_id"], int)
    assert _assistant_contents(db_session, conv.id) == ["你好世界"]


def test_stream_disconnect_saves_partial(db_session, monkeypatch) -> None:
    """客户端在第 2 次 is_disconnected 检查后断开：停止生成并保存已生成部分"""
    response, conv = _make_stream_context(
        db_session, monkeypatch, ["你好", "世界"]
    )
    # 覆写 fake request：第 2 次检查起视为断开
    req = ChatRequest(conversation_id=conv.id, content="你好")
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")

    async def _run() -> list[str]:
        resp = await chat_route.stream_chat(
            req, _FakeRequest(disconnect_call=1), db_session
        )
        return await _collect(resp)

    chunks = asyncio.run(_run())
    events = _parse_events(chunks)

    # 仅收到第 1 个 token；不再发送 done；DB 保存部分内容
    assert events == [{"type": "token", "content": "你好"}]
    assert _assistant_contents(db_session, conv.id) == ["你好"]


def test_stream_disconnect_before_token_saves_nothing(db_session, monkeypatch) -> None:
    """客户端在首个 token 前断开：无事件产出，也不保存空消息"""
    response, conv = _make_stream_context(db_session, monkeypatch, ["你好", "世界"])
    req = ChatRequest(conversation_id=conv.id, content="你好")
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")

    async def _run() -> list[str]:
        resp = await chat_route.stream_chat(
            req, _FakeRequest(disconnect_call=0), db_session
        )
        return await _collect(resp)

    chunks = asyncio.run(_run())
    assert chunks == []
    assert _assistant_contents(db_session, conv.id) == []


def test_stream_client_disconnect_raised_saves_partial(db_session, monkeypatch) -> None:
    """发送过程中被中断（ClientDisconnect）：尽力保存已生成部分"""
    response, conv = _make_stream_context(
        db_session,
        monkeypatch,
        ["你好", "世界"],
        raise_disconnect_after=0,  # 产出第 1 个 token 后抛 ClientDisconnect
    )
    req = ChatRequest(conversation_id=conv.id, content="你好")
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")

    async def _run() -> list[str]:
        resp = await chat_route.stream_chat(req, _FakeRequest(), db_session)
        return await _collect(resp)

    chunks = asyncio.run(_run())
    events = _parse_events(chunks)

    assert events == [{"type": "token", "content": "你好"}]
    assert _assistant_contents(db_session, conv.id) == ["你好"]


def test_stream_llm_error_emits_error_event(db_session, monkeypatch) -> None:
    """LLM 异常：向客户端发送 error 事件，不落库"""

    class _ErrorProvider(_StubProvider):
        async def stream_generate(self, messages, temperature=0.7, max_tokens=2048, model=None):
            from backend.app.services.llm.errors import LLMError

            if False:  # 使函数成为 async generator（首轮即抛错）
                yield ""
            raise LLMError("boom")

    char_id = _create_character(db_session, name="艾莉")
    conv = conversation_service.create_conversation(
        db_session,
        ConversationCreate(character_id=char_id, model_provider="claude", model_name="claude-test"),
    )
    req = ChatRequest(conversation_id=conv.id, content="你好")
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")
    monkeypatch.setattr(
        chat_service,
        "LLMFactory",
        type("_FakeLLMFactory", (), {"get_provider": staticmethod(lambda p, k: _ErrorProvider([]))}),
    )

    async def _run() -> list[str]:
        resp = await chat_route.stream_chat(req, _FakeRequest(), db_session)
        return await _collect(resp)

    chunks = asyncio.run(_run())
    events = _parse_events(chunks)

    assert len(events) == 1
    assert events[0]["type"] == "error"
    assert _assistant_contents(db_session, conv.id) == []
