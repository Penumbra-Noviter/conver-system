"""
FastAPI 依赖注入

集中管理依赖项，避免路由模块直接导入数据库层。
"""

from __future__ import annotations

from backend.app.database import get_db

__all__ = ["get_db"]
