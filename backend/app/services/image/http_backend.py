"""
HTTP 端点图片后端（CG-1 — A1111 兼容 / 自定义 HTTP）

A1111 兼容端点（Stable Diffusion WebUI）：POST {base_url}/sdapi/v1/txt2img，
body {prompt, negative_prompt, width, height, steps} → {images: [base64]}。
自定义 HTTP 端点按 A1111 同构请求（txt2img 协议是事实标准）。

「本地优先」：拉取到的图片 base64 解码后落盘数据目录 cg/ 子目录，返回本地
文件路径（ImageResult.url 本地文件路径，非远程地址）。

传输 seam（测试注入）：模块级 `_HTTP_CLIENT_FACTORY`（默认 httpx.AsyncClient）
——测试可替换为假客户端（连接失败/非 2xx → ImageConnectionError、
超时 → ImageTimeoutError）；**15 秒超时守卫语义**（复用 fetch-seam 15s 契约）。
响应畸形（缺 images / 非列表 / 非法 base64）→ ImageResponseError 明确错误。
"""

from __future__ import annotations

import base64
import binascii

import httpx

from backend.app.services.image.base import BaseImageGen, ImageGenParams, ImageResult
from backend.app.services.image.errors import (
    ImageConnectionError,
    ImageResponseError,
    ImageTimeoutError,
)
from backend.app.services.image.storage import save_image_bytes

__all__ = ["HttpImageGen"]

#: 图片生成 HTTP 请求超时（15 秒守卫语义，与 fetch-seam 同契约）
HTTP_TIMEOUT_SECONDS = 15.0

#: httpx 客户端工厂（测试 seam：替换为假客户端以注入失败/畸形响应）
_HTTP_CLIENT_FACTORY = httpx.AsyncClient


class HttpImageGen(BaseImageGen):
    """A1111 兼容 HTTP 图片后端（txt2img）"""

    def __init__(
        self,
        base_url: str | None = None,
        *,
        api_key: str | None = None,
    ):
        super().__init__(base_url, api_key=api_key)
        if not base_url:
            raise ImageConnectionError("HTTP 图片后端未配置端点地址（base_url）")

    def _txt2img_url(self) -> str:
        """A1111 txt2img 端点 URL（base_url 去尾斜杠 + /sdapi/v1/txt2img）"""
        return self.base_url.rstrip("/") + "/sdapi/v1/txt2img"

    async def _post_json(self, url: str, payload: dict) -> dict:
        """POST JSON → 响应 JSON（15s 超时守卫 + 连接/超时错误映射）

        传输 seam：测试替换 `_HTTP_CLIENT_FACTORY` 为假客户端以注入
        超时/连接失败（httpx 异常族映射为 Image 异常族）。

        Args:
            url: 端点 URL
            payload: JSON body

        Returns:
            响应 JSON dict

        Raises:
            ImageTimeoutError: 请求超时（15 秒）
            ImageConnectionError: 连接失败 / HTTP 非 2xx
        """
        headers = {}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        try:
            async with _HTTP_CLIENT_FACTORY(timeout=HTTP_TIMEOUT_SECONDS) as client:
                resp = await client.post(url, json=payload, headers=headers)
                resp.raise_for_status()
                return resp.json()
        except httpx.TimeoutException as e:
            raise ImageTimeoutError(
                f"图片生成请求超时（{HTTP_TIMEOUT_SECONDS} 秒）：{url}"
            ) from e
        except httpx.HTTPError as e:
            raise ImageConnectionError(f"图片后端连接失败: {e}") from e

    async def generate(self, params: ImageGenParams) -> ImageResult:
        """调用 A1111 txt2img 生成并落盘本地

        Args:
            params: 生成参数（prompt/negative_prompt/width/height/steps）

        Returns:
            图片结果（url = 本地文件路径，宽高与请求一致）

        Raises:
            ImageConnectionError: 端点未配置 / 连接失败 / 非 2xx
            ImageTimeoutError: 请求超时
            ImageResponseError: 响应畸形（缺 images / 非列表 / 非法 base64）
        """
        payload = {
            "prompt": params.prompt,
            "negative_prompt": params.negative_prompt,
            "width": params.width,
            "height": params.height,
            "steps": params.steps,
        }
        data = await self._post_json(self._txt2img_url(), payload)

        images = data.get("images")
        if not isinstance(images, list) or not images or not isinstance(images[0], str):
            raise ImageResponseError(
                "图片后端响应畸形：缺少 images 数组（A1111 txt2img 返回 {images: [base64]}）"
            )
        try:
            raw = base64.b64decode(images[0], validate=True)
        except (binascii.Error, ValueError) as e:
            raise ImageResponseError(
                "图片后端响应畸形：images[0] 非有效 base64"
            ) from e

        url = save_image_bytes(
            raw, width=params.width, height=params.height, content_type="image/png"
        )
        return ImageResult(
            url=url,
            width=params.width,
            height=params.height,
            content_type="image/png",
        )