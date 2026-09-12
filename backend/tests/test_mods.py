"""
MD-1 Mod 挂载层 — 契约测试

覆盖（验收语义契约，spec §MD-1）：
    1. 绑定唯一性（同角色同 Mod 不重复）
    2. 禁用绑定不参与叠加（零影响断言）
    3. sort_order 决定叠加顺序（含同序稳定排序）
    4. 解绑 / 删角色级联
    5. apply_prompt_mods 空 Mod 列表 → 输入原样返回（零变化）
    补充：CRUD 语义（create/list/update/delete）+ bind 自动 sort_order +
    404 守卫 + target_area 过滤 + payload 解析容错 + world→system 映射。
    补充（F-102 后端）：reorder_character_mods 批量重排原子契约（正常重排 /
    空列表 400 / 越界缺失 404 / 归属不符 404 / 重复 id / 角色不存在 404）。

依赖：pytest + SQLite 内存库（conftest.db_session）；级联语义测试手动开启
PRAGMA foreign_keys=ON（conftest 默认关，与 test_message_swipes 同模式）。
"""

from __future__ import annotations

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from backend.app.models.mods import Mod, ModBinding
from backend.app.schemas.mods import ModCreate, ModUpdate
from backend.app.services import mods as mods_service
from backend.app.services.exceptions import (
    CharacterNotFoundError,
    ModAlreadyBoundError,
    ModBindingNotFoundError,
    ModNotFoundError,
    ModReorderError,
)

__all__: list[str] = []


# ── 测试基础设施 ──


def _create_character(db: Session, name: str = "测试角色") -> int:
    """落库一个角色，返回 id"""
    from backend.app.models.character import Character

    char = Character(name=name, personality="冷静、睿智")
    db.add(char)
    db.commit()
    db.refresh(char)
    return char.id


def _create_mod(
    db: Session,
    *,
    name: str = "测试 Mod",
    target_area: str = "prompt",
    payload: str = "",
) -> Mod:
    """落库一个 Mod，返回 ORM 对象"""
    return mods_service.create_mod(
        db,
        ModCreate(name=name, target_area=target_area, payload=payload),
    )


def _prompt_payload(world: str = "", before_char: str = "", after_char: str = "") -> str:
    """构造 prompt 区 payload JSON 文本（三区域）"""
    import json

    return json.dumps(
        {"world": world, "before_char": before_char, "after_char": after_char},
        ensure_ascii=False,
    )


# ── 1. CRUD 语义 ──


class TestModCrud:
    def test_create_with_defaults(self, db_session: Session) -> None:
        """默认字段：prompt 区 / 空 payload / version 1.0 / source manual / 空描述"""
        mod = _create_mod(db_session, name="默认 Mod")
        assert mod.name == "默认 Mod"
        assert mod.description == ""
        assert mod.target_area == "prompt"
        assert mod.payload == ""
        assert mod.version == "1.0"
        assert mod.source == "manual"
        assert mod.id is not None

    def test_create_with_explicit_fields(self, db_session: Session) -> None:
        """显式字段全量落库"""
        mod = mods_service.create_mod(
            db_session,
            ModCreate(
                name="显式 Mod",
                description="说明文字",
                target_area="css",
                payload="body { color: red; }",
                version="2.3",
                source="imported",
            ),
        )
        assert mod.target_area == "css"
        assert mod.payload == "body { color: red; }"
        assert mod.version == "2.3"
        assert mod.source == "imported"

    def test_list_mods_id_asc(self, db_session: Session) -> None:
        """列表按 id 升序（确定性）"""
        _create_mod(db_session, name="A")
        _create_mod(db_session, name="B")
        names = [m.name for m in mods_service.list_mods(db_session)]
        assert names == ["A", "B"]

    def test_list_mods_empty(self, db_session: Session) -> None:
        """空库列表返回空"""
        assert mods_service.list_mods(db_session) == []

    def test_update_partial_skip_none(self, db_session: Session) -> None:
        """部分更新：仅提交显式字段，未提交字段原样保留；显式 None 跳过"""
        mod = _create_mod(db_session, name="原名")
        updated = mods_service.update_mod(
            db_session,
            mod.id,
            ModUpdate(name="新名", payload=None),  # payload 显式 None 视为未提供
        )
        assert updated.name == "新名"
        assert updated.payload == ""  # 原样保留（未被 None 毒化）

    def test_update_not_found(self, db_session: Session) -> None:
        """更新不存在的 Mod → ModNotFoundError"""
        import pytest

        with pytest.raises(ModNotFoundError):
            mods_service.update_mod(db_session, 9999, ModUpdate(name="x"))

    def test_delete_mod(self, db_session: Session) -> None:
        """删除 Mod；再删不存在 → ModNotFoundError"""
        import pytest

        mod = _create_mod(db_session)
        mods_service.delete_mod(db_session, mod.id)
        assert db_session.get(Mod, mod.id) is None
        with pytest.raises(ModNotFoundError):
            mods_service.delete_mod(db_session, mod.id)


