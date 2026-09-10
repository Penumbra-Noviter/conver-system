"""
Prompt 组装 — LLM 消息列表的纯函数组装层

从 services/message.py 迁移的纯逻辑：模板变量替换、mes_example 解析、完整消息列表
组装。本模块不依赖数据库 Session，角色数据与历史消息由调用方查好传入，因此可独立
单测、可复用（如 CLI 调用 / 后续多 Provider 上下文复用）。

公开 API（__all__）：
    CharacterData           — 角色纯数据容器（不含 DB 依赖）
    apply_template_vars     — 模板变量替换（{{user}} / {{char}}）
    parse_mes_example       — mes_example 分块多轮解析
    build_messages          — 完整消息列表组装（主入口）
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from backend.app.services.character_fields import PROMPT_FIELDS
from backend.app.services.text_utils import role_str

__all__ = ["CharacterData", "apply_template_vars", "parse_mes_example", "build_messages"]


@dataclass(frozen=True)
class CharacterData:
    """角色纯数据（不含 DB 依赖），供 Prompt 组装使用

    Attributes:
        name: 角色名称（{{char}} 模板变量来源）
        system_prompt: 覆盖式系统提示词（优先于 personality）
        personality: 人格设定（system_prompt 为空时回退）
        scenario: 场景设定（组装为 [场景设定]\\n... 的 system 消息）
        mes_example: 对话范例（few-shot，<START> 分隔多轮）
        post_history_instructions: 历史后指令（历史之后、当前输入之前）
    """
    name: str
    system_prompt: str = ""
    personality: str = ""
    scenario: str = ""
    mes_example: str = ""
    post_history_instructions: str = ""


def apply_template_vars(text: str, user_name: str = "User", char_name: str = "Character") -> str:
    """替换文本中的模板变量

    支持变量:
        {{user}}  — 用户昵称（从设置读取）
        {{char}}  — 角色名称（从角色数据读取）
    """
    if not text:
        return text
    return text.replace("{{user}}", user_name).replace("{{char}}", char_name)


def parse_mes_example(
    mes_example: str,
    user_name: str = "User",
    char_name: str = "Character",
) -> list[dict[str, str]]:
    """解析 mes_example 对话范例为 user/assistant 消息序列

    支持 <START> 分隔的多轮范例，每行格式为 {{user}}: 或 {{char}}: 开头。
    参考 SillyTavern V2 规范，{{user}} 映射为 user 角色，{{char}} 映射为 assistant 角色。
    同时替换消息内容中的 {{user}}/{{char}} 模板变量。
    """
    if not mes_example or not mes_example.strip():
        return []

    messages: list[dict[str, str]] = []
    # 按 <START> 分隔多轮范例
    blocks = mes_example.split("<START>")

    for block in blocks:
        block = block.strip()
        if not block:
            continue

        for line in block.split("\n"):
            line = line.strip()
            if not line:
                continue
            if line.startswith("{{user}}"):
                content = line[len("{{user}}"):].lstrip(":").strip()
                if content:
                    messages.append({
                        "role": "user",
                        "content": apply_template_vars(content, user_name, char_name),
                    })
            elif line.startswith("{{char}}"):
                content = line[len("{{char}}"):].lstrip(":").strip()
                if content:
                    messages.append({
                        "role": "assistant",
                        "content": apply_template_vars(content, user_name, char_name),
                    })

    return messages


def build_messages(
    character: CharacterData,
    history: Sequence[object],
    user_content: str,
    max_rounds: int = 30,
    user_name: str = "User",
    append_current_input: bool = True,
    world: dict[str, list[str]] | None = None,
) -> list[dict[str, str]]:
    """组装发送给 LLM 的消息列表（纯函数，无 DB 依赖）

    组装顺序：
        0. world["before_char"] 注入块（世界书：角色 system prompt 之前，逐条 system）
        1. system prompt（system_prompt 优先，否则 personality）
        2. scenario（作为 [场景设定]\\n... 的 system 消息）
        2.5 world["after_char"] 注入块（世界书：场景设定之后，逐条 system）
        2.75 world["system"] 合并为单条 [世界知识] system（多条以空行连接，按给定序）
        3. mes_example（few-shot 示例）
        4. 历史消息（正序，滑窗截断：超过 max_rounds*2 条取最后 max_rounds*2 条）
        5. post_history_instructions（system 消息）
        6. 当前 user 输入（append_current_input=True 时）

    world 参数（WL-3）：None 或全空列表时零注入、输出与改动前逐字节一致
    （零变化硬约束，由既有用例锁定）；键即注入位置（world="system" 为世界书
    position='world' 内容，见 lorebook_engine.build_world_injection 契约）。

    append_current_input=False 契约（重生成路径）：
        不追加当前 user 输入；末条恢复为历史末条 user（待回复触发源）；
        因无 user 末尾兜底而残留的尾随 PHI system 一并剥离，保证末端无 system。

    Args:
        character: 角色纯数据
        history: 历史消息序列（每项至少含 role 与 content 属性）
        user_content: 当前用户输入（False 时被忽略、不校验、不追加）
        max_rounds: 保留的对话轮数（每轮 2 条消息，滑窗上限为 max_rounds*2）
        user_name: 用户昵称（{{user}} 模板变量）
        append_current_input: 是否追加当前用户输入。True（默认）逐字保持现
            组装行为；False 用于重生成路径（不追加当前输入，末条为历史末条
            user，剥离尾随 PHI system）。
        world: 世界书注入块（{before_char/after_char/system: [内容]}，默认 None
            零注入；注入内容已在引擎层做过模板变量替换，此处不重复处理）

    Returns:
        组装好的消息列表，role 均为纯字符串 system/user/assistant
    """
    char_name = character.name or "Character"
    world = world or {}
    # 空/纯空白注入内容不产生空 system 消息（Falsify 修复锁：`or []` 只挡
    # None/空列表，列表内的空串元素须在此过滤）
    world_before = [c for c in (world.get("before_char") or []) if c and c.strip()]
    world_after = [c for c in (world.get("after_char") or []) if c and c.strip()]
    world_knowledge = [c for c in (world.get("system") or []) if c and c.strip()]

    messages: list[dict[str, str]] = []

    # 0. before_char 注入块（世界书）：角色 system prompt 之前，最高优先级上下文
    for content in world_before:
        messages.append({"role": "system", "content": content})

    # 1. system prompt（优先使用 system_prompt 字段，其次 personality）
    system_content = character.system_prompt or character.personality
    messages.append({
        "role": "system",
        "content": apply_template_vars(system_content, user_name, char_name),
    })

    # 2. 场景设定（scenario）— 附加在 system prompt 后，作为补充上下文
    if character.scenario:
        scenario = apply_template_vars(character.scenario, user_name, char_name)
        messages.append({"role": "system", "content": f"[场景设定]\n{scenario}"})

    # 2.5 after_char 注入块（世界书）：场景设定之后
    for content in world_after:
        messages.append({"role": "system", "content": content})

    # 2.75 world 知识（世界书）：合并为单条 [世界知识] system，多条以空行连接
    if world_knowledge:
        messages.append({
            "role": "system",
            "content": "[世界知识]\n" + "\n\n".join(world_knowledge),
        })

    # 3. 对话范例（mes_example）— 作为 few-shot 示例插入
    if character.mes_example:
        messages.extend(parse_mes_example(character.mes_example, user_name, char_name))

    # 4. 历史消息（滑窗截断，保留最近 max_rounds 轮对话）
    history_list = list(history)
    if len(history_list) > max_rounds * 2:
        history_list = history_list[-(max_rounds * 2):]

    for msg in history_list:
        messages.append({"role": role_str(msg.role), "content": msg.content})

    # 5. 历史后指令（post_history_instructions）— 附加在历史消息之后、当前输入之前
    if character.post_history_instructions:
        phi = apply_template_vars(character.post_history_instructions, user_name, char_name)
        messages.append({"role": "system", "content": phi})

    # 6. 当前输入（append_current_input=False 时不追加，并剥离尾随 PHI system）
    if append_current_input:
        content = apply_template_vars(user_content, user_name, char_name)
        messages.append({"role": "user", "content": content})
    else:
        # 重生成路径：末条须为历史末条 user（触发源）。无当前 user 末尾兜底时，
        # 步骤 5 的 PHI（system）会成为末条，故先剥离全部尾随 system。
        while messages and messages[-1].get("role") == "system":
            messages.pop()

    return messages
