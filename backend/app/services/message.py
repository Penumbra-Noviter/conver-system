"""
消息管理 & 聊天逻辑

协议表面（__all__）：get_messages / create_message / create_message_no_commit /
auto_insert_greeting / build_message_list / search_messages / require_message /
update_message / delete_message /
add_swipe / append_swipe_and_bump / list_swipes / list_swipes_batch /
switch_swipe / delete_swipe。
"""

from __future__ import annotations

import datetime
from collections.abc import Sequence

from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, MessageSwipe, Role
from backend.app.schemas.message import SearchResult
from backend.app.services import conversation as conversation_service
from backend.app.services.character_fields import PROMPT_FIELDS
from backend.app.services.exceptions import MessageNotFoundError, SwipeIndexError
from backend.app.services.llm.prompt import CharacterData, apply_template_vars, build_messages

__all__ = [
    "get_messages",
    "create_message",
    "create_message_no_commit",
    "auto_insert_greeting",
    "build_message_list",
    "search_messages",
    "require_message",
    "update_message",
    "delete_message",
    "add_swipe",
    "append_swipe_and_bump",
    "list_swipes",
    "list_swipes_batch",
    "switch_swipe",
    "delete_swipe",
]


def get_messages(db: Session, conversation_id: int) -> list[Message]:
    """获取对话的所有消息（按时间正序）"""
    return (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.asc())
        .all()
    )


def create_message(db: Session, conversation_id: int, role: Role, content: str) -> Message:
    """保存单条消息，同时更新对话的 updated_at 时间戳

    保存首条 user 消息时，若标题仍为占位默认值则同步替换为规则截断标题
    （规则收口于 conversation_service.maybe_auto_title，见 ARC-3）。

    内部调用 create_message_no_commit 后执行 commit + refresh。
    """
    msg = create_message_no_commit(db, conversation_id, role, content)
    db.commit()
    db.refresh(msg)
    return msg


def create_message_no_commit(db: Session, conversation_id: int, role: Role, content: str) -> Message:
    """创建消息对象并 add 到会话，但不提交（供事务原子性场景使用）

    与 create_message 相同的副作用（conv.updated_at、maybe_auto_title），
    但调用方负责后续 commit + refresh。典型用途：重生成时先截断后批量提交。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        role: 消息角色（USER / ASSISTANT）
        content: 消息内容

    Returns:
        Message 实例（未提交，id 为 None 直到 commit）
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if conv:
        conv.updated_at = datetime.datetime.now()
        if role == Role.USER:
            conversation_service.maybe_auto_title(db, conv, content)

    msg = Message(conversation_id=conversation_id, role=role, content=content)
    db.add(msg)
    return msg


def auto_insert_greeting(
    db: Session,
    conversation_id: int,
    user_name: str = "User",
) -> Message | None:
    """如果是对话的第一条消息且角色有 greeting，自动插入开场白

    在用户发送首条消息时调用，插入角色的 greeting 作为第一条 assistant 消息。
    支持 {{user}}/{{char}} 模板变量替换。
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if not conv:
        return None

    # 检查是否已有消息（包括 greeting）
    existing = db.query(Message).filter(Message.conversation_id == conversation_id).first()
    if existing:
        return None  # 已有消息，不重复插入

    # 获取角色的 greeting
    character = db.query(Character).filter(Character.id == conv.character_id).first()
    if not character or not character.first_mes:
        return None

    # 模板变量替换（纯函数来自 services/llm/prompt.py）
    greeting = apply_template_vars(character.first_mes, user_name, character.name)

    # 插入 greeting 作为 assistant 消息
    return create_message(db, conversation_id, Role.ASSISTANT, greeting)


