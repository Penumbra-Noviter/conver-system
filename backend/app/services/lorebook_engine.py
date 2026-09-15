"""
世界书激活引擎（WL-2）— 纯函数，零 DB / 零 IO

协议表面（__all__）：LorebookEntryData / activate_lorebook_entries /
build_world_injection / collect_scan_text。命中判定、概率/互斥组抽取、按
position 分组构建注入块全部无副作用，RNG 注入可复现（同种子同结果）。
ORM 条目由调用方（WL-3）转换为 LorebookEntryData，本模块不 import 数据库。

语义对齐 SillyTavern World Info（spec §WL-2）：
- constant=true 直进（不判命中）；or/and 子串匹配，大小写不敏感，空 key 不参与
- depth 由 collect_scan_text 落实（0..20，>20 裁剪，<0 视为 0；system 指令不计轮）
- probability：0 必弃 / 100 必进（均不消耗 RNG）/ 中间值掷点
- group_name 非空：同组按 group_weight 加权抽一；无组条目全部入选
- 输出按 (order, id) 升序（确定性锁定）
"""

from __future__ import annotations

import random
from collections.abc import Callable, Sequence
from dataclasses import dataclass

from backend.app.services.llm.prompt import (
    SOURCE_MEMORY,
    SOURCE_WORLD,
    InjectedSegment,
    apply_template_vars,
)

__all__ = [
    "LorebookEntryData",
    "activate_lorebook_entries",
    "build_world_injection",
    "collect_scan_text",
]

#: depth 上限（spec：0..20）
MAX_DEPTH = 20

#: 计入「轮」窗口的角色（system 指令是上下文而非对话）
_DIALOGUE_ROLES = ("user", "assistant")

#: position → 注入块键（未知 position 回落 world → system）
_POSITION_KEYS = {"world": "system", "before_char": "before_char", "after_char": "after_char"}


@dataclass(frozen=True)
class LorebookEntryData:
    """引擎输入条目（纯数据容器，与 ORM 解耦）

    Attributes:
        id: 条目主键（输出稳定排序的同序决胜键）
        keys: 触发关键词（或/and 子串匹配；空 key 不参与）
        content: 命中后注入内容（build_world_injection 输出源）
        constant: 常驻（不判命中直接入选）
        order: 输出排序（升序）
        probability: 独立命中概率（0 必弃 / 100 必进）
        group_name: 互斥组名（空=不分组）
        group_weight: 组内加权抽一权重
        match_mode: or（任一 key）/ and（全部 key）
        position: 注入位置（world / before_char / after_char）
        enabled: 单条开关（false 不参与）
    """
    id: int
    keys: tuple[str, ...] = ()
    content: str = ""
    constant: bool = False
    order: int = 100
    probability: int = 100
    group_name: str = ""
    group_weight: int = 100
    match_mode: str = "or"
    position: str = "world"
    enabled: bool = True


def activate_lorebook_entries(
    entries: Sequence[LorebookEntryData],
    scan_text: str,
    *,
    current_input: str = "",
    rng: random.Random | None = None,
) -> list[LorebookEntryData]:
    """命中判定 + 概率/互斥组抽取 + 排序（纯函数，主入口）

    流程（顺序即语义）：
        1. enabled=false 剔除
        2. constant 直进；否则 keys 对匹配文本做子串匹配（大小写不敏感，
           or=任一 key 命中 / and=全部 key 命中；空 key 不参与）
        3. 概率闸：>=100 必进、<=0 必弃（均不消耗 RNG）、中间值掷点
        4. 互斥组：同 group_name 按 group_weight 加权抽一（每组合计一次 RNG）
        5. 输出按 (order, id) 升序（确定性锁定）

    Args:
        entries: 待判定条目（含 enabled=false 的全量即可，本函数自行过滤）
        scan_text: 扫描窗口文本（由 collect_scan_text 产出；为空时回退 current_input）
        current_input: 当前用户输入（scan_text 为空时的兜底匹配文本）
        rng: 随机源（注入 Random 实例可复现；None → 新建）

    Returns:
        命中的条目列表（按 (order, id) 升序）
    """
    rng = rng or random.Random()
    match_text = scan_text if scan_text else current_input

    # 输入先按 (order, id) 规范化：RNG 消耗序列（概率掷点 + 组抽签）随规范序，
    # 同种子可复现性不随调用方传入顺序漂移（Falsify 修复锁）
    ordered = sorted(entries, key=_sort_key)

    candidates: list[LorebookEntryData] = []
    for entry in ordered:
        if not entry.enabled:
            continue
        if not entry.constant and not _keys_match(entry, match_text):
            continue
        if not _probability_gate(entry, rng):
            continue
        candidates.append(entry)

    resolved = _resolve_groups(candidates, rng)
    return sorted(resolved, key=_sort_key)