# ── 2. 绑定（bind / unbind / toggle / list）──


class TestBinding:
    def test_bind_auto_sort_order(self, db_session: Session) -> None:
        """自动 sort_order：首个绑定 0，逐次 +1"""
        char_id = _create_character(db_session)
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        b1 = mods_service.bind_mod(db_session, char_id, m1.id)
        b2 = mods_service.bind_mod(db_session, char_id, m2.id)
        assert b1.sort_order == 0
        assert b2.sort_order == 1

    def test_bind_explicit_sort_order(self, db_session: Session) -> None:
        """显式 sort_order 覆盖自动值"""
        char_id = _create_character(db_session)
        mod = _create_mod(db_session)
        binding = mods_service.bind_mod(db_session, char_id, mod.id, sort_order=42)
        assert binding.sort_order == 42

    def test_bind_uniqueness(self, db_session: Session) -> None:
        """同角色同 Mod 重复绑定 → ModAlreadyBoundError（契约锁 1）"""
        import pytest

        char_id = _create_character(db_session)
        mod = _create_mod(db_session)
        mods_service.bind_mod(db_session, char_id, mod.id)
        with pytest.raises(ModAlreadyBoundError):
            mods_service.bind_mod(db_session, char_id, mod.id)

    def test_bind_unknown_character(self, db_session: Session) -> None:
        """绑定到不存在的角色 → CharacterNotFoundError"""
        import pytest

        mod = _create_mod(db_session)
        with pytest.raises(CharacterNotFoundError):
            mods_service.bind_mod(db_session, 9999, mod.id)

    def test_bind_unknown_mod(self, db_session: Session) -> None:
        """绑定不存在的 Mod → ModNotFoundError"""
        import pytest

        char_id = _create_character(db_session)
        with pytest.raises(ModNotFoundError):
            mods_service.bind_mod(db_session, char_id, 9999)

    def test_unbind(self, db_session: Session) -> None:
        """解绑单个绑定，其余保留（契约锁 4）"""
        import pytest

        char_id = _create_character(db_session)
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        b1 = mods_service.bind_mod(db_session, char_id, m1.id)
        b2 = mods_service.bind_mod(db_session, char_id, m2.id)

        mods_service.unbind_mod(db_session, b1.id)

        remain = mods_service.list_character_mods(db_session, char_id)
        assert [b.mod_id for b in remain] == [m2.id]
        assert db_session.get(ModBinding, b1.id) is None
        assert db_session.get(ModBinding, b2.id) is not None

    def test_unbind_not_found(self, db_session: Session) -> None:
        """解绑不存在的绑定 → ModBindingNotFoundError"""
        import pytest

        with pytest.raises(ModBindingNotFoundError):
            mods_service.unbind_mod(db_session, 9999)

    def test_set_binding_enabled_toggle(self, db_session: Session) -> None:
        """开关切换：enabled 翻转落库"""
        char_id = _create_character(db_session)
        mod = _create_mod(db_session)
        binding = mods_service.bind_mod(db_session, char_id, mod.id, enabled=True)

        off = mods_service.set_binding_enabled(db_session, binding.id, False)
        assert off.enabled is False
        on = mods_service.set_binding_enabled(db_session, binding.id, True)
        assert on.enabled is True

    def test_set_binding_enabled_not_found(self, db_session: Session) -> None:
        """切换不存在的绑定 → ModBindingNotFoundError"""
        import pytest

        with pytest.raises(ModBindingNotFoundError):
            mods_service.set_binding_enabled(db_session, 9999, True)

    def test_list_character_mods_sorted(self, db_session: Session) -> None:
        """按角色列出绑定，sort_order 升序 + 同序 mod_id 稳定"""
        char_id = _create_character(db_session)
        other_id = _create_character(db_session, name="另一角色")
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        m3 = _create_mod(db_session, name="M3")
        mods_service.bind_mod(db_session, char_id, m2.id, sort_order=0)
        mods_service.bind_mod(db_session, char_id, m1.id, sort_order=0)
        mods_service.bind_mod(db_session, char_id, m3.id, sort_order=1)
        # 另一角色的绑定不应混入
        mods_service.bind_mod(db_session, other_id, m1.id, sort_order=99)

        remain = mods_service.list_character_mods(db_session, char_id)
        # 同 sort_order=0 按 mod_id 升序 → m1, m2；再 sort_order=1 → m3
        assert [(b.mod_id, b.sort_order) for b in remain] == [
            (m1.id, 0),
            (m2.id, 0),
            (m3.id, 1),
        ]

    def test_delete_character_cascades_bindings(self, db_session: Session) -> None:
        """删角色级联删除其全部绑定（契约锁 4，PRAGMA foreign_keys=ON）"""
        db_session.execute(text("PRAGMA foreign_keys=ON"))
        char_id = _create_character(db_session)
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        mods_service.bind_mod(db_session, char_id, m1.id)
        mods_service.bind_mod(db_session, char_id, m2.id)

        from backend.app.models.character import Character

        char = db_session.get(Character, char_id)
        db_session.delete(char)
        db_session.commit()

        assert mods_service.list_character_mods(db_session, char_id) == []

    def test_delete_mod_cascades_bindings(self, db_session: Session) -> None:
        """删 Mod 级联删除其全部绑定（FK CASCADE）"""
        db_session.execute(text("PRAGMA foreign_keys=ON"))
        char_id = _create_character(db_session)
        mod = _create_mod(db_session, name="将被删的 Mod")
        mods_service.bind_mod(db_session, char_id, mod.id)

        mods_service.delete_mod(db_session, mod.id)

        assert db_session.get(ModBinding, 1) is None