def build_message_list(
    db: Session,
    conversation: Conversation,
    user_content: str,
    max_rounds: int = 30,
    user_name: str = "User",
    append_current_input: bool = True,
    world_injection: dict[str, list[str]] | None = None,
    history: Sequence[Message] | None = None,
) -> list[dict]:
    """构建发送给 LLM 的消息列表

    组装顺序：
        1. character.system_prompt 或 personality（作为 system prompt，支持模板变量）
        2. character.scenario（场景设定，支持模板变量）
        3. character.mes_example（对话范例，支持模板变量）
        4. 历史消息（按时间正序，受滑窗限制）
        5. character.post_history_instructions（历史后指令，支持模板变量）
        6. 当前用户输入（支持模板变量；append_current_input=False 时不追加）

    world_injection（WL-3）：世界书注入块（{before_char/after_char/system: [内容]}）
    透传给 build_messages；None/全空时零注入、输出与改动前逐字节一致。

    history（F-95）：可选外部传入的历史（None → 内部查询）。调用方（如
    assemble_chat_context 已为世界书扫描窗取过历史）传此参数可避免重复查询。

    查询角色与历史消息后，委托给 services/llm/prompt.py 的纯函数完成组装。

    append_current_input=False（重生成路径）：不追加当前 user 输入；输出末条
    为历史末条 user（待回复触发源），尾随 PHI system 一并剥离。

    模板变量：
        {{user}} — 用户昵称
        {{char}} — 角色名称
    """
    character = db.query(Character).filter(Character.id == conversation.character_id).first()
    if not character:
        raise ValueError(f"角色不存在: {conversation.character_id}")

    # 按 PROMPT_FIELDS 从 ORM 提取（单一映射深模块，C5 架构评审）
    char_data = CharacterData(**{
        field: getattr(character, field, "") or ""
        for field in PROMPT_FIELDS
    })
    if history is None:
        history = get_messages(db, conversation.id)

    return build_messages(
        character=char_data,
        history=history,
        user_content=user_content,
        max_rounds=max_rounds,
        user_name=user_name,
        append_current_input=append_current_input,
        world=world_injection,
    )


def search_messages(
    db: Session,
    query: str,
    limit: int = 50,
) -> list[SearchResult]:
    """搜索消息内容，返回带对话和角色上下文的搜索结果

    使用 SQLite LIKE 进行关键词匹配，按时间倒序排列。
    每条结果包含：消息预览、所属对话标题、角色名、角色头像、发送时间。
    返回 `list[SearchResult]`（字段契约见 schemas/message.py）。
    """
    if not query or not query.strip():
        return []

    q = f"%{query.strip()}%"

    results = (
        db.query(Message, Conversation, Character)
        .join(Conversation, Message.conversation_id == Conversation.id)
        .join(Character, Conversation.character_id == Character.id)
        .filter(Message.content.ilike(q))
        .order_by(Message.created_at.desc())
        .limit(limit)
        .all()
    )

    output = []
    for msg, conv, char in results:
        # 截取关键词周围的上下文片段
        content = msg.content or ""
        lower_content = content.lower()
        lower_query = query.strip().lower()
        idx = lower_content.find(lower_query)

        if idx >= 0:
            ctx_start = max(0, idx - 50)
            ctx_end = min(len(content), idx + len(query) + 50)
            prefix = "…" if ctx_start > 0 else ""
            suffix = "…" if ctx_end < len(content) else ""
            preview = prefix + content[ctx_start:ctx_end] + suffix
        else:
            preview = content[:120] + ("…" if len(content) > 120 else "")

        output.append(SearchResult(
            message_id=msg.id,
            conversation_id=conv.id,
            conversation_title=conv.title,
            character_id=char.id,
            character_name=char.name,
            character_avatar=char.avatar,
            role=msg.role.value,
            content_preview=preview,
            created_at=msg.created_at.isoformat() if msg.created_at else None,
        ))

    return output


# ════════════════════════════════════════════════════════════════
# MS-1 swipes 多候选
# ════════════════════════════════════════════════════════════════

def _require_message(db: Session, message_id: int) -> Message:
    """守卫：消息必须存在，否则抛 MessageNotFoundError"""
    msg = db.query(Message).filter(Message.id == message_id).first()
    if msg is None:
        raise MessageNotFoundError(f"消息不存在: {message_id}")
    return msg


def require_message(db: Session, message_id: int) -> Message:
    """按 ID 取单条消息（不存在抛 MessageNotFoundError）—— `_require_message` 的公开别名

    message 级端点（PUT /api/messages/{message_id}）的归属解析入口：由 message_id
    解析出消息及其 conversation_id 后委托下游（chat_service.edit_and_resend 需要
    conversation_id）。与 `_require_message` 同语义，公开供路由层调用，避免路由
    直接触碰 ORM。命名对齐 conversation_service.require_conversation（深函数守卫）。
    """
    return _require_message(db, message_id)


# ════════════════════════════════════════════════════════════════
# 消息级编辑 / 删除（message-edit-resend）
# ════════════════════════════════════════════════════════════════

