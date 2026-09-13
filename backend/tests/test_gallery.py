"""
CG-2 CG 资产库 + 画廊 — 契约测试

覆盖（验收语义契约，spec §CG-2）：
    1. 入库去重（同 url 同作品 → 返回既有，不重复入库）
    2. 解锁幂等（已解锁再调无副作用）
    3. 加权抽选（同种子可复现 + 顺序无关 + weight=0 永不抽中 + 权重分布）
    4. 分组过滤 / 解锁过滤 / 列表序（新品在前）
    5. 会话删除后图保留（SET NULL）/ 作品删除级联删图（CASCADE）
    6. 防御矩阵：未知角色 / 未知会话 / 消息不属于该会话 → 404 异常族

依赖：pytest + SQLite 内存库（conftest.db_session）；级联语义测试手动开启
PRAGMA foreign_keys=ON（conftest 默认关，与 test_message_swipes 同模式）。
"""

from __future__ import annotations

import random
from types import SimpleNamespace

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from backend.app.models.cg_image import CgImage
from backend.app.schemas.conversation import ConversationCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import gallery as gallery_service
from backend.app.services import message as message_service
from backend.app.services.exceptions import (
    CharacterNotFoundError,
    CgImageNotFoundError,
    ConversationNotFoundError,
    MessageNotFoundError,
)

__all__: list[str] = []

URL_A = "cg/cg_20260911_120000_001_512x512.png"


# ── 测试基础设施（与 test_branch_snapshot.py 同模式）──


def _create_character(db: Session, name: str = "测试角色") -> int:
    """落库一个角色，返回 id"""
    from backend.app.models.character import Character

    char = Character(name=name, personality="冷静、睿智")
    db.add(char)
    db.commit()
    db.refresh(char)
    return char.id


def _create_conversation(db: Session, character_id: int):
    """落库一个角色对话"""
    return conversation_service.create_conversation(
        db,
        ConversationCreate(character_id=character_id, model_provider="claude", model_name="claude-test"),
    )


def _add_message(db: Session, conversation_id: int, content: str = "问") -> int:
    """落库一条 user 消息，返回 id"""
    from backend.app.models.message import Role

    return message_service.create_message(db, conversation_id, Role.USER, content).id


# ── 1. add_cg（入库 + 去重 + 防御矩阵）──


