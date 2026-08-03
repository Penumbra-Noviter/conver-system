"""
消息管理 & 聊天逻辑
"""

from __future__ import annotations

import datetime

from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, Role
from backend.app.services import conversation as conversation_service


def _apply_template_vars(text: str, user_name: str = "User", char_name: str = "Character") -> str:
    """替换文本中的模板变量

    支持变量:
        {{user}}  — 用户昵称（从设置读取）
        {{char}}  — 角色名称（从角色数据读取）
    """
    if not text:
        return text
    text = text.replace("{{user}}", user_name)
    text = text.replace("{{char}}", char_name)
    return text


def get_messages(db: Session, conversation_id: int) -> list[Message]:
    """获取对话的所有消息（按时间正序）"""
    return (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.asc())
        .all()
    )


def _auto_title_on_first_user_message(
    db: Session, conv: Conversation, content: str
) -> None:
    """首条 user 消息且标题仍为占位默认值时，用规则截断标题替换（P3.5）

    调用时机：create_message 保存 user 消息之前（避免 autoflush 把本条算作已有 user 消息）。
    """
    if not conv or not content:
        return
    existing_user = (
        db.query(Message)
        .filter(Message.conversation_id == conv.id, Message.role == Role.USER)
        .first()
    )
    if existing_user is not None:
        return  # 本条不是首条 user 消息
    if conv.title != conversation_service.default_conversation_title(db, conv.id):
        return  # 标题已被显式命名，不覆盖
    conv.title = conversation_service.truncate_title(content)


def create_message(db: Session, conversation_id: int, role: Role, content: str) -> Message:
    """保存单条消息，同时更新对话的 updated_at 时间戳

    保存首条 user 消息时，若标题仍为占位默认值则同步替换为规则截断标题。
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if conv:
        conv.updated_at = datetime.datetime.now()
        if role == Role.USER:
            _auto_title_on_first_user_message(db, conv, content)

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

    # 模板变量替换
    greeting = _apply_template_vars(character.first_mes, user_name, character.name)

    # 插入 greeting 作为 assistant 消息
    return create_message(db, conversation_id, Role.ASSISTANT, greeting)


def _parse_mes_example(mes_example: str, user_name: str = "User", char_name: str = "Character") -> list[dict]:
    """解析 mes_example 对话范例为 user/assistant 消息序列

    支持 <START> 分隔的多轮范例，每行格式为 {{user}}: 或 {{char}}: 开头。
    参考 SillyTavern V2 规范，{{user}} 映射为 user 角色，{{char}} 映射为 assistant 角色。
    同时替换消息内容中的 {{user}}/{{char}} 模板变量。
    """
    if not mes_example or not mes_example.strip():
        return []

    messages: list[dict] = []
    # 按 <START> 分隔多轮范例
    blocks = mes_example.split('<START>')

    for block in blocks:
        block = block.strip()
        if not block:
            continue

        for line in block.split('\n'):
            line = line.strip()
            if not line:
                continue
            if line.startswith('{{user}}'):
                content = line[len('{{user}}'):].lstrip(':').strip()
                if content:
                    messages.append({
                        "role": "user",
                        "content": _apply_template_vars(content, user_name, char_name),
                    })
            elif line.startswith('{{char}}'):
                content = line[len('{{char}}'):].lstrip(':').strip()
                if content:
                    messages.append({
                        "role": "assistant",
                        "content": _apply_template_vars(content, user_name, char_name),
                    })

    return messages


def build_message_list(
    db: Session,
    conversation: Conversation,
    user_content: str,
    max_rounds: int = 30,
    user_name: str = "User",
) -> list[dict]:
    """构建发送给 LLM 的消息列表

    组装顺序：
        1. character.personality（作为 system prompt，支持模板变量）
        2. character.scenario（场景设定，支持模板变量）
        3. character.mes_example（对话范例，支持模板变量）
        4. 历史消息（按时间正序，受滑窗限制）
        5. character.post_history_instructions（历史后指令，支持模板变量）
        6. 当前用户输入（支持模板变量）

    模板变量：
        {{user}} — 用户昵称
        {{char}} — 角色名称
    """
    character = db.query(Character).filter(Character.id == conversation.character_id).first()
    if not character:
        raise ValueError(f"角色不存在: {conversation.character_id}")

    char_name = character.name or "Character"

    # system prompt（优先使用 system_prompt 字段，其次 personality）
    system_content = character.system_prompt or character.personality
    system_content = _apply_template_vars(system_content, user_name, char_name)
    messages: list[dict] = [{"role": "system", "content": system_content}]

    # 场景设定（scenario）— 附加在 system prompt 后，作为补充上下文
    if character.scenario:
        scenario = _apply_template_vars(character.scenario, user_name, char_name)
        messages.append({"role": "system", "content": f"[场景设定]\n{scenario}"})

    # 对话范例（mes_example）— 作为 few-shot 示例插入
    if character.mes_example:
        examples = _parse_mes_example(character.mes_example, user_name, char_name)
        messages.extend(examples)

    # 历史消息（滑窗截断，保留最近 N 轮对话）
    history = get_messages(db, conversation.id)
    if len(history) > max_rounds * 2:
        history = history[-(max_rounds * 2):]

    for msg in history:
        messages.append({"role": msg.role.value, "content": msg.content})

    # 历史后指令（post_history_instructions）— 附加在历史消息之后、当前输入之前
    if character.post_history_instructions:
        phi = _apply_template_vars(character.post_history_instructions, user_name, char_name)
        messages.append({"role": "system", "content": phi})

    # 当前输入
    content = _apply_template_vars(user_content, user_name, char_name)
    messages.append({"role": "user", "content": content})

    return messages


def search_messages(
    db: Session,
    query: str,
    limit: int = 50,
) -> list[dict]:
    """搜索消息内容，返回带对话和角色上下文的搜索结果

    使用 SQLite LIKE 进行关键词匹配，按时间倒序排列。
    每条结果包含：消息预览、所属对话标题、角色名、角色头像、发送时间。
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

        output.append({
            "message_id": msg.id,
            "conversation_id": conv.id,
            "conversation_title": conv.title,
            "character_id": char.id,
            "character_name": char.name,
            "character_avatar": char.avatar,
            "role": msg.role.value,
            "content_preview": preview,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
        })

    return output
