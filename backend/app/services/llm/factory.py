"""
LLM Provider 工厂

负责 Provider 的注册与获取。扩展新 Provider 的步骤：
    1. 在 services/llm/ 下创建新文件，实现 BaseLLM
    2. 在 __init__.py 中注册
"""

from __future__ import annotations

from backend.app.services.llm.base import BaseLLM


class LLMFactory:
    """Provider 注册与获取"""

    _providers: dict[str, type[BaseLLM]] = {}

    @classmethod
    def register(cls, name: str, provider_cls: type[BaseLLM]) -> None:
        """注册 Provider"""
        cls._providers[name] = provider_cls

    @classmethod
    def get_provider(cls, name: str, api_key: str, base_url: str | None = None) -> BaseLLM:
        """获取 Provider 实例"""
        if name not in cls._providers:
            raise ValueError(f"不支持的 Provider: {name}")
        return cls._providers[name](api_key=api_key, base_url=base_url)

    @classmethod
    def list_providers(cls) -> list[str]:
        """列出所有已注册的 Provider"""
        return list(cls._providers.keys())
