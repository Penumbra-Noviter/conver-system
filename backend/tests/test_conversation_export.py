"""
对话导出单测 — backend/app/services/conversation_export.py

覆盖：
    1. JSON 导出：conversation / character（9 字段契约，ConversationExportCharacter Schema 驱动）/
       messages 三段结构、缺对话返回 None、缺角色 character=None、无消息 messages=[]
    2. Markdown 导出：标题 / 角色信息 / 模型 / 时间 / 按日期分组 / 无角色回退 /
       角色信息为空回退「无」

依赖：pytest + SQLite 内存库（conftest.db_session，StaticPool 保证同一连接）。
"""

from __future__ import annotations

import datetime

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, Role
from backend.app.services.conversation_export import (
    export_conversation_json,
    export_conversation_markdown,
)

__all__: list[str] = []


# ── 测试数据构造（落库） ──


def _create_character(db_session, **overrides: object) -> Character:
    """落库一个角色，返回持久化实例"""
    base = {
        "name": "测试角色",
        "description": "一个用于测试的角色",
        "personality": "冷静、睿智",
        "scenario": "月下竹林",
        "first_mes": "你好，久等了。",
        "mes_example": "<START>\n{{user}}: 你好\n{{char}}: 欢迎",
        "system_prompt": "你是测试角色。",
        "post_history_instructions": "保持人设。",
        "alternate_greetings": ["备选开场白"],
        "tags": ["冒险", "奇幻"],
        "creator": "测试作者",
        "version": "1.0",
        "creator_notes": {"note": "创作者备注"},
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
        "model_name": "claude-sonnet-5",
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


# ── 1. JSON 导出 ──


class TestExportJson:
    def test_full_structure(self, db_session) -> None:
        """三段结构：conversation / character（9 字段子集）/ messages"""
        char = _create_character(db_session, name="艾莉", avatar="data:image/png;base64,AAA")
        conv = _create_conversation(db_session, char.id)
        msg1 = _create_message(db_session, conv.id, Role.USER, "你好")
        msg2 = _create_message(db_session, conv.id, Role.ASSISTANT, "欢迎")

        data = export_conversation_json(db_session, conv.id)

        assert data is not None
        assert list(data.keys()) == ["conversation", "character", "messages"]

        assert data["conversation"] == {
            "id": conv.id,
            "title": "关于诗歌的讨论",
            "model_provider": "claude",
            "model_name": "claude-sonnet-5",
            "created_at": conv.created_at.isoformat(),
            "updated_at": conv.updated_at.isoformat(),
        }

        # character 段：字段名与顺序即导出契约（ConversationExportCharacter Schema 定义）
        assert list(data["character"].keys()) == [
            "id", "name", "description", "personality", "scenario",
            "first_mes", "system_prompt", "avatar", "temperature",
        ]
        assert data["character"]["id"] == char.id
        assert data["character"]["name"] == "艾莉"
        assert data["character"]["description"] == "一个用于测试的角色"
        assert data["character"]["personality"] == "冷静、睿智"
        assert data["character"]["scenario"] == "月下竹林"
        assert data["character"]["first_mes"] == "你好，久等了。"
        assert data["character"]["system_prompt"] == "你是测试角色。"
        assert data["character"]["avatar"] == "data:image/png;base64,AAA"
        assert data["character"]["temperature"] == 0.7
        # 导出子集之外的角色字段不得混入（契约逐字节一致）
        assert "mes_example" not in data["character"]
        assert "extensions" not in data["character"]

        assert [m["id"] for m in data["messages"]] == [msg1.id, msg2.id]
        assert data["messages"][0] == {
            "id": msg1.id,
            "role": "user",
            "content": "你好",
            "created_at": msg1.created_at.isoformat(),
        }
        assert data["messages"][1]["role"] == "assistant"

    def test_missing_conversation_returns_none(self, db_session) -> None:
        """对话不存在 → None"""
        assert export_conversation_json(db_session, 99999) is None

    def test_missing_character_character_none(self, db_session) -> None:
        """角色不存在 → character 段为 None（FK 未强制时允许悬挂 character_id）"""
        conv = _create_conversation(db_session, 99999)
        data = export_conversation_json(db_session, conv.id)
        assert data is not None
        assert data["character"] is None
        assert data["messages"] == []

    def test_no_messages_messages_empty(self, db_session) -> None:
        """无消息 → messages 为空列表"""
        char = _create_character(db_session)
        conv = _create_conversation(db_session, char.id)
        data = export_conversation_json(db_session, conv.id)
        assert data is not None
        assert data["messages"] == []


# ── 2. Markdown 导出 ──


class TestExportMarkdown:
    def test_full_markdown(self, db_session) -> None:
        """标题 / 角色信息 / 模型 / 时间 / 消息行"""
        char = _create_character(db_session, name="艾莉")
        conv = _create_conversation(db_session, char.id)
        _create_message(db_session, conv.id, Role.USER, "你好")
        _create_message(db_session, conv.id, Role.ASSISTANT, "欢迎")

        md = export_conversation_markdown(db_session, conv.id)
        assert md is not None
        lines = md.split("\n")

        assert lines[0] == "# 与 艾莉 的对话"
        assert "**角色信息**: 一个用于测试的角色；人格: 冷静、睿智；场景: 月下竹林" in lines
        assert "**模型**: claude/claude-sonnet-5" in lines
        assert f"**时间**: {conv.created_at.strftime('%Y-%m-%d %H:%M')}" in lines
        assert "**user**: 你好" in lines
        assert "**assistant**: 欢迎" in lines

    def test_missing_conversation_returns_none(self, db_session) -> None:
        """对话不存在 → None"""
        assert export_conversation_markdown(db_session, 99999) is None

    def test_no_character_fallback(self, db_session) -> None:
        """角色不存在 → 「未知角色」+ 角色信息「无」"""
        conv = _create_conversation(db_session, 99999)
        _create_message(db_session, conv.id, Role.USER, "在吗")
        md = export_conversation_markdown(db_session, conv.id)
        assert md is not None
        assert "# 与 未知角色 的对话" in md
        assert "**角色信息**: 无" in md
        assert "**user**: 在吗" in md

    def test_character_info_parts_partial(self, db_session) -> None:
        """角色部分字段缺失 → 角色信息只含非空片段"""
        char = _create_character(db_session, personality="", scenario="")
        conv = _create_conversation(db_session, char.id)
        md = export_conversation_markdown(db_session, conv.id)
        assert md is not None
        assert "**角色信息**: 一个用于测试的角色" in md
        assert "人格" not in md
        assert "场景" not in md

    def test_character_info_empty_fallback(self, db_session) -> None:
        """描述/人格/场景全空 → 角色信息「无」"""
        char = _create_character(db_session, description="", personality="", scenario="")
        conv = _create_conversation(db_session, char.id)
        md = export_conversation_markdown(db_session, conv.id)
        assert md is not None
        assert "**角色信息**: 无" in md

    def test_groups_by_date(self, db_session) -> None:
        """消息按日期分组，日期切换处以 --- 分隔"""
        char = _create_character(db_session)
        conv = _create_conversation(db_session, char.id)
        _create_message(
            db_session, conv.id, Role.USER, "第一天",
            created_at=datetime.datetime(2026, 1, 1, 10, 0),
        )
        _create_message(
            db_session, conv.id, Role.ASSISTANT, "第二天",
            created_at=datetime.datetime(2026, 1, 2, 10, 0),
        )
        _create_message(
            db_session, conv.id, Role.USER, "第二天晚",
            created_at=datetime.datetime(2026, 1, 2, 20, 0),
        )

        md = export_conversation_markdown(db_session, conv.id)
        assert md is not None
        lines = md.split("\n")

        first = lines.index("### 2026-01-01")
        second = lines.index("### 2026-01-02")
        assert lines[first + 2] == "**user**: 第一天"
        assert lines[second - 2] == "---"  # 跨日分隔线
        assert lines[second + 2] == "**assistant**: 第二天"
        assert lines[second + 4] == "**user**: 第二天晚"
        assert "### 2026-01-01" in lines
        assert "### 2026-01-02" in lines

    def test_message_without_timestamp(self, db_session) -> None:
        """消息无时间戳 → 不产出 None 日期头（沿用既有行为）

        None 时间戳在 SQLite 升序排序中排最前，与 current_date 初值（None）相同，
        故日期头被抑制；有日期消息仍正常分组。
        """
        char = _create_character(db_session)
        conv = _create_conversation(db_session, char.id)
        _create_message(
            db_session, conv.id, Role.USER, "第一天",
            created_at=datetime.datetime(2026, 1, 1, 10, 0),
        )
        msg = _create_message(db_session, conv.id, Role.USER, "无时间消息")
        msg.created_at = None
        db_session.commit()

        md = export_conversation_markdown(db_session, conv.id)
        assert md is not None
        assert "### None" not in md
        assert "### 2026-01-01" in md
        assert "**user**: 无时间消息" in md
        assert "**user**: 第一天" in md

        # 首条消息即无时间戳 → 同样不产出日期头（current_date 初值亦为 None）
        conv2 = _create_conversation(db_session, char.id)
        msg2 = _create_message(db_session, conv2.id, Role.USER, "无时间首条")
        msg2.created_at = None
        db_session.commit()
        md2 = export_conversation_markdown(db_session, conv2.id)
        assert md2 is not None
        assert "### None" not in md2
        assert "**user**: 无时间首条" in md2


# ── 3. 路由层导出响应（Content-Disposition 编码） ──


class TestExportRouteHeaders:
    def test_export_json_chinese_filename_header(self, db_session) -> None:
        """JSON 导出：角色名为中文时 Content-Disposition 必须可编码
        （latin-1 只支持 ASCII → filename 用 ASCII 兜底，中文走 RFC 5987 filename*）"""
        from backend.app.api.routes.conversations import export_conversation_json

        char = _create_character(db_session, name="测试·毒舌助手")
        conv = _create_conversation(db_session, char.id)
        _create_message(db_session, conv.id, Role.USER, "你好")

        resp = export_conversation_json(conv.id, db_session)
        assert resp.status_code == 200
        header = resp.headers["Content-Disposition"]
        # ASCII 兜底 + UTF-8 编码名并存（RFC 5987）
        assert 'filename="conversation-' in header
        assert header.endswith('.json"') or ".json" in header
        assert "filename*=UTF-8''" in header
        assert "conversation-1-" in header  # 中文角色名已进 filename* 而非 filename

    def test_export_markdown_ascii_filename(self, db_session) -> None:
        """Markdown 导出：header 始终可编码（ASCII 文件名）"""
        from backend.app.api.routes.conversations import export_conversation_markdown

        char = _create_character(db_session, name="测试·毒舌助手")
        conv = _create_conversation(db_session, char.id)
        _create_message(db_session, conv.id, Role.USER, "你好")

        resp = export_conversation_markdown(conv.id, db_session)
        assert resp.status_code == 200
        assert "attachment" in resp.headers["Content-Disposition"]
