"""
模拟器 API 路由

POST /api/simulators/import   — 单文件 HTML 游戏导入（multipart 字段名 `file`）
POST /api/simulators/generate — 从文本描述 AI 生成游戏
POST /api/simulators/reprobe  — 重新识别已有游戏（修正 type/config/endpointMode）

导入接口契约（spec T-02 决策 4，与工单 04 前端共用锚点，定版）：
    成功 200：{ ok: true, game: { id, file, name, type, config? }, renamed, warnings }
    校验失败 400（非 .html / 超 5MB / 空文件）；重复 409（SHA-256 命中，
    detail 含「已存在」）；缺 file 字段 422（FastAPI 校验）
    warnings 键集：eval / document.cookie / cross-origin-fetch
    （常量单源 simulator_store.SUSPICIOUS_PATTERNS，前端映射中文文案）

生成接口契约：
    请求：{ "description": "世界观描述", "title": "游戏标题（可选）" }
    成功 200：{ ok: true, game: { id, file, name, type, source: "generated" }, retries }
    校验失败 422：{ ok: false, errors: [{field, message}], suggestion, retries }
    重复 409（SHA-256 与现存文件重复，detail 含「已存在」）
    LLM 错误 401/429/504/502：走 LLMError 统一异常处理

重新识别接口契约（2026-08-26：导入类型探测补强 + 存量修正入口）：
    请求：{ "id": "游戏条目 id" }
    成功 200：{ ok: true, game: { id, file, name, type, config?, endpointMode? } }
    条目不存在 404（detail 含「不存在」）；条目 file 对应文件缺失 404
    （detail 含「文件」）；请求体缺 id 422（FastAPI 校验）
    语义：重读落盘 HTML → probe_config（三层探测）+ probe_endpoint_mode →
    更新 manifest 条目 type/config/endpointMode（原子写，其他字段原样保留）

同源 API 反代契约（2026-08-28 CORS 修复）：
    [GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD] /api/simulators/proxy/{path:path}
    语义：模拟器游戏在 iframe 内用浏览器 fetch 直连第三方 OpenAI 兼容 API
    时受 CORS 限制（目标不返回 Access-Control-Allow-Origin 即被拦截）。
    本端点把游戏对 /api/simulators/proxy/<path> 的请求转发到主应用配置的
    OpenAI 兼容 base（setting_service.credentials().endpoint 的主机 + <path>），
    服务端发起无 CORS，实现「游戏同源、后端代打」。
    关键契约：
        - path 为完整剩余路径（如 v1/chat/completions、v1/models），原样拼到
          real_endpoint 的 scheme://netloc 之后（real_endpoint 自身 path 不参与
          拼接——前端注入的代理 endpoint 已把 real_endpoint 的 path 段写入
          path，见 key-injector toProxyEndpoint）；
        - key 由后端注入（Authorization: Bearer <credentials().key>），忽略
          客户端可能自带的 Authorization（key 不依赖游戏侧，且不信任游戏）；
        - 透传流式响应（StreamingResponse + resp.aiter_bytes()），兼容 SSE；
        - 未配置 OpenAI 兼容端点 → 503（detail 明确文案，不静默）。

分层约定：本路由仅做 HTTP 映射（状态码 + 响应形状）；校验 / 文件读写 /
探测 / manifest 注册全部委托 services/simulator_store 导入族；生成逻辑
委托 services/game_generator；代理目标解析为纯函数 `_build_proxy_target` /
`_proxy_headers`（可单测，不依赖网络）。数据目录在请求期解析（不缓存于
import 期，测试可 monkeypatch CONVER_DATA_DIR 环境变量）。
"""

from __future__ import annotations

from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.services import data_dir as data_dir_service
from backend.app.services import setting as setting_service
from backend.app.services import simulator_store
from backend.app.services.game_generator import (
    GenerateResult,
    generate_game,
)

__all__ = ["router"]

router = APIRouter(prefix="/api/simulators", tags=["模拟器导入"])


