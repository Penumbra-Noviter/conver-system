"""
聊天回合业务逻辑 — 流式/非流式聊天共用的深模块

协议表面（__all__）：ChatContext / assemble_chat_context / prepare_chat / complete_chat /
regenerate_chat / continue_chat / edit_and_resend / chat_error_response / stream_reply。

一次「聊天回合」的生命周期（插开场白 → 存用户消息 → 组装上下文 →
取 Key 与 Provider → 生成 → 错误映射 → 保存/保存部分）全部收拢于此；
api/routes/chat.py 只保留 HTTP 映射（领域异常 → HTTPException）与 SSE data: 帧包装。
领域族与 LLM 族错误映射统一委托 services/error_mapping.py 单一入口
（ARC10-4「两路并存」合并完成；LLM 族迁入随 T-01）。

对比参照 services/character_card.py 的深模块形态：协议表面小、实现丰富，
测试针对接口而非路由内部实现。
"""

from __future__ import annotations

import logging
import random
from collections.abc import AsyncIterator, Awaitable, Callable, Sequence
from dataclasses import dataclass

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session
from starlette.requests import ClientDisconnect

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.cg_image import CgImage
from backend.app.models.lorebook import LorebookEntry
from backend.app.models.message import Message, Role
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import conversation as conversation_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import memory_palace as memory_palace_service
from backend.app.services import message as message_service
from backend.app.services import mods as mods_service
from backend.app.services import setting as setting_service
from backend.app.services.error_mapping import domain_error_response, llm_error_response
from backend.app.services.exceptions import (
    ConversationNotFoundError,
    DomainError,
    InvalidContinueTargetError,
    InvalidEditTargetError,
    InvalidRegenerateTargetError,
    MessageNotFoundError,
)
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMError
from backend.app.services.llm.resolver import resolve_llm
from backend.app.services.lorebook_engine import (
    LorebookEntryData,
    activate_lorebook_entries,
    build_world_injection,
    collect_scan_text,
)
from backend.app.services.text_utils import role_str

__all__ = [
    "ChatContext",
    "assemble_chat_context",
    "prepare_chat",
    "complete_chat",
    "regenerate_chat",
    "continue_chat",
    "edit_and_resend",
    "chat_error_response",
    "stream_reply",
]


logger = logging.getLogger(__name__)


#: MS-3 续写指令（尾随 user 触发的指令行；spec §MS-3 两可选实证拍板——
#: 续写触发用「原消息末段」（user 形态），否决「续写系统提示」：适配器
#: _prepare_messages「last system wins」锁定契约下尾随 system 会挤掉角色
#: persona/system 链，user 形态与普通路径 system 链一致）
CONTINUE_INSTRUCTION = (
    "（请继续书写上一条 AI 回复：保持角色人设、语气与文风，"
    "不要重复或概括已经写过的内容，直接从停下的地方接续）"
)

#: 续写触发的「原消息末段」锚点长度上限（字符）
_CONTINUATION_TAIL_CHARS = 200


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
    history_limit_message_id: int | None = None,
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
        history_limit_message_id: 历史截止消息 ID（含）——MS-1 重生成路径传入
            触发源 user id，目标 assistant 及其后续不进上下文（模型不看到被
            替换的回复）；世界书扫描窗与消息列表共用该截止。

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

    # 3. 构建消息列表（含 system prompt + 历史 + 滑窗 + 模板变量 + 世界书注入；不落库）
    user_name = setting_service.user_name(db)
    max_rounds = setting_service.sliding_window_rounds(db)
    history = message_service.get_messages(db, conv.id)
    if history_limit_message_id is not None:
        history = [m for m in history if m.id <= history_limit_message_id]
    world_injection = _lorebook_world_injection(
        db, character, history, current_input or "", user_name,
    )
    if any(world_injection.values()):
        logger.debug(
            "世界书注入：%s（%d 条）",
            {k: len(v) for k, v in world_injection.items()},
            sum(len(v) for v in world_injection.values()),
        )
    # MD-2/02：在世界书注入之上叠加启用 prompt 区 Mod（追加各块，不新增尾随 system）
    world_injection = _mod_prompt_injection(db, character, world_injection)
    if current_input is not None:
        messages = message_service.build_message_list(
            db, conv, current_input, max_rounds=max_rounds, user_name=user_name,
            world_injection=world_injection, history=history,
        )
    else:
        # 重生成路径：append_current_input=False —— 不追加当前输入，末条为
        # 历史末条 user（待回复触发源），尾随 PHI system 已在纯函数内剥离。
        messages = message_service.build_message_list(
            db, conv, "", max_rounds=max_rounds, user_name=user_name,
            append_current_input=False, world_injection=world_injection, history=history,
        )

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


