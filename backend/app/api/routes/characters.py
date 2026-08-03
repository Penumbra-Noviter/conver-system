"""
角色 REST API 路由
"""

from __future__ import annotations

from urllib.parse import quote

from fastapi import APIRouter, Body, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.character import CharacterCreate, CharacterResponse, CharacterUpdate
from backend.app.services import character as service
from backend.app.services.character_card import from_v2_card, to_v2_card

router = APIRouter(prefix="/api/characters", tags=["角色管理"])


@router.get("", response_model=list[CharacterResponse])
def list_characters(db: Session = Depends(get_db)) -> list[CharacterResponse]:
    """获取所有角色"""
    return service.list_characters(db)


@router.get("/{character_id}", response_model=CharacterResponse)
def get_character(character_id: int, db: Session = Depends(get_db)) -> CharacterResponse:
    """获取单个角色"""
    char = service.get_character_with_count(db, character_id)
    if not char:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="角色不存在")
    return char


@router.post("", response_model=CharacterResponse, status_code=status.HTTP_201_CREATED)
def create_character(data: CharacterCreate, db: Session = Depends(get_db)) -> CharacterResponse:
    """创建新角色"""
    return service.create_character(db, data)


@router.put("/{character_id}", response_model=CharacterResponse)
def update_character(character_id: int, data: CharacterUpdate, db: Session = Depends(get_db)) -> CharacterResponse:
    """更新角色"""
    char = service.update_character(db, character_id, data)
    if not char:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="角色不存在")
    return char


@router.delete("/{character_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_character(character_id: int, db: Session = Depends(get_db)) -> None:
    """删除角色（级联删除关联对话和消息）"""
    if not service.delete_character(db, character_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="角色不存在")


@router.get("/{character_id}/export")
def export_character(character_id: int, db: Session = Depends(get_db)) -> JSONResponse:
    """导出角色为 SillyTavern V2 角色卡（JSON 附件下载）"""
    char = service.get_character(db, character_id)
    if not char:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="角色不存在")

    filename = quote(f"{char.name}.json")
    return JSONResponse(
        content=to_v2_card(char),
        media_type="application/json",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{filename}"},
    )


@router.post("/import", response_model=CharacterResponse, status_code=status.HTTP_201_CREATED)
def import_character(card: dict, db: Session = Depends(get_db)) -> CharacterResponse:
    """从 SillyTavern V2 角色卡 JSON 导入角色（V2 信封 / 裸 data / V1 旧卡）

    流程：from_v2_card 归一化 → 直接新建落库（D3 允许重名），
    不校验完整性（D6 导入路径不参与完整性引导）。
    无法识别的卡 / 缺 name → 422 友好报错。
    """
    try:
        data = from_v2_card(card)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"导入失败：{exc}",
        ) from exc
    return service.create_character(db, data)
