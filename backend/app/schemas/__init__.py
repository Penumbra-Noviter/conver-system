"""
Schema 层包 — 模块清单（manifest，不 re-export）

Pydantic 请求 / 响应模型以独立模块文件存在（如 character / conversation），
调用方按需显式导入：`from backend.app.schemas.character import CharacterCreate`。

本 `__init__.py` 仅维护 `__all__` 元数据清单，供工具与读者发现实际模块；
刻意不 re-export，避免 import 成本与模块间隐式耦合。

领域术语见仓库根 `CONTEXT.md` 术语表。
"""

__all__ = [
    "character",
    "conversation",
    "message",
    "settings",
]
