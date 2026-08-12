"""
聊天 REST API 路由

包含：
    - POST /api/chats — 非流式聊天
    - POST /api/chats/stream — 流式聊天（SSE）

业务逻辑（聊天回合编排 / LLM 错误映射 / 流式持久化）收拢在 services/chat.py；
领域异常（对话不存在/缺 Key/Provider 不支持）直接上抛，由统一 exception handler
（api/errors.py）转 404/400；LLM 错误经 complete_chat 显式 raise HTTPException，
由 FastAPI 原生处理。本文件只保留路由声明与 SSE data: 帧包装。
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import chat as chat_service

router = APIRouter(tags=["聊天"])


@router.post("/api/chats", response_model=ChatResponse)
async def create_chat(request: ChatRequest, db: Session = Depends(get_db)) -> ChatResponse:
    """非流式聊天 — 接入真实 LLM（回合业务在 services/chat.py complete_chat）

    领域异常上抛（统一 handler 转 404/400）；LLMError 在 complete_chat 内
    显式 raise HTTPException（带 provider 上下文），FastAPI 原生处理。
    """
    return await chat_service.complete_chat(db, request)


@router.post("/api/chats/stream")
async def stream_chat(
    request: ChatRequest,
    raw_request: Request,
    db: Session = Depends(get_db),
) -> StreamingResponse:
    """流式聊天（SSE）— 逐 token 返回

    客户端断开（停止生成）时停止 LLM 调用，并保存已生成的部分内容为 assistant 消息。
    领域异常（prepare_chat）在流构造前上抛，由统一 handler 转 JSON 响应；
    流内 LLM 错误仍由 services/chat.py 产出 error 帧（不走 HTTP handler）。
    """
    ctx = chat_service.prepare_chat(db, request)

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
