# LLM 集成设计

## 架构

```
┌──────────────────────────────────────────────────┐
│                   Service 层                      │
│   message.build_message_list(db, conv, content)   │
│   message.create_message(db, conv_id, role, txt)  │
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

    def __init__(self, api_key: str, base_url: str | None = None):
        self.api_key = api_key
        self.base_url = base_url

    @abstractmethod
    async def generate(
        self,
        messages: list[dict],       # [{"role": "...", "content": "..."}, ...]
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

    async def test_connection(self, model: str | None = None) -> None:
        """测试 API 连接可用性（默认实现：最小请求 max_tokens=1，可覆写）"""
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
    def get_provider(cls, name: str, api_key: str, base_url: str | None = None) -> BaseLLM:
        if name not in cls._providers:
            raise ValueError(f"不支持的 Provider: {name}")
        return cls._providers[name](api_key=api_key, base_url=base_url)

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

`message_service.build_message_list(db, conversation, user_content, max_rounds=30)` 组装顺序：

```
1. system_prompt = character.system_prompt or character.personality
   messages = [{"role": "system", "content": system_prompt}]
2. scenario 非空 → 追加系统消息 "[场景设定]\n{scenario}"
3. mes_example 非空 → 解析为 few-shot 示例（{{user}}: / {{char}}: 行，
   <START> 分隔多轮），插入历史之前
4. 历史消息（按时间正序；超过 max_rounds*2 条时截取最近 N 轮滑窗）
5. post_history_instructions 非空 → 追加系统消息（置于历史之后、当前输入之前）
6. 当前用户输入 → 追加 {"role": "user", "content": user_content}
```

- **模板变量**：上述所有文本经 `_apply_template_vars()` 替换 `{{user}}` → 用户昵称（settings `user_name`）、`{{char}}` → 角色名。
- **上下文策略**：滑动窗口保留最近 N 轮（`max_rounds` 从 settings `sliding_window_rounds` 读取，默认 30），非 token 估算截断。
- **首条消息**：`create_message` 保存首条 user 消息时，若标题仍为占位默认值，则替换为规则截断标题（见 api-design.md 创建对话）；`auto_insert_greeting` 在对话无消息时插入角色 `first_mes` 开场白。
- 结果送入 LLM Provider。

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

1. 在 `app/services/llm/` 下新建文件，实现 `BaseLLM` 抽象类（含 `test_connection`，默认实现够用）
2. 在 `app/services/llm/__init__.py` 中导入并用 Factory 注册
3. 在 `api/routes/settings.py` 的 `ALLOWED_KEYS` 白名单中加入 `{provider}_api_key` 配置项
4. 在 `api/routes/models.py` 的 `AVAILABLE_MODELS` 中加入新 Provider 的模型名
