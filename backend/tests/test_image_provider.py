"""
CG-1 text2img Provider 抽象 — 契约测试

覆盖（验收语义契约，spec §CG-1）：
    1. 注册表派生：AVAILABLE_IMAGE_PROVIDERS 登记条目全部可在 factory 解析
       （http → HttpImageGen / local → LocalImageGen）；未知 Provider 明确拒绝
    2. 缺 Key 错误映射：requires_key Provider 且 Key 缺失 → ImageAuthError（401）；
       本地优先后端无需 Key 正常走通
    3. 响应畸形 → 明确错误：缺 images / 空数组 / 非法 base64 → ImageResponseError
    4. 超时（15s 守卫语义）+ 连接失败：httpx 异常族 → ImageTimeoutError(504) /
       ImageConnectionError(502)
    5. A1111 happy path：{images:[base64]} → 落盘本地 + PNG magic + 尺寸/类型
    6. 本地文件后端：确定性占位 PNG（同 prompt 同字节）+ 落盘本地
    7. image_error_response 映射矩阵

依赖：pytest；HTTP 调用经 `_HTTP_CLIENT_FACTORY` 假客户端注入（零真实网络）；
落盘经 CONVER_DATA_DIR 指到 tmp_path（零污染）。
"""

from __future__ import annotations

import base64
import io

import httpx
import pytest
from pydantic import ValidationError

from backend.app.services import error_mapping
from backend.app.services.exceptions import ProviderNotSupportedError
from backend.app.services.image.base import BaseImageGen, ImageGenParams, ImageResult
from backend.app.services.image.errors import (
    ImageAuthError,
    ImageConnectionError,
    ImageError,
    ImageResponseError,
    ImageTimeoutError,
)
from backend.app.services.image.factory import ImageFactory
from backend.app.services.image.http_backend import HttpImageGen
from backend.app.services.image.local_backend import LocalImageGen
from backend.app.services.image.model_data import (
    AVAILABLE_IMAGE_PROVIDERS,
    IMAGE_PROVIDER_KEYS,
    image_provider_id,
    image_provider_requires_key,
)
from backend.app.services.image.resolver import resolve_image

__all__: list[str] = []


# ── 测试基础设施 ──


@pytest.fixture()
def cg_dir_tmp(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    """把数据目录指到 tmp_path（CG 落盘零污染）"""
    monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))


class _FakeResponse:
    """假 httpx 响应（raise_for_status + json）"""

    def __init__(self, data: object, status: int = 200) -> None:
        self._data = data
        self._status = status

    def raise_for_status(self) -> None:
        if self._status >= 400:
            raise httpx.HTTPStatusError(
                f"HTTP {self._status}", request=httpx.Request("POST", "http://x"), response=None
            )

    def json(self) -> object:
        return self._data


class _FakeClient:
    """假 httpx.AsyncClient（async 上下文形态；post 可配置返回/抛错）"""

    def __init__(self, result: object = None, error: Exception | None = None, **kwargs) -> None:
        self._result = result
        self._error = error
        self.calls: list[tuple] = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args) -> bool:
        return False

    async def post(self, url: str, json: object = None, headers: dict | None = None):
        self.calls.append((url, json, headers))
        if self._error is not None:
            raise self._error
        return _FakeResponse(self._result)


def _patch_client(
    monkeypatch: pytest.MonkeyPatch,
    client: _FakeClient,
) -> None:
    """用假客户端替换 http_backend._HTTP_CLIENT_FACTORY"""
    from backend.app.services.image import http_backend

    monkeypatch.setattr(http_backend, "_HTTP_CLIENT_FACTORY", lambda **kw: client)


def _tiny_png_bytes() -> bytes:
    """生成一张极小的合法 PNG（happy path 的 base64 源）"""
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (64, 64), (10, 20, 30)).save(buf, format="PNG")
    return buf.getvalue()


def _png_bytes_magic(path: str) -> bool:
    """本地文件 PNG magic 校验（\x89PNG\r\n\x1a\n）"""
    with open(path, "rb") as f:
        head = f.read(8)
    return head == b"\x89PNG\r\n\x1a\n"


