"""
对话导出业务逻辑（JSON / Markdown / 分支快照）

深模块：协议表面五个公开函数（export_conversation_json / export_conversation_markdown /
character_export_filename / build_branch_snapshot / validate_branch_snapshot），实现内收拢
对话 + 角色 + 消息的组装与导出文件名的角色名生成（路由只调服务，不直接操作 ORM）。

character 段复用 `schemas/conversation.py::ConversationExportCharacter`（from_attributes）驱动序列化，
Schema 即导出契约（字段名/顺序/类型唯一定义于此），service 层零手写字段映射。
与 character_card.to_v2_card 的区别：to_v2_card 输出的是 SillyTavern V2 信封（字段名/结构不同），
不适用于导出 JSON 的子集投影。

MD 导出的「角色信息」段在组装时应用模板变量替换（{{char}}/{{user}} → 角色名/用户昵称，
昵称读取自 setting.user_name，未配置回退默认）；JSON 导出保留原始设定（结构化数据往返保真），
两者行为差异是有意设计。

分支快照（BR-1）：build_branch_snapshot 产出**版本化** BranchSnapshot（version 字段，
Schema 见 schemas/branch.py），载荷含消息（role/content/created_at，按 id 升序——id=插入序，
created_at 秒精度同秒乱序不可靠）、世界书条目与候选（记忆随存档走）；validate_branch_snapshot
拒绝缺失/不支持版本与畸形结构（BranchSnapshotError → 400），BR-2 导入复用。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message
from backend.app.schemas.branch import (
    SNAPSHOT_VERSION,
    BranchSnapshot,
    BranchSnapshotLorebookEntry,
    BranchSnapshotMessage,
    BranchSnapshotSwipe,
)
from backend.app.schemas.conversation import ConversationExportCharacter
from backend.app.services import conversation as conversation_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import BranchSnapshotError, MessageNotFoundError
from backend.app.services.llm.prompt import apply_template_vars
from pydantic import ValidationError

__all__ = [
    "build_branch_snapshot",
    "character_export_filename",
    "export_conversation_json",
    "export_conversation_markdown",
    "validate_branch_snapshot",
]


def _character_export_data(character: Character) -> dict:
    """角色 ORM → 导出 JSON 的 character 段

    Schema 驱动（ConversationExportCharacter，from_attributes），
    字段契约即 Schema 定义，新增角色字段只需维护 Schema 一处。
    """
    return ConversationExportCharacter.model_validate(character).model_dump()


def export_conversation_json(db: Session, conversation_id: int) -> dict | None:
    """导出对话为 JSON 格式

    结构：`{ conversation, character, messages[] }`；对话不存在返回 None。
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if not conv:
        return None

    character = db.query(Character).filter(Character.id == conv.character_id).first()

    messages = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.asc())
        .all()
    )

    character_data = _character_export_data(character) if character else None

    # 候选批量取（list_swipes_batch 一次 IN 查询，消除逐消息 N+1；BR-1 共享单点）
    swipes_by_message = message_service.list_swipes_batch(db, [m.id for m in messages])

    messages_data = []
    for msg in messages:
        messages_data.append({
            "id": msg.id,
            "role": msg.role.value,
            "content": msg.content,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
            "active_swipe_index": msg.active_swipe_index,
            "swipes": swipes_by_message.get(msg.id, []),
        })

    return {
        "conversation": {
            "id": conv.id,
            "title": conv.title,
            "model_provider": conv.model_provider,
            "model_name": conv.model_name,
            "created_at": conv.created_at.isoformat() if conv.created_at else None,
            "updated_at": conv.updated_at.isoformat() if conv.updated_at else None,
        },
        "character": character_data,
        "messages": messages_data,
    }


