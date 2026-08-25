"""
Conver System — 游戏生成服务（AI 文本 → 可运行 HTML 模拟器）

核心编排：
    1. 构造 prompt（种子模板 + 用户描述 + 可选重试反馈）
    2. resolve_llm 获取已配置的 LLM 实例
    3. llm.generate() 调用 LLM 生成 HTML
    4. validate_generated_html() 校验闸门（6 项检查）
    5. 通过 → 复用 simulator_store 导入管线落盘 + 注册 manifest
    6. 失败 → 返回结构化错误 + 重试建议（最多 3 次重试）

协议表面（__all__）：MAX_RETRIES / generate_game / validate_generated_html
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from html.parser import HTMLParser
from typing import Any

from sqlalchemy.orm import Session

from backend.app.services import data_dir as data_dir_service
from backend.app.services.game_template import MARKER_PATTERN, SEED_TEMPLATE
from backend.app.services.llm.resolver import resolve_llm
from backend.app.services.simulator_import import (
    CFG_REQUIRED_IDS,
    ScanResult,
    import_game,
    probe_config,
    scan_input_ids,
    scan_suspicious,
)

__all__ = [
    "MAX_RETRIES",
    "ScanResult",
    "generate_game",
    "scan_generated_html",
    "validate_generated_html",
]

logger = logging.getLogger(__name__)

#: 最大重试次数（校验失败后重试打磨）
MAX_RETRIES = 3

#: 默认文件名（无标题时回退）
_FALLBACK_NAME = "generated-game"

#: 生成游戏在 manifest 中的 source 标记
GENERATED_SOURCE = "generated"


# ═══════════════════════════════════════════════════════════
# 领域类型
# ═══════════════════════════════════════════════════════════


@dataclass(frozen=True)
class ValidationError:
    """校验闸门单项错误"""
    field: str
    message: str


@dataclass
class GenerateResult:
    """生成结果

    Attributes:
        ok: 是否成功
        game: 成功时返回 manifest 条目
        errors: 校验失败时返回错误列表
        suggestion: 校验失败时返回重试建议
        retries: 实际使用的重试次数
    """
    ok: bool
    game: dict | None = None
    errors: list[ValidationError] | None = None
    suggestion: str | None = None
    retries: int = 0


# ═══════════════════════════════════════════════════════════
# 校验闸门
# ═══════════════════════════════════════════════════════════


def _check_html_structure(html: str) -> ValidationError | None:
    """检查 1：HTML 骨架完整性（含 <!DOCTYPE html> 或 <html>）"""
    lower = html.lower().strip()
    if lower.startswith("<!doctype html") or "<html" in lower[:200]:
        return None
    return ValidationError(field="structure", message="生成的 HTML 缺少 <!DOCTYPE html> 或 <html> 标签")


def _check_template_completeness(html: str) -> ValidationError | None:
    """检查 2：模板标记完整性（无剩余 <!-- GEN: 标记）"""
    if MARKER_PATTERN.search(html):
        return ValidationError(field="template", message="模板标记未完全填充（仍有 <!-- GEN: --> 未替换）")
    return None


def _check_cfg_contract(html: str) -> ValidationError | None:
    """检查 3：cfg- 契约完整性（cfg-endpoint / cfg-apikey / cfg-model 三个 input 存在）"""
    ids = scan_input_ids(html)
    missing = CFG_REQUIRED_IDS - {i for i in ids if i.startswith("cfg-")}
    if missing:
        names = "、".join(sorted(missing))
        return ValidationError(field="cfg", message=f"缺少 AI 配置输入框：{names}")
    return None


class _ParseabilityChecker(HTMLParser):
    """检查 4 辅助：HTML 可解析性校验（遇到错误时记录）"""
    def __init__(self) -> None:
        super().__init__()
        self.errors: list[str] = []

    def handle_decl(self, decl: str) -> None:
        pass  # DOCTYPE 声明不会触发 error

    def error(self, message: str) -> None:
        self.errors.append(message)


def _check_html_parseability(html: str) -> ValidationError | None:
    """检查 4：基础 HTML 可解析性（html.parser 能解析）"""
    checker = _ParseabilityChecker()
    try:
        checker.feed(html)
        checker.close()
    except Exception as exc:
        return ValidationError(field="syntax", message=f"HTML 语法错误：{exc}")
    if checker.errors:
        return ValidationError(field="syntax", message=f"HTML 解析警告：{'；'.join(checker.errors[:3])}")
    return None


def _check_security(html: str, precomputed_warnings: list[str] | None = None) -> list[ValidationError]:
    """检查 5：安全扫描（复用 scan_suspicious；precomputed_warnings 传入时
    直接使用预计算结果——T-03 生成路径单次扫描）"""
    warnings = precomputed_warnings if precomputed_warnings is not None else scan_suspicious(html)
    if warnings:
        return [ValidationError(field="security", message=f"检测到可疑模式：{'、'.join(warnings)}")]
    return []


def _extract_scenes_literal(html: str) -> str | None:
    """定位 GAME_SCENES 数组字面量并做括号配对切分（跳过字符串字面量内字符）。

    修复点（code-review 发现）：原非贪婪正则 `(\\[.*?\\])\\s*;` 会在 narrative
    文本含 `];` 或 `]\\n;` 时提前截断，导致合法游戏被误报 JSON 解析失败。
    本实现先定位 `var/const/let GAME_SCENES = [`, 再从 `[` 起按括号深度配对
    扫描（字符串字面量内字符整体跳过，含转义序列），取到真正匹配的闭合 `]`。

    Returns:
        完整数组文本（含两端方括号）；找不到数组起始 → None
    """
    match = re.search(r'(?:var|const|let)\s+GAME_SCENES\s*=\s*\[', html)
    if not match:
        return None
    i = match.end() - 1  # 指向 '['
    depth = 0
    quote: str | None = None  # 当前字符串引号（" / ' / `）；None 表示不在字符串内
    n = len(html)
    while i < n:
        ch = html[i]
        if quote is not None:
            if ch == "\\":
                i += 2  # 跳过转义序列（可能是转义引号）
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'`":
            quote = ch
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return html[match.end() - 1:i + 1]
        i += 1
    return None


def _try_extract_scenes(html: str) -> tuple[list[dict] | None, str | None]:
    """尝试从生成的 HTML 中提取场景数据。

    场景 id 契约：唯一（重复 id → data 错误）；next 引用必须存在于 id 集合中
    （自引用与双向循环通过校验是设计允许——游戏可无限循环属叙事自由，
    视为合法叙事结构，不阻断）。

    Returns:
        (scenes 列表, 错误消息) —— 成功时 error 为 None，失败时 scenes 为 None
    """
    raw = _extract_scenes_literal(html)
    if raw is None:
        return None, "未找到 GAME_SCENES 数据定义"
    try:
        scenes = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"场景数据 JSON 解析失败：{exc}"
    if not isinstance(scenes, list):
        return None, "场景数据必须是数组"
    if len(scenes) == 0:
        return None, "场景数据为空（至少需要一个场景）"
    for i, scene in enumerate(scenes):
        if not isinstance(scene, dict):
            return None, f"第 {i + 1} 个场景不是对象"
        if "id" not in scene:
            return None, f"第 {i + 1} 个场景缺少 id 字段"
        if "narrative" not in scene or not isinstance(scene.get("narrative"), str) or not scene["narrative"].strip():
            return None, f"场景「{scene.get('id', '?')}」缺少叙事文本"
        if "choices" not in scene or not isinstance(scene.get("choices"), list):
            return None, f"场景「{scene.get('id', '?')}」缺少 choices 数组"
        for j, choice in enumerate(scene["choices"]):
            if not isinstance(choice, dict):
                return None, f"场景「{scene['id']}」第 {j + 1} 个选项不是对象"
            if "text" not in choice or not choice["text"]:
                return None, f"场景「{scene['id']}」第 {j + 1} 个选项缺少 text"
            if "next" not in choice or not choice["next"]:
                return None, f"场景「{scene['id']}」第 {j + 1} 个选项缺少 next"
    # 场景 id 必须是字符串且不得重复（id 是导航锚点，重复会导致 getScene 命中歧义）
    ids = []
    for i, scene in enumerate(scenes):
        sid = scene.get("id")
        if not isinstance(sid, str):
            return None, f"第 {i + 1} 个场景 id 必须是字符串（收到 {type(sid).__name__}）"
        ids.append(sid)
    if len(ids) != len(set(ids)):  # type: ignore[arg-type] — 已确保全为 str
        dup = next(id for id in set(ids) if ids.count(id) > 1)
        return None, f"场景 id 存在重复：「{dup}」（每个场景 id 必须唯一）"
    # 校验引用完整性：所有 next 值都在场景 id 集合中（自引用/循环通过是设计允许）
    all_ids = set(ids)
    for scene in scenes:
        for choice in scene["choices"]:
            if choice["next"] not in all_ids:
                return None, f"场景「{scene['id']}」的选项「{choice['text']}」引用了不存在的场景「{choice['next']}」"
    return scenes, None


def _check_game_data(html: str) -> ValidationError | None:
    """检查 6：游戏数据有效性（场景 JSON 可解析、至少一个场景、每场景有叙事与 choices、
    id 唯一、选项引用完整）"""
    scenes, error = _try_extract_scenes(html)
    if error:
        return ValidationError(field="data", message=error)
    return None


def validate_generated_html(
    html: str,
    *,
    precomputed_scan: ScanResult | None = None,
) -> list[ValidationError]:
    """校验闸门：对 LLM 生成的 HTML 执行六项检查

    precomputed_scan 传入时，检查 5（安全扫描）直接采用其 warnings 结果，
    不再调用 scan_suspicious（T-03 双重扫描消除）；不传时检查 5 按现状自行扫描。

    检查项：
        1. HTML 骨架完整性（<!DOCTYPE html> 或 <html>）
        2. 模板标记完整性（无剩余 <!-- GEN: -->）
        3. cfg- 契约完整性（cfg-endpoint / cfg-apikey / cfg-model）
        4. 基础 HTML 可解析性
        5. 安全扫描（eval / document.cookie / cross-origin-fetch）
        6. 游戏数据有效性（场景 JSON 可解析、≥1 场景、引用完整性）

    Returns:
        错误列表（空列表表示全部通过）
    """
    errors: list[ValidationError] = []
    precomputed_warnings = precomputed_scan.warnings if precomputed_scan is not None else None

    # 按顺序检查，前面的失败不阻断后续检查（收集全部错误以利于重试）
    for check in [_check_html_structure, _check_template_completeness,
                  _check_cfg_contract, _check_html_parseability,
                  _check_security, _check_game_data]:
        if check is _check_security:
            result = _check_security(html, precomputed_warnings)
        else:
            result = check(html)
        if isinstance(result, list):
            errors.extend(result)
        elif result is not None:
            errors.append(result)
    return errors


# ═══════════════════════════════════════════════════════════
# 单次扫描（T-03 双重扫描消除）
# ═══════════════════════════════════════════════════════════


def scan_generated_html(html: str) -> ScanResult:
    """对生成的 HTML 执行元数据探测与恶意模式粗筛，打包为 ScanResult
    （T-03 单次扫描：生成路径由此单点计算一次，结果供校验闸门检查 5 与
    import_game 的 precomputed_scan 复用，消除双重扫描）。

    game_type/config 来自 probe_config（cfg- 三元组探测）；warnings 来自
    scan_suspicious（SUSPICIOUS_PATTERNS 粗筛，命中不拦截）。
    """
    game_type, config = probe_config(html)
    warnings = scan_suspicious(html)
    return ScanResult(game_type=game_type, config=config, warnings=warnings)


# ═══════════════════════════════════════════════════════════
# Prompt 构造
# ═══════════════════════════════════════════════════════════


def _build_system_prompt() -> str:
    """构造系统提示词（种子模板 + 填充规则 + 示例）"""
    return f"""你是一个叙事游戏生成器。你的任务是根据用户提供的世界观描述，生成一个完整的 HTML 叙事选择游戏。

