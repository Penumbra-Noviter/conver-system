"""
世界书条目 REST API 路由（WL-4）

包含：
    - GET    /api/characters/{character_id}/lorebook — 角色世界书条目列表
    - POST   /api/characters/{character_id}/lorebook — 创建条目
    - PUT    /api/lorebook/{entry_id}                 — 部分更新条目
    - DELETE /api/lorebook/{entry_id}                 — 删除条目

路由层只做 HTTP 映射：角色/条目存在性守卫在服务层抛领域异常
（CharacterNotFoundError / LorebookEntryNotFoundError），由统一
exception handler 转 404；请求体校验（keys 数组、数值边界）由
Pydantic Schema 在进入服务层前拦截（422）。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.lorebook import (
    LorebookEntryCreate,
    LorebookEntryResponse,
    LorebookEntryUpdate,
)
from backend.app.services import character as character_service
from backend.app.services import lorebook as lorebook_service

router = APIRouter(tags=["世界书"])


@router.get(
    "/api/characters/{character_id}/lorebook",
    response_model=list[LorebookEntryResponse],
)
def list_lorebook(character_id: int, db: Session = Depends(get_db)) -> list:
    """获取角色世界书条目列表（order 升序、同 order 按 id 稳定）"""
    character_service.require_character(db, character_id)
    return lorebook_service.list_entries(db, character_id)


@router.post(
    "/api/characters/{character_id}/lorebook",
    response_model=LorebookEntryResponse,
)
def create_lorebook(
    character_id: int, payload: LorebookEntryCreate, db: Session = Depends(get_db)
):
    """创建世界书条目（角色不存在 → 404）"""
    character_service.require_character(db, character_id)
    return lorebook_service.create_entry(db, character_id, payload)


@router.put("/api/lorebook/{entry_id}", response_model=LorebookEntryResponse)
def update_lorebook(
    entry_id: int, payload: LorebookEntryUpdate, db: Session = Depends(get_db)
):
    """部分更新世界书条目（仅提交显式字段；条目不存在 → 404）"""
    return lorebook_service.update_entry(db, entry_id, payload)


@router.delete("/api/lorebook/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_lorebook(entry_id: int, db: Session = Depends(get_db)) -> Response:
    """删除世界书条目（条目不存在 → 404）"""
    lorebook_service.delete_entry(db, entry_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
