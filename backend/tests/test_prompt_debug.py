"""
PD-3 Prompt Debug 后端 — 契约锁测试

锁定语义（docs/prompt-polish-spec.md §3 PD-3 六条验收标准）：
1. simple 模式角色：segments 顺序 = before_char → system → scenario → after_char
   → world → mes_example → history → post_history → user，来源逐段正确
2. expert 模式角色：system 段单条 expert_prompt，来源 character
3. 世界书 manual → world；记忆宫殿 auto → memory
4. prompt 区 Mod → mod（与 world 分开标注）
5. 空对话（无历史）+ 无注入 → 仅 system（character）+ user（user）
6. debug 追溯 content 与 assemble_chat_context 产出 messages 逐条一致（只见证、不改线上）

另覆盖（Falsify）：world/memory/mod 组合、expert 组合、空态、重生成路径、
[世界知识] 混合来源回落、build_messages 零变化（纯字符串 world 等价）。
"""

from __future__ import annotations

from types import SimpleNamespace

from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.lorebook import LorebookEntryCreate
from backend.app.schemas.mods import ModCreate
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import mods as mods_service
from backend.app.services import setting as setting_service
from backend.app.services.llm import resolver as llm_resolver
from backend.app.services.llm.prompt import (
    CharacterData,
    InjectedSegment,
    build_messages,
    build_messages_with_source,
)

__all__: list[str] = []


# ════════════════════════════════════════════════════════════════
# 纯数据构造
# ════════════════════════════════════════════════════════════════


def _character(**overrides: object) -> CharacterData:
    """角色纯数据工厂（字段可覆盖）"""
    base: dict[str, object] = {
        "name": "测试角色",
        "system_prompt": "",
        "personality": "你是测试角色。",
        "scenario": "月下竹林",
        "mes_example": "",
        "post_history_instructions": "",
    }
    base.update(overrides)
    return CharacterData(**base)  # type: ignore[arg-type]


def _msg(role: str, content: str) -> SimpleNamespace:
    """假消息（role + content 双属性）"""
    return SimpleNamespace(role=role, content=content)


def _history(*pairs: tuple[str, str]) -> list[SimpleNamespace]:
    return [_msg(role, content) for role, content in pairs]


# ════════════════════════════════════════════════════════════════
# 一、simple 模式全序 + 来源（锁 1）
# ════════════════════════════════════════════════════════════════


def test_simple_mode_full_order_sources() -> None:
    """simple 全序：before_char/system/scenario/after_char/world/mes_example/
    history/post_history/user，来源逐段正确"""
    char = _character(
        mes_example="<START>\n{{user}}: 例1\n{{char}}: 例2",
        post_history_instructions="保持人设。",
    )
    history = _history(("user", "历史1"), ("assistant", "历史2"))
    world: dict[str, list[InjectedSegment]] = {
        "before_char": [InjectedSegment("角色前置", "world")],
        "system": [InjectedSegment("背景一", "world")],
        "after_char": [InjectedSegment("场景后", "world")],
    }
    segments = build_messages_with_source(char, history, "当前输入", world=world)

    assert segments == [
        {"role": "system", "content": "角色前置", "source": "world"},
        {"role": "system", "content": "你是测试角色。", "source": "character"},
        {"role": "system", "content": "[场景设定]\n月下竹林", "source": "character"},
        {"role": "system", "content": "场景后", "source": "world"},
        {"role": "system", "content": "[世界知识]\n背景一", "source": "world"},
        {"role": "user", "content": "例1", "source": "character"},
        {"role": "assistant", "content": "例2", "source": "character"},
        {"role": "user", "content": "历史1", "source": "history"},
        {"role": "assistant", "content": "历史2", "source": "history"},
        {"role": "system", "content": "保持人设。", "source": "character"},
        {"role": "user", "content": "当前输入", "source": "user"},
    ]


# ════════════════════════════════════════════════════════════════
# 二、expert 模式分流（锁 2）
# ════════════════════════════════════════════════════════════════


