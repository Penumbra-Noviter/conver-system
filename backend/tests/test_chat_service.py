"""
T-03（ARC9-B1）聊天服务层直测 — chat_error_response / prepare_chat / complete_chat

覆盖：
    1. chat_error_response 全映射表（领域 3 类 + LLM 5 类，状态码/消息逐字）
    2. prepare_chat 直接测试（领域异常路径 + 正常路径 ChatContext 字段）
    3. complete_chat 正常路径（fake provider → ChatResponse + 落库）与
       LLM 错误路径（HTTPException 状态码/消息逐字，与路由旧行为等价）
    4. 路由薄化后直测（create_chat / stream_chat：领域异常上抛由统一 handler 转 HTTP；
       LLM 错误经 complete_chat 显式 raise HTTPException）
    5. stream_reply 直测（T-03 O1+O3）：零 token 空流不落库且 done 帧无新建消息 id；
       泛化异常错误帧前补含堆栈的 ERROR 日志；空流+断连竞态与部分内容保存守卫

依赖：pytest + SQLite 内存库（conftest.db_session）+ monkeypatch LLMFactory.get_provider。
不构造真实网络请求。§1-4 不手工构造 ChatContext（stream_reply 常规隔离测试留在
test_p35.py）；§5 为 T-03 指定用例，手工构造 ChatContext 直调 stream_reply。
"""

from __future__ import annotations

import asyncio
import logging

import pytest
from fastapi import HTTPException

from backend.app.api.routes import chat as chat_route
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.message import ChatRequest, ChatResponse
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.error_mapping import IMPORT_FORMAT_HINT, llm_error_response
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    CardFormatError,
    CardValidationError,
    ConversationNotFoundError,
    DocParseError,
    DomainError,
    ProviderNotSupportedError,
)
from backend.app.services.llm import resolver as llm_resolver
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)

__all__: list[str] = []


# ── 测试基础设施 ──


def _create_character(db_session, name: str = "测试角色", temperature: float = 0.7) -> int:
    """落库一个无 greeting 的角色，返回 id"""
    from backend.app.models.character import Character

    char = Character(
        name=name,
        personality="冷静、睿智",
        first_mes="",  # 关闭 greeting 自动插入，简化断言
        temperature=temperature,
    )
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char.id


def _create_conversation(db_session, *, provider: str = "claude", model: str = "claude-test"):
    """落库一个绑定角色的对话（可指定 provider/model），返回 Conversation 实例"""
    char_id = _create_character(db_session)
    return conversation_service.create_conversation(
        db_session,
        ConversationCreate(
            character_id=char_id,
            model_provider=provider,
            model_name=model,
        ),
    )