def update_message(
    db: Session,
    message_id: int,
    content: str,
    *,
    commit: bool = True,
) -> Message:
    """就地替换消息 content（不触碰 swipes；user 消息无候选，assistant 编辑本期不做故候选无需处理）

    edit_and_resend 经 commit=False 参与原子落库（同 add_swipe(commit=False) 既有模式）：
    替换后不提交，由调用方统一 commit；commit=True 时提交并 refresh。

    Args:
        db: 数据库会话
        message_id: 目标消息 ID（不存在抛 MessageNotFoundError）
        content: 新内容
        commit: 是否提交（False 由调用方统一提交）

    Returns:
        更新后的 Message（commit=True 时已 refresh）

    Raises:
        MessageNotFoundError: 消息不存在
    """
    msg = _require_message(db, message_id)
    msg.content = content
    if commit:
        db.commit()
        db.refresh(msg)
    return msg


def delete_message(
    db: Session,
    message_id: int,
    *,
    commit: bool = True,
) -> None:
    """角色感知删除单条消息（spec §delete message）

    USER → 删除该条及其后所有消息（conversation_id 相同且 id >= 目标 id，
    后续 assistant 失去触发源）；ASSISTANT（及 system 等非 user 角色）→ 仅删
    该条，其候选经 message_swipes.message_id FK ON DELETE CASCADE 级联删除。
    删除后 bump 所属 conversation.updated_at（会话列表排序不变量，同
    append_swipe_and_bump 口径）。级联语义下沉 service 层受保护写：删除范围由
    本函数收敛，不靠调用方自觉。

    Args:
        db: 数据库会话
        message_id: 目标消息 ID（不存在抛 MessageNotFoundError）
        commit: 是否提交（False 由调用方统一提交）

    Raises:
        MessageNotFoundError: 消息不存在
    """
    msg = _require_message(db, message_id)
    conversation_id = msg.conversation_id
    if msg.role == Role.USER:
        db.query(Message).filter(
            Message.conversation_id == conversation_id,
            Message.id >= msg.id,
        ).delete(synchronize_session=False)
    else:
        db.delete(msg)
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if conv is not None:
        conv.updated_at = datetime.datetime.now()
    if commit:
        db.commit()


def add_swipe(
    db: Session,
    message_id: int,
    content: str,
    *,
    make_active: bool = True,
    commit: bool = True,
) -> int:
    """为消息追加候选（MS-1：重生成等操作改为追加而非覆盖）

    候选 0 = 消息原始内容（首次 add_swipe 时播种为候选行），新内容从候选 1 起
    递增——候选集含原始版本，UI 计数/切换/删除统一作用于候选行。序号与
    (message_id, index) 唯一约束一致；make_active=True 时同步更新
    messages.active_swipe_index。

    Args:
        db: 数据库会话
        message_id: 归属消息 ID（不存在抛 MessageNotFoundError）
        content: 候选内容
        make_active: 是否把新候选置为当前激活
        commit: 是否提交（False 由调用方统一提交——append_swipe_and_bump 的
            单 commit 结算：候选 + content 跟随 + updated_at bump 原子落库）

    Returns:
        新候选序号（index；首次追加返回 1，候选 0 为原始内容）
    """
    msg = _require_message(db, message_id)
    max_index = (
        db.query(func.max(MessageSwipe.index))
        .filter(MessageSwipe.message_id == message_id)
        .scalar()
    )
    if max_index is None:
        # 播种：原始内容 = 候选 0（受保护，delete_swipe 拒删）
        db.add(MessageSwipe(message_id=message_id, index=0, content=msg.content))
        max_index = 0
    next_index = max_index + 1  # max+1：删中间候选留空档后不碰撞（Falsify HIGH 修复）
    db.add(MessageSwipe(message_id=message_id, index=next_index, content=content))
    if make_active:
        # content 跟随激活候选（LLM 上下文/前端渲染读 msg.content = 当前候选）
        msg.content = content
        msg.active_swipe_index = next_index
    if commit:
        db.commit()
    return next_index


def append_swipe_and_bump(
    db: Session,
    message_id: int,
    content: str,
    *,
    make_active: bool = True,
) -> Message:
    """追加候选并连带 bump 会话 updated_at + commit + refresh（F-124 持久化仪式单一入口）

    收口「add_swipe → bump conversation.updated_at → commit → refresh」四步为一处：
    重生成 / 续写两调用点只传 message_id + 新文本。语义与原两调用点逐字一致：

    1. add_swipe(commit=False)（候选 0 播种 + 新候选置激活 + content 跟随，不提交）；
    2. 由 message_id 归属消息解析 conversation_id，取 Conversation；存在时
       bump updated_at（会话列表排序置顶不变量，漏 bump 隐患消除）；
    3. 单 commit（候选 + content 跟随 + updated_at bump 原子落库，F-127 消除两段
       提交窗口）+ refresh，返回刷新后的目标 Message。

    Args:
        db: 数据库会话
        message_id: 归属消息 ID（不存在抛 MessageNotFoundError）
        content: 候选内容
        make_active: 是否把新候选置为当前激活（content 跟随激活候选）

    Returns:
        刷新后的目标 Message（content/active_swipe_index 与候选一致）
    """
    add_swipe(db, message_id, content, make_active=make_active, commit=False)
    msg = _require_message(db, message_id)
    conv = db.query(Conversation).filter(Conversation.id == msg.conversation_id).first()
    if conv is not None:
        conv.updated_at = datetime.datetime.now()
    db.commit()
    db.refresh(msg)
    return msg


