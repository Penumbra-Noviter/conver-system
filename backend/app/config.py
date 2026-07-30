"""
Conver System — 应用配置

通过 pydantic-settings 从 .env 文件加载基础配置。
API Key 等运行时配置通过 DB settings 表管理（非 .env）。
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """应用全局配置"""

    # LLM API Keys（.env 占位，实际通过 DB settings 表管理）
    CLAUDE_API_KEY: str = ""
    OPENAI_API_KEY: str = ""
    OPENAI_BASE_URL: str = ""

    # 默认模型
    DEFAULT_PROVIDER: str = "claude"
    DEFAULT_MODEL: str = "claude-sonnet-4-20250514"

    # 数据库
    DATABASE_URL: str = "sqlite+aiosqlite:///./conver_system.db"

    # 服务端口
    HOST: str = "127.0.0.1"
    PORT: int = 8000

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