class GenerateRequest(BaseModel):
    """AI 生成游戏请求"""
    description: str = Field(..., min_length=1, max_length=10000,
                             description="世界观描述文本（1-10000 字符）")
    title: str | None = Field(default=None, max_length=100,
                               description="游戏标题（可选，用于生成文件名）")


class ReprobeRequest(BaseModel):
    """重新识别游戏请求"""
    id: str = Field(..., min_length=1, max_length=200,
                    description="manifest 游戏条目 id")


# ══════════════════════════════════════════════════
# 同源 API 反代（CORS 修复 2026-08-28）— 纯函数可单测
# ══════════════════════════════════════════════════

#: 转发时剥除的 hop-by-hop / 重写头（host 由 httpx 重建；content-length 由
#: httpx 按 body 重建；authorization 由后端统一注入；connection/accept-encoding
#: 属连接层，不转发）
_PROXY_SKIP_HEADERS = frozenset({
    "host", "content-length", "authorization", "connection", "accept-encoding",
})


def _build_proxy_target(real_endpoint: str, path: str) -> str:
    """把 real_endpoint 的 scheme://netloc 与剩余 path 拼成代理目标 URL。

    real_endpoint 自身 path 段不参与拼接（前端注入的代理 endpoint 已把该段
    写入 path —— 见 key-injector toProxyEndpoint），避免 /v1 重复。
    @param real_endpoint - 主应用 OpenAI 兼容 base（如 https://host/v1）
    @param path - 路由剩余路径（如 v1/chat/completions、v1/models）
    @returns 完整目标 URL（如 https://host/v1/chat/completions）
    @raises ValueError - real_endpoint 无有效 netloc（scheme 缺失但主机可解析，
      则 scheme 回退 https）
    """
    parsed = urlparse(real_endpoint)
    netloc = parsed.netloc
    if not netloc:
        raise ValueError(f"OpenAI 兼容端点缺少主机: {real_endpoint!r}")
    scheme = parsed.scheme or "https"
    return f"{scheme}://{netloc}/{path.lstrip('/')}"


def _proxy_headers(request_headers, api_key: str) -> dict[str, str]:
    """组装转发 headers：剥除 hop-by-hop 与客户端 Authorization，后端注入 key。

    不转发客户端 Authorization —— key 由主应用统一注入（游戏侧自填的占位 key
    不进入上游，也不被信任）；其余头原样透传（含 Accept 等，保持上游协商）。
    """
    headers: dict[str, str] = {}
    for key, value in request_headers.items():
        if key.lower() not in _PROXY_SKIP_HEADERS:
            headers[key] = value
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    return headers


@router.api_route(
    "/proxy/{path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
)
async def simulator_api_proxy(
    path: str,
    request: Request,
    db: Session = Depends(get_db),
) -> StreamingResponse:
    """模拟器同源 API 反代：转发游戏对第三方 OpenAI 兼容 API 的请求（CORS 修复）。

    目标 = 主应用配置的 OpenAI 兼容 base 的 scheme://netloc + path；key 由后端
    注入；流式响应透传（兼容 SSE 聊天流）。未配置端点 → 503。
    """
    creds = setting_service.credentials(db)
    real_endpoint = (creds.get("endpoint") or "").strip()
    if not real_endpoint:
        raise HTTPException(status_code=503, detail="未配置 OpenAI 兼容端点，无法代理模拟器 API")
    try:
        target = _build_proxy_target(real_endpoint, path)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail="OpenAI 兼容端点无效，无法代理模拟器 API") from exc

    headers = _proxy_headers(request.headers, creds.get("key") or "")
    body = await request.body()
    client = httpx.AsyncClient(timeout=60.0)
    req = client.build_request(request.method, target, headers=headers, content=body)
    resp = await client.send(req, stream=True)
    out_headers = {
        key: value for key, value in resp.headers.items() if key.lower() != "content-length"
    }
    return StreamingResponse(resp.aiter_bytes(), status_code=resp.status_code, headers=out_headers)


