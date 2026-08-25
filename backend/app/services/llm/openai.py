"""
OpenAI Provider — 接入 OpenAI（及兼容 API 的第三方服务）

支持：
- OpenAI 官方 API（gpt-4o, gpt-4o-mini 等）
- 兼容 OpenAI 协议的第三方 API（自定义 base_url）
- 非流式 / 流式两种模式
"""

from __future__ import annotations

import re
from typing import AsyncIterator

import openai

from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMError, translate_sdk_error


def _normalize_base_url(base_url: str | None) -> str | None:
    """规范化 OpenAI 兼容端点地址

    用户常只填面板根地址（如 https://api.example.com），而 OpenAI SDK
    会拼接 /chat/completions，导致请求打到 HTML 面板而非 API 端点。
    惯例补充 /v1 版本段；已含版本段（v1 / v1beta 等）或为空则原样返回。
    """
    if not base_url:
        return None
    url = base_url.rstrip("/")
    last_segment = url.rsplit("/", 1)[-1]
    if re.fullmatch(r"v\d+(?:beta)?", last_segment):
        return url
    return f"{url}/v1"


class OpenAIProvider(BaseLLM):
    """OpenAI / 兼容 API 实现"""

    def __init__(self, api_key: str, base_url: str | None = None):
        super().__init__(api_key, base_url)
        base_url = _normalize_base_url(base_url)
        client_kwargs = {"api_key": api_key}
        if base_url:
            client_kwargs["base_url"] = base_url
        self._async_client = openai.AsyncOpenAI(**client_kwargs)

    def _translate_error(self, error: Exception) -> LLMError:
        """将 OpenAI SDK 异常统一映射为 LLMError 层级"""
        return translate_sdk_error(
            error, "OpenAI",
            auth_cls=openai.AuthenticationError,
            rate_cls=openai.RateLimitError,
            timeout_cls=openai.APITimeoutError,
            bad_request_cls=openai.BadRequestError,
        )

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        """非流式生成完整回复"""
        system, chat_messages = self._prepare_messages(messages)
        model = model or "gpt-4o"
        if system:
            chat_messages.insert(0, {"role": "system", "content": system})

        async with self._translated_call():
            response = await self._async_client.chat.completions.create(
                model=model,
                messages=chat_messages,
                temperature=temperature,
                max_tokens=max_tokens,
            )
            return response.choices[0].message.content or ""

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> AsyncIterator[str]:
        """流式生成，逐 token 产出"""
        system, chat_messages = self._prepare_messages(messages)
        model = model or "gpt-4o"
        if system:
            chat_messages.insert(0, {"role": "system", "content": system})

        async with self._translated_call():
            stream = await self._async_client.chat.completions.create(
                model=model,
                messages=chat_messages,
                temperature=temperature,
                max_tokens=max_tokens,
                stream=True,
            )
            async for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