class TestAddCg:
    """入库契约：默认字段 + 显式字段 + 幂等去重 + 404 守卫"""

    def test_add_with_defaults(self, db_session: Session) -> None:
        """默认字段：分组空串 / 未解锁 / 非特殊 / 无解锁提示"""
        char_id = _create_character(db_session)

        cg = gallery_service.add_cg(db_session, char_id, URL_A)

        assert isinstance(cg, CgImage)
        assert cg.character_id == char_id
        assert cg.url == URL_A
        assert cg.group_name == ""
        assert cg.unlocked is False
        assert cg.is_special is False
        assert cg.unlock_hint == ""
        assert cg.conversation_id is None
        assert cg.message_id is None

    def test_add_with_conversation_and_message(self, db_session: Session) -> None:
        """显式携带产出会话与消息（CG-3 出图链路的归属记录）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        msg_id = _add_message(db_session, conv.id)

        cg = gallery_service.add_cg(
            db_session, char_id, URL_A,
            conversation_id=conv.id, message_id=msg_id,
            group_name="名场面", unlock_hint="推进主线解锁",
        )

        assert cg.conversation_id == conv.id
        assert cg.message_id == msg_id
        assert cg.group_name == "名场面"
        assert cg.unlock_hint == "推进主线解锁"

    def test_add_dedup_same_url_same_character(self, db_session: Session) -> None:
        """核心契约 1：入库去重——同作品同 url 返回既有行，不产生重复"""
        char_id = _create_character(db_session)

        first = gallery_service.add_cg(db_session, char_id, URL_A)
        second = gallery_service.add_cg(db_session, char_id, URL_A)

        assert second.id == first.id
        assert db_session.query(CgImage).count() == 1

    def test_add_same_url_different_character_no_dedup(self, db_session: Session) -> None:
        """同 url 不同作品 → 各自入库（去重键 = 作品 + url）"""
        char_a = _create_character(db_session, name="角色A")
        char_b = _create_character(db_session, name="角色B")

        cg_a = gallery_service.add_cg(db_session, char_a, URL_A)
        cg_b = gallery_service.add_cg(db_session, char_b, URL_A)

        assert cg_a.id != cg_b.id
        assert db_session.query(CgImage).count() == 2

    def test_add_dedup_returns_existing_without_overwriting(self, db_session: Session) -> None:
        """重复入库不覆盖既有（unlock_hint 等字段保持首条值）"""
        char_id = _create_character(db_session)
        gallery_service.add_cg(db_session, char_id, URL_A, unlock_hint="首条提示")

        again = gallery_service.add_cg(db_session, char_id, URL_A, unlock_hint="后到提示")

        assert again.unlock_hint == "首条提示"

    def test_add_with_weight_unlocked_special(self, db_session: Session) -> None:
        """扩参契约（T1）：weight/unlocked/is_special 显式传参逐一落库"""
        char_id = _create_character(db_session)

        cg = gallery_service.add_cg(
            db_session, char_id, URL_A, weight=0, unlocked=True, is_special=True
        )

        assert cg.weight == 0
        assert cg.unlocked is True
        assert cg.is_special is True

    def test_add_weight_default_100(self, db_session: Session) -> None:
        """默认契约（T1）：不传新参数时 weight=100（与旧行为一致）"""
        char_id = _create_character(db_session)

        cg = gallery_service.add_cg(db_session, char_id, URL_A)

        assert cg.weight == 100

    def test_add_dedup_preserves_existing_weight(self, db_session: Session) -> None:
        """幂等去重不回退（T1）：同作品同 url 再调返回既有行，不改既有 weight"""
        char_id = _create_character(db_session)
        first = gallery_service.add_cg(db_session, char_id, URL_A, weight=7)

        again = gallery_service.add_cg(db_session, char_id, URL_A, weight=999)

        assert again.id == first.id
        assert again.weight == 7
        assert db_session.query(CgImage).count() == 1

    def test_add_unknown_character_404(self, db_session: Session) -> None:
        """未知作品 → CharacterNotFoundError"""
        with pytest.raises(CharacterNotFoundError):
            gallery_service.add_cg(db_session, 99999, URL_A)

    def test_add_unknown_conversation_404(self, db_session: Session) -> None:
        """未知会话 → ConversationNotFoundError"""
        char_id = _create_character(db_session)
        with pytest.raises(ConversationNotFoundError):
            gallery_service.add_cg(db_session, char_id, URL_A, conversation_id=99999)

    def test_add_message_not_in_conversation_404(self, db_session: Session) -> None:
        """消息不属于该会话 → MessageNotFoundError（不得错挂归属）"""
        char_id = _create_character(db_session)
        conv_a = _create_conversation(db_session, char_id)
        conv_b = _create_conversation(db_session, char_id)
        msg_a = _add_message(db_session, conv_a.id)

        with pytest.raises(MessageNotFoundError):
            gallery_service.add_cg(
                db_session, char_id, URL_A, conversation_id=conv_b.id, message_id=msg_a
            )


# ── 2. list_cg（过滤 + 排序）──


class TestListCg:
    """列表契约：角色隔离 / 分组过滤 / 解锁过滤 / 新品在前"""

    def _seed(self, db_session: Session) -> int:
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        msg_id = _add_message(db_session, conv.id)
        gallery_service.add_cg(db_session, char_id, f"{URL_A}1", conversation_id=conv.id, message_id=msg_id)
        gallery_service.add_cg(db_session, char_id, f"{URL_A}2", group_name="名场面")
        cg3 = gallery_service.add_cg(db_session, char_id, f"{URL_A}3", group_name="名场面")
        gallery_service.unlock_cg(db_session, cg3.id)
        return char_id

    def test_list_all_newest_first(self, db_session: Session) -> None:
        """全量列表新品在前（id 降序，确定性）"""
        char_id = self._seed(db_session)

        rows = gallery_service.list_cg(db_session, char_id)

        assert [r.url for r in rows] == [f"{URL_A}3", f"{URL_A}2", f"{URL_A}1"]

    def test_list_character_isolation(self, db_session: Session) -> None:
        """角色隔离：只返回该作品的图"""
        char_a = self._seed(db_session)
        char_b = _create_character(db_session, name="角色B")
        gallery_service.add_cg(db_session, char_b, f"{URL_A}b")

        assert len(gallery_service.list_cg(db_session, char_a)) == 3
        assert len(gallery_service.list_cg(db_session, char_b)) == 1

    def test_list_group_filter(self, db_session: Session) -> None:
        """分组过滤：仅该组；None = 不分"""
        char_id = self._seed(db_session)

        rows = gallery_service.list_cg(db_session, char_id, group_name="名场面")

        assert [r.url for r in rows] == [f"{URL_A}3", f"{URL_A}2"]

    def test_list_unlocked_only(self, db_session: Session) -> None:
        """解锁过滤：仅已解锁"""
        char_id = self._seed(db_session)

        rows = gallery_service.list_cg(db_session, char_id, unlocked_only=True)

        assert [r.url for r in rows] == [f"{URL_A}3"]


# ── 3. unlock_cg（解锁 + 幂等）──


class TestUnlockCg:
    """解锁契约：置 unlocked=True + 幂等 + 未知 404"""

    def test_unlock_sets_flag(self, db_session: Session) -> None:
        char_id = _create_character(db_session)
        cg = gallery_service.add_cg(db_session, char_id, URL_A)
        assert cg.unlocked is False

        unlocked = gallery_service.unlock_cg(db_session, cg.id)

        assert unlocked.id == cg.id
        assert unlocked.unlocked is True
        assert db_session.query(CgImage).filter(CgImage.id == cg.id).first().unlocked is True

    def test_unlock_idempotent(self, db_session: Session) -> None:
        """核心契约 2：解锁幂等——已解锁再调无副作用（返回同一行，flag 不变）"""
        char_id = _create_character(db_session)
        cg = gallery_service.add_cg(db_session, char_id, URL_A)
        gallery_service.unlock_cg(db_session, cg.id)

        again = gallery_service.unlock_cg(db_session, cg.id)

        assert again.id == cg.id
        assert again.unlocked is True
        assert db_session.query(CgImage).count() == 1

    def test_unlock_unknown_404(self, db_session: Session) -> None:
        """未知 CG → CgImageNotFoundError"""
        with pytest.raises(CgImageNotFoundError):
            gallery_service.unlock_cg(db_session, 99999)


# ── 4. pick_cg_by_weight（加权抽选）──


class _WeightedCg(SimpleNamespace):
    """带 weight 的候选（duck-typed 契约：pick 只读 .id / .weight）"""

    def __init__(self, cg_id: int, weight: int = 1):
        super().__init__(id=cg_id, weight=weight)


class TestPickCgByWeight:
    """加权抽选契约：可复现 / 顺序无关 / 零权重永弃 / 权重分布"""

    def test_empty_candidates_returns_none(self) -> None:
        assert gallery_service.pick_cg_by_weight([]) is None

    def test_zero_total_weight_returns_none(self) -> None:
        """总权重为 0（全部 zero-weight）→ None（无可抽）"""
        candidates = [_WeightedCg(1, 0), _WeightedCg(2, 0)]
        assert gallery_service.pick_cg_by_weight(candidates, rng=random.Random(1)) is None

    def test_weight_zero_never_picked(self) -> None:
        """weight=0 永不抽中（即使传入顺序靠前）"""
        candidates = [_WeightedCg(1, 0), _WeightedCg(2, 1)]
        picked = {gallery_service.pick_cg_by_weight(candidates, rng=random.Random(seed)).id for seed in range(50)}
        assert 1 not in picked
        assert picked == {2}

    def test_same_seed_reproducible_across_input_order(self) -> None:
        """核心契约 3a：同种子可复现 + 不随输入顺序变化（RNG 消耗序列跟随规范化序）"""
        candidates = [_WeightedCg(i, weight=(i % 3) + 1) for i in range(5)]

        base = gallery_service.pick_cg_by_weight(candidates, rng=random.Random(42))
        reversed_pick = gallery_service.pick_cg_by_weight(list(reversed(candidates)), rng=random.Random(42))
        shuffled = gallery_service.pick_cg_by_weight(
            random.Random(7).sample(candidates, len(candidates)), rng=random.Random(42)
        )

        assert base.id == reversed_pick.id
        assert base.id == shuffled.id

    def test_uniform_without_weight_attr(self) -> None:
        """无 weight 属性 → 均权（任意候选都可能被抽中，同种子可复现）"""
        from backend.app.models.cg_image import CgImage

        candidates = [SimpleNamespace(id=i) for i in range(3)]  # 无 weight → 1
        assert isinstance(candidates[0], SimpleNamespace)
        # 无 weight 属性时按均权处理（与 CgImage ORM 行同形态）
        picks = {gallery_service.pick_cg_by_weight(candidates, rng=random.Random(seed)).id for seed in range(30)}
        assert picks <= {0, 1, 2}
        assert gallery_service.pick_cg_by_weight(candidates, rng=random.Random(5)).id == \
            gallery_service.pick_cg_by_weight(candidates, rng=random.Random(5)).id

    def test_weighted_distribution(self) -> None:
        """核心契约 3b：权重分布——2 倍权重候选在多轮抽选后显著更常被选中"""
        candidates = [_WeightedCg(1, 1), _WeightedCg(2, 1), _WeightedCg(3, 2)]
        counts = {1: 0, 2: 0, 3: 0}
        for i in range(2000):
            picked = gallery_service.pick_cg_by_weight(candidates, rng=random.Random(i))
            counts[picked.id] += 1

        # 期望：候选 3（weight=2/4=50%）≈1000 次；候选 1/2（各 25%）≈500 次
        assert counts[3] > counts[1] + 200
        assert counts[3] > counts[2] + 200

    def test_single_candidate_always_picked(self) -> None:
        candidates = [_WeightedCg(7)]
        for seed in range(10):
            assert gallery_service.pick_cg_by_weight(candidates, rng=random.Random(seed)).id == 7


# ── 5. 级联 / SET NULL 生命周期 ──


class TestCgImageLifecycle:
    """会话删除后图保留（SET NULL）/ 作品删除级联删图（CASCADE）——PRAGMA ON"""

    def test_delete_conversation_sets_null_and_image_survives(self, db_session: Session) -> None:
        """核心契约 5：删除产出会话 → CG 保留，conversation_id/message_id 置 NULL"""
        db_session.execute(text("PRAGMA foreign_keys=ON"))
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        msg_id = _add_message(db_session, conv.id)
        cg = gallery_service.add_cg(
            db_session, char_id, URL_A, conversation_id=conv.id, message_id=msg_id
        )
        assert cg.conversation_id == conv.id

        conversation_service.delete_conversation(db_session, conv.id)

        db_session.expire_all()
        survivor = db_session.query(CgImage).filter(CgImage.id == cg.id).first()
        assert survivor is not None  # 图保留
        assert survivor.conversation_id is None
        assert survivor.message_id is None
        assert survivor.character_id == char_id

    def test_delete_source_character_cascades(self, db_session: Session) -> None:
        """删除作品 → CG 级联删除（CASCADE）"""
        from backend.app.models.character import Character

        db_session.execute(text("PRAGMA foreign_keys=ON"))
        char_id = _create_character(db_session)
        gallery_service.add_cg(db_session, char_id, URL_A)

        char = db_session.query(Character).filter(Character.id == char_id).first()
        db_session.delete(char)
        db_session.commit()

        assert db_session.query(CgImage).count() == 0


# ── 6. 自愈迁移（T1：cg_images.weight 列；spec §0 加列须附幂等契约锁）──


def test_cg_weight_migration_on_legacy_db() -> None:
    """存量库（无 weight 列）→ 迁移补列，存量行 weight=100；连续两次调用幂等"""
    from sqlalchemy import create_engine, text

    engine = create_engine("sqlite://")
    with engine.connect() as conn:
        # 模拟存量库：cg_images 不含 weight（历史 schema 形态），且已有存量行
        conn.execute(text(
            "CREATE TABLE cg_images ("
            " id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL,"
            " conversation_id INTEGER, message_id INTEGER, url TEXT NOT NULL,"
            " group_name VARCHAR(100), is_special BOOLEAN, unlocked BOOLEAN,"
            " unlock_hint TEXT, created_at DATETIME)"
        ))
        conn.execute(text("INSERT INTO cg_images (character_id, url) VALUES (1, 'legacy.png')"))
        conn.commit()

    from backend.app.database import _ensure_cg_images_weight

    _ensure_cg_images_weight(engine)  # 首次补列
    _ensure_cg_images_weight(engine)  # 幂等：再跑无事

    with engine.connect() as conn:
        info = conn.execute(text("PRAGMA table_info(cg_images)")).fetchall()
        columns = {row[1] for row in info}
        assert "weight" in columns
        # 列类型/约束与 ORM 定义一致（INTEGER NOT NULL DEFAULT 100；PRAGMA 列序：type=2, notnull=3, dflt=4）
        col = next(r for r in info if r[1] == "weight")
        assert col[2] == "INTEGER" and col[3] == 1 and col[4] == "100"
        # 存量行补默认 100
        legacy_weight = conn.execute(
            text("SELECT weight FROM cg_images WHERE url='legacy.png'")
        ).scalar()
        assert legacy_weight == 100


def test_init_db_wires_cg_weight_migration(tmp_path, monkeypatch) -> None:
    """init_db 接线锁（T1）：init_db 调用链触发 weight 自愈迁移（接线不脱落）"""
    import backend.app.database as database_mod
    from sqlalchemy import create_engine, text

    engine = create_engine(f"sqlite:///{tmp_path / 'wiring.db'}")
    with engine.connect() as conn:
        # 预置存量形态：cg_images 无 weight（create_all 不会给已存在表加列）
        conn.execute(text(
            "CREATE TABLE cg_images ("
            " id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL,"
            " conversation_id INTEGER, message_id INTEGER, url TEXT NOT NULL,"
            " group_name VARCHAR(100), is_special BOOLEAN, unlocked BOOLEAN,"
            " unlock_hint TEXT, created_at DATETIME)"
        ))
        conn.commit()

    monkeypatch.setattr(database_mod, "engine", engine)
    database_mod.init_db()

    with engine.connect() as conn:
        columns = {row[1] for row in conn.execute(text("PRAGMA table_info(cg_images)")).fetchall()}
        assert "weight" in columns

def test_cg_weight_migration_concurrent_no_duplicate_crash(tmp_path) -> None:
    """并发迁移 Falsify（T1）：竞态窗口——conn1 持过期探测快照（他方连接已抢先
    补列并提交）再执行 ALTER → duplicate column；实现须吞该错视为「他方已补齐」，
    不得崩溃。过期快照用透传代理确定性复现（真两连接的 PRAGMA/ALTER 时序在
    单机测试中不可稳定交错——原版直接传 Connection 反而是守卫不触发的伪测试，
    突变验证 #2 揭示后重写）"""
    from sqlalchemy import create_engine

    from backend.app.database import _ensure_cg_images_weight

    engine = create_engine(f"sqlite:///{tmp_path / 'race.db'}")
    with engine.connect() as conn:
        conn.execute(text(
            "CREATE TABLE cg_images ("
            " id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL,"
            " conversation_id INTEGER, message_id INTEGER, url TEXT NOT NULL,"
            " group_name VARCHAR(100), is_special BOOLEAN, unlocked BOOLEAN,"
            " unlock_hint TEXT, created_at DATETIME)"
        ))
        conn.commit()

    conn1 = engine.connect()
    try:
        # 他方连接抢先补列并提交（竞态的「他方」半边，真实 DDL）
        conn1.execute(text(
            "ALTER TABLE cg_images ADD COLUMN weight INTEGER NOT NULL DEFAULT 100"
        ))
        conn1.commit()

        class _StaleProbeResult:
            """过期探测快照：PRAGMA table_info 返回空（看不见 weight），其余透传"""

            def fetchall(self) -> list:
                return []

        class _StaleProbeConn:
            """竞态窗口模拟：探测命中过期快照，ALTER 落在真实连接上（撞 duplicate column）"""

            def __init__(self, real) -> None:
                self._real = real

            def execute(self, stmt, *args, **kwargs):
                result = self._real.execute(stmt, *args, **kwargs)
                if "table_info" in str(stmt):
                    return _StaleProbeResult()
                return result

            def commit(self) -> None:
                self._real.commit()

            def rollback(self) -> None:
                self._real.rollback()

        _ensure_cg_images_weight(_StaleProbeConn(conn1))  # 不得抛 duplicate column

        columns = {row[1] for row in conn1.execute(text("PRAGMA table_info(cg_images)"))}
        assert "weight" in columns
    finally:
        conn1.close()


