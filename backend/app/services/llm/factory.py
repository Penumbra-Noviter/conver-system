"""
LLM Provider 工厂

负责 Provider 的注册与获取。注册采用显式机制，而非 import 副作用：
    - 内置 Provider 通过 `register_builtin_providers()` 注册
    - 应用入口在启动时显式调用（见 main.py on_startup）
    - `get_provider` / `list_providers` 首次调用前会自动确保内置 Provider 已注册

Provider 清单单一来源：注册从 `model_data.AVAILABLE_MODELS` 派生（新增 Provider
只改模型数据文件）。派生规则：
    - `_CLASS_OVERRIDES` 中的显式声明优先（支持未来独立实现类）
    - 否则 `key == "claude"` → ClaudeProvider、`id == "openai"` → OpenAIProvider
    - 不匹配任何规则（且无显式覆盖）时注册失败并报错，提示进 `_CLASS_OVERRIDES`

扩展新 Provider 的步骤：
    1. 在 services/model_data.py 的 `AVAILABLE_MODELS["providers"]` 中登记 key / id / models
    2. 默认规则匹配（claude / openai 兼容协议）时无需其他改动
    3. 独立协议/实现类：在 services/llm/ 下创建新文件实现 BaseLLM，
       并在 `_CLASS_OVERRIDES` 中登记 key → 实现类
"""

from __future__ import annotations

from backend.app.services.llm.base import BaseLLM
from backend.app.services.model_data import AVAILABLE_MODELS

__all__ = ["LLMFactory", "register_builtin_providers"]

# 显式覆盖 dict：key → 实现类，优先于默认派生规则（支持未来独立实现类）
_CLASS_OVERRIDES: dict[str, type[BaseLLM]] = {}


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
        """从 AVAILABLE_MODELS 派生注册所有内置 Provider

        规则：`_CLASS_OVERRIDES` 显式声明优先；否则 `key == "claude"` → ClaudeProvider、
        `id == "openai"` → OpenAIProvider（OpenAI 兼容第三方）；注册名 = key。
        不匹配任何规则且无显式覆盖的条目直接报错（新增 Provider 必须可解析）。
        """
        from backend.app.services.llm.claude import ClaudeProvider
        from backend.app.services.llm.openai import OpenAIProvider

        for provider in AVAILABLE_MODELS["providers"]:
            key = provider.get("key")
            if not key:
                raise ValueError(f"AVAILABLE_MODELS provider 条目缺少 key 字段: {provider!r}")
            provider_cls = _CLASS_OVERRIDES.get(key)
            if provider_cls is None:
                if key == "claude":
                    provider_cls = ClaudeProvider
                elif provider.get("id") == "openai":
                    provider_cls = OpenAIProvider
                else:
                    raise ValueError(
                        f"Provider '{key}' 无可用实现类：请设置 id='openai' "
                        f"或在 _CLASS_OVERRIDES 中显式声明实现类"
                    )
            cls.register(key, provider_cls)

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