async def _generate_with_error_mapping(ctx: ChatContext) -> str:
    """await generate + 捕获 LLMError → chat_error_response → raise HTTPException

    非流式三条路径（complete_chat / regenerate_chat / continue_chat）共用的
    「生成并映射 LLM 错误」私有 seam：把「记得包 try/except 异常映射接线」的知识从
    三处逐字重复收敛为单点（F-126）。生成成功返回回复文本；LLMError 经
    chat_error_response 单一入口映射为 HTTPException 上抛（状态码/消息逐字
    一致，不重复实现映射）；非 LLMError 异常原样透传（不吞、不映射——领域异常 /
    持久化异常等由各自调用方负责）。

    流式路径 stream_reply 刻意不纳入本 seam：其错误帧走 llm_error_response 直接
    产出 SSE error 帧而非 raise HTTPException，语义不同（F-45 错误不落库契约）。

    Args:
        ctx: prepare_chat / assemble_chat_context 的产物

    Returns:
        生成的回复文本

    Raises:
        HTTPException: LLM 调用失败（401/429/504/400/502，经 chat_error_response 映射）
    """
    try:
        return await ctx.provider.generate(
            ctx.messages,
            temperature=ctx.temperature,
            model=ctx.conversation.model_name,
        )
    except LLMError as e:
        status_code, message = chat_error_response(
            e, ctx.conversation.model_provider
        )
        raise HTTPException(status_code=status_code, detail=message)


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
    reply_text = await _generate_with_error_mapping(ctx)

    saved = message_service.create_message(
        db, request.conversation_id, Role.ASSISTANT, reply_text
    )

    # WL-5 记忆宫殿：回合完成后按阈值触发自动归纳（失败绝不阻断主流程）
    await _maybe_memory_palace(
        db, request.conversation_id, ctx.provider, ctx.conversation.model_name
    )
    # T6：CG 自动触发（完整回合后按概率自动解锁候选 CG）
    await _maybe_auto_cg(db, request.conversation_id, saved.id)

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
    """重生成对话中目标 AI 回复（缺省末条 assistant）——MS-1 swipes 语义

    编排：解析并校验目标 → 校验触发源（须存在 user 消息）→ 组装上下文（历史
    截止于触发源 user，目标及其后续不进上下文——模型不看到被替换的回复；不插入
    user）→ 生成 → **add_swipe 追加候选**（历史消息数不变：1 条 assistant + N 候选，
    新候选置为激活）→ ChatResponse（message_id = 目标消息，候选挂于其上）。
    LLM 失败时无截断可回滚（原内容与候选均保留），时间线不变。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        message_id: 目标 assistant 消息 ID；None 取末条 assistant

    Returns:
        ChatResponse（reply / message_id=目标消息 / conversation_id）

    Raises:
        ConversationNotFoundError: 对话不存在
        MessageNotFoundError: message_id 不存在或不属于该对话
        InvalidRegenerateTargetError: 目标非 assistant / 无触发 user
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
        HTTPException: LLM 调用失败（经 chat_error_response 映射）
    """
    # 1. 校验对话存在
    conversation_service.require_conversation(db, conversation_id)

    # 2. 解析并校验目标
    target = _resolve_regenerate_target(db, conversation_id, message_id)

    # 3. 校验触发源：必须存在 user 消息（无触发源 → 400）
    trigger = _last_user_before(db, conversation_id, target.id)
    if trigger is None:
        raise InvalidRegenerateTargetError("没有可重生成的用户消息")

    # 4-5. 组装上下文（历史截止于触发源 user，不插入 user）+ 生成回复。
    #     MS-1：不再截断 DB——目标与后续消息保留，新回复以候选追加。
    #     assemble 不抛 LLMError，移出 try；生成 + 错误映射收口于
    #     _generate_with_error_mapping（F-126）。
    ctx = assemble_chat_context(
        db, conversation_id, current_input=None,
        history_limit_message_id=trigger.id,
    )
    reply_text = await _generate_with_error_mapping(ctx)

    # 6. message 层单一入口追加候选并置为激活（历史消息数不变；LLM 失败路径
    #    无副作用）。content 跟随激活候选（旧前端/后续 LLM 上下文读到新回复）；
    #    bump 会话 updated_at + commit + refresh 收口于该单一入口
    #    （F-124：会话列表排序置顶不变量不再漏 bump）。
    message_service.append_swipe_and_bump(db, target.id, reply_text, make_active=True)

    return ChatResponse(
        reply=reply_text,
        message_id=target.id,
        conversation_id=conversation_id,
    )


