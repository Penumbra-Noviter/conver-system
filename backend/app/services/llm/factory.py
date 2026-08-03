"""
LLM Provider 工厂

负责 Provider 的注册与获取。注册采用显式机制，而非 import 副作用：
    - 内置 Provider 通过 `register_builtin_providers()` 注册
    - 应用入口在启动时显式调用（见 main.py on_startup）
    - `get_provider` / `list_providers` 首次调用前会自动确保内置 Provider 已注册

扩展新 Provider 的步骤：
    1. 在 services/llm/ 下创建新文件，实现 BaseLLM
    2. 在 `register_builtin_providers()` 中导入并注册
"""

from __future__ import annotations

from backend.app.services.llm.base import BaseLLM


class LLMFactory:
    """Provider 注册与获取"""

    _providers: dict[str, type[BaseLLM]] = {}
    _builtins_loaded: bool = False

    @classmethod
    def register(cls, name: str, provider_cls: type[BaseLLM]) -> None:
        """注册 Provider"""
        cls._providers[name] = provider_cls

    @classmethod
    def register_builtin_providers(cls) -> None:
        """注册所有内置 Provider（claude / openai）"""
        from backend.app.services.llm.claude import ClaudeProvider
        from backend.app.services.llm.openai import OpenAIProvider

        cls.register("claude", ClaudeProvider)
        cls.register("openai", OpenAIProvider)

    @classmethod
    def _ensure_builtins(cls) -> None:
        """确保内置 Provider 已注册（懒加载，仅注册一次）"""
        if not cls._builtins_loaded:
            cls.register_builtin_providers()
            cls._builtins_loaded = True

    @classmethod
    def get_provider(cls, name: str, api_key: str, base_url: str | None = None) -> BaseLLM:
        """获取 Provider 实例"""
        cls._ensure_builtins()
        if name not in cls._providers:
            raise ValueError(f"不支持的 Provider: {name}")
        return cls._providers[name](api_key=api_key, base_url=base_url)

    @classmethod
    def list_providers(cls) -> list[str]:
        """列出所有已注册的 Provider"""
        cls._ensure_builtins()
        return list(cls._providers.keys())


# 模块级别名：便于从包层直接导入并显式注册内置 Provider
register_builtin_providers = LLMFactory.register_builtin_providers
