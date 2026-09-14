"""
对话 CRUD 业务逻辑（BR-2：clone_conversation / branch_from_message 分支派生）
"""

from __future__ import annotations

import datetime
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, MessageSwipe, Role
from backend.app.schemas.branch import BranchSnapshot
from backend.app.schemas.conversation import ConversationCreate, ConversationUpdate
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    BranchSnapshotError,
    CharacterNotFoundError,
    ConversationNotFoundError,
    MessageNotFoundError,
)
from backend.app.services.llm.prompt import apply_template_vars


def list_conversations(db: Session, character_id: Optional[int] = None) -> list[Conversation]:
    """获取对话列表，附带消息数量与分支来源元数据（锚消息截断预览）

    F-100 能力 2（后端最小暴露）：对分支派生会话带出 parent_conversation_id /
    branch_from_message_id / branch_title 三列（ORM 已写入，此处随列表序列化），
    并经关联查询补 branch_from_message_preview（锚消息 content 截断 ~60 字符）；
    普通会话该字段为 None（不渲染分支标记的依据）。
    """
    # 锚消息内容（分支会话 branch_from_message_id 指向父会话中的分叉锚消息；
    # 父已删时 branch_from_message_id 置 NULL → 子查询无命中 → 预览为 None）
    anchor_content = (
        select(Message.content)
        .where(Message.id == Conversation.branch_from_message_id)
        .correlate(Conversation)
        .scalar_subquery()
    )
    query = db.query(
        Conversation,
        func.count(Message.id).label("message_count"),
        anchor_content.label("branch_from_message_preview"),
    ).outerjoin(
        Message, Message.conversation_id == Conversation.id
    ).group_by(Conversation.id)

    if character_id is not None:
        query = query.filter(Conversation.character_id == character_id)

    results = []
    for conv, count, anchor_raw in query.order_by(Conversation.updated_at.desc()).all():
        conv.message_count = count
        conv.branch_from_message_preview = _truncate_branch_preview(anchor_raw)
        results.append(conv)
    return results


def get_conversation(db: Session, conversation_id: int) -> Optional[Conversation]:
    """获取单个对话"""
    return db.query(Conversation).filter(Conversation.id == conversation_id).first()


def require_conversation(db: Session, conversation_id: int) -> Conversation:
    """获取对话，不存在时抛 ConversationNotFoundError（深函数）

    路由层「不存在」守卫统一走此处：内部 get + 领域异常上抛，
    由统一 exception handler 转 404，不再各写各的 HTTPException。
    """
    conv = get_conversation(db, conversation_id)
    if not conv:
        raise ConversationNotFoundError("对话不存在")
    return conv


def _default_title_for_character(char_name: str | None) -> str:
    """生成对话占位默认标题「与 {角色名} 的对话」"""
    return f"与 {char_name or '角色'} 的对话"


def truncate_title(text: str, max_len: int = 20) -> str:
    """规则截断对话标题（纯函数）

    折叠所有空白为单空格并去首尾，截取前 max_len 个字符后追加「…」；
    不剥离 Markdown 语法（原样截断字符）。
    """
    collapsed = " ".join(text.split())
    if len(collapsed) <= max_len:
        return collapsed
    return collapsed[:max_len] + "…"


def _truncate_branch_preview(content: str | None, max_len: int = 60) -> str | None:
    """锚消息预览截断（纯函数）

    折叠所有空白为单空格并去首尾，截取前 max_len 个字符后追加「…」；
    None / 空 / 纯空白返回 None（普通会话或锚消息缺失时不渲染分支标记）。
    """
    if not content:
        return None
    collapsed = " ".join(content.split())
    if not collapsed:
        return None
    if len(collapsed) <= max_len:
        return collapsed
    return collapsed[:max_len] + "…"


def default_conversation_title(db: Session, conversation_id: int) -> str:
    """返回对话当前的占位默认标题

    用于判断标题是否仍为自动生成的占位值（首条 user 消息后应被替换）。
    """
    conv = get_conversation(db, conversation_id)
    if not conv:
        return "新对话"
    character = db.query(Character).filter(Character.id == conv.character_id).first()
    return _default_title_for_character(character.name if character else None)


def maybe_auto_title(db: Session, conv: Conversation, content: str) -> None:
    """首条 user 消息且标题仍为占位默认值时，用规则截断标题替换

    标题生命周期（占位默认 → 首条替换）在此一文件收口：
        - 占位默认：`_default_title_for_character`（「与 {角色名} 的对话」）
        - 截断：`truncate_title`
        - 替换：本函数，仅在首条 user 消息且标题未被显式命名时发生

    调用时机：create_message 保存 user 消息之前（避免 autoflush 把本条算作已有 user 消息）。
    """
    if not conv or not content:
        return
    existing_user = (
        db.query(Message)
        .filter(Message.conversation_id == conv.id, Message.role == Role.USER)
        .first()
    )
    if existing_user is not None:
        return  # 本条不是首条 user 消息
    if conv.title != default_conversation_title(db, conv.id):
        return  # 标题已被显式命名，不覆盖
    conv.title = truncate_title(content)


