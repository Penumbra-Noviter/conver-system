"""
聊天 REST API 路由

包含：
    - POST /api/chats — 非流式聊天
    - POST /api/chats/stream — 流式聊天（SSE）

业务逻辑（聊天回合编排 / LLM 错误映射 / 流式持久化）收拢在 services/chat.py；
本文件只做 HTTP 映射与 SSE data: 帧包装。
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.models.message import Role
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import chat as chat_service
from backend.app.services import message as message_service
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    ConversationNotFoundError,
    ProviderNotSupportedError,
)
from backend.app.services.llm.errors import LLMError

router = APIRouter(tags=["聊天"])


# DomainError → HTTP 状态码映射
_DOMAIN_ERROR_MAP: dict[type, int] = {
    ConversationNotFoundError: status.HTTP_404_NOT_FOUND,
    ApiKeyMissingError: status.HTTP_400_BAD_REQUEST,
    ProviderNotSupportedError: status.HTTP_400_BAD_REQUEST,
}


def _prepare_or_raise(db: Session, request: ChatRequest):
    """调用 prepare_chat，捕获领域异常并转为 HTTPException"""
    try:
        return chat_service.prepare_chat(db, request)
    except tuple(_DOMAIN_ERROR_MAP) as e:
        http_status = _DOMAIN_ERROR_MAP.get(type(e), status.HTTP_400_BAD_REQUEST)
        raise HTTPException(status_code=http_status, detail=str(e))


@router.post("/api/chats", response_model=ChatResponse)
async def create_chat(request: ChatRequest, db: Session = Depends(get_db)) -> ChatResponse:
    """非流式聊天 — 接入真实 LLM"""
    ctx = _prepare_or_raise(db, request)

    try:
        reply_text = await ctx.provider.generate(
            ctx.messages,
            temperature=ctx.temperature,
            model=ctx.conversation.model_name,
        )
    except LLMError as e:
        status_code, message = chat_service.llm_error_response(
            e, ctx.conversation.model_provider
        )
        raise HTTPException(status_code=status_code, detail=message)

    saved = message_service.create_message(
        db, request.conversation_id, Role.ASSISTANT, reply_text
    )

    return ChatResponse(
        reply=reply_text,
        message_id=saved.id,
        conversation_id=request.conversation_id,
    )


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
