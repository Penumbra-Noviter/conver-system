"""
ARC-10 T-15（B3）统一错误响应 exception handler 测试

覆盖：
    1. 领域异常族 wire 映射（直调 handler 函数）：404 / 400 / 400 + 三种 422
       （CardFormat 含 hint 拼接 / CardValidation 纯原因 / DocParse 纯原因），detail 逐字
    2. LLM 异常族 wire 映射（直调 handler 函数）：401 / 429 / 504 / 400 / 502
       （防御性注册：401 为无 provider 模板形态，请求路径实际经 complete_chat 显式 raise）
    3. 应用级注册（TestClient wire）：真实路由抛领域异常 → 状态码 + JSON detail 逐字；
       HTTPException 不被吞（FastAPI 原生 404 / 请求校验 422 不受影响）；并发调用互不干扰
    4. test-connection 400 语义：provider 校验异常经统一 handler → 400 + 逐字 detail
       （不走 LLM 族 401/429/504 映射）
    5. SSE 流不受 handler 影响：流式路由领域错误 → 404 JSON（在流构造前由 handler 生效；
       LLM 错误帧仍由服务层 stream_reply 产出，见 test_p35.py）
    6. 真实 app（main.py）注册生效：统一 handler 装配于生产应用（wire 单测 + import 级执行）
    7. characters CRUD 路由 wire 直测（本工单涉改文件覆盖率门 G2：路由层公开行为钉死）
    8. CharacterNotFoundError 映射（BE-2 新增异常 → 404 逐字，不落未知子类兜底）
    9. conversations CRUD 路由 wire 直测（BE-2：404 逐字 + 正常路径 + 删除/清空边界 +
       消息历史正常路径；独立 conversation_wire_app fixture，不动既有 wire_app）
    10. 三处导出附件头统一（BE-2：ASCII 兜底 + RFC 5987 并存；导出哨兵 404 逐字钉死）

依赖：pytest + SQLite 内存库（conftest.db_session）+ TestClient（httpx）。
不构造真实网络请求。
"""

from __future__ import annotations

import asyncio
import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from starlette.requests import Request

from backend.app.api.errors import (
    _IMPORT_FORMAT_HINT,
    domain_error_handler,
    llm_error_handler,
)
from backend.app.api.routes import chat as chat_route
from backend.app.api.routes import characters as characters_route
from backend.app.api.routes import conversations as conversations_route
from backend.app.api.routes import messages as messages_route
from backend.app.api.routes import settings as settings_route
from backend.app.database import get_db
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, Role
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    CardFormatError,
    CardValidationError,
    CharacterNotFoundError,
    ConversationNotFoundError,
    DocParseError,
    DomainError,
    ProviderNotSupportedError,
)
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)

__all__: list[str] = []


def _request() -> Request:
    """最小 ASGI scope 的请求桩（handler 不读取请求内容，仅供签名直调）"""
    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/",
            "headers": [],
            "query_string": b"",
            "server": ("testserver", 80),
            "client": ("testclient", 123),
            "scheme": "http",
            "root_path": "",
            "http_version": "1.1",
        }
    )


def _call_handler(handler, exc: Exception) -> tuple[int, str]:
    """直调 handler 函数，返回 (status_code, detail)（JSONResponse 契约）"""
    resp = asyncio.run(handler(_request(), exc))
    return resp.status_code, json.loads(resp.body)["detail"]


# ── 1. 领域异常族 wire 映射（直调 handler）──


