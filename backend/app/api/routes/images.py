"""
图片出图 / CG 回顾路由（CG-3）

- POST /api/images/tasks — 提交图片生成任务（后台异步执行）
- GET  /api/images/tasks/{task_id} — 轮询任务状态（三态：pending/running/succeeded/failed）
- GET  /api/characters/{character_id}/cg-timeline — 剧情回顾时间线（已解锁 CG + 消息片段）
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.image_task import CgTimelineItem, ImageTaskCreate, ImageTaskResponse
from backend.app.services import conversation as conversation_service
from backend.app.services import gallery as gallery_service
from backend.app.services import setting as setting_service
from backend.app.services.image import tasks as tasks_service

router = APIRouter(tags=["图片"])


async def _background_run(task_id: int) -> None:
    """后台执行图片任务（独立 SessionLocal；核心逻辑在 tasks.run_image_task）"""
    from backend.app.database import SessionLocal

    db = SessionLocal()
    try:
        await tasks_service.run_image_task(task_id, db)
    finally:
        db.close()


@router.post(
    "/api/images/tasks",
    response_model=ImageTaskResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_image_task(
    body: ImageTaskCreate,
    db: Session = Depends(get_db),
) -> ImageTaskResponse:
    """提交图片生成任务（对话内出图：prompt → 后台生成 → 完成挂 CG）

    出图锚 message_id 可选（缺省 None → 会话级 CG，不挂具体消息）；后台
    异步执行（失败落 failed 态，不破坏对话）。character_id 由会话派生；
    provider 从 settings（image_provider）解析（MD-3），未配置生图后端 → 400。
    """
    if not tasks_service.image_generation_available(db):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="未配置图片生成后端，请先在设置中配置生图服务",
        )
    conv = conversation_service.require_conversation(db, body.conversation_id)
    task = tasks_service.create_image_task(
        db,
        conversation_id=body.conversation_id,
        character_id=conv.character_id,
        prompt=body.prompt,
        negative_prompt=body.negative_prompt,
        width=body.width,
        height=body.height,
        steps=body.steps,
        provider=setting_service.image_provider(db),
        message_id=body.message_id,
    )
    asyncio.create_task(_background_run(task.id))
    return ImageTaskResponse.model_validate(task)


@router.get("/api/images/available")
def image_available(db: Session = Depends(get_db)) -> dict[str, bool]:
    """生图能力门控（MD-3）：是否配置了可用的生图后端（前端据此控制出图按钮）"""
    return {"available": tasks_service.image_generation_available(db)}


@router.get("/api/images/tasks/{task_id}", response_model=ImageTaskResponse)
def get_image_task(task_id: int, db: Session = Depends(get_db)) -> ImageTaskResponse:
    """轮询任务状态（生成中 pending/running / 成功 succeeded / 失败 failed）"""
    return ImageTaskResponse.model_validate(tasks_service.get_image_task(db, task_id))


@router.get(
    "/api/characters/{character_id}/cg-timeline",
    response_model=list[CgTimelineItem],
)
def cg_timeline(character_id: int, db: Session = Depends(get_db)) -> list[CgTimelineItem]:
    """剧情回顾时间线（已解锁 CG + 对应消息片段，消息 created_at 升序）"""
    from backend.app.services import character as character_service

    character_service.require_character(db, character_id)
    return [CgTimelineItem(**item) for item in gallery_service.cg_timeline(db, character_id)]