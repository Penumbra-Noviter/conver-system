"""
图片生成异常定义（CG-1，与 LLM 异常族同构）

Service/Provider 层捕获并抛出，路由层经 error_mapping.image_error_response
统一映射为 HTTP 状态码（401/504/502/400）。
"""

from __future__ import annotations

__all__ = [
    "ImageError",
    "ImageAuthError",
    "ImageConnectionError",
    "ImageResponseError",
    "ImageTimeoutError",
]


class ImageError(Exception):
    """图片生成调用基类异常"""

    def __init__(self, message: str, original_error: Exception | None = None):
        self.original_error = original_error
        super().__init__(message)


class ImageAuthError(ImageError):
    """图片 Provider 凭据缺失 / 无效"""


class ImageConnectionError(ImageError):
    """连接失败（端点未配置 / 网络不可达 / HTTP 非 2xx）"""


class ImageResponseError(ImageError):
    """上游响应畸形（缺 images / 非列表 / 非法 base64 / 非 2xx 结构错误）"""


class ImageTimeoutError(ImageError):
    """请求超时（15 秒守卫语义）"""