class TestDomainErrorHandler:
    """领域异常族：状态码 + detail 与现状逐字（404 / 400 / 400 + 三种 422）"""

    def test_conversation_not_found_404(self) -> None:
        """ConversationNotFoundError → 404 + str(e) 逐字"""
        exc = ConversationNotFoundError("对话不存在")
        assert _call_handler(domain_error_handler, exc) == (404, "对话不存在")

    def test_api_key_missing_400(self) -> None:
        """ApiKeyMissingError → 400 + str(e) 逐字"""
        exc = ApiKeyMissingError("未配置 claude API Key，请在设置中填写")
        assert _call_handler(domain_error_handler, exc) == (400, str(exc))

    def test_provider_not_supported_400(self) -> None:
        """ProviderNotSupportedError → 400 + str(e) 逐字"""
        exc = ProviderNotSupportedError("不支持的 Provider: gemini")
        assert _call_handler(domain_error_handler, exc) == (400, str(exc))

    def test_card_format_422_with_hint(self) -> None:
        """CardFormatError → 422 + 导入失败：{e}。{hint}（含支持格式说明，逐字）"""
        exc = CardFormatError("无法识别的角色卡格式")
        expected = f"导入失败：无法识别的角色卡格式。{_IMPORT_FORMAT_HINT}"
        assert _call_handler(domain_error_handler, exc) == (422, expected)

    def test_card_validation_422_plain(self) -> None:
        """CardValidationError → 422 + 导入失败：{e}（不带格式说明）"""
        exc = CardValidationError("角色名称不能为空")
        assert _call_handler(domain_error_handler, exc) == (422, "导入失败：角色名称不能为空")

    def test_doc_parse_422(self) -> None:
        """DocParseError → 422 + str(e)（纯原因）"""
        exc = DocParseError("未配置 API Key，请先在设置中填写")
        assert _call_handler(domain_error_handler, exc) == (422, str(exc))

    def test_unknown_domain_subclass_fallback_400(self) -> None:
        """Falsify：未知 DomainError 子类 → 400 + str(e) 兜底（不误匹配到已知类型、不崩溃）"""

        class _MysteryError(DomainError):
            pass

        exc = _MysteryError("未知领域错误")
        assert _call_handler(domain_error_handler, exc) == (400, "未知领域错误")


# ── 2. LLM 异常族 wire 映射（直调 handler，防御性注册）──


class TestLLMErrorHandler:
    """LLM 异常族：经 services/chat.py::chat_error_response 映射（401/429/504/400/502）

    注：401 分支为防御性注册形态——请求路径上的 LLM 错误实际先经 complete_chat
    显式 raise HTTPException（携带 provider 上下文），handler 侧 provider 未知。
    """

    def test_auth_401_defensive_template(self) -> None:
        """LLMAuthError → 401 + 基础文案（无 provider 前缀，无前导空格；ARC10-1 缺陷修复后形态）"""
        exc = LLMAuthError("Claude API Key 无效或未配置")
        assert _call_handler(llm_error_handler, exc) == (401, "API Key 无效，请在设置中更新")

    def test_rate_limit_429_fixed(self) -> None:
        """LLMRateLimitError → 429 + 固定消息"""
        assert _call_handler(llm_error_handler, LLMRateLimitError("x")) == (
            429,
            "API 请求频率超限，请稍后再试",
        )

    def test_timeout_504_fixed(self) -> None:
        """LLMTimeoutError → 504 + 固定消息"""
        assert _call_handler(llm_error_handler, LLMTimeoutError("x")) == (
            504,
            "API 请求超时，请检查网络后重试",
        )

    def test_content_filter_400_str(self) -> None:
        """LLMContentFilterError → 400 + str(e)"""
        exc = LLMContentFilterError("内容被内容过滤器拦截")
        assert _call_handler(llm_error_handler, exc) == (400, str(exc))

    def test_base_llm_error_502_str(self) -> None:
        """LLMError 基类 → 502 + str(e)"""
        exc = LLMError("Claude API 调用失败: boom")
        assert _call_handler(llm_error_handler, exc) == (502, str(exc))


# ── 3. 应用级注册（TestClient wire：真实路由 + 统一 handler）──


@pytest.fixture
def wire_app(db_session) -> FastAPI:
    """注册真实路由 + 统一 handler 的最小应用（get_db 覆盖为内存会话）"""
    app = FastAPI()
    app.add_exception_handler(DomainError, domain_error_handler)
    app.add_exception_handler(LLMError, llm_error_handler)
    app.include_router(chat_route.router)
    app.include_router(characters_route.router)
    app.include_router(settings_route.router)
    app.dependency_overrides[get_db] = lambda: db_session
    return app


