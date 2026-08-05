"""
P4.3 单元测试 — API Key 保存时测试连接

覆盖：
    1. BaseLLM.test_connection() 默认实现：以最小请求调用 generate（max_tokens=1）
    2. POST /api/settings/test-connection 端点：成功 / 鉴权失败 / 不支持 provider /
       未提供 Key / 空 Key 回退已存 Key / base_url 透传 / 通用异常

依赖：pytest + SQLite 内存库（StaticPool 保证同一连接，避免 threading 限制）。
端点测试通过 monkeypatch LLMFactory.get_provider 返回 stub，不发起真实网络请求。
"""

from __future__ import annotations

import asyncio

import pytest
from fastapi import HTTPException

from backend.app.config import settings
from backend.app.models.setting import Setting
from backend.app.schemas.settings import ConnectionTestRequest
from backend.app.api.routes import settings as settings_route
from backend.app.services import setting as setting_service
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMAuthError
from backend.app.services.llm.factory import LLMFactory

__all__: list[str] = []


def _save_setting(db_session, key: str, value: str) -> None:
    """写入一条设置记录"""
    db_session.add(Setting(key=key, value=value))
    db_session.commit()


# ── 1. BaseLLM.test_connection() 默认实现 ──


class _RecordingProvider(BaseLLM):
    """记录 generate 调用参数的最小 Provider 实现"""

    def __init__(self) -> None:
        super().__init__(api_key="test-key")
        self.called: tuple | None = None

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        self.called = (messages, temperature, max_tokens, model)
        return "pong"

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> object:
        yield "pong"


class TestBaseLLMTestConnection:
    def test_default_impl_uses_minimal_request(self) -> None:
        """默认实现用最小请求（1 token）调用 generate，并透传 model"""
        provider = _RecordingProvider()
        asyncio.run(provider.test_connection(model="claude-sonnet-4-20250514"))

        assert provider.called is not None
        messages, temperature, max_tokens, model = provider.called
        assert messages == [{"role": "user", "content": "ping"}]
        assert temperature == 0.0
        assert max_tokens == 1
        assert model == "claude-sonnet-4-20250514"


# ── 2. POST /api/settings/test-connection 端点 ──


class _StubLLM:
    """可配置抛出错误的 LLM stub"""

    def __init__(self, error: Exception | None = None) -> None:
        self.error = error

    async def test_connection(self, model: str | None = None) -> None:
        if self.error:
            raise self.error


def _patch_provider(monkeypatch, *, error: Exception | None = None) -> dict:
    """让 LLMFactory.get_provider 返回 stub，并记录其收到的参数

    Returns:
        记录 get_provider 调用参数的 dict（name / api_key / base_url）
    """
    calls: dict = {}

    def fake_get_provider(name: str, api_key: str, base_url: str | None = None) -> object:
        calls["name"] = name
        calls["api_key"] = api_key
        calls["base_url"] = base_url
        return _StubLLM(error=error)

    monkeypatch.setattr(LLMFactory, "get_provider", fake_get_provider)
    return calls


def _run(data: ConnectionTestRequest, db_session) -> object:
    """同步驱动异步端点函数"""
    return asyncio.run(settings_route.test_connection(data, db_session))


# ── 3. GET / PUT /api/settings 端点（连接测试依赖的存取路径）──


class TestSettingsCrud:
    def test_get_settings_returns_stored(self, db_session) -> None:
        """GET 返回白名单内已存设置"""
        _save_setting(db_session, "claude_api_key", "sk-ant-test")
        _save_setting(db_session, "default_provider", "claude")
        result = settings_route.get_settings(db_session)
        assert result["claude_api_key"] == "sk-ant-test"
        assert result["default_provider"] == "claude"

    def test_put_settings_upserts_and_filters(self, db_session) -> None:
        """PUT 写入白名单键、忽略非白名单键、已存在则更新"""
        _save_setting(db_session, "claude_api_key", "old")
        result = settings_route.update_settings(
            {"claude_api_key": "new", "not_allowed": "x"}, db_session,
        )
        assert result["claude_api_key"] == "new"
        assert "not_allowed" not in result

    def test_put_settings_creates_new_key(self, db_session) -> None:
        """PUT 对不存在的白名单键走创建分支"""
        result = settings_route.update_settings({"user_name": "Alice"}, db_session)
        assert result["user_name"] == "Alice"


# ── 4. services/setting.py 深模块语义（收口后的读写 + 500 修复）──


