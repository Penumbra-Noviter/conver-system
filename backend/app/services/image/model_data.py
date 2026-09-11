"""
Image Provider 清单单一来源（CG-1，对齐 model_data.py AVAILABLE_MODELS 模式）

AVAILABLE_IMAGE_PROVIDERS = 图片 Provider 登记表（唯一声明源）；factory 派生注册
与 resolver 校验均由此处派生（新增 Provider 只改本文件，必要时在
factory._CLASS_OVERRIDES 声明实现类 / 实现类自身）。

派生元数据（单一实现对镜像 LLM 侧 provider_registry 的角色）：
    - image_provider_id(key)：实现类派生的协议 id（http / local）
    - image_provider_requires_key(key)：该 Provider 是否需要 API Key
"""

from __future__ import annotations

__all__ = [
    "AVAILABLE_IMAGE_PROVIDERS",
    "IMAGE_PROVIDER_KEYS",
    "image_provider_id",
    "image_provider_requires_key",
]

AVAILABLE_IMAGE_PROVIDERS = {
    "providers": [
        {
            "key": "a1111",
            "id": "http",
            "name": "A1111 兼容（Stable Diffusion WebUI）",
            "requires_key": False,
        },
        {
            "key": "custom-http",
            "id": "http",
            "name": "自定义 HTTP 端点",
            "requires_key": False,
        },
        {
            "key": "local",
            "id": "local",
            "name": "本地文件（占位输出，零后端）",
            "requires_key": False,
        },
    ],
}


def _provider_entries() -> list[dict]:
    """登记表条目列表（防御：结构被破坏时显式失败而非静默）"""
    entries = AVAILABLE_IMAGE_PROVIDERS.get("providers")
    if not isinstance(entries, list):
        raise ValueError("AVAILABLE_IMAGE_PROVIDERS 结构无效：providers 应为列表")
    return entries


IMAGE_PROVIDER_KEYS: list[str] = [p["key"] for p in _provider_entries()]


def image_provider_id(key: str) -> str:
    """Provider 实现类派生的协议 id（http / local）

    Args:
        key: Provider 标识（如 a1111 / custom-http / local）

    Returns:
        协议 id——factory 据此选择实现类（http → HttpImageGen，local → LocalImageGen）

    Raises:
        KeyError: 未登记的 Provider 标识
    """
    for entry in _provider_entries():
        if entry["key"] == key:
            return entry["id"]
    raise KeyError(f"未登记的图片 Provider: {key}")


def image_provider_requires_key(key: str) -> bool:
    """该 Provider 是否需要 API Key（缺 Key 时 resolver 抛 ImageAuthError）

    Args:
        key: Provider 标识

    Returns:
        True 需要 Key；False（本地优先后端默认）无需 Key
    """
    for entry in _provider_entries():
        if entry["key"] == key:
            return bool(entry.get("requires_key", False))
    raise KeyError(f"未登记的图片 Provider: {key}")