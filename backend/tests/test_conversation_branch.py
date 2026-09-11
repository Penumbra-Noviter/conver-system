"""
BR-2 从快照/分支派生会话 — 契约测试

覆盖（验收语义契约，spec §BR-2）：
    1. branch 生成的新会话消息序列与源（截断后）逐条一致
    2. 源会话零改动（消息数与内容断言）
    3. 世界书条目语义锁定：分支不重插不污染（角色级共享随角色自然继承；
       角色条目集合不变——重插会造成重复副本破坏记忆宫殿增量计数不变量）
    4. 级联：删源会话不影响已派生分支（parent 引用置空策略明示并锁定）
    5. 路由层：不存在 message_id → 404 明确错误体；GET /snapshot 下载；
       POST /branch /import-branch 创建 + 版本拒绝
    6. clone 防御矩阵：未知角色 / 非法消息角色 / 激活序号越界 /
       content≠激活候选（快照不变量破坏即拒）

依赖：pytest + SQLite 内存库（conftest.db_session）；不构造真实网络请求。
"""

from __future__ import annotations

import pytest
from sqlalchemy.orm import Session

from backend.app.api.routes import conversations as conversations_route
from backend.app.models.message import Message, MessageSwipe, Role
from backend.app.schemas.branch import SNAPSHOT_VERSION, BranchSnapshot, BranchSnapshotMessage, BranchSnapshotSwipe
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.lorebook import LorebookEntryCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import conversation_export as export_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import message as message_service
from backend.app.services.exceptions import (
    BranchSnapshotError,
    CharacterNotFoundError,
    MessageNotFoundError,
)

__all__: list[str] = []


# ── 测试基础设施（与 test_branch_snapshot.py 同模式）──


def _create_character(
    db: Session,
    name: str = "测试角色",
) -> int:
    """落库一个角色，返回 id"""
    from backend.app.models.character import Character

    char = Character(name=name, personality="冷静、睿智")
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
    title: str = "源对话",
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
            title=title,
        ),
    )


def _add_messages(
    db: Session,
    conversation_id: int,
    *pairs: tuple[str, str],
) -> list[int]:
    """按顺序追加消息，返回消息 id 列表（每对为 (role, content)）"""
    ids = []
    for role, content in pairs:
        ids.append(message_service.create_message(db, conversation_id, Role(role), content).id)
    return ids


def _add_lorebook_entries(db: Session, character_id: int, count: int = 2) -> None:
    """给角色落库 count 条世界书条目（含常驻/关键词形态）"""
    for i in range(count):
        lorebook_service.create_entry(
            db,
            character_id,
            LorebookEntryCreate(
                title=f"条目{i}",
                keys=[f"键{i}"] if i > 0 else [],
                content=f"内容{i}",
                constant=(i == 0),
                order=10 + i,
                position="world" if i == 0 else "before_char",
                enabled=True,
            ),
        )


def _message_contents(db: Session, conversation_id: int) -> list[str]:
    """按 id 升序返回对话全部消息内容"""
    rows = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.id.asc())
        .all()
    )
    return [row.content for row in rows]


def _message_roles(db: Session, conversation_id: int) -> list[str]:
    """按 id 升序返回对话全部消息角色"""
    rows = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.id.asc())
        .all()
    )
    return [row.role.value for row in rows]


def _entry_titles(db: Session, character_id: int) -> list[str]:
    """角色世界书条目标题（list_entries 确定性序）"""
    return [e.title for e in lorebook_service.list_entries(db, character_id)]


def _full_snapshot(db: Session, conversation_id: int) -> BranchSnapshot:
    """便捷：全量快照"""
    return export_service.build_branch_snapshot(db, conversation_id)


def _setup_source(db: Session) -> tuple[object, list[int]]:
    """带候选 + 世界书条目的源会话（4 消息），返回 (conv, message_ids)"""
    char_id = _create_character(db)
    _add_lorebook_entries(db, char_id)
    conv = _create_conversation(db, character_id=char_id, title="源对话")
    ids = _add_messages(
        db, conv.id,
        ("user", "第一轮问"), ("assistant", "第一轮答"),
        ("user", "第二轮问"), ("assistant", "第二轮答"),
    )
    message_service.add_swipe(db, ids[3], "重写第二轮答", make_active=True)
    return conv, ids


