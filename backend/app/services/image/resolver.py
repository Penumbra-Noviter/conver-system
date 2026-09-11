"""
图片凭据解析 / 实例化收口（CG-1，与 resolve_llm 同构）

provider 校验（未登记 → ProviderNotSupportedError）→ requires_key 且 Key 缺失
→ ImageAuthError（明确报错，不影响对话主流程——CG-3 任务失败只影响出图）→
ImageFactory 实例化。显式 api_key / base_url 优先（CG-3 设置接线前显式传入；
本地优先后端无需 Key 也能走通）。

协议表面（__all__）：resolve_image。
"""

from __future__ import annotations

from backend.app.services.exceptions import ProviderNotSupportedError
from backend.app.services.image.base import BaseImageGen
from backend.app.services.image.errors import ImageAuthError
from backend.app.services.image.factory import ImageFactory
from backend.app.services.image import model_data

__all__ = ["resolve_image"]


def resolve_image(
    provider: str,
    *,
    api_key: str | None = None,
    base_url: str | None = None,
) -> tuple[str, BaseImageGen]:
    """图片 Provider 校验 + 缺 Key 检查 + 实例化（收口深函数）

    Args:
        provider: 图片 Provider 标识（a1111 / custom-http / local；须已登记）
        api_key: API Key（requires_key Provider 且缺失 → ImageAuthError；
            HttpImageGen 有值时附带 Authorization 头）
        base_url: 端点地址（HTTP 类 Provider 必需，构造即校验）

    Returns:
        (provider, backend) 二元组

    Raises:
        ProviderNotSupportedError: 未登记/未注册的图片 Provider
        ImageAuthError: requires_key Provider 且 Key 缺失
        ImageConnectionError: HTTP 类 Provider 未配置 base_url（构造时）
    """
    if provider not in model_data.IMAGE_PROVIDER_KEYS:
        raise ProviderNotSupportedError(f"不支持的图片 Provider: {provider}")
    if model_data.image_provider_requires_key(provider) and not api_key:
        raise ImageAuthError(f"未配置 {provider} API Key，请在设置中填写")
    backend = ImageFactory.get_provider(
        provider, api_key=api_key, base_url=base_url
    )
    return provider, backend