"""
模拟器同源 API 反代 — 单元测试（CORS 修复 2026-08-28）

契约锚点（见 simulators.py 模块 docstring「同源 API 反代契约」）：
    纯函数 `_build_proxy_target(real_endpoint, path)`：
        - path 原样拼到 real_endpoint 的 scheme://netloc 之后（real path 不参与）
        - scheme 缺失回退 https；netloc 缺失 → ValueError
    纯函数 `_proxy_headers(request_headers, api_key)`：
        - 剥除 host/content-length/authorization/connection/accept-encoding
        - 后端注入 Authorization: Bearer <key>；key 空 → 不注入
    路由 wire `[GET|POST|...] /api/simulators/proxy/{path}`：
        - 未配置 OpenAI 兼容端点 → 503
        - 正常：httpx 以正确 target / method / headers（含后端 key）转发
        - 流式响应透传

全部用例不触网络（monkeypatch httpx.AsyncClient 与 setting_service.credentials）。
"""

from __future__ import annotations

from pathlib import Path

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.api.routes import simulators as simulators_route
from backend.app.api.routes.simulators import _build_proxy_target, _proxy_headers
from backend.app.services import setting as setting_service

__all__ = [
    "TestBuildProxyTarget",
    "TestProxyHeaders",
    "TestProxyEndpointWire",
]


class TestBuildProxyTarget:
    """目标 URL 拼装矩阵"""

    def test_path_appended_to_netloc(self) -> None:
        assert _build_proxy_target("https://yunshuzhilian.asia/v1", "v1/models") == \
            "https://yunshuzhilian.asia/v1/models"

    def test_chat_completions_full_path(self) -> None:
        assert _build_proxy_target("https://host/v1", "v1/chat/completions") == \
            "https://host/v1/chat/completions"

    def test_real_path_segment_not_duplicated(self) -> None:
        # real base 的 path 段已由前端写入 path（toProxyEndpoint），此处不重复
        assert _build_proxy_target("https://host/v1", "v1/chat/completions") == \
            "https://host/v1/chat/completions"

    def test_leading_slash_stripped(self) -> None:
        assert _build_proxy_target("https://host/v1", "/v1/models") == \
            "https://host/v1/models"

    def test_scheme_fallback_https(self) -> None:
        # 无 scheme 但带 // 的 netloc 形态 → 回退 https
        assert _build_proxy_target("//yunshuzhilian.asia/v1", "v1/models") == \
            "https://yunshuzhilian.asia/v1/models"

    def test_no_path_base(self) -> None:
        assert _build_proxy_target("https://api.deepseek.com", "models") == \
            "https://api.deepseek.com/models"

    def test_missing_netloc_raises(self) -> None:
        with pytest.raises(ValueError):
            _build_proxy_target("not-a-url", "models")

    def test_empty_endpoint_raises(self) -> None:
        with pytest.raises(ValueError):
            _build_proxy_target("", "models")


class TestProxyHeaders:
    """转发头组装：剥除 hop-by-hop + 注入后端 key"""

    def test_skips_hop_and_client_auth_headers(self) -> None:
        h = _proxy_headers(
            {
                "Host": "127.0.0.1:8000",
                "Content-Length": "5",
                "Authorization": "Bearer sk-client-stale",
                "Connection": "keep-alive",
                "Accept-Encoding": "gzip",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
            "sk-backend",
        )
        assert "Host" not in h
        assert "Content-Length" not in h
        assert "Connection" not in h
        assert "Accept-Encoding" not in h
        # 客户端自带的 key 被丢弃，由后端统一注入
        assert h["Authorization"] == "Bearer sk-backend"
        assert h["Accept"] == "application/json"
        assert h["Content-Type"] == "application/json"

    def test_no_key_omits_authorization(self) -> None:
        h = _proxy_headers({"Accept": "*/*"}, "")
        assert "Authorization" not in h
        assert h["Accept"] == "*/*"


class _FakeResponse:
    """假上游响应：非流式头 + 一段可迭代字节体"""

    status_code = 200
    headers = {"content-type": "application/json", "content-length": "13", "x-upstream": "1"}

    async def aiter_bytes(self):
        yield b'{"ok": true}'


class _FakeAsyncClient:
    """假 httpx 客户端：记录发送请求，返回假响应"""

    def __init__(self, timeout: object = None) -> None:
        self.timeout = timeout
        self.sent: list[tuple] = []

    def build_request(self, method: str, url: str, headers=None, content=None) -> tuple:
        return (method, url, headers, content)

    async def send(self, req, stream: bool = True) -> _FakeResponse:
        self.sent.append(req)
        return _FakeResponse()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc) -> None:
        return None


class TestProxyEndpointWire:
    """路由 wire（TestClient + monkeypatch httpx/credentials）"""

    @pytest.fixture
    def import_app(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> FastAPI:
        """最小应用（仅模拟器路由）；CONVER_DATA_DIR 指向临时目录"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        app = FastAPI()
        app.include_router(simulators_route.router)
        return app

    def _make_client(self, monkeypatch: pytest.MonkeyPatch, creds: dict):
        fake = _FakeAsyncClient()
        monkeypatch.setattr(httpx, "AsyncClient", lambda *a, **k: fake)
        monkeypatch.setattr(setting_service, "credentials", lambda db: creds)
        return fake

    def test_503_when_no_endpoint(
        self, import_app: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        self._make_client(monkeypatch, {"endpoint": "", "key": "", "model": "", "protocol": "none"})
        with TestClient(import_app) as client:
            resp = client.get("/api/simulators/proxy/v1/models")
        assert resp.status_code == 503
        assert "未配置" in resp.json()["detail"]

    def test_503_when_endpoint_invalid(
        self, import_app: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        self._make_client(monkeypatch, {"endpoint": "not-a-url", "key": "sk", "model": "", "protocol": "openai"})
        with TestClient(import_app) as client:
            resp = client.get("/api/simulators/proxy/v1/models")
        assert resp.status_code == 503

    def test_forwards_get_with_backend_key(
        self, import_app: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        fake = self._make_client(
            monkeypatch,
            {"endpoint": "https://yunshuzhilian.asia/v1", "key": "sk-backend", "model": "m", "protocol": "openai"},
        )
        with TestClient(import_app) as client:
            resp = client.get("/api/simulators/proxy/v1/models")
        assert resp.status_code == 200
        assert resp.json() == {"ok": True}
        method, url, headers, _content = fake.sent[0]
        assert method == "GET"
        assert url == "https://yunshuzhilian.asia/v1/models"
        assert headers["Authorization"] == "Bearer sk-backend"
        assert "x-upstream" not in headers  # 请求头不带上游透传的响应头

    def test_forwards_post_method_and_body(
        self, import_app: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        fake = self._make_client(
            monkeypatch,
            {"endpoint": "https://api.deepseek.com/v1", "key": "sk", "model": "m", "protocol": "openai"},
        )
        payload = b'{"model":"deepseek-v4-flash"}'
        with TestClient(import_app) as client:
            resp = client.post(
                "/api/simulators/proxy/v1/chat/completions",
                content=payload,
                headers={"Content-Type": "application/json"},
            )
        assert resp.status_code == 200
        method, url, headers, content = fake.sent[0]
        assert method == "POST"
        assert url == "https://api.deepseek.com/v1/chat/completions"
        assert content == payload
