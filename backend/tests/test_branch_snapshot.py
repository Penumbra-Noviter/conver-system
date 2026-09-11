"""
BR-1 分支元数据与快照导出 — 契约测试

覆盖（验收语义契约，spec §BR-1）：
    1. 截断锚正确性：upto_message_id 含锚、不含锚后消息；None → 全量
    2. 快照含世界书条目与 swipes（记忆随存档走，对齐对标站语义）
    3. 版本号缺失/不支持 → BranchSnapshotError 明确异常
    4. 导出 → JSON 往返一致（消息顺序、创建时间、候选与源逐条一致）
    5. 自愈迁移：存量 conversations 表缺分支三列 → ALTER 补列 + 幂等
    6. 对话不存在 → ConversationNotFoundError；锚不存在/跨会话 → MessageNotFoundError
    7. 批量候选：list_swipes_batch 一次 IN 查询（list_swipes 不被逐条调用，无 N+1）

依赖：pytest + SQLite 内存库（conftest.db_session）；不构造真实网络请求。
"""

from __future__ import annotations

import json

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session

from backend.app.models.message import Message, Role
from backend.app.schemas.branch import SNAPSHOT_VERSION, BranchSnapshot
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.lorebook import LorebookEntryCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import conversation_export as export_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import message as message_service
from backend.app.services.exceptions import (
    BranchSnapshotError,
    ConversationNotFoundError,
    MessageNotFoundError,
)

__all__: list[str] = []


# ── 测试基础设施（与 test_chat_continue.py 同模式）──


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
    title: str = "测试对话",
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


def _add_lorebook_entries(db: Session, character_id: int) -> None:
    """给角色落库两条世界书条目（覆盖不同 position/constant/keys 形态）"""
    lorebook_service.create_entry(
        db,
        character_id,
        LorebookEntryCreate(
            title="大陆设定",
            keys=["王都", "王国"],
            content="这里是王都，白银之城。",
            constant=False,
            order=10,
            position="world",
            enabled=True,
        ),
    )
    lorebook_service.create_entry(
        db,
        character_id,
        LorebookEntryCreate(
            title="常驻剑客",
            keys=[],
            content="剑客永远佩戴一把长剑。",
            constant=True,
            order=20,
            position="before_char",
            enabled=True,
        ),
    )


# ── 1. 快照载荷与截断锚 ──