# ── 1. 注册表派生 ──


class TestImageFactory:
    """单一来源派生：登记条目 → 实现类；get/list/未知拒绝"""

    def test_builtin_providers_registered_from_single_source(
        self, cg_dir_tmp
    ) -> None:
        """AVAILABLE_IMAGE_PROVIDERS 全部登记条目可在 factory 解析（唯一声明源派生）"""
        for key in IMAGE_PROVIDER_KEYS:
            assert key in ImageFactory.list_providers()
        assert set(IMAGE_PROVIDER_KEYS) <= set(ImageFactory.list_providers())

    def test_http_provider_class_derivation(self, cg_dir_tmp) -> None:
        """id=http 的条目 → HttpImageGen（a1111 与自定义 HTTP 同实现类）"""
        prov_a1111 = ImageFactory.get_provider("a1111", base_url="http://127.0.0.1:7860")
        prov_custom = ImageFactory.get_provider("custom-http", base_url="http://127.0.0.1:9999")
        assert isinstance(prov_a1111, HttpImageGen)
        assert isinstance(prov_custom, HttpImageGen)
        assert isinstance(prov_a1111, BaseImageGen)
        # base_url 透传（构造即校验缺端点）
        assert prov_a1111.base_url == "http://127.0.0.1:7860"

    def test_local_provider_class_derivation(self, cg_dir_tmp) -> None:
        """id=local → LocalImageGen（零网络零 Key）"""
        prov = ImageFactory.get_provider("local")
        assert isinstance(prov, LocalImageGen)

    def test_unknown_provider_rejected(self, cg_dir_tmp) -> None:
        """未登记 Provider → ProviderNotSupportedError（领域异常，非 ValueError）"""
        with pytest.raises(ProviderNotSupportedError):
            ImageFactory.get_provider("not-a-provider")

    def test_provider_id_and_requires_key_lookup(self, cg_dir_tmp) -> None:
        """派生元数据：协议 id 与 requires_key 查找（本地优先默认无需 Key）"""
        assert image_provider_id("a1111") == "http"
        assert image_provider_id("local") == "local"
        assert image_provider_requires_key("local") is False
        assert image_provider_requires_key("a1111") is False
        with pytest.raises(KeyError):
            image_provider_id("nope")
        with pytest.raises(KeyError):
            image_provider_requires_key("nope")

    def test_params_validation(self, cg_dir_tmp) -> None:
        """ImageGenParams 越界「拒」：空 prompt / 超界尺寸"""
        with pytest.raises(ValidationError):
            ImageGenParams(prompt="")
        with pytest.raises(ValidationError):
            ImageGenParams(prompt="x", width=8)  # < 32
        with pytest.raises(ValidationError):
            ImageGenParams(prompt="x", height=4096)  # > 2048
        assert ImageGenParams(prompt="一只猫").prompt == "一只猫"


# ── 2. 缺 Key 错误映射 ──


class TestImageAuth:
    """requires_key Provider 缺 Key → ImageAuthError（明确报错，不影响对话）"""

    def test_resolve_missing_key_raises_auth_error(self, cg_dir_tmp, monkeypatch) -> None:
        """requires_key=True 的 Provider 且 Key 缺失 → ImageAuthError（通过临时登记条目验证）"""
        from backend.app.services.image import model_data as image_model_data

        monkeypatch.setitem(
            image_model_data.AVAILABLE_IMAGE_PROVIDERS,
            "providers",
            image_model_data.AVAILABLE_IMAGE_PROVIDERS["providers"]
            + [{"key": "keyed-provider", "id": "local", "name": "需 Key 测试", "requires_key": True}],
        )
        # IMAGE_PROVIDER_KEYS 为模块级派生常量（import 时固化），需同步替换
        monkeypatch.setattr(
            image_model_data, "IMAGE_PROVIDER_KEYS",
            image_model_data.IMAGE_PROVIDER_KEYS + ["keyed-provider"],
        )
        # 强制重建派生缓存（测试隔离：恢复原缓存键集合）
        before = set(ImageFactory.list_providers())
        ImageFactory._builtins_loaded = False
        ImageFactory._providers = {}
        try:
            ImageFactory.register("keyed-provider", LocalImageGen)
            with pytest.raises(ImageAuthError, match="未配置"):
                resolve_image("keyed-provider")
        finally:
            ImageFactory._builtins_loaded = False
            ImageFactory._providers = {k: v for k, v in ImageFactory._providers.items() if k in before}

    def test_builtin_local_resolves_without_key(self, cg_dir_tmp) -> None:
        """本地优先后端无需 Key：resolver 直接给出可生成实例（缺 Key 不影响对话主流程）"""
        provider, backend = resolve_image("local")
        assert provider == "local"
        assert isinstance(backend, LocalImageGen)

    def test_auth_error_mapped_to_401(self, cg_dir_tmp) -> None:
        """缺 Key 错误映射：ImageAuthError → 401 + 明确消息"""
        err = ImageAuthError("未配置 keyed-provider API Key")
        status, message = error_mapping.image_error_response(err)
        assert status == 401
        assert "未配置" in message