## 种子模板

以下是完整游戏模板。你需要替换其中的两个标记 <!-- GEN:config --> 和 <!-- GEN:scenes --> 为实际数据。**不要修改模板中已有的 HTML 结构和 CSS 样式**。

```
{SEED_TEMPLATE}
```

## 填充规则

### 1. <!-- GEN:config --> → JSON 对象

替换为以下格式的 JSON（**不要包含注释标记**，直接写 JSON）：
{{
    "title": "游戏标题（根据用户描述生成）",
    "world": "世界观简介（1-3 句话概括世界背景）"
}}

### 2. <!-- GEN:scenes --> → JSON 数组

替换为场景数据数组，每个场景的格式：
{{
    "id": "场景唯一标识（英文字母/数字/下划线）",
    "narrative": "叙事文本（描述当前场景的所见所闻所感，1-4 段）",
    "choices": [
        {{ "text": "选项文本", "next": "目标场景 id" }},
        ...
    ]
}}

## 要求

1. 场景数量：至少 3 个，建议 5-8 个，不超过 15 个
2. 每个场景至少 1 个选项，最多 5 个选项
3. 终局场景（如结局、胜利、失败）的 choices 为空数组 []
4. 所有选项的 next 值必须指向已存在的场景 id
5. 叙事文本要生动、有沉浸感，与世界观一致
6. 输出**只包含完整 HTML**，不要添加任何解释或额外文字
7. **不要修改模板中已有的 HTML 结构和 CSS 样式**

