"""
模拟器导入 API 路由（工单 03）

POST /api/simulators/import — 单文件 HTML 游戏导入（multipart 字段名 `file`）。

接口契约（spec T-02 决策 4，与工单 04 前端共用锚点，定版）：
    成功 200：{ ok: true, game: { id, file, name, type, config? }, renamed, warnings }
    校验失败 400（非 .html / 超 5MB / 空文件）；重复 409（SHA-256 命中，
    detail 含「已存在」）；缺 file 字段 422（FastAPI 校验）
    warnings 键集：eval / document.cookie / cross-origin-fetch
    （常量单源 simulator_store.SUSPICIOUS_PATTERNS，前端映射中文文案）

分层约定：本路由仅做 HTTP 映射（状态码 + 响应形状）；校验 / 文件读写 /
探测 / manifest 注册全部委托 services/simulator_store 导入族（本文件无
open/shutil 等文件系统业务调用，grep 口径可验）。数据目录在请求期解析
（不缓存于 import 期，测试可 monkeypatch CONVER_DATA_DIR 环境变量）。
"""

from __future__ import annotations

from fastapi import APIRouter, File, HTTPException, UploadFile

from backend.app.services import data_dir as data_dir_service
from backend.app.services import simulator_store

__all__ = ["router"]

router = APIRouter(prefix="/api/simulators", tags=["模拟器导入"])


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
