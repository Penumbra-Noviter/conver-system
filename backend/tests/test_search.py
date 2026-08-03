"""
消息搜索单测 — backend/app/services/message.py::search_messages + 路由 response_model

覆盖：
    1. 空查询 / 空白查询 / 无匹配 → 空列表
    2. 搜索结果字段契约（SearchResult：9 字段，role 为字符串、created_at 为 isoformat 串）
    3. 关键词上下文预览（短内容无省略号 / 长内容 ±50 字窗口 + 首尾省略号）
    4. 排序（created_at 倒序）与 limit 截断
    5. 路由层直连返回 list[SearchResult]（response_model 统一序列化路径）

依赖：pytest + SQLite 内存库（conftest.db_session）。
"""

from __future__ import annotations

import datetime

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, Role
from backend.app.schemas.message import SearchResult
from backend.app.api.routes import messages as messages_route
from backend.app.services import message as message_service

__all__: list[str] = []


# ── 测试数据构造（落库） ──


def _create_character(db_session, **overrides: object) -> Character:
    """落库一个角色，返回持久化实例"""
    base = {
        "name": "林墨",
        "description": "诗人",
        "personality": "浪漫",
        "scenario": "月下竹林",
        "first_mes": "欢迎。",
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
        "model_name": "claude-sonnet-4-20250514",
    }
    base.update(overrides)
    conv = Conversation(**base)
    db_session.add(conv)
    db_session.commit()
    db_session.refresh(conv)
    return conv


def _create_message(
    db_session,
    conversation_id: int,
    role: Role,
    content: str,
    created_at: datetime.datetime | None = None,
) -> Message:
    """落库一条消息；显式传 created_at 可覆盖默认时间戳"""
    msg = Message(conversation_id=conversation_id, role=role, content=content)
    db_session.add(msg)
    db_session.commit()
    db_session.refresh(msg)
    if created_at is not None:
        msg.created_at = created_at
        db_session.commit()
        db_session.refresh(msg)
    return msg


def _seed_one(db_session) -> tuple[Character, Conversation, Message]:
    """构造一角色一对话一消息，返回 (char, conv, msg)"""
    char = _create_character(db_session, avatar="data:image/png;base64,ABC")
    conv = _create_conversation(db_session, char.id)
    msg = _create_message(db_session, conv.id, Role.USER, "今天心情不错，我们聊诗歌吧")
    return char, conv, msg


# ── 1. 空查询 / 无匹配 ──


class TestEmptyAndNoMatch:
    def test_empty_query_returns_empty(self, db_session) -> None:
        """空查询 → []"""
        _seed_one(db_session)
        assert message_service.search_messages(db_session, "") == []

    def test_whitespace_query_returns_empty(self, db_session) -> None:
        """全空白查询 → []"""
        _seed_one(db_session)
        assert message_service.search_messages(db_session, "   \n ") == []

    def test_no_match_returns_empty(self, db_session) -> None:
        """无匹配关键词 → []"""
        _seed_one(db_session)
        assert message_service.search_messages(db_session, "不存在的词") == []


# ── 2. 结果字段契约 ──


class TestSearchResultContract:
    def test_fields_and_order(self, db_session) -> None:
        """SearchResult 字段名与顺序即导出契约（与 docs/api-design.md 一致）"""
        _seed_one(db_session)
        results = message_service.search_messages(db_session, "诗歌")
        assert len(results) == 1
        result = results[0]
        assert isinstance(result, SearchResult)
        assert list(result.model_dump().keys()) == [
            "message_id", "conversation_id", "conversation_title",
            "character_id", "character_name", "character_avatar",
            "role", "content_preview", "created_at",
        ]

    def test_full_values(self, db_session) -> None:
        """各字段值正确（role 为值字符串、created_at 为 isoformat 串）"""
        char, conv, msg = _seed_one(db_session)
        result = message_service.search_messages(db_session, "诗歌")[0]

        assert result.message_id == msg.id
        assert result.conversation_id == conv.id
        assert result.conversation_title == "关于诗歌的讨论"
        assert result.character_id == char.id
        assert result.character_name == "林墨"
        assert result.character_avatar == "data:image/png;base64,ABC"
        assert result.role == "user"
        assert isinstance(result.role, str)  # 枚举值字符串，非 Role 枚举
        assert result.created_at == msg.created_at.isoformat()

    def test_no_avatar_character_avatar_none(self, db_session) -> None:
        """角色无头像 → character_avatar None"""
        char = _create_character(db_session, avatar=None)
        conv = _create_conversation(db_session, char.id)
        _create_message(db_session, conv.id, Role.USER, "你好诗歌")
        result = message_service.search_messages(db_session, "诗歌")[0]
        assert result.character_avatar is None

    def test_created_at_none_when_no_timestamp(self, db_session) -> None:
        """消息无时间戳 → created_at None"""
        char = _create_character(db_session)
        conv = _create_conversation(db_session, char.id)
        msg = _create_message(db_session, conv.id, Role.USER, "诗歌内容")
        msg.created_at = None
        db_session.commit()
        result = message_service.search_messages(db_session, "诗歌")[0]
        assert result.created_at is None


