"""
对话导出业务逻辑（JSON / Markdown）

深模块：协议表面仅三个公开函数（export_conversation_json / export_conversation_markdown /
character_export_filename），实现内收拢对话 + 角色 + 消息的组装与导出文件名的角色名生成
（路由只调服务，不直接操作 ORM）。

character 段复用 `schemas/conversation.py::ConversationExportCharacter`（from_attributes）驱动序列化，
Schema 即导出契约（字段名/顺序/类型唯一定义于此），service 层零手写字段映射。
与 character_card.to_v2_card 的区别：to_v2_card 输出的是 SillyTavern V2 信封（字段名/结构不同），
不适用于导出 JSON 的子集投影。

MD 导出的「角色信息」段在组装时应用模板变量替换（{{char}}/{{user}} → 角色名/用户昵称，
昵称读取自 setting.user_name，未配置回退默认）；JSON 导出保留原始设定（结构化数据往返保真），
两者行为差异是有意设计。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message
from backend.app.schemas.conversation import ConversationExportCharacter
from backend.app.services import setting as setting_service
from backend.app.services.llm.prompt import apply_template_vars

__all__ = [
    "character_export_filename",
    "export_conversation_json",
    "export_conversation_markdown",
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

    messages_data = []
    for msg in messages:
        messages_data.append({
            "id": msg.id,
            "role": msg.role.value,
            "content": msg.content,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
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
