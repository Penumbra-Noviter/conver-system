"""
模拟器 API 路由

POST /api/simulators/import   — 单文件 HTML 游戏导入（multipart 字段名 `file`）
POST /api/simulators/generate — 从文本描述 AI 生成游戏

导入接口契约（spec T-02 决策 4，与工单 04 前端共用锚点，定版）：
    成功 200：{ ok: true, game: { id, file, name, type, config? }, renamed, warnings }
    校验失败 400（非 .html / 超 5MB / 空文件）；重复 409（SHA-256 命中，
    detail 含「已存在」）；缺 file 字段 422（FastAPI 校验）
    warnings 键集：eval / document.cookie / cross-origin-fetch
    （常量单源 simulator_store.SUSPICIOUS_PATTERNS，前端映射中文文案）

生成接口契约：
    请求：{ "description": "世界观描述", "title": "游戏标题（可选）" }
    成功 200：{ ok: true, game: { id, file, name, type, source: "generated" }, retries }
    校验失败 422：{ ok: false, errors: [{field, message}], suggestion, retries }
    重复 409（SHA-256 与现存文件重复，detail 含「已存在」）
    LLM 错误 401/429/504/502：走 LLMError 统一异常处理

分层约定：本路由仅做 HTTP 映射（状态码 + 响应形状）；校验 / 文件读写 /
探测 / manifest 注册全部委托 services/simulator_store 导入族；生成逻辑
委托 services/game_generator。数据目录在请求期解析（不缓存于 import 期，
测试可 monkeypatch CONVER_DATA_DIR 环境变量）。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.services import data_dir as data_dir_service
from backend.app.services import simulator_store
from backend.app.services.game_generator import (
    GenerateResult,
    generate_game,
)

__all__ = ["router"]

router = APIRouter(prefix="/api/simulators", tags=["模拟器导入"])


class GenerateRequest(BaseModel):
    """AI 生成游戏请求"""
    description: str = Field(..., min_length=1, max_length=10000,
                             description="世界观描述文本（1-10000 字符）")
    title: str | None = Field(default=None, max_length=100,
                               description="游戏标题（可选，用于生成文件名）")


@router.post("/import")
async def import_simulator(file: UploadFile = File(...)) -> dict:
    """导入单文件 HTML 模拟器游戏（multipart 字段名 file；返回契约见模块 docstring）。

    读取守卫：最多读 5MB+1 字节，超限即拒绝（不整读超大文件，防内存膨胀）。
    领域异常（校验失败 / 重复）本地映射 400/409 及明确文案；落盘失败
    （OSError，如数据目录不可写）保持 500 语义不静默吞掉。
    """
    content = await file.read(simulator_store.MAX_IMPORT_BYTES + 1)
    try:
        result = simulator_store.import_game(
            data_dir_service.simulators_dir(), file.filename or "", content
        )
    except simulator_store.SimulatorImportError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except simulator_store.SimulatorDuplicateError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "game": result.game, "renamed": result.renamed, "warnings": result.warnings}


@router.post("/generate")
async def generate_simulator(body: GenerateRequest, db: Session = Depends(get_db)) -> dict:
    """AI 游戏生成：从用户提供的世界观描述生成可运行的 HTML 模拟器游戏。

    流程：LLM 填充种子模板 → 校验闸门（6 项检查）→ 通过后落盘并注册 manifest。
    校验失败自动重试（最多 3 次），返回结构化错误与修正建议。
    """
    try:
        result: GenerateResult = await generate_game(
            db=db,
            description=body.description,
            title=body.title,
        )
    except simulator_store.SimulatorDuplicateError as exc:
        # SHA-256 内容与现存文件重复 → 409（与导入路由同语义，detail 含「已存在」）
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    if result.ok:
        return {"ok": True, "game": result.game, "retries": result.retries}

    # 校验失败 — 返回结构化错误（422 语义：校验不通过）
    raise HTTPException(
        status_code=422,
        detail={
            "ok": False,
            "errors": [{"field": e.field, "message": e.message} for e in (result.errors or [])],
            "suggestion": result.suggestion,
            "retries": result.retries,
        },
    )