class TestAppRegistrationWire:
    """应用级注册生效：路由抛领域异常 → 统一 handler 转 JSON 响应（状态码/detail 逐字）"""

    def test_chat_route_domain_error_404(self, wire_app) -> None:
        """POST /api/chats 对话不存在 → 404 + 逐字 detail"""
        with TestClient(wire_app) as client:
            resp = client.post("/api/chats", json={"conversation_id": 99999, "content": "你好"})
        assert resp.status_code == 404
        assert resp.json() == {"detail": "对话不存在"}

    def test_stream_route_domain_error_404_json(self, wire_app) -> None:
        """流式路由领域错误（对话不存在）→ 404 JSON（非 SSE error 帧；handler 在流构造前生效）"""
        with TestClient(wire_app) as client:
            resp = client.post("/api/chats/stream", json={"conversation_id": 99999, "content": "你好"})
        assert resp.status_code == 404
        assert resp.json() == {"detail": "对话不存在"}

    def test_import_route_422_with_hint(self, wire_app) -> None:
        """导入损坏卡 → 422 + 导入失败：{e}。{hint}（wire 全链路逐字）"""
        with TestClient(wire_app) as client:
            resp = client.post("/api/characters/import", json={"foo": "bar"})
        assert resp.status_code == 422
        body = resp.json()["detail"]
        assert body.startswith("导入失败：")
        assert "无法识别的角色卡格式" in body
        assert "支持格式" in body
        assert "chara_card_v2" in body
        assert "向导" in body

    def test_import_route_validation_422_plain(self, wire_app) -> None:
        """导入缺 name 卡 → 422 + 纯原因（不带格式说明）"""
        with TestClient(wire_app) as client:
            resp = client.post(
                "/api/characters/import",
                json={"spec": "chara_card_v2", "data": {"personality": "x"}},
            )
        assert resp.status_code == 422
        assert resp.json()["detail"] == "导入失败：角色名称不能为空"

    def test_parse_document_no_key_422(self, wire_app) -> None:
        """文档解析缺 Key → 422 + str(e)"""
        with TestClient(wire_app) as client:
            resp = client.post("/api/characters/parse-document", json={"text": "设定文档"})
        assert resp.status_code == 422
        assert resp.json()["detail"] == "未配置 API Key，请先在设置中填写"

    def test_test_connection_unsupported_provider_400(self, wire_app) -> None:
        """test-connection 领域族（provider 校验）→ 400 + 逐字 detail（不走 LLM 族映射）"""
        with TestClient(wire_app) as client:
            resp = client.post(
                "/api/settings/test-connection",
                json={"provider": "gemini", "api_key": "key"},
            )
        assert resp.status_code == 400
        assert resp.json()["detail"] == "不支持的 Provider: gemini"

    def test_http_exception_not_swallowed(self, wire_app) -> None:
        """Falsify：handler 不吞 HTTPException——路由显式抛出的 404 保持 FastAPI 原生响应"""
        @wire_app.post("/boom")
        def _boom() -> None:
            raise HTTPException(status_code=404, detail="角色不存在")

        with TestClient(wire_app) as client:
            resp = client.post("/boom")
        assert resp.status_code == 404
        assert resp.json() == {"detail": "角色不存在"}

    def test_request_validation_422_unaffected(self, wire_app) -> None:
        """Falsify：请求体校验失败仍为 FastAPI 原生 422（RequestValidationError 不受影响）"""
        with TestClient(wire_app) as client:
            resp = client.post("/api/chats", json={"conversation_id": 1})  # 缺 content
        assert resp.status_code == 422
        assert "detail" in resp.json()

    def test_concurrent_handler_calls_isolated(self) -> None:
        """Falsify：并发调用 handler 无共享状态污染（多线程各自映射正确）"""

        def _work(i: int) -> tuple[int, str]:
            if i % 2 == 0:
                return _call_handler(
                    domain_error_handler, ConversationNotFoundError(f"对话不存在{i}")
                )
            return _call_handler(llm_error_handler, LLMRateLimitError("x"))

        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(_work, range(32)))
        for i, result in enumerate(results):
            expected = (404, f"对话不存在{i}") if i % 2 == 0 else (429, "API 请求频率超限，请稍后再试")
            assert result == expected


