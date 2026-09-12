"""
图片生成任务服务（CG-3，深模块）

协议表面（__all__）：create_image_task / get_image_task / run_image_task。

出图链路：提交（pending）→ 后台 run_image_task（running → generate → 成功
gallery.add_cg + succeeded / 失败 failed + error）。run_image_task 核心逻辑
session 注入（测试可传 test 会话）；路由后台包装负责 SessionLocal 生命周期。
「失败不破坏对话」：任何异常吞并落 failed 态 + error（对话主流程零影响）。
"""

from __future__ import annotations

import datetime
import json

from sqlalchemy.orm import Session

from backend.app.models.conversation import Conversation
from backend.app.models.image_task import ImageTask
from backend.app.models.message import Message
from backend.app.services import gallery as gallery_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ConversationNotFoundError,
    ImageTaskNotFoundError,
    MessageNotFoundError,
)
from backend.app.services.image.base import ImageGenParams
from backend.app.services.image.model_data import image_provider_id
from backend.app.services.image.resolver import resolve_image

__all__ = [
    "create_image_task",
    "get_image_task",
    "run_image_task",
    "image_generation_available",
]


def image_generation_available(db: Session) -> bool:
    """生图能力门控单一来源（MD-3）

    判定（读 settings image_provider / image_base_url）：
        - provider 未配置（空串）→ False
        - provider = local（占位后端，仅开发/测试）→ False（生产不可用）
        - provider 为 HTTP 类（a1111 / custom-http）→ base_url 非空才可用
        - 未登记 provider → False

    Args:
        db: 数据库会话

    Returns:
        是否配置了可用的生图后端
    """
    provider = setting_service.image_provider(db)
    if not provider:
        return False
    try:
        protocol_id = image_provider_id(provider)
    except KeyError:
        return False
    if protocol_id == "local":
        return False  # 占位后端生产不可用
    if protocol_id == "http":
        return bool(setting_service.image_base_url(db))
    return False


def create_image_task(
    db: Session,
    *,
    conversation_id: int,
    character_id: int,
    prompt: str,
    negative_prompt: str = "",
    width: int = 512,
    height: int = 512,
    steps: int = 20,
    provider: str = "local",
    message_id: int | None = None,
) -> ImageTask:
    """提交图片生成任务（status=pending，参数 JSON 落 params）

    Args:
        db: 数据库会话
        conversation_id: 产出会话
        character_id: 归属作品
        prompt: 生成提示词
        negative_prompt: 负面提示词
        width: 图片宽
        height: 图片高
        steps: 采样步数
        provider: 图片 Provider 标识（缺省 local）
        message_id: 出图锚消息 id（可选；须属于该会话）

    Returns:
        新建 ImageTask（status=pending）

    Raises:
        ConversationNotFoundError: 会话不存在（路由层 404）
        MessageNotFoundError: 锚消息不存在 / 不属于该会话
    """
    if db.query(Conversation.id).filter(Conversation.id == conversation_id).first() is None:
        raise ConversationNotFoundError("对话不存在")
    if message_id is not None:
        anchor = (
            db.query(Message.id)
            .filter(Message.id == message_id, Message.conversation_id == conversation_id)
            .first()
        )
        if anchor is None:
            raise MessageNotFoundError(f"消息不存在: {message_id}")

    params = ImageGenParams(
        prompt=prompt,
        negative_prompt=negative_prompt,
        width=width,
        height=height,
        steps=steps,
    )
    task = ImageTask(
        conversation_id=conversation_id,
        character_id=character_id,
        message_id=message_id,
        provider=provider,
        params=params.model_dump_json(),
        status="pending",
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


def get_image_task(db: Session, task_id: int) -> ImageTask:
    """轮询任务状态（不存在 → ImageTaskNotFoundError → 404）

    Args:
        db: 数据库会话
        task_id: 任务 id

    Returns:
        任务（status/result_url/error 由响应 schema 投影）
    """
    task = db.query(ImageTask).filter(ImageTask.id == task_id).first()
    if task is None:
        raise ImageTaskNotFoundError(f"图片任务不存在: {task_id}")
    return task


async def run_image_task(task_id: int, db: Session) -> None:
    """执行图片生成任务核心逻辑（session 注入，路由后台包装负责生命周期）

    编排：pending → running → resolve_image → generate → 成功 gallery.add_cg
    （出图入资产库，url = 本地文件路径）+ succeeded；失败（Provider/生成/落库
    任何异常）→ failed + error。「失败不破坏对话」——异常吞并落 failed 态，
    不外抛（对话主流程零影响）。

    Args:
        task_id: 任务 id
        db: 数据库会话（测试传 test 会话；生产路由后台用 SessionLocal）
    """
    task = db.query(ImageTask).filter(ImageTask.id == task_id).first()
    if task is None or task.status != "pending":
        return

    task.status = "running"
    db.commit()

    try:
        params = ImageGenParams(**json.loads(task.params))
        _, backend = resolve_image(
            task.provider, base_url=setting_service.image_base_url(db)
        )
        result = await backend.generate(params)
        gallery_service.add_cg(
            db,
            task.character_id,
            result.url,
            conversation_id=task.conversation_id,
            message_id=task.message_id,
        )
        task.status = "succeeded"
        task.result_url = result.url
        task.completed_at = datetime.datetime.now()
        db.commit()
    except Exception as e:  # noqa: BLE001 — 失败落 failed 态不外抛（不破坏对话）
        db.rollback()
        task = db.query(ImageTask).filter(ImageTask.id == task_id).first()
        if task is not None:
            task.status = "failed"
            task.error = str(e)
            task.completed_at = datetime.datetime.now()
            db.commit()