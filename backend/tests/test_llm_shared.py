"""
共享 Provider 骨架单测（BE-3 收口验证）

覆盖：
    1. _prepare_messages 共享 helper 上移 BaseLLM（最小子类直测：system 分离 /
       无 system / 空列表 / 多 system 取末条 / 消息重建 / OpenAI 侧 string 形态）
    2. OpenAI 调用处 dict 包装（system 以 {"role": "system", ...} 置首）、
       Claude 调用处字符串透传（system 顶层参数）——wire 形状逐字钉住
    3. generate / stream_generate 共享 try/except 骨架：SDK 异常（create / 流中）
       统一翻译为 LLMError，消息逐字
    4. BaseLLM.test_connection 默认实现（以最小请求调用 generate）

依赖：pytest + 假 async client（不建库、不发网络请求）。
"""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.claude import ClaudeProvider
from backend.app.services.llm.errors import LLMError
from backend.app.services.llm.openai import OpenAIProvider

__all__: list[str] = []


class _MinimalProvider(BaseLLM):
    """仅实现抽象方法的 Provider：验证共享 helper 已上移基类（未覆写）"""

    def __init__(self, api_key: str, base_url: str | None = None):
        super().__init__(api_key, base_url)
        self.generate_calls: list[dict] = []

    def _translate_error(self, error: Exception) -> LLMError:
        """stub：本测试不产生 SDK 调用，翻译仅满足抽象契约"""
        return LLMError(str(error), error)

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        """记录调用参数的最小非流式实现"""
        self.generate_calls.append(
            {
                "messages": messages,
                "temperature": temperature,
                "max_tokens": max_tokens,
                "model": model,
            }
        )
        return ""

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> object:
        """最小流式实现"""
        yield ""


class TestSharedMessagePreparation:
    """共享消息准备 helper：上移基类后各角色形态"""

    def test_prepare_messages_separates_system_content_and_rebuilds_chat(self) -> None:
        """system 提取为纯文本内容，其余消息逐条重建为 {role, content}"""
        provider = _MinimalProvider("test-key")
        system, chat = provider._prepare_messages(
            [
                {"role": "system", "content": "你是助手"},
                {"role": "user", "content": "你好"},
                {"role": "assistant", "content": "在的"},
            ]
        )
        assert system == "你是助手"
        assert chat == [
            {"role": "user", "content": "你好"},
            {"role": "assistant", "content": "在的"},
        ]

    def test_prepare_messages_without_system_returns_none(self) -> None:
        """无 system：返回 (None, 全部消息)；空列表：返回 (None, [])"""
        provider = _MinimalProvider("test-key")
        system, chat = provider._prepare_messages([{"role": "user", "content": "你好"}])
        assert system is None
        assert chat == [{"role": "user", "content": "你好"}]

        system, chat = provider._prepare_messages([])
        assert system is None
        assert chat == []

    def test_prepare_messages_last_system_message_wins(self) -> None:
        """多条 system：取末条内容（与既有 Provider 行为一致）"""
        provider = _MinimalProvider("test-key")
        system, chat = provider._prepare_messages(
            [
                {"role": "system", "content": "第一条"},
                {"role": "user", "content": "你好"},
                {"role": "system", "content": "第二条"},
            ]
        )
        assert system == "第二条"
        assert chat == [{"role": "user", "content": "你好"}]

    def test_openai_provider_uses_shared_string_form(self) -> None:
        """OpenAI Provider 不再各自实现：共享 helper 返回纯文本 system（dict 包装在调用处）"""
        provider = OpenAIProvider("test-key")
        system, chat = provider._prepare_messages([{"role": "system", "content": "S"}])
        assert system == "S"
        assert chat == []


class _FakeStream:
    """异步迭代假流：按序产出 chunk，可配置中途抛错"""

    def __init__(self, chunks: list, error: Exception | None = None):
        self._chunks = list(chunks)
        self._error = error

    def __aiter__(self) -> "_FakeStream":
        return self

    async def __anext__(self) -> object:
        if self._error is not None:
            error, self._error = self._error, None
            raise error
        if not self._chunks:
            raise StopAsyncIteration
        return self._chunks.pop(0)


class _FakeOpenAICompletions:
    """记录调用参数的假 completions：普通 / 流式两种形态 + create 与流中错误"""

    def __init__(
        self,
        content: str = "",
        chunks: list | None = None,
        error: Exception | None = None,
        stream_error: Exception | None = None,
    ):
        self.content = content
        self.chunks = chunks or []
        self.error = error
        self.stream_error = stream_error
        self.calls: list[dict] = []

    async def create(self, **kwargs: object) -> object:
        self.calls.append(kwargs)
        if self.error is not None:
            error, self.error = self.error, None
            raise error
        if kwargs.get("stream"):
            return _FakeStream(self.chunks, self.stream_error)
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=self.content))]
        )


