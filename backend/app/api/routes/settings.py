"""
设置管理 API 路由

运行时可读写 DB settings 表中的配置项。
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from backend.app.api.deps import get_db
from backend.app.models.setting import Setting

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
def get_settings(db: Session = Depends(get_db)):
    """获取所有设置"""
    return _get_all_settings(db)


@router.put("")
def update_settings(data: dict[str, Any], db: Session = Depends(get_db)):
    """更新设置（只更新白名单内的键）"""
    _set_settings(db, data)
    return _get_all_settings(db)
