"""
BE-1 单元测试 — resolve_llm 深函数（LLM 凭据解析/实例化收口）

覆盖：
    1. 未配置 Key → ApiKeyMissingError（统一领域异常）
    2. Provider 不合法（get_provider 抛 ValueError）→ ProviderNotSupportedError
    3. 正常解析 → (provider, model, llm) 三元组 + 参数透传
    4. provider / model 缺省回退默认值
    5. 显式 api_key / base_url 覆盖优先（连接测试用）

依赖：pytest + SQLite 内存库（conftest.db_session）+ monkeypatch 假工厂。
不构造真实网络请求。
"""

from __future__ import annotations

import pytest

from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    ProviderNotSupportedError,
)
from backend.app.services.llm import resolver
from backend.app.services.llm.resolver import resolve_llm

__all__: list[str] = []


class _FakeProvider:
    """记录构造参数的假 Provider"""

    def __init__(self, api_key: str, base_url: str | None = None) -> None:
        self.api_key = api_key
        self.base_url = base_url


class _FakeFactory:
    """替代 resolver.LLMFactory 的假工厂（记录调用参数，不污染真实工厂）"""

    instances: list[tuple[str, str, str | None]] = []

    @classmethod
    def get_provider(cls, name: str, api_key: str, base_url: str | None = None) -> _FakeProvider:
        cls.instances.append((name, api_key, base_url))
        return _FakeProvider(api_key, base_url)


def _patch_factory(monkeypatch) -> None:
    """让 resolver.LLMFactory.get_provider 返回假 Provider"""
    _FakeFactory.instances = []
    monkeypatch.setattr(resolver, "LLMFactory", _FakeFactory)


def _patch_api_key(monkeypatch, value: str = "sk-test") -> None:
    """让 setting_service.api_key 恒返回测试 Key"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: value)


class TestResolveLlm:
    def test_missing_api_key_raises(self, db_session) -> None:
        """未配置 API Key（DB 设置表为空）→ ApiKeyMissingError（统一领域异常）"""
        with pytest.raises(ApiKeyMissingError) as exc:
            resolve_llm(db_session, "claude", "claude-test")
        assert "claude" in str(exc.value)
        assert "API Key" in str(exc.value)

    def test_unsupported_provider_raises(self, db_session, monkeypatch) -> None:
        """Provider 不合法（get_provider 抛 ValueError）→ ProviderNotSupportedError"""

        class _RaisingFactory:
            @staticmethod
            def get_provider(name: str, api_key: str, base_url: str | None = None) -> object:
                raise ValueError(f"不支持的 Provider: {name}")

        _patch_api_key(monkeypatch)
        monkeypatch.setattr(resolver, "LLMFactory", _RaisingFactory)

        with pytest.raises(ProviderNotSupportedError) as exc:
            resolve_llm(db_session, "gemini", "gemini-test")
        assert "gemini" in str(exc.value)

    def test_resolve_returns_triple(self, db_session, monkeypatch) -> None:
        """正常解析 → (provider, model, llm) 三元组，构造参数透传"""
        _patch_api_key(monkeypatch)
        _patch_factory(monkeypatch)

        prov, mod, llm = resolve_llm(db_session, "claude", "claude-test")

        assert (prov, mod) == ("claude", "claude-test")
        assert isinstance(llm, _FakeProvider)
        assert _FakeFactory.instances == [("claude", "sk-test", None)]

    def test_provider_falls_back_to_default(self, db_session, monkeypatch) -> None:
        """provider 缺省 → 回退默认 Provider（DB → config）"""
        _patch_api_key(monkeypatch)
        _patch_factory(monkeypatch)
        monkeypatch.setattr(setting_service, "default_provider", lambda db: "openai")

        prov, _, _ = resolve_llm(db_session, None, "gpt-4o")

        assert prov == "openai"
        assert _FakeFactory.instances == [("openai", "sk-test", None)]

    def test_model_falls_back_to_default(self, db_session, monkeypatch) -> None:
        """model 缺省 → 回退默认模型"""
        _patch_api_key(monkeypatch)
        _patch_factory(monkeypatch)
        monkeypatch.setattr(setting_service, "default_model", lambda db: "deepseek-v4-flash")

        _, mod, _ = resolve_llm(db_session, "deepseek", None)

        assert mod == "deepseek-v4-flash"

    def test_explicit_overrides_win(self, db_session, monkeypatch) -> None:
        """显式 api_key / base_url 覆盖优先于已存配置（连接测试场景）"""
        _patch_api_key(monkeypatch, value="sk-stored")
        _patch_factory(monkeypatch)
        monkeypatch.setattr(setting_service, "base_url", lambda db, provider: "https://stored.example.com")

        _, _, llm = resolve_llm(
            db_session,
            "claude",
            "claude-test",
            api_key="sk-explicit",
            base_url="https://explicit.example.com/v1",
        )

        assert _FakeFactory.instances == [
            ("claude", "sk-explicit", "https://explicit.example.com/v1"),
        ]
        assert llm.api_key == "sk-explicit"