def create_conversation(db: Session, data: ConversationCreate) -> Conversation:
    """创建对话

    标题：未显式传 title（或传空）时默认「与 {角色名} 的对话」；
    模型：未显式传 model_provider/model_name 时回退到 settings 默认值（再回退到 config 默认值）。
    预设对话快照：data.preset_dialogue 原样固化到列（None/空串 → null，不落伪值），
    前端选择、后端信任落库（与 greeting 快照同语义，不校验是否属于角色 preset_dialogues）。
    """
    character = db.query(Character).filter(Character.id == data.character_id).first()
    title = (
        data.title
        if "title" in data.model_fields_set and data.title
        else _default_title_for_character(character.name if character else None)
    )
    # 仅当请求显式传入 model_provider/model_name 时采用；否则用 settings 默认值（未设置时用 config 默认值）
    provider = (
        data.model_provider
        if "model_provider" in data.model_fields_set
        else setting_service.default_provider(db)
    )
    model_name = (
        data.model_name
        if "model_name" in data.model_fields_set
        else setting_service.default_model(db)
    )

    conv = Conversation(
        character_id=data.character_id,
        title=title,
        model_provider=provider,
        model_name=model_name,
        # 预设对话快照：None/空串归一为 null（不落伪值），非空原样固化
        preset_dialogue=data.preset_dialogue or None,
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)

    # 预插开场白：创建对话时把开场白插入为首条 assistant 消息
    #   - 显式传 greeting 时以其值为准（None/空串 → 不预插）
    #   - 未传 greeting 时用 character.first_mes（既有语义，零回归）
    if "greeting" in data.model_fields_set:
        greeting_text = data.greeting
    else:
        greeting_text = character.first_mes if character else None

    if greeting_text:
        user_name = (setting_service.get_value(db, 'user_name') or 'User')
        char_name = character.name if character else "Character"
        content = apply_template_vars(greeting_text, user_name, char_name)
        message_service.create_message(db, conv.id, Role.ASSISTANT, content)

    db.refresh(conv)
    return conv


def update_conversation(db: Session, conversation_id: int, data: ConversationUpdate) -> Optional[Conversation]:
    """更新对话"""
    conv = get_conversation(db, conversation_id)
    if not conv:
        return None
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(conv, field, value)
    db.commit()
    db.refresh(conv)
    return conv


def delete_conversation(db: Session, conversation_id: int) -> bool:
    """删除对话及关联消息（级联）

    BR-2 删源置空策略：删除源会话**不连坐已派生分支**——先将其子会话的
    parent_conversation_id / branch_from_message_id 置 NULL（与 SQLite
    ON DELETE SET NULL 同语义；本模型对分支列不加 FK——存量库 ALTER 补
    自引用 FK 不可靠，故在服务层显式兑现并锁定），branch_title 保留
    （分支显示名仍可用）。
    """
    conv = get_conversation(db, conversation_id)
    if not conv:
        return False
    db.query(Conversation).filter(
        Conversation.parent_conversation_id == conversation_id
    ).update({"parent_conversation_id": None, "branch_from_message_id": None})
    db.delete(conv)
    db.commit()
    return True


def delete_all_conversations(db: Session) -> None:
    """清空所有对话及关联消息"""
    db.query(Message).delete()
    db.query(Conversation).delete()
    db.commit()


# ════════════════════════════════════════════════════
# BR-2 分支派生（快照导入 / 锚消息分支）
# ════════════════════════════════════════════════════

