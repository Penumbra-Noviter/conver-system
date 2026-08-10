"""
消息管理 & 聊天逻辑
"""

from __future__ import annotations

import datetime

from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, Role
from backend.app.schemas.message import SearchResult
from backend.app.services import conversation as conversation_service
from backend.app.services.llm.prompt import CharacterData, apply_template_vars, build_messages


def get_messages(db: Session, conversation_id: int) -> list[Message]:
    """获取对话的所有消息（按时间正序）"""
    return (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.asc())
        .all()
    )


def create_message(db: Session, conversation_id: int, role: Role, content: str) -> Message:
    """保存单条消息，同时更新对话的 updated_at 时间戳

    保存首条 user 消息时，若标题仍为占位默认值则同步替换为规则截断标题
    （规则收口于 conversation_service.maybe_auto_title，见 ARC-3）。
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if conv:
        conv.updated_at = datetime.datetime.now()
        if role == Role.USER:
            conversation_service.maybe_auto_title(db, conv, content)

    msg = Message(conversation_id=conversation_id, role=role, content=content)
    db.add(msg)

    db.commit()
    db.refresh(msg)
    return msg


def auto_insert_greeting(
    db: Session,
    conversation_id: int,
    user_name: str = "User",
) -> Message | None:
    """如果是对话的第一条消息且角色有 greeting，自动插入开场白

    在用户发送首条消息时调用，插入角色的 greeting 作为第一条 assistant 消息。
    支持 {{user}}/{{char}} 模板变量替换。
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if not conv:
        return None

    # 检查是否已有消息（包括 greeting）
    existing = db.query(Message).filter(Message.conversation_id == conversation_id).first()
    if existing:
        return None  # 已有消息，不重复插入

    # 获取角色的 greeting
    character = db.query(Character).filter(Character.id == conv.character_id).first()
    if not character or not character.first_mes:
        return None

    # 模板变量替换（纯函数来自 services/llm/prompt.py）
    greeting = apply_template_vars(character.first_mes, user_name, character.name)

    # 插入 greeting 作为 assistant 消息
    return create_message(db, conversation_id, Role.ASSISTANT, greeting)


def build_message_list(
    db: Session,
    conversation: Conversation,
    user_content: str,
    max_rounds: int = 30,
    user_name: str = "User",
) -> list[dict]:
    """构建发送给 LLM 的消息列表

    组装顺序：
        1. character.system_prompt 或 personality（作为 system prompt，支持模板变量）
        2. character.scenario（场景设定，支持模板变量）
        3. character.mes_example（对话范例，支持模板变量）
        4. 历史消息（按时间正序，受滑窗限制）
        5. character.post_history_instructions（历史后指令，支持模板变量）
        6. 当前用户输入（支持模板变量）

    查询角色与历史消息后，委托给 services/llm/prompt.py 的纯函数完成组装。

    模板变量：
        {{user}} — 用户昵称
        {{char}} — 角色名称
    """
    character = db.query(Character).filter(Character.id == conversation.character_id).first()
    if not character:
        raise ValueError(f"角色不存在: {conversation.character_id}")

    char_data = CharacterData(
        name=character.name or "",
        system_prompt=character.system_prompt or "",
        personality=character.personality or "",
        scenario=character.scenario or "",
        mes_example=character.mes_example or "",
        post_history_instructions=character.post_history_instructions or "",
    )
    history = get_messages(db, conversation.id)

    return build_messages(
        character=char_data,
        history=history,
        user_content=user_content,
        max_rounds=max_rounds,
        user_name=user_name,
    )


def search_messages(
    db: Session,
    query: str,
    limit: int = 50,
) -> list[SearchResult]:
    """搜索消息内容，返回带对话和角色上下文的搜索结果

    使用 SQLite LIKE 进行关键词匹配，按时间倒序排列。
    每条结果包含：消息预览、所属对话标题、角色名、角色头像、发送时间。
    返回 `list[SearchResult]`（字段契约见 schemas/message.py）。
    """
    if not query or not query.strip():
        return []

    q = f"%{query.strip()}%"

    results = (
        db.query(Message, Conversation, Character)
        .join(Conversation, Message.conversation_id == Conversation.id)
        .join(Character, Conversation.character_id == Character.id)
        .filter(Message.content.ilike(q))
        .order_by(Message.created_at.desc())
        .limit(limit)
        .all()
    )

    output = []
    for msg, conv, char in results:
        # 截取关键词周围的上下文片段
        content = msg.content or ""
        lower_content = content.lower()
        lower_query = query.strip().lower()
        idx = lower_content.find(lower_query)

        if idx >= 0:
            ctx_start = max(0, idx - 50)
            ctx_end = min(len(content), idx + len(query) + 50)
            prefix = "…" if ctx_start > 0 else ""
            suffix = "…" if ctx_end < len(content) else ""
            preview = prefix + content[ctx_start:ctx_end] + suffix
        else:
            preview = content[:120] + ("…" if len(content) > 120 else "")

        output.append(SearchResult(
            message_id=msg.id,
            conversation_id=conv.id,
            conversation_title=conv.title,
            character_id=char.id,
            character_name=char.name,
            character_avatar=char.avatar,
            role=msg.role.value,
            content_preview=preview,
            created_at=msg.created_at.isoformat() if msg.created_at else None,
        ))

    return output