# ── 3. 响应畸形 / 超时 / 连接失败 ──


class TestHttpImageBackend:
    """A1111 后端错误语义（假客户端注入）+ happy path"""

    def gen(self, base_url: str = "http://127.0.0.1:7860") -> HttpImageGen:
        return HttpImageGen(base_url=base_url)

    async def test_missing_base_url_rejected_at_construction(self, cg_dir_tmp) -> None:
        """HTTP 后端未配置端点地址 → 构造即 ImageConnectionError（明确错误）"""
        with pytest.raises(ImageConnectionError, match="端点"):
            HttpImageGen(base_url=None)

    async def test_txt2img_url_contract(self, cg_dir_tmp) -> None:
        """端点 URL = base_url 去尾斜杠 + /sdapi/v1/txt2img（A1111 契约）"""
        assert self.gen("http://x:7860/")._txt2img_url() == "http://x:7860/sdapi/v1/txt2img"

    async def test_happy_path_decodes_and_saves_local(
        self, cg_dir_tmp, monkeypatch
    ) -> None:
        """核心契约 5：{images:[base64]} → 落盘本地 + PNG magic + 尺寸/类型"""
        client = _FakeClient(result={"images": [base64.b64encode(_tiny_png_bytes()).decode("ascii")]})
        _patch_client(monkeypatch, client)

        result = await self.gen().generate(ImageGenParams(prompt="一只白猫"))

        assert isinstance(result, ImageResult)
        assert result.width == 512
        assert result.height == 512
        assert result.content_type == "image/png"
        assert _png_bytes_magic(result.url)
        # 请求体契约：A1111 txt2img payload（prompt/size/steps 透传）
        url, payload, headers = client.calls[0]
        assert url == "http://127.0.0.1:7860/sdapi/v1/txt2img"
        assert payload["prompt"] == "一只白猫"
        assert payload["width"] == 512
        assert payload["steps"] == 20

    async def test_api_key_sent_as_bearer(self, cg_dir_tmp, monkeypatch) -> None:
        """api_key 有值时附带 Authorization: Bearer 头"""
        client = _FakeClient(result={"images": [base64.b64encode(_tiny_png_bytes()).decode("ascii")]})
        _patch_client(monkeypatch, client)

        await HttpImageGen("http://x:7860", api_key="secret").generate(
            ImageGenParams(prompt="猫")
        )

        assert client.calls[0][2]["Authorization"] == "Bearer secret"

    async def test_missing_images_array_raises(
        self, cg_dir_tmp, monkeypatch
    ) -> None:
        """响应畸形：缺 images / 非列表 / 空数组 → ImageResponseError 明确错误"""
        for bad in ({}, {"images": "不是列表"}, {"images": []}, {"images": [1, 2]}):
            client = _FakeClient(result=bad)
            _patch_client(monkeypatch, client)
            with pytest.raises(ImageResponseError, match="畸形"):
                await self.gen().generate(ImageGenParams(prompt="猫"))

    async def test_invalid_base64_raises(self, cg_dir_tmp, monkeypatch) -> None:
        """响应畸形：images[0] 非合法 base64 → ImageResponseError"""
        client = _FakeClient(result={"images": ["!!!!not-base64!!!!"]})
        _patch_client(monkeypatch, client)

        with pytest.raises(ImageResponseError, match="base64"):
            await self.gen().generate(ImageGenParams(prompt="猫"))

    async def test_timeout_mapped_to_image_timeout(
        self, cg_dir_tmp, monkeypatch
    ) -> None:
        """核心契约 4：httpx 超时 → ImageTimeoutError（15s 守卫语义）"""
        client = _FakeClient(error=httpx.TimeoutException("timed out"))
        _patch_client(monkeypatch, client)

        with pytest.raises(ImageTimeoutError):
            await self.gen().generate(ImageGenParams(prompt="猫"))
        status, message = error_mapping.image_error_response(ImageTimeoutError("超时"))
        assert status == 504
        assert "超时" in message

    async def test_connection_error_mapped(self, cg_dir_tmp, monkeypatch) -> None:
        """连接失败/非 2xx → ImageConnectionError（502）"""
        client = _FakeClient(error=httpx.ConnectError("refused"))
        _patch_client(monkeypatch, client)

        with pytest.raises(ImageConnectionError):
            await self.gen().generate(ImageGenParams(prompt="猫"))


