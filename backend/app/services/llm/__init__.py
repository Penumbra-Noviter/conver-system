"""
LLM Provider 包

导出工厂与 Prompt 纯函数。Provider 类（ClaudeProvider / OpenAIProvider / BaseLLM）
经 `LLMFactory.register_builtin_providers()` 显式注册，**不从包路径导入**——
保证「import 本包」不触发任何 LLM SDK 加载（显式注册无副作用，懒加载价值成立）。

    - 内置 Provider 通过 `LLMFactory.register_builtin_providers()` 注册
    - 应用入口（main.py on_startup）在启动时显式调用
    - 也可依赖 `get_provider` / `list_providers` 首次调用时的自动注册（懒加载兜底）

Provider 清单单一来源为 `services/model_data.py` 的 `AVAILABLE_MODELS`，
新增 Provider 只改模型数据文件（必要时在 factory._CLASS_OVERRIDES 声明实现类）。
"""

from backend.app.services.llm.factory import LLMFactory, register_builtin_providers
from backend.app.services.llm.prompt import (
    CharacterData,
    apply_template_vars,
    build_messages,
    parse_mes_example,
)

__all__ = [
    "LLMFactory",
    "register_builtin_providers",
    "CharacterData",
    "apply_template_vars",
    "parse_mes_example",
    "build_messages",
]
