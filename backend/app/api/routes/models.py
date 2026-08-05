"""
可用模型 API 路由
"""

from __future__ import annotations

from fastapi import APIRouter

from backend.app.services.model_data import AVAILABLE_MODELS

router = APIRouter(prefix="/api/models", tags=["模型管理"])


@router.get("")
def list_models() -> dict[str, list[dict]]:
    """获取可用模型列表"""
    return AVAILABLE_MODELS
