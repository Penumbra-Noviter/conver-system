"""
SP-2 采样参数透传 — 契约锁测试

锁的内容：
1. OpenAI：采样参数（top_p / presence_penalty / frequency_penalty）非 None 时
   进 SDK create 调用 wire，None 时不进（不覆盖 API 默认）
2. Claude：采样参数即使非 None 也不进 SDK create 调用 wire（anthropic 1.0.0 移除，
   仅 max_tokens 可用）
3. chat._sampling_kwargs：从 ChatContext 提取非 None 采样参数
"""

from __future__ import annotations

from types import SimpleNamespace

from backend.app.services.llm.claude import ClaudeProvider
from backend.app.services.llm.openai import OpenAIProvider

__all__: list[str] = []


class _FakeCompletions:
    """记录 OpenAI SDK create 调用 kwargs 的假 completions"""

    def __init__(self) -> None:
        self.calls: list[dict] = []

    async def create(self, **kwargs: object) -> object:
        self.calls.append(kwargs)
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content="x"))]
        )


class _FakeMessages:
    """记录 Claude SDK create 调用 kwargs 的假 messages"""

    def __init__(self) -> None:
        self.calls: list[dict] = []

    async def create(self, **kwargs: object) -> object:
        self.calls.append(kwargs)
        return SimpleNamespace(content=[SimpleNamespace(type="text", text="x")])


def _openai(completions: _FakeCompletions) -> OpenAIProvider:
    provider = OpenAIProvider("test-key")
    provider._async_client = SimpleNamespace(chat=SimpleNamespace(completions=completions))
    return provider


def _claude(messages: _FakeMessages) -> ClaudeProvider:
    provider = ClaudeProvider("test-key")
    provider._async_client = SimpleNamespace(messages=messages)
    return provider


async def test_openai_transmits_sampling_params() -> None:
    """OpenAI 采样参数非 None 时进 SDK wire"""
    completions = _FakeCompletions()
    provider = _openai(completions)

    await provider.generate(
        [{"role": "user", "content": "U"}],
        top_p=0.9,
        presence_penalty=0.5,
        frequency_penalty=-0.3,
    )

    call = completions.calls[0]
    assert call["top_p"] == 0.9
    assert call["presence_penalty"] == 0.5
    assert call["frequency_penalty"] == -0.3


async def test_openai_omits_none_sampling_params() -> None:
    """OpenAI 采样参数 None 时不进 SDK wire（保留 API 默认）"""
    completions = _FakeCompletions()
    provider = _openai(completions)

    await provider.generate([{"role": "user", "content": "U"}])

    call = completions.calls[0]
    assert "top_p" not in call
    assert "presence_penalty" not in call
    assert "frequency_penalty" not in call


async def test_claude_omits_sampling_params() -> None:
    """Claude 采样参数即使非 None 也不进 SDK wire（anthropic 1.0.0 移除，仅 max_tokens）"""
    messages = _FakeMessages()
    provider = _claude(messages)

    await provider.generate(
        [{"role": "user", "content": "U"}],
        top_p=0.9,
        presence_penalty=0.5,
        frequency_penalty=-0.3,
        max_tokens=4096,
    )

    call = messages.calls[0]
    assert "top_p" not in call
    assert "presence_penalty" not in call
    assert "frequency_penalty" not in call
    assert call["max_tokens"] == 4096


def test_sampling_kwargs_extracts_non_none() -> None:
    """_sampling_kwargs：仅提取非 None 采样参数，None 字段不进 kwargs"""
    from backend.app.services.chat import ChatContext, _sampling_kwargs

    ctx = ChatContext(
        conversation=None,  # type: ignore[arg-type]
        temperature=0.7,
        messages=[],
        provider=None,  # type: ignore[arg-type]
        top_p=0.9,
        presence_penalty=None,
        frequency_penalty=-0.3,
        max_tokens=4096,
    )
    assert _sampling_kwargs(ctx) == {
        "top_p": 0.9,
        "frequency_penalty": -0.3,
        "max_tokens": 4096,
    }


def test_sampling_kwargs_empty_when_all_none() -> None:
    """_sampling_kwargs：全 None 返回空 dict（不覆盖 provider 默认）"""
    from backend.app.services.chat import ChatContext, _sampling_kwargs

    ctx = ChatContext(
        conversation=None,  # type: ignore[arg-type]
        temperature=0.7,
        messages=[],
        provider=None,  # type: ignore[arg-type]
    )
    assert _sampling_kwargs(ctx) == {}
