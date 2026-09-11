"""
记忆宫殿（WL-5）— LLM 自动归纳 → 世界书 auto 条目

协议表面（__all__）：MemoryDraft / MEMORY_DRAFT_SCHEMA / should_summarize /
summarize_turn / persist_drafts。引擎（lorebook_engine / lorebook 仓库）零改动：
本层是「归纳 → 条目」的调用方形态（spec §WL-5）。

归纳失败隔离：summarize_turn 内部捕获 LLM 异常与 JSON 解析失败 → 记日志返回
None（不向上抛），对话主流程调用方只判 None；persist_drafts 纯 DB 写入。
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass

from sqlalchemy.orm import Session

from backend.app.models.lorebook import LorebookEntry
from backend.app.services.llm.base import BaseLLM

logger = logging.getLogger(__name__)

__all__ = [
    "MemoryDraft",
    "MEMORY_DRAFT_SCHEMA",
    "should_summarize",
    "summarize_turn",
    "persist_drafts",
]

#: auto 条目固定配置（spec §WL-5：position='world'，depth=20 可配）
AUTO_POSITION = "world"
AUTO_DEPTH = 20

#: 归纳输出 JSON schema（title/keys/content；prompt 组装与解析校验共用单一来源）
MEMORY_DRAFT_SCHEMA = {
    "title": "string 条目标题（一句话要点）",
    "keys": ["string 触发关键词 2-5 个，具体名词优先"],
    "content": "string 记忆内容（150 字内，第三人称陈述）",
}

#: 参与归纳的最近消息条数（上限窗口，防超长上下文）
_SUMMARIZE_WINDOW = 20


@dataclass(frozen=True)
class MemoryDraft:
    """单条归纳草案（对应 MEMORY_DRAFT_SCHEMA 三字段）"""
    title: str
    keys: list[str]
    content: str


def should_summarize(
    message_count: int,
    char_count: int,
    *,
    every_rounds: int,
    char_threshold: int,
) -> bool:
    """阈值判定：每 N 轮（=2N 条消息）或记忆字符数达标即归纳

    Args:
        message_count: 对话消息总数（每轮 2 条：user + assistant）
        char_count: 对话累计字符数
        every_rounds: 每多少轮归纳一次（0 → 每回合恒归纳）
        char_threshold: 字符数阈值（参考对标站 10000）

    Returns:
        True=需要归纳 / False=未达标
    """
    rounds_met = every_rounds <= 0 or message_count >= every_rounds * 2
    return rounds_met or char_count >= char_threshold


async def summarize_turn(
    history: list[object],
    *,
    provider: BaseLLM,
    model: str | None = None,
    user_name: str = "User",
    char_name: str = "Character",
) -> MemoryDraft | None:
    """归纳最近对话为记忆草案（失败降级返回 None，绝不向上抛）

    流程：取窗口内历史 → 组装归纳 prompt（要求按 MEMORY_DRAFT_SCHEMA 输出 JSON）
    → provider.generate → 剥围栏 + 严格 json.loads + 字段校验（title/keys/content
    齐全且 keys 为非空 str 列表）。LLM 异常 / 非法 JSON / 缺字段 → logger.warning
    并返回 None（异常隔离契约：对话主流程不受影响）。

    Args:
        history: 对话历史（role/content 属性；取最近 _SUMMARIZE_WINDOW 条）
        provider: 已解析的 LLM Provider 实例
        model: 模型名（透传 generate）
        user_name: 用户昵称（{{user}} 模板变量）
        char_name: 角色名（{{char}} 模板变量）

    Returns:
        MemoryDraft（三字段齐全）；任何失败 → None
    """
    window = history[-_SUMMARIZE_WINDOW:]
    transcript = "\n".join(
        f"{_role_str(getattr(m, 'role', ''))}: {getattr(m, 'content', '')}" for m in window
    )
    schema_example = json.dumps(MEMORY_DRAFT_SCHEMA, ensure_ascii=False)
    prompt = (
        f"你是记忆宫殿归纳器。把以下对话归纳为一条世界书记忆条目，"
        f"严格输出 JSON（不要输出其它文字），字段结构如下：\n{schema_example}\n"
        f"要求：title 一句话要点；keys 2-5 个具体名词触发词（不要用单字泛词）；"
        f"content 150 字内第三人称陈述。\n\n对话：\n{transcript}\n\n{{user}}={{user_name}}, {{char}}={{char_name}}\nJSON："
    )
    try:
        reply = await provider.generate(
            [{"role": "user", "content": prompt}],
            temperature=0.3,
            model=model,
        )
    except Exception as e:  # noqa: BLE001 — 归纳失败隔离（LLM 异常族 + 意外均降级）
        logger.warning("记忆宫殿归纳失败（LLM 异常）: %s", e)
        return None

    draft = _parse_draft(reply)
    if draft is None:
        logger.warning("记忆宫殿归纳输出无法解析为合法条目（已降级不落库）")
    return draft


def persist_drafts(
    db: Session,
    character_id: int,
    drafts: list[MemoryDraft],
) -> int:
    """把归纳草案落库为世界书 auto 条目（keys 空跳过；同 keys+同 content 去重）

    Args:
        db: 数据库会话
        character_id: 归属角色
        drafts: 归纳草案列表（含无效草案 caller 已过滤或本函数跳过）

    Returns:
        实际新增条目数
    """
    # 既有 auto 条目指纹集（frozenset(keys), content）——去重基准
    existing = {
        (frozenset(e.keys), e.content)
        for e in db.query(LorebookEntry).filter(
            LorebookEntry.character_id == character_id,
            LorebookEntry.source == "auto",
        ).all()
    }

    inserted = 0
    for draft in drafts:
        if not draft or not draft.keys:
            continue
        fingerprint = (frozenset(draft.keys), draft.content)
        if fingerprint in existing:
            continue
        db.add(
            LorebookEntry(
                character_id=character_id,
                title=draft.title,
                keys=list(draft.keys),
                content=draft.content,
                constant=False,
                order=100,
                probability=100,
                group_name="",
                group_weight=100,
                match_mode="or",
                position=AUTO_POSITION,
                depth=AUTO_DEPTH,
                source="auto",
                enabled=True,
            )
        )
        existing.add(fingerprint)
        inserted += 1
    db.commit()
    return inserted


# ── 内部实现 ──


def _parse_draft(reply: str) -> MemoryDraft | None:
    """剥围栏 + 严格 JSON 解析 + 字段校验；任何失败 → None"""
    text = (reply or "").strip()
    fence = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.DOTALL)
    if fence:
        text = fence.group(1).strip()
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, TypeError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    title = data.get("title")
    keys = data.get("keys")
    content = data.get("content")
    if not isinstance(title, str) or not isinstance(content, str):
        return None
    if not isinstance(keys, list) or not all(isinstance(k, str) and k.strip() for k in keys):
        return None
    return MemoryDraft(title=title, keys=[k.strip() for k in keys], content=content)


def _role_str(role: object) -> str:
    """消息角色归一（委托 text_utils.role_str，F-94 收敛）"""
    from backend.app.services.text_utils import role_str

    return role_str(role)