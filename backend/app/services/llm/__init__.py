"""
LLM Provider 包

导出 LLM 相关类型与工厂。Provider 注册为显式机制，而非 import 副作用：
    - 内置 Provider 通过 `LLMFactory.register_builtin_providers()` 注册
    - 应用入口（main.py on_startup）在启动时显式调用
    - 也可依赖 `get_provider` / `list_providers` 首次调用时的自动注册（懒加载）
"""

from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.claude import ClaudeProvider
from backend.app.services.llm.factory import LLMFactory, register_builtin_providers
from backend.app.services.llm.openai import OpenAIProvider

__all__ = [
    "BaseLLM",
    "ClaudeProvider",
    "OpenAIProvider",
    "LLMFactory",
    "register_builtin_providers",
]
