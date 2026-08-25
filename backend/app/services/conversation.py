"""
对话 CRUD 业务逻辑
"""

from __future__ import annotations

from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate, ConversationUpdate
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import ConversationNotFoundError
from backend.app.services.llm.prompt import apply_template_vars


def list_conversations(db: Session, character_id: Optional[int] = None) -> list[Conversation]:
    """获取对话列表，附带消息数量"""
    query = db.query(
        Conversation,
        func.count(Message.id).label("message_count"),
    ).outerjoin(
        Message, Message.conversation_id == Conversation.id
    ).group_by(Conversation.id)

    if character_id is not None:
        query = query.filter(Conversation.character_id == character_id)

    results = []
    for conv, count in query.order_by(Conversation.updated_at.desc()).all():
        conv.message_count = count
        results.append(conv)
    return results


def get_conversation(db: Session, conversation_id: int) -> Optional[Conversation]:
    """获取单个对话"""
    return db.query(Conversation).filter(Conversation.id == conversation_id).first()


def require_conversation(db: Session, conversation_id: int) -> Conversation:
    """获取对话，不存在时抛 ConversationNotFoundError（深函数）

    路由层「不存在」守卫统一走此处：内部 get + 领域异常上抛，
    由统一 exception handler 转 404，不再各写各的 HTTPException。
    """
    conv = get_conversation(db, conversation_id)
    if not conv:
        raise ConversationNotFoundError("对话不存在")
    return conv


def _default_title_for_character(char_name: str | None) -> str:
    """生成对话占位默认标题「与 {角色名} 的对话」"""
    return f"与 {char_name or '角色'} 的对话"


def truncate_title(text: str, max_len: int = 20) -> str:
    """规则截断对话标题（纯函数）

    折叠所有空白为单空格并去首尾，截取前 max_len 个字符后追加「…」；
    不剥离 Markdown 语法（原样截断字符）。
    """
    collapsed = " ".join(text.split())
    if len(collapsed) <= max_len:
        return collapsed
    return collapsed[:max_len] + "…"


def default_conversation_title(db: Session, conversation_id: int) -> str:
    """返回对话当前的占位默认标题

    用于判断标题是否仍为自动生成的占位值（首条 user 消息后应被替换）。
    """
    conv = get_conversation(db, conversation_id)
    if not conv:
        return "新对话"
    character = db.query(Character).filter(Character.id == conv.character_id).first()
    return _default_title_for_character(character.name if character else None)


def maybe_auto_title(db: Session, conv: Conversation, content: str) -> None:
    """首条 user 消息且标题仍为占位默认值时，用规则截断标题替换

    标题生命周期（占位默认 → 首条替换）在此一文件收口：
        - 占位默认：`_default_title_for_character`（「与 {角色名} 的对话」）
        - 截断：`truncate_title`
        - 替换：本函数，仅在首条 user 消息且标题未被显式命名时发生

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
    if conv.title != default_conversation_title(db, conv.id):
        return  # 标题已被显式命名，不覆盖
    conv.title = truncate_title(content)


def create_conversation(db: Session, data: ConversationCreate) -> Conversation:
    """创建对话

    标题：未显式传 title（或传空）时默认「与 {角色名} 的对话」；
    模型：未显式传 model_provider/model_name 时回退到 settings 默认值（再回退到 config 默认值）。
    """
    character = db.query(Character).filter(Character.id == data.character_id).first()
    title = (
        data.title
        if "title" in data.model_fields_set and data.title
        else _default_title_for_character(character.name if character else None)
    )
    # 仅当请求显式传入 model_provider/model_name 时采用；否则用 settings 默认值（未设置时用 config 默认值）
    provider = (
        data.model_provider
        if "model_provider" in data.model_fields_set
        else setting_service.default_provider(db)
    )
    model_name = (
        data.model_name
        if "model_name" in data.model_fields_set
        else setting_service.default_model(db)
    )

    conv = Conversation(
        character_id=data.character_id,
        title=title,
        model_provider=provider,
        model_name=model_name,
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)

    # 预插开场白：创建对话时把角色的 first_mes 插入为首条 assistant 消息
    if character and character.first_mes:
        user_name = (setting_service.get_value(db, 'user_name') or 'User')
        greeting = apply_template_vars(character.first_mes, user_name, character.name)
        message_service.create_message(db, conv.id, Role.ASSISTANT, greeting)

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
    db.query(Message).delete()
    db.query(Conversation).delete()
    db.commit()