# ── 4. 真实 app（main.py）注册生效 ──


class TestRealAppRegistration:
    """main.py 装配验证：统一 handler 注册于生产应用实例"""

    def test_real_app_dispatch_domain_error(self, db_session) -> None:
        """真实 app（含全部路由 + handler 注册）经 handler 转 404 JSON"""
        from backend.app.main import app

        app.dependency_overrides[get_db] = lambda: db_session
        try:
            client = TestClient(app)  # 不进入 lifespan，避免真实数据目录副作用
            resp = client.post("/api/chats", json={"conversation_id": 99999, "content": "你好"})
        finally:
            app.dependency_overrides.clear()
        assert resp.status_code == 404
        assert resp.json() == {"detail": "对话不存在"}


# ── 5. characters CRUD 路由 wire 直测（涉改文件覆盖率门 G2）──


class TestCharactersRouteCrud:
    """characters 路由公开行为钉死（CRUD 端点 + 导入成功路径；404 分支同为 FastAPI 原生）"""

    def test_list_returns_empty(self, wire_app) -> None:
        """GET /api/characters 空库 → 200 空列表"""
        with TestClient(wire_app) as client:
            resp = client.get("/api/characters")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_create_and_get(self, wire_app) -> None:
        """POST 创建 → 201；GET 详情 → 200 回读；GET 不存在 → 404 角色不存在"""
        with TestClient(wire_app) as client:
            created = client.post("/api/characters", json={"name": "新角色"})
            assert created.status_code == 201
            char_id = created.json()["id"]

            got = client.get(f"/api/characters/{char_id}")
            assert got.status_code == 200
            assert got.json()["name"] == "新角色"

            missing = client.get("/api/characters/99999")
        assert missing.status_code == 404
        assert missing.json() == {"detail": "角色不存在"}

    def test_update_and_delete(self, wire_app) -> None:
        """PUT 更新 → 200；DELETE → 204；对不存在 id 均 404"""
        with TestClient(wire_app) as client:
            created = client.post("/api/characters", json={"name": "待更新"})
            char_id = created.json()["id"]

            updated = client.put(f"/api/characters/{char_id}", json={"name": "已更新"})
            assert updated.status_code == 200
            assert updated.json()["name"] == "已更新"

            deleted = client.delete(f"/api/characters/{char_id}")
            assert deleted.status_code == 204

            not_found_put = client.put("/api/characters/99999", json={"name": "x"})
            assert not_found_put.status_code == 404

            not_found_del = client.delete("/api/characters/99999")
        assert not_found_del.status_code == 404

    def test_export_character(self, wire_app) -> None:
        """GET /api/characters/{id}/export → 200 V2 卡 JSON；不存在 → 404"""
        with TestClient(wire_app) as client:
            created = client.post("/api/characters", json={"name": "导出角色"})
            char_id = created.json()["id"]

            exported = client.get(f"/api/characters/{char_id}/export")
            assert exported.status_code == 200
            assert exported.json()["data"]["name"] == "导出角色"

            missing = client.get("/api/characters/99999/export")
        assert missing.status_code == 404

    def test_import_success_creates_character(self, wire_app) -> None:
        """合法 V2 卡导入 → 201 落库（导入成功路径）"""
        with TestClient(wire_app) as client:
            resp = client.post(
                "/api/characters/import",
                json={"spec": "chara_card_v2", "data": {"name": "导入角色", "description": "来自卡"}},
            )
        assert resp.status_code == 201
        assert resp.json()["name"] == "导入角色"


# ── 6. CharacterNotFoundError 映射（BE-2 新增异常）──


class TestCharacterNotFoundMapping:
    """CharacterNotFoundError → 404 + str(e) 逐字（经统一 handler；wire 见 TestCharactersRouteCrud）"""

    def test_character_not_found_404(self) -> None:
        """CharacterNotFoundError → 404 + 逐字文案（不落未知子类 400 兜底）"""
        exc = CharacterNotFoundError("角色不存在")
        assert _call_handler(domain_error_handler, exc) == (404, "角色不存在")


