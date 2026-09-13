"""
swipes 数据模型与服务契约锁（MS-1，spec §MS-1）

锁定语义：
1. add_swipe 序号自增（0 起）且 (message_id, index) 唯一约束生效
2. switch_swipe 越界 → SwipeIndexError；合法切换更新 active_swipe_index 且与候选一致
3. 重生成 = add_swipe 追加候选：历史消息数不变（1 条 assistant + N 候选）
4. delete_swipe 边界：删中间/删当前（回落相邻）/删最后；候选清空 → 拒绝
5. 级联：删消息 → 候选全删
6. 导出含候选集与 active 索引，往返一致
"""

from __future__ import annotations

import pytest
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.lorebook import LorebookEntry  # noqa: F401 — 注册模型
from backend.app.models.message import Message, MessageSwipe, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services.conversation_export import export_conversation_json
from backend.app.services.exceptions import MessageNotFoundError, SwipeIndexError

__all__: list[str] = []


def _setup(db_session: Session) -> tuple[Character, Conversation, Message]:
    """角色 + 会话 + 首条 assistant 消息（无 greeting）"""
    char = Character(name="swipe角色", personality="测试", first_mes="")
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    conv = conversation_service.create_conversation(
        db_session, ConversationCreate(character_id=char.id)
    )
    db_session.add(Message(conversation_id=conv.id, role=Role.ASSISTANT, content="原始回复"))
    db_session.commit()
    msg = db_session.query(Message).filter(Message.conversation_id == conv.id).first()
    return char, conv, msg


# ════════════════════════════════════════════════════════════════
# 一、add_swipe 序号自增 + 唯一约束
# ════════════════════════════════════════════════════════════════


def test_add_swipe_increments_index(db_session: Session) -> None:
    """add_swipe 序号自增（候选 0 = 原始内容播种，新内容从 1 起）；make_active 更新 active_swipe_index"""
    _, _, msg = _setup(db_session)
    assert message_service.add_swipe(db_session, msg.id, "候选一", make_active=True) == 1
    assert message_service.add_swipe(db_session, msg.id, "候选二", make_active=False) == 2

    swipes = message_service.list_swipes(db_session, msg.id)
    assert [s.index for s in swipes] == [0, 1, 2]
    assert swipes[0].content == "原始回复"  # 候选 0 = 原始内容（播种）
    db_session.refresh(msg)
    assert msg.active_swipe_index == 1  # 仅第一个 make_active 生效
    assert msg.content == "候选一"  # content 跟随激活候选（Falsify 修复锁）
    assert swipes[2].content == "候选二"


def test_add_swipe_after_middle_delete_no_collision(db_session: Session) -> None:
    """删中间候选留空档后重新 add：序号 = max(index)+1 不碰撞（Falsify HIGH 修复锁）"""
    _, _, msg = _setup(db_session)
    message_service.add_swipe(db_session, msg.id, "候选一")
    message_service.add_swipe(db_session, msg.id, "候选二")
    message_service.add_swipe(db_session, msg.id, "候选三")
    message_service.delete_swipe(db_session, msg.id, 2)  # 剩余 [0,1,3]

    idx = message_service.add_swipe(db_session, msg.id, "候选四")
    assert idx == 4  # max(0,1,3)+1，不碰撞现存 3
    assert [s.index for s in message_service.list_swipes(db_session, msg.id)] == [0, 1, 3, 4]


def test_add_swipe_content_index_unique(db_session: Session) -> None:
    """(message_id, index) 唯一约束：手工插入重复 index → IntegrityError"""
    from sqlalchemy.exc import IntegrityError

    _, _, msg = _setup(db_session)
    message_service.add_swipe(db_session, msg.id, "候选")
    with pytest.raises(IntegrityError):
        db_session.add(MessageSwipe(message_id=msg.id, index=0, content="重复"))
        db_session.commit()
    db_session.rollback()


# ════════════════════════════════════════════════════════════════
# 二、switch_swipe
# ════════════════════════════════════════════════════════════════


