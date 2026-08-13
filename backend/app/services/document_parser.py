"""
文档智能解析 — 深模块

使用用户配置的 LLM 从自由文本中提取角色卡字段（name / personality / first_mes 等），
将用户的角色设定文档、小说片段、简介等自然语言描述自动拆分为结构化字段。

协议表面：__all__ 仅 parse_document 一个公开函数。
"""

from __future__ import annotations

import logging

import json

logger = logging.getLogger(__name__)

from sqlalchemy.orm import Session

from backend.app.schemas.character import DocParseResponse
from backend.app.services.exceptions import (
    ApiKeyMissingError,
    DocParseError,
    ProviderNotSupportedError,
)
from backend.app.services.llm.resolver import resolve_llm

__all__ = ["parse_document"]

# 提取字段白名单：LLM 可能返回额外字段，只取此集合内的
_PARSED_FIELDS = frozenset({
    "name", "description", "personality", "scenario",
    "first_mes", "mes_example", "system_prompt",
    "post_history_instructions", "tags", "creator",
})

_PARSE_SYSTEM_PROMPT = """你是一个角色卡解析器。用户会提供一段关于角色的文字描述（可能是小说片段、设定文档、角色简介等），请从中提取以下字段并以 JSON 格式返回：

{
  "name": "角色名称",
  "description": "简短描述（一句话）",
  "personality": "人格设定、性格特征、说话方式、行为模式等核心设定",
  "scenario": "场景设定（对话发生的背景/世界）",
  "first_mes": "开场白（角色首次见面说的话）",
  "mes_example": "对话范例（展示角色说话风格的示例对话）",
  "system_prompt": "系统提示词（如果有明确的指令性内容）",
  "tags": ["标签1", "标签2"],
  "creator": "作者/来源"
}

规则：
1. name 必须提取，无法确定则留空字符串
2. 不要编造文档中没有的信息
3. personality 是核心字段，尽量详细
4. 对话范例用 <START> 标记开头，{{user}} 表示用户，{{char}} 表示角色
5. 不确定的字段留空字符串或空数组
6. 只返回 JSON，不要其他文字"""


async def parse_document(
    db: Session,
    text: str,
    provider: str | None = None,
    model: str | None = None,
) -> DocParseResponse:
    """使用用户配置的 LLM 从文档中提取角色卡字段

    Args:
        db: 数据库会话（用于读取 LLM 配置）
        text: 用户文档文本
        provider: 指定 LLM Provider（留空则用默认）
        model: 指定 LLM 模型（留空则用默认）

    Returns:
        解析后的角色字段（DocParseResponse）

    Raises:
        DocParseError: LLM 调用失败 / 返回无法解析的响应 / 未配置 API Key /
            Provider 不支持（后两者由 resolve_llm 抛 ApiKeyMissingError /
            ProviderNotSupportedError，此处按本模块 wire 契约统一转 DocParseError：
            422 + 既有文案逐字）
    """
    # 1. 解析 provider / model 并解析 LLM 实例（凭据读取 + 实例化收口于 resolve_llm）
    try:
        _, mod, llm = resolve_llm(db, provider, model)
    except ApiKeyMissingError:
        raise DocParseError("未配置 API Key，请先在设置中填写") from None
    except ProviderNotSupportedError as exc:
        # 基线 wire：不支持的 Provider → 422 + 既有文案逐字（旧实现捕获
        # ValueError 转 DocParseError；resolver 收口为领域异常后此处还原契约）
        raise DocParseError(str(exc)) from None

    # 2. 构造消息并调用 LLM
    messages = [
        {"role": "system", "content": _PARSE_SYSTEM_PROMPT},
        {"role": "user", "content": text},
    ]

    try:
        raw = await llm.generate(messages, temperature=0.3, max_tokens=4096, model=mod)
    except Exception as exc:
        raise DocParseError(f"LLM 调用失败：{_truncate(str(exc), 200)}") from exc

    # 3. 解析 JSON 响应
    parsed = _extract_json(raw)
    if parsed is None:
        raise DocParseError("LLM 返回了无法解析的响应，请重试或手动创建")

    # 4. 构建响应（只取白名单字段，容错处理）
    result: dict[str, object] = {}
    parsed_fields: list[str] = []

    for field in _PARSED_FIELDS:
        value = parsed.get(field)
        if value is None or value == "" or value == []:
            result[field] = _default_for(field)
            continue

        if field == "tags":
            if isinstance(value, list):
                result[field] = [str(t) for t in value if t]
            else:
                result[field] = []
        elif isinstance(value, str):
            result[field] = value.strip()
        else:
            result[field] = str(value)

        parsed_fields.append(field)

    return DocParseResponse(
        name=result.get("name", ""),
        description=result.get("description", ""),
        personality=result.get("personality", ""),
        scenario=result.get("scenario", ""),
        first_mes=result.get("first_mes", ""),
        mes_example=result.get("mes_example", ""),
        system_prompt=result.get("system_prompt", ""),
        post_history_instructions=result.get("post_history_instructions", ""),
        tags=result.get("tags", []),
        creator=result.get("creator", ""),
        parsed_fields=parsed_fields,
    )


# ── 内部辅助 ──


def _extract_json(raw: str) -> dict | None:
    """从 LLM 输出中提取 JSON dict

    尝试：完整 JSON 解析 → 从 ```json ... ``` 代码块提取 → 从 { ... } 范围提取
    """
    text = raw.strip()

    # 直接尝试
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            return data
    except json.JSONDecodeError:
        logger.debug("直接 JSON 解析失败，尝试代码块提取")

    # 代码块提取
    if "```" in text:
        for marker in ("```json\n", "```\n", "```"):
            start = text.find(marker)
            if start >= 0:
                end = text.find("```", start + len(marker))
                if end >= 0:
                    candidate = text[start + len(marker):end].strip()
                    try:
                        data = json.loads(candidate)
                        if isinstance(data, dict):
                            return data
                    except json.JSONDecodeError:
                        continue

    # 花括号范围提取
    brace_start = text.find("{")
    if brace_start >= 0:
        brace_end = text.rfind("}")
        if brace_end > brace_start:
            candidate = text[brace_start:brace_end + 1]
            try:
                data = json.loads(candidate)
                if isinstance(data, dict):
                    return data
            except json.JSONDecodeError:
                logger.debug("花括号范围 JSON 解析失败")

    return None


def _default_for(field: str) -> str | list:
    """字段默认值"""
    return [] if field == "tags" else ""


def _truncate(msg: str, max_len: int) -> str:
    """截断错误消息"""
    return msg[:max_len] + ("…" if len(msg) > max_len else "")