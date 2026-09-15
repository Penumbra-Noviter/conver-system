"""
Prompt 组装 — LLM 消息列表的纯函数组装层

从 services/message.py 迁移的纯逻辑：模板变量替换、mes_example 解析、完整消息列表
组装。本模块不依赖数据库 Session，角色数据与历史消息由调用方查好传入，因此可独立
单测、可复用（如 CLI 调用 / 后续多 Provider 上下文复用）。

公开 API（__all__）：
    CharacterData              — 角色纯数据容器（不含 DB 依赖）
    InjectedSegment            — 带来源的注入分段（世界书/记忆/Mod）
    apply_template_vars        — 模板变量替换（{{user}} / {{char}}）
    parse_mes_example          — mes_example 分块多轮解析
    build_messages             — 完整消息列表组装（主入口，零来源语义）
    build_messages_with_source — 带来源标注的消息列表组装（debug 追溯）
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from backend.app.services.character_fields import PROMPT_FIELDS
from backend.app.services.text_utils import role_str

__all__ = [
    "CharacterData",
    "InjectedSegment",
    "apply_template_vars",
    "parse_mes_example",
    "build_messages",
    "build_messages_with_source",
    "SOURCE_CHARACTER",
    "SOURCE_WORLD",
    "SOURCE_MEMORY",
    "SOURCE_MOD",
    "SOURCE_HISTORY",
    "SOURCE_USER",
    "SOURCE_NARRATIVE",
]

#: 来源枚举（PD-3 debug 追溯六类；chat.py 注入链构造 InjectedSegment 时引用单一来源）
SOURCE_CHARACTER = "character"
SOURCE_WORLD = "world"
SOURCE_MEMORY = "memory"
SOURCE_MOD = "mod"
SOURCE_HISTORY = "history"
SOURCE_USER = "user"
#: 叙述风格注入段来源（02 叙述风格 prompt 注入：独立 system 段，与 after_char 同阶）
SOURCE_NARRATIVE = "narrative"


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
        prompt_mode: 组装模式（simple=结构化组装；expert=整段 expert_prompt 替代）
        expert_prompt: 专家模式整段 system prompt（仅 prompt_mode='expert' 且非空时生效）
    """
    name: str
    system_prompt: str = ""
    personality: str = ""
    scenario: str = ""
    mes_example: str = ""
    post_history_instructions: str = ""
    prompt_mode: str = "simple"
    expert_prompt: str = ""

    @classmethod
    def from_orm(cls, character: object | None) -> CharacterData:
        """ORM 角色 → 角色纯数据（唯一投影入口，F-147）

        PROMPT_FIELDS 通配投影 + prompt_mode（默认 "simple"）/ expert_prompt
        （默认 ""）补位；``character is None`` 时返回空角色 ``CharacterData(name="")``
        （对齐 build_prompt_debug 的角色可空语义）。message.build_message_list 与
        chat.build_prompt_debug 均经此入口，角色投影知识只维护一份。

        Args:
            character: 角色 ORM 实例（None → 空角色）

        Returns:
            CharacterData（name 恒在，其余字段以默认值兜底）
        """
        if character is None:
            return cls(name="")
        return cls(
            **{field: getattr(character, field, "") or "" for field in PROMPT_FIELDS},
            prompt_mode=getattr(character, "prompt_mode", "") or "simple",
            expert_prompt=getattr(character, "expert_prompt", "") or "",
        )