def clone_conversation(
    db: Session,
    snapshot: BranchSnapshot,
    *,
    title: str | None = None,
) -> Conversation:
    """从分支快照重建会话（BR-2：导入 / 分支共用）

    新会话：character_id 复用快照角色（**世界书为角色级共享**——随角色自然
    继承，不重插条目：重插会产生角色条目重复副本，破坏记忆宫殿增量计数等
    既有不变量；「新会话独立可改」在共享角色模型下不可兑现，Spec 偏差记录）；
    消息按快照序（build_branch_snapshot 输出即 id 序=插入序）重建，role /
    content / created_at 往返保真；候选与激活序号按快照 swipes 的
    message_index 直接落库（候选 0 = 原始内容；content 恒等于激活候选）。

    防御校验（契约锁锁定，手写快照破坏不变量即拒）：
        - 角色存在（CharacterNotFoundError → 404）
        - 消息角色合法（Role 枚举成员；非法 → BranchSnapshotError）
        - 激活序号在候选范围内、content == 激活候选（快照不变量）

    Args:
        db: 数据库会话
        snapshot: 校验通过的分支快照（BranchSnapshot；路由层经
            validate_branch_snapshot 先行校验版本身份）
        title: 新会话标题；None → 快照标题（再缺省「与 {角色名} 的对话」）

    Returns:
        重建的新会话

    Raises:
        CharacterNotFoundError: 快照角色不存在
        BranchSnapshotError: 消息角色非法 / 激活序号越界 / content≠激活候选
    """
    character = db.query(Character).filter(Character.id == snapshot.character_id).first()
    if character is None:
        raise CharacterNotFoundError(f"角色不存在: {snapshot.character_id}")

    conv = Conversation(
        character_id=snapshot.character_id,
        title=title or snapshot.title or _default_title_for_character(character.name),
        model_provider=snapshot.model_provider or setting_service.default_provider(db),
        model_name=snapshot.model_name or setting_service.default_model(db),
    )
    db.add(conv)
    db.flush()  # 取新会话 id（候选引用）

    # 消息按快照序重建（created_at 保真；非法角色 → 明确异常）
    rebuilt = []
    for item in snapshot.messages:
        try:
            role = Role(item.role)
        except ValueError as e:
            raise BranchSnapshotError(f"快照消息角色无效: {item.role}") from e
        msg = Message(
            conversation_id=conv.id,
            role=role,
            content=item.content,
            created_at=item.created_at,
        )
        db.add(msg)
        rebuilt.append(msg)
    db.flush()  # 取消息 id（候选引用）

    # 候选与激活序号直接落库（不走 add_swipe：播种语义假设 content 即候选 0）
    for entry in snapshot.swipes:
        if entry.message_index >= len(rebuilt):
            raise BranchSnapshotError(
                f"快照候选 message_index 越界: {entry.message_index}"
            )
        target = rebuilt[entry.message_index]
        if not entry.swipes:
            continue
        if entry.active_swipe_index >= len(entry.swipes):
            raise BranchSnapshotError(
                f"快照激活序号越界: {entry.active_swipe_index}（候选仅 {len(entry.swipes)} 条）"
            )
        if target.content != entry.swipes[entry.active_swipe_index]:
            raise BranchSnapshotError("快照消息内容与激活候选不一致（content 须跟随激活候选）")
        for index, content in enumerate(entry.swipes):
            db.add(MessageSwipe(message_id=target.id, index=index, content=content))
        target.active_swipe_index = entry.active_swipe_index

    conv.updated_at = datetime.datetime.now()
    db.commit()
    db.refresh(conv)
    return conv


def branch_from_message(
    db: Session,
    conversation_id: int,
    message_id: int,
    *,
    title: str | None = None,
) -> Conversation:
    """从源会话的锚消息处派生分支会话（BR-2，spec §BR-2）

    编排：校验源会话 + 锚消息（存在 / 属于该会话，404）→ 截断快照（含锚）→
    clone（消息/候选重建；世界书随角色共享）→ 记录 parent_conversation_id /
    branch_from_message_id / branch_title（分支显示名）→ 返回新会话。

    Args:
        db: 数据库会话
        conversation_id: 源会话 ID
        message_id: 分叉锚消息 id（该消息为快照末条，含；随源删除时分支引用置空）
        title: 分支显示名（进入 branch_title 与新会话标题）

    Returns:
        新分支会话（parent/branch_from_message_id 已记录）

    Raises:
        ConversationNotFoundError: 源会话不存在
        MessageNotFoundError: 锚消息不存在或不属于该会话
    """
    conv = require_conversation(db, conversation_id)
    anchor = (
        db.query(Message.id)
        .filter(Message.id == message_id, Message.conversation_id == conversation_id)
        .first()
    )
    if anchor is None:
        raise MessageNotFoundError(f"分叉锚消息不存在: {message_id}")

    # 延迟导入防循环：conversation_export 依赖本模块（require_conversation）
    from backend.app.services import conversation_export as export_service

    snapshot = export_service.build_branch_snapshot(
        db, conversation_id, upto_message_id=message_id
    )
    new_conv = clone_conversation(db, snapshot, title=title)
    new_conv.parent_conversation_id = conversation_id
    new_conv.branch_from_message_id = message_id
    new_conv.branch_title = title
    db.commit()
    db.refresh(new_conv)
    return new_conv
