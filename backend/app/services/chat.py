"""
聊天回合业务逻辑 — 流式/非流式聊天共用的深模块

协议表面（__all__）：ChatContext / assemble_chat_context / prepare_chat / complete_chat /
regenerate_chat / chat_error_response / stream_reply。

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
from backend.app.models.message import Message, Role
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.error_mapping import domain_error_response, llm_error_response
from backend.app.services.exceptions import (
    ConversationNotFoundError,
    DomainError,
    InvalidRegenerateTargetError,
    MessageNotFoundError,
)
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMError
from backend.app.services.llm.resolver import resolve_llm

__all__ = [
    "ChatContext",
    "assemble_chat_context",
    "prepare_chat",
    "complete_chat",
    "regenerate_chat",
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


def assemble_chat_context(
    db: Session,
    conversation_id: int,
    *,
    current_input: str | None = None,
) -> ChatContext:
    """组装聊天上下文（不插入 user、不自动插入 greeting）

    从 prepare_chat 抽出的下层函数：校验对话 → 取角色 temperature → 组装消息
    列表 → resolve_llm。不落库任何消息，重生成与普通发送复用同一条组装路径，
    保证 truncation 后组装与滑窗轮数一致、无幽灵消息。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        current_input: 当前用户输入。提供时作为末条 user 输入追加到消息列表；
            None（重生成路径）时不追加——把历史末条 user 消息作为待回复目标，
            避免触发消息在 history + 追加各出现一次的重复。

    Returns:
        组装好的聊天上下文（对话、温度、消息列表、Provider 实例）

    Raises:
        ConversationNotFoundError: 对话不存在
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
    """
    # 1. 验证对话存在
    conv = conversation_service.require_conversation(db, conversation_id)

    # 2. 获取角色（用于 temperature）
    character = db.query(Character).filter(Character.id == conv.character_id).first()
    temperature = character.temperature if character else 0.7

    # 3. 构建消息列表（含 system prompt + 历史 + 滑窗 + 模板变量；不落库）
    user_name = setting_service.user_name(db)
    max_rounds = setting_service.sliding_window_rounds(db)
    if current_input is not None:
        messages = message_service.build_message_list(
            db, conv, current_input, max_rounds=max_rounds, user_name=user_name,
        )
    else:
        # 重生成路径：不追加当前输入。build_message_list 末尾恒追加输入，
        # 此处用空串追加后丢弃，使历史末条 user 即为待回复目标（不重复）。
        # 带 post_history_instructions（PHI）的角色：build_message_list 在最后
        # user 之后追加 PHI（system）再追加 "" user，故丢弃 "" user 后需再移除
        # 末尾 system（PHI），使末尾 user 恢复为触发源（W2 增量审核 BREAKS-高）。
        messages = message_service.build_message_list(
            db, conv, "", max_rounds=max_rounds, user_name=user_name,
        )
        messages = messages[:-1]
        while messages and messages[-1].get("role") == "system":
            messages.pop()

    # 4. 解析 Provider（凭据读取 + 未配置 Key 校验 + 实例化收口于 resolve_llm）
    _, _, provider = resolve_llm(db, conv.model_provider, conv.model_name)

    return ChatContext(
        conversation=conv,
        temperature=temperature,
        messages=messages,
        provider=provider,
    )


def prepare_chat(db: Session, request: ChatRequest) -> ChatContext:
    """校验对话、构建消息列表、获取 Provider — 流式/非流式聊天共用前置逻辑

    先自动插入 greeting、落库用户消息，再委托下层函数 assemble_chat_context
    组装（组装本身不落库）。重生成不经过本函数（避免重复插入 user）。

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

    # 2. 自动插入 greeting（仅首次，支持模板变量）
    user_name = setting_service.user_name(db)
    message_service.auto_insert_greeting(db, request.conversation_id, user_name=user_name)

    # 3. 保存用户消息
    message_service.create_message(db, request.conversation_id, Role.USER, request.content)

    # 4. 组装上下文（含 system prompt + 历史 + 当前输入 + 滑窗 + Provider）
    return assemble_chat_context(db, request.conversation_id, current_input=request.content)


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