## 示例

用户描述：「一个发生在魔法学院的冒险故事，学生发现了一个秘密通道」

<!-- GEN:config --> 替换为：
{{"title":"魔法学院秘道探险","world":"在一所古老的魔法学院中，流传着一个关于秘密通道的传说。据说通道通往学院最深的秘密，但从未有人走完全程。"}}

<!-- GEN:scenes --> 替换为：
[
    {{
        "id": "start",
        "narrative": "夜深了，你站在图书馆三楼的书架间。月光透过彩色玻璃窗洒在地板上，照亮了墙壁上的一幅古老挂毯——传说秘密通道的入口就在这幅挂毯后面。\\n\\n你听到远处传来巡逻的脚步声。",
        "choices": [
            {{"text": "掀起挂毯看看", "next": "tunnel"}},
            {{"text": "先躲进旁边的空教室", "next": "classroom"}}
        ]
    }},
    {{
        "id": "tunnel",
        "narrative": "你掀起挂毯，发现后面确实有一扇暗门。轻轻一推，门开了，露出一条向下延伸的石阶。墙壁上的火把自动亮起，仿佛在欢迎你。\\n\\n石阶很窄，只能容一人通过。空气中弥漫着潮湿的泥土气息。",
        "choices": [
            {{"text": "沿着石阶走下去", "next": "crypt"}},
            {{"text": "回到图书馆再想想", "next": "start"}}
        ]
    }}
]
"""


def _build_user_prompt(description: str, title: str | None = None) -> str:
    """构造用户提示词"""
    parts = []
    if title:
        parts.append(f"游戏标题：{title}")
    parts.append(f"世界观描述：\n{description}")
    return "\n\n".join(parts)


def _build_retry_prompt(description: str, title: str | None,
                        errors: list[ValidationError], suggestion: str,
                        previous_html: str) -> str:
    """构造重试提示词（包含原始描述 + 校验错误 + 修正建议）"""
    error_lines = []
    for err in errors:
        error_lines.append(f"  - [{err.field}] {err.message}")
    error_text = "\n".join(error_lines)

    return f"""你之前生成的游戏未通过校验，需要修正后重新生成。

