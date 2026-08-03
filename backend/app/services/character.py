"""
角色 CRUD 业务逻辑
"""

from __future__ import annotations

from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.schemas.character import CharacterCreate, CharacterUpdate


def list_characters(db: Session) -> list[Character]:
    """获取所有角色，附带对话数量，按更新时间倒序"""
    query = db.query(
        Character,
        func.count(Conversation.id).label("conversation_count"),
    ).outerjoin(
        Conversation, Conversation.character_id == Character.id
    ).group_by(Character.id).order_by(Character.updated_at.desc())

    results = []
    for char, count in query.all():
        char.conversation_count = count
        results.append(char)
    return results


def get_character(db: Session, character_id: int) -> Optional[Character]:
    """获取单个角色（ORM 对象，供内部使用）"""
    return db.query(Character).filter(Character.id == character_id).first()


def get_character_with_count(db: Session, character_id: int) -> Optional[Character]:
    """获取单个角色（附带对话数量，供 API 路由使用）"""
    query = db.query(
        Character,
        func.count(Conversation.id).label("conversation_count"),
    ).outerjoin(
        Conversation, Conversation.character_id == Character.id
    ).filter(Character.id == character_id).group_by(Character.id)

    result = query.first()
    if not result:
        return None

    char, count = result
    char.conversation_count = count
    return char


def create_character(db: Session, data: CharacterCreate) -> Character:
    """创建角色"""
    char = Character(**data.model_dump())
    db.add(char)
    db.commit()
    db.refresh(char)
    return char


def update_character(db: Session, character_id: int, data: CharacterUpdate) -> Optional[Character]:
    """更新角色（部分更新）"""
    char = get_character(db, character_id)
    if not char:
        return None
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(char, field, value)
    db.commit()
    db.refresh(char)
    return char


def delete_character(db: Session, character_id: int) -> bool:
    """删除角色及关联对话、消息（级联）"""
    char = get_character(db, character_id)
    if not char:
        return False
    db.delete(char)
    db.commit()
    return True