def _resolve_regenerate_target(
    db: Session,
    conversation_id: int,
    message_id: int | None,
) -> Message:
    """解析重生成目标消息并校验（对话归属 + 必须为 assistant）

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        message_id: 目标消息 ID；None 时取末条 assistant

    Returns:
        目标 assistant 消息

    Raises:
        MessageNotFoundError: 显式 message_id 不存在或不属于该对话；无 assistant 可重生成
        InvalidRegenerateTargetError: 目标非 assistant
    """
    if message_id is not None:
        target = db.query(Message).filter(Message.id == message_id).first()
        if target is None or target.conversation_id != conversation_id:
            raise MessageNotFoundError("消息不存在")
    else:
        target = (
            db.query(Message)
            .filter(Message.conversation_id == conversation_id, Message.role == Role.ASSISTANT)
            .order_by(Message.id.desc())
            .first()
        )
        if target is None:
            raise InvalidRegenerateTargetError("没有可重生成的 AI 回复")

    if target.role != Role.ASSISTANT:
        raise InvalidRegenerateTargetError("只能重生成 AI 回复")
    return target


def _last_user_before(
    db: Session,
    conversation_id: int,
    target_id: int,
) -> Message | None:
    """返回 target 之前最近的一条 user 消息（重生成触发源）

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        target_id: 目标消息 ID

    Returns:
        最近的 user 消息；不存在则返回 None
    """
    return (
        db.query(Message)
        .filter(
            Message.conversation_id == conversation_id,
            Message.role == Role.USER,
            Message.id < target_id,
        )
        .order_by(Message.id.desc())
        .first()
    )


async def regenerate_chat(
    db: Session,
    conversation_id: int,
    message_id: int | None = None,
) -> ChatResponse:
    """重生成对话中目标 AI 回复（缺省末条 assistant）

    编排：解析并校验目标 → 校验触发源（截断后须有 user 消息）→ 截断（删除目标
    及其后全部消息，锚定 PK id，不 commit）→ 组装上下文（不插入 user）→ 生成 →
    单事务落库新 assistant 消息 → ChatResponse。LLM 失败时回滚截断，时间线不变。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        message_id: 目标 assistant 消息 ID；None 取末条 assistant

    Returns:
        ChatResponse（reply / message_id / conversation_id）

    Raises:
        ConversationNotFoundError: 对话不存在
        MessageNotFoundError: message_id 不存在或不属于该对话
        InvalidRegenerateTargetError: 目标非 assistant / 截断后无触发 user
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
        HTTPException: LLM 调用失败（经 chat_error_response 映射）
    """
    # 1. 校验对话存在
    conversation_service.require_conversation(db, conversation_id)

    # 2. 解析并校验目标
    target = _resolve_regenerate_target(db, conversation_id, message_id)

    # 3. 校验触发源：截断后必须存在 user 消息（无触发源 → 400）
    if _last_user_before(db, conversation_id, target.id) is None:
        raise InvalidRegenerateTargetError("没有可重生成的用户消息")

    # 4. 截断（删除 target 及其后全部，不 commit；截断后任何异常均回滚，
    #    防半截断持久化——W2 增量审核 BREAKS-中：不止 LLMError，resolve_llm
    #    的 ApiKeyMissing/ProviderNotSupported 等异常同样须回滚）
    message_service.delete_messages_from(db, conversation_id, target.id)

    # 5-6. 组装上下文 + 生成回复（同一原子的异常边界）
    try:
        ctx = assemble_chat_context(db, conversation_id, current_input=None)
        reply_text = await ctx.provider.generate(
            ctx.messages,
            temperature=ctx.temperature,
            model=ctx.conversation.model_name,
        )
    except LLMError as e:
        db.rollback()
        status_code, message = chat_error_response(
            e, ctx.conversation.model_provider
        )
        raise HTTPException(status_code=status_code, detail=message)
    except Exception:
        db.rollback()
        raise

    # 7. 单事务落库：截断 + 新 assistant 一次提交
    saved = message_service.create_message_no_commit(
        db, conversation_id, Role.ASSISTANT, reply_text
    )
    db.commit()
    db.refresh(saved)

    return ChatResponse(
        reply=reply_text,
        message_id=saved.id,
        conversation_id=conversation_id,
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
    - 错误不保存：LLMError / 泛化异常等错误路径下，partial content 不落库
      （F-45），避免 reload 后幽灵内容与错误气泡不一致。
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
        saved = True  # F-45：错误帧后不再保存部分内容，防止 reload 后幽灵内容与错误气泡不一致
        yield {"type": "error", "message": message}
    except Exception as e:
        # O3：泛化异常属未预期路径，错误帧产出前先落 ERROR 日志（含堆栈）便于线上排障
        logger.exception("流式生成回复失败")
        saved = True  # F-45：错误帧后不再保存部分内容，防止 reload 后幽灵内容与错误气泡不一致
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
