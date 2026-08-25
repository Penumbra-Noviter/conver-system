"""
对话 REST API 路由
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse, PlainTextResponse
from sqlalchemy.orm import Session

from backend.app.api.headers import build_content_disposition
from backend.app.database import get_db
from backend.app.schemas.conversation import ConversationCreate, ConversationResponse, ConversationUpdate
from backend.app.services import conversation as service
from backend.app.services import conversation_export as export_service

router = APIRouter(prefix="/api/conversations", tags=["对话管理"])


@router.get("", response_model=list[ConversationResponse])
def list_conversations(
    character_id: Optional[int] = Query(None, description="按角色筛选"),
    db: Session = Depends(get_db),
) -> list[ConversationResponse]:
    """获取对话列表"""
    return service.list_conversations(db, character_id)


@router.get("/{conversation_id}", response_model=ConversationResponse)
def get_conversation(conversation_id: int, db: Session = Depends(get_db)) -> ConversationResponse:
    """获取单个对话"""
    return service.require_conversation(db, conversation_id)


@router.post("", response_model=ConversationResponse, status_code=status.HTTP_201_CREATED)
def create_conversation(data: ConversationCreate, db: Session = Depends(get_db)) -> ConversationResponse:
    """创建新对话"""
    return service.create_conversation(db, data)


@router.put("/{conversation_id}", response_model=ConversationResponse)
def update_conversation(conversation_id: int, data: ConversationUpdate, db: Session = Depends(get_db)) -> ConversationResponse:
    """更新对话"""
    service.require_conversation(db, conversation_id)
    return service.update_conversation(db, conversation_id, data)


@router.delete("/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_conversation(conversation_id: int, db: Session = Depends(get_db)) -> None:
    """删除对话（级联删除消息）"""
    service.require_conversation(db, conversation_id)
    service.delete_conversation(db, conversation_id)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_all_conversations(db: Session = Depends(get_db)) -> None:
    """清空所有对话（级联删除所有消息）"""
    service.delete_all_conversations(db)


@router.get("/{conversation_id}/export/json")
def export_conversation_json(conversation_id: int, db: Session = Depends(get_db)) -> JSONResponse:
    """导出对话为 JSON 格式文件"""
    data = export_service.export_conversation_json(db, conversation_id)
    if not data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")

    character_name = export_service.character_export_filename(db, conversation_id)
    return JSONResponse(
        content=data,
        media_type="application/json",
        headers={
            "Content-Disposition": build_content_disposition(
                f"conversation-{conversation_id}.json",
                f"conversation-{conversation_id}-{character_name}.json",
            )
        },
    )


@router.get("/{conversation_id}/export/markdown")
def export_conversation_markdown(conversation_id: int, db: Session = Depends(get_db)) -> PlainTextResponse:
    """导出对话为 Markdown 格式文件"""
    md = export_service.export_conversation_markdown(db, conversation_id)
    if not md:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")

    character_name = export_service.character_export_filename(db, conversation_id)
    return PlainTextResponse(
        content=md,
        media_type="text/markdown; charset=utf-8",
        headers={
            "Content-Disposition": build_content_disposition(
                f"conversation-{conversation_id}.md",
                f"conversation-{conversation_id}-{character_name}.md",
            )
        },
    )
