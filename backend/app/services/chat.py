"""
聊天回合业务逻辑 — 流式/非流式聊天共用的深模块

协议表面（__all__）：ChatContext / prepare_chat / complete_chat / chat_error_response / stream_reply。

一次「聊天回合」的生命周期（插开场白 → 存用户消息 → 组装上下文 →
取 Key 与 Provider → 生成 → 错误映射 → 保存/保存部分）全部收拢于此；
api/routes/chat.py 只保留 HTTP 映射（领域异常 → HTTPException）与 SSE data: 帧包装。
领域族与 LLM 族错误映射统一委托 services/error_mapping.py 单一入口
（ARC10-4「两路并存」合并完成；LLM 族迁入随 T-01）。

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
from backend.app.services.error_mapping import domain_error_response, llm_error_response
from backend.app.services.exceptions import (
    ConversationNotFoundError,
    DomainError,
)
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMError
from backend.app.services.llm.resolver import resolve_llm

__all__ = [
    "ChatContext",
    "prepare_chat",
    "complete_chat",
    "chat_error_response",
    "stream_reply",
]


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

    # 6. 解析 Provider（凭据读取 + 未配置 Key 校验 + 实例化收口于 resolve_llm）
    _, _, provider = resolve_llm(db, conv.model_provider, conv.model_name)

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

    状态码与消息与重构前逐字一致（除防御语义对齐项，见下）：
    - 领域异常族：委托 services/error_mapping.py::domain_error_response 单一入口
      （404/400/422 全家族 + 未知领域异常 400 兜底）。注：422 家族（CardFormatError /
      CardValidationError / DocParseError）在聊天领域分支原映射 400，委托后变 422——
      该分支生产路径不可达（仅非流式完整回合的 LLM 错误分支、LLM 异常处理器与直测
      用例触达），属防御语义对齐（ARC10-2 / ARC10-4 合并单一映射表时纳入）
    - LLM 异常族：委托 error_mapping.llm_error_response（401 Auth 含 provider 模板——
      provider 为空时输出无前缀基础文案；429/504 固定消息、400、502）
    - 其余异常：502 + str(e) 兜底（防御性，当前调用方不会传入）

    Args:
        e: 待映射的异常（领域异常或 LLM 异常）
        provider: LLM 分支的 Provider 名（Auth 消息模板使用；领域分支不使用）

    Returns:
        (HTTP 状态码, 用户可见消息)
    """
    if isinstance(e, DomainError):
        return domain_error_response(e)
    if isinstance(e, LLMError):
        return llm_error_response(e, provider or "")
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
    - 零 token 流不落库：Provider 正常结束但未产出任何 token（full_content 为
      空串）时，跳过持久化、不留空 assistant 消息，done 帧 message_id 为 None。

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

        # 流结束，保存完整回复到 DB；零 token 空流不落库（O1：空 assistant
        # 消息会污染历史），done 帧 message_id 置 None，不引用未保存消息 id
        message_id: int | None = None
        if not saved and full_content:
            saved_msg = message_service.create_message(
                db, conversation_id, Role.ASSISTANT, full_content
            )
            saved = True
            message_id = saved_msg.id
        yield {"type": "done", "message_id": message_id}

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
        # O3：泛化异常属未预期路径，错误帧产出前先落 ERROR 日志（含堆栈）便于线上排障
        logger.exception("流式生成回复失败")
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
