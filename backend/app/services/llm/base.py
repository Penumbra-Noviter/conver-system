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

    async def test_connection(self, model: str | None = None) -> None:
        """测试 API 连接是否可用（校验 Key 有效性与网络可达性）

        默认实现：发起一次最小生成请求（max_tokens=1），连接无效时抛出
        由 Provider _translate_error 映射的 LLMError。Provider 可覆写以做
        更便宜的专用校验（如 models 端点）。
        """
        await self.generate(
            [{"role": "user", "content": "ping"}],
            temperature=0.0,
            max_tokens=1,
            model=model,
        )
