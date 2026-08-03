"""
可用模型 API 路由
"""

from __future__ import annotations

from fastapi import APIRouter

router = APIRouter(prefix="/api/models", tags=["模型管理"])

# 硬编码的可用模型列表（后续可扩展为动态查询）
AVAILABLE_MODELS = {
    "providers": [
        {
            "id": "claude",
            "name": "Claude (Anthropic)",
            "models": [
                "claude-sonnet-4-20250514",
                "claude-opus-4-8-20250514",
                "claude-haiku-4-5-20251001",
            ],
        },
        {
            "id": "openai",
            "name": "OpenAI / 兼容 API",
            "models": [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4-turbo",
            ],
        },
    ]
}


@router.get("")
def list_models() -> dict[str, list[dict]]:
    """获取可用模型列表"""
    return AVAILABLE_MODELS