def test_switch_swipe_valid_and_out_of_range(db_session: Session) -> None:
    """合法切换更新 active_swipe_index（含切回原始候选 0）；越界 → SwipeIndexError"""
    _, _, msg = _setup(db_session)
    message_service.add_swipe(db_session, msg.id, "候选一")
    message_service.add_swipe(db_session, msg.id, "候选二")

    switched = message_service.switch_swipe(db_session, msg.id, 1)
    assert switched.active_swipe_index == 1
    assert switched.content == "候选一"  # content 跟随激活
    # 切回原始候选 0
    back = message_service.switch_swipe(db_session, msg.id, 0)
    assert back.active_swipe_index == 0
    assert back.content == "原始回复"

    with pytest.raises(SwipeIndexError):
        message_service.switch_swipe(db_session, msg.id, 99)


# ════════════════════════════════════════════════════════════════
# 三、delete_swipe 边界
# ════════════════════════════════════════════════════════════════


def test_delete_swipe_middle_and_active_fallback(db_session: Session) -> None:
    """删中间：其余保留；删当前（active）：回落到相邻候选"""
    _, _, msg = _setup(db_session)
    message_service.add_swipe(db_session, msg.id, "候选一")
    message_service.add_swipe(db_session, msg.id, "候选二")
    message_service.add_swipe(db_session, msg.id, "候选三")
    message_service.switch_swipe(db_session, msg.id, 3)

    # 删中间（index=2）→ 候选 [0,1,3] 保留
    message_service.delete_swipe(db_session, msg.id, 2)
    assert [s.index for s in message_service.list_swipes(db_session, msg.id)] == [0, 1, 3]

    # 删当前 active=3 → 回落到相邻较小候选（index=1），content 跟随回落
    message_service.delete_swipe(db_session, msg.id, 3)
    db_session.refresh(msg)
    assert msg.active_swipe_index == 1
    assert msg.content == "候选一"  # 回落 index=1 → 候选一


def test_delete_swipe_last_and_base_protected(db_session: Session) -> None:
    """删最后一条非活跃候选 → active 保持；原始候选（index 0）受保护拒删"""
    _, _, msg = _setup(db_session)
    message_service.add_swipe(db_session, msg.id, "候选一")
    message_service.add_swipe(db_session, msg.id, "候选二")
    message_service.switch_swipe(db_session, msg.id, 0)  # 活跃 = 原始候选

    # 删最后一条（index=2，非活跃）→ 候选剩 [0,1]，active 保持 0
    message_service.delete_swipe(db_session, msg.id, 2)
    db_session.refresh(msg)
    assert msg.active_swipe_index == 0
    assert len(message_service.list_swipes(db_session, msg.id)) == 2

    # 原始候选（index 0）受保护 → 拒绝删除（消息保留）
    with pytest.raises(SwipeIndexError):
        message_service.delete_swipe(db_session, msg.id, 0)
    assert db_session.query(Message).filter(Message.id == msg.id).first() is not None


# ════════════════════════════════════════════════════════════════
# 四、级联删除
# ════════════════════════════════════════════════════════════════


def test_cascade_delete_message_removes_swipes(db_session: Session) -> None:
    """删消息 → 候选全删（DB 级 FK CASCADE）"""
    from sqlalchemy import text

    db_session.execute(text("PRAGMA foreign_keys=ON"))
    _, _, msg = _setup(db_session)
    message_service.add_swipe(db_session, msg.id, "候选0")
    message_service.add_swipe(db_session, msg.id, "候选1")

    db_session.delete(msg)
    db_session.commit()

    assert db_session.query(MessageSwipe).count() == 0


# ════════════════════════════════════════════════════════════════
# 五、导出含候选集与 active 索引
# ════════════════════════════════════════════════════════════════