def _resolve_edit_target(
    db: Session,
    message_id: int,
) -> Message:
    """解析编辑目标并校验（存在 + 必须为 user）

    编辑入口语义（F-130 收敛）：PUT /api/messages/{message_id} 的 URL 不携带
    conversation_id，message_id 全局唯一，故归属校验由「message_id 存在」自然
    承担（查出的 target 自带 conversation_id）。不再有外部 conversation_id 输入，
    「跨会话编辑」防御对象随之消失——目标解析知识收口本函数单一入口。

    Args:
        db: 数据库会话
        message_id: 目标消息 ID

    Returns:
        目标 user 消息

    Raises:
        MessageNotFoundError: 消息不存在
        InvalidEditTargetError: 目标非 user
    """
    target = db.query(Message).filter(Message.id == message_id).first()
    if target is None:
        raise MessageNotFoundError("消息不存在")
    if target.role != Role.USER:
        raise InvalidEditTargetError("只能编辑用户消息")
    return target


async def edit_and_resend(
    db: Session,
    message_id: int,
    content: str,
) -> ChatResponse:
    """编辑重发（仅 user）：就地替换 content + 物理截断后续 + 重新生成 assistant 回复

    编排（spec §edit-resend 原子性契约）：
    1. _resolve_edit_target 解析并校验目标（存在 + role == USER），并由 target
       派生 conversation_id（F-130 收敛：不再由路由预查 message 后冗余传入，
       目标解析知识收口本函数单一入口）；
    2. require_conversation 校验对话存在（防御 FK 脏数据，正常不可达）；
    3. update_message(commit=False) 就地替换 content（不提交，参与原子落库）；
    4. assemble_chat_context(history_limit_message_id=message_id) 组装上下文
       （历史截止于被编辑 user，后续不进上下文；不插入 user）；
    5. _generate_with_error_mapping 生成（失败抛 HTTPException，未提交变更随
       session close 回滚 → 零落库）；
    6. 成功后物理删除 id > message_id 的后续消息（被编辑 user 保留）；
    7. create_message(ASSISTANT) 落库新回复 —— 单 commit 结算 content 替换 +
       后续删除 + 新 assistant 三者，原子落库。

    与 regenerate_chat 的差异：regenerate 是「上下文截止 + 候选追加、不删后续」；
    本函数是「替换 content + 物理删后续 + 新建 assistant」，故生成前破坏性变更
    须在失败时回滚（不 commit，靠 session close 回滚未提交变更）。

    Args:
        db: 数据库会话
        message_id: 被编辑的 user 消息 ID
        content: 修正后的 user 消息内容

    Returns:
        ChatResponse（reply=新回复 / message_id=新 assistant 消息 / conversation_id）

    Raises:
        ConversationNotFoundError: 对话不存在（FK 脏数据防御）
        MessageNotFoundError: message_id 不存在
        InvalidEditTargetError: 目标非 user
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
        HTTPException: LLM 调用失败（经 chat_error_response 映射）
    """
    # 1. 解析并校验目标（存在 + role == USER），派生 conversation_id（F-130 收敛）
    target = _resolve_edit_target(db, message_id)
    conversation_id = target.conversation_id

    # 2. 校验对话存在（防御 FK 脏数据——message 存在但其 conversation 被物理删）
    conversation_service.require_conversation(db, conversation_id)

    # 3. 就地替换 content（不提交——与后续删除 + 新 assistant 同一 commit 结算）
    message_service.update_message(db, message_id, content, commit=False)

    # 4-5. 组装上下文（历史截止于被编辑 user）+ 生成回复。
    #     assemble 不抛 LLMError，移出 try；生成 + 错误映射收口于
    #     _generate_with_error_mapping（F-126）。失败上抛 HTTPException，
    #     未提交的 content 替换随 session close 回滚（零落库）。
    ctx = assemble_chat_context(
        db, conversation_id, current_input=None,
        history_limit_message_id=message_id,
    )
    reply_text = await _generate_with_error_mapping(ctx)

    # 6. 物理截断被编辑 user 之后的所有消息（旧回复基于旧内容已无意义）。
    #    仅删 id > message_id，被编辑 user 保留。
    db.query(Message).filter(
        Message.conversation_id == conversation_id,
        Message.id > message_id,
    ).delete(synchronize_session="fetch")

    # 7. 单 commit 结算：content 替换 + 后续删除 + 新 assistant 原子落库。
    saved = message_service.create_message(
        db, conversation_id, Role.ASSISTANT, reply_text
    )

    return ChatResponse(
        reply=reply_text,
        message_id=saved.id,
        conversation_id=conversation_id,
    )


