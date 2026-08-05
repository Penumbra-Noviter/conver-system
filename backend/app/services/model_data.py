"""
Conver System — 可用模型数据

硬编码的可用模型列表（后续可扩展为动态查询）。
所有 id="openai" 的 provider 均使用 OpenAI 兼容 API。
"""

from __future__ import annotations

__all__ = ["AVAILABLE_MODELS"]

AVAILABLE_MODELS = {
    "providers": [
        {
            "key": "claude",
            "id": "claude",
            "name": "Claude (Anthropic)",
            "models": [
                "claude-sonnet-5",
                "claude-fable-5",
                "claude-mythos-5",
                "claude-opus-4-8",
                "claude-opus-4-7",
                "claude-mythos-preview",
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-haiku-4-5",
                "claude-opus-4-5",
                "claude-sonnet-4-5",
            ],
        },
        {
            "key": "openai",
            "id": "openai",
            "name": "OpenAI",
            "models": [
                "gpt-5.6-sol",
                "gpt-5.6-terra",
                "gpt-5.6-luna",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.4-nano",
                "gpt-5.2",
                "gpt-5.2-pro",
                "gpt-5.1",
                "gpt-5.1-mini",
                "gpt-5.1-codex",
                "gpt-5",
                "gpt-5-mini",
                "gpt-5-nano",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano",
                "o4-mini",
                "o3",
                "o3-mini",
                "gpt-4o",
                "gpt-4o-mini",
            ],
        },
        {
            "key": "deepseek",
            "id": "openai",
            "name": "DeepSeek",
            "models": [
                "deepseek-v4-flash",
                "deepseek-v4-pro",
                "deepseek-chat",
                "deepseek-reasoner",
            ],
        },
        {
            "key": "qwen",
            "id": "openai",
            "name": "通义千问 (Qwen)",
            "models": [
                "qwen-max",
                "qwen-plus",
                "qwen-turbo",
            ],
        },
        {
            "key": "kimi",
            "id": "openai",
            "name": "月之暗面 (Kimi)",
            "models": [
                "kimi-k3",
                "kimi-k2.5",
                "kimi-k2",
                "kimi-k2-lite",
                "kimi-k2-thinking-turbo",
            ],
        },
        {
            "key": "glm",
            "id": "openai",
            "name": "智谱 (GLM / Zhipu)",
            "models": [
                "glm-4-plus",
                "glm-4",
                "glm-4v",
                "glm-4-flash",
                "glm-4-air",
                "glm-3-turbo",
            ],
        },
        {
            "key": "minimax",
            "id": "openai",
            "name": "MiniMax",
            "models": [
                "MiniMax-M3",
                "MiniMax-M2.7",
                "MiniMax-M2.5",
                "MiniMax-M2.1",
                "MiniMax-M2",
            ],
        },
        {
            "key": "step",
            "id": "openai",
            "name": "阶跃星辰 (Step)",
            "models": [
                "step-2",
                "step-2v",
                "step-1",
                "step-1v",
            ],
        },
    ]
}