def list_swipes(db: Session, message_id: int) -> list[MessageSwipe]:
    """消息候选列表（index 升序）"""
    return (
        db.query(MessageSwipe)
        .filter(MessageSwipe.message_id == message_id)
        .order_by(MessageSwipe.index.asc())
        .all()
    )


def list_swipes_batch(
    db: Session,
    message_ids: Sequence[int],
) -> dict[int, list[str]]:
    """批量取候选内容（message_id → index 升序 content 列表；无候选消息缺键）

    BR-1：快照导出等批量场景复用——一次 IN 查询填充全部候选，避免逐消息
    list_swipes 的 N+1（MS-2 路由 _with_swipes_batch 同构逻辑上移服务层，
    路由改指本函数，单一实现）。

    Args:
        db: 数据库会话
        message_ids: 消息 id 序列（空 → 空 dict，零查询）

    Returns:
        {message_id: [候选 content，index 升序]}；无候选消息不出现键
    """
    if not message_ids:
        return {}
    rows = (
        db.query(MessageSwipe.message_id, MessageSwipe.content)
        .filter(MessageSwipe.message_id.in_(message_ids))
        .order_by(MessageSwipe.message_id, MessageSwipe.index)
        .all()
    )
    swipes_by_message: dict[int, list[str]] = {}
    for message_id, content in rows:
        swipes_by_message.setdefault(message_id, []).append(content)
    return swipes_by_message


def switch_swipe(db: Session, message_id: int, index: int) -> Message:
    """切换激活候选（越界抛 SwipeIndexError）并更新 active_swipe_index

    Args:
        db: 数据库会话
        message_id: 归属消息 ID
        index: 目标候选序号（必须存在）

    Returns:
        更新后的 Message
    """
    msg = _require_message(db, message_id)
    exists = (
        db.query(MessageSwipe.id)
        .filter(MessageSwipe.message_id == message_id, MessageSwipe.index == index)
        .first()
    )
    if exists is None:
        raise SwipeIndexError(f"候选序号不存在: {index}")
    swipe = (
        db.query(MessageSwipe)
        .filter(MessageSwipe.message_id == message_id, MessageSwipe.index == index)
        .first()
    )
    msg.content = swipe.content  # content 跟随激活候选
    msg.active_swipe_index = index
    db.commit()
    db.refresh(msg)
    return msg


def delete_swipe(db: Session, message_id: int, index: int) -> Message:
    """删除候选；删除当前激活候选时回落到相邻候选（小于被删 index 的最大现存，
    否则大于的最小现存）；候选 0 = 消息原始内容，受保护拒删（永不出现候选清空态）

    Args:
        db: 数据库会话
        message_id: 归属消息 ID
        index: 待删除候选序号

    Returns:
        更新后的 Message
    """
    msg = _require_message(db, message_id)
    if index == 0:
        raise SwipeIndexError("候选 0 为消息原始内容，受保护不可删除")
    swipe = (
        db.query(MessageSwipe)
        .filter(MessageSwipe.message_id == message_id, MessageSwipe.index == index)
        .first()
    )
    if swipe is None:
        raise SwipeIndexError(f"候选序号不存在: {index}")
    db.delete(swipe)

    remaining = [
        row[0]
        for row in db.query(MessageSwipe.index)
        .filter(MessageSwipe.message_id == message_id)
        .order_by(MessageSwipe.index.asc())
        .all()
    ]
    if msg.active_swipe_index == index:
        # 回落到相邻候选：小于被删 index 的最大现存，否则大于的最小现存；
        # content 同步跟随回落候选（候选 0 = 原始内容永远在，无「清空」态）
        fallback = (lower[-1] if (lower := [i for i in remaining if i < index]) else remaining[0])
        msg.active_swipe_index = fallback
        msg.content = (
            db.query(MessageSwipe.content)
            .filter(MessageSwipe.message_id == message_id, MessageSwipe.index == fallback)
            .scalar()
        )
    db.commit()
    db.refresh(msg)
    return msg