def _resolve_continue_target(
    db: Session,
    conversation_id: int,
) -> Message:
    """解析续写目标并校验（须为对话末条消息且为 assistant）

    MS-3 语义：续写只能在末条 assistant 之后进行（前端按钮也只渲染在末条
    assistant 气泡）。末条为 user / 对话无消息 → 无续写目标。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID

    Returns:
        末条 assistant 消息

    Raises:
        InvalidContinueTargetError: 对话无消息或末条非 assistant
    """
    latest = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.id.desc())
        .first()
    )
    if latest is None or latest.role != Role.ASSISTANT:
        raise InvalidContinueTargetError("没有可续写的 AI 回复（末条须为 AI 回复）")
    return latest


def _continuation_tail(content: str | None) -> str:
    """取原消息末段（续写触发锚点）：去首尾空白后取末 200 字符

    MS-3 触发形态：尾随 user 消息 = CONTINUE_INSTRUCTION + 末段（spec §MS-3
    「原消息末段为触发」）。短内容整体作为末段；空内容返回空串（触发只含指令）。

    Args:
        content: 被续写消息原文（可为 None）

    Returns:
        末段锚点字符串（非空原文时非空）
    """
    text = (content or "").strip()
    if not text:
        return ""
    if len(text) > _CONTINUATION_TAIL_CHARS:
        return text[-_CONTINUATION_TAIL_CHARS:]
    return text


