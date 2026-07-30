"""注册所有 LLM Provider 到 Factory"""

from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.claude import ClaudeProvider
from backend.app.services.llm.factory import LLMFactory
from backend.app.services.llm.openai import OpenAIProvider

# 注册内置 Provider
LLMFactory.register("claude", ClaudeProvider)
LLMFactory.register("openai", OpenAIProvider)

__all__ = ["BaseLLM", "LLMFactory"]
