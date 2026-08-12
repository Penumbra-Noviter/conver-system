"""
统一错误响应 exception handler（ARC-10 B3）

领域异常族（DomainError）与 LLM 异常族（LLMError）在应用级统一映射为
JSON 响应（状态码 + detail 与现状逐字一致），路由层不再各自 try/except：

- 领域族：ConversationNotFoundError→404、ApiKeyMissingError→400、
  ProviderNotSupportedError→400、CardFormatError→422（含支持格式说明）、
  CardValidationError→422（纯原因）、DocParseError→422（纯原因）
- LLM 族：委托 services/chat.py::chat_error_response 映射（401/429/504/400/502；
  防御性注册——请求路径上的 LLM 错误实际先经 complete_chat 显式 raise
  HTTPException 并携带 provider 上下文）
- test-connection 不走 LLM 族统一映射（400 + 可读原因语义保留在路由层，见 D-B3-1）

由 main.py 注册两枚 handler（Starlette 按异常 MRO 匹配子类，注册基类即覆盖全族）；
HTTPException 与请求校验错误（RequestValidationError）仍由 FastAPI 原生处理，不受影响。
"""

from __future__ import annotations

from fastapi import Request, status
from fastapi.responses import JSONResponse

from backend.app.services import chat as chat_service
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    CardFormatError,
    CardValidationError,
    ConversationNotFoundError,
    DocParseError,
    DomainError,
    ProviderNotSupportedError,
)
from backend.app.services.llm.errors import LLMError

__all__ = ["domain_error_handler", "llm_error_handler"]

#: 角色卡导入失败时的支持格式说明（随 B1 之前的路由层迁入，422 detail 拼接用）
_IMPORT_FORMAT_HINT = (
    "支持格式：SillyTavern V2 角色卡（spec=chara_card_v2）、data 信封、"
    "裸 data（含 name 字段）、V1 旧卡（含 char_name 字段）；"
    "也可改用「创建角色」向导（智能导入/模板/手动）"
)


def _domain_error_response(exc: DomainError) -> tuple[int, str]:
    """领域异常 → (HTTP 状态码, detail)

    映射与 services/chat.py::chat_error_response 的领域分支同表
    （404/400/400），并叠加角色导入/文档解析的 422 类；detail 逐字保持现状。

    Args:
        exc: 待映射的领域异常

    Returns:
        (HTTP 状态码, 用户可见消息)
    """
    if isinstance(exc, ConversationNotFoundError):
        return status.HTTP_404_NOT_FOUND, str(exc)
    if isinstance(exc, (ApiKeyMissingError, ProviderNotSupportedError)):
        return status.HTTP_400_BAD_REQUEST, str(exc)
    if isinstance(exc, CardFormatError):
        return status.HTTP_422_UNPROCESSABLE_CONTENT, f"导入失败：{exc}。{_IMPORT_FORMAT_HINT}"
    if isinstance(exc, CardValidationError):
        return status.HTTP_422_UNPROCESSABLE_CONTENT, f"导入失败：{exc}"
    if isinstance(exc, DocParseError):
        return status.HTTP_422_UNPROCESSABLE_CONTENT, str(exc)
    # 未知 DomainError 子类（防御性兜底；异常层次冻结，当前无生产者）
    return status.HTTP_400_BAD_REQUEST, str(exc)


async def domain_error_handler(request: Request, exc: DomainError) -> JSONResponse:
    """领域异常统一映射（404/400/422，detail 与现状逐字）

    Args:
        request: 触发异常的请求（handler 不读取其内容）
        exc: 待映射的领域异常

    Returns:
        携带状态码与 detail 的 JSON 响应
    """
    status_code, detail = _domain_error_response(exc)
    return JSONResponse(status_code=status_code, content={"detail": detail})


async def llm_error_handler(request: Request, exc: LLMError) -> JSONResponse:
    """LLM 异常统一映射（401/429/504/400/502，经 services/chat.py::chat_error_response）

    防御性注册：请求路径上的 LLM 错误实际先经 complete_chat 显式 raise
    HTTPException（携带 provider 上下文），此处 provider 未知；注册兜底保证
    绕过完整回合的调用路径仍得到一致映射。

    Args:
        request: 触发异常的请求（handler 不读取其内容）
        exc: 待映射的 LLM 异常

    Returns:
        携带状态码与 detail 的 JSON 响应
    """
    status_code, message = chat_service.chat_error_response(exc)
    return JSONResponse(status_code=status_code, content={"detail": message})