async def continue_chat(
    db: Session,
    conversation_id: int,
) -> ChatResponse:
    """续写末条 AI 回复（MS-3 append 续写：不追加 user，原消息扩展为「原内容 + 续写片段」）

    编排：解析并校验末条 assistant → 组装上下文（历史截止于目标，不插入 user）→
    尾随续写触发 user 消息（CONTINUE_INSTRUCTION + 原消息末段）→ 生成 → **add_swipe
    追加候选**（消息条数不变：原内容保留为候选，续写结果置为激活，content 跟随
    激活候选）→ ChatResponse（message_id = 被续写消息）。LLM 失败时无任何落库
    （原内容与候选均不变）。

    触发形态拍板（spec §MS-3 两可选实证选一）：尾随 **user** 消息而非续写 system
    提示 —— 适配器 _prepare_messages「last system wins」为锁定契约，尾随 system
    会把角色 persona/system 链挤掉（真实 Provider 下续写出戏）；user 形态下
    system 链与普通路径完全一致。「不追加 user」契约指 DB 层零新增消息行。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID

    Returns:
        ChatResponse（reply=原内容+续写片段 / message_id=被续写消息 / conversation_id）

    Raises:
        ConversationNotFoundError: 对话不存在
        InvalidContinueTargetError: 末条非 assistant / 对话无消息
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
        HTTPException: LLM 调用失败（经 chat_error_response 映射）
    """
    # 1. 校验对话存在
    conversation_service.require_conversation(db, conversation_id)

    # 2. 解析并校验目标（须为末条 assistant）
    target = _resolve_continue_target(db, conversation_id)

    # 3-4. 组装上下文（历史截止于目标，不插入 user；当前输入 None → 不追加）
    #      + 尾随续写触发 user 消息（指令 + 原消息末段）。
    #      组装/尾随触发均不抛 LLMError，移出 try；生成 + 错误映射收口于
    #      _generate_with_error_mapping（F-126）。
    ctx = assemble_chat_context(
        db, conversation_id, current_input=None,
        history_limit_message_id=target.id,
    )
    tail = _continuation_tail(target.content)
    trigger = CONTINUE_INSTRUCTION if not tail else f"{CONTINUE_INSTRUCTION}\n{tail}"
    ctx.messages.append({"role": "user", "content": trigger})
    reply_text = await _generate_with_error_mapping(ctx)

    # 5. message 层单一入口追加候选并置为激活：原内容保留（无候选时播种
    #    候选 0），续写结果 = 原内容 + 续写片段（消息条数不变；content 跟随激活
    #    候选）。bump 会话 updated_at + commit + refresh 收口于该单一入口。
    base_text = target.content or ""
    continuation = reply_text.strip()
    if not continuation:
        # 空续写（LLM 未产出片段）：零改动 no-op——不新增重复候选行（Falsify
        # 守卫：base + "" = base 会产生内容相同的重复候选），消息与候选均不动。
        return ChatResponse(
            reply=base_text,
            message_id=target.id,
            conversation_id=conversation_id,
        )
    new_text = base_text + continuation
    message_service.append_swipe_and_bump(db, target.id, new_text, make_active=True)

    return ChatResponse(
        reply=new_text,
        message_id=target.id,
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
        # WL-5 记忆宫殿：done 帧发出后触发归纳（Falsify 修复：归纳 LLM 调用不
        # 阻塞 done 帧；断连取消此时无副作用——消息已落库、done 已送达）
        if saved and full_content and message_id is not None:
            await _maybe_memory_palace(
                db, conversation_id, ctx.provider, ctx.conversation.model_name
            )
            # T6：CG 自动触发（done 帧后路径，与 complete_chat 同型）
            await _maybe_auto_cg(db, conversation_id, message_id)

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


def _lorebook_world_injection(
    db: Session,
    character: Character | None,
    history: Sequence[Message],
    current_input: str,
    user_name: str,
) -> dict[str, list[str]]:
    """组装世界书注入块（角色无启用条目 → {}，零开销）

    WL-3 注入链：list_entries → 启用条目最大 depth → collect_scan_text 构建扫描
    窗口（全量历史，与消息滑窗 max_rounds 解耦）→ activate（每次调用新 RNG，
    注入结果非确定性，符合概率/互斥组语义）→ build_world_injection。条目 →
    LorebookEntryData 的 ORM 解耦转换在此完成（引擎零 DB 依赖）。

    Args:
        db: 数据库会话
        character: 角色 ORM（None → 零注入）
        history: 对话历史（扫描窗口源，非滑窗截断后）
        current_input: 当前输入（重生成路径传 ""，靠历史命中）
        user_name: 用户昵称（{{user}} 模板变量）

    Returns:
        build_world_injection 输出形态（{system/before_char/after_char: [内容]}）；
        无条目/全部禁用时返回 {}
    """
    if character is None:
        return {}
    entries = lorebook_service.list_entries(db, character.id)
    enabled = [e for e in entries if e.enabled]
    if not enabled:
        return {}

    depth = max(e.depth for e in enabled)
    scan_text = collect_scan_text(history, current_input, depth, role_of=_msg_role)
    data_entries = [
        LorebookEntryData(
            id=e.id,
            keys=tuple(e.keys),
            content=e.content,
            constant=e.constant,
            order=e.order,
            probability=e.probability,
            group_name=e.group_name,
            group_weight=e.group_weight,
            match_mode=e.match_mode,
            position=e.position,
            enabled=e.enabled,
        )
        for e in enabled
    ]
    activated = activate_lorebook_entries(data_entries, scan_text, rng=random.Random())
    return build_world_injection(activated, user_name=user_name, char_name=character.name or "Character")


def _mod_prompt_injection(
    db: Session,
    character: Character | None,
    world_injection: dict[str, list[str]],
) -> dict[str, list[str]]:
    """把角色启用的 prompt 区 Mod 叠加进世界书注入块（MD-2/02 注入链）

    读取逻辑下沉为 mods_service 的区过滤读取 seam（F-123）：按 target_area="prompt"
    回读启用 Mod → ModPayload，再经 apply_prompt_mods 叠加（world→system）。角色为
    空 / 无绑定 / 全禁用 / 全非 prompt 区 → 原样返回 world_injection（零开销，与
    _lorebook_world_injection 的「无条目 → {}」同语义）。

    Args:
        db: 数据库会话
        character: 角色 ORM（None → 零注入）
        world_injection: _lorebook_world_injection 的产物
            （{system/before_char/after_char: [内容]}）

    Returns:
        叠加后的注入块 dict（apply_prompt_mods 返回新 dict；无可参与项时为
        原 world_injection 对象）
    """
    if character is None:
        return world_injection
    payloads = mods_service.list_enabled_mods_for_area(db, character.id, "prompt")
    if not payloads:
        return world_injection
    return mods_service.apply_prompt_mods(world_injection, payloads)


def _memory_mod_instructions(db: Session, character: Character | None) -> str:
    """读角色启用 memory 区 Mod 的归纳口径（T3：memory 区 Mod 消费数据源）

    读取逻辑下沉为 mods_service 的区过滤读取 seam（F-123）：按 target_area="memory"
    回读启用 Mod，取 payload 纯文本以 \n 连接（不做 JSON 解析、不转义）。空串/
    纯空白 payload 过滤与悬挂绑定跳过语义保留在本调用点（内存区专属，不下沉）。

    角色为空 / 无绑定 / 全禁用 / 无 memory Mod → 返回空串
    （空串传入 summarize_turn 时归纳 prompt 字节级不变——调用方零影响契约）。

    Args:
        db: 数据库会话
        character: 角色 ORM（None → 空串）

    Returns:
        memory 区 Mod payload 以 \n 连接的纯文本；无可参与项时为空串
    """
    if character is None:
        return ""
    payloads = mods_service.list_enabled_mods_for_area(db, character.id, "memory")
    # seam 继承 list_character_mods 的 (sort_order, mod_id) 升序，此处沿用其确定性排序
    lines = [p.payload for p in payloads if (p.payload or "").strip()]
    return "\n".join(lines)


def _msg_role(msg: object) -> str:
    """消息 → 角色字符串（委托 text_utils.role_str，F-94 收敛）"""
    return role_str(getattr(msg, "role", ""))


async def _maybe_memory_palace(
    db: Session,
    conversation_id: int,
    provider: BaseLLM,
    model: str | None,
) -> None:
    """记忆宫殿触发（WL-5）：开关开 + 阈值达标 → 归纳 → 落库；任何失败不阻断

    complete_chat / stream_reply 在完整回合落库后调用。异常隔离策略：
    summarize_turn 内部已吞 LLM/JSON 失败（返回 None）；本函数再包一层
    try/except 兜底意外（DB/计数异常等），保证记忆增强绝不破坏对话主流程。

    每 N 轮语义（Falsify/Spec 修复）：增量消息数 = 总消息数 - 已归纳轮数×2
    （每个 auto 条目对应一轮已消费），避免 N>1 时累计单调恒触发。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        provider: 本回合已解析的 LLM Provider（复用，不重复解析）
        model: 模型名（透传归纳调用）
    """
    try:
        if not setting_service.memory_palace_enabled(db):
            return
        conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
        if conv is None:
            return
        character = db.query(Character).filter(Character.id == conv.character_id).first()
        if character is None:
            return
        messages = message_service.get_messages(db, conversation_id)
        if not messages:
            return
        # 增量计数：每个 auto 条目对应已归纳的一轮（2 条消息），杜绝 N>1 时
        # 累计单调恒触发（should_summarize 纯函数语义不变，调用方传增量）
        auto_count = (
            db.query(func.count(LorebookEntry.id))
            .filter(
                LorebookEntry.character_id == character.id,
                LorebookEntry.source == "auto",
            )
            .scalar()
            or 0
        )
        incremental = max(0, len(messages) - auto_count * 2)
        char_count = sum(len(m.content or "") for m in messages)
        if not memory_palace_service.should_summarize(
            incremental,
            char_count,
            every_rounds=setting_service.memory_palace_every_rounds(db),
            char_threshold=setting_service.memory_palace_char_threshold(db),
        ):
            return
        draft = await memory_palace_service.summarize_turn(
            messages,
            provider=provider,
            model=model,
            user_name=setting_service.user_name(db),
            char_name=character.name,
            # T3：角色解析成功后回读 memory 区 Mod 归纳口径（无 memory Mod → 空串，
            # 归纳 prompt 字节级不变）；失败由本函数既有 try/except 隔离
            extra_instructions=_memory_mod_instructions(db, character),
        )
        if draft is not None:
            memory_palace_service.persist_drafts(db, character.id, [draft])
    except Exception:  # noqa: BLE001 — 异常隔离兜底（记忆增强失败绝不影响对话）
        logger.exception("记忆宫殿触发失败（已隔离，不影响对话主流程）")


async def _maybe_auto_cg(
    db: Session,
    conversation_id: int,
    assistant_message_id: int,
) -> None:
    """CG 自动触发（T6）：完整回合后按概率自动解锁候选 CG

    complete_chat / stream_reply 在完整回合落库后调用。异常隔离策略：任何失败不阻断
    主流程（logger.exception 记录）。

    详细语义见 spec T6-cg-auto-trigger.md。
    """
    try:
        prob = setting_service.cg_auto_trigger_probability(db)
        if prob == 0:
            return
        if random.randint(1, 100) > prob:
            return

        conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
        if conv is None:
            return
        character = db.query(Character).filter(Character.id == conv.character_id).first()
        if character is None:
            return

        from backend.app.services import gallery as gallery_service

        # 候选池：锁定且 weight>0 的 CG（weight=0 的锁定 CG 永不进池）
        candidates = (
            db.query(CgImage)
            .filter(
                CgImage.character_id == conv.character_id,
                CgImage.unlocked.is_(False),
                CgImage.weight > 0,
            )
            .all()
        )

        # pick_cg_by_weight 算法本体零改动（T1 落地）：空池 → None，空池 no-op
        cg = gallery_service.pick_cg_by_weight(candidates)
        if cg is None:
            return

        # 解锁走 gallery.unlock_cg 单一 seam（幂等 + refresh + CgImageNotFoundError 语义）
        cg = gallery_service.unlock_cg(db, cg.id)
        # 锚定：unlock_cg 本身不改锚，锚定在 _maybe_auto_cg 内补写
        cg.message_id = assistant_message_id
        cg.conversation_id = conversation_id
        db.commit()
    except Exception:  # noqa: BLE001 — 异常隔离兜底
        logger.exception("CG 自动触发失败（已隔离，不影响对话主流程）")