class TestSnapshotLoad:
    """build_branch_snapshot 载荷字段与消息截断语义"""

    def test_full_snapshot_includes_all_messages_and_metadata(
        self, db_session: Session
    ) -> None:
        """upto_message_id=None → 全量；载荷含版本/角色/模型/标题与消息序列"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, character_id=char_id, title="分支测试")
        _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )

        snap = export_service.build_branch_snapshot(db_session, conv.id)

        assert snap.version == SNAPSHOT_VERSION
        assert snap.character_id == char_id
        assert snap.model_provider == "claude"
        assert snap.model_name == "claude-test"
        assert snap.title == "分支测试"
        assert [m.role for m in snap.messages] == ["user", "assistant", "user", "assistant"]
        assert [m.content for m in snap.messages] == [
            "第一轮问", "第一轮答", "第二轮问", "第二轮答",
        ]

    def test_truncation_anchor_inclusive(
        self, db_session: Session
    ) -> None:
        """核心契约 1：upto_message_id 截断含锚、不含锚后消息"""
        conv = _create_conversation(db_session)
        ids = _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        anchor_id = ids[1]  # 第一轮答

        snap = export_service.build_branch_snapshot(db_session, conv.id, upto_message_id=anchor_id)

        assert [m.content for m in snap.messages] == ["第一轮问", "第一轮答"]

    def test_truncation_rebases_swipe_message_index(
        self, db_session: Session
    ) -> None:
        """截断后 swipes 的 message_index 指向截断后消息数组下标（非源全局位置）"""
        conv = _create_conversation(db_session)
        ids = _add_messages(
            db_session, conv.id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )
        # 对「第二轮答」（截断后不存在）与「第一轮答」（截断后下标 1）加候选
        message_service.add_swipe(db_session, ids[3], "重写第二轮", make_active=True)
        message_service.add_swipe(db_session, ids[1], "重写第一轮", make_active=True)

        snap = export_service.build_branch_snapshot(db_session, conv.id, upto_message_id=ids[1])

        # 截断后 messages = [第一轮问, 第一轮答]；swipes 只含锚消息（下标 1）
        assert len(snap.swipes) == 1
        assert snap.swipes[0].message_index == 1
        assert snap.swipes[0].swipes == ["第一轮答", "重写第一轮"]
        assert snap.swipes[0].active_swipe_index == 1

    def test_conversation_not_found_raises(self, db_session: Session) -> None:
        """对话不存在 → ConversationNotFoundError（路由层转 404）"""
        with pytest.raises(ConversationNotFoundError):
            export_service.build_branch_snapshot(db_session, 99999)

    def test_unknown_anchor_raises(self, db_session: Session) -> None:
        """锚消息 id 不存在 → MessageNotFoundError（静默空快照禁止）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        with pytest.raises(MessageNotFoundError):
            export_service.build_branch_snapshot(db_session, conv.id, upto_message_id=99999)

    def test_anchor_of_other_conversation_raises(self, db_session: Session) -> None:
        """锚消息属于其他对话 → MessageNotFoundError（不得跨会话截断）"""
        conv_a = _create_conversation(db_session)
        conv_b = _create_conversation(db_session)
        ids_a = _add_messages(db_session, conv_a.id, ("user", "问A"), ("assistant", "答A"))
        _add_messages(db_session, conv_b.id, ("user", "问B"), ("assistant", "答B"))

        with pytest.raises(MessageNotFoundError):
            export_service.build_branch_snapshot(db_session, conv_b.id, upto_message_id=ids_a[1])


# ── 2. 记忆随存档走（世界书条目 + swipes）──


