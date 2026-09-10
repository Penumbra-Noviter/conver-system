"""
世界书条目仓库层契约锁（WL-1）

锁定语义（docs/chat-simulator-upgrade-spec.md §WL-1，二选一处取「拒」）：
- keys 必须为 JSON 数组（非 list 输入被拒）；空 keys 允许（constant 场景）
- order/probability/depth/group_weight 越界 → pydantic 校验拒绝（拒，非裁剪）
- character_id 级联删除条目（DB 级 ON DELETE CASCADE，需启用 FK pragma）
- replace_entries 幂等（连续两次调用结果一致）
- parse_character_book：ST character_book 结构 → 条目字段一一对应
- 既有 character_card character_book 保真零回归（转换层不受本工单影响）
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError
from sqlalchemy import text

from backend.app.models.character import Character
from backend.app.schemas.lorebook import LorebookEntryCreate, LorebookEntryUpdate
from backend.app.services import lorebook as lorebook_service
from backend.app.services.character_card import from_v2_card, to_v2_card
from backend.app.services.exceptions import CharacterNotFoundError, LorebookEntryNotFoundError

__all__: list[str] = []


@pytest.fixture(autouse=True)
def _enable_fk(db_session) -> None:
    """本文件契约含 DB 级级联：启用 FK pragma（conftest 测试引擎默认关闭）"""
    db_session.execute(text("PRAGMA foreign_keys=ON"))


def _persist(db_session, make_character, **overrides: object) -> Character:
    """make_character 工厂产物落库（返回带 id 的 ORM 角色）"""
    char = make_character(**overrides)
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char


# ════════════════════════════════════════════════════════════════
# 一、Schema 契约：keys 数组 / 越界拒绝
# ════════════════════════════════════════════════════════════════


def test_keys_must_be_list_and_empty_allowed() -> None:
    """keys 非 list 被拒；空 keys 允许（constant 场景）"""
    with pytest.raises(ValidationError):
        LorebookEntryCreate(keys="关键字")  # 非 list 输入
    entry = LorebookEntryCreate(keys=[], constant=True)
    assert entry.keys == []
    assert entry.constant is True


@pytest.mark.parametrize(
    "field, bad_value",
    [
        ("order", -1),
        ("order", 10000),
        ("probability", 0),
        ("probability", 101),
        ("depth", -1),
        ("depth", 21),
        ("group_weight", 0),
        ("group_weight", 101),
    ],
)
def test_bounds_rejected(field: str, bad_value: int) -> None:
    """order/probability/depth/group_weight 越界 → 校验拒绝（锁定「拒」语义）"""
    with pytest.raises(ValidationError):
        LorebookEntryCreate(**{field: bad_value})


# ════════════════════════════════════════════════════════════════
# 二、仓库层 CRUD
# ════════════════════════════════════════════════════════════════


def test_create_and_list_sorted(db_session, make_character) -> None:
    """create → list：order 升序、同 order 按 id 升序（确定性排序契约）"""
    char = _persist(db_session, make_character)
    entry_b = lorebook_service.create_entry(db_session, char.id, LorebookEntryCreate(title="B", order=200))
    entry_a = lorebook_service.create_entry(db_session, char.id, LorebookEntryCreate(title="A", order=100))
    lorebook_service.create_entry(db_session, char.id, LorebookEntryCreate(title="C", order=100))

    entries = lorebook_service.list_entries(db_session, char.id)
    assert [e.title for e in entries] == ["A", "C", "B"]  # A/C 同 order → id 升序
    assert entries[0].id == entry_a.id
    assert entries[1].id > entry_a.id
    assert entries[2].id == entry_b.id
    assert entries[2].keys == []  # keys 落库/读回为 JSON 数组


def test_create_missing_character_raises(db_session) -> None:
    """创建时角色不存在 → CharacterNotFoundError（防 FK 违例 500）"""
    with pytest.raises(CharacterNotFoundError):
        lorebook_service.create_entry(db_session, 99999, LorebookEntryCreate())


def test_update_partial(db_session, make_character) -> None:
    """部分更新：仅提交显式字段，其余原样保留"""
    char = _persist(db_session, make_character)
    entry = lorebook_service.create_entry(db_session, char.id, LorebookEntryCreate(title="旧", content="c", order=5))
    updated = lorebook_service.update_entry(db_session, entry.id, LorebookEntryUpdate(content="新内容", enabled=False))
    assert updated.content == "新内容"
    assert updated.enabled is False
    assert updated.title == "旧"
    assert updated.order == 5


def test_update_missing_raises(db_session) -> None:
    """更新不存在的条目 → LorebookEntryNotFoundError"""
    with pytest.raises(LorebookEntryNotFoundError):
        lorebook_service.update_entry(db_session, 99999, LorebookEntryUpdate(title="x"))


def test_delete(db_session, make_character) -> None:
    """删除后列表为空"""
    char = _persist(db_session, make_character)
    entry = lorebook_service.create_entry(db_session, char.id, LorebookEntryCreate())
    lorebook_service.delete_entry(db_session, entry.id)
    assert lorebook_service.list_entries(db_session, char.id) == []


def test_delete_missing_raises(db_session) -> None:
    """删除不存在的条目 → LorebookEntryNotFoundError"""
    with pytest.raises(LorebookEntryNotFoundError):
        lorebook_service.delete_entry(db_session, 99999)


# ════════════════════════════════════════════════════════════════
# 三、级联与替换
# ════════════════════════════════════════════════════════════════


def test_cascade_delete_on_character(db_session, make_character) -> None:
    """删角色 → 世界书条目级联删除（DB 级 FK CASCADE）"""
    char = _persist(db_session, make_character)
    lorebook_service.create_entry(db_session, char.id, LorebookEntryCreate(title="条目1"))
    lorebook_service.create_entry(db_session, char.id, LorebookEntryCreate(title="条目2"))
    assert len(lorebook_service.list_entries(db_session, char.id)) == 2

    db_session.delete(char)
    db_session.commit()

    assert lorebook_service.list_entries(db_session, char.id) == []
    count = db_session.execute(text("SELECT COUNT(*) FROM lorebook_entries")).scalar()
    assert count == 0  # 表内无残留行


def test_replace_entries_idempotent(db_session, make_character) -> None:
    """replace_entries 幂等：连续两次调用结果一致（先删后插）"""
    char = _persist(db_session, make_character)
    entries = [
        LorebookEntryCreate(title="A", keys=["x"], content="a"),
        LorebookEntryCreate(title="B", keys=["y"], content="b"),
    ]

    n1 = lorebook_service.replace_entries(db_session, char.id, entries)
    first = lorebook_service.list_entries(db_session, char.id)
    n2 = lorebook_service.replace_entries(db_session, char.id, entries)
    second = lorebook_service.list_entries(db_session, char.id)

    assert n1 == 2 and n2 == 2
    assert [(e.title, e.keys, e.content) for e in first] == [
        (e.title, e.keys, e.content) for e in second
    ]
    # 首次调用同时清空既有条目（先删后插语义）
    assert {e.title for e in first} == {"A", "B"}


def test_replace_missing_character_raises(db_session) -> None:
    """替换时角色不存在 → CharacterNotFoundError"""
    with pytest.raises(CharacterNotFoundError):
        lorebook_service.replace_entries(db_session, 99999, [])


# ════════════════════════════════════════════════════════════════
# 四、parse_character_book（ST 结构 → 条目草案）
# ════════════════════════════════════════════════════════════════


def test_parse_character_book_structure() -> None:
    """ST character_book 结构 → 条目字段一一对应（keys/content/constant/order/probability/group）"""
    book = {
        "name": "测试世界书",
        "description": "用于契约锁的 ST 结构",
        "entries": [
            {
                "keys": ["酒馆", "tavern"],
                "content": "酒馆的老板是莉莉，她认识每一个常客。",
                "constant": False,
                "insertion_order": 55,
                "probability": 80,
                "group": "地点",
                "group_weight": 30,
                "position": "before_char",
                "depth": 4,
                "enabled": True,
                "name": "酒馆",
            }
        ],
    }
    drafts = lorebook_service.parse_character_book(book)
    assert len(drafts) == 1
    d = drafts[0]
    assert d.keys == ["酒馆", "tavern"]
    assert d.content == "酒馆的老板是莉莉，她认识每一个常客。"
    assert d.constant is False
    assert d.order == 55
    assert d.probability == 80
    assert d.group_name == "地点"
    assert d.group_weight == 30
    assert d.position == "before_char"
    assert d.depth == 4
    assert d.source == "manual"
    assert d.enabled is True
    assert d.match_mode == "or"


def test_parse_character_book_selective_to_and() -> None:
    """ST selective + secondary_keys → match_mode=and；否则 or"""
    book_and = {
        "entries": [
            {"keys": ["a"], "secondary_keys": ["b"], "selective": True},
        ]
    }
    assert lorebook_service.parse_character_book(book_and)[0].match_mode == "and"
    book_or = {"entries": [{"keys": ["a"], "selective": False}]}
    assert lorebook_service.parse_character_book(book_or)[0].match_mode == "or"


def test_parse_character_book_tolerant() -> None:
    """脏数据容错：非 dict entry 跳过、非 list entries → 空、越界数值裁剪、position 回落"""
    assert lorebook_service.parse_character_book(None) == []
    assert lorebook_service.parse_character_book("oops") == []
    assert lorebook_service.parse_character_book({"entries": "oops"}) == []

    drafts = lorebook_service.parse_character_book(
        {
            "entries": [
                42,  # 非 dict entry → 跳过
                {
                    "keys": "单串",  # 非 list → 单值包裹
                    "insertion_order": 99999,
                    "probability": 0,
                    "depth": 99,
                    "group_weight": 0,
                    "position": "in_chat",  # 本模型不承载 → world
                },
            ]
        }
    )
    assert len(drafts) == 1
    d = drafts[0]
    assert d.keys == ["单串"]
    assert d.order == 9999  # 解析层裁剪（API 层拒绝）
    assert d.probability == 1
    assert d.depth == 20
    assert d.group_weight == 1
    assert d.position == "world"


# ════════════════════════════════════════════════════════════════
# 五、既有 character_book 保真零回归
# ════════════════════════════════════════════════════════════════


def test_character_book_roundtrip_unchanged(db_session, make_character) -> None:
    """character_card 转换层 character_book 保真契约不受本工单影响"""
    char = _persist(
        db_session,
        make_character,
        extensions={"conver_system": {"character_book": {"entries": [1, 2]}}},
    )
    card = to_v2_card(char)
    assert card["data"]["extensions"]["conver_system"]["character_book"] == {"entries": [1, 2]}
    restored = from_v2_card(card)
    assert restored.extensions["conver_system"]["character_book"] == {"entries": [1, 2]}
