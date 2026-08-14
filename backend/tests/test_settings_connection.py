"""
P4.3 单元测试 — API Key 保存时测试连接 + U8-T1 只读凭证端点

覆盖：
    1. BaseLLM.test_connection() 默认实现：以最小请求调用 generate（max_tokens=1）
    2. POST /api/settings/test-connection 端点：成功 / 鉴权失败 / 不支持 provider /
       未提供 Key / 空 Key 回退已存 Key / base_url 透传 / 通用异常
    3. GET /api/settings/credentials 端点（U8-T1）：openai 协议槽位优先 /
       claude-only 标志 / 无 Key 标志 / model 协议判定 / .env 回退 /
       跨协议 endpoint 兜底 / 协议混配（见文件末尾 TestCredentials* 用例）

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
from backend.app.services.exceptions import ProviderNotSupportedError
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMAuthError, LLMError
from backend.app.services.llm.factory import LLMFactory
from backend.app.services.llm.openai import _normalize_base_url

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

    def _translate_error(self, error: Exception) -> LLMError:
        """stub：本测试不产生 SDK 调用，翻译仅满足抽象契约"""
        return LLMError(str(error), error)

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
        asyncio.run(provider.test_connection(model="claude-sonnet-5"))

        assert provider.called is not None
        messages, temperature, max_tokens, model = provider.called
        assert messages == [{"role": "user", "content": "ping"}]
        assert temperature == 0.0
        assert max_tokens == 1
        assert model == "claude-sonnet-5"


# ── 1.5 OpenAI base_url 规范化（面板根地址 → /v1 端点）──


class TestNormalizeBaseUrl:
    def test_none_passthrough(self) -> None:
        assert _normalize_base_url(None) is None

    def test_root_url_appends_v1(self) -> None:
        """用户只填面板根地址 → 补 /v1（New API 等常见配置）"""
        assert _normalize_base_url("https://api.kukuit.com") == "https://api.kukuit.com/v1"

    def test_trailing_slash_appends_v1(self) -> None:
        assert _normalize_base_url("https://api.example.com/") == "https://api.example.com/v1"

    def test_already_v1_unchanged(self) -> None:
        assert _normalize_base_url("https://api.openai.com/v1") == "https://api.openai.com/v1"
        assert _normalize_base_url("https://api.example.com/v1/") == "https://api.example.com/v1"

    def test_custom_version_segment_kept(self) -> None:
        """非 /v1 版本段（如 /v1beta）不误改"""
        assert _normalize_base_url("https://api.example.com/v1beta") == "https://api.example.com/v1beta"


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
        记录调用参数的 dict（name / api_key / base_url / model）
    """
    calls: dict = {}

    class _RecStub:
        """记录 test_connection 收到的 model，可配置抛出错误"""

        def __init__(self, err: Exception | None) -> None:
            self.err = err

        async def test_connection(self, model: str | None = None) -> None:
            calls["model"] = model
            if self.err:
                raise self.err

    def fake_get_provider(name: str, api_key: str, base_url: str | None = None) -> object:
        calls["name"] = name
        calls["api_key"] = api_key
        calls["base_url"] = base_url
        return _RecStub(error)

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
        """未知 Provider → ProviderNotSupportedError 上抛（统一 handler 转 400，wire 语义不变）"""
        req = ConnectionTestRequest(provider="gemini", api_key="key")
        with pytest.raises(ProviderNotSupportedError) as exc:
            _run(req, db_session)
        assert "不支持的 Provider" in str(exc.value)

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

    def test_model_falls_back_to_default_model(self, db_session, monkeypatch) -> None:
        """请求无 model 时回退默认模型（用户配置的），避免硬编码模型误报"""
        _save_setting(db_session, "default_model", "deepseek-v4-flash")
        calls = _patch_provider(monkeypatch)
        req = ConnectionTestRequest(provider="deepseek", api_key="sk-test")
        _run(req, db_session)
        assert calls["model"] == "deepseek-v4-flash"
        assert calls["name"] == "deepseek"

    def test_model_explicit_wins_over_default(self, db_session, monkeypatch) -> None:
        """请求显式传 model 时优先使用"""
        _save_setting(db_session, "default_model", "deepseek-v4-flash")
        calls = _patch_provider(monkeypatch)
        req = ConnectionTestRequest(provider="deepseek", api_key="sk-test", model="qwen-max")
        _run(req, db_session)
        assert calls["model"] == "qwen-max"

    def test_base_url_falls_back_to_saved(self, db_session, monkeypatch) -> None:
        """请求无 base_url 时回退库中已存 URL（通用解析：同协议 → 跨协议）"""
        _save_setting(db_session, "claude_base_url", "https://relay.example.com")
        calls = _patch_provider(monkeypatch)
        req = ConnectionTestRequest(provider="deepseek", api_key="sk-test")
        _run(req, db_session)
        assert calls["base_url"] == "https://relay.example.com"

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


