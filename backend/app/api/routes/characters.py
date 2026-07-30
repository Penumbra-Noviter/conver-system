"""
角色 REST API 路由
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from backend.app.api.deps import get_db
from backend.app.schemas.character import CharacterCreate, CharacterResponse, CharacterUpdate
from backend.app.services import character as service

router = APIRouter(prefix="/api/characters", tags=["角色管理"])


@router.get("", response_model=list[CharacterResponse])
def list_characters(db: Session = Depends(get_db)):
    """获取所有角色"""
    return service.list_characters(db)


@router.get("/{character_id}", response_model=CharacterResponse)
def get_character(character_id: int, db: Session = Depends(get_db)):
    """获取单个角色"""
    char = service.get_character_with_count(db, character_id)
    if not char:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="角色不存在")
    return char


@router.post("", response_model=CharacterResponse, status_code=status.HTTP_201_CREATED)
def create_character(data: CharacterCreate, db: Session = Depends(get_db)):
    """创建新角色"""
    return service.create_character(db, data)


@router.put("/{character_id}", response_model=CharacterResponse)
def update_character(character_id: int, data: CharacterUpdate, db: Session = Depends(get_db)):
    """更新角色"""
    char = service.update_character(db, character_id, data)
    if not char:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="角色不存在")
    return char


@router.delete("/{character_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_character(character_id: int, db: Session = Depends(get_db)):
    """删除角色（级联删除关联对话和消息）"""
    if not service.delete_character(db, character_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="角色不存在")