## 原始世界观描述

{f'游戏标题：{title}' if title else ''}
{description}

## 上次生成的 HTML（有问题的版本）

```
{previous_html[:1000]}...
```

## 校验错误

{error_text}

## 修正建议

{suggestion}

请重新生成完整的 HTML，修正以上所有错误。"""


# ═══════════════════════════════════════════════════════════
# 编排
# ═══════════════════════════════════════════════════════════


async def generate_game(
    db: Session,
    description: str,
    title: str | None = None,
    *,
    previous_html: str | None = None,
    previous_errors: list[ValidationError] | None = None,
    previous_suggestion: str | None = None,
    retries_left: int = MAX_RETRIES,
    attempted: int = 0,
) -> GenerateResult:
    """生成游戏（主编排入口）

    Args:
        db: 数据库会话
        description: 用户输入的世界观描述
        title: 可选游戏标题
        previous_html: 重试时上次生成的 HTML
        previous_errors: 重试时上次校验错误
        previous_suggestion: 重试时修正建议
        retries_left: 剩余重试次数
        attempted: 已尝试次数

    Returns:
        GenerateResult（ok=True 表示成功，game 为 manifest 条目）

    Raises:
        LLMError: LLM 调用失败（由调用方统一处理）
    """
    # 1. 解析 LLM 凭据
    _, model, llm = resolve_llm(db, provider=None)

    # 2. 构造 prompt
    if previous_html is not None and previous_errors is not None:
        prompt = _build_retry_prompt(
            description, title,
            previous_errors, previous_suggestion or "",
            previous_html,
        )
    else:
        prompt = _build_user_prompt(description, title)

    messages = [
        {"role": "system", "content": _build_system_prompt()},
        {"role": "user", "content": prompt},
    ]

    # 3. 调用 LLM
    temperature = 0.3 if previous_html else 0.7
    logger.info("生成游戏：attempt=%d, retries_left=%d, model=%s, temperature=%.1f",
                attempted + 1, retries_left, model, temperature)
    reply = await llm.generate(
        messages,
        temperature=temperature,
        max_tokens=8192,
        model=model,
    )

    # 3a. 防御：LLM 返回非字符串 → 视为一次失败重试或直接返回错误
    if not isinstance(reply, str):
        logger.warning("LLM 返回非字符串类型：%s", type(reply).__name__)
        if retries_left <= 0:
            return GenerateResult(
                ok=False,
                errors=[ValidationError(field="data", message=f"LLM 返回了非字符串类型：{type(reply).__name__}")],
                suggestion="请重试",
                retries=attempted + 1,
            )
        return await generate_game(
            db=db,
            description=description,
            title=title,
            previous_html=str(reply) if reply is not None else None,
            previous_errors=[ValidationError(field="data", message=f"LLM 返回非字符串类型：{type(reply).__name__}")],
            previous_suggestion="请确保 LLM 配置正确并重试",
            retries_left=retries_left - 1,
            attempted=attempted + 1,
        )

    # 4. 校验闸门（T-03 生成路径单次扫描：先 scan_generated_html 一次打包
    # probe_config + scan_suspicious 结果，校验检查 5 与落盘的 import_game
    # 复用同一扫描结果，import_game 内部不再重复计算）
    scan = scan_generated_html(reply)
    errors = validate_generated_html(reply, precomputed_scan=scan)

    if not errors:
        # 校验通过 → 落盘
        logger.info("游戏生成校验通过，准备落盘：title=%s", title or _FALLBACK_NAME)
        game = _persist_generated_game(reply, title, precomputed_scan=scan)
        return GenerateResult(ok=True, game=game, retries=attempted)

    # 5. 校验失败 → 重试或返回错误
    if retries_left <= 0:
        # 重试次数耗尽
        logger.warning("游戏生成重试耗尽：%d 次全部失败", attempted + 1)
        return GenerateResult(
            ok=False,
            errors=errors,
            suggestion=_build_suggestion(errors),
            retries=attempted + 1,
        )

    # 继续重试
    return await generate_game(
        db=db,
        description=description,
        title=title,
        previous_html=reply,
        previous_errors=errors,
        previous_suggestion=_build_suggestion(errors),
        retries_left=retries_left - 1,
        attempted=attempted + 1,
    )


def _build_suggestion(errors: list[ValidationError]) -> str:
    """根据校验错误生成修正建议"""
    suggestions = []
    for err in errors:
        if err.field == "structure":
            suggestions.append("请确保生成的 HTML 以 <!DOCTYPE html> 开头，包含 <html>、<head>、<body> 标签。")
        elif err.field == "template":
            suggestions.append("请确保已替换所有 <!-- GEN:config --> 和 <!-- GEN:scenes --> 标记为实际数据，不要保留任何注释标记。")
        elif err.field == "cfg":
            suggestions.append("请确保模板中的 cfg-endpoint、cfg-apikey、cfg-model 三个 input 元素未被删除。")
        elif err.field == "syntax":
            suggestions.append(f"请修复 HTML 语法错误：{err.message}")
        elif err.field == "data":
            suggestions.append(f"请修正场景数据：{err.message}")
        elif err.field == "security":
            suggestions.append(f"请移除可疑代码：{err.message}")
    return "；".join(suggestions) if suggestions else "请重新生成，确保模板标记被正确替换。"


def _persist_generated_game(
    html: str, title: str | None, *, precomputed_scan: ScanResult | None = None
) -> dict:
    """将生成的 HTML 游戏写入数据目录并注册 manifest

    Args:
        html: 生成的完整 HTML 文本
        title: 游戏标题（用于生成文件名）
        precomputed_scan: 校验闸门已计算的扫描结果（T-03），非 None 时
            import_game 跳过内部 probe_config / scan_suspicious 重复计算

    Returns:
        manifest 条目 dict

    Raises:
        OSError: 数据目录不可写
    """
    sim_dir = data_dir_service.simulators_dir()
    name = _sanitize_title(title) if title else _FALLBACK_NAME
    filename = f"{name}.html"
    content = html.encode("utf-8")

    result = import_game(
        sim_dir, filename, content, source=GENERATED_SOURCE, precomputed_scan=precomputed_scan
    )
    return result.game


def _sanitize_title(title: str) -> str:
    """将游戏标题转换为可读文件名干（只保留 Unicode 文字字符、空格、连字符）。
    这是「可读性」层（剔除标点/emoji 等装饰字符），不是安全层——下游
    import_game 内部的 sanitize_filename 会再做保留名/字节截断等安全净化。
    """
    cleaned = re.sub(r'[^\w\s-]', '', title).strip()
    return cleaned or _FALLBACK_NAME