"""
消息查询 REST API 路由

包含：
    - GET /api/conversations/{id}/messages — 获取消息历史
    - GET /api/messages/search — 搜索消息
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.message import MessageResponse, SearchResult
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service

router = APIRouter(tags=["消息"])


@router.get(
    "/api/conversations/{conversation_id}/messages",
    response_model=list[MessageResponse],
)
def get_messages(conversation_id: int, db: Session = Depends(get_db)) -> list[MessageResponse]:
    """获取对话的消息历史（按时间正序）"""
    conv = conversation_service.get_conversation(db, conversation_id)
    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")
    return message_service.get_messages(db, conversation_id)


@router.get("/api/messages/search", response_model=list[SearchResult])
def search_messages(
    q: str = Query("", description="搜索关键词"),
    limit: int = Query(50, description="最大返回条数"),
    db: Session = Depends(get_db),
) -> list[SearchResult]:
    """搜索消息内容（关键词匹配）

    返回包含关键词的消息列表，每条附带对话标题和角色信息。
    """
    results = message_service.search_messages(db, q, limit=limit)
    return results