@router.post("/import")
async def import_simulator(file: UploadFile = File(...)) -> dict:
    """导入单文件 HTML 模拟器游戏（multipart 字段名 file；返回契约见模块 docstring）。

    读取守卫：最多读 5MB+1 字节，超限即拒绝（不整读超大文件，防内存膨胀）。
    领域异常（校验失败 / 重复）本地映射 400/409 及明确文案；落盘失败
    （OSError，如数据目录不可写）保持 500 语义不静默吞掉。
    """
    content = await file.read(simulator_store.MAX_IMPORT_BYTES + 1)
    try:
        result = simulator_store.import_game(
            data_dir_service.simulators_dir(), file.filename or "", content
        )
    except simulator_store.SimulatorImportError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except simulator_store.SimulatorDuplicateError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "game": result.game, "renamed": result.renamed, "warnings": result.warnings}


@router.post("/reprobe")
async def reprobe_simulator(body: ReprobeRequest) -> dict:
    """重新识别已有游戏：重读落盘 HTML → 三层探测（type/config）+ 端点口径
    （endpointMode）→ 原子更新 manifest 条目（其他字段原样保留）。

    修正入口（2026-08-26 存量补强）：导入时误判为 local 的 AI 驱动游戏
    （引擎系游戏控件在 JS 模板字符串内、cfg- 约定不符等）由前端卡片
    「重新识别」按钮调用。条目不存在 → 404；条目 file 落盘文件缺失 →
    404（数据目录损坏态，明确文案不静默）。
    """
    sim_dir = data_dir_service.simulators_dir()
    manifest = simulator_store._read_manifest_or_rebuild(sim_dir)
    target = next((e for e in manifest.get("simulators", []) if e.get("id") == body.id), None)
    if target is None:
        raise HTTPException(status_code=404, detail=f"游戏不存在：{body.id}")
    game_file = str(target.get("file") or "")
    if not game_file:
        raise HTTPException(status_code=404, detail=f"游戏文件缺失：{body.id}")
    html_path = sim_dir / game_file
    if not html_path.is_file():
        raise HTTPException(status_code=404, detail=f"游戏文件缺失：{game_file}")
    content = html_path.read_bytes()
    text = content.decode("utf-8", errors="replace")
    game_type, config = simulator_store.probe_config(text)
    endpoint_mode = simulator_store.probe_endpoint_mode(text)
    updates: dict = {"type": game_type}
    if config is not None:
        updates["config"] = config
    else:
        updates.pop("config", None)  # local 时不保留旧 config（降级清空）
    if endpoint_mode is not None:
        updates["endpointMode"] = endpoint_mode
    else:
        updates.pop("endpointMode", None)  # 推断不到时清空旧口径，回落后端缺省语义
    updated = simulator_store.update_manifest_entry(sim_dir, body.id, **updates)
    return {"ok": True, "game": updated}


@router.post("/generate")
async def generate_simulator(body: GenerateRequest, db: Session = Depends(get_db)) -> dict:
    """AI 游戏生成：从用户提供的世界观描述生成可运行的 HTML 模拟器游戏。

    流程：LLM 填充种子模板 → 校验闸门（6 项检查）→ 通过后落盘并注册 manifest。
    校验失败自动重试（最多 3 次），返回结构化错误与修正建议。
    """
    try:
        result: GenerateResult = await generate_game(
            db=db,
            description=body.description,
            title=body.title,
        )
    except simulator_store.SimulatorDuplicateError as exc:
        # SHA-256 内容与现存文件重复 → 409（与导入路由同语义，detail 含「已存在」）
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    if result.ok:
        return {"ok": True, "game": result.game, "retries": result.retries}

    # 校验失败 — 返回结构化错误（422 语义：校验不通过）
    raise HTTPException(
        status_code=422,
        detail={
            "ok": False,
            "errors": [{"field": e.field, "message": e.message} for e in (result.errors or [])],
            "suggestion": result.suggestion,
            "retries": result.retries,
        },
    )
