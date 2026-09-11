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