"""
Conver System — FastAPI 应用入口

负责：
    1. 创建 FastAPI 应用实例
    2. 注册所有路由
    3. 初始化数据库
    4. 挂载前端静态文件
"""

from __future__ import annotations

import sys
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from backend.app.api.errors import domain_error_handler, llm_error_handler
from backend.app.api.routes import characters, chat, conversations, messages, models, settings
from backend.app.services.exceptions import DomainError
from backend.app.services.llm import LLMFactory
from backend.app.services.llm.errors import LLMError

app = FastAPI(
    title="Conver System",
    description="本地优先、多模型可切换的角色对话系统",
    version="0.1.0",
)


# ── 注册统一错误 handler（领域异常族 + LLM 异常族，Starlette 按 MRO 匹配子类）──
app.add_exception_handler(DomainError, domain_error_handler)
app.add_exception_handler(LLMError, llm_error_handler)


# ── 注册 API 路由 ──
app.include_router(characters.router)
app.include_router(chat.router)
app.include_router(conversations.router)
app.include_router(messages.router)
app.include_router(models.router)
app.include_router(settings.router)


# ── 挂载前端静态文件 ──
# 注意：挂载在 / 路径上，会捕获所有未被 API 路由匹配的请求。
# 契约：所有 API 路由必须使用 /api 前缀，且在此行之前注册。
# 若添加非 /api 前缀的新路由，必须注册在此行之前，否则将被静态文件捕获。
def _frontend_dir() -> Path:
    """前端静态目录定位：frozen（PyInstaller）态指向 _MEIPASS/frontend，源码态指向仓库 frontend。

    打包态不随包分发前端（webview 走 http://127.0.0.1，后端无需挂载），
    _MEIPASS/frontend 不存在时 exists() 守卫安全跳过，保证打包态不崩溃；
    若未来需要随包分发，在 spec 的 datas 追加即可自动挂载。
    """
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent)) / "frontend"
    return Path(__file__).resolve().parent.parent.parent / "frontend"


FRONTEND_DIR = _frontend_dir()
if FRONTEND_DIR.exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")


# ── 启动事件 ──
@app.on_event("startup")
def on_startup() -> None:
    """应用启动时注册内置 LLM Provider 并初始化数据库"""
    LLMFactory.register_builtin_providers()
    from backend.app.database import init_db
    init_db()