def test_add_weight_negative_roundtrip(db_session: Session) -> None:
    """Falsify（T1）：weight 负数不崩溃、原样落库——数据层无 CHECK 约束，
    「永不抽中/过滤」语义由调用方门槛（T6：weight>0 候选过滤）保证"""
    char_id = _create_character(db_session)

    cg = gallery_service.add_cg(db_session, char_id, URL_A, weight=-5)

    db_session.expire(cg)
    assert cg.weight == -5


def test_add_weight_none_falls_back_to_column_default(db_session: Session) -> None:
    """Falsify（T1）：weight=None 不崩、不写 NULL——SQLAlchemy 对带 Python 端
    default 的列，INSERT 时 None 回退列默认 100（NOT NULL 约束无被破坏面）"""
    char_id = _create_character(db_session)

    cg = gallery_service.add_cg(db_session, char_id, URL_A, weight=None)  # type: ignore[arg-type]

    assert cg.weight == 100


# ── 7. CG 路由三件套（T2：录入 / 解锁 / 全量列表；镜像 test_mods_routes.py 形态：
#     真实路由 + 统一异常处理器最小应用，get_db 覆盖为内存会话；路由零 ORM 契约）──

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from backend.app.api.errors import domain_error_handler  # noqa: E402
from backend.app.api.routes import images as images_route  # noqa: E402
from backend.app.database import get_db  # noqa: E402
from backend.app.services.exceptions import DomainError  # noqa: E402


