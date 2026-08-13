"""
角色 REST API 路由
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from backend.app.api.headers import build_content_disposition
from backend.app.database import get_db
from backend.app.schemas.character import CharacterCreate, CharacterResponse, CharacterUpdate, DocParseRequest, DocParseResponse
from backend.app.services import character as service
from backend.app.services.character_card import from_v2_card, to_v2_card
from backend.app.services.document_parser import parse_document

router = APIRouter(prefix="/api/characters", tags=["角色管理"])


@router.get("", response_model=list[CharacterResponse])
def list_characters(db: Session = Depends(get_db)) -> list[CharacterResponse]:
    """获取所有角色"""
    return service.list_characters(db)


@router.get("/{character_id}", response_model=CharacterResponse)
def get_character(character_id: int, db: Session = Depends(get_db)) -> CharacterResponse:
    """获取单个角色"""
    return service.require_character(db, character_id)


@router.post("", response_model=CharacterResponse, status_code=status.HTTP_201_CREATED)
def create_character(data: CharacterCreate, db: Session = Depends(get_db)) -> CharacterResponse:
    """创建新角色"""
    return service.create_character(db, data)


@router.put("/{character_id}", response_model=CharacterResponse)
def update_character(character_id: int, data: CharacterUpdate, db: Session = Depends(get_db)) -> CharacterResponse:
    """更新角色"""
    service.require_character(db, character_id)
    return service.update_character(db, character_id, data)


@router.delete("/{character_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_character(character_id: int, db: Session = Depends(get_db)) -> None:
    """删除角色（级联删除关联对话和消息）"""
    service.require_character(db, character_id)
    service.delete_character(db, character_id)


@router.get("/{character_id}/export")
def export_character(character_id: int, db: Session = Depends(get_db)) -> JSONResponse:
    """导出角色为 SillyTavern V2 角色卡（JSON 附件下载）"""
    char = service.require_character(db, character_id)
    return JSONResponse(
        content=to_v2_card(char),
        media_type="application/json",
        headers={
            "Content-Disposition": build_content_disposition(
                f"character-{character_id}.json",
                f"{char.name}.json",
            )
        },
    )


@router.post("/parse-document", response_model=DocParseResponse)
async def parse_character_document(
    request: DocParseRequest,
    db: Session = Depends(get_db),
) -> DocParseResponse:
    """使用 LLM 从文档中提取角色卡字段（智能解析）

    用户粘贴角色设定文档 → LLM 自动提取 name / personality / first_mes 等字段 → 返回结构化数据。
    前端可将结果预填入创建向导的各步骤。
    DocParseError 上抛，由统一 exception handler 转 422 + 纯原因。
    """
    return await parse_document(db, request.text, request.provider, request.model)


@router.post("/import", response_model=CharacterResponse, status_code=status.HTTP_201_CREATED)
def import_character(card: dict, db: Session = Depends(get_db)) -> CharacterResponse:
    """从 SillyTavern V2 角色卡 JSON 导入角色（V2 信封 / 裸 data / V1 旧卡）

    流程：from_v2_card 归一化 → 直接新建落库（D3 允许重名），
    不校验完整性（D6 导入路径不参与完整性引导）。
    无法识别的卡 / 缺 name → CardFormatError / CardValidationError 上抛，
    由统一 exception handler 转 422 友好报错（格式错误附带支持格式说明，引导改用向导）。
    """
    data = from_v2_card(card)
    return service.create_character(db, data)
