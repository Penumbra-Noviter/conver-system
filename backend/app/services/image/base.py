"""
图片生成抽象基类（CG-1，与 LLM BaseLLM 同构）

BaseImageGen：所有图片 Provider 实现此接口。核心方法 generate(params) -> ImageResult
（直接生成；长耗时任务的 submit + poll 由 CG-3 image_tasks 承担，不在本层）。

参数/结果形态：
    - ImageGenParams：Provider 无关的生成参数（提示词 + 尺寸 + 采样步数）
    - ImageResult.url：本地文件路径或 HTTP URL（CG-2 cg_images.url 契约）——
      「本地优先」：内置 HTTP 后端拉取图片后落盘本地，返回本地文件路径
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from pydantic import BaseModel, Field


class ImageGenParams(BaseModel):
    """图片生成参数（Provider 无关；越界「拒」语义 Field 约束）

    默认尺寸对齐常用生成后端（A1111 默认 512x512）；steps 对 A1111 有效，
    自定义 HTTP 端点可忽略。
    """
    prompt: str = Field(..., min_length=1, description="生成提示词")
    negative_prompt: str = Field("", description="负面提示词（A1111 用）")
    width: int = Field(512, ge=32, le=2048, description="图片宽")
    height: int = Field(512, ge=32, le=2048, description="图片高")
    steps: int = Field(20, ge=1, le=150, description="采样步数")


@dataclass(frozen=True)
class ImageResult:
    """图片生成结果

    Attributes:
        url: 图片地址——本地文件路径或 HTTP URL（CG-2 cg_images.url 契约）
        width: 图片宽（生成方已知时）
        height: 图片高
        content_type: MIME 类型（如 image/png）
    """
    url: str
    width: int | None = None
    height: int | None = None
    content_type: str | None = None


class BaseImageGen(ABC):
    """所有图片 Provider 的抽象基类（CG-1）"""

    def __init__(
        self,
        base_url: str | None = None,
        *,
        api_key: str | None = None,
    ):
        self.base_url = base_url
        self.api_key = api_key

    @abstractmethod
    async def generate(self, params: ImageGenParams) -> ImageResult:
        """生成一张图片并落盘本地（或返回远程 URL）

        Args:
            params: 生成参数（Provider 无关）

        Returns:
            图片结果（url 本地文件路径或 HTTP URL）

        Raises:
            ImageAuthError: 凭据缺失 / 无效
            ImageTimeoutError: 请求超时（15 秒守卫语义）
            ImageResponseError: 上游响应畸形
            ImageConnectionError: 连接失败 / 端点未配置
        """
        ...