# ── 3. apply_prompt_mods（纯函数）──


class TestApplyPromptMods:
    def test_empty_mod_list_returns_input_unchanged(self) -> None:
        """空 Mod 列表 → 输入原样返回（零变化，契约锁 5）"""
        base = {"system": ["已有"], "before_char": [], "after_char": ["尾"]}
        result = mods_service.apply_prompt_mods(base, [])
        assert result == base
        # 输入不被原地篡改（返回新 dict / 新列表）
        assert result is not base

    def test_disabled_binding_zero_effect(self) -> None:
        """禁用绑定不参与叠加（契约锁 2）"""
        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=1,
                target_area="prompt",
                payload=_prompt_payload(world="不该出现"),
                sort_order=0,
                enabled=False,
            )
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result == base

    def test_sort_order_decides_overlay_order(self) -> None:
        """sort_order 决定叠加顺序（契约锁 3）"""
        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=1, target_area="prompt",
                payload=_prompt_payload(world="晚"), sort_order=2, enabled=True,
            ),
            mods_service.ModPayload(
                mod_id=2, target_area="prompt",
                payload=_prompt_payload(world="早"), sort_order=0, enabled=True,
            ),
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result["system"] == ["早", "晚"]

    def test_equal_sort_order_stable_by_mod_id(self) -> None:
        """同 sort_order 按 mod_id 稳定排序（契约锁 3 稳定子断言）"""
        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=5, target_area="prompt",
                payload=_prompt_payload(world="B"), sort_order=0, enabled=True,
            ),
            mods_service.ModPayload(
                mod_id=3, target_area="prompt",
                payload=_prompt_payload(world="A"), sort_order=0, enabled=True,
            ),
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result["system"] == ["A", "B"]

    def test_three_regions_mapped(self) -> None:
        """三区域分别映射：world→system、before_char、after_char"""
        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=1,
                target_area="prompt",
                payload=_prompt_payload(world="W", before_char="B", after_char="A"),
                sort_order=0,
                enabled=True,
            )
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result["system"] == ["W"]
        assert result["before_char"] == ["B"]
        assert result["after_char"] == ["A"]

    def test_non_prompt_target_skipped(self) -> None:
        """memory / css 区 Mod 不参与 prompt 叠加"""
        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=1, target_area="css",
                payload=_prompt_payload(world="不该进 prompt"), sort_order=0, enabled=True,
            ),
            mods_service.ModPayload(
                mod_id=2, target_area="memory",
                payload=_prompt_payload(world="也不该进"), sort_order=0, enabled=True,
            ),
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result == base

    def test_region_value_non_str_skipped(self) -> None:
        """payload 区域值为非 str（数字/对象）→ 该区域容错跳过，不抛"""
        import json

        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=1, target_area="prompt",
                payload=json.dumps({"world": 123, "before_char": {"嵌套": True}, "after_char": "实"}),
                sort_order=0, enabled=True,
            )
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result["system"] == []
        assert result["before_char"] == []
        assert result["after_char"] == ["实"]

    def test_invalid_payload_json_skipped(self) -> None:
        """payload 非 JSON / 空 / 合法 JSON 但非 dict → 容错跳过，不抛"""
        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=1, target_area="prompt", payload="不是 JSON", sort_order=0, enabled=True,
            ),
            mods_service.ModPayload(
                mod_id=2, target_area="prompt", payload="", sort_order=0, enabled=True,
            ),
            mods_service.ModPayload(
                mod_id=3, target_area="prompt", payload='["world 区不是对象"]', sort_order=0, enabled=True,
            ),
            mods_service.ModPayload(
                mod_id=4, target_area="prompt", payload='"纯字符串"', sort_order=0, enabled=True,
            ),
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result == base

    def test_empty_region_content_skipped(self) -> None:
        """空/纯空白区域内容不产生注入条目"""
        base = {"system": [], "before_char": [], "after_char": []}
        mods = [
            mods_service.ModPayload(
                mod_id=1, target_area="prompt",
                payload=_prompt_payload(world="   ", before_char="", after_char="实"),
                sort_order=0, enabled=True,
            )
        ]
        result = mods_service.apply_prompt_mods(base, mods)
        assert result["system"] == []
        assert result["before_char"] == []
        assert result["after_char"] == ["实"]

    def test_does_not_mutate_input_lists(self) -> None:
        """输入 base_blocks 的列表不被就地修改"""
        base = {"system": ["原"], "before_char": [], "after_char": []}
        snapshot = list(base["system"])
        mods = [
            mods_service.ModPayload(
                mod_id=1, target_area="prompt",
                payload=_prompt_payload(world="新"), sort_order=0, enabled=True,
            )
        ]
        mods_service.apply_prompt_mods(base, mods)
        assert base["system"] == snapshot  # 原列表未被追加