@pytest.fixture
def cg_wire_app(db_session: Session) -> FastAPI:
    """CG 三端点真实路由 + 统一 handler 的最小应用（get_db 覆盖为内存会话）"""
    app = FastAPI()
    app.add_exception_handler(DomainError, domain_error_handler)
    app.include_router(images_route.router)
    app.dependency_overrides[get_db] = lambda: db_session
    return app


class TestCgCreateRoute:
    """POST /api/characters/{character_id}/cg（T2 录入端点契约）"""

    def test_create_201_default_locked_and_passthrough(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """合法 body → 201；unlocked 恒 False（不收 unlocked 字段）；
        weight/unlock_hint/is_special/group_name 逐一透传落库（T1 扩参消费验证）"""
        char_id = _create_character(db_session)

        with TestClient(cg_wire_app) as client:
            resp = client.post(
                f"/api/characters/{char_id}/cg",
                json={
                    "url": URL_A,
                    "group_name": "第一章",
                    "weight": 250,
                    "unlock_hint": "通关第一章后解锁",
                    "is_special": True,
                },
            )

        assert resp.status_code == 201
        body = resp.json()
        assert body["character_id"] == char_id
        assert body["url"] == URL_A
        assert body["group_name"] == "第一章"
        assert body["weight"] == 250
        assert body["unlock_hint"] == "通关第一章后解锁"
        assert body["is_special"] is True
        # 初始默认锁定：端点不收 unlocked 字段，恒 False
        assert body["unlocked"] is False
        # 落库一致性：响应即 DB 行（id 可回查）
        row = db_session.query(CgImage).filter(CgImage.id == body["id"]).one()
        assert row.unlocked is False
        assert row.weight == 250

    def test_create_defaults_weight_100_and_empty_group(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """仅传 url（其余缺省）→ weight=100、group_name=""、hint=""、is_special=False"""
        char_id = _create_character(db_session)

        with TestClient(cg_wire_app) as client:
            resp = client.post(f"/api/characters/{char_id}/cg", json={"url": URL_A})

        assert resp.status_code == 201
        body = resp.json()
        assert body["weight"] == 100
        assert body["group_name"] == ""
        assert body["unlock_hint"] == ""
        assert body["is_special"] is False

    def test_create_same_url_idempotent_no_duplicate(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """add_cg 既有幂等去重语义经路由不破坏：同作品同 url 二次录入 → 同一行"""
        char_id = _create_character(db_session)

        with TestClient(cg_wire_app) as client:
            first = client.post(f"/api/characters/{char_id}/cg", json={"url": URL_A})
            second = client.post(f"/api/characters/{char_id}/cg", json={"url": URL_A})

        assert first.status_code == 201
        assert second.status_code == 201
        assert second.json()["id"] == first.json()["id"]
        assert len(gallery_service.list_cg(db_session, char_id)) == 1

    def test_create_unknown_character_404(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """角色不存在 → 404（CharacterNotFoundError 经统一 handler 映射）"""
        with TestClient(cg_wire_app) as client:
            resp = client.post("/api/characters/99999/cg", json={"url": URL_A})

        assert resp.status_code == 404

    def test_create_422_matrix(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """Falsify 矩阵：url 空串 / url 非字符串 / weight<0 / weight=None /
        body 缺 url → 一律 422（pydantic 校验，min_length=1 / ge=0 / 必填）"""
        char_id = _create_character(db_session)
        cases: list[dict] = [
            {"url": ""},
            {"url": 123},
            {"url": URL_A, "weight": -1},
            {"url": URL_A, "weight": None},
            {},
        ]

        with TestClient(cg_wire_app) as client:
            for payload in cases:
                resp = client.post(f"/api/characters/{char_id}/cg", json=payload)
                assert resp.status_code == 422, f"payload={payload} → {resp.status_code}"

        # 422 拒绝路径零副作用：未产生任何 CG 行
        assert gallery_service.list_cg(db_session, char_id) == []


class TestCgUnlockRoute:
    """POST /api/cg/{cg_id}/unlock（T2 解锁端点契约）"""

    def test_unlock_200_sets_unlocked(self, db_session: Session, cg_wire_app: FastAPI) -> None:
        """锁定 CG 调用后 unlocked=True，响应即解锁后的行"""
        char_id = _create_character(db_session)
        cg = gallery_service.add_cg(db_session, char_id, URL_A)

        with TestClient(cg_wire_app) as client:
            resp = client.post(f"/api/cg/{cg.id}/unlock")

        assert resp.status_code == 200
        body = resp.json()
        assert body["id"] == cg.id
        assert body["unlocked"] is True

    def test_unlock_idempotent_repeat(self, db_session: Session, cg_wire_app: FastAPI) -> None:
        """幂等：已解锁再调返回同一行（同 id、unlocked 仍 True、无新行）"""
        char_id = _create_character(db_session)
        cg = gallery_service.add_cg(db_session, char_id, URL_A)

        with TestClient(cg_wire_app) as client:
            first = client.post(f"/api/cg/{cg.id}/unlock")
            second = client.post(f"/api/cg/{cg.id}/unlock")

        assert first.status_code == 200
        assert second.status_code == 200
        assert second.json()["id"] == first.json()["id"]
        assert second.json()["unlocked"] is True
        assert len(gallery_service.list_cg(db_session, char_id)) == 1

    def test_unlock_unknown_cg_404(self, db_session: Session, cg_wire_app: FastAPI) -> None:
        """不存在 id → 404（CgImageNotFoundError 经统一 handler 映射）"""
        with TestClient(cg_wire_app) as client:
            resp = client.post("/api/cg/99999/unlock")

        assert resp.status_code == 404


class TestCgListRoute:
    """GET /api/characters/{character_id}/cg（T2 全量列表端点契约）"""

    def test_list_desc_includes_locked(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """全量含未解锁，id 降序（新品在前，与画廊网格排序契约一致）"""
        char_id = _create_character(db_session)
        ids = [
            gallery_service.add_cg(db_session, char_id, f"cg/pic_{i}.png").id
            for i in range(3)
        ]

        with TestClient(cg_wire_app) as client:
            resp = client.get(f"/api/characters/{char_id}/cg")

        assert resp.status_code == 200
        body = resp.json()
        assert [item["id"] for item in body] == sorted(ids, reverse=True)
        # 含未解锁（列表不做解锁过滤——画廊灰态消费 unlock_hint）
        assert all(item["unlocked"] is False for item in body)

    def test_list_empty_character_returns_empty_array(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """无 CG 角色 → 200 与空数组 []"""
        char_id = _create_character(db_session)

        with TestClient(cg_wire_app) as client:
            resp = client.get(f"/api/characters/{char_id}/cg")

        assert resp.status_code == 200
        assert resp.json() == []

    def test_list_unknown_character_404(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """角色不存在 → 404（require_character → 统一 handler）"""
        with TestClient(cg_wire_app) as client:
            resp = client.get("/api/characters/99999/cg")

        assert resp.status_code == 404

    def test_list_filters_group_name_and_unlocked_only(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """可选查询参数过滤：group_name 精确匹配 / unlocked_only 仅已解锁（默认全量）"""
        char_id = _create_character(db_session)
        gallery_service.add_cg(db_session, char_id, "cg/a.png", group_name="第一章")
        gallery_service.add_cg(db_session, char_id, "cg/b.png", group_name="第二章")
        gallery_service.add_cg(db_session, char_id, "cg/c.png", group_name="第一章")

        with TestClient(cg_wire_app) as client:
            by_group = client.get(
                f"/api/characters/{char_id}/cg", params={"group_name": "第一章"}
            )
            unlocked_only = client.get(
                f"/api/characters/{char_id}/cg", params={"unlocked_only": "true"}
            )

        # group_name 过滤：仅第一章 2 张，id 降序
        assert by_group.status_code == 200
        assert [item["url"] for item in by_group.json()] == ["cg/c.png", "cg/a.png"]
        # unlocked_only 过滤：全部锁定 → 空
        assert unlocked_only.status_code == 200
        assert unlocked_only.json() == []

    def test_list_cross_character_isolation(
        self, db_session: Session, cg_wire_app: FastAPI
    ) -> None:
        """角色隔离：角色 A 的列表请求碰不到角色 B 的 CG（id 枚举别的角色资产不可见）"""
        char_a = _create_character(db_session, name="角色 A")
        char_b = _create_character(db_session, name="角色 B")
        gallery_service.add_cg(db_session, char_a, "cg/a_only.png")
        gallery_service.add_cg(db_session, char_b, "cg/b_only.png")

        with TestClient(cg_wire_app) as client:
            resp_a = client.get(f"/api/characters/{char_a}/cg")
            resp_b = client.get(f"/api/characters/{char_b}/cg")

        assert [item["url"] for item in resp_a.json()] == ["cg/a_only.png"]
        assert [item["url"] for item in resp_b.json()] == ["cg/b_only.png"]
