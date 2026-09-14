"""
消息编辑重发 / 删除 —— 端点级契约锁（message-edit-resend 工单 02）

锁定语义（spec §edit-resend 端点契约）：
1. PUT /api/messages/{message_id} 请求体 {content}（min_length=1）→ 200 ChatResponse
2. DELETE /api/messages/{message_id} → 204 No Content
3. 编辑不存在消息 → 404（MessageNotFoundError）；编辑非 user → 400（InvalidEditTargetError）
4. 删除不存在消息 → 404
5. 路由不直接触碰 ORM（委托 message_service / chat_service）

依赖：pytest + SQLite 内存库（conftest.db_session）+ TestClient + 统一 domain_error_handler。
编辑重发路径用 stub provider 覆盖 LLM 生成（monkeypatch llm_resolver.LLMFactory）。
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.llm import resolver as llm_resolver

__all__: list[str] = []


# ── 测试布景辅助 ──


def _create_character(db: Session, first_mes: str = "") -> int:
    """落库一个角色（默认无 greeting），返回 id"""
    char = Character(name="路由角色", personality="测试", first_mes=first_mes)
    db.add(char)
    db.commit()
    db.refresh(char)
    return char.id


def _create_conversation(db: Session, *, character_id: int | None = None):
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
    return (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id, Message.content == content)
        .one()
        .id
    )


def _contents(db: Session, conversation_id: int) -> list[str]:
    """按 id 升序返回对话全部消息内容"""
    return [
        row.content
        for row in db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.id.asc())
        .all()
    ]


def _patch_api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    """让 setting_service.api_key 恒返回测试 Key（绕过 DB 设置表）"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")


class _FakeProvider:
    """记录 generate 调用参数的假 Provider（固定回复）"""

    def __init__(self, reply: str = "这是编辑重发回复") -> None:
        self.reply = reply

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
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


def _client(db: Session) -> TestClient:
    """构造带 messages 路由 + 统一 domain_error_handler + get_db override 的 TestClient"""
    from fastapi import FastAPI

    from backend.app.api.errors import domain_error_handler
    from backend.app.api.routes import messages as messages_route
    from backend.app.database import get_db
    from backend.app.services.exceptions import DomainError

    app = FastAPI()
    app.add_exception_handler(DomainError, domain_error_handler)
    app.include_router(messages_route.router)
    app.dependency_overrides[get_db] = lambda: db
    return TestClient(app)


# ── PUT 编辑重发 ──


class TestPutEditMessage:
    """PUT /api/messages/{message_id}：编辑重发端点契约"""

    def test_edit_returns_chat_response(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """200 返回 ChatResponse（reply/message_id/conversation_id），并物理截断后续"""
        _patch_api_key(monkeypatch)
        fake = _FakeProvider(reply="新的回复")
        _patch_factory(monkeypatch, fake)
        conv = _create_conversation(db_session)
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        target = _message_id(db_session, conv.id, "第一轮问")

        with _client(db_session) as client:
            resp = client.put(f"/api/messages/{target}", json={"content": "修正后的问题"})

        assert resp.status_code == 200
        body = resp.json()
        assert body["reply"] == "新的回复"
        assert body["conversation_id"] == conv.id
        assert isinstance(body["message_id"], int)
        # 时间线 = 编辑点(含)之前 + 1 新 assistant；后续全部截断
        assert _contents(db_session, conv.id) == ["修正后的问题", "新的回复"]

    def test_edit_nonexistent_message_404(self, db_session: Session) -> None:
        """编辑不存在消息 → 404（MessageNotFoundError）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        with _client(db_session) as client:
            resp = client.put("/api/messages/99999", json={"content": "新内容"})

        assert resp.status_code == 404

    def test_edit_non_user_message_400(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """编辑非 user（assistant）→ 400（InvalidEditTargetError 经 handler 映射）"""
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        target = _message_id(db_session, conv.id, "答")

        with _client(db_session) as client:
            resp = client.put(f"/api/messages/{target}", json={"content": "新内容"})

        assert resp.status_code == 400

    def test_edit_empty_content_422(self, db_session: Session) -> None:
        """请求体 content 为空 → 422（EditMessageRequest min_length=1 校验）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        target = _message_id(db_session, conv.id, "问")

        with _client(db_session) as client:
            resp = client.put(f"/api/messages/{target}", json={"content": ""})

        assert resp.status_code == 422


# ── DELETE 删除单条 ──


class TestDeleteMessage:
    """DELETE /api/messages/{message_id}：删除单条端点契约"""

    def test_delete_returns_204_and_removes(self, db_session: Session) -> None:
        """204 No Content，且目标消息被删除（触发 user 保留）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        target = _message_id(db_session, conv.id, "答")

        with _client(db_session) as client:
            resp = client.delete(f"/api/messages/{target}")

        assert resp.status_code == 204
        assert _contents(db_session, conv.id) == ["问"]

    def test_delete_nonexistent_message_404(self, db_session: Session) -> None:
        """删除不存在消息 → 404（MessageNotFoundError）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        with _client(db_session) as client:
            resp = client.delete("/api/messages/99999")

        assert resp.status_code == 404
