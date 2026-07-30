"""
消息 & 聊天 REST API 路由

包含：
    - GET /api/conversations/{id}/messages — 获取消息历史
    - POST /api/chat — 非流式聊天
    - POST /api/chat/stream — 流式聊天（SSE）
"""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from backend.app.api.deps import get_db
from backend.app.models.character import Character
from backend.app.models.setting import Setting
from backend.app.schemas.message import ChatRequest, ChatResponse, MessageResponse
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)
from backend.app.services.llm.factory import LLMFactory

router = APIRouter(tags=["消息 & 聊天"])


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


# ── Endpoints ──


@router.get(
    "/api/conversations/{conversation_id}/messages",
    response_model=list[MessageResponse],
)
def get_messages(conversation_id: int, db: Session = Depends(get_db)):
    """获取对话的消息历史（按时间正序）"""
    conv = conversation_service.get_conversation(db, conversation_id)
    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")
    return message_service.get_messages(db, conversation_id)


@router.post("/api/chat", response_model=ChatResponse)
async def create_chat(request: ChatRequest, db: Session = Depends(get_db)):
    """非流式聊天 — 接入真实 LLM"""
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
    message_service.save_message(db, request.conversation_id, "user", request.content)

    # 5. 构建消息列表（含 system prompt + 历史 + 当前输入 + 滑窗 + 模板变量）
    max_rounds = _get_sliding_window_rounds(db)
    messages_list = message_service.build_message_list(
        db, conv, request.content, max_rounds=max_rounds, user_name=user_name,
    )

    # 6. 获取 API Key
    api_key = _get_api_key(db, conv.model_provider)
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"未配置 {conv.model_provider} API Key，请在设置中填写",
        )

    # 7. 获取 Provider 并调用
    try:
        provider = LLMFactory.get_provider(conv.model_provider, api_key)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"不支持的 Provider: {conv.model_provider}",
        )

    try:
        reply_text = await provider.generate(
            messages_list,
            temperature=temperature,
            model=conv.model_name,
        )
    except LLMError as e:
        _raise_llm_http_error(e, conv.model_provider)

    # 8. 保存回复
    saved = message_service.save_message(
        db, request.conversation_id, "assistant", reply_text
    )

    return ChatResponse(
        reply=reply_text,
        message_id=saved.id,
        conversation_id=request.conversation_id,
    )


@router.post("/api/chat/stream")
async def stream_chat(request: ChatRequest, db: Session = Depends(get_db)):
    """流式聊天（SSE）— 逐 token 返回"""
    # 验证对话存在
    conv = conversation_service.get_conversation(db, request.conversation_id)
    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")

    character = db.query(Character).filter(Character.id == conv.character_id).first()
    temperature = character.temperature if character else 0.7

    # 自动插入 greeting（仅首次，支持模板变量）
    user_name = _get_user_name(db)
    message_service.auto_insert_greeting(db, request.conversation_id, user_name=user_name)

    # 保存用户消息
    message_service.save_message(db, request.conversation_id, "user", request.content)

    # 构建消息列表（含滑窗 + 模板变量）
    max_rounds = _get_sliding_window_rounds(db)
    messages_list = message_service.build_message_list(
        db, conv, request.content, max_rounds=max_rounds, user_name=user_name,
    )

    # 获取 API Key
    api_key = _get_api_key(db, conv.model_provider)
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"未配置 {conv.model_provider} API Key，请在设置中填写",
        )

    try:
        provider = LLMFactory.get_provider(conv.model_provider, api_key)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"不支持的 Provider: {conv.model_provider}",
        )

    async def event_generator():
        """SSE 事件生成器"""
        full_content = ""
        try:
            async for token in provider.stream_generate(
                messages_list,
                temperature=temperature,
                model=conv.model_name,
            ):
                full_content += token
                yield f"data: {json.dumps({'type': 'token', 'content': token})}\n\n"

            # 流结束，保存完整回复到 DB
            saved = message_service.save_message(
                db, request.conversation_id, "assistant", full_content
            )
            yield f"data: {json.dumps({'type': 'done', 'message_id': saved.id})}\n\n"

        except LLMError as e:
            _, message = _llm_error_response(e, conv.model_provider)
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


@router.get("/api/messages/search")
def search_messages(
    q: str = Query("", description="搜索关键词"),
    limit: int = Query(50, description="最大返回条数"),
    db: Session = Depends(get_db),
):
    """搜索消息内容（关键词匹配）

    返回包含关键词的消息列表，每条附带对话标题和角色信息。
    """
    results = message_service.search_messages(db, q, limit=limit)
    return results
