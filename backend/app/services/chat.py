"""
聊天回合业务逻辑 — 流式/非流式聊天共用的深模块

协议表面（__all__）：ChatContext / prepare_chat / llm_error_response / stream_reply。

一次「聊天回合」的生命周期（插开场白 → 存用户消息 → 组装上下文 →
取 Key 与 Provider → 生成 → 保存/保存部分）全部收拢于此；
api/routes/chat.py 只保留 HTTP 映射与 SSE data: 帧包装。

对比参照 services/character_card.py 的深模块形态：协议表面小、实现丰富，
测试针对接口而非路由内部实现。
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Awaitable, Callable
from dataclasses import dataclass

from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from starlette.requests import ClientDisconnect

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Role
from backend.app.schemas.message import ChatRequest
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)
from backend.app.services.llm.factory import LLMFactory

__all__ = ["ChatContext", "prepare_chat", "llm_error_response", "stream_reply"]

# LLM 错误 → (HTTP 状态码, 用户可见消息) 映射
_LLM_ERROR_MAP: dict[type[LLMError], tuple[int, str | None]] = {
    LLMAuthError: (status.HTTP_401_UNAUTHORIZED, None),
    LLMRateLimitError: (status.HTTP_429_TOO_MANY_REQUESTS, "API 请求频率超限，请稍后再试"),
    LLMTimeoutError: (status.HTTP_504_GATEWAY_TIMEOUT, "API 请求超时，请检查网络后重试"),
    LLMContentFilterError: (status.HTTP_400_BAD_REQUEST, None),
    LLMError: (status.HTTP_502_BAD_GATEWAY, None),
}


@dataclass
class ChatContext:
    """一次聊天请求的准备结果（流式/非流式共用）"""
    conversation: Conversation
    temperature: float
    messages: list[dict]
    provider: BaseLLM


def prepare_chat(db: Session, request: ChatRequest) -> ChatContext:
    """校验对话、构建消息列表、获取 Provider — 流式/非流式聊天共用前置逻辑

    Args:
        db: 数据库会话
        request: 聊天请求

    Returns:
        组装好的聊天上下文（对话、温度、消息列表、Provider 实例）

    Raises:
        HTTPException: 对话不存在 / 未配置 API Key / 不支持的 Provider
    """
    # 1. 验证对话存在
    conv = conversation_service.get_conversation(db, request.conversation_id)
    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")

    # 2. 获取角色（用于 temperature）
    character = db.query(Character).filter(Character.id == conv.character_id).first()
    temperature = character.temperature if character else 0.7

    # 3. 自动插入 greeting（仅首次，支持模板变量）
    user_name = setting_service.user_name(db)
    message_service.auto_insert_greeting(db, request.conversation_id, user_name=user_name)

    # 4. 保存用户消息
    message_service.create_message(db, request.conversation_id, Role.USER, request.content)

    # 5. 构建消息列表（含 system prompt + 历史 + 当前输入 + 滑窗 + 模板变量）
    max_rounds = setting_service.sliding_window_rounds(db)
    messages = message_service.build_message_list(
        db, conv, request.content, max_rounds=max_rounds, user_name=user_name,
    )

    # 6. 获取 API Key
    api_key = setting_service.api_key(db, conv.model_provider)
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"未配置 {conv.model_provider} API Key，请在设置中填写",
        )

    # 7. 获取 Provider（含自定义 base_url）
    try:
        base_url = setting_service.get_value(db, f"{conv.model_provider}_base_url") or None
        provider = LLMFactory.get_provider(conv.model_provider, api_key, base_url)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"不支持的 Provider: {conv.model_provider}",
        )

    return ChatContext(
        conversation=conv,
        temperature=temperature,
        messages=messages,
        provider=provider,
    )


def llm_error_response(e: LLMError, provider: str) -> tuple[int, str]:
    """将 LLMError 转为 (HTTP 状态码, 用户可见消息)"""
    for exc_type, (status_code, fixed_msg) in _LLM_ERROR_MAP.items():
        if isinstance(e, exc_type):
            if fixed_msg is not None:
                return status_code, fixed_msg
            if isinstance(e, LLMAuthError):
                return status_code, f"{provider} API Key 无效，请在设置中更新"
            return status_code, str(e)
    return status.HTTP_502_BAD_GATEWAY, str(e)


async def stream_reply(
    db: Session,
    conversation_id: int,
    ctx: ChatContext,
    is_disconnected: Callable[[], Awaitable[bool]],
) -> AsyncIterator[dict]:
    """流式生成回复并持久化，产出 SSE 事件 dict（token / done / error）

    - 客户端断开（is_disconnected 返回 True 或抛 ClientDisconnect）→ 停止 LLM，
      将已生成的部分内容保存为 assistant 消息后正常收尾。
    - 停止语义为「用户主动停止」，非错误；路由层只做 data: 帧包装。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        ctx: prepare_chat 的产物
        is_disconnected: 客户端是否已断开的协程判断（如 raw_request.is_disconnected）
    """
    full_content = ""
    try:
        async for token in ctx.provider.stream_generate(
            ctx.messages,
            temperature=ctx.temperature,
            model=ctx.conversation.model_name,
        ):
            # 客户端断开 → 停止生成，保存已生成部分（不再发送事件）
            if await is_disconnected():
                if full_content:
                    message_service.create_message(
                        db, conversation_id, Role.ASSISTANT, full_content
                    )
                return

            full_content += token
            yield {"type": "token", "content": token}

        # 流结束，保存完整回复到 DB
        saved = message_service.create_message(
            db, conversation_id, Role.ASSISTANT, full_content
        )
        yield {"type": "done", "message_id": saved.id}

    except ClientDisconnect:
        # 客户端在发送过程中断开 — 尽力保存已生成部分
        if full_content:
            message_service.create_message(
                db, conversation_id, Role.ASSISTANT, full_content
            )
        return

    except LLMError as e:
        _, message = llm_error_response(e, ctx.conversation.model_provider)
        yield {"type": "error", "message": message}
    except Exception as e:
        yield {"type": "error", "message": f"生成回复失败: {e}"}
