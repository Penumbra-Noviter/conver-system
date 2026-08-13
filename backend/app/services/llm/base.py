"""
LLM 抽象基类 — 所有 Provider 实现此接口

定义两个核心方法：
    - generate(): 非流式生成
    - stream_generate(): 流式生成（AsyncIterator）

共享骨架（Provider 不再各自实现）：
    - _prepare_messages(): 消息准备（system 分离 + 消息逐条重建）
    - _translated_call(): generate / stream_generate 的 try/except 骨架
      （SDK 异常统一经 Provider._translate_error 映射为 LLMError）
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from contextlib import asynccontextmanager
from typing import AsyncIterator

from backend.app.services.llm.errors import LLMError


class BaseLLM(ABC):
    """所有 LLM Provider 的抽象基类"""

    def __init__(self, api_key: str, base_url: str | None = None):
        self.api_key = api_key
        self.base_url = base_url

    @abstractmethod
    def _translate_error(self, error: Exception) -> LLMError:
        """将 SDK 异常统一映射为 LLMError 层级（抽象契约，必须实现）

        generate / stream_generate 经 _translated_call 骨架捕获的任意异常
        统一交给本方法翻译后再上抛；抽象方法强制子类实现，漏实现者无法
        实例化（TypeError），杜绝未来 Provider 忘实现时 AttributeError 穿透 500。
        参照实现：openai.py / claude.py（translate_sdk_error 适配各自 SDK）。

        Args:
            error: SDK 抛出的原始异常

        Returns:
            映射后的 LLMError（消息带 Provider 名，wire 语义由 LLMError 族决定）
        """
        ...

    def _prepare_messages(self, messages: list[dict]) -> tuple[str | None, list[dict]]:
        """从消息列表提取 system prompt，返回 (system_content, chat_messages)

        system 以纯文本内容返回：Claude 侧直接用作顶层 system 参数，
        OpenAI 侧需在调用处包装回 {"role": "system", "content": ...} 再插入消息列表。
        非 system 消息逐条重建为 {"role", "content"} 字典（不持有外部引用）。
        """
        system = None
        chat_messages = []
        for msg in messages:
            if msg["role"] == "system":
                system = msg["content"]
            else:
                chat_messages.append({"role": msg["role"], "content": msg["content"]})
        return system, chat_messages

    @asynccontextmanager
    async def _translated_call(self) -> AsyncIterator[None]:
        """generate / stream_generate 共享 try/except 骨架

        Provider 将 SDK 调用体放入 `async with self._translated_call():` 块内，
        块内任何异常统一经 Provider._translate_error（子类实现，见 openai.py /
        claude.py）映射为 LLMError 上抛。基类零 SDK 依赖，不承担具体翻译。
        """
        try:
            yield
        except Exception as e:
            raise self._translate_error(e) from e

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