def _patch_api_key(monkeypatch) -> None:
    """让 setting_service.api_key 恒返回测试 Key（绕过 DB 设置表）"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")


class _FakeProvider:
    """记录 generate 调用参数的假 Provider（可配置固定回复或抛出 LLMError）"""

    def __init__(self, reply: str = "这是测试回复", error: Exception | None = None) -> None:
        self.reply = reply
        self.error = error
        self.calls: list[tuple] = []

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        self.calls.append((messages, temperature, max_tokens, model))
        if self.error is not None:
            raise self.error
        return self.reply


class _FakeLLMFactory:
    """替代 LLMFactory.get_provider 的工厂（与 test_p35 同一模式，不污染真实工厂）"""

    def __init__(self, provider: _FakeProvider) -> None:
        self.provider = provider

    def get_provider(self, name: str, api_key: str, base_url: str | None = None) -> _FakeProvider:
        return self.provider


def _patch_factory(monkeypatch, provider: _FakeProvider) -> None:
    """让 llm_resolver.LLMFactory.get_provider 返回指定假 Provider"""
    monkeypatch.setattr(llm_resolver, "LLMFactory", _FakeLLMFactory(provider))


# ── 1. chat_error_response 全映射表直测（B1 审计点：状态码/消息逐字）──


class TestChatErrorResponse:
    """两族错误映射合一后的单一入口：领域异常族 + LLM 异常族"""

    @pytest.mark.parametrize("exc, status_code", [
        (ConversationNotFoundError("对话不存在"), 404),
        (ApiKeyMissingError("未配置 claude API Key，请在设置中填写"), 400),
        (ProviderNotSupportedError("不支持的 Provider: gemini"), 400),
    ])
    def test_domain_family_verbatim(self, exc: Exception, status_code: int) -> None:
        """领域异常族：映射状态码 + detail=str(e) 逐字"""
        assert chat_service.chat_error_response(exc) == (status_code, str(exc))

    def test_llm_auth_uses_provider_template(self) -> None:
        """LLMAuthError → 401 + {provider} API Key 无效，请在设置中更新（模板逐字）"""
        e = LLMAuthError("Claude API Key 无效或未配置")
        assert chat_service.chat_error_response(e, "claude") == (
            401,
            "claude API Key 无效，请在设置中更新",
        )

    def test_llm_auth_without_provider_no_leading_space(self) -> None:
        """Falsify：LLMAuthError 不传 provider（空串）→ 401 + 基础文案，无前导空格"""
        status_code, message = chat_service.chat_error_response(LLMAuthError("x"))
        assert not message.startswith(" ")
        assert (status_code, message) == (401, "API Key 无效，请在设置中更新")

    def test_llm_auth_with_provider_none_no_prefix(self) -> None:
        """契约锁：签名允许 None 的确定性——锁 provider=None 时无前缀基础文案；
        行为已安全（TD-6 标注 str|None 后），非回归锁（与
        test_llm_auth_without_provider_no_leading_space 入口路径形成双面锁定）"""
        assert llm_error_response(
            LLMAuthError("Claude API Key 无效或未配置"), None
        ) == (401, "API Key 无效，请在设置中更新")

    def test_llm_rate_limit_fixed_message(self) -> None:
        """LLMRateLimitError → 429 + 固定消息"""
        assert chat_service.chat_error_response(LLMRateLimitError("x"), "claude") == (
            429,
            "API 请求频率超限，请稍后再试",
        )

    def test_llm_timeout_fixed_message(self) -> None:
        """LLMTimeoutError → 504 + 固定消息"""
        assert chat_service.chat_error_response(LLMTimeoutError("x"), "claude") == (
            504,
            "API 请求超时，请检查网络后重试",
        )

    def test_llm_content_filter_uses_str(self) -> None:
        """LLMContentFilterError → 400 + str(e)"""
        e = LLMContentFilterError("内容被 Claude 内容过滤器拦截")
        assert chat_service.chat_error_response(e, "claude") == (400, str(e))

    def test_llm_base_error_502(self) -> None:
        """LLMError 基类 → 502 + str(e)"""
        e = LLMError("Claude API 调用失败: boom")
        assert chat_service.chat_error_response(e, "claude") == (502, str(e))

    def test_unknown_exception_fallback_502(self) -> None:
        """Falsify：非领域非 LLM 异常 → 502 + str(e) 兜底（不抛错）"""
        assert chat_service.chat_error_response(RuntimeError("boom")) == (502, "boom")

    def test_unknown_domain_subclass_fallback_400(self) -> None:
        """Falsify：未知 DomainError 子类 → 400 + str(e)（与统一 handler 兜底语义对齐，ARC10-2）"""

        class _MysteryDomainError(DomainError):
            pass

        exc = _MysteryDomainError("未知领域错误")
        assert chat_service.chat_error_response(exc) == (400, "未知领域错误")

    def test_domain_422_card_format_with_hint(self) -> None:
        """CardFormatError → 422 + 导入失败：{e}。{hint}（防御语义对齐：领域分支委托后 422 家族从 400 变 422）"""
        exc = CardFormatError("无法识别的角色卡格式")
        assert chat_service.chat_error_response(exc) == (
            422,
            f"导入失败：无法识别的角色卡格式。{IMPORT_FORMAT_HINT}",
        )

    def test_domain_422_card_validation_plain(self) -> None:
        """CardValidationError → 422 + 导入失败：{e}（纯原因，不带格式说明）"""
        exc = CardValidationError("角色名称不能为空")
        assert chat_service.chat_error_response(exc) == (422, "导入失败：角色名称不能为空")

    def test_domain_422_doc_parse_plain(self) -> None:
        """DocParseError → 422 + str(e)（纯原因）"""
        exc = DocParseError("未配置 API Key，请先在设置中填写")
        assert chat_service.chat_error_response(exc) == (422, str(exc))


# ── 2. prepare_chat 直接测试 ──


class TestPrepareChat:
    """prepare_chat 领域异常路径 + 正常路径 ChatContext 字段"""

    def test_conversation_not_found_raises(self, db_session) -> None:
        """对话不存在 → ConversationNotFoundError（路由层转 404）"""
        req = ChatRequest(conversation_id=99999, content="你好")
        with pytest.raises(ConversationNotFoundError):
            chat_service.prepare_chat(db_session, req)

    def test_missing_api_key_raises(self, db_session) -> None:
        """未配置 API Key（DB 设置表为空）→ ApiKeyMissingError（路由层转 400）"""
        conv = _create_conversation(db_session)
        req = ChatRequest(conversation_id=conv.id, content="你好")
        with pytest.raises(ApiKeyMissingError) as exc:
            chat_service.prepare_chat(db_session, req)
        assert "API Key" in str(exc.value)

    def test_unsupported_provider_raises(self, db_session, monkeypatch) -> None:
        """Provider 未注册（get_provider 抛 ProviderNotSupportedError）→ 原样上抛"""
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session, provider="gemini")
        req = ChatRequest(conversation_id=conv.id, content="你好")

        class _RaisingFactory:
            """get_provider 恒抛 ProviderNotSupportedError 的假工厂（模拟未注册 Provider）"""

            @staticmethod
            def get_provider(name: str, api_key: str, base_url: str | None = None) -> object:
                raise ProviderNotSupportedError(f"不支持的 Provider: {name}")

        monkeypatch.setattr(llm_resolver, "LLMFactory", _RaisingFactory)

        with pytest.raises(ProviderNotSupportedError) as exc:
            chat_service.prepare_chat(db_session, req)
        assert "gemini" in str(exc.value)

    def test_happy_path_returns_context(self, db_session, monkeypatch) -> None:
        """正常路径：ChatContext 字段（conversation/temperature/messages/provider）"""
        _patch_api_key(monkeypatch)
        char_id = _create_character(db_session, temperature=0.9)
        conv = conversation_service.create_conversation(
            db_session,
            ConversationCreate(
                character_id=char_id,
                model_provider="claude",
                model_name="claude-test",
            ),
        )
        fake = _FakeProvider()
        _patch_factory(monkeypatch, fake)
        req = ChatRequest(conversation_id=conv.id, content="你好")

        ctx = chat_service.prepare_chat(db_session, req)

        assert ctx.conversation.id == conv.id
        assert ctx.temperature == 0.9
        assert ctx.provider is fake
        assert ctx.messages[-1] == {"role": "user", "content": "你好"}
        # 回合前置：用户消息已落库
        saved = message_service.get_messages(db_session, conv.id)
        assert saved[-1].content == "你好"


# ── 3. complete_chat 直测 ──


def _setup_complete(db_session, monkeypatch, provider: _FakeProvider):
    """组装一次完整非流式回合环境，返回 (conv, request)"""
    _patch_api_key(monkeypatch)
    conv = _create_conversation(db_session, provider="claude", model="claude-test")
    _patch_factory(monkeypatch, provider)
    req = ChatRequest(conversation_id=conv.id, content="你好")
    return conv, req


class TestCompleteChat:
    """非流式回合深模块入口：prepare → generate → LLM 错误映射 → 持久化 → 响应构造"""

    async def test_happy_path_returns_response_and_persists(
        self, db_session, monkeypatch
    ) -> None:
        """正常路径：ChatResponse 字段 + assistant 消息落库 + generate 参数透传"""
        fake = _FakeProvider(reply="这是回复")
        conv, req = _setup_complete(db_session, monkeypatch, fake)

        resp = await chat_service.complete_chat(db_session, req)

        assert isinstance(resp, ChatResponse)
        assert resp.reply == "这是回复"
        assert isinstance(resp.message_id, int)
        assert resp.conversation_id == conv.id
        # 回复已落库为 assistant 消息
        saved = message_service.get_messages(db_session, conv.id)
        assert saved[-1].role.name == "ASSISTANT"
        assert saved[-1].content == "这是回复"
        # generate 参数与路由旧实现逐字一致：temperature/model 透传
        messages, temperature, max_tokens, model = fake.calls[0]
        assert messages[-1] == {"role": "user", "content": "你好"}
        assert temperature == 0.7
        assert model == "claude-test"

    @pytest.mark.parametrize("llm_exc, status_code, message", [
        (LLMAuthError("bad key"), 401, "claude API Key 无效，请在设置中更新"),
        (LLMRateLimitError("rate"), 429, "API 请求频率超限，请稍后再试"),
        (LLMTimeoutError("timeout"), 504, "API 请求超时，请检查网络后重试"),
        (LLMContentFilterError("filtered"), 400, "filtered"),
        (LLMError("boom"), 502, "boom"),
    ])
    async def test_llm_error_raises_http_exception(
        self, db_session, monkeypatch, llm_exc: LLMError, status_code: int, message: str
    ) -> None:
        """LLM 异常 → HTTPException 上抛（状态码/消息逐字，与路由旧行为等价），不落 assistant 消息"""
        fake = _FakeProvider(error=llm_exc)
        _, req = _setup_complete(db_session, monkeypatch, fake)

        with pytest.raises(HTTPException) as exc:
            await chat_service.complete_chat(db_session, req)

        assert exc.value.status_code == status_code
        assert exc.value.detail == message
        roles = [m.role for m in message_service.get_messages(db_session, req.conversation_id)]
        assert Role.ASSISTANT not in roles

    async def test_domain_error_propagates_unchanged(self, db_session) -> None:
        """领域异常从 complete_chat 上抛（不转 HTTPException）——转换由路由层负责"""
        req = ChatRequest(conversation_id=99999, content="你好")
        with pytest.raises(ConversationNotFoundError):
            await chat_service.complete_chat(db_session, req)

    async def test_db_write_failure_propagates(self, db_session, monkeypatch) -> None:
        """Falsify：持久化失败 → 原始异常上抛（不吞错、不伪造响应）"""
        fake = _FakeProvider(reply="回复")
        _, req = _setup_complete(db_session, monkeypatch, fake)

        def _boom(db, conversation_id, role, content):
            raise RuntimeError("db down")

        monkeypatch.setattr(message_service, "create_message", _boom)
        with pytest.raises(RuntimeError):
            await chat_service.complete_chat(db_session, req)


# ── 4. 路由薄化后直测（create_chat / stream_chat 领域异常上抛、LLM 错误转 HTTPException）──


class _FakeRequest:
    """最小 raw_request 桩（领域异常在事件生成器构造前抛出，is_disconnected 不会被执行）"""

    async def is_disconnected(self) -> bool:
        return False


class TestCreateChatRoute:
    """POST /api/chats 路由薄化后：领域异常上抛（统一 handler 转 404/400，wire 断言在 test_error_handler.py）+ 成功路径"""

    async def test_success(self, db_session, monkeypatch) -> None:
        """成功路径：响应体 {reply, message_id, conversation_id}（响应契约不变）"""
        fake = _FakeProvider(reply="路由回复")
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _patch_factory(monkeypatch, fake)
        req = ChatRequest(conversation_id=conv.id, content="你好")

        resp = await chat_route.create_chat(req, db_session)

        assert resp.reply == "路由回复"
        assert resp.conversation_id == conv.id
        assert isinstance(resp.message_id, int)

    async def test_domain_error_404(self, db_session) -> None:
        """领域异常（对话不存在）→ 上抛 ConversationNotFoundError（统一 handler 转 404 + 逐字 detail）"""
        req = ChatRequest(conversation_id=99999, content="你好")
        with pytest.raises(ConversationNotFoundError) as exc:
            await chat_route.create_chat(req, db_session)
        assert str(exc.value) == "对话不存在"

    async def test_domain_error_400_missing_key(self, db_session) -> None:
        """领域异常（无 API Key）→ 上抛 ApiKeyMissingError（统一 handler 转 400 + 逐字 detail）"""
        conv = _create_conversation(db_session)
        req = ChatRequest(conversation_id=conv.id, content="你好")
        with pytest.raises(ApiKeyMissingError) as exc:
            await chat_route.create_chat(req, db_session)
        assert "API Key" in str(exc.value)

    async def test_llm_error_401(self, db_session, monkeypatch) -> None:
        """LLM 异常经 complete_chat 转 HTTPException 后穿透路由 → 401 逐字"""
        fake = _FakeProvider(error=LLMAuthError("bad"))
        _patch_api_key(monkeypatch)
        conv = _create_conversation(db_session)
        _patch_factory(monkeypatch, fake)
        req = ChatRequest(conversation_id=conv.id, content="你好")

        with pytest.raises(HTTPException) as exc:
            await chat_route.create_chat(req, db_session)
        assert exc.value.status_code == 401
        assert exc.value.detail == "claude API Key 无效，请在设置中更新"

    async def test_stream_path_domain_error_404(self, db_session) -> None:
        """流式路径领域异常（对话不存在）→ 上抛 ConversationNotFoundError（统一 handler 转 404）"""
        req = ChatRequest(conversation_id=99999, content="你好")
        with pytest.raises(ConversationNotFoundError):
            await chat_route.stream_chat(req, _FakeRequest(), db_session)


# ── 5. stream_reply 直测（T-03：O1 零 token 空流守卫 + O3 泛化异常日志）──


class _StreamStubProvider:
    """流式桩 Provider：逐 token 产出；全部产出后可抛指定异常（泛化/LLM 均可）"""

    def __init__(self, tokens: list[str], error_after: Exception | None = None) -> None:
        self.tokens = tokens
        self.error_after = error_after

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ):
        for tok in self.tokens:
            yield tok
        if self.error_after is not None:
            raise self.error_after


async def _never_disconnected() -> bool:
    """is_disconnected 桩：永远返回 False"""
    return False


async def _always_disconnected() -> bool:
    """is_disconnected 桩：首次轮询即视为已断开"""
    return True


def _disconnect_after_call(n: int):
    """is_disconnected 桩工厂：第 n 次调用之后恒返回 True（与 test_p35._FakeRequest 同语义）"""

    async def _is_disconnected() -> bool:
        _is_disconnected.calls += 1  # type: ignore[attr-defined]
        return _is_disconnected.calls > n  # type: ignore[attr-defined]

    _is_disconnected.calls = 0  # type: ignore[attr-defined]
    return _is_disconnected


def _make_stream_pair(db_session, provider):
    """落库一个无 greeting 对话并手工组装 ChatContext，返回 (conv, ctx)"""
    conv = _create_conversation(db_session)
    ctx = chat_service.ChatContext(
        conversation=conv,
        temperature=0.7,
        messages=[{"role": "user", "content": "你好"}],
        provider=provider,
    )
    return conv, ctx


def _collect_stream_events(db_session, conv_id: int, ctx) -> list[dict]:
    """驱动 stream_reply 至自然结束（含错误帧后继续迭代），收集全部事件 dict"""

    async def _run() -> list[dict]:
        return [
            event
            async for event in chat_service.stream_reply(
                db_session, conv_id, ctx, is_disconnected=_never_disconnected
            )
        ]

    return asyncio.run(_run())


def _assistant_contents(db_session, conv_id: int) -> list[str]:
    rows = (
        db_session.query(Message)
        .filter(Message.conversation_id == conv_id, Message.role == Role.ASSISTANT)
        .order_by(Message.created_at.asc())
        .all()
    )
    return [row.content for row in rows]


class TestStreamReplyZeroTokenAndErrorLog:
    """T-03 验收：零 token 流不落库、done 帧不引用未保存 id；泛化异常帧前补日志"""

    def test_zero_token_stream_skips_persist_done_without_new_id(
        self, db_session
    ) -> None:
        """(a) 零 token 流：无 assistant 消息落库，done 帧 message_id 为 None（字段在、值 null）"""
        conv, ctx = _make_stream_pair(db_session, _StreamStubProvider(tokens=[]))

        events = _collect_stream_events(db_session, conv.id, ctx)

        assert events == [{"type": "done", "message_id": None}]
        assert _assistant_contents(db_session, conv.id) == []

    def test_generic_exception_error_frame_and_stack_log(
        self, db_session, caplog
    ) -> None:
        """(b) 非 LLM 泛化异常：错误帧文案语义不变，yield 前落含堆栈的 ERROR 日志"""
        conv, ctx = _make_stream_pair(
            db_session,
            _StreamStubProvider(tokens=[], error_after=RuntimeError("boom")),
        )

        with caplog.at_level(logging.ERROR, logger="backend.app.services.chat"):
            events = _collect_stream_events(db_session, conv.id, ctx)

        # 错误帧文案与改动前逐字一致
        assert events == [{"type": "error", "message": "生成回复失败: boom"}]
        assert _assistant_contents(db_session, conv.id) == []
        records = [r for r in caplog.records if r.name == "backend.app.services.chat"]
        assert len(records) == 1
        rec = records[0]
        assert rec.levelno == logging.ERROR
        # 含异常栈：exc_info 非空且指向原始异常类型
        assert rec.exc_info is not None
        assert rec.exc_info[0] is RuntimeError

    def test_zero_token_disconnect_race_saves_nothing(self, db_session) -> None:
        """Falsify（空流+断连竞态）：内容为空串的流中断开 → 守卫生效，不落库、不发 done

        构造：provider 只产空串 token（full_content 恒为空），第 1 次断开检查后即断开。
        断开检查先于本迭代 token 产出，故第 2 次轮询为 True 时仅第 1 个空串 token 已发出。
        """
        conv, ctx = _make_stream_pair(db_session, _StreamStubProvider(tokens=["", ""]))

        async def _run() -> list[dict]:
            return [
                event
                async for event in chat_service.stream_reply(
                    db_session, conv.id, ctx,
                    is_disconnected=_disconnect_after_call(1),
                )
            ]

        events = asyncio.run(_run())

        # 首个空串 token 在断开检查之后产出（既有语义）；随后断开 → 提前返回，
        # full_content 为空 → 不保存、无 done 帧
        assert events == [{"type": "token", "content": ""}]
        assert _assistant_contents(db_session, conv.id) == []

    def test_generic_exception_after_partial_tokens_does_not_save_partial(
        self, db_session
    ) -> None:
        """F-45（O2 一致性缺口）：中途泛化异常 → 错误帧后 partial content 不落库。
        防止 reload 后幽灵内容与错误气泡呈现不一致。"""
        conv, ctx = _make_stream_pair(
            db_session,
            _StreamStubProvider(tokens=["你好"], error_after=RuntimeError("mid-boom")),
        )

        events = _collect_stream_events(db_session, conv.id, ctx)

        assert [e["type"] for e in events] == ["token", "error"]
        assert events[-1]["message"] == "生成回复失败: mid-boom"
        # F-45：错误帧后不保存部分内容，reload 后无幽灵内容
        assert _assistant_contents(db_session, conv.id) == []
