"""
聊天 REST API 路由

包含：
    - POST /api/chats — 非流式聊天
    - POST /api/chats/stream — 流式聊天（SSE）

业务逻辑（聊天回合编排 / LLM 错误映射 / 流式持久化）收拢在 services/chat.py；
本文件只做 HTTP 映射（领域异常 → HTTPException）与 SSE data: 帧包装。
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import chat as chat_service
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    ConversationNotFoundError,
    ProviderNotSupportedError,
)

router = APIRouter(tags=["聊天"])

#: 领域异常族（prepare_chat / complete_chat 上抛，路由层转 HTTP；映射表在服务层单一来源）
_DOMAIN_ERRORS = (
    ConversationNotFoundError,
    ApiKeyMissingError,
    ProviderNotSupportedError,
)


def _prepare_or_raise(db: Session, request: ChatRequest):
    """调用 prepare_chat，捕获领域异常并转为 HTTPException（经服务层 chat_error_response）"""
    try:
        return chat_service.prepare_chat(db, request)
    except _DOMAIN_ERRORS as e:
        status_code, message = chat_service.chat_error_response(e)
        raise HTTPException(status_code=status_code, detail=message)


@router.post("/api/chats", response_model=ChatResponse)
async def create_chat(request: ChatRequest, db: Session = Depends(get_db)) -> ChatResponse:
    """非流式聊天 — 接入真实 LLM（回合业务在 services/chat.py complete_chat）"""
    try:
        return await chat_service.complete_chat(db, request)
    except _DOMAIN_ERRORS as e:
        status_code, message = chat_service.chat_error_response(e)
        raise HTTPException(status_code=status_code, detail=message)


@router.post("/api/chats/stream")
async def stream_chat(
    request: ChatRequest,
    raw_request: Request,
    db: Session = Depends(get_db),
) -> StreamingResponse:
    """流式聊天（SSE）— 逐 token 返回

    客户端断开（停止生成）时停止 LLM 调用，并保存已生成的部分内容为 assistant 消息。
    """
    ctx = _prepare_or_raise(db, request)

    async def event_generator() -> AsyncIterator[str]:
        """SSE 事件生成器 — 仅做 data: 帧包装，事件由 services/chat.py 产出"""
        async for event in chat_service.stream_reply(
            db,
            request.conversation_id,
            ctx,
            is_disconnected=raw_request.is_disconnected,
        ):
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )
