"""
设置管理 Pydantic Schema
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class ConnectionTestRequest(BaseModel):
    """API Key 连接测试请求"""
    provider: str = Field(..., description="Provider 标识（claude / openai）")
    api_key: str = Field(default="", description="要测试的 API Key；留空则用已保存的 Key")
    base_url: str | None = Field(default=None, description="自定义 API 地址（OpenAI 兼容服务用）")
    model: str | None = Field(default=None, description="测试用的模型名；留空则用 Provider 默认模型")


class ConnectionTestResponse(BaseModel):
    """API Key 连接测试响应"""
    ok: bool = True
    provider: str
    message: str = "连接成功"
