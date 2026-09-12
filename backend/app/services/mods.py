"""
Mod 挂载层服务（MD-1，深模块）

协议表面（__all__）：ModPayload / list_mods / create_mod / update_mod /
delete_mod / bind_mod / unbind_mod / set_binding_enabled / set_binding_sort_order /
list_character_mods / reorder_character_mods / apply_prompt_mods（ModReorderError 在
exceptions.py 统一登记，本模块不导出）。

数据模型：mods（全局 Mod 库，目标区域 prompt|memory|css）+ mod_bindings（作品级
挂载，(character_id, mod_id) 唯一 + sort_order + enabled 开关）。本模块只做存取
与「prompt 区注入叠加」纯函数；memory/css 区由各自消费方读取（MD-2 及后续）。

apply_prompt_mods（纯函数，零 DB）：把已启用 prompt 区 Mod 的注入内容按
sort_order 升序（同序按 mod_id 稳定）叠加进 base_blocks。base_blocks 三块键为
``system``/``before_char``/``after_char``（与 lorebook_engine.build_world_injection
输出同构，可直接作为 world_injection 传入 llm/prompt.build_messages）；prompt Mod
的 payload 为 JSON ``{"world": str, "before_char": str, "after_char": str}``，
其中 ``world`` 注入 ``system`` 块（对齐 lorebook _POSITION_KEYS 的 world→system
语义）。payload 非 JSON / 非 dict / 区域非 str → 容错跳过（不破坏对话，不抛）。
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from dataclasses import dataclass

from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.mods import Mod, ModBinding
from backend.app.schemas.mods import ModCreate, ModUpdate
from backend.app.services.exceptions import (
    CharacterNotFoundError,
    ModAlreadyBoundError,
    ModBindingNotFoundError,
    ModNotFoundError,
    ModReorderError,
)

__all__ = [
    "ModPayload",
    "list_mods",
    "create_mod",
    "update_mod",
    "delete_mod",
    "bind_mod",
    "unbind_mod",
    "set_binding_enabled",
    "set_binding_sort_order",
    "list_character_mods",
    "reorder_character_mods",
    "apply_prompt_mods",
]

#: prompt 区 payload 的三区域键（spec §MD-1 词汇）→ 注入块键（对齐
#: lorebook_engine._POSITION_KEYS：world → system 世界知识块）
_REGION_KEYS = (("world", "system"), ("before_char", "before_char"), ("after_char", "after_char"))


@dataclass(frozen=True)
class ModPayload:
    """apply_prompt_mods 输入条目（纯数据容器，与 ORM 解耦）

    Attributes:
        mod_id: Mod 主键（同 sort_order 的稳定决胜键）
        target_area: 目标区域（仅 "prompt" 参与叠加）
        payload: 注入内容（prompt 区为 JSON ``{world/before_char/after_char}``）
        sort_order: 叠加排序（升序）
        enabled: 绑定开关（false 不参与叠加）
    """
    mod_id: int
    target_area: str = "prompt"
    payload: str = ""
    sort_order: int = 0
    enabled: bool = True


def list_mods(db: Session) -> list[Mod]:
    """全局 Mod 库列表（id 升序，确定性）

    Args:
        db: 数据库会话

    Returns:
        Mod 列表（id 升序）
    """
    return db.query(Mod).order_by(Mod.id.asc()).all()


def _require_mod(db: Session, mod_id: int) -> Mod:
    """守卫：Mod 必须存在，否则抛 ModNotFoundError"""
    mod = db.query(Mod).filter(Mod.id == mod_id).first()
    if mod is None:
        raise ModNotFoundError(f"Mod 不存在: {mod_id}")
    return mod


def _require_character(db: Session, character_id: int) -> None:
    """守卫：角色必须存在，否则抛 CharacterNotFoundError（防 FK 违例 500）"""
    exists = db.query(Character.id).filter(Character.id == character_id).first()
    if exists is None:
        raise CharacterNotFoundError(f"角色不存在: {character_id}")


def _require_binding(db: Session, binding_id: int) -> ModBinding:
    """守卫：绑定必须存在，否则抛 ModBindingNotFoundError"""
    binding = db.query(ModBinding).filter(ModBinding.id == binding_id).first()
    if binding is None:
        raise ModBindingNotFoundError(f"Mod 绑定不存在: {binding_id}")
    return binding


def create_mod(db: Session, payload: ModCreate) -> Mod:
    """创建 Mod（单事务提交）

    Args:
        db: 数据库会话
        payload: Mod 数据（Schema 已做边界校验）

    Returns:
        落库后的 Mod ORM 对象
    """
    mod = Mod(**payload.model_dump())
    db.add(mod)
    db.commit()
    db.refresh(mod)
    return mod


def update_mod(db: Session, mod_id: int, payload: ModUpdate) -> Mod:
    """部分更新 Mod（仅提交显式字段）

    显式 null 视为「未提供」跳过写入（与 lorebook.update_entry 同语义——对
    NOT NULL 列照写会抛 IntegrityError、对可空列落 NULL 毒化后续读取）。

    Args:
        db: 数据库会话
        mod_id: Mod ID（不存在抛 ModNotFoundError）
        payload: 待更新字段（exclude_unset）

    Returns:
        更新后的 Mod ORM 对象
    """
    mod = _require_mod(db, mod_id)
    for field, value in payload.model_dump(exclude_unset=True).items():
        if value is None:
            continue
        setattr(mod, field, value)
    db.commit()
    db.refresh(mod)
    return mod


def delete_mod(db: Session, mod_id: int) -> None:
    """删除 Mod（级联删除其全部绑定）

    Args:
        db: 数据库会话
        mod_id: Mod ID（不存在抛 ModNotFoundError）

    Returns:
        None（成功即删除）
    """
    mod = _require_mod(db, mod_id)
    db.delete(mod)
    db.commit()


def bind_mod(
    db: Session,
    character_id: int,
    mod_id: int,
    *,
    enabled: bool = True,
    sort_order: int | None = None,
) -> ModBinding:
    """把 Mod 挂载到角色（作品级）

    sort_order=None 时自动取该角色现有最大 sort_order + 1（首个为 0）；
    同角色同 Mod 重复绑定抛 ModAlreadyBoundError（DB 唯一约束兜底）。

    Args:
        db: 数据库会话
        character_id: 角色 ID（不存在抛 CharacterNotFoundError）
        mod_id: Mod ID（不存在抛 ModNotFoundError）
        enabled: 绑定开关（默认 True）
        sort_order: 叠加排序（None = 自动续尾）

    Returns:
        落库后的 ModBinding ORM 对象

    Raises:
        CharacterNotFoundError: 角色不存在
        ModNotFoundError: Mod 不存在
        ModAlreadyBoundError: 同角色已绑定该 Mod
    """
    _require_character(db, character_id)
    _require_mod(db, mod_id)

    existing = (
        db.query(ModBinding)
        .filter(ModBinding.character_id == character_id, ModBinding.mod_id == mod_id)
        .first()
    )
    if existing is not None:
        raise ModAlreadyBoundError(f"角色 {character_id} 已绑定 Mod {mod_id}")

    if sort_order is None:
        max_order = (
            db.query(func.max(ModBinding.sort_order))
            .filter(ModBinding.character_id == character_id)
            .scalar()
        )
        sort_order = (max_order + 1) if max_order is not None else 0

    binding = ModBinding(
        character_id=character_id,
        mod_id=mod_id,
        enabled=enabled,
        sort_order=sort_order,
    )
    db.add(binding)
    db.commit()
    db.refresh(binding)
    return binding


def unbind_mod(db: Session, binding_id: int) -> None:
    """解绑（删除绑定行）

    Args:
        db: 数据库会话
        binding_id: 绑定 ID（不存在抛 ModBindingNotFoundError）

    Returns:
        None（成功即删除）
    """
    binding = _require_binding(db, binding_id)
    db.delete(binding)
    db.commit()


def set_binding_enabled(db: Session, binding_id: int, enabled: bool) -> ModBinding:
    """切换绑定开关（幂等：同值再写无副作用）

    Args:
        db: 数据库会话
        binding_id: 绑定 ID（不存在抛 ModBindingNotFoundError）
        enabled: 目标开关态

    Returns:
        更新后的 ModBinding ORM 对象
    """
    binding = _require_binding(db, binding_id)
    binding.enabled = enabled
    db.commit()
    db.refresh(binding)
    return binding


def set_binding_sort_order(db: Session, binding_id: int, sort_order: int) -> ModBinding:
    """单条幂等更新绑定的 sort_order（MD-2 排序落库，非解绑重绑）

    Args:
        db: 数据库会话
        binding_id: 绑定 ID（不存在抛 ModBindingNotFoundError）
        sort_order: 目标叠加排序值

    Returns:
        更新后的 ModBinding ORM 对象
    """
    binding = _require_binding(db, binding_id)
    binding.sort_order = sort_order
    db.commit()
    db.refresh(binding)
    return binding


def list_character_mods(db: Session, character_id: int) -> list[ModBinding]:
    """角色已挂载的绑定列表（sort_order 升序，同序按 mod_id 稳定）

    Args:
        db: 数据库会话
        character_id: 角色 ID

    Returns:
        ModBinding 列表（确定性排序）
    """
    return (
        db.query(ModBinding)
        .filter(ModBinding.character_id == character_id)
        .order_by(ModBinding.sort_order.asc(), ModBinding.mod_id.asc())
        .all()
    )


def reorder_character_mods(
    db: Session,
    character_id: int,
    ordered_binding_ids: list[int],
) -> list[ModBinding]:
    """原子批量重排角色挂载 Mod 顺序（F-102 后端）

    一次性提交该角色全部挂载 Mod 的 binding_id 新序，单事务内校验归属并逐条
    ``sort_order = 列表下标``，一次 commit——消除「两次独立写中间态留下重复
    sort_order」的窗口。任一校验失败在 commit 之前抛出，整体不落库（无部分写入）。

    校验顺序（任一失败即抛、整体不落库）：
        1. 角色存在 → 否则 CharacterNotFoundError（404）
        2. 非空列表 → 否则 ModReorderError（400，明确拒绝，避免误清空）
        3. 无重复 id → 否则 ModReorderError（400；HTTP 层已由 schema 422 拦截，
           此处为直接调用方的防御）
        4. 逐条 binding 存在且归属该角色 → 否则 ModBindingNotFoundError（404；
           引用不存在 / 混入他角色绑定同归一 404）
        5. 恰好覆盖该角色全部绑定（不缺失）→ 否则 ModReorderError（400）

    Args:
        db: 数据库会话
        character_id: 角色 ID（不存在抛 CharacterNotFoundError）
        ordered_binding_ids: 按新序排列的绑定 ID 列表（恰好覆盖该角色全部绑定）

    Returns:
        重排后的绑定列表（sort_order 升序，同序按 mod_id 稳定）

    Raises:
        CharacterNotFoundError: 角色不存在
        ModBindingNotFoundError: 任一 binding_id 不存在或归属其他角色
        ModReorderError: 空列表 / 重复 id / 未恰好覆盖该角色全部绑定
    """
    _require_character(db, character_id)

    if not ordered_binding_ids:
        raise ModReorderError("批量重排不能为空列表")

    if len(ordered_binding_ids) != len(set(ordered_binding_ids)):
        raise ModReorderError("ordered_binding_ids 含重复 binding_id")

    existing = (
        db.query(ModBinding)
        .filter(ModBinding.character_id == character_id)
        .all()
    )
    by_id = {b.id: b for b in existing}

    for binding_id in ordered_binding_ids:
        if binding_id not in by_id:
            raise ModBindingNotFoundError(f"Mod 绑定不存在: {binding_id}")

    if set(ordered_binding_ids) != set(by_id):
        raise ModReorderError("ordered_binding_ids 必须恰好覆盖该角色全部绑定")

    for index, binding_id in enumerate(ordered_binding_ids):
        by_id[binding_id].sort_order = index

    db.commit()
    return list_character_mods(db, character_id)


def apply_prompt_mods(
    base_blocks: dict[str, list[str]],
    mods: Sequence[ModPayload],
) -> dict[str, list[str]]:
    """把已启用 prompt 区 Mod 的注入内容按 sort_order 叠加进注入块（纯函数）

    零 DB / 零 IO。返回新 dict（新列表），不就地篡改 base_blocks。空 Mod 列表
    （或全部禁用 / 非 prompt 区 / payload 空）→ 返回与输入相等的副本（零变化）。

    叠加语义：
        1. 仅 enabled=True 且 target_area="prompt" 的 Mod 参与
        2. 按 (sort_order, mod_id) 升序稳定排序（同序按 mod_id 决胜）
        3. 逐个解析 payload JSON，把 world/before_char/after_char 三区域的
           非空内容 append 到对应注入块（world→system）；空串/纯空白跳过

    容错（不抛、不破坏对话）：payload 非 JSON / 非 dict / 区域值非 str → 该
    Mod 整体或该区域静默跳过。

    Args:
        base_blocks: 注入块（{system/before_char/after_char: [内容]}，与
            build_world_injection 输出同构）
        mods: 参与叠加的 ModPayload 序列（含禁用项，本函数自行过滤）

    Returns:
        叠加后的注入块 dict（新对象；三键恒存在）
    """
    result = {k: list(v) for k, v in base_blocks.items()}
    result.setdefault("system", [])
    result.setdefault("before_char", [])
    result.setdefault("after_char", [])

    ordered = sorted(
        (m for m in mods if m.enabled and m.target_area == "prompt"),
        key=lambda m: (m.sort_order, m.mod_id),
    )
    for mod in ordered:
        regions = _parse_prompt_payload(mod.payload)
        for region, block_key in _REGION_KEYS:
            content = regions.get(region, "")
            if content and content.strip():
                result[block_key].append(content)
    return result


def _parse_prompt_payload(payload: str) -> dict[str, str]:
    """解析 prompt 区 payload JSON → {区域: 内容}；非 JSON / 非 dict / 值非 str → 容错跳过"""
    if not payload or not payload.strip():
        return {}
    try:
        parsed = json.loads(payload)
    except (TypeError, ValueError):
        return {}
    if not isinstance(parsed, dict):
        return {}
    regions: dict[str, str] = {}
    for region, _block_key in _REGION_KEYS:
        value = parsed.get(region)
        if isinstance(value, str):
            regions[region] = value
    return regions