def build_world_injection(
    activated: Sequence[LorebookEntryData],
    *,
    user_name: str = "User",
    char_name: str = "Character",
    source_by_id: dict[int, str] | None = None,
) -> dict[str, list[InjectedSegment]]:
    """按 position 分组构建带来源注入块（纯函数）

    返回 ``{"system": [...], "before_char": [...], "after_char": [...]}``：
    组内按 (order, id) 升序；content 经 ``{{user}}`` / ``{{char}}`` 模板替换
    （与角色字段模板变量同 seam）。未知 position 回落 world（system 块），
    不静默丢弃。

    source 标注（PD-3 来源保真）：来源经 entry.id 反查 ``source_by_id`` 传入，
    ``LorebookEntryData`` 自身零 source 契约不变——值为 ``"auto"`` 时标
    ``SOURCE_MEMORY``，其余（缺省键或非 auto 值）标 ``SOURCE_WORLD``。

    Args:
        activated: 激活引擎输出（已排序与否均可，本函数内部稳定排序）
        user_name: {{user}} 模板变量值
        char_name: {{char}} 模板变量值
        source_by_id: entry id → source（如 "auto"/"manual"）；None/缺省键 → world

    Returns:
        position → 注入分段列表（按 (order, id) 升序）
    """
    blocks: dict[str, list[InjectedSegment]] = {
        "system": [], "before_char": [], "after_char": [],
    }
    for entry in sorted(activated, key=_sort_key):
        key = _POSITION_KEYS.get(entry.position, "system")
        source = SOURCE_MEMORY if (source_by_id or {}).get(entry.id) == "auto" else SOURCE_WORLD
        content = apply_template_vars(entry.content, user_name, char_name)
        blocks[key].append(InjectedSegment(content=content, source=source))
    return blocks


def collect_scan_text(
    history: Sequence[object],
    current_input: str,
    depth: int,
    *,
    role_of: Callable[[object], str],
) -> str:
    """构建命中扫描窗口文本（纯函数）

    depth 语义（spec §WL-2）：0 → 仅 current_input；N → 最近 N 轮 = 2N 条
    「对话消息」（system 指令不计轮）的 content 以换行连接 + current_input。
    越界裁剪：>20 → 20；<0 → 0（仅输入）。

    Args:
        history: 历史消息对象（需暴露 ``content`` 属性；角色经 role_of 提取）
        current_input: 当前用户输入（恒追加，depth=0 时仅此项）
        depth: 参与命中的最近轮数（0..20，越界裁剪）
        role_of: 消息 → 角色字符串（"user"/"assistant" 计入窗口）

    Returns:
        换行连接的扫描文本（空历史 + 空输入 → ""）
    """
    clipped = max(0, min(depth, MAX_DEPTH))
    if clipped == 0:
        return current_input
    dialogue = [m for m in history if role_of(m) in _DIALOGUE_ROLES]
    window = dialogue[-2 * clipped :]
    parts = [str(getattr(m, "content", "") or "") for m in window]
    parts.append(current_input)
    return "\n".join(parts)


# ── 内部实现 ──


def _keys_match(entry: LorebookEntryData, text: str) -> bool:
    """子串命中判定：or=任一 key、and=全部 key；空白 key 剔除；大小写不敏感

    匹配前去除 key 周边空白（与「空白即剔除」语义一致，Falsify 修复锁）。
    """
    keys = [k.strip() for k in entry.keys if k and k.strip()]
    if not keys:
        return False
    lowered = text.lower()
    if entry.match_mode == "and":
        return all(k.lower() in lowered for k in keys)
    return any(k.lower() in lowered for k in keys)


def _probability_gate(entry: LorebookEntryData, rng: random.Random) -> bool:
    """独立概率闸：0 必弃 / 100 必进（均不消耗 RNG）/ 中间值掷点"""
    if entry.probability >= 100:
        return True
    if entry.probability <= 0:
        return False
    return rng.random() * 100 < entry.probability


def _resolve_groups(
    candidates: Sequence[LorebookEntryData], rng: random.Random
) -> list[LorebookEntryData]:
    """互斥组解析：同组按 group_weight 加权抽一；无组条目全部保留"""
    groups: dict[str, list[LorebookEntryData]] = {}
    singles: list[LorebookEntryData] = []
    for entry in candidates:
        if entry.group_name:
            groups.setdefault(entry.group_name, []).append(entry)
        else:
            singles.append(entry)

    result = list(singles)
    for group in groups.values():
        result.append(_weighted_pick(group, rng))
    return result


def _weighted_pick(group: Sequence[LorebookEntryData], rng: random.Random) -> LorebookEntryData:
    """按 group_weight 加权抽一（权重兜底 ≥1，非空组恒可抽）"""
    weights = [max(e.group_weight, 1) for e in group]
    total = sum(weights)
    r = rng.random() * total
    cumulative = 0.0
    for entry, weight in zip(group, weights):
        cumulative += weight
        if r < cumulative:
            return entry
    return group[-1]


def _sort_key(entry: LorebookEntryData) -> tuple[int, int]:
    """输出/规范化排序键：order 升序、同 order 按 id 升序（确定性锁定）"""
    return (entry.order, entry.id)
