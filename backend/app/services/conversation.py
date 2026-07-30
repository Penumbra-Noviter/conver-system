"""
对话 CRUD 业务逻辑
"""

from __future__ import annotations

from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message
from backend.app.models.setting import Setting
from backend.app.schemas.conversation import ConversationCreate, ConversationUpdate


def list_conversations(db: Session, character_id: Optional[int] = None) -> list[dict]:
    """获取对话列表，附带消息数量"""
    query = db.query(
        Conversation,
        func.count(Message.id).label("message_count"),
    ).outerjoin(
        Message, Message.conversation_id == Conversation.id
    ).group_by(Conversation.id)

    if character_id is not None:
        query = query.filter(Conversation.character_id == character_id)

    results = query.order_by(Conversation.updated_at.desc()).all()

    output = []
    for conv, count in results:
        d = {
            "id": conv.id,
            "character_id": conv.character_id,
            "title": conv.title,
            "model_provider": conv.model_provider,
            "model_name": conv.model_name,
            "message_count": count,
            "created_at": conv.created_at,
            "updated_at": conv.updated_at,
        }
        output.append(d)
    return output


def get_conversation(db: Session, conversation_id: int) -> Optional[Conversation]:
    """获取单个对话"""
    return db.query(Conversation).filter(Conversation.id == conversation_id).first()


def create_conversation(db: Session, data: ConversationCreate) -> Conversation:
    """创建对话，未指定模型时从 settings 表读取默认值"""
    # 从 settings 表读取默认 provider/model（若传参为空或为默认值但 settings 中有值）
    provider = data.model_provider
    model_name = data.model_name

    if provider == "claude" and model_name == "claude-sonnet-4-20250514":
        # 使用了默认值，检查 settings 是否有覆盖
        default_provider = db.query(Setting).filter(Setting.key == "default_provider").first()
        default_model = db.query(Setting).filter(Setting.key == "default_model").first()
        if default_provider and default_provider.value:
            provider = default_provider.value
        if default_model and default_model.value:
            model_name = default_model.value

    conv = Conversation(
        character_id=data.character_id,
        title=data.title,
        model_provider=provider,
        model_name=model_name,
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)
    return conv


def update_conversation(db: Session, conversation_id: int, data: ConversationUpdate) -> Optional[Conversation]:
    """更新对话"""
    conv = get_conversation(db, conversation_id)
    if not conv:
        return None
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(conv, field, value)
    db.commit()
    db.refresh(conv)
    return conv


def delete_conversation(db: Session, conversation_id: int) -> bool:
    """删除对话及关联消息（级联）"""
    conv = get_conversation(db, conversation_id)
    if not conv:
        return False
    db.delete(conv)
    db.commit()
    return True


def delete_all_conversations(db: Session) -> None:
    """清空所有对话及关联消息"""
    from backend.app.models.message import Message
    db.query(Message).delete()
    db.query(Conversation).delete()
    db.commit()


def export_conversation_json(db: Session, conversation_id: int) -> dict | None:
    """导出对话为 JSON 格式"""
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if not conv:
        return None

    character = db.query(Character).filter(Character.id == conv.character_id).first()

    messages = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.asc())
        .all()
    )

    character_data = None
    if character:
        character_data = {
            "id": character.id,
            "name": character.name,
            "description": character.description,
            "personality": character.personality,
            "scenario": character.scenario,
            "first_mes": character.first_mes,
            "system_prompt": character.system_prompt,
            "avatar": character.avatar,
            "temperature": character.temperature,
        }

    messages_data = []
    for msg in messages:
        messages_data.append({
            "id": msg.id,
            "role": msg.role,
            "content": msg.content,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
        })

    return {
        "conversation": {
            "id": conv.id,
            "title": conv.title,
            "model_provider": conv.model_provider,
            "model_name": conv.model_name,
            "created_at": conv.created_at.isoformat() if conv.created_at else None,
            "updated_at": conv.updated_at.isoformat() if conv.updated_at else None,
        },
        "character": character_data,
        "messages": messages_data,
    }


def export_conversation_markdown(db: Session, conversation_id: int) -> str | None:
    """导出对话为 Markdown 格式"""
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if not conv:
        return None

    character = db.query(Character).filter(Character.id == conv.character_id).first()

    messages = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.asc())
        .all()
    )

    character_name = character.name if character else "未知角色"
    character_info_parts = []
    if character:
        if character.description:
            character_info_parts.append(character.description)
        if character.personality:
            character_info_parts.append(f"人格: {character.personality}")
        if character.scenario:
            character_info_parts.append(f"场景: {character.scenario}")
    character_info = "；".join(character_info_parts) if character_info_parts else "无"

    lines = [f"# 与 {character_name} 的对话", ""]
    lines.append(f"**角色信息**: {character_info}")
    lines.append(f"**模型**: {conv.model_provider}/{conv.model_name}")

    created_str = conv.created_at.strftime("%Y-%m-%d %H:%M") if conv.created_at else "未知"
    lines.append(f"**时间**: {created_str}")
    lines.append("")
    lines.append("---")
    lines.append("")

    current_date = None
    for msg in messages:
        if msg.created_at:
            msg_date = msg.created_at.strftime("%Y-%m-%d")
            msg_time = msg.created_at.strftime("%Y-%m-%d %H:%M")
        else:
            msg_date = None
            msg_time = "未知时间"

        if msg_date != current_date:
            if current_date is not None:
                lines.append("---")
                lines.append("")
            lines.append(f"### {msg_date}")
            lines.append("")
            current_date = msg_date

        lines.append(f"**{msg.role}**: {msg.content}")
        lines.append("")

    return "\n".join(lines)