class TestSettingService:
    def test_get_int_falls_back_on_non_numeric(self, db_session) -> None:
        """sliding_window_rounds 存非数字 → get_int 回退默认 30（防 500）"""
        _save_setting(db_session, "sliding_window_rounds", "abc")
        assert setting_service.sliding_window_rounds(db_session) == 30

    def test_sliding_window_default_when_missing(self, db_session) -> None:
        assert setting_service.sliding_window_rounds(db_session) == 30

    def test_sliding_window_reads_int(self, db_session) -> None:
        _save_setting(db_session, "sliding_window_rounds", "7")
        assert setting_service.sliding_window_rounds(db_session) == 7

    def test_default_provider_falls_back_to_config(self, db_session) -> None:
        assert setting_service.default_provider(db_session) == settings.DEFAULT_PROVIDER

    def test_default_provider_from_db(self, db_session) -> None:
        _save_setting(db_session, "default_provider", "openai")
        assert setting_service.default_provider(db_session) == "openai"

    def test_default_model_from_db(self, db_session) -> None:
        _save_setting(db_session, "default_model", "gpt-4o")
        assert setting_service.default_model(db_session) == "gpt-4o"

    def test_user_name_default(self, db_session) -> None:
        assert setting_service.user_name(db_session) == "User"

    def test_api_key_unconfigured_returns_empty(self, db_session) -> None:
        assert setting_service.api_key(db_session, "claude") == ""

    # ── 通用凭证解析（任一槽位有值即可用）──

    def test_api_key_same_protocol_fallback(self, db_session) -> None:
        """DeepSeek（OpenAI 协议）→ 同协议槽位 openai_api_key"""
        _save_setting(db_session, "openai_api_key", "sk-openai")
        assert setting_service.api_key(db_session, "deepseek") == "sk-openai"

    def test_api_key_cross_protocol_fallback(self, db_session) -> None:
        """只填 claude_api_key，DeepSeek 跨协议兜底取到它（通用系统）"""
        _save_setting(db_session, "claude_api_key", "sk-claude")
        assert setting_service.api_key(db_session, "deepseek") == "sk-claude"

    def test_api_key_prefers_same_protocol(self, db_session) -> None:
        """两个槽位都有值 → 同协议槽位优先"""
        _save_setting(db_session, "claude_api_key", "sk-claude")
        _save_setting(db_session, "openai_api_key", "sk-openai")
        assert setting_service.api_key(db_session, "deepseek") == "sk-openai"
        assert setting_service.api_key(db_session, "claude") == "sk-claude"

    def test_api_key_provider_specific_wins(self, db_session) -> None:
        """provider 特定键优先于协议槽位"""
        _save_setting(db_session, "deepseek_api_key", "sk-deepseek")
        _save_setting(db_session, "openai_api_key", "sk-openai")
        assert setting_service.api_key(db_session, "deepseek") == "sk-deepseek"

    def test_base_url_same_protocol_fallback(self, db_session) -> None:
        """DeepSeek → 同协议槽位 openai_base_url"""
        _save_setting(db_session, "openai_base_url", "https://openai.example.com")
        assert setting_service.base_url(db_session, "deepseek") == "https://openai.example.com"

    def test_base_url_cross_protocol_fallback(self, db_session) -> None:
        """只填 claude_base_url，DeepSeek 跨协议兜底取到它"""
        _save_setting(db_session, "claude_base_url", "https://relay.example.com")
        assert setting_service.base_url(db_session, "deepseek") == "https://relay.example.com"

    def test_base_url_prefers_same_protocol(self, db_session) -> None:
        """两个槽位都有值 → 同协议槽位优先"""
        _save_setting(db_session, "claude_base_url", "https://claude.example.com")
        _save_setting(db_session, "openai_base_url", "https://openai.example.com")
        assert setting_service.base_url(db_session, "deepseek") == "https://openai.example.com"

    def test_base_url_unconfigured_returns_empty(self, db_session) -> None:
        assert setting_service.base_url(db_session, "claude") == ""


class TestConnectionEndpoint:
    def test_success(self, db_session, monkeypatch) -> None:
        """Key 有效 → 返回 ok=True"""
        _patch_provider(monkeypatch)
        req = ConnectionTestRequest(provider="claude", api_key="sk-ant-test")
        resp = _run(req, db_session)
        assert resp.ok is True
        assert resp.provider == "claude"

    def test_auth_failure_returns_400(self, db_session, monkeypatch) -> None:
        """Key 无效 → 400 + 可读原因"""
        _patch_provider(monkeypatch, error=LLMAuthError("Claude API Key 无效或未配置"))
        req = ConnectionTestRequest(provider="claude", api_key="sk-ant-bad")
        with pytest.raises(HTTPException) as exc:
            _run(req, db_session)
        assert exc.value.status_code == 400
        assert "无效" in exc.value.detail

    def test_unsupported_provider_returns_400(self, db_session) -> None:
        """未知 Provider → 400，不构造 LLM 实例"""
        req = ConnectionTestRequest(provider="gemini", api_key="key")
        with pytest.raises(HTTPException) as exc:
            _run(req, db_session)
        assert exc.value.status_code == 400
        assert "不支持的 Provider" in exc.value.detail

    def test_empty_key_and_no_saved_key_returns_400(self, db_session, monkeypatch) -> None:
        """请求无 Key 且库中无已存 Key → 400"""
        _patch_provider(monkeypatch)
        req = ConnectionTestRequest(provider="claude", api_key="")
        with pytest.raises(HTTPException) as exc:
            _run(req, db_session)
        assert exc.value.status_code == 400
        assert "未提供 API Key" in exc.value.detail

    def test_empty_key_falls_back_to_saved_key(self, db_session, monkeypatch) -> None:
        """请求无 Key 时回退库中已存 Key 测试"""
        _save_setting(db_session, "openai_api_key", "sk-saved")
        calls = _patch_provider(monkeypatch)
        req = ConnectionTestRequest(provider="openai", api_key="")
        resp = _run(req, db_session)
        assert resp.ok is True
        assert calls["api_key"] == "sk-saved"

    def test_base_url_passed_through(self, db_session, monkeypatch) -> None:
        """OpenAI 兼容 base_url 透传给 Provider"""
        calls = _patch_provider(monkeypatch)
        req = ConnectionTestRequest(
            provider="openai",
            api_key="sk-test",
            base_url="https://api.example.com/v1",
        )
        _run(req, db_session)
        assert calls["base_url"] == "https://api.example.com/v1"

    def test_generic_exception_returns_400(self, db_session, monkeypatch) -> None:
        """非 LLMError 异常（网络不可达等）→ 400 连接失败"""
        _patch_provider(monkeypatch, error=ConnectionError("connection refused"))
        req = ConnectionTestRequest(provider="claude", api_key="sk-ant-test")
        with pytest.raises(HTTPException) as exc:
            _run(req, db_session)
        assert exc.value.status_code == 400
        assert "连接失败" in exc.value.detail
