"""
聊天 REST API 路由

包含：
    - POST /api/chats — 非流式聊天
    - POST /api/chats/stream — 流式聊天（SSE）
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from dataclasses import dataclass

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Role
from backend.app.models.setting import Setting
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)
from backend.app.services.llm.factory import LLMFactory

router = APIRouter(tags=["聊天"])


# ── 辅助函数 ──


def _get_api_key(db: Session, provider: str) -> str:
    """从 settings 表获取指定 Provider 的 API Key"""
    key_name = f"{provider}_api_key"
    setting = db.query(Setting).filter(Setting.key == key_name).first()
    return setting.value if setting else ""


def _get_sliding_window_rounds(db: Session) -> int:
    """从 settings 表读取滑动窗口轮数配置"""
    setting = db.query(Setting).filter(Setting.key == "sliding_window_rounds").first()
    return int(setting.value) if setting and setting.value else 30


def _get_user_name(db: Session) -> str:
    """从 settings 表读取用户昵称，默认 'User'"""
    setting = db.query(Setting).filter(Setting.key == "user_name").first()
    return setting.value if setting and setting.value else "User"


# LLM 错误 → HTTP 状态码映射
_LLM_ERROR_MAP: dict[type[LLMError], tuple[int, str | None]] = {
    LLMAuthError: (status.HTTP_401_UNAUTHORIZED, None),
    LLMRateLimitError: (status.HTTP_429_TOO_MANY_REQUESTS, "API 请求频率超限，请稍后再试"),
    LLMTimeoutError: (status.HTTP_504_GATEWAY_TIMEOUT, "API 请求超时，请检查网络后重试"),
    LLMContentFilterError: (status.HTTP_400_BAD_REQUEST, None),
    LLMError: (status.HTTP_502_BAD_GATEWAY, None),
}


def _llm_error_response(e: LLMError, provider: str) -> tuple[int, str]:
    """将 LLMError 转为 (HTTP 状态码, 用户可见消息)"""
    for exc_type, (status_code, fixed_msg) in _LLM_ERROR_MAP.items():
        if isinstance(e, exc_type):
            if fixed_msg is not None:
                return status_code, fixed_msg
            if isinstance(e, LLMAuthError):
                return status_code, f"{provider} API Key 无效，请在设置中更新"
            return status_code, str(e)
    return status.HTTP_502_BAD_GATEWAY, str(e)


def _raise_llm_http_error(e: LLMError, provider: str) -> None:
    """将 LLMError 转为 HTTPException 抛出"""
    status_code, message = _llm_error_response(e, provider)
    raise HTTPException(status_code=status_code, detail=message)


@dataclass
class _ChatContext:
    """一次聊天请求的准备结果（流式/非流式共用）"""
    conversation: Conversation
    temperature: float
    messages: list[dict]
    provider: BaseLLM


def _prepare_chat(db: Session, request: ChatRequest) -> _ChatContext:
    """校验对话、构建消息列表、获取 Provider — 流式/非流式聊天共用前置逻辑

    Args:
        db: 数据库会话
        request: 聊天请求

    Returns:
        组装好的聊天上下文（对话、温度、消息列表、Provider 实例）
    """
    # 1. 验证对话存在
    conv = conversation_service.get_conversation(db, request.conversation_id)
    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")

    # 2. 获取角色（用于 temperature）
    character = db.query(Character).filter(Character.id == conv.character_id).first()
    temperature = character.temperature if character else 0.7

    # 3. 自动插入 greeting（仅首次，支持模板变量）
    user_name = _get_user_name(db)
    message_service.auto_insert_greeting(db, request.conversation_id, user_name=user_name)

    # 4. 保存用户消息
    message_service.create_message(db, request.conversation_id, Role.USER, request.content)

    # 5. 构建消息列表（含 system prompt + 历史 + 当前输入 + 滑窗 + 模板变量）
    max_rounds = _get_sliding_window_rounds(db)
    messages = message_service.build_message_list(
        db, conv, request.content, max_rounds=max_rounds, user_name=user_name,
    )

    # 6. 获取 API Key
    api_key = _get_api_key(db, conv.model_provider)
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"未配置 {conv.model_provider} API Key，请在设置中填写",
        )

    # 7. 获取 Provider
    try:
        provider = LLMFactory.get_provider(conv.model_provider, api_key)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"不支持的 Provider: {conv.model_provider}",
        )

    return _ChatContext(
        conversation=conv,
        temperature=temperature,
        messages=messages,
        provider=provider,
    )


# ── Endpoints ──


@router.post("/api/chats", response_model=ChatResponse)
async def create_chat(request: ChatRequest, db: Session = Depends(get_db)) -> ChatResponse:
    """非流式聊天 — 接入真实 LLM"""
    ctx = _prepare_chat(db, request)

    # 调用 LLM 生成回复
    try:
        reply_text = await ctx.provider.generate(
            ctx.messages,
            temperature=ctx.temperature,
            model=ctx.conversation.model_name,
        )
    except LLMError as e:
        _raise_llm_http_error(e, ctx.conversation.model_provider)

    # 保存回复
    saved = message_service.create_message(
        db, request.conversation_id, Role.ASSISTANT, reply_text
    )

    return ChatResponse(
        reply=reply_text,
        message_id=saved.id,
        conversation_id=request.conversation_id,
    )


@router.post("/api/chats/stream")
async def stream_chat(request: ChatRequest, db: Session = Depends(get_db)) -> StreamingResponse:
    """流式聊天（SSE）— 逐 token 返回"""
    ctx = _prepare_chat(db, request)

    async def event_generator() -> AsyncIterator[str]:
        """SSE 事件生成器"""
        full_content = ""
        try:
            async for token in ctx.provider.stream_generate(
                ctx.messages,
                temperature=ctx.temperature,
                model=ctx.conversation.model_name,
            ):
                full_content += token
                yield f"data: {json.dumps({'type': 'token', 'content': token})}\n\n"

            # 流结束，保存完整回复到 DB
            saved = message_service.create_message(
                db, request.conversation_id, Role.ASSISTANT, full_content
            )
            yield f"data: {json.dumps({'type': 'done', 'message_id': saved.id})}\n\n"

        except LLMError as e:
            _, message = _llm_error_response(e, ctx.conversation.model_provider)
            yield f"data: {json.dumps({'type': 'error', 'message': message})}\n\n"
        except Exception as e:
            yield (
                f"data: {json.dumps({'type': 'error', 'message': f'生成回复失败: {e}'})}"
                f"\n\n"
            )

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )
