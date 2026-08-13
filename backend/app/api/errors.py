"""
统一错误响应 exception handler（ARC-10 B3）

领域异常族（DomainError）与 LLM 异常族（LLMError）在应用级统一映射为
JSON 响应（状态码 + detail 与现状逐字一致），路由层不再各自 try/except：

- 领域族：委托 services/error_mapping.py::domain_error_response 单一入口
  （404/400/422 全家族 + 未知领域异常 400 兜底；映射表不再双份维护，
  ARC10-4「两路并存」合并完成；CharacterNotFoundError→404 随 BE-2 并入）
- LLM 族：委托 services/chat.py::chat_error_response 映射（401/429/504/400/502；
  防御性注册——请求路径上的 LLM 错误实际先经 complete_chat 显式 raise
  HTTPException 并携带 provider 上下文）
- test-connection 不走 LLM 族统一映射（400 + 可读原因语义保留在路由层，见 D-B3-1）

由 main.py 注册两枚 handler（Starlette 按异常 MRO 匹配子类，注册基类即覆盖全族）；
HTTPException 与请求校验错误（RequestValidationError）仍由 FastAPI 原生处理，不受影响。
"""

from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse

from backend.app.services import chat as chat_service
from backend.app.services.error_mapping import domain_error_response
from backend.app.services.exceptions import DomainError
from backend.app.services.llm.errors import LLMError

__all__ = ["domain_error_handler", "llm_error_handler"]

async def domain_error_handler(request: Request, exc: DomainError) -> JSONResponse:
    """领域异常统一映射（404/400/422，detail 与现状逐字；委托服务层单一入口）

    Args:
        request: 触发异常的请求（handler 不读取其内容）
        exc: 待映射的领域异常

    Returns:
        携带状态码与 detail 的 JSON 响应
    """
    status_code, detail = domain_error_response(exc)
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
