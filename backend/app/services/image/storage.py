"""
CG 图片本地落盘（CG-1：生成结果 → 数据目录 cg/ 下的本地文件）

「本地优先」：HTTP 后端拉取/本地后端生成的图片一律落盘数据目录 cg/ 子目录，
返回本地文件路径（CG-2 cg_images.url 契约：本地文件路径或 HTTP URL）。
"""

from __future__ import annotations

import datetime
import uuid

from backend.app.services.data_dir import cg_dir

__all__ = ["save_image_bytes"]


def save_image_bytes(
    raw: bytes,
    *,
    width: int | None = None,
    height: int | None = None,
    content_type: str = "image/png",
) -> str:
    """把图片字节落盘数据目录 cg/ 子目录，返回本地文件路径字符串

    文件名：`cg_{YYYYmmdd_HHMMSS}_{微秒}_{uuid4前8位}_{宽}x{高}.png`——
    时间戳 + uuid 短后缀保证唯一（同微秒内连续两次调用不覆盖，Falsify 通
    flaky 测试实证：时间戳+微秒命名在同微秒写入会互相覆盖）；目录不存在时
    自动创建（mkdir parents）。

    Args:
        raw: 图片原始字节（PNG/JPEG 等）
        width: 图片宽（文件名标注用，未知可省）
        height: 图片高（文件名标注用，未知可省）
        content_type: MIME 类型（决定扩展名；png/jpeg 支持）

    Returns:
        本地文件路径（字符串，绝对路径）
    """
    extension = ".jpg" if content_type == "image/jpeg" else ".png"
    now = datetime.datetime.now()
    dims = f"_{width}x{height}" if (width and height) else ""
    unique = uuid.uuid4().hex[:8]
    target = cg_dir() / f"cg_{now:%Y%m%d_%H%M%S}_{now.microsecond}_{unique}{dims}{extension}"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(raw)
    return str(target)