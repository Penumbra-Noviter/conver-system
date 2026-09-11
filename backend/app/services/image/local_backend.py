"""
本地文件图片后端（CG-1 — 零网络零 Key 的最小后端）

用途：无外部生成后端时的 CG 链路可用形态 / 测试 / 开发冒烟。generate 生成
确定性纯色占位 PNG（颜色由 prompt 派生——同 prompt 同图，可复现断言友好），
落盘数据目录 cg/ 子目录后返回本地文件路径。
"""

from __future__ import annotations

import io
import random

from PIL import Image, ImageDraw

from backend.app.services.image.base import BaseImageGen, ImageGenParams, ImageResult
from backend.app.services.image.storage import save_image_bytes

__all__ = ["LocalImageGen"]


def _placeholder_png(prompt: str, width: int, height: int) -> bytes:
    """生成确定性纯色占位 PNG（颜色/图形由 prompt 哈希派生，同 prompt 同字节）"""
    rng = random.Random(prompt)
    color = (rng.randint(40, 215), rng.randint(40, 215), rng.randint(40, 215))
    image = Image.new("RGB", (width, height), color)
    draw = ImageDraw.Draw(image)
    # 中心圆 + 对角线，便于肉眼区分不同 prompt 的占位图
    accent = (255 - color[0], 255 - color[1], 255 - color[2])
    radius = min(width, height) // 4
    cx, cy = width // 2, height // 2
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=accent, width=3)
    draw.line((0, 0, width, height), fill=accent, width=3)
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


class LocalImageGen(BaseImageGen):
    """本地文件后端：确定性占位 PNG，零网络零 Key（requires_key=False）"""

    async def generate(self, params: ImageGenParams) -> ImageResult:
        """生成占位 PNG 并落盘本地

        Args:
            params: 生成参数（prompt 决定颜色/图形；width/height 决定尺寸）

        Returns:
            图片结果（url = 本地文件路径）
        """
        raw = _placeholder_png(params.prompt, params.width, params.height)
        url = save_image_bytes(raw, width=params.width, height=params.height)
        return ImageResult(
            url=url,
            width=params.width,
            height=params.height,
            content_type="image/png",
        )