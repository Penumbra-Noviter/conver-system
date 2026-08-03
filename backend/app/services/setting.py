"""
运行时设置读写 — 深模块

协议表面（__all__）：get_value / get_int / get_all / set_many / api_key /
user_name / sliding_window_rounds / default_provider / default_model。

将「运行时设置」从三处手写点收拢于此：
    - api/routes/chat.py（_get_api_key / _get_sliding_window_rounds / _get_user_name）
    - api/routes/settings.py（_get_all_settings / _get_setting / _set_settings + ALLOWED_KEYS）
    - services/conversation.py（_get_setting_value）

默认回退链（DB settings → config 默认值）与整型容错（防非数字 500）也收口在此。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from backend.app.config import settings
from backend.app.models.setting import Setting

__all__ = [
    "ALLOWED_KEYS",
    "get_value",
    "get_int",
    "get_all",
    "set_many",
    "api_key",
    "user_name",
    "sliding_window_rounds",
    "default_provider",
    "default_model",
]

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


def get_value(db: Session, key: str, default: str = "") -> str:
    """读取单个设置值，不存在或值为空返回 default"""
    row = db.query(Setting).filter(Setting.key == key).first()
    return row.value if row and row.value else default


def get_int(db: Session, key: str, default: int) -> int:
    """读取整型设置，缺失或非数字回退 default（防 500）"""
    value = get_value(db, key)
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def get_all(db: Session) -> dict[str, str]:
    """读取白名单内所有设置"""
    rows = db.query(Setting).filter(Setting.key.in_(ALLOWED_KEYS)).all()
    return {row.key: row.value for row in rows}


def set_many(db: Session, data: dict[str, str]) -> None:
    """批量写入设置（白名单外键忽略；存在则更新，不存在则创建）"""
    for key, value in data.items():
        if key not in ALLOWED_KEYS:
            continue
        existing = db.query(Setting).filter(Setting.key == key).first()
        if existing:
            existing.value = str(value)
        else:
            db.add(Setting(key=key, value=str(value)))
    db.commit()


def api_key(db: Session, provider: str) -> str:
    """读取指定 Provider 的 API Key，未配置返回空串"""
    return get_value(db, f"{provider}_api_key")


def user_name(db: Session) -> str:
    """读取用户昵称，默认 'User'"""
    return get_value(db, "user_name") or "User"


def sliding_window_rounds(db: Session) -> int:
    """读取滑动窗口轮数配置，默认 30"""
    return get_int(db, "sliding_window_rounds", default=30)


def default_provider(db: Session) -> str:
    """返回默认 Provider（DB settings → config 默认值回退链）"""
    return get_value(db, "default_provider") or settings.DEFAULT_PROVIDER


def default_model(db: Session) -> str:
    """返回默认模型（DB settings → config 默认值回退链）"""
    return get_value(db, "default_model") or settings.DEFAULT_MODEL
