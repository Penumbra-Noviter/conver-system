"""
Claude Provider — 接入 Anthropic Claude
"""

from __future__ import annotations

from typing import AsyncIterator

import anthropic

from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import translate_sdk_error


class ClaudeProvider(BaseLLM):
    """Anthropic Claude 实现"""

    def __init__(self, api_key: str, base_url: str | None = None):
        super().__init__(api_key, base_url)
        client_kwargs = {"api_key": api_key}
        if base_url:
            client_kwargs["base_url"] = base_url
        self._client = anthropic.Anthropic(**client_kwargs)
        self._async_client = anthropic.AsyncAnthropic(**client_kwargs)

    @property
    def provider_name(self) -> str:
        return "claude"

    def _prepare_messages(
        self, messages: list[dict]
    ) -> tuple[str | None, list[dict]]:
        """从消息列表中提取 system prompt，返回 (system, chat_messages)"""
        system = None
        chat_messages = []
        for msg in messages:
            if msg["role"] == "system":
                system = msg["content"]
            else:
                chat_messages.append({"role": msg["role"], "content": msg["content"]})
        return system, chat_messages

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        """非流式生成完整回复"""
        system, chat_messages = self._prepare_messages(messages)
        model = model or "claude-sonnet-4-20250514"

        try:
            response = await self._async_client.messages.create(
                model=model,
                system=system or [],
                messages=chat_messages,
                temperature=temperature,
                max_tokens=max_tokens,
            )
            # 提取文本内容（处理可能的多内容块）
            for block in response.content:
                if block.type == "text":
                    return block.text
            return ""
        except Exception as e:
            raise translate_sdk_error(
                e, "Claude",
                auth_cls=anthropic.AuthenticationError,
                rate_cls=anthropic.RateLimitError,
                timeout_cls=anthropic.APITimeoutError,
                bad_request_cls=anthropic.BadRequestError,
            )

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> AsyncIterator[str]:
        """流式生成，逐 token 产出"""
        system, chat_messages = self._prepare_messages(messages)
        model = model or "claude-sonnet-4-20250514"

        try:
            async with self._async_client.messages.stream(
                model=model,
                system=system or [],
                messages=chat_messages,
                temperature=temperature,
                max_tokens=max_tokens,
            ) as stream:
                async for text in stream.text_stream:
                    yield text
        except Exception as e:
            raise translate_sdk_error(
                e, "Claude",
                auth_cls=anthropic.AuthenticationError,
                rate_cls=anthropic.RateLimitError,
                timeout_cls=anthropic.APITimeoutError,
                bad_request_cls=anthropic.BadRequestError,
            )