def test_export_includes_swipes_and_active(db_session: Session) -> None:
    """JSON 导出：assistant 消息含 swipes 候选集 + active_swipe_index，json 往返一致"""
    _, conv, msg = _setup(db_session)
    message_service.add_swipe(db_session, msg.id, "候选一")
    message_service.add_swipe(db_session, msg.id, "候选二", make_active=True)
    message_service.add_swipe(db_session, msg.id, "候选三", make_active=False)

    data = export_conversation_json(db_session, conv.id)
    assert data is not None
    exported_msg = next(m for m in data["messages"] if m["role"] == "assistant")
    assert exported_msg["content"] == "候选二"  # content = 激活候选
    assert exported_msg["active_swipe_index"] == 2
    assert exported_msg["swipes"] == ["原始回复", "候选一", "候选二", "候选三"]

    # json 往返一致（幂等序列化）
    import json as _json

    roundtrip = _json.loads(_json.dumps(data))
    rt_msg = next(m for m in roundtrip["messages"] if m["role"] == "assistant")
    assert rt_msg["swipes"] == ["原始回复", "候选一", "候选二", "候选三"]
    assert rt_msg["active_swipe_index"] == 2

# ════════════════════════════════════════════════════════════════
# 七、路由：消息列表含候选 + switch-swipe 端点（MS-2 前端依赖）
# ════════════════════════════════════════════════════════════════


def test_messages_route_includes_swipes_and_switch(db_session) -> None:
    """GET 消息列表含候选集/激活序号；POST switch-swipe 切换生效（越界 400）"""
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from backend.app.api.errors import domain_error_handler
    from backend.app.api.routes import messages as messages_route
    from backend.app.database import get_db
    from backend.app.services.exceptions import DomainError

    app = FastAPI()
    app.add_exception_handler(DomainError, domain_error_handler)
    app.include_router(messages_route.router)
    app.dependency_overrides[get_db] = lambda: db_session

    from backend.app.models.character import Character
    from backend.app.schemas.conversation import ConversationCreate

    char = Character(name="swipe路由", personality="测试", first_mes="")
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    conv = conversation_service.create_conversation(
        db_session, ConversationCreate(character_id=char.id)
    )
    db_session.add(Message(conversation_id=conv.id, role=Role.ASSISTANT, content="原始"))
    db_session.commit()
    msg = db_session.query(Message).filter(Message.conversation_id == conv.id).first()
    message_service.add_swipe(db_session, msg.id, "候选A", make_active=False)
    message_service.add_swipe(db_session, msg.id, "候选B", make_active=False)

    with TestClient(app) as client:
        listed = client.get(f"/api/conversations/{conv.id}/messages")
        assert listed.status_code == 200
        item = listed.json()[0]
        assert item["swipes"] == ["原始", "候选A", "候选B"]
        assert item["active_swipe_index"] == 0
        assert item["content"] == "原始"  # active=0 → 原始

        switched = client.post(f"/api/messages/{msg.id}/switch-swipe", json={"index": 2})
        assert switched.status_code == 200
        body = switched.json()
        assert body["active_swipe_index"] == 2
        assert body["content"] == "候选B"  # content 跟随激活

        assert client.post(f"/api/messages/{msg.id}/switch-swipe", json={"index": 99}).status_code == 400


# ════════════════════════════════════════════════════════════════
# 六、自愈迁移幂等（spec §0：加列须附契约锁锁幂等）
# ════════════════════════════════════════════════════════════════


def test_migration_idempotent_on_legacy_db() -> None:
    """存量库（无 active_swipe_index 列）→ 迁移补列；连续两次调用幂等"""
    from sqlalchemy import create_engine, text

    engine = create_engine("sqlite://")
    with engine.connect() as conn:
        # 模拟存量库：messages 表不含 active_swipe_index（历史 schema 形态）
        conn.execute(text(
            "CREATE TABLE messages ("
            " id INTEGER PRIMARY KEY, conversation_id INTEGER NOT NULL,"
            " role VARCHAR(9) NOT NULL, content TEXT NOT NULL, created_at DATETIME)"
        ))
        conn.commit()

    from backend.app.database import _ensure_messages_active_swipe_index

    _ensure_messages_active_swipe_index(engine)  # 首次补列
    _ensure_messages_active_swipe_index(engine)  # 幂等：再跑无事

    with engine.connect() as conn:
        columns = {row[1] for row in conn.execute(text("PRAGMA table_info(messages)")).fetchall()}
        assert "active_swipe_index" in columns
        # 列类型/默认与 ORM 定义一致（INTEGER NOT NULL DEFAULT 0；PRAGMA 列序：type=2, notnull=3, dflt=4）
        row = next(r for r in conn.execute(text("PRAGMA table_info(messages)")).fetchall() if r[1] == "active_swipe_index")
        assert row[2] == "INTEGER" and row[3] == 1 and row[4] == "0"
        # 存量行默认 0
        conn.execute(text("INSERT INTO messages (id, conversation_id, role, content) VALUES (1, 1, 'user', 'x')"))
        conn.commit()
        assert conn.execute(text("SELECT active_swipe_index FROM messages WHERE id=1")).scalar() == 0