@dataclass(frozen=True)
class InjectedSegment:
    """带来源的注入分段（世界书/记忆/Mod 注入项，PD-3 debug 追溯）

    Attributes:
        content: 注入内容（已在注入链层做过模板变量替换）
        source: 来源（world=世界书手动条目 / memory=记忆宫殿 auto 条目 /
            mod=prompt 区 Mod）；默认 world
    """
    content: str
    source: str = SOURCE_WORLD


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
    narrative_style: str = "",
    preset_dialogue: str = "",
) -> list[dict[str, str]]:
    """组装发送给 LLM 的消息列表（纯函数，无 DB 依赖；零来源语义）

    签名与输出与 PD-3 改动前保持一致（零变化硬约束）：world 参数只接受纯字符串
    列表（世界书注入块在调用方已叠加合并），逐字节输出与改动前一致。组装顺序见
    `_assemble`——本函数与 build_messages_with_source 共用同一组装核心，来源标注
    仅 debug 路径需要。

    Args:
        character: 角色纯数据
        history: 历史消息序列（每项至少含 role 与 content 属性）
        user_content: 当前用户输入（append_current_input=False 时被忽略）
        max_rounds: 保留的对话轮数（每轮 2 条消息，滑窗上限为 max_rounds*2）
        user_name: 用户昵称（{{user}} 模板变量）
        append_current_input: 是否追加当前用户输入。True（默认）保持现组装行为；
            False 用于重生成路径（不追加当前输入，末条为历史末条 user，剥离尾随 PHI）
        world: 世界书注入块（{before_char/after_char/system: [内容]}，默认 None
            零注入；注入内容已在引擎层做过模板变量替换）
        narrative_style: 叙述风格规则文本（空串/纯空白零注入，输出与不传逐字节
            一致；非空时在 after_char 之后、[世界知识] 之前注入 [叙述风格] system 段）
        preset_dialogue: 预设对话快照文本（空串/纯空白零注入，输出与不传逐字节
            一致；非空时在 mes_example 之后、history 之前经 parse_mes_example 解析
            注入 user/assistant few-shot，source 复用 SOURCE_CHARACTER）

    Returns:
        组装好的消息列表，每项只含 role 与 content
    """
    segments = _assemble(
        character, history, user_content, max_rounds, user_name,
        append_current_input, world, narrative_style, preset_dialogue,
    )
    return [{"role": s["role"], "content": s["content"]} for s in segments]


def build_messages_with_source(
    character: CharacterData,
    history: Sequence[object],
    user_content: str,
    max_rounds: int = 30,
    user_name: str = "User",
    append_current_input: bool = True,
    world: dict[str, list[str | InjectedSegment]] | None = None,
    narrative_style: str = "",
    preset_dialogue: str = "",
) -> list[dict[str, str]]:
    """组装发送给 LLM 的消息列表，逐条标注来源（PD-3 debug 追溯专用，只读见证）

    与 build_messages 共用同一组装核心 `_assemble`（单一组装实现，不复制顺序），
    仅多返回每条 source 字段。world 参数额外接受 InjectedSegment 项以携带来源
    （world/memory/mod）；纯字符串项回退来源 world（与 build_messages 等价）。

    来源枚举见模块常量 SOURCE_CHARACTER / SOURCE_WORLD / SOURCE_MEMORY /
    SOURCE_MOD / SOURCE_HISTORY / SOURCE_USER / SOURCE_NARRATIVE。

    Args:
        character: 角色纯数据
        history: 历史消息序列
        user_content: 当前用户输入
        max_rounds: 保留的对话轮数
        user_name: 用户昵称
        append_current_input: 是否追加当前用户输入
        world: 带来源注入块（{before_char/after_char/system: [内容或 InjectedSegment]}）
        narrative_style: 叙述风格规则文本（非空时注入 source=narrative 的
            [叙述风格] system 段；空串/纯空白零注入）
        preset_dialogue: 预设对话快照文本（非空时注入 source=character 的
            user/assistant few-shot；空串/纯空白零注入）

    Returns:
        带 source 的消息分段列表，content/role 序列与 build_messages 逐条一致
    """
    return _assemble(
        character, history, user_content, max_rounds, user_name,
        append_current_input, world, narrative_style, preset_dialogue,
    )