class TestSnapshotMemoryPayload:
    """快照含世界书条目与候选（对齐对标站「记忆随存档走」语义）"""

    def test_snapshot_contains_lorebook_entries(
        self, db_session: Session
    ) -> None:
        """核心契约 2：世界书条目进快照，字段保真（keys 数组/constant/position）"""
        char_id = _create_character(db_session)
        _add_lorebook_entries(db_session, char_id)
        conv = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        snap = export_service.build_branch_snapshot(db_session, conv.id)

        assert len(snap.lorebook_entries) == 2
        by_title = {e.title: e for e in snap.lorebook_entries}
        assert by_title["大陆设定"].keys == ["王都", "王国"]
        assert by_title["大陆设定"].constant is False
        assert by_title["大陆设定"].position == "world"
        assert by_title["常驻剑客"].constant is True
        assert by_title["常驻剑客"].position == "before_char"
        assert by_title["常驻剑客"].content == "剑客永远佩戴一把长剑。"

    def test_snapshot_contains_swipes_and_active_index(
        self, db_session: Session
    ) -> None:
        """候选集与激活序号进快照（content 跟随激活候选语义）"""
        conv = _create_conversation(db_session)
        ids = _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "原始答"))
        message_service.add_swipe(db_session, ids[1], "重写答", make_active=True)

        snap = export_service.build_branch_snapshot(db_session, conv.id)

        assert snap.messages[1].content == "重写答"  # content 跟随激活候选
        assert len(snap.swipes) == 1
        swipe = snap.swipes[0]
        assert swipe.message_index == 1
        assert swipe.swipes == ["原始答", "重写答"]
        assert swipe.active_swipe_index == 1

    def test_no_swipes_no_entries_yields_empty_lists(
        self, db_session: Session
    ) -> None:
        """无候选/无世界书条目 → 快照对应列表为空（结构稳定）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        snap = export_service.build_branch_snapshot(db_session, conv.id)

        assert snap.swipes == []
        assert snap.lorebook_entries == []


# ── 3. 版本化契约 ──


class TestSnapshotVersion:
    """版本号缺失/不支持 → 明确异常（未知版本拒绝导入）"""

    def test_version_missing_raises(self) -> None:
        """缺 version 字段 → BranchSnapshotError 明确消息"""
        with pytest.raises(BranchSnapshotError, match="缺少版本号"):
            export_service.validate_branch_snapshot({"character_id": 1, "messages": []})

    def test_version_unsupported_raises(self) -> None:
        """version=999（未来版本）→ BranchSnapshotError 明确消息"""
        with pytest.raises(BranchSnapshotError, match="不支持"):
            export_service.validate_branch_snapshot(
                {"version": 999, "character_id": 1, "messages": []}
            )

    def test_validate_returns_model_on_current_version(self) -> None:
        """当前版本 → 校验通过返回 BranchSnapshot（结构可解析）"""
        snap = export_service.validate_branch_snapshot(
            {
                "version": SNAPSHOT_VERSION,
                "character_id": 7,
                "model_provider": "claude",
                "title": "快照标题",
                "messages": [{"role": "user", "content": "你好"}],
            }
        )
        assert isinstance(snap, BranchSnapshot)
        assert snap.character_id == 7
        assert snap.messages[0].content == "你好"

    def test_validate_malformed_structure_raises(self) -> None:
        """结构畸形（messages 非列表）→ BranchSnapshotError 明确异常（不裸抛 pydantic）"""
        with pytest.raises(BranchSnapshotError, match="无效"):
            export_service.validate_branch_snapshot(
                {"version": SNAPSHOT_VERSION, "character_id": 1, "messages": "不是列表"}
            )

    def test_validate_non_dict_raises(self) -> None:
        """非 dict 输入 → BranchSnapshotError"""
        with pytest.raises(BranchSnapshotError):
            export_service.validate_branch_snapshot(["version", 1])


# ── 4. 导出 → JSON 往返一致 ──


class TestSnapshotRoundTrip:
    """快照 JSON 稳定往返 + 与源 DB 逐条一致（BR-1 可锁部分；重建往返由 BR-2 承担）"""

    def test_json_roundtrip_stable(self, db_session: Session) -> None:
        """核心契约 4（导出侧）：dict → json → dict 往返相等（可序列化、无丢失）"""
        char_id = _create_character(db_session)
        _add_lorebook_entries(db_session, char_id)
        conv = _create_conversation(db_session, character_id=char_id)
        ids = _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))
        message_service.add_swipe(db_session, ids[1], "重写答", make_active=True)

        snap = export_service.build_branch_snapshot(db_session, conv.id)
        dumped = snap.model_dump(mode="json")

        roundtripped = json.loads(json.dumps(dumped))

        assert roundtripped == dumped
        assert roundtripped["version"] == SNAPSHOT_VERSION

    def test_messages_match_source_rows(self, db_session: Session) -> None:
        """快照消息 role/content/created_at 与源 DB 逐条一致（顺序/时间保真）"""
        conv = _create_conversation(db_session)
        _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答"))

        snap = export_service.build_branch_snapshot(db_session, conv.id)
        rows = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv.id)
            .order_by(Message.id.asc())
            .all()
        )

        assert [m.role for m in snap.messages] == [r.role.value for r in rows]
        assert [m.content for m in snap.messages] == [r.content for r in rows]
        assert [m.created_at for m in snap.messages] == [r.created_at for r in rows]


# ── 5. 批量候选（无 N+1）──


class TestSnapshotBatchSwipes:
    """list_swipes_batch 一次 IN 查询批量取候选（快照不走逐条 list_swipes）"""

    def test_build_does_not_call_per_message_list_swipes(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """list_swipes 被逐条调用即报错 → build 走批量路径（N+1 回归锁）"""
        conv = _create_conversation(db_session)
        ids = _add_messages(
            db_session, conv.id,
            ("user", "问"), ("assistant", "答"), ("user", "又问"), ("assistant", "再答"),
        )
        message_service.add_swipe(db_session, ids[1], "重写答", make_active=True)
        monkeypatch.setattr(
            message_service, "list_swipes",
            lambda *a, **k: (_ for _ in ()).throw(AssertionError("逐条 list_swipes 被调用（N+1）")),
        )

        snap = export_service.build_branch_snapshot(db_session, conv.id)

        assert len(snap.swipes) == 1
        assert snap.swipes[0].swipes == ["答", "重写答"]

    def test_list_swipes_batch_grouping(self, db_session: Session) -> None:
        """批量函数：多消息候选按 message_id 分组、index 升序"""
        conv = _create_conversation(db_session)
        ids = _add_messages(db_session, conv.id, ("user", "问"), ("assistant", "答A"), ("assistant", "答B"))
        message_service.add_swipe(db_session, ids[1], "A1", make_active=True)
        message_service.add_swipe(db_session, ids[2], "B1", make_active=True)

        batch = message_service.list_swipes_batch(db_session, [ids[1], ids[2]])

        assert batch[ids[1]] == ["答A", "A1"]
        assert batch[ids[2]] == ["答B", "B1"]

    def test_list_swipes_batch_empty_input(self, db_session: Session) -> None:
        """空输入 → 空 dict（零查询守卫）"""
        assert message_service.list_swipes_batch(db_session, []) == {}


# ── 6. 自愈迁移（conversations 分支三列）──


class TestBranchColumnMigration:
    """存量 conversations 表缺分支三列 → ALTER 补列；连续两次调用幂等"""

    def _legacy_engine(self):
        """模拟存量库：conversations 表不含分支三列（历史 schema 形态）"""
        engine = create_engine("sqlite://")
        with engine.connect() as conn:
            conn.execute(text(
                "CREATE TABLE conversations ("
                " id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL,"
                " title VARCHAR(200), model_provider VARCHAR(50), model_name VARCHAR(100),"
                " created_at DATETIME, updated_at DATETIME)"
            ))
            conn.commit()
        return engine

    def test_migration_adds_columns_idempotent(self) -> None:
        """核心契约 5：首次补列 + 幂等再跑无事；列类型/可空与 ORM 定义一致"""
        from backend.app.database import _ensure_conversation_branch_columns

        engine = self._legacy_engine()
        _ensure_conversation_branch_columns(engine)  # 首次补列
        _ensure_conversation_branch_columns(engine)  # 幂等：再跑无事

        with engine.connect() as conn:
            columns = {
                row[1]: row
                for row in conn.execute(text("PRAGMA table_info(conversations)")).fetchall()
            }
            assert {"parent_conversation_id", "branch_from_message_id", "branch_title"} <= set(columns)
            # PRAGMA 列序：type=2, notnull=3, dflt=4；分支列均可空（notnull=0）、无默认值
            assert columns["parent_conversation_id"][2] == "INTEGER"
            assert columns["parent_conversation_id"][3] == 0
            assert columns["branch_from_message_id"][2] == "INTEGER"
            assert columns["branch_title"][2] == "VARCHAR(200)"
            assert columns["branch_title"][3] == 0
            # 存量行零影响（旧行父/锚为 NULL）
            conn.execute(text("INSERT INTO conversations (character_id, title) VALUES (1, '旧行')"))
            conn.commit()
            row = conn.execute(text(
                "SELECT parent_conversation_id, branch_from_message_id, branch_title FROM conversations"
            )).fetchone()
            assert row == (None, None, None)

    def test_new_db_via_create_all_has_columns(self, db_session: Session) -> None:
        """新库 create_all 建表自带分支三列（无需迁移）"""
        from backend.app.database import Base

        assert "parent_conversation_id" in Base.metadata.tables["conversations"].columns
        assert "branch_from_message_id" in Base.metadata.tables["conversations"].columns
        assert "branch_title" in Base.metadata.tables["conversations"].columns