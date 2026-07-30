# LLM 集成设计

## 架构

```
┌──────────────────────────────────────────────────┐
│                   Service 层                      │
│   message_service.generate_reply(conversation)    │
└─────────────────────┬────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────────┐
│               LLM Factory (工厂)                   │
│         provider = get_provider(provider_name)     │
└──────────┬──────────────┬──────────────┬─────────┘
           │              │              │
           ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ClaudeProvider│ │OpenAIProvider│ │(Future)      │
│              │ │              │ │OllamaProv.   │
│ anthropic SDK│ │ openai SDK   │ │ ...          │
└──────────────┘ └──────────────┘ └──────────────┘
```

## 抽象基类 BaseLLM

```python
from abc import ABC, abstractmethod
from typing import AsyncIterator

class BaseLLM(ABC):
    """所有 LLM Provider 的抽象基类"""

    @abstractmethod
    async def generate(
        self,
        messages: list[dict],       # [{"role": "...", "content": "..."}, ...]
        temperature: float = 0.7,
        max_tokens: int = 2048,
    ) -> str:
        """非流式生成完整回复"""
        ...

    @abstractmethod
    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
    ) -> AsyncIterator[str]:
        """流式生成，逐 token 产出"""
        ...

    @property
    @abstractmethod
    def provider_name(self) -> str:
        """返回唯一标识，如 'claude' / 'openai'"""
        ...
```

## Factory

```python
class LLMFactory:
    _providers: dict[str, type[BaseLLM]] = {}

    @classmethod
    def register(cls, name: str, provider_cls: type[BaseLLM]):
        cls._providers[name] = provider_cls

    @classmethod
    def get_provider(cls, name: str, api_key: str) -> BaseLLM:
        if name not in cls._providers:
            raise ValueError(f"不支持的 Provider: {name}")
        return cls._providers[name](api_key=api_key)

    @classmethod
    def list_providers(cls) -> list[str]:
        return list(cls._providers.keys())
```

## Provider 实现

### ClaudeProvider

```python
class ClaudeProvider(BaseLLM):
    def __init__(self, api_key: str):
        self.client = Anthropic(api_key=api_key)

    async def generate(self, messages, temperature=0.7, max_tokens=2048):
        # 转换消息格式为 Anthropic 格式
        # 调用 self.client.messages.create()
        # 返回 response.content[0].text
        ...

    async def stream_generate(self, messages, temperature=0.7, max_tokens=2048):
        # async with self.client.messages.stream() as stream:
        #     async for text in stream.text_stream:
        #         yield text
        ...

    @property
    def provider_name(self): return "claude"
```

### OpenAIProvider

```python
class OpenAIProvider(BaseLLM):
    def __init__(self, api_key: str, base_url: str = None):
        self.client = AsyncOpenAI(api_key=api_key, base_url=base_url)

    async def generate(self, messages, temperature=0.7, max_tokens=2048):
        # 调用 self.client.chat.completions.create()
        # 返回 choice.message.content
        ...

    async def stream_generate(self, messages, temperature=0.7, max_tokens=2048):
        # async for chunk in await self.client.chat.completions.create(stream=True):
        #     if chunk.choices[0].delta.content:
        #         yield chunk.choices[0].delta.content
        ...

    @property
    def provider_name(self): return "openai"
```

> **兼容性**: OpenAIProvider 可通过 `base_url` 参数连接任何兼容 OpenAI API 的服务（如本地 llm 代理、第三方中转等）。

## 消息格式转换

各 Provider 的 SDK 消息格式不同，需要在 Provider 内部做适配转换。

### 统一格式（Service 层使用）

```python
[
    {"role": "system", "content": "你是林墨，一位流浪诗人..."},
    {"role": "user", "content": "你好"},
    {"role": "assistant", "content": "你来了。"},
    {"role": "user", "content": "今天心情不错"},
]
```

### 各 SDK 格式差异

| SDK | system | user | assistant |
|-----|--------|------|-----------|
| Anthropic | `{"role": "user", "content": "System: ..."}` 或 `system` 参数 | `{"role": "user", "content": "..."}` | `{"role": "assistant", "content": "..."}` |
| OpenAI | `{"role": "system", "content": "..."}` | `{"role": "user", "content": "..."}` | `{"role": "assistant", "content": "..."}` |

## Prompt 构建逻辑

```
1. 加载角色: character.personality
2. 加载对话: conversation 下的所有 messages（按时间正序）
3. 构建消息列表:
   system_prompt = character.personality
   messages = [
       {"role": "system", "content": system_prompt},
       ...history...,             # 历史消息
       {"role": "user", "content": 用户最新输入}
   ]
4. 截断策略（可选）:
   - 计算历史消息的 token 估算值
   - 超出 max_tokens 时，从最早的非 system 消息开始丢弃
   - 至少保留最近的 N 轮对话
5. 送入 LLM Provider
```

## 异常处理

```python
class LLMError(Exception):
    """LLM 调用基类异常"""

class LLMAuthError(LLMError):
    """API Key 无效或未配置"""

class LLMRateLimitError(LLMError):
    """频率限制"""

class LLMTimeoutError(LLMError):
    """请求超时"""

class LLMContentFilterError(LLMError):
    """内容被过滤"""
```

Service 层调用 LLM 时捕获这些异常，转为对应的 HTTP 响应。

## 添加新 Provider 的步骤

1. 在 `app/services/llm/` 下新建文件，实现 `BaseLLM` 抽象类
2. 在 `app/services/llm/__init__.py` 中导入并用 Factory 注册
3. 在 `config.py` 中添加对应的 API Key 配置项
4. 在前端模型列表中加入新 Provider 的模型名