# ── 4. reorder_character_mods（批量重排，F-102 后端）──


class TestReorderCharacterMods:
    """reorder_character_mods 服务层原子契约（spec §F-102）

    语义：ordered_binding_ids 必须恰好覆盖该角色全部绑定，逐条 sort_order =
    列表下标，一次 commit；任一校验失败整体不落库。
    """

    def test_reorder_persists_new_order(self, db_session: Session) -> None:
        """正常重排：sort_order = 列表下标持久化，列表按新序返回"""
        char_id = _create_character(db_session)
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        m3 = _create_mod(db_session, name="M3")
        b1 = mods_service.bind_mod(db_session, char_id, m1.id)  # sort_order=0
        b2 = mods_service.bind_mod(db_session, char_id, m2.id)  # sort_order=1
        b3 = mods_service.bind_mod(db_session, char_id, m3.id)  # sort_order=2

        result = mods_service.reorder_character_mods(
            db_session, char_id, [b3.id, b1.id, b2.id]
        )

        assert [b.mod_id for b in result] == [m3.id, m1.id, m2.id]
        assert [b.sort_order for b in result] == [0, 1, 2]

        persisted = mods_service.list_character_mods(db_session, char_id)
        assert [(b.mod_id, b.sort_order) for b in persisted] == [
            (m3.id, 0),
            (m1.id, 1),
            (m2.id, 2),
        ]

    def test_reorder_empty_list_rejected(self, db_session: Session) -> None:
        """空列表 → ModReorderError（400 明确拒绝，避免误清空）"""
        char_id = _create_character(db_session)
        mod = _create_mod(db_session)
        mods_service.bind_mod(db_session, char_id, mod.id)

        with pytest.raises(ModReorderError):
            mods_service.reorder_character_mods(db_session, char_id, [])

    def test_reorder_unknown_character(self, db_session: Session) -> None:
        """角色不存在 → CharacterNotFoundError"""
        with pytest.raises(CharacterNotFoundError):
            mods_service.reorder_character_mods(db_session, 9999, [1])

    def test_reorder_missing_binding(self, db_session: Session) -> None:
        """引用不存在的 binding_id → ModBindingNotFoundError"""
        char_id = _create_character(db_session)
        mod = _create_mod(db_session)
        mods_service.bind_mod(db_session, char_id, mod.id)

        with pytest.raises(ModBindingNotFoundError):
            mods_service.reorder_character_mods(db_session, char_id, [9999])

    def test_reorder_foreign_binding_rejected_atomically(self, db_session: Session) -> None:
        """混入他角色绑定 → ModBindingNotFoundError 且原顺序零改动（原子）"""
        char_id = _create_character(db_session)
        other_id = _create_character(db_session, name="另一角色")
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        b1 = mods_service.bind_mod(db_session, char_id, m1.id)  # sort_order=0
        mods_service.bind_mod(db_session, char_id, m2.id)  # sort_order=1
        foreign = mods_service.bind_mod(db_session, other_id, m1.id)  # 他角色

        with pytest.raises(ModBindingNotFoundError):
            mods_service.reorder_character_mods(
                db_session, char_id, [b1.id, foreign.id]
            )

        remained = mods_service.list_character_mods(db_session, char_id)
        assert [(b.mod_id, b.sort_order) for b in remained] == [
            (m1.id, 0),
            (m2.id, 1),
        ]

    def test_reorder_incomplete_coverage_rejected(self, db_session: Session) -> None:
        """缺失某绑定（未恰好覆盖）→ ModReorderError 且零改动"""
        char_id = _create_character(db_session)
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        b1 = mods_service.bind_mod(db_session, char_id, m1.id)  # sort_order=0
        mods_service.bind_mod(db_session, char_id, m2.id)  # sort_order=1

        with pytest.raises(ModReorderError):
            mods_service.reorder_character_mods(db_session, char_id, [b1.id])

        remained = mods_service.list_character_mods(db_session, char_id)
        assert [(b.mod_id, b.sort_order) for b in remained] == [
            (m1.id, 0),
            (m2.id, 1),
        ]

    def test_reorder_duplicate_id_rejected(self, db_session: Session) -> None:
        """重复 binding_id → ModReorderError（HTTP 层由 schema 422 拦截，服务层防御）"""
        char_id = _create_character(db_session)
        m1 = _create_mod(db_session, name="M1")
        m2 = _create_mod(db_session, name="M2")
        b1 = mods_service.bind_mod(db_session, char_id, m1.id)
        mods_service.bind_mod(db_session, char_id, m2.id)

        with pytest.raises(ModReorderError):
            mods_service.reorder_character_mods(db_session, char_id, [b1.id, b1.id])
