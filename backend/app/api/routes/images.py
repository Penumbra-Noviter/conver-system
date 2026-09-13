"""
图片出图 / CG 回顾路由（CG-3 / T2）

- POST /api/images/tasks — 提交图片生成任务（后台异步执行）
- GET  /api/images/tasks/{task_id} — 轮询任务状态（三态：pending/running/succeeded/failed）
- GET  /api/characters/{character_id}/cg-timeline — 剧情回顾时间线（已解锁 CG + 消息片段）
- POST /api/characters/{character_id}/cg — 手工录入 CG（T2：初始恒锁定）
- POST /api/cg/{cg_id}/unlock — 解锁 CG（T2：幂等）
- GET  /api/characters/{character_id}/cg — 全量 CG 列表（T2：id 降序，含未解锁）

路由零 ORM：CG 三件套全部委托 gallery service（add_cg / unlock_cg / list_cg），
领域异常由应用级 DomainError handler（api/errors.py）统一映射 HTTP。
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.image_task import (
    CgImageCreate,
    CgImageResponse,
    CgTimelineItem,
    ImageTaskCreate,
    ImageTaskResponse,
)
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


@router.post(
    "/api/characters/{character_id}/cg",
    response_model=CgImageResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_cg(
    character_id: int, body: CgImageCreate, db: Session = Depends(get_db)
) -> CgImageResponse:
    """手工录入 CG（T2；画廊「录入 CG」表单数据通道）

    初始默认锁定：不收 unlocked 字段，服务层 add_cg 默认恒 unlocked=False；
    同作品同 url 幂等去重（既有行直接返回，add_cg 语义不破坏）。
    角色不存在 → 404（CharacterNotFoundError 经统一 handler 映射）。
    """
    cg = gallery_service.add_cg(
        db,
        character_id,
        body.url,
        group_name=body.group_name,
        unlock_hint=body.unlock_hint,
        weight=body.weight,
        is_special=body.is_special,
    )
    return CgImageResponse.model_validate(cg)


@router.post("/api/cg/{cg_id}/unlock", response_model=CgImageResponse)
def unlock_cg(cg_id: int, db: Session = Depends(get_db)) -> CgImageResponse:
    """解锁 CG（T2；画廊锁定态点击数据通道，幂等复用 unlock_cg）

    幂等：已解锁再调返回同一行、无副作用。cg 不存在 → 404
    （CgImageNotFoundError 经统一 handler 映射）。
    """
    return CgImageResponse.model_validate(gallery_service.unlock_cg(db, cg_id))


@router.get(
    "/api/characters/{character_id}/cg",
    response_model=list[CgImageResponse],
)
def list_cg(
    character_id: int,
    group_name: str | None = None,
    unlocked_only: bool = False,
    db: Session = Depends(get_db),
) -> list[CgImageResponse]:
    """角色全量 CG 列表（T2；画廊网格数据通道，id 降序全量含未解锁）

    默认全量（不传过滤 → list_cg 无过滤）；可选 group_name 精确过滤 /
    unlocked_only 仅已解锁（list_cg 既有过滤语义）。角色不存在 → 404
    （require_character → 统一 handler）。
    """
    from backend.app.services import character as character_service

    character_service.require_character(db, character_id)
    rows = gallery_service.list_cg(
        db, character_id, group_name=group_name, unlocked_only=unlocked_only
    )
    return [CgImageResponse.model_validate(cg) for cg in rows]