# ════════════════════════════════════════════════════════════════
# 八、append_swipe_and_bump 持久化仪式契约锁（F-124）
# ════════════════════════════════════════════════════════════════


def test_append_swipe_and_bump_appends_active_and_bumps_updated_at(
    db_session: Session,
) -> None:
    """追加候选并置激活 + bump 会话 updated_at + 返回刷新后 Message

    锁定「add_swipe → bump updated_at → commit → refresh」原子语义（F-124 收口）：
    候选 0 播种原始内容、新内容置激活、content/active_swipe_index 跟随、会话
    updated_at 确实 bump（排序置顶不变量）。
    """
    import datetime as _dt

    _, conv, msg = _setup(db_session)
    before = _dt.datetime(2000, 1, 1)
    conv.updated_at = before
    db_session.commit()

    result = message_service.append_swipe_and_bump(db_session, msg.id, "追加候选")

    # 返回刷新后的 Message：content 跟随激活候选、active_swipe_index 正确
    assert isinstance(result, Message)
    assert result.id == msg.id
    assert result.content == "追加候选"
    assert result.active_swipe_index == 1
    # 候选集：候选 0 = 原始内容播种，新候选 index 1
    swipes = message_service.list_swipes(db_session, msg.id)
    assert [s.index for s in swipes] == [0, 1]
    assert [s.content for s in swipes] == ["原始回复", "追加候选"]
    # 会话 updated_at 确实 bump（排序置顶不变量）
    db_session.refresh(conv)
    assert conv.updated_at > before


def test_append_swipe_and_bump_seeds_zero_and_idempotent_repeat(
    db_session: Session,
) -> None:
    """无既有候选时播种候选 0（原始内容）；重复调用幂等追加候选 1、2"""
    _, conv, msg = _setup(db_session)

    message_service.append_swipe_and_bump(db_session, msg.id, "候选一")
    message_service.append_swipe_and_bump(db_session, msg.id, "候选二")

    swipes = message_service.list_swipes(db_session, msg.id)
    assert [s.index for s in swipes] == [0, 1, 2]
    assert [s.content for s in swipes] == ["原始回复", "候选一", "候选二"]
    db_session.refresh(msg)
    assert msg.active_swipe_index == 2  # 最后一次 make_active 生效
    assert msg.content == "候选二"


def test_append_swipe_and_bump_make_active_false_keeps_content(
    db_session: Session,
) -> None:
    """make_active=False：追加候选但不改激活（content/active_swipe_index 不跟随）"""
    _, conv, msg = _setup(db_session)

    result = message_service.append_swipe_and_bump(
        db_session, msg.id, "候选一", make_active=False,
    )

    assert result.active_swipe_index == 0  # 未置激活
    assert result.content == "原始回复"  # content 不跟随
    assert [s.content for s in message_service.list_swipes(db_session, msg.id)] == [
        "原始回复",
        "候选一",
    ]


def test_append_swipe_and_bump_missing_message_raises(db_session: Session) -> None:
    """message_id 不存在 → MessageNotFoundError（add_swipe 守卫上抛，不落库）"""
    with pytest.raises(MessageNotFoundError):
        message_service.append_swipe_and_bump(db_session, 99999, "内容")
