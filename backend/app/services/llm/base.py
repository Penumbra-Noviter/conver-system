"""
LLM 抽象基类 — 所有 Provider 实现此接口

定义两个核心方法：
    - generate(): 非流式生成
    - stream_generate(): 流式生成（AsyncIterator）
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import AsyncIterator


class BaseLLM(ABC):
    """所有 LLM Provider 的抽象基类"""

    def __init__(self, api_key: str, base_url: str | None = None):
        self.api_key = api_key
        self.base_url = base_url

    @abstractmethod
    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        """非流式生成完整回复"""
        ...

    @abstractmethod
    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> AsyncIterator[str]:
        """流式生成，逐 token 产出"""
        ...

    @property
    @abstractmethod
    def provider_name(self) -> str:
        """返回唯一标识，如 'claude' / 'openai'"""
        ...