# ── 5. GET /api/settings/credentials 凭证端点（U8-T1，只读）──
#
# 契约（spec「U8 凭证端点契约」/ 工单 U8-T1）：
#   - 解析链复用运行设置服务既有语义，openai 协议槽位优先（DB → .env）
#   - 仅 claude key → protocol=claude 且 key 为空串（claude key 值绝不回传游戏）
#   - 两者皆无 → protocol=none，key/endpoint/model 全空串（只读查询不报错）
#   - endpoint/model 为空时交由前端保持游戏默认
# 断言纪律：key 只断言存在性/非空（不断言 key 值明文）；仅「不回传 claude key」
# 的防泄漏断言使用测试假值比较。


class TestCredentialsService:
    """setting_service.credentials()：OpenAI 兼容凭证三元组 + 协议能力标志"""

    def test_empty_db_and_env_returns_none(self, db_session, monkeypatch) -> None:
        """DB 与 .env 全空 → protocol=none，key/endpoint/model 全空串"""
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "")
        monkeypatch.setattr(settings, "CLAUDE_API_KEY", "")
        assert setting_service.credentials(db_session) == {
            "key": "",
            "endpoint": "",
            "model": "",
            "protocol": "none",
        }

    def test_openai_key_from_db(self, db_session) -> None:
        """DB openai_api_key → protocol=openai + 非空 key"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["key"]
        assert result["endpoint"] == ""

    def test_claude_only_key_not_returned(self, db_session) -> None:
        """仅 claude key → protocol=claude，key/endpoint/model 全空（claude key 值绝不回传）"""
        _save_setting(db_session, "claude_api_key", "sk-ant-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "claude"
        assert result["key"] == ""
        assert result["endpoint"] == ""
        assert result["model"] == ""

    def test_openai_key_preferred_over_claude(self, db_session) -> None:
        """双协议 key → openai 槽位优先，key 非空且不是 claude 槽位值"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "claude_api_key", "sk-ant-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["key"]
        assert result["key"] != "sk-ant-test"

    def test_env_openai_key_fallback(self, db_session, monkeypatch) -> None:
        """DB 无 openai key → .env OPENAI_API_KEY 兜底（同协议 .env 回退）"""
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "sk-env-openai-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["key"]

    def test_env_openai_key_not_overridden_by_db_claude_key(self, db_session, monkeypatch) -> None:
        """DB 仅 claude key + .env openai key → protocol=openai 且 key 非 DB claude 值"""
        _save_setting(db_session, "claude_api_key", "sk-ant-test")
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "sk-env-openai-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["key"]
        assert result["key"] != "sk-ant-test"

    def test_env_claude_key_only(self, db_session, monkeypatch) -> None:
        """仅 .env CLAUDE_API_KEY → protocol=claude，key 空串"""
        monkeypatch.setattr(settings, "CLAUDE_API_KEY", "sk-ant-env-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "claude"
        assert result["key"] == ""

    def test_base_url_only_no_key_returns_none(self, db_session) -> None:
        """仅 openai_base_url 无任何 key → protocol=none，endpoint 也为空"""
        _save_setting(db_session, "openai_base_url", "https://api.example.com/v1")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "none"
        assert result["endpoint"] == ""

    def test_endpoint_cross_protocol_fallback(self, db_session) -> None:
        """openai key + 仅 claude_base_url → endpoint 走既有跨协议兜底（复用 base_url 链）"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "claude_base_url", "https://relay.example.com")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["endpoint"] == "https://relay.example.com"

    def test_claude_key_with_openai_base_url_endpoint_empty(self, db_session) -> None:
        """协议混配：仅 claude key + openai_base_url → protocol=claude 且 endpoint 空"""
        _save_setting(db_session, "claude_api_key", "sk-ant-test")
        _save_setting(db_session, "openai_base_url", "https://api.example.com/v1")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "claude"
        assert result["endpoint"] == ""

    def test_model_returned_when_openai_key_and_openai_provider(self, db_session) -> None:
        """openai key + 默认 provider=openai → 返回 default_model"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "default_provider", "openai")
        _save_setting(db_session, "default_model", "gpt-4o-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["model"] == "gpt-4o-test"

    def test_model_empty_when_default_provider_claude(self, db_session) -> None:
        """openai key 存在但默认 provider=claude → model 空串（游戏保持默认模型）"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "default_provider", "claude")
        _save_setting(db_session, "default_model", "gpt-4o-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["key"]
        assert result["model"] == ""

    def test_model_empty_when_no_openai_key(self, db_session) -> None:
        """默认 provider 为 openai 协议但无 openai key → model 仍空（完整凭证仅 openai 槽位有 key 时返回）"""
        _save_setting(db_session, "default_provider", "deepseek")
        _save_setting(db_session, "default_model", "deepseek-v4-test")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "none"
        assert result["model"] == ""

    def test_model_empty_when_openai_provider_and_model_not_explicitly_configured(self, db_session, monkeypatch) -> None:
        """默认 provider 为 openai 协议族（deepseek）且未显式配置默认模型 → .env 默认模型
        不属于 openai 协议模型集时 model 空串（TD-66：注入不再混入 claude 模型名）"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "default_provider", "deepseek")
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "")
        monkeypatch.setattr(settings, "DEFAULT_MODEL", "claude-sonnet-4-20250514")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["key"]
        assert result["model"] == ""

    def test_model_explicit_config_outside_openai_set_returned(self, db_session, monkeypatch) -> None:
        """显式配置 default_model（openai 集外值）→ 原样返回（TD-66：显式配置不误伤）"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "default_provider", "openai")
        _save_setting(db_session, "default_model", "claude-sonnet-4-20250514")
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["model"] == "claude-sonnet-4-20250514"

    def test_model_falls_back_to_env_when_in_openai_set(self, db_session, monkeypatch) -> None:
        """.env 默认模型属于 openai 协议模型集（gpt-4o）→ 未显式配置时回退该值（TD-66 不误伤）"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "default_provider", "openai")
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "")
        monkeypatch.setattr(settings, "DEFAULT_MODEL", "gpt-4o")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["model"] == "gpt-4o"

    def test_model_env_fallback_in_openai_set_any_openai_protocol_provider(self, db_session, monkeypatch) -> None:
        """openai 协议族任一 provider（deepseek）+ .env 默认模型在集内 → 回退该值"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "default_provider", "deepseek")
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "")
        monkeypatch.setattr(settings, "DEFAULT_MODEL", "qwen-max")
        result = setting_service.credentials(db_session)
        assert result["protocol"] == "openai"
        assert result["model"] == "qwen-max"


class TestCredentialsEndpoint:
    """GET /api/settings/credentials 端点（直接驱动路由函数）"""

    def test_no_credentials_returns_200_shape(self, db_session, monkeypatch) -> None:
        """无凭证 → 正常返回（非 404/401）：protocol=none + 全字段空串"""
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "")
        monkeypatch.setattr(settings, "CLAUDE_API_KEY", "")
        resp = settings_route.get_credentials(db_session)
        assert resp.protocol == "none"
        assert resp.key == ""
        assert resp.endpoint == ""
        assert resp.model == ""

    def test_with_openai_credentials_returns_triple(self, db_session) -> None:
        """openai key + base_url + 默认 provider=openai → 三元组 + protocol=openai"""
        _save_setting(db_session, "openai_api_key", "sk-openai-test")
        _save_setting(db_session, "openai_base_url", "https://api.example.com/v1")
        _save_setting(db_session, "default_provider", "openai")
        _save_setting(db_session, "default_model", "gpt-4o-test")
        resp = settings_route.get_credentials(db_session)
        assert resp.protocol == "openai"
        assert resp.key
        assert resp.endpoint == "https://api.example.com/v1"
        assert resp.model == "gpt-4o-test"

    def test_claude_only_key_returns_claude_flag(self, db_session) -> None:
        """仅 claude key → protocol=claude 且 key 空串（端点不回传 claude key）"""
        _save_setting(db_session, "claude_api_key", "sk-ant-test")
        resp = settings_route.get_credentials(db_session)
        assert resp.protocol == "claude"
        assert resp.key == ""
        assert resp.endpoint == ""