# ── 7. conversations CRUD 路由 wire 直测（BE-2 新增）──


@pytest.fixture
def conversation_wire_app(db_session) -> FastAPI:
    """对话/消息/角色路由 + 统一 handler 的最小应用（独立 fixture，不动既有 wire_app）"""
    app = FastAPI()
    app.add_exception_handler(DomainError, domain_error_handler)
    app.add_exception_handler(LLMError, llm_error_handler)
    app.include_router(conversations_route.router)
    app.include_router(messages_route.router)
    app.include_router(characters_route.router)
    app.dependency_overrides[get_db] = lambda: db_session
    return app


class TestConversationsRouteCrud:
    """conversations 路由公开行为钉死（CRUD + 清空边界；404 分支经统一 handler 转领域异常）"""

    def test_list_returns_empty(self, conversation_wire_app) -> None:
        """GET /api/conversations 空库 → 200 空列表"""
        with TestClient(conversation_wire_app) as client:
            resp = client.get("/api/conversations")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_create_and_get(self, conversation_wire_app) -> None:
        """POST 创建 → 201；GET 详情 → 200 回读；GET 不存在 → 404 对话不存在"""
        with TestClient(conversation_wire_app) as client:
            created = client.post(
                "/api/conversations",
                json={"character_id": 1, "title": "新对话", "model_provider": "claude", "model_name": "claude-sonnet-5"},
            )
            assert created.status_code == 201
            conv_id = created.json()["id"]

            got = client.get(f"/api/conversations/{conv_id}")
            assert got.status_code == 200
            assert got.json()["title"] == "新对话"

            missing = client.get("/api/conversations/99999")
        assert missing.status_code == 404
        assert missing.json() == {"detail": "对话不存在"}

    def test_update_and_delete(self, conversation_wire_app) -> None:
        """PUT 更新 → 200；DELETE → 204；对不存在 id 均 404"""
        with TestClient(conversation_wire_app) as client:
            created = client.post(
                "/api/conversations",
                json={"character_id": 1, "title": "待更新"},
            )
            conv_id = created.json()["id"]

            updated = client.put(f"/api/conversations/{conv_id}", json={"title": "已更新"})
            assert updated.status_code == 200
            assert updated.json()["title"] == "已更新"

            deleted = client.delete(f"/api/conversations/{conv_id}")
            assert deleted.status_code == 204

            not_found_put = client.put("/api/conversations/99999", json={"title": "x"})
            assert not_found_put.status_code == 404

            not_found_del = client.delete("/api/conversations/99999")
        assert not_found_del.status_code == 404

    def test_delete_all_clears(self, conversation_wire_app) -> None:
        """DELETE "" 清空 → 204；再次列表 → 空（清空边界）"""
        with TestClient(conversation_wire_app) as client:
            client.post("/api/conversations", json={"character_id": 1, "title": "甲"})
            client.post("/api/conversations", json={"character_id": 1, "title": "乙"})

            cleared = client.delete("/api/conversations")
            assert cleared.status_code == 204

            listed = client.get("/api/conversations")
        assert listed.status_code == 200
        assert listed.json() == []

    def test_messages_route_missing_conversation_404(self, conversation_wire_app) -> None:
        """GET 不存在对话的消息历史 → 404 对话不存在（消息路由守卫同语义）"""
        with TestClient(conversation_wire_app) as client:
            resp = client.get("/api/conversations/99999/messages")
        assert resp.status_code == 404
        assert resp.json() == {"detail": "对话不存在"}

    def test_messages_route_returns_history(self, conversation_wire_app, db_session) -> None:
        """GET 存在对话的消息历史 → 200 消息列表（消息路由正常路径）"""
        # 消息仅由聊天回合创建、无直连创建端点，故经 ORM 落库
        conv = Conversation(character_id=1, title="历史对话")
        db_session.add(conv)
        db_session.commit()
        db_session.refresh(conv)
        db_session.add(Message(conversation_id=conv.id, role=Role.USER, content="你好"))
        db_session.commit()

        with TestClient(conversation_wire_app) as client:
            resp = client.get(f"/api/conversations/{conv.id}/messages")
        assert resp.status_code == 200
        assert resp.json()[0]["content"] == "你好"


