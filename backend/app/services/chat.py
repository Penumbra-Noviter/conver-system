"""
聊天回合业务逻辑 — 流式/非流式聊天共用的深模块

协议表面（__all__）：ChatContext / prepare_chat / complete_chat / chat_error_response / stream_reply。

一次「聊天回合」的生命周期（插开场白 → 存用户消息 → 组装上下文 →
取 Key 与 Provider → 生成 → 错误映射 → 保存/保存部分）全部收拢于此；
api/routes/chat.py 只保留 HTTP 映射（领域异常 → HTTPException）与 SSE data: 帧包装。
领域 + LLM 两族错误映射并置为单一入口 chat_error_response（B1 共识 D2）。

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
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    ConversationNotFoundError,
    DomainError,
    ProviderNotSupportedError,
)
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)
from backend.app.services.llm.factory import LLMFactory

__all__ = [
    "ChatContext",
    "prepare_chat",
    "complete_chat",
    "chat_error_response",
    "stream_reply",
]

# 领域异常 → HTTP 状态码 映射（detail 一律 str(e)；语义源自路由层原 _DOMAIN_ERROR_MAP，B1 迁入合一）
_DOMAIN_ERROR_MAP: dict[type[DomainError], int] = {
    ConversationNotFoundError: status.HTTP_404_NOT_FOUND,
    ApiKeyMissingError: status.HTTP_400_BAD_REQUEST,
    ProviderNotSupportedError: status.HTTP_400_BAD_REQUEST,
}

# LLM 错误 → (HTTP 状态码, 用户可见消息) 映射
_LLM_ERROR_MAP: dict[type[LLMError], tuple[int, str | None]] = {
    LLMAuthError: (status.HTTP_401_UNAUTHORIZED, None),
    LLMRateLimitError: (status.HTTP_429_TOO_MANY_REQUESTS, "API 请求频率超限，请稍后再试"),
    LLMTimeoutError: (status.HTTP_504_GATEWAY_TIMEOUT, "API 请求超时，请检查网络后重试"),
    LLMContentFilterError: (status.HTTP_400_BAD_REQUEST, None),
    LLMError: (status.HTTP_502_BAD_GATEWAY, None),
}


import logging

logger = logging.getLogger(__name__)


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
        ConversationNotFoundError: 对话不存在
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
    """
    # 1. 验证对话存在
    conv = conversation_service.get_conversation(db, request.conversation_id)
    if not conv:
        raise ConversationNotFoundError("对话不存在")

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
        raise ApiKeyMissingError(
            f"未配置 {conv.model_provider} API Key，请在设置中填写",
        )

    # 7. 获取 Provider（含自定义 base_url）
    try:
        base_url = setting_service.base_url(db, conv.model_provider) or None
        provider = LLMFactory.get_provider(conv.model_provider, api_key, base_url)
    except ValueError:
        raise ProviderNotSupportedError(
            f"不支持的 Provider: {conv.model_provider}",
        )

    return ChatContext(
        conversation=conv,
        temperature=temperature,
        messages=messages,
        provider=provider,
    )


