"""
LLM 凭据解析 / 实例化收口 — 深函数 resolve_llm（B2 共识 D3）

三处调用序列（聊天回合 / 文档解析 / 连接测试）同条件曾有三种错误语义：
「未配置 API Key」在聊天回合抛领域异常、在文档解析被错误归类为解析失败 422、
在连接测试为裸 400。本模块统一为同一种领域异常（ApiKeyMissingError），
由各调用方按自身 wire 契约转换：

    - 聊天回合：直接使用（领域异常经统一 handler 转 400）
    - 文档解析：调用处捕获 → 转 DocParseError（保持 422 + 既有文案 wire）
    - 连接测试：路由捕获 → 转 HTTPException(400)（保持 D-B3-1 局部语义）

协议表面（__all__）：resolve_llm。
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    ProviderNotSupportedError,
)
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.factory import LLMFactory

__all__ = ["resolve_llm"]


def resolve_llm(
    db: Session,
    provider: str | None,
    model: str | None = None,
    *,
    api_key: str | None = None,
    base_url: str | None = None,
) -> tuple[str, str, BaseLLM]:
    """凭据读取 + 未配置 Key 校验 + Provider 实例化（LLM 解析收口深函数）

    通用解析链（任一槽位有值即可用）与聊天回合旧行为一致：
        - provider 缺省 → 回退默认 Provider（DB settings → config）
        - api_key：显式覆盖优先，否则 setting_service 通用解析（provider 特定 →
          同协议槽位 → 跨协议兜底 → .env）；仍为空 → ApiKeyMissingError
        - base_url：显式覆盖优先，否则 setting_service 通用解析（空 → None）
        - model 缺省 → 回退默认模型（避免硬编码模型导致误报）

    Args:
        db: 数据库会话（读取 LLM 配置）
        provider: Provider 标识（claude / openai / 第三方）；留空用默认
        model: 模型名；留空用默认
        api_key: 显式 Key 覆盖（连接测试场景）；留空回退已存配置
        base_url: 显式 base_url 覆盖（连接测试场景）；留空回退已存配置

    Returns:
        (provider, model, llm) 三元组——provider / model 为解析后的实际值

    Raises:
        ApiKeyMissingError: 未配置 API Key
        ProviderNotSupportedError: 不支持的 Provider
    """
    prov = provider or setting_service.default_provider(db)
    key = api_key or setting_service.api_key(db, prov)
    if not key:
        raise ApiKeyMissingError(f"未配置 {prov} API Key，请在设置中填写")

    url = base_url or setting_service.base_url(db, prov) or None
    mod = model or setting_service.default_model(db) or None

    try:
        llm = LLMFactory.get_provider(prov, key, url)
    except ValueError:
        raise ProviderNotSupportedError(f"不支持的 Provider: {prov}")

    return prov, mod, llm
