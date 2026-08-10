"""
服务层包 — 深模块清单（manifest，不 re-export）

各业务能力以独立模块文件存在（如 chat / character_card / conversation），
调用方按需显式导入：`from backend.app.services import chat as chat_service`。

本 `__init__.py` 仅维护 `__all__` 元数据清单，供工具与读者发现实际模块；
刻意不 re-export，避免 import 成本与模块间隐式耦合。

领域术语（聊天回合 / 运行时设置 / 角色 / 对话 / 消息 / Provider 等）
见仓库根 `CONTEXT.md` 术语表；深模块形态参照 services/chat.py 的说明。
"""

__all__ = [
    "character",
    "character_card",
    "chat",
    "conversation",
    "conversation_export",
    "document_parser",
    "exceptions",
    "llm",
    "message",
    "model_data",
    "setting",
]
