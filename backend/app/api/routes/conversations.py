"""
对话 REST API 路由
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse, PlainTextResponse
from sqlalchemy.orm import Session

from backend.app.api.deps import get_db
from backend.app.schemas.conversation import ConversationCreate, ConversationResponse, ConversationUpdate
from backend.app.services import conversation as service

router = APIRouter(prefix="/api/conversations", tags=["对话管理"])


@router.get("", response_model=list[ConversationResponse])
def list_conversations(
    character_id: Optional[int] = Query(None, description="按角色筛选"),
    db: Session = Depends(get_db),
):
    """获取对话列表"""
    return service.list_conversations(db, character_id)


@router.get("/{conversation_id}", response_model=ConversationResponse)
def get_conversation(conversation_id: int, db: Session = Depends(get_db)):
    """获取单个对话"""
    conv = service.get_conversation(db, conversation_id)
    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")
    return conv


@router.post("", response_model=ConversationResponse, status_code=status.HTTP_201_CREATED)
def create_conversation(data: ConversationCreate, db: Session = Depends(get_db)):
    """创建新对话"""
    return service.create_conversation(db, data)


@router.put("/{conversation_id}", response_model=ConversationResponse)
def update_conversation(conversation_id: int, data: ConversationUpdate, db: Session = Depends(get_db)):
    """更新对话"""
    conv = service.update_conversation(db, conversation_id, data)
    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")
    return conv


@router.delete("/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_conversation(conversation_id: int, db: Session = Depends(get_db)):
    """删除对话（级联删除消息）"""
    if not service.delete_conversation(db, conversation_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_all_conversations(db: Session = Depends(get_db)):
    """清空所有对话（级联删除所有消息）"""
    service.delete_all_conversations(db)


@router.get("/{conversation_id}/export/json")
def export_conversation_json(conversation_id: int, db: Session = Depends(get_db)):
    """导出对话为 JSON 格式文件"""
    data = service.export_conversation_json(db, conversation_id)
    if not data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")

    character_name = data["character"]["name"].replace(" ", "_") if data.get("character") and data["character"].get("name") else str(conversation_id)
    return JSONResponse(
        content=data,
        media_type="application/json",
        headers={
            "Content-Disposition": f'attachment; filename="conversation-{conversation_id}-{character_name}.json"'
        },
    )


@router.get("/{conversation_id}/export/markdown")
def export_conversation_markdown(conversation_id: int, db: Session = Depends(get_db)):
    """导出对话为 Markdown 格式文件"""
    md = service.export_conversation_markdown(db, conversation_id)
    if not md:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")

    return PlainTextResponse(
        content=md,
        media_type="text/markdown; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="conversation-{conversation_id}.md"'
        },
    )
