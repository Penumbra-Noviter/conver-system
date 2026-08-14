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


class CredentialsResponse(BaseModel):
    """OpenAI 兼容凭证只读响应（U8 模拟器注入用）

    字段契约（spec「U8 凭证端点契约」）：
        - key：openai 协议槽位解析到的 key（仅 protocol=openai 时非空；
          claude-only / none 一律空串，claude key 值绝不回传）
        - endpoint：openai 协议槽位 base_url（复用既有跨协议兜底链）；
          为空时前端保持游戏默认地址
        - model：默认 provider 为 openai 协议且存在 openai key 时返回，
          否则空串（游戏保持默认模型）
        - protocol：协议能力标志 ∈ openai | claude | none（供前端
          按钮禁用 / 提示文案判断）
    """
    key: str = ""
    endpoint: str = ""
    model: str = ""
    protocol: str = ""
