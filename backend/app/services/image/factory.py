"""
Image Provider 工厂（CG-1，与 LLMFactory 同构）

注册与获取。内置 Provider 经 `register_builtin_providers()` 注册（派生自
model_data.AVAILABLE_IMAGE_PROVIDERS）；`get_provider` / `list_providers` 首次
调用前自动确保内置已注册（懒加载兜底）。

派生规则（对齐 LLMFactory）：
    - `_CLASS_OVERRIDES` 显式声明优先（支持未来独立实现类）
    - 否则 `image_provider_id(key) == "http"` → HttpImageGen、
      `== "local"` → LocalImageGen
    - 不匹配任何规则（且无显式覆盖）时注册失败并报错，提示进 `_CLASS_OVERRIDES`
"""

from __future__ import annotations

from backend.app.services.exceptions import ProviderNotSupportedError
from backend.app.services.image.base import BaseImageGen
from backend.app.services.image.model_data import (
    IMAGE_PROVIDER_KEYS,
    image_provider_id,
)

__all__ = ["ImageFactory", "register_builtin_providers"]

# 显式覆盖 dict：key → 实现类，优先于默认派生规则（支持未来独立实现类）
_CLASS_OVERRIDES: dict[str, type[BaseImageGen]] = {}


class ImageFactory:
    """图片 Provider 注册与获取"""

    _providers: dict[str, type[BaseImageGen]] = {}
    _builtins_loaded: bool = False

    @classmethod
    def register(cls, name: str, provider_cls: type[BaseImageGen]) -> None:
        """注册图片 Provider"""
        cls._providers[name] = provider_cls

    @classmethod
    def register_builtin_providers(cls) -> None:
        """从 AVAILABLE_IMAGE_PROVIDERS 派生注册所有内置图片 Provider

        规则：`_CLASS_OVERRIDES` 显式声明优先；否则按 `image_provider_id`：
        http → HttpImageGen、local → LocalImageGen。注册名 = key。
        不匹配任何规则且无显式覆盖的条目直接报错（新增 Provider 必须可解析）。
        """
        from backend.app.services.image.http_backend import HttpImageGen
        from backend.app.services.image.local_backend import LocalImageGen

        for key in IMAGE_PROVIDER_KEYS:
            provider_cls = _CLASS_OVERRIDES.get(key)
            if provider_cls is None:
                protocol_id = image_provider_id(key)
                if protocol_id == "http":
                    provider_cls = HttpImageGen
                elif protocol_id == "local":
                    provider_cls = LocalImageGen
                else:
                    raise ValueError(
                        f"图片 Provider '{key}' 无可用实现类：请设置 id='http'/'local' "
                        f"或在 _CLASS_OVERRIDES 中显式声明实现类"
                    )
            cls.register(key, provider_cls)

    @classmethod
    def _ensure_builtins(cls) -> None:
        """确保内置图片 Provider 已注册（懒加载，仅注册一次）"""
        if not cls._builtins_loaded:
            cls.register_builtin_providers()
            cls._builtins_loaded = True

    @classmethod
    def get_provider(
        cls,
        name: str,
        *,
        api_key: str | None = None,
        base_url: str | None = None,
    ) -> BaseImageGen:
        """获取图片 Provider 实例

        Args:
            name: Provider 标识（a1111 / custom-http / local）
            api_key: API Key（requires_key Provider 必需；HttpImageGen 有值时
                附带 Authorization 头）
            base_url: 端点地址（HTTP 类 Provider 必需，构造即校验）

        Returns:
            Provider 实例

        Raises:
            ProviderNotSupportedError: 未注册的 Provider 名（领域异常，非 ValueError）
        """
        cls._ensure_builtins()
        if name not in cls._providers:
            raise ProviderNotSupportedError(f"不支持的图片 Provider: {name}")
        return cls._providers[name](base_url=base_url, api_key=api_key)

    @classmethod
    def list_providers(cls) -> list[str]:
        """列出所有已注册的图片 Provider"""
        cls._ensure_builtins()
        return list(cls._providers.keys())


# 模块级别名：便于从包层直接导入并显式注册内置 Provider
register_builtin_providers = ImageFactory.register_builtin_providers