# ── 1. clone_conversation（快照导入重建）──


class TestCloneConversation:
    """从快照重建会话：消息/候选/激活往返一致 + 防御矩阵"""

    def test_clone_roundtrip_messages_swipes_and_metadata(
        self, db_session: Session
    ) -> None:
        """核心契约（BR-1 #4 兑现）：快照 → 新会话逐条一致（消息序/候选/激活/元数据）"""
        conv, ids = _setup_source(db_session)
        snapshot = _full_snapshot(db_session, conv.id)

        new_conv = conversation_service.clone_conversation(db_session, snapshot)

        assert new_conv.id != conv.id
        assert new_conv.character_id == conv.character_id
        assert new_conv.model_provider == "claude"
        assert new_conv.model_name == "claude-test"
        assert new_conv.title == "源对话"
        # 消息逐条一致（角色/内容/创建时间）
        assert _message_roles(db_session, new_conv.id) == _message_roles(db_session, conv.id)
        assert _message_contents(db_session, new_conv.id) == _message_contents(db_session, conv.id)
        # 候选与激活序号往返一致（候选 0 = 原始内容；content 跟随激活候选）
        new_msgs = (
            db_session.query(Message)
            .filter(Message.conversation_id == new_conv.id)
            .order_by(Message.id.asc())
            .all()
        )
        last = new_msgs[-1]
        assert last.content == "重写第二轮答"
        assert last.active_swipe_index == 1
        swipe_rows = (
            db_session.query(MessageSwipe)
            .filter(MessageSwipe.message_id == last.id)
            .order_by(MessageSwipe.index.asc())
            .all()
        )
        assert [s.content for s in swipe_rows] == ["第二轮答", "重写第二轮答"]
        # created_at 保真
        src_msgs = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv.id)
            .order_by(Message.id.asc())
            .all()
        )
        assert [m.created_at for m in new_msgs] == [m.created_at for m in src_msgs]

    def test_clone_explicit_title_overrides(self, db_session: Session) -> None:
        """显式 title 覆盖快照标题；None → 快照标题"""
        conv, _ = _setup_source(db_session)
        snapshot = _full_snapshot(db_session, conv.id)

        with_title = conversation_service.clone_conversation(db_session, snapshot, title="我的分支")
        assert with_title.title == "我的分支"

        without_title = conversation_service.clone_conversation(db_session, snapshot)
        assert without_title.title == "源对话"

    def test_clone_unknown_character_raises(self, db_session: Session) -> None:
        """快照角色不存在 → CharacterNotFoundError（404 语义）"""
        snapshot = BranchSnapshot(version=SNAPSHOT_VERSION, character_id=99999)

        with pytest.raises(CharacterNotFoundError):
            conversation_service.clone_conversation(db_session, snapshot)

    def test_clone_invalid_message_role_raises(self, db_session: Session) -> None:
        """快照消息角色非法 → BranchSnapshotError（不裸抛 ValueError）"""
        char_id = _create_character(db_session)
        snapshot = BranchSnapshot(
            version=SNAPSHOT_VERSION,
            character_id=char_id,
            messages=[BranchSnapshotMessage(role="npc", content="非法角色")],
        )

        with pytest.raises(BranchSnapshotError):
            conversation_service.clone_conversation(db_session, snapshot)

    def test_clone_active_index_out_of_range_raises(self, db_session: Session) -> None:
        """激活序号越界（候选 2 条但 active=5）→ BranchSnapshotError"""
        char_id = _create_character(db_session)
        snapshot = BranchSnapshot(
            version=SNAPSHOT_VERSION,
            character_id=char_id,
            messages=[BranchSnapshotMessage(role="assistant", content="答")],
            swipes=[BranchSnapshotSwipe(message_index=0, swipes=["答", "重写"], active_swipe_index=5)],
        )

        with pytest.raises(BranchSnapshotError, match="激活"):
            conversation_service.clone_conversation(db_session, snapshot)

    def test_clone_content_mismatch_active_candidate_raises(self, db_session: Session) -> None:
        """content ≠ 激活候选（手写快照破坏「content 跟随激活候选」不变量）→ 拒绝"""
        char_id = _create_character(db_session)
        snapshot = BranchSnapshot(
            version=SNAPSHOT_VERSION,
            character_id=char_id,
            messages=[BranchSnapshotMessage(role="assistant", content="内容A")],
            swipes=[BranchSnapshotSwipe(message_index=0, swipes=["原始", "候选B"], active_swipe_index=1)],
        )

        with pytest.raises(BranchSnapshotError, match="激活候选"):
            conversation_service.clone_conversation(db_session, snapshot)

    def test_clone_empty_messages_yields_empty_conversation(self, db_session: Session) -> None:
        """空消息快照 → 新会话无消息（合法；无候选）"""
        char_id = _create_character(db_session)
        snapshot = BranchSnapshot(version=SNAPSHOT_VERSION, character_id=char_id)

        new_conv = conversation_service.clone_conversation(db_session, snapshot)

        assert _message_contents(db_session, new_conv.id) == []