def export_conversation_markdown(db: Session, conversation_id: int) -> str | None:
    """导出对话为 Markdown 格式

    结构：标题 + 角色信息 + 模型/时间元信息 + 按日期分组的消息；对话不存在返回 None。
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if not conv:
        return None

    character = db.query(Character).filter(Character.id == conv.character_id).first()

    messages = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.asc())
        .all()
    )

    character_name = character.name if character else "未知角色"
    character_info_parts = []
    if character:
        # 仅 MD 导出的「角色信息」段替换模板变量（{{char}}/{{user}}）；
        # JSON 导出与角色卡导出保留原始设定（结构化数据/往返保真）
        user_nickname = setting_service.user_name(db)
        if character.description:
            character_info_parts.append(
                apply_template_vars(character.description, user_name=user_nickname, char_name=character.name)
            )
        if character.personality:
            character_info_parts.append(
                f"人格: {apply_template_vars(character.personality, user_name=user_nickname, char_name=character.name)}"
            )
        if character.scenario:
            character_info_parts.append(
                f"场景: {apply_template_vars(character.scenario, user_name=user_nickname, char_name=character.name)}"
            )
    character_info = "；".join(character_info_parts) if character_info_parts else "无"

    lines = [f"# 与 {character_name} 的对话", ""]
    lines.append(f"**角色信息**: {character_info}")
    lines.append(f"**模型**: {conv.model_provider}/{conv.model_name}")

    created_str = conv.created_at.strftime("%Y-%m-%d %H:%M") if conv.created_at else "未知"
    lines.append(f"**时间**: {created_str}")
    lines.append("")
    lines.append("---")
    lines.append("")

    current_date = None
    for msg in messages:
        if msg.created_at:
            msg_date = msg.created_at.strftime("%Y-%m-%d")
        else:
            msg_date = None

        if msg_date != current_date:
            if current_date is not None:
                lines.append("---")
                lines.append("")
            lines.append(f"### {msg_date}")
            lines.append("")
            current_date = msg_date

        lines.append(f"**{msg.role.value}**: {msg.content}")
        lines.append("")

    return "\n".join(lines)


def character_export_filename(db: Session, conversation_id: int) -> str:
    """导出文件名中的角色名（空格折叠为下划线；无角色 / 无名回退对话 id）

    语义自路由层原样搬迁：对话不存在 / 角色缺失 / 角色名为空 → 回退对话 id 字符串；
    否则返回角色名并将空格折叠为下划线（下载文件名友好）。
    """
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if conv is None:
        return str(conversation_id)
    char = db.query(Character).filter(Character.id == conv.character_id).first()
    if char is None or not char.name:
        return str(conversation_id)
    return char.name.replace(" ", "_")


def build_branch_snapshot(
    db: Session,
    conversation_id: int,
    upto_message_id: int | None = None,
) -> BranchSnapshot:
    """构建分支快照（版本化导出；BR-1，spec §BR-1）

    载荷：{version, character_id, model_provider, model_name, title,
    messages:[{role, content, created_at}], lorebook_entries:[...], swipes:[...]}
    ——记忆随存档走（世界书条目 + 候选集与激活序号，对齐对标站语义）。
    消息按 **id 升序**（id=插入序；created_at 为秒精度，同秒多条时排序不可靠，
    快照/重建的稳定序以 id 为准）；swipes 的 message_index 指向截断后 messages
    数组下标。候选批量取（list_swipes_batch 一次 IN 查询，无 N+1）。

    Args:
        db: 数据库会话
        conversation_id: 对话 ID
        upto_message_id: 截断锚消息 id（**含**）；None → 全量。锚不存在或
            不属于该对话 → MessageNotFoundError（禁止静默空快照）

    Returns:
        分支快照（BranchSnapshot）

    Raises:
        ConversationNotFoundError: 对话不存在
        MessageNotFoundError: 锚消息不存在或不属于该对话
    """
    conv = conversation_service.require_conversation(db, conversation_id)

    # 截断锚校验：存在 + 属于该对话（先于查询，避免静默空快照）
    if upto_message_id is not None:
        anchor = (
            db.query(Message.id)
            .filter(Message.id == upto_message_id, Message.conversation_id == conversation_id)
            .first()
        )
        if anchor is None:
            raise MessageNotFoundError(f"分叉锚消息不存在: {upto_message_id}")

    messages = (
        db.query(Message)
        .filter(Message.conversation_id == conversation_id)
        .order_by(Message.id.asc())
        .all()
    )
    if upto_message_id is not None:
        messages = [m for m in messages if m.id <= upto_message_id]

    swipes_by_message = message_service.list_swipes_batch(db, [m.id for m in messages])

    snapshot_messages = [
        BranchSnapshotMessage(
            role=m.role.value,
            content=m.content,
            created_at=m.created_at,
        )
        for m in messages
    ]
    snapshot_swipes = [
        BranchSnapshotSwipe(
            message_index=index,
            swipes=swipes_by_message[m.id],
            active_swipe_index=m.active_swipe_index,
        )
        for index, m in enumerate(messages)
        if m.id in swipes_by_message
    ]
    snapshot_entries = [
        BranchSnapshotLorebookEntry(
            title=e.title,
            keys=list(e.keys),
            content=e.content,
            constant=e.constant,
            order=e.order,
            probability=e.probability,
            group_name=e.group_name,
            group_weight=e.group_weight,
            match_mode=e.match_mode,
            position=e.position,
            depth=e.depth,
            source=e.source,
            enabled=e.enabled,
        )
        for e in lorebook_service.list_entries(db, conv.character_id)
    ]

    return BranchSnapshot(
        version=SNAPSHOT_VERSION,
        character_id=conv.character_id,
        model_provider=conv.model_provider,
        model_name=conv.model_name,
        title=conv.title,
        messages=snapshot_messages,
        lorebook_entries=snapshot_entries,
        swipes=snapshot_swipes,
    )


def validate_branch_snapshot(data: object) -> BranchSnapshot:
    """校验快照 dict → BranchSnapshot（版本号缺失/不支持 → 明确异常）

    BR-1 交付、BR-2 导入端点复用：快照 JSON 为版本化结构，未知版本拒绝导入
    （SNAPSHOT_VERSION 单一来源）；结构畸形（pydantic ValidationError）统一
    包装为 BranchSnapshotError 明确消息，不裸抛。

    Args:
        data: 快照数据（JSON 反序列化后的 dict）

    Returns:
        校验通过的 BranchSnapshot

    Raises:
        BranchSnapshotError: 非 dict / 缺 version / version 不支持 / 结构畸形
    """
    if not isinstance(data, dict):
        raise BranchSnapshotError("快照格式无效：应为 JSON 对象")
    version = data.get("version")
    if version is None:
        raise BranchSnapshotError("快照缺少版本号（version 字段），无法识别格式")
    if version != SNAPSHOT_VERSION:
        raise BranchSnapshotError(
            f"不支持的快照版本: {version}（当前支持版本 {SNAPSHOT_VERSION}）"
        )
    try:
        return BranchSnapshot.model_validate(data)
    except ValidationError as e:
        raise BranchSnapshotError(f"快照结构无效: {e}") from e
