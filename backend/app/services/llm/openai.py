"""
OpenAI Provider — 接入 OpenAI（及兼容 API 的第三方服务）

支持：
- OpenAI 官方 API（gpt-4o, gpt-4o-mini 等）
- 兼容 OpenAI 协议的第三方 API（自定义 base_url）
- 非流式 / 流式两种模式
"""

from __future__ import annotations

from typing import AsyncIterator

import openai

from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.errors import LLMError, translate_sdk_error


class OpenAIProvider(BaseLLM):
    """OpenAI / 兼容 API 实现"""

    def __init__(self, api_key: str, base_url: str | None = None):
        super().__init__(api_key, base_url)
        client_kwargs = {"api_key": api_key}
        if base_url:
            client_kwargs["base_url"] = base_url
        self._client = openai.OpenAI(**client_kwargs)
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

    def _prepare_messages(
        self, messages: list[dict]
    ) -> tuple[dict | None, list[dict]]:
        """从消息列表中提取 system prompt，返回 (system_dict, chat_messages)

        OpenAI 使用 system 角色消息而非顶层参数，因此从列表中分离 system。
        """
        system = None
        chat_messages = []
        for msg in messages:
            if msg["role"] == "system":
                system = {"role": "system", "content": msg["content"]}
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
        model = model or "gpt-4o"
        if system:
            chat_messages.insert(0, system)

        try:
            response = await self._async_client.chat.completions.create(
                model=model,
                messages=chat_messages,
                temperature=temperature,
                max_tokens=max_tokens,
            )
            return response.choices[0].message.content or ""
        except Exception as e:
            raise self._translate_error(e)

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
            chat_messages.insert(0, system)

        try:
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
        except Exception as e:
            raise self._translate_error(e)