def _assemble(
    character: CharacterData,
    history: Sequence[object],
    user_content: str,
    max_rounds: int,
    user_name: str,
    append_current_input: bool,
    world: dict[str, list[str | InjectedSegment]] | None,
    narrative_style: str,
    preset_dialogue: str,
) -> list[dict[str, str]]:
    """消息列表组装核心（私有；build_messages / build_messages_with_source 共用）

    组装顺序（PD-5 已含 expert 分流）：
        0. world["before_char"] 注入块（逐条 system，最高优先级）
        1. system prompt（system_prompt 优先，否则 personality）；expert 模式以
           expert_prompt 单条替代 1/2/5 三处结构化注入
        2. scenario（[场景设定] system）
        2.5 world["after_char"] 注入块
        2.7 narrative_style 非空时注入 [叙述风格] system（source=narrative；
            expert/simple 皆注入，因 after_char 不在 expert 替代范围）
        2.75 world["system"] 合并单条 [世界知识]（多条以空行连接）
        3. mes_example（few-shot）
        3.5 preset_dialogue 非空时注入预设对话 few-shot（source=character；
            mes_example 之后、history 之前）
        4. 历史消息（正序，滑窗截断）
        5. post_history_instructions（system；expert 模式跳过）
        6. 当前 user 输入（append_current_input=False 时剥离尾随 system）
    """
    char_name = character.name or "Character"
    world = world or {}
    # 空/纯空白注入内容不产生空 system 消息（Falsify 修复锁：`or []` 只挡
    # None/空列表，列表内的空串元素须在此过滤）
    world_before = _filter_injection(world.get("before_char"))
    world_after = _filter_injection(world.get("after_char"))
    world_knowledge = _filter_injection(world.get("system"))

    expert = (
        character.prompt_mode == "expert"
        and bool(character.expert_prompt and character.expert_prompt.strip())
    )

    segments: list[dict[str, str]] = []

    for content, source in world_before:
        segments.append({"role": "system", "content": content, "source": source})

    if expert:
        segments.append({
            "role": "system",
            "content": apply_template_vars(character.expert_prompt, user_name, char_name),
            "source": SOURCE_CHARACTER,
        })
    else:
        system_content = character.system_prompt or character.personality
        segments.append({
            "role": "system",
            "content": apply_template_vars(system_content, user_name, char_name),
            "source": SOURCE_CHARACTER,
        })
        if character.scenario:
            scenario = apply_template_vars(character.scenario, user_name, char_name)
            segments.append({
                "role": "system",
                "content": f"[场景设定]\n{scenario}",
                "source": SOURCE_CHARACTER,
            })

    for content, source in world_after:
        segments.append({"role": "system", "content": content, "source": source})

    # 02 叙述风格注入：after_char 之后、[世界知识] 之前；空/纯空白零注入（与不传
    # narrative_style 输出逐字节一致）。expert 模式同样注入（after_char 不在替代范围）。
    if narrative_style and narrative_style.strip():
        segments.append({
            "role": "system",
            "content": f"[叙述风格]\n{narrative_style}",
            "source": SOURCE_NARRATIVE,
        })

    if world_knowledge:
        merged_source = _world_knowledge_source([s for _, s in world_knowledge])
        segments.append({
            "role": "system",
            "content": "[世界知识]\n" + "\n\n".join(c for c, _ in world_knowledge),
            "source": merged_source,
        })

    if character.mes_example:
        for example in parse_mes_example(character.mes_example, user_name, char_name):
            segments.append({
                "role": example["role"],
                "content": example["content"],
                "source": SOURCE_CHARACTER,
            })

    # 06 预设对话 few-shot 注入：mes_example 之后、history 之前；空/纯空白零注入
    # （与不传 preset_dialogue 输出逐字节一致）。source 复用 SOURCE_CHARACTER
    # （预设对话是角色提供的示范，与 mes_example 同源，不新增 source 常量）。
    if preset_dialogue and preset_dialogue.strip():
        for example in parse_mes_example(preset_dialogue, user_name, char_name):
            segments.append({
                "role": example["role"],
                "content": example["content"],
                "source": SOURCE_CHARACTER,
            })

    history_list = list(history)
    if len(history_list) > max_rounds * 2:
        history_list = history_list[-(max_rounds * 2):]

    for msg in history_list:
        segments.append({
            "role": role_str(msg.role),
            "content": msg.content,
            "source": SOURCE_HISTORY,
        })

    if not expert and character.post_history_instructions:
        phi = apply_template_vars(character.post_history_instructions, user_name, char_name)
        segments.append({"role": "system", "content": phi, "source": SOURCE_CHARACTER})

    if append_current_input:
        content = apply_template_vars(user_content, user_name, char_name)
        segments.append({"role": "user", "content": content, "source": SOURCE_USER})
    else:
        # 重生成路径：末条须为历史末条 user（触发源）。无当前 user 末尾兜底时，
        # 步骤 5 的 PHI（system）会成为末条，故先剥离全部尾随 system。
        while segments and segments[-1].get("role") == "system":
            segments.pop()

    return segments


def _split_injection(item: str | InjectedSegment) -> tuple[str, str]:
    """注入项 → (content, source)；纯字符串回退来源 world"""
    if isinstance(item, InjectedSegment):
        return item.content, item.source
    return item, SOURCE_WORLD


def _filter_injection(
    items: list[str | InjectedSegment] | None,
) -> list[tuple[str, str]]:
    """过滤空/纯空白注入项，返回 [(content, source)]（保持给定序）"""
    result: list[tuple[str, str]] = []
    for item in items or []:
        content, source = _split_injection(item)
        if content and content.strip():
            result.append((content, source))
    return result


def _world_knowledge_source(sources: list[str]) -> str:
    """[世界知识] 合并块来源：单一来源取之；混合来源回落 world（文档化兜底）

    world/memory 皆属世界书条目、mod 亦可能追加进 system 块；混合时以 world 兜底
    （内容一致性不受来源标注影响，debug 只见证不改线上）。
    """
    distinct = set(sources)
    if len(distinct) == 1:
        return sources[0]
    return SOURCE_WORLD