# ── 4. 本地文件后端 ──


class TestLocalImageBackend:
    """本地占位后端：确定性 + 落盘本地"""

    async def test_generate_writes_png_and_reproducible(self, cg_dir_tmp) -> None:
        """核心契约 6：占位 PNG 落盘本地 + 同 prompt 同字节（确定性可复现）"""
        backend = LocalImageGen()
        params = ImageGenParams(prompt="雪夜客栈", width=64, height=64)

        r1 = await backend.generate(params)
        r2 = await backend.generate(params)

        assert _png_bytes_magic(r1.url)
        assert r1.width == 64 and r1.height == 64
        assert r1.content_type == "image/png"
        with open(r2.url, "rb") as f2, open(r1.url, "rb") as f1:
            assert f2.read() == f1.read()  # 同 prompt → 同字节（可复现断言）

    async def test_different_prompt_different_image(self, cg_dir_tmp) -> None:
        """不同 prompt → 不同字节（颜色由 prompt 派生）"""
        backend = LocalImageGen()
        r1 = await backend.generate(ImageGenParams(prompt="猫", width=32, height=32))
        r2 = await backend.generate(ImageGenParams(prompt="狗", width=32, height=32))

        with open(r1.url, "rb") as f1, open(r2.url, "rb") as f2:
            assert f1.read() != f2.read()


# ── 5. resolver / 映射矩阵 ──


class TestImageResolverAndMapping:
    """resolve_image 收口 + image_error_response 全族映射"""

    def test_resolve_unknown_provider_rejected(self, cg_dir_tmp) -> None:
        """未登记 Provider → ProviderNotSupportedError"""
        with pytest.raises(ProviderNotSupportedError):
            resolve_image("nope")

    def test_resolve_http_without_base_url_rejected(self, cg_dir_tmp) -> None:
        """HTTP 类 Provider 无端点地址 → 构造即 ImageConnectionError（明确错误）"""
        with pytest.raises(ImageConnectionError):
            resolve_image("a1111")

    def test_mapping_matrix(self, cg_dir_tmp) -> None:
        """image_error_response 映射矩阵：auth 401 / timeout 504 固定文案 / 畸形 502"""
        assert error_mapping.image_error_response(ImageAuthError("auth"))[0] == 401
        status, msg = error_mapping.image_error_response(ImageTimeoutError("t"))
        assert status == 504 and msg == "图片生成请求超时，请检查后端后重试"
        assert error_mapping.image_error_response(ImageResponseError("畸形")) == (502, "畸形")
        assert error_mapping.image_error_response(ImageConnectionError("连接")) == (502, "连接")
        assert error_mapping.image_error_response(ImageError("基类"))[0] == 502