# ── 2. branch_from_message（从锚消息派生）──


class TestBranchFromMessage:
    """分支派生：消息逐条一致 + 源零改动 + 父/锚记录"""

    def test_branch_messages_match_source_truncated(
        self, db_session: Session
    ) -> None:
        """核心契约 1：新会话消息序列与源（截断含锚后）逐条一致；父/锚/分支名记录"""
        conv, ids = _setup_source(db_session)
        anchor_id = ids[1]  # 第一轮答

        new_conv = conversation_service.branch_from_message(
            db_session, conv.id, anchor_id, title="雪夜分叉"
        )

        assert new_conv.id != conv.id
        assert _message_contents(db_session, new_conv.id) == ["第一轮问", "第一轮答"]
        assert _message_roles(db_session, new_conv.id) == ["user", "assistant"]
        # 分支元数据
        assert new_conv.parent_conversation_id == conv.id
        assert new_conv.branch_from_message_id == anchor_id
        assert new_conv.branch_title == "雪夜分叉"
        # 角色关联不变（同 character）
        assert new_conv.character_id == conv.character_id

    def test_source_untouched(self, db_session: Session) -> None:
        """核心契约 2：源会话零改动（消息数、内容、候选全保留）"""
        conv, ids = _setup_source(db_session)
        before_contents = _message_contents(db_session, conv.id)
        before_ids = [m.id for m in
                      db_session.query(Message).filter(Message.conversation_id == conv.id).all()]

        conversation_service.branch_from_message(db_session, conv.id, ids[1])

        assert _message_contents(db_session, conv.id) == before_contents
        after_ids = [m.id for m in
                     db_session.query(Message).filter(Message.conversation_id == conv.id).all()]
        assert after_ids == before_ids  # 无新增/删除/替换
        # 候选原样
        target = db_session.query(Message).filter(Message.id == ids[3]).first()
        assert [s.content for s in message_service.list_swipes(db_session, target.id)] == [
            "第二轮答", "重写第二轮答",
        ]

    def test_branch_lorebook_shared_no_duplication(
        self, db_session: Session
    ) -> None:
        """核心契约 3：分支不重插不污染——角色条目集合不变（共享世界态随角色自然继承）"""
        conv, ids = _setup_source(db_session)
        char_id = conv.character_id
        before_titles = _entry_titles(db_session, char_id)
        assert len(before_titles) == 2

        new_conv = conversation_service.branch_from_message(db_session, conv.id, ids[1])

        # 条目集合不变（不重复副本——重插会破坏记忆宫殿增量计数不变量）
        assert _entry_titles(db_session, char_id) == before_titles
        # 分支会话与源读到同一角色世界态（共享语义；同 character 会话视角一致）
        assert lorebook_service.list_entries(db_session, new_conv.character_id) == \
            lorebook_service.list_entries(db_session, char_id)

    def test_branch_unknown_message_404(self, db_session: Session) -> None:
        """锚消息不存在 → MessageNotFoundError（路由层 404 明确错误体）"""
        conv, _ = _setup_source(db_session)

        with pytest.raises(MessageNotFoundError):
            conversation_service.branch_from_message(db_session, conv.id, 99999)

    def test_branch_message_of_other_conversation_404(self, db_session: Session) -> None:
        """锚消息属于其他对话 → MessageNotFoundError（不得跨会话分支）"""
        conv_a, ids_a = _setup_source(db_session)
        conv_b = _create_conversation(db_session)
        _add_messages(db_session, conv_b.id, ("user", "问B"), ("assistant", "答B"))

        with pytest.raises(MessageNotFoundError):
            conversation_service.branch_from_message(db_session, conv_b.id, ids_a[1])

    def test_delete_source_nulls_children_and_branch_survives(
        self, db_session: Session
    ) -> None:
        """核心契约 4：删源会话不影响已派生分支——parent/锚置空，分支仍可读"""
        conv, ids = _setup_source(db_session)
        child = conversation_service.branch_from_message(db_session, conv.id, ids[1], title="分叉")

        conversation_service.delete_conversation(db_session, conv.id)

        # 分支存活 + 引用置空（明示策略：parent/锚 → NULL；branch_title 保留）
        db_session.refresh(child)
        assert child.parent_conversation_id is None
        assert child.branch_from_message_id is None
        assert child.branch_title == "分叉"
        assert _message_contents(db_session, child.id) == ["第一轮问", "第一轮答"]