def test_expert_single_system_source_character() -> None:
    """expert + 非空 → system 段单条 expert_prompt，来源 character，无 scenario/PHI"""
    char = _character(
        prompt_mode="expert",
        expert_prompt="你是{{char}}，专家指令。",
        system_prompt="系统提示",  # 应被忽略
        scenario="场景设定",  # 应被忽略
        post_history_instructions="历史指令",  # 应被忽略
    )
    segments = build_messages_with_source(char, [], "你好")
    assert segments == [
        {"role": "system", "content": "你是测试角色，专家指令。", "source": "character"},
        {"role": "user", "content": "你好", "source": "user"},
    ]


# ════════════════════════════════════════════════════════════════
# 三、[世界知识] 混合来源回落 + 重生成路径（Falsify）
# ════════════════════════════════════════════════════════════════


def test_world_knowledge_mixed_source_falls_back_world() -> None:
    """[世界知识] 合并块混合 world/memory 来源 → 回落 world（内容仍逐条合并）"""
    world: dict[str, list[InjectedSegment]] = {
        "system": [
            InjectedSegment("手动知识", "world"),
            InjectedSegment("记忆知识", "memory"),
        ],
    }
    segments = build_messages_with_source(_character(), [], "输入", world=world)
    world_segments = [s for s in segments if "世界知识" in s["content"]]
    assert world_segments == [
        {"role": "system", "content": "[世界知识]\n手动知识\n\n记忆知识", "source": "world"},
    ]


def test_plain_string_world_defaults_source_world() -> None:
    """world 内纯字符串项 → 来源回退 world，content 与 build_messages 一致"""
    world = {"system": ["纯字符串知识"]}
    segments = build_messages_with_source(_character(), [], "输入", world=world)
    world_segments = [s for s in segments if "世界知识" in s["content"]]
    assert world_segments == [
        {"role": "system", "content": "[世界知识]\n纯字符串知识", "source": "world"},
    ]


def test_regenerate_path_no_trailing_system() -> None:
    """append_current_input=False：末条为历史末条 user，无尾随 system，来源保真"""
    char = _character(post_history_instructions="保持人设。")
    history = _history(("user", "问1"), ("assistant", "答1"), ("user", "问2"))
    segments = build_messages_with_source(char, history, "忽略", append_current_input=False)
    assert segments[-1] == {"role": "user", "content": "问2", "source": "history"}
    assert segments[-1]["role"] != "system"


def test_empty_world_byte_identical_to_build_messages() -> None:
    """world=None 时 build_messages_with_source 与 build_messages 逐 content 一致"""
    char = _character(mes_example="<START>\n{{user}}: 例\n{{char}}: 例2", post_history_instructions="PHI")
    history = _history(("user", "问"), ("assistant", "答"))
    msgs = build_messages(char, history, "输入")
    segments = build_messages_with_source(char, history, "输入")
    assert [s["content"] for s in segments] == [m["content"] for m in msgs]
    assert [s["role"] for s in segments] == [m["role"] for m in msgs]


# ════════════════════════════════════════════════════════════════
# 集成：build_prompt_debug 来源保真（锁 3 / 锁 4 / 锁 5）
# ════════════════════════════════════════════════════════════════


def _create_character(db: Session, **overrides: object) -> Character:
    """落库角色（可覆盖字段）"""
    base = {
        "name": "世界书角色",
        "personality": "你是世界书测试角色。",
        "scenario": "测试场景",
        "first_mes": "",
        "system_prompt": "",
        "post_history_instructions": "",
        "mes_example": "",
    }
    base.update(overrides)
    char = Character(**base)
    db.add(char)
    db.commit()
    db.refresh(char)
    return char


def _create_conversation(db: Session, character_id: int) -> Conversation:
    """落库对话（默认 provider/model）"""
    return conversation_service.create_conversation(
        db, ConversationCreate(character_id=character_id)
    )


def test_debug_world_manual_vs_memory_auto(db_session) -> None:
    """锁 3：manual 条目 → world；auto 条目 → memory（世界书与记忆宫殿分开）"""
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    lorebook_service.create_entry(
        db_session, char.id,
        LorebookEntryCreate(keys=(), content="手动世界知识", constant=True, position="before_char", source="manual"),
    )
    lorebook_service.create_entry(
        db_session, char.id,
        LorebookEntryCreate(keys=(), content="记忆条目", constant=True, position="world", source="auto"),
    )

    debug = chat_service.build_prompt_debug(db_session, conv.id)

    by_content = {s.content: s.source for s in debug.segments}
    assert by_content["手动世界知识"] == "world"
    assert by_content["[世界知识]\n记忆条目"] == "memory"


