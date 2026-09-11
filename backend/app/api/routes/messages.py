"""
消息查询 REST API 路由

包含：
    - GET /api/conversations/{id}/messages — 获取消息历史（含候选集/激活序号）
    - GET /api/messages/search — 搜索消息
    - POST /api/messages/{message_id}/switch-swipe — 切换候选（MS-2）
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.message import MessageResponse, SearchResult, SwitchSwipeRequest
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service

router = APIRouter(tags=["消息"])


@router.get(
    "/api/conversations/{conversation_id}/messages",
    response_model=list[MessageResponse],
)
def get_messages(conversation_id: int, db: Session = Depends(get_db)) -> list[MessageResponse]:
    """获取对话的消息历史（按时间正序；assistant 消息附候选集与激活序号，MS-2）"""
    conversation_service.require_conversation(db, conversation_id)
    messages = message_service.get_messages(db, conversation_id)
    return _with_swipes_batch(db, messages)


@router.post(
    "/api/messages/{message_id}/switch-swipe",
    response_model=MessageResponse,
)
def switch_swipe(
    message_id: int, body: SwitchSwipeRequest, db: Session = Depends(get_db)
) -> MessageResponse:
    """切换消息激活候选（越界 → SwipeIndexError → 400）"""
    msg = message_service.switch_swipe(db, message_id, body.index)
    return _with_swipes_batch(db, [msg])[0]


def _with_swipes_batch(db: Session, messages: list) -> list[MessageResponse]:
    """ORM 消息列表 → 响应（候选集批量填充，避免每消息一次查询的 N+1）

    批量取候选逻辑上移服务层（message_service.list_swipes_batch，BR-1 共享单点，
    快照导出复用）；user/system 等无候选消息自然为空列表。
    """
    if not messages:
        return []
    swipes_by_message = message_service.list_swipes_batch(db, [m.id for m in messages])
    responses = [MessageResponse.model_validate(m) for m in messages]
    for resp in responses:
        resp.swipes = swipes_by_message.get(resp.id, [])
    return responses


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
