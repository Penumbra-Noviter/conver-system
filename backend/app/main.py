"""
Conver System — FastAPI 应用入口

负责：
    1. 创建 FastAPI 应用实例
    2. 注册所有路由
    3. 初始化数据库
    4. 挂载前端静态文件
"""

from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from backend.app.api.routes import characters, conversations, messages, models, settings

# 注册 LLM Provider（触发 llm/__init__.py 中的注册逻辑）
import backend.app.services.llm  # noqa: F401

app = FastAPI(
    title="Conver System",
    description="本地优先、多模型可切换的角色对话系统",
    version="0.1.0",
)


# ── 注册 API 路由 ──
app.include_router(characters.router)
app.include_router(conversations.router)
app.include_router(messages.router)
app.include_router(models.router)
app.include_router(settings.router)


# ── 挂载前端静态文件 ──
FRONTEND_DIR = Path(__file__).resolve().parent.parent.parent / "frontend"
if FRONTEND_DIR.exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")


# ── 启动事件 ──
@app.on_event("startup")
def on_startup() -> None:
    """应用启动时初始化数据库"""
    from backend.app.database import init_db
    init_db()