def test_debug_mod_source_separate_from_world(db_session) -> None:
    """锁 4：prompt 区 Mod → mod，与 world 手动条目分开标注"""
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    lorebook_service.create_entry(
        db_session, char.id,
        LorebookEntryCreate(keys=(), content="手动世界知识", constant=True, position="before_char", source="manual"),
    )
    mod = mods_service.create_mod(
        db_session, ModCreate(name="提示词 Mod", target_area="prompt", payload='{"before_char": "mod 注入内容"}')
    )
    mods_service.bind_mod(db_session, char.id, mod.id)

    debug = chat_service.build_prompt_debug(db_session, conv.id)

    by_content = {s.content: s.source for s in debug.segments}
    assert by_content["手动世界知识"] == "world"
    assert by_content["mod 注入内容"] == "mod"


def test_debug_empty_conversation_minimal(db_session) -> None:
    """锁 5：空对话（无历史、无注入、无 scenario）→ 仅 system(character) + user(user)"""
    char = _create_character(db_session, personality="你是空态角色。", scenario="", first_mes="")
    conv = _create_conversation(db_session, char.id)

    debug = chat_service.build_prompt_debug(db_session, conv.id)

    assert [s.model_dump() for s in debug.segments] == [
        {"role": "system", "content": "你是空态角色。", "source": "character"},
        {"role": "user", "content": "", "source": "user"},
    ]
    assert debug.character_name == "世界书角色"
    assert debug.model == "claude/claude-sonnet-5"
    assert debug.prompt_mode == "simple"


# ════════════════════════════════════════════════════════════════
# 集成：debug 与 assemble_chat_context 逐条 content 一致（锁 6）
# ════════════════════════════════════════════════════════════════


class _FakeProvider:
    """记录 generate 调用参数的假 Provider（组装测试不实际生成）"""

    async def generate(self, messages, temperature=0.7, max_tokens=2048, model=None):
        return "回复"


class _FakeLLMFactory:
    """替代 LLMFactory.get_provider 的工厂"""

    def __init__(self, provider: _FakeProvider) -> None:
        self.provider = provider

    def get_provider(self, name, api_key, base_url=None):
        return self.provider


def test_debug_content_matches_assemble_chat_context(db_session, monkeypatch) -> None:
    """锁 6：debug segments content 与 assemble_chat_context messages 逐条一致"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")
    fake = _FakeProvider()
    monkeypatch.setattr(llm_resolver, "LLMFactory", _FakeLLMFactory(fake))

    char = _create_character(db_session, mes_example="<START>\n{{user}}: 例1\n{{char}}: 例2", post_history_instructions="保持人设。")
    conv = _create_conversation(db_session, char.id)
    lorebook_service.create_entry(
        db_session, char.id,
        LorebookEntryCreate(keys=(), content="常驻指引", constant=True, position="before_char", source="manual"),
    )
    mod = mods_service.create_mod(
        db_session, ModCreate(name="提示词 Mod", target_area="prompt", payload='{"before_char": "mod 内容"}')
    )
    mods_service.bind_mod(db_session, char.id, mod.id)

    debug = chat_service.build_prompt_debug(db_session, conv.id)
    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="")

    assert [s.content for s in debug.segments] == [m["content"] for m in ctx.messages]
    assert [s.role for s in debug.segments] == [m["role"] for m in ctx.messages]


# ════════════════════════════════════════════════════════════════
# 集成：expert 模式经 build_prompt_debug（锁 2 服务层）
# ════════════════════════════════════════════════════════════════


def test_debug_expert_mode(db_session) -> None:
    """expert 角色经 build_prompt_debug：prompt_mode=expert，system 单条来源 character"""
    char = _create_character(
        db_session, prompt_mode="expert", expert_prompt="你是{{char}}，专家整段。", scenario="", first_mes=""
    )
    conv = _create_conversation(db_session, char.id)

    debug = chat_service.build_prompt_debug(db_session, conv.id)

    assert debug.prompt_mode == "expert"
    assert [s.model_dump() for s in debug.segments] == [
        {"role": "system", "content": "你是世界书角色，专家整段。", "source": "character"},
        {"role": "user", "content": "", "source": "user"},
    ]
