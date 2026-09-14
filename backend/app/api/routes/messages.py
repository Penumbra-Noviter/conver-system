"""
消息查询 REST API 路由

包含：
    - GET /api/conversations/{id}/messages — 获取消息历史（含候选集/激活序号）
    - GET /api/messages/search — 搜索消息
    - POST /api/messages/{message_id}/switch-swipe — 切换候选（MS-2）
    - PUT /api/messages/{message_id} — 编辑重发（仅 user；message-edit-resend）
    - DELETE /api/messages/{message_id} — 删除单条消息（message-edit-resend）
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.message import (
    ChatResponse,
    EditMessageRequest,
    MessageResponse,
    SearchResult,
    SwitchSwipeRequest,
)
from backend.app.services import chat as chat_service
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


@router.put("/api/messages/{message_id}", response_model=ChatResponse)
async def edit_message(
    message_id: int,
    body: EditMessageRequest,
    db: Session = Depends(get_db),
) -> ChatResponse:
    """编辑重发（仅 user）：就地替换 content 并重新生成后续回复（message-edit-resend）

    编排（替换 content + 物理截断后续 + 重新生成，单 commit 原子落库；LLM 失败
    零落库）收拢在 services/chat.py 的 edit_and_resend。路由先经 message_service
    解析消息归属会话（不存在 → MessageNotFoundError → 404），再委托生成；领域异常
    （MessageNotFoundError / InvalidEditTargetError）上抛由统一 handler 转 404/400。
    响应 ChatResponse（message_id = 新 assistant 消息 id）。
    """
    message = message_service.require_message(db, message_id)
    return await chat_service.edit_and_resend(
        db, message.conversation_id, message_id, body.content
    )


@router.delete("/api/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_message(
    message_id: int,
    db: Session = Depends(get_db),
) -> None:
    """删除单条消息（角色感知：USER 截断其及后续 / ASSISTANT 仅删该条+候选级联）

    删除范围收敛于 services/message.py 的 delete_message（不存在 →
    MessageNotFoundError → 404）。204 No Content。
    """
    message_service.delete_message(db, message_id)
