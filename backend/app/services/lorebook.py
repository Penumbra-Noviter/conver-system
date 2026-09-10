"""
世界书条目仓库层（WL-1）

协议表面（__all__）：list_entries / create_entry / update_entry / delete_entry /
replace_entries / parse_character_book。字段语义对齐 SillyTavern World Info
（docs/world-simulation-exploration.md D3/D4 与 docs/chat-simulator-upgrade-spec.md
§WL-1）；本层只做存取与「角色卡 character_book → 条目草案」的解析，命中判定/
排序/注入引擎在 lorebook_engine.py（WL-2）承载。

边界策略：Schema 层（schemas/lorebook.py）对越界值采用「拒」（pydantic Field
约束）；parse_character_book 对 ST 脏数据采用「裁剪」（导入容错），两者分界
由契约锁用例锁定（test_lorebook_store.py）。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.lorebook import LorebookEntry
from backend.app.schemas.lorebook import LorebookEntryCreate, LorebookEntryUpdate
from backend.app.services.exceptions import CharacterNotFoundError, LorebookEntryNotFoundError

__all__ = [
    "list_entries",
    "create_entry",
    "update_entry",
    "delete_entry",
    "replace_entries",
    "parse_character_book",
]

#: ST character_book 中本模型不承载的 position 值（如 in_chat）统一回落 world
_KNOWN_ST_POSITIONS = ("before_char", "after_char")

#: 解析层数值边界（与 schema Field 约束一致；解析层裁剪、API 层拒绝）
_DEPTH_DEFAULT = 20


def list_entries(db: Session, character_id: int) -> list[LorebookEntry]:
    """获取角色的全部世界书条目

    排序契约（确定性，契约锁锁定）：order 升序，同 order 按 id 升序。

    Args:
        db: 数据库会话
        character_id: 角色 ID

    Returns:
        条目 ORM 列表（keys 已反序列化为 list[str]）
    """
    return (
        db.query(LorebookEntry)
        .filter(LorebookEntry.character_id == character_id)
        .order_by(LorebookEntry.order.asc(), LorebookEntry.id.asc())
        .all()
    )


def _require_character(db: Session, character_id: int) -> None:
    """守卫：角色必须存在，否则抛 CharacterNotFoundError（防 FK 违例 500）"""
    exists = db.query(Character.id).filter(Character.id == character_id).first()
    if exists is None:
        raise CharacterNotFoundError(f"角色不存在: {character_id}")


def _require_entry(db: Session, entry_id: int) -> LorebookEntry:
    """守卫：条目必须存在，否则抛 LorebookEntryNotFoundError"""
    entry = db.query(LorebookEntry).filter(LorebookEntry.id == entry_id).first()
    if entry is None:
        raise LorebookEntryNotFoundError(f"世界书条目不存在: {entry_id}")
    return entry


def create_entry(db: Session, character_id: int, payload: LorebookEntryCreate) -> LorebookEntry:
    """创建世界书条目（单事务提交）

    Args:
        db: 数据库会话
        character_id: 归属角色 ID（不存在抛 CharacterNotFoundError）
        payload: 条目数据（Schema 已做边界校验）

    Returns:
        落库后的条目 ORM 对象
    """
    _require_character(db, character_id)
    entry = LorebookEntry(character_id=character_id, **payload.model_dump())
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


def update_entry(db: Session, entry_id: int, payload: LorebookEntryUpdate) -> LorebookEntry:
    """部分更新世界书条目（仅提交显式字段）

    显式 null 视为「未提供」跳过写入（LorebookEntryUpdate 全字段 Optional 形态下，
    `{"content": null}` 若照写会对 NOT NULL 列抛 IntegrityError、对可空列落 NULL
    毒化后续读取——由 Falsify 修复锁锁定该语义）。

    Args:
        db: 数据库会话
        entry_id: 条目 ID（不存在抛 LorebookEntryNotFoundError）
        payload: 待更新字段（exclude_unset，未提交字段原样保留）

    Returns:
        更新后的条目 ORM 对象
    """
    entry = _require_entry(db, entry_id)
    for field, value in payload.model_dump(exclude_unset=True).items():
        if value is None:
            continue
        setattr(entry, field, value)
    db.commit()
    db.refresh(entry)
    return entry


def delete_entry(db: Session, entry_id: int) -> None:
    """删除世界书条目

    Args:
        db: 数据库会话
        entry_id: 条目 ID（不存在抛 LorebookEntryNotFoundError）

    Returns:
        None（成功即删除）
    """
    entry = _require_entry(db, entry_id)
    db.delete(entry)
    db.commit()


def replace_entries(db: Session, character_id: int, entries: list[LorebookEntryCreate]) -> int:
    """全量替换角色的世界书条目（先删后插，单事务）

    幂等（契约锁锁定）：连续两次以相同输入调用，两次均落库为相同条目集合，
    返回计数一致。常用于「角色卡 character_book 解析结果一键落库」。

    Args:
        db: 数据库会话
        character_id: 归属角色 ID（不存在抛 CharacterNotFoundError）
        entries: 新条目清单（空列表 = 清空该角色全部条目）

    Returns:
        新条目数量
    """
    _require_character(db, character_id)
    db.query(LorebookEntry).filter(LorebookEntry.character_id == character_id).delete(
        synchronize_session="fetch"
    )
    for payload in entries:
        db.add(LorebookEntry(character_id=character_id, **payload.model_dump()))
    db.commit()
    return len(entries)


def parse_character_book(book: dict) -> list[LorebookEntryCreate]:
    """角色卡 character_book → 世界书条目草案列表（字段语义对齐 ST）

    消费 `extensions.conver_system.character_book`（形如 ``{"entries": [...]}``，
    与 ST character_book 顶层结构一致）。逐条映射：
      keys/content/constant/insertion_order(或 order)→order/probability/group→group_name
    一一对应；position 仅 before_char/after_char 保留，in_chat 等本模型不承载值
    回落 world；match_mode 由 ST selective+secondary_keys 推得（and/or）。

    脏数据容错（导入场景不抛）：非 dict entry 跳过、缺失字段取默认值、数值越界
    裁剪（解析层裁剪、API 层拒绝的分界见模块 docstring）。

    Args:
        book: character_book dict（None/非 dict/缺 entries 键 → 空列表）

    Returns:
        条目草案列表（可直接交 replace_entries / create_entry 落库）
    """
    if not isinstance(book, dict):
        return []
    raw_entries = book.get("entries")
    if not isinstance(raw_entries, list):
        return []

    return [_entry_from_st(raw) for raw in raw_entries if isinstance(raw, dict)]


def _entry_from_st(raw: dict) -> LorebookEntryCreate:
    """单条 ST entry dict → LorebookEntryCreate（数值裁剪、列表/布尔容错）"""
    position = raw.get("position")
    if position not in _KNOWN_ST_POSITIONS:
        position = "world"
    # ST selective 语义：启用 secondary_keys 时全部关键词须命中 → and；否则 or
    selective = _as_bool(raw.get("selective"), False)
    secondary = raw.get("secondary_keys") or []
    match_mode = "and" if selective and secondary else "or"

    return LorebookEntryCreate(
        title=str(raw.get("name") or "")[:200],
        keys=_as_str_list(raw.get("keys")),
        content=str(raw.get("content") or ""),
        constant=_as_bool(raw.get("constant"), False),
        order=_clamp_int(raw.get("insertion_order", raw.get("order", 100)), 0, 9999, 100),
        probability=_clamp_int(raw.get("probability", 100), 1, 100, 100),
        group_name=str(raw.get("group") or "")[:100],
        group_weight=_clamp_int(raw.get("group_weight", 100), 1, 100, 100),
        match_mode=match_mode,
        position=position,
        depth=_clamp_int(raw.get("depth", _DEPTH_DEFAULT), 0, 20, _DEPTH_DEFAULT),
        source="manual",
        enabled=_as_bool(raw.get("enabled"), True),
    )


def _as_str_list(value) -> list[str]:
    """容错：None/空 → []；list → str 化；其它 → 单值包裹（对齐 character_card._as_list 惯例）"""
    if value is None or value == "":
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


def _as_bool(value, default: bool) -> bool:
    """布尔容错：字符串按字面求值（'false'/'0'/'no'/空 → False，'true'/'1'/'yes' → True），
    数值按非零，其它（含 None）→ default。杜绝 bool('false') == True 的语义反转（Falsify 修复）。"""
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("false", "0", "no", "off", ""):
            return False
        if lowered in ("true", "1", "yes", "on"):
            return True
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return default


def _clamp_int(value, lo: int, hi: int, default: int) -> int:
    """数值裁剪：非法/缺失 → default；越界 → 裁剪到 [lo, hi]"""
    try:
        num = int(value)
    except (TypeError, ValueError):
        return default
    return min(hi, max(lo, num))