# ── 3. 路由层契约 ──


class TestBranchRoutes:
    """POST /{id}/branch、POST /import-branch、GET /{id}/snapshot"""

    async def test_route_branch_creates_conversation(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """POST /{id}/branch：body {message_id, title} → 新会话 + 父/锚/分支名"""
        from backend.app.schemas.branch import BranchRequest

        conv, ids = _setup_source(db_session)
        body = BranchRequest(message_id=ids[1], title="路由分支")

        resp = await conversations_route.branch(conv.id, body, db_session)

        assert resp.id != conv.id
        assert resp.character_id == conv.character_id
        fresh = conversation_service.require_conversation(db_session, resp.id)
        assert fresh.parent_conversation_id == conv.id
        assert fresh.branch_from_message_id == ids[1]
        assert fresh.branch_title == "路由分支"
        assert _message_contents(db_session, resp.id) == ["第一轮问", "第一轮答"]

    async def test_route_branch_message_not_found_404(
        self, db_session: Session
    ) -> None:
        """核心契约 5：不存在 message_id → MessageNotFoundError（统一 handler 转 404 明确错误体）"""
        from backend.app.schemas.branch import BranchRequest

        conv, _ = _setup_source(db_session)
        body = BranchRequest(message_id=99999)

        with pytest.raises(MessageNotFoundError):
            await conversations_route.branch(conv.id, body, db_session)

    async def test_route_import_branch_creates_conversation(
        self, db_session: Session
    ) -> None:
        """POST /import-branch：body {snapshot} → 新会话 + 消息重建"""
        from backend.app.schemas.branch import ImportBranchRequest

        conv, ids = _setup_source(db_session)
        snapshot = _full_snapshot(db_session, conv.id)

        resp = await conversations_route.import_branch(
            ImportBranchRequest(snapshot=snapshot.model_dump(mode="json")), db_session
        )

        assert resp.id != conv.id
        assert resp.title == "源对话"
        assert _message_contents(db_session, resp.id) == _message_contents(db_session, conv.id)

    async def test_route_import_branch_version_rejected(
        self, db_session: Session
    ) -> None:
        """import 未知版本快照 → BranchSnapshotError（400 明确拒绝，未知版本不导入）"""
        from backend.app.schemas.branch import ImportBranchRequest

        body = ImportBranchRequest(snapshot={"version": 999, "character_id": 1, "messages": []})

        with pytest.raises(BranchSnapshotError, match="不支持"):
            await conversations_route.import_branch(body, db_session)

    async def test_route_snapshot_download(self, db_session: Session) -> None:
        """GET /{id}/snapshot → 快照 dict（含版本 + 消息）+ 下载头"""
        import json

        conv, ids = _setup_source(db_session)

        resp = await conversations_route.snapshot(conv.id, db_session)

        data = json.loads(resp.body)
        assert data["version"] == SNAPSHOT_VERSION
        assert [m["content"] for m in data["messages"]] == [
            "第一轮问", "第一轮答", "第二轮问", "重写第二轮答",
        ]
        assert "attachment" in resp.headers.get("content-disposition", "")