# ── 3. 关键词上下文预览 ──


class TestContentPreview:
    def test_short_content_no_ellipsis(self, db_session) -> None:
        """关键词附近无截断 → 预览为完整内容（无省略号）"""
        _seed_one(db_session)
        result = message_service.search_messages(db_session, "诗歌")[0]
        assert result.content_preview == "今天心情不错，我们聊诗歌吧"
        assert result.content_preview.startswith("今")
        assert not result.content_preview.startswith("…")

    def test_long_content_context_window(self, db_session) -> None:
        """长内容 → ±50 字上下文窗口 + 首尾省略号"""
        char = _create_character(db_session)
        conv = _create_conversation(db_session, char.id)
        content = "x" * 100 + "关键词" + "y" * 100
        _create_message(db_session, conv.id, Role.USER, content)

        result = message_service.search_messages(db_session, "关键词")[0]
        preview = result.content_preview

        assert preview.startswith("…")
        assert preview.endswith("…")
        assert "关键词" in preview
        # 窗口 = [idx-50, idx+len(query)+50)，关键词占 3 字
        assert preview == "…" + content[50:153] + "…"
        assert len(preview) == 105  # 1 + 103 + 1


# ── 4. 排序与 limit ──


class TestOrderAndLimit:
    def _seed_three(self, db_session) -> tuple[Message, Message, Message]:
        char = _create_character(db_session)
        conv = _create_conversation(db_session, char.id)
        m1 = _create_message(
            db_session, conv.id, Role.USER, "第一首诗歌",
            created_at=datetime.datetime(2026, 1, 1, 10, 0),
        )
        m2 = _create_message(
            db_session, conv.id, Role.ASSISTANT, "第二首诗歌",
            created_at=datetime.datetime(2026, 1, 2, 10, 0),
        )
        m3 = _create_message(
            db_session, conv.id, Role.USER, "第三首诗歌",
            created_at=datetime.datetime(2026, 1, 3, 10, 0),
        )
        return m1, m2, m3

    def test_order_desc_by_created_at(self, db_session) -> None:
        """命中多条 → 按 created_at 倒序"""
        m1, m2, m3 = self._seed_three(db_session)
        results = message_service.search_messages(db_session, "诗歌")
        assert [r.message_id for r in results] == [m3.id, m2.id, m1.id]

    def test_limit_truncates(self, db_session) -> None:
        """limit 截断返回条数"""
        self._seed_three(db_session)
        results = message_service.search_messages(db_session, "诗歌", limit=2)
        assert len(results) == 2


# ── 5. 路由层（response_model 统一序列化路径） ──


class TestSearchRoute:
    def test_route_returns_search_results(self, db_session) -> None:
        """路由直连：返回 list[SearchResult]，走统一序列化路径"""
        _seed_one(db_session)
        results = messages_route.search_messages(q="诗歌", limit=50, db=db_session)
        assert isinstance(results, list)
        assert len(results) == 1
        assert isinstance(results[0], SearchResult)
        assert results[0].content_preview == "今天心情不错，我们聊诗歌吧"

    def test_route_no_match_returns_empty(self, db_session) -> None:
        """路由直连：无匹配 → []"""
        _seed_one(db_session)
        assert messages_route.search_messages(q="无匹配", limit=50, db=db_session) == []