class _FakeClaudeMessages:
    """记录调用参数的假 messages：create 普通形态 + stream 上下文形态"""

    def __init__(
        self,
        blocks: list | None = None,
        texts: list | None = None,
        error: Exception | None = None,
        stream_error: Exception | None = None,
    ):
        self.blocks = blocks or []
        self.texts = texts or []
        self.error = error
        self.stream_error = stream_error
        self.calls: list[dict] = []

    async def create(self, **kwargs: object) -> object:
        self.calls.append(kwargs)
        if self.error is not None:
            error, self.error = self.error, None
            raise error
        return SimpleNamespace(content=self.blocks)

    def stream(self, **kwargs: object) -> "_FakeClaudeStream":
        self.calls.append(kwargs)
        return _FakeClaudeStream(self.texts, self.stream_error)


class _FakeClaudeStream:
    """假流式上下文：__aenter__ 返回自身，text_stream 按序产出"""

    def __init__(self, texts: list, error: Exception | None = None):
        self.text_stream = _FakeStream(texts, error)

    async def __aenter__(self) -> "_FakeClaudeStream":
        return self

    async def __aexit__(self, exc_type: object, exc: object, tb: object) -> bool:
        return False


def _openai_provider(completions: _FakeOpenAICompletions, base_url: str | None = None) -> OpenAIProvider:
    """构造 OpenAIProvider 并替换 _async_client 为假客户端（不建库、不发网络）"""
    provider = OpenAIProvider("test-key", base_url=base_url)
    provider._async_client = SimpleNamespace(chat=SimpleNamespace(completions=completions))
    return provider


def _claude_provider(messages: _FakeClaudeMessages, base_url: str | None = None) -> ClaudeProvider:
    """构造 ClaudeProvider 并替换 _async_client 为假客户端（不建库、不发网络）"""
    provider = ClaudeProvider("test-key", base_url=base_url)
    provider._async_client = SimpleNamespace(messages=messages)
    return provider


class TestOpenAICallSiteWrapping:
    """OpenAI 侧：system 在调用处包装回 dict 后插入消息列表首位，行为逐字不变"""

    async def test_generate_wraps_system_as_dict_and_returns_content(self) -> None:
        """system 包装为 {"role": "system", ...} 且置首；默认模型 gpt-4o；参数透传"""
        completions = _FakeOpenAICompletions(content="你好")
        provider = _openai_provider(completions)

        result = await provider.generate(
            [{"role": "system", "content": "你是助手"}, {"role": "user", "content": "你好"}],
            temperature=0.3,
            max_tokens=64,
        )

        assert result == "你好"
        assert completions.calls == [
            {
                "model": "gpt-4o",
                "messages": [
                    {"role": "system", "content": "你是助手"},
                    {"role": "user", "content": "你好"},
                ],
                "temperature": 0.3,
                "max_tokens": 64,
            }
        ]

    async def test_generate_without_system_keeps_messages_unchanged(self) -> None:
        """无 system：消息列表原样透传；空回复返回空串"""
        completions = _FakeOpenAICompletions(content="")
        provider = _openai_provider(completions, base_url="https://api.example.com/v1")

        result = await provider.generate(
            [{"role": "user", "content": "a"}, {"role": "assistant", "content": "b"}]
        )

        assert result == ""
        assert completions.calls[0]["messages"] == [
            {"role": "user", "content": "a"},
            {"role": "assistant", "content": "b"},
        ]
        assert completions.calls[0]["model"] == "gpt-4o"

    async def test_stream_generate_yields_delta_content_with_system_dict(self) -> None:
        """流式：逐 delta.content 产出（空 choices 跳过）；system 仍为 dict 形态"""
        chunks = [
            SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content="你"))]),
            SimpleNamespace(choices=[]),
            SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content="好"))]),
        ]
        completions = _FakeOpenAICompletions(chunks=chunks)
        provider = _openai_provider(completions, base_url="https://api.example.com")

        collected = [
            c
            async for c in provider.stream_generate(
                [{"role": "system", "content": "S"}, {"role": "user", "content": "U"}],
                model="gpt-4o-mini",
            )
        ]

        assert collected == ["你", "好"]
        assert completions.calls[0]["stream"] is True
        assert completions.calls[0]["model"] == "gpt-4o-mini"
        assert completions.calls[0]["messages"] == [
            {"role": "system", "content": "S"},
            {"role": "user", "content": "U"},
        ]

    async def test_stream_generate_translates_iteration_error(self) -> None:
        """流中 SDK 异常：骨架统一翻译为 LLMError"""
        completions = _FakeOpenAICompletions(
            chunks=[SimpleNamespace(choices=[])],
            stream_error=Exception("boom"),
        )
        provider = _openai_provider(completions)

        with pytest.raises(LLMError, match="OpenAI API 调用失败: boom"):
            [c async for c in provider.stream_generate([{"role": "user", "content": "U"}])]

    async def test_generate_translates_sdk_exception_to_llm_error(self) -> None:
        """create 抛 SDK 异常：骨架统一翻译为 LLMError（消息逐字）"""
        completions = _FakeOpenAICompletions(error=Exception("boom"))
        provider = _openai_provider(completions)

        with pytest.raises(LLMError, match="OpenAI API 调用失败: boom"):
            await provider.generate([{"role": "user", "content": "U"}])


