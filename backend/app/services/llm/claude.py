"""
Claude Provider — 接入 Anthropic Claude
"""

from __future__ import annotations

from typing import AsyncIterator

import anthropic

from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMError, translate_sdk_error

__all__ = ["ClaudeProvider"]


class ClaudeProvider(BaseLLM):
    """Anthropic Claude 实现"""

    def __init__(self, api_key: str, base_url: str | None = None):
        super().__init__(api_key, base_url)
        client_kwargs = {"api_key": api_key}
        if base_url:
            client_kwargs["base_url"] = base_url
        self._async_client = anthropic.AsyncAnthropic(**client_kwargs)

    def _translate_error(self, error: Exception) -> LLMError:
        """将 Claude SDK 异常统一映射为 LLMError 层级"""
        return translate_sdk_error(
            error, "Claude",
            auth_cls=anthropic.AuthenticationError,
            rate_cls=anthropic.RateLimitError,
            timeout_cls=anthropic.APITimeoutError,
            bad_request_cls=anthropic.BadRequestError,
        )

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
        top_p: float | None = None,
        presence_penalty: float | None = None,
        frequency_penalty: float | None = None,
    ) -> str:
        """非流式生成完整回复

        temperature / top_p / presence_penalty / frequency_penalty 保留于对外签名
        供上层（chat 链路）依赖，但不透传 SDK——anthropic 1.0.0 的 messages.create
        已移除全部采样参数（F-56 temperature + SP-1 实证 top_p/presence/frequency），
        仅 max_tokens 可用，传入即 TypeError（契约锁测试见
        test_llm_shared.py::TestAnthropic1xContractLock）。
        """
        system, chat_messages = self._prepare_messages(messages)
        model = model or "claude-sonnet-5"

        async with self._translated_call():
            response = await self._async_client.messages.create(
                model=model,
                system=system or [],
                messages=chat_messages,
                max_tokens=max_tokens,
            )
            # 提取文本内容（处理可能的多内容块）
            for block in response.content:
                if block.type == "text":
                    return block.text
            return ""

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
        top_p: float | None = None,
        presence_penalty: float | None = None,
        frequency_penalty: float | None = None,
    ) -> AsyncIterator[str]:
        """流式生成，逐 token 产出

        采样参数保留于对外签名但不透传 SDK（同 generate，anthropic 1.0.0 移除全部
        采样参数，仅 max_tokens 可用）。
        """
        system, chat_messages = self._prepare_messages(messages)
        model = model or "claude-sonnet-5"

        async with self._translated_call():
            async with self._async_client.messages.stream(
                model=model,
                system=system or [],
                messages=chat_messages,
                max_tokens=max_tokens,
            ) as stream:
                async for text in stream.text_stream:
                    yield text
