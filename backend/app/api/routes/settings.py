"""
设置管理 API 路由

运行时可读写 DB settings 表中的配置项。
读写逻辑（白名单 / 回退链 / 整型容错）收拢在 services/setting.py。
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.settings import ConnectionTestRequest, ConnectionTestResponse
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import ProviderNotSupportedError
from backend.app.services.llm.errors import LLMError
from backend.app.services.llm.factory import LLMFactory

router = APIRouter(prefix="/api/settings", tags=["设置管理"])


@router.get("")
def get_settings(db: Session = Depends(get_db)) -> dict[str, str]:
    """获取所有设置"""
    return setting_service.get_all(db)


@router.put("")
def update_settings(data: dict[str, Any], db: Session = Depends(get_db)) -> dict[str, str]:
    """更新设置（只更新白名单内的键）"""
    setting_service.set_many(db, data)
    return setting_service.get_all(db)


@router.post("/test-connection", response_model=ConnectionTestResponse)
async def test_connection(
    data: ConnectionTestRequest,
    db: Session = Depends(get_db),
) -> ConnectionTestResponse:
    """测试指定 Provider 的 API Key 连接是否可用

    未显式传 Key / URL / 模型时全部回退通用解析：
        - Key / URL → setting_service（provider 特定 → 同协议槽位 → 跨协议兜底）
        - 模型 → 当前默认模型（用户配置的），避免用硬编码模型导致误报
    失败返回 400 及用户可读的原因（Key 无效 / 网络不可达 / 模型无权限等）。
    领域族（provider 校验）走统一 exception handler 转 400（D-B3-1：
    test-connection 不走 LLM 族统一映射，LLMError/无 Key 保持局部 400 语义）。
    """
    provider = data.provider
    if provider not in LLMFactory.list_providers():
        raise ProviderNotSupportedError(f"不支持的 Provider: {provider}")

    api_key = data.api_key or setting_service.api_key(db, provider)
    if not api_key:
        raise HTTPException(status_code=400, detail="未提供 API Key，请在设置中填写后再测试")

    base_url = data.base_url or setting_service.base_url(db, provider) or None
    model = data.model or setting_service.default_model(db) or None

    try:
        llm = LLMFactory.get_provider(provider, api_key, base_url)
        await llm.test_connection(model=model)
    except LLMError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"连接失败: {e}")

    return ConnectionTestResponse(provider=provider)