class TestClaudeCallSiteWrapping:
    """Claude 侧：system 以纯文本透传顶层参数，行为逐字不变"""

    async def test_generate_passes_system_as_string(self) -> None:
        """system 为顶层字符串参数（不进 messages）；默认模型 claude-sonnet-5；提取 text 块"""
        messages = _FakeClaudeMessages(blocks=[SimpleNamespace(type="text", text="你好")])
        provider = _claude_provider(messages)

        result = await provider.generate(
            [{"role": "system", "content": "你是助手"}, {"role": "user", "content": "你好"}],
            temperature=0.3,
            max_tokens=64,
        )

        assert result == "你好"
        assert messages.calls == [
            {
                "model": "claude-sonnet-5",
                "system": "你是助手",
                "messages": [{"role": "user", "content": "你好"}],
                "temperature": 0.3,
                "max_tokens": 64,
            }
        ]

    async def test_generate_without_text_block_returns_empty(self) -> None:
        """无 text 内容块：返回空串；无 system：system 参数为空列表"""
        messages = _FakeClaudeMessages(blocks=[SimpleNamespace(type="tool_use", text=None)])
        provider = _claude_provider(messages)

        result = await provider.generate([{"role": "user", "content": "U"}])

        assert result == ""
        assert messages.calls[0]["system"] == []

    async def test_stream_generate_yields_texts_with_system_string(self) -> None:
        """流式：逐 text 产出；system 仍为顶层字符串参数"""
        messages = _FakeClaudeMessages(texts=["你", "好"])
        provider = _claude_provider(messages, base_url="https://api.anthropic.com")

        collected = [
            t
            async for t in provider.stream_generate(
                [{"role": "system", "content": "S"}, {"role": "user", "content": "U"}]
            )
        ]

        assert collected == ["你", "好"]
        assert messages.calls[0]["system"] == "S"
        assert messages.calls[0]["messages"] == [{"role": "user", "content": "U"}]

    async def test_stream_generate_translates_stream_error(self) -> None:
        """流中 SDK 异常：骨架统一翻译为 LLMError"""
        messages = _FakeClaudeMessages(texts=["你"], stream_error=Exception("boom"))
        provider = _claude_provider(messages)

        with pytest.raises(LLMError, match="Claude API 调用失败: boom"):
            [t async for t in provider.stream_generate([{"role": "user", "content": "U"}])]

    async def test_generate_translates_sdk_exception_to_llm_error(self) -> None:
        """create 抛 SDK 异常：骨架统一翻译为 LLMError（消息逐字）"""
        messages = _FakeClaudeMessages(error=Exception("boom"))
        provider = _claude_provider(messages)

        with pytest.raises(LLMError, match="Claude API 调用失败: boom"):
            await provider.generate([{"role": "user", "content": "U"}])


class TestConnectionDefault:
    """BaseLLM.test_connection 默认实现：最小请求调用 generate"""

    async def test_test_connection_delegates_to_generate_with_minimal_request(self) -> None:
        """固定 ping 消息 + temperature=0 / max_tokens=1，并透传 model"""
        provider = _MinimalProvider("test-key")

        await provider.test_connection(model="gpt-4o")

        assert provider.generate_calls == [
            {
                "messages": [{"role": "user", "content": "ping"}],
                "temperature": 0.0,
                "max_tokens": 1,
                "model": "gpt-4o",
            }
        ]
