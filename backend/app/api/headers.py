"""
附件下载响应头单一 helper（B4 收口）

三处导出路由（对话 JSON / 对话 Markdown / 角色卡）的 Content-Disposition
统一由 `build_content_disposition` 构造：ASCII 兜底 + RFC 5987 filename* 单点实现。

- HTTP header 只支持 latin-1 → 中文文件名无法直接落 header，
  `filename=` 仅放 ASCII 兜底名，完整名走 RFC 5987 `filename*=UTF-8''`（百分号编码）。
- 编码采用最严格安全参数（safe=''）：空格 / 斜杠 / 中文一律编码，
  避免文件名中的斜杠原样进入 header。
"""

from __future__ import annotations

from urllib.parse import quote

__all__ = ["build_content_disposition"]


def build_content_disposition(ascii_filename: str, utf8_filename: str) -> str:
    """构造附件下载 Content-Disposition（ASCII 兜底 + RFC 5987 filename*）

    Args:
        ascii_filename: 纯 ASCII 兜底文件名（落 `filename="..."`，必须可 latin-1 编码）
        utf8_filename: 完整文件名（落 `filename*=UTF-8''...`，UTF-8 百分号编码，
            空格 / 斜杠 / 非 ASCII 字符一律编码）

    Returns:
        `attachment; filename="..."; filename*=UTF-8''...` 形式的 header 值
    """
    return (
        f'attachment; filename="{ascii_filename}"; '
        f"filename*=UTF-8''{quote(utf8_filename, safe='')}"
    )
