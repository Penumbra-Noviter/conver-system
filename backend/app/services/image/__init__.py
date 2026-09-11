"""
图片生成（text2img）包 — CG-1 Provider 抽象，与 LLM Provider 同构

导出工厂与解析入口。Provider 实现类（HttpImageGen / LocalImageGen / BaseImageGen）
经 `ImageFactory.register_builtin_providers()` 显式注册，**不从包路径导入**——
保证「import 本包」不触发任何 HTTP 客户端/PIL 加载（显式注册无副作用，懒加载
价值成立；httpx 与 PIL 为调用期依赖）。

    - 内置 Provider 在首次调用 `get_provider` / `list_providers` 时通过
      `_ensure_builtins` 自动注册（懒加载兜底，与 LLMFactory 同模式）

Provider 清单单一来源为 `services/image/model_data.py` 的
`AVAILABLE_IMAGE_PROVIDERS`（对齐 model_data.py AVAILABLE_MODELS 模式），
新增图片 Provider 只改该数据文件（必要时在 factory._CLASS_OVERRIDES 声明实现类）。
"""

from backend.app.services.image.factory import (
    ImageFactory,
    register_builtin_providers,
)
from backend.app.services.image.resolver import resolve_image

__all__ = [
    "ImageFactory",
    "register_builtin_providers",
    "resolve_image",
]