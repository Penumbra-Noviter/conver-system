"""
Provider 派生元数据 — 单一来源深模块

Provider 清单的派生视图（协议映射 / 协议族模型集 / key 顺序）在此收敛为
模块级常量与纯函数，各消费方（llm/factory 注册、setting 凭证解析）对标导入，
消除对 AVAILABLE_MODELS["providers"] 的多处独立遍历。

数据源头仍为 `services/model_data.py` 的 `AVAILABLE_MODELS`（原始声明，新增
Provider 只改该文件的 providers 条目，本模块派生视图自动跟随——由
`tests/test_provider_registry.py` 契约锁防漂移比对锁定）。

协议语义（TD-66）：多个第三方 provider 共享同一协议（如 DeepSeek/Qwen 使用
OpenAI 兼容 API）。API_PROVIDER_MAP 仅收录 key != id 的协议共享者（claude /
openai 自身走 resolve_api_provider 回退）；OPENAI_PROTOCOL_MODELS 为协议
id == "openai" 的全部 provider 的 models 并集（含 openai 自身），credentials()
的 model 门控据此判定 .env 回退值是否可用于 openai 协议。
"""

from __future__ import annotations

from backend.app.services.model_data import AVAILABLE_MODELS

__all__ = [
    "PROVIDER_KEYS",
    "API_PROVIDER_MAP",
    "OPENAI_PROTOCOL_MODELS",
    "resolve_api_provider",
]

def _require_key(provider: dict) -> str:
    """校验 provider 条目含非空 key 字段，返回该 key（缺则显式 ValueError）"""
    key = provider.get("key")
    if not key:
        raise ValueError(f"AVAILABLE_MODELS provider 条目缺少 key 字段: {provider!r}")
    return key


def _require_id(provider: dict) -> str:
    """校验 provider 条目含非空 id 字段，返回该 id（缺则显式 ValueError）"""
    pid = provider.get("id")
    if not pid:
        raise ValueError(f"AVAILABLE_MODELS provider 条目缺少 id 字段: {provider!r}")
    return pid


# Provider key 声明序（与 AVAILABLE_MODELS["providers"] 顺序一致，注册顺序契约）
# 条目缺 key 时显式 ValueError（注册名依赖 key，与既有校验语义对齐）
PROVIDER_KEYS: tuple[str, ...] = tuple(
    _require_key(p) for p in AVAILABLE_MODELS["providers"]
)

# Provider key → API 协议标识符映射（key != id 的协议共享者）
# 注：键集不可作 OPENAI_PROTOCOL_MODELS 的数据源 —— openai 自身不在本映射内
# key 存在性已由 PROVIDER_KEYS 的 _require_key 校验；此处 filter 先调 _require_id，
# 缺 id 的条目在 filter 阶段即抛 ValueError（与缺 key 对称）。
API_PROVIDER_MAP: dict[str, str] = {
    p["key"]: _require_id(p)
    for p in AVAILABLE_MODELS["providers"]
    if _require_id(p) != p["key"]
}

# OpenAI 协议族模型集（TD-66）：协议 id == "openai" 的全部 provider 的 models 并集
OPENAI_PROTOCOL_MODELS: frozenset[str] = frozenset(
    model
    for p in AVAILABLE_MODELS["providers"]
    if p["id"] == "openai"
    for model in p.get("models", [])
)


def resolve_api_provider(provider: str) -> str:
    """将 provider key 映射到同协议的凭证槽位（claude / openai）

    Args:
        provider: Provider key（如 "deepseek"）

    Returns:
        协议 id：在 API_PROVIDER_MAP 中返回其协议，否则返回自身（claude /
        openai 直接透传为凭证槽位名）。
    """
    return API_PROVIDER_MAP.get(provider, provider)