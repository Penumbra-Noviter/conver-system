"""
设置管理 API 路由

运行时可读写 DB settings 表中的配置项。
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.models.setting import Setting
from backend.app.schemas.settings import ConnectionTestRequest, ConnectionTestResponse
from backend.app.services.llm.errors import LLMError
from backend.app.services.llm.factory import LLMFactory

router = APIRouter(prefix="/api/settings", tags=["设置管理"])

# 允许前端读写的配置键白名单
ALLOWED_KEYS = {
    "claude_api_key",
    "openai_api_key",
    "openai_base_url",
    "default_provider",
    "default_model",
    "sliding_window_rounds",
    "theme_mode",
    "user_name",
}


def _get_all_settings(db: Session) -> dict[str, str]:
    """读取所有设置"""
    rows = db.query(Setting).filter(Setting.key.in_(ALLOWED_KEYS)).all()
    return {row.key: row.value for row in rows}


def _get_setting(db: Session, key: str) -> str:
    """读取单个设置值，不存在返回空串"""
    row = db.query(Setting).filter(Setting.key == key).first()
    return row.value if row else ""


def _set_settings(db: Session, data: dict[str, str]) -> None:
    """批量写入设置（存在则更新，不存在则创建）"""
    for key, value in data.items():
        if key not in ALLOWED_KEYS:
            continue
        existing = db.query(Setting).filter(Setting.key == key).first()
        if existing:
            existing.value = str(value)
        else:
            db.add(Setting(key=key, value=str(value)))
    db.commit()


@router.get("")
def get_settings(db: Session = Depends(get_db)) -> dict[str, str]:
    """获取所有设置"""
    return _get_all_settings(db)


@router.put("")
def update_settings(data: dict[str, Any], db: Session = Depends(get_db)) -> dict[str, str]:
    """更新设置（只更新白名单内的键）"""
    _set_settings(db, data)
    return _get_all_settings(db)


@router.post("/test-connection", response_model=ConnectionTestResponse)
async def test_connection(
    data: ConnectionTestRequest,
    db: Session = Depends(get_db),
) -> ConnectionTestResponse:
    """测试指定 Provider 的 API Key 连接是否可用

    用请求携带的 Key（留空则回退到已保存的 Key）发起一次最小请求；
    失败返回 400 及用户可读的原因（Key 无效 / 网络不可达等）。
    """
    provider = data.provider
    if provider not in LLMFactory.list_providers():
        raise HTTPException(status_code=400, detail=f"不支持的 Provider: {provider}")

    api_key = data.api_key or _get_setting(db, f"{provider}_api_key")
    if not api_key:
        raise HTTPException(status_code=400, detail="未提供 API Key，请在设置中填写后再测试")

    try:
        llm = LLMFactory.get_provider(provider, api_key, data.base_url or None)
        await llm.test_connection(model=data.model)
    except LLMError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"连接失败: {e}")

    return ConnectionTestResponse(provider=provider)