# ── 8. 三处导出附件头统一（BE-2：ASCII 兜底 + RFC 5987 并存）──


class TestExportHeadersWire:
    """导出附件头经单一 helper 构造：filename= ASCII 兜底 + filename*= UTF-8 编码并存"""

    def test_character_export_ascii_fallback_plus_rfc5987(self, conversation_wire_app) -> None:
        """角色卡导出：ASCII 兜底 + filename* 并存；中文名走百分号编码段"""
        with TestClient(conversation_wire_app) as client:
            created = client.post("/api/characters", json={"name": "测试·毒舌助手"})
            char_id = created.json()["id"]

            exported = client.get(f"/api/characters/{char_id}/export")
        assert exported.status_code == 200
        header = exported.headers["Content-Disposition"]
        assert 'filename="character-' in header
        assert "filename*=UTF-8''" in header
        assert "filename*=UTF-8''%E6%B5%8B" in header  # 「测」UTF-8 编码进 filename*

    def test_markdown_export_filename_star_carries_chinese_name(self, conversation_wire_app) -> None:
        """Markdown 导出：filename* 携带中文角色名（不再纯 ASCII 丢失）"""
        with TestClient(conversation_wire_app) as client:
            char = client.post("/api/characters", json={"name": "中文名"})
            conv = client.post("/api/conversations", json={"character_id": char.json()["id"]})

            exported = client.get(f"/api/conversations/{conv.json()['id']}/export/markdown")
        assert exported.status_code == 200
        header = exported.headers["Content-Disposition"]
        assert 'filename="conversation-' in header
        assert "filename*=UTF-8''conversation-" in header
        assert "%E4%B8%AD%E6%96%87" in header  # 「中文」UTF-8 编码进 filename*

    def test_json_export_filename_star_carries_chinese_name(self, conversation_wire_app) -> None:
        """JSON 导出：ASCII 兜底 + filename* 携带中文角色名（三处导出同形态）"""
        with TestClient(conversation_wire_app) as client:
            char = client.post("/api/characters", json={"name": "艾莉"})
            conv = client.post("/api/conversations", json={"character_id": char.json()["id"]})

            exported = client.get(f"/api/conversations/{conv.json()['id']}/export/json")
        assert exported.status_code == 200
        header = exported.headers["Content-Disposition"]
        assert 'filename="conversation-' in header
        assert "filename*=UTF-8''conversation-" in header
        assert "%E8%89%BE%E8%8E%89" in header  # 「艾莉」UTF-8 编码进 filename*

    def test_json_export_dangling_character_falls_back_to_id(self, conversation_wire_app) -> None:
        """JSON 导出：对话悬挂 character_id（角色已删）→ 200 + 文件名回退对话 id"""
        with TestClient(conversation_wire_app) as client:
            conv = client.post("/api/conversations", json={"character_id": 99999})

            exported = client.get(f"/api/conversations/{conv.json()['id']}/export/json")
        assert exported.status_code == 200
        assert exported.json()["character"] is None
        header = exported.headers["Content-Disposition"]
        assert f"filename*=UTF-8''conversation-{conv.json()['id']}-{conv.json()['id']}.json" in header

    def test_export_json_missing_conversation_404(self, conversation_wire_app) -> None:
        """JSON 导出哨兵：对话不存在 → 404 + 逐字（哨兵语义保留，不改调 require）"""
        with TestClient(conversation_wire_app) as client:
            resp = client.get("/api/conversations/99999/export/json")
        assert resp.status_code == 404
        assert resp.json() == {"detail": "对话不存在"}

    def test_export_markdown_missing_conversation_404(self, conversation_wire_app) -> None:
        """Markdown 导出哨兵：对话不存在 → 404 + 逐字（哨兵语义保留，不改调 require）"""
        with TestClient(conversation_wire_app) as client:
            resp = client.get("/api/conversations/99999/export/markdown")
        assert resp.status_code == 404
        assert resp.json() == {"detail": "对话不存在"}