async def complete_chat(db: Session, request: ChatRequest) -> ChatResponse:
    """非流式聊天回合深模块入口：prepare → generate → LLM 错误映射 → 持久化 → 响应构造

    完整搬移原路由层 create_chat 的业务语义（B1）：领域异常经 prepare_chat 上抛
    （由路由层转 HTTP），LLMError 在此映射为 HTTPException 上抛（FastAPI 会正确
    处理请求路径中抛出的 HTTPException）。

    Args:
        db: 数据库会话
        request: 聊天请求

    Returns:
        ChatResponse（reply / message_id / conversation_id）

    Raises:
        ConversationNotFoundError: 对话不存在
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
        HTTPException: LLM 调用失败（401/429/504/400/502，经 chat_error_response 映射）
    """
    ctx = prepare_chat(db, request)

    try:
        reply_text = await ctx.provider.generate(
            ctx.messages,
            temperature=ctx.temperature,
            model=ctx.conversation.model_name,
        )
    except LLMError as e:
        status_code, message = chat_error_response(
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


def chat_error_response(e: Exception, provider: str | None = None) -> tuple[int, str]:
    """领域/LLM 异常 → (HTTP 状态码, 用户可见消息) 单一映射入口

    两族映射并置于此（领域异常族 + LLM 异常族），状态码与消息与重构前逐字一致：
    - 领域异常族：ConversationNotFoundError→404、ApiKeyMissingError→400、
      ProviderNotSupportedError→400，detail=str(e)
    - LLM 异常族：委托 llm_error_response（401 Auth 含 provider 模板——provider 为空时
      输出无前缀基础文案；429/504 固定消息、400、502）
    - 未知领域异常（未入表子类）：400 + str(e)（与 api/errors.py 兜底语义对齐，ARC10-2）
    - 其余异常：502 + str(e) 兜底（防御性，当前调用方不会传入）

    Args:
        e: 待映射的异常（领域异常或 LLM 异常）
        provider: LLM 分支的 Provider 名（Auth 消息模板使用；领域分支不使用）

    Returns:
        (HTTP 状态码, 用户可见消息)
    """
    for exc_type, http_status in _DOMAIN_ERROR_MAP.items():
        if isinstance(e, exc_type):
            return http_status, str(e)
    if isinstance(e, LLMError):
        return llm_error_response(e, provider or "")
    if isinstance(e, DomainError):
        # 未知领域异常子类：400 兜底（防御性；与 api/errors.py 未知分支语义对齐，ARC10-2）
        # 422 家族（CardFormatError/CardValidationError/DocParseError）不落此分支——经
        # api/errors.py 按 422 + 说明文案处理（关联 ARC10-2 / ARC10-4；合并单一映射表时纳入）
        return status.HTTP_400_BAD_REQUEST, str(e)
    return status.HTTP_502_BAD_GATEWAY, str(e)


def llm_error_response(e: LLMError, provider: str | None) -> tuple[int, str]:
    """将 LLMError 转为 (HTTP 状态码, 用户可见消息)（内部实现，chat_error_response 与 stream_reply 共用）"""
    for exc_type, (status_code, fixed_msg) in _LLM_ERROR_MAP.items():
        if isinstance(e, exc_type):
            if fixed_msg is not None:
                return status_code, fixed_msg
            if isinstance(e, LLMAuthError):
                # Provider 非空带前缀、为空时输出基础文案（按构造消除前导空格，ARC10-1）
                prefix = f"{provider} " if provider else ""
                return status_code, f"{prefix}API Key 无效，请在设置中更新"
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
    - 兜底：生成器被取消（GeneratorExit / CancelledError，Starlette 在客户端
      断开时取消 SSE 生成器的真实路径）时，finally 中仍尽力保存已生成部分。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        ctx: prepare_chat 的产物
        is_disconnected: 客户端是否已断开的协程判断（如 raw_request.is_disconnected）
    """
    full_content = ""
    saved = False  # 是否已落库，防止 finally 兜底重复保存

    try:
        async for token in ctx.provider.stream_generate(
            ctx.messages,
            temperature=ctx.temperature,
            model=ctx.conversation.model_name,
        ):
            # 客户端断开 → 停止生成，保存已生成部分（不再发送事件）
            if await is_disconnected():
                if full_content and not saved:
                    message_service.create_message(
                        db, conversation_id, Role.ASSISTANT, full_content
                    )
                    saved = True
                return

            full_content += token
            yield {"type": "token", "content": token}

        # 流结束，保存完整回复到 DB
        if not saved:
            saved_msg = message_service.create_message(
                db, conversation_id, Role.ASSISTANT, full_content
            )
            saved = True
        yield {"type": "done", "message_id": saved_msg.id}

    except ClientDisconnect:
        # 客户端在发送过程中断开 — 尽力保存已生成部分
        if full_content and not saved:
            message_service.create_message(
                db, conversation_id, Role.ASSISTANT, full_content
            )
            saved = True
        return

    except LLMError as e:
        _, message = llm_error_response(e, ctx.conversation.model_provider)
        yield {"type": "error", "message": message}
    except Exception as e:
        yield {"type": "error", "message": f"生成回复失败: {e}"}
    finally:
        # 生成器被取消（GeneratorExit / CancelledError）→ 兜底保存已生成部分。
        # finally 中不可再 yield（取消场景下 yield 会抛 RuntimeError），只做落库。
        if full_content and not saved:
            try:
                message_service.create_message(
                    db, conversation_id, Role.ASSISTANT, full_content
                )
            except Exception:
                logger.exception("保存已生成的部分消息失败")
