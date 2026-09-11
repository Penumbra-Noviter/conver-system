"""
CG 资产库服务（CG-2，深模块）

协议表面（__all__）：add_cg / list_cg / unlock_cg / pick_cg_by_weight。

生命周期契约（对齐对标站「会话删除后图保留」语义，DB FK 落实）：
    - character_id → CASCADE（删除作品级联删图）
    - conversation_id / message_id → SET NULL（删除会话/消息后图保留）
加权抽选（pick_cg_by_weight）：对齐对标站「概率模式——触发时从加权列表中
挑选一张」；weight 取候选 `weight` 属性（无则 1），**按 id 升序规范化排序
后掷点**（同种子可复现、不随输入顺序变化——WL-2 同型 Falsify 教训锁定）。
"""

from __future__ import annotations

import random
from collections.abc import Sequence

from sqlalchemy.orm import Session

from backend.app.models.cg_image import CgImage
from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message
from backend.app.services.exceptions import (
    CharacterNotFoundError,
    CgImageNotFoundError,
    ConversationNotFoundError,
    MessageNotFoundError,
)

__all__ = ["add_cg", "list_cg", "unlock_cg", "pick_cg_by_weight", "cg_timeline"]


def add_cg(
    db: Session,
    character_id: int,
    url: str,
    *,
    conversation_id: int | None = None,
    message_id: int | None = None,
    group_name: str = "",
    unlock_hint: str = "",
) -> CgImage:
    """入库一张 CG 图（幂等去重：同作品同 url 直接返回既有行，不重复入库）

    Args:
        db: 数据库会话
        character_id: 归属作品（不存在 → CharacterNotFoundError）
        url: 图片地址（本地文件路径或 URL）
        conversation_id: 产出会话（可选；不存在 → ConversationNotFoundError）
        message_id: 产出自哪条消息（可选；不存在或不属于该会话 → MessageNotFoundError）
        group_name: 分组（空 = 默认分组，展示层映射）
        unlock_hint: 未解锁时提示

    Returns:
        新入库或既有（同作品同 url）的 CgImage

    Raises:
        CharacterNotFoundError: 角色不存在
        ConversationNotFoundError: conversation_id 不存在
        MessageNotFoundError: message_id 不存在 / 不属于该会话
    """
    if db.query(Character.id).filter(Character.id == character_id).first() is None:
        raise CharacterNotFoundError(f"角色不存在: {character_id}")

    if conversation_id is not None:
        if db.query(Conversation.id).filter(Conversation.id == conversation_id).first() is None:
            raise ConversationNotFoundError("对话不存在")
        if message_id is not None:
            belongs = (
                db.query(Message.id)
                .filter(Message.id == message_id, Message.conversation_id == conversation_id)
                .first()
            )
            if belongs is None:
                raise MessageNotFoundError(f"消息不存在: {message_id}")

    # 幂等去重：同作品同 url → 返回既有（不产生重复行）
    existing = (
        db.query(CgImage)
        .filter(CgImage.character_id == character_id, CgImage.url == url)
        .first()
    )
    if existing is not None:
        return existing

    cg = CgImage(
        character_id=character_id,
        conversation_id=conversation_id,
        message_id=message_id,
        url=url,
        group_name=group_name,
        unlock_hint=unlock_hint,
    )
    db.add(cg)
    db.commit()
    db.refresh(cg)
    return cg


def list_cg(
    db: Session,
    character_id: int,
    *,
    group_name: str | None = None,
    unlocked_only: bool = False,
) -> list[CgImage]:
    """角色 CG 图列表（新品在前：id 降序——画廊最新产出优先）

    Args:
        db: 数据库会话
        character_id: 归属作品
        group_name: 分组过滤（None = 全部分组；仅精确匹配非空值）
        unlocked_only: 仅已解锁

    Returns:
        CgImage 列表（id 降序，确定性）
    """
    query = db.query(CgImage).filter(CgImage.character_id == character_id)
    if group_name is not None:
        query = query.filter(CgImage.group_name == group_name)
    if unlocked_only:
        query = query.filter(CgImage.unlocked.is_(True))
    return query.order_by(CgImage.id.desc()).all()


def unlock_cg(db: Session, cg_id: int) -> CgImage:
    """解锁 CG（幂等：已解锁再调无副作用，返回同一行）

    Args:
        db: 数据库会话
        cg_id: 目标 CG id

    Returns:
        解锁后的 CgImage

    Raises:
        CgImageNotFoundError: cg 不存在
    """
    cg = db.query(CgImage).filter(CgImage.id == cg_id).first()
    if cg is None:
        raise CgImageNotFoundError(f"CG 图片不存在: {cg_id}")
    if not cg.unlocked:
        cg.unlocked = True
        db.commit()
        db.refresh(cg)
    return cg


def cg_timeline(db: Session, character_id: int) -> list[dict]:
    """剧情回顾时间线（CG-3）：已解锁 CG + 对应消息片段，按时间升序

    排序契约（契约锁锁定）：消息 created_at 升序（CG 无锚消息时按其自身
    created_at 参与排序）；同一条消息的多图保持入库序（cg.id 升序）——
    对齐「时间线顺序 = 消息 created_at 升序；同消息多图入库序」。

    Args:
        db: 数据库会话
        character_id: 归属作品

    Returns:
        时间线条目 dict 列表（cg_id/url/group_name/message_content/
        message_created_at/cg_created_at），已解锁且按上述序
    """
    rows = (
        db.query(CgImage, Message.content, Message.created_at)
        .outerjoin(Message, Message.id == CgImage.message_id)
        .filter(CgImage.character_id == character_id, CgImage.unlocked.is_(True))
        .all()
    )
    items = [
        {
            "cg_id": cg.id,
            "url": cg.url,
            "group_name": cg.group_name,
            "message_content": msg_content,
            "message_created_at": msg_created_at,
            "cg_created_at": cg.created_at,
        }
        for cg, msg_content, msg_created_at in rows
    ]
    # 消息 created_at 升序（无锚消息 → 用 cg.created_at 参与排序）；同消息 → cg.id 升序（入库序）
    return sorted(
        items,
        key=lambda it: (it["message_created_at"] or it["cg_created_at"], it["cg_id"]),
    )


def pick_cg_by_weight(
    candidates: Sequence[CgImage],
    *,
    rng: random.Random | None = None,
) -> CgImage | None:
    """按权重抽一张 CG（对齐对标站概率池语义；空候选 → None）

    权重契约：候选 `weight` 属性（无 → 1）；`weight=0` 永不抽中。
    **规范化**：先按 id 升序排序再掷点——同一集合任意传入顺序 + 同种子 →
    同一结果（WL-2 同型 Falsify 教训：RNG 消耗序列跟随迭代序）。

    Args:
        candidates: 候选 CG（含 .id；可选 .weight 属性）
        rng: 随机源（缺省新建；注入固定种子可复现）

    Returns:
        抽中的 CgImage；空候选或总权重为 0 → None
    """
    if not candidates:
        return None
    rng = rng or random.Random()
    ordered = sorted(candidates, key=lambda c: c.id)
    weights = [max(0, int(getattr(c, "weight", 1) or 0)) for c in ordered]
    total = sum(weights)
    if total <= 0:
        return None
    roll = rng.uniform(0, total)
    acc = 0
    for cg, w in zip(ordered, weights):
        acc += w
        if roll < acc:
            return cg
    return ordered[-1]  # 浮点兜底（roll == total 边缘）