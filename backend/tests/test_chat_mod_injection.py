"""
assemble_chat_context prompt 区 Mod 注入链集成契约锁（MD-2/02，chat 层）

锁定语义（.scratch/md-2/spec.md §后端 prompt 区注入链集成）：
- 世界书注入块产出之后、构建消息列表之前，读取角色启用 prompt 区 Mod →
  ModPayload → apply_prompt_mods 叠加进 world_injection（world→system）
- 禁用绑定零影响；非 prompt 区（memory/css）零影响
- 多个启用 prompt Mod 按 (sort_order, mod_id) 升序叠加（同序 mod_id 稳定）
- 无 Mod / 无绑定零回归（复用 test_chat_world_injection 基线锁定）
- 叠加在世界书注入之上（追加各块），不新增尾随 system（不恶化 F-99）
"""

from __future__ import annotations

import json

from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.lorebook import LorebookEntryCreate
from backend.app.schemas.mods import ModCreate
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import mods as mods_service
from backend.app.services import setting as setting_service
from backend.app.services.llm import resolver as llm_resolver

__all__: list[str] = []


class _FakeProvider:
    """记录 generate 调用参数的假 Provider（组装测试不实际生成）"""

    def __init__(self) -> None:
        self.calls: list[tuple] = []

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        self.calls.append((messages, temperature, max_tokens, model))
        return "回复"


class _FakeLLMFactory:
    """替代 LLMFactory.get_provider 的工厂（与 test_chat_world_injection 同模式）"""

    def __init__(self, provider: _FakeProvider) -> None:
        self.provider = provider

    def get_provider(self, name: str, api_key: str, base_url: str | None = None) -> _FakeProvider:
        return self.provider


def _patch_llm_env(monkeypatch) -> _FakeProvider:
    """打桩 resolve_llm 依赖（api_key + 工厂），返回假 Provider 实例"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")
    fake = _FakeProvider()
    monkeypatch.setattr(llm_resolver, "LLMFactory", _FakeLLMFactory(fake))
    return fake


def _create_character(db: Session, name: str = "Mod注入角色") -> Character:
    """落库角色（无 greeting / scenario / mes_example，结构可预测，简化断言）"""
    char = Character(name=name, personality="你是角色人格设定。", scenario="", first_mes="")
    db.add(char)
    db.commit()
    db.refresh(char)
    return char


def _create_conversation(db: Session, character_id: int):
    """落库对话（默认 provider/model 回退 settings）"""
    return conversation_service.create_conversation(
        db, ConversationCreate(character_id=character_id)
    )


def _create_mod(
    db: Session,
    *,
    name: str = "测试 Mod",
    target_area: str = "prompt",
    payload: str = "",
) -> int:
    """落库一个 Mod，返回其 id"""
    mod = mods_service.create_mod(
        db,
        ModCreate(name=name, target_area=target_area, payload=payload),
    )
    return mod.id


def _prompt_payload(world: str = "", before_char: str = "", after_char: str = "") -> str:
    """构造 prompt 区 payload JSON 文本（三区域）"""
    return json.dumps(
        {"world": world, "before_char": before_char, "after_char": after_char},
        ensure_ascii=False,
    )


def _bind(
    db: Session,
    character_id: int,
    mod_id: int,
    *,
    sort_order: int | None = None,
    enabled: bool = True,
) -> int:
    """挂载 Mod 到角色并返回绑定 id"""
    return mods_service.bind_mod(
        db, character_id, mod_id, enabled=enabled, sort_order=sort_order
    ).id


def _base_messages() -> list[dict]:
    """无任何注入时的基线消息列表（personality system + 当前 user 输入）"""
    return [
        {"role": "system", "content": "你是角色人格设定。"},
        {"role": "user", "content": "你好"},
    ]


# ════════════════════════════════════════════════════════════════
# 一、单启用 prompt Mod：三区域各就位
# ════════════════════════════════════════════════════════════════


def test_prompt_mod_injects_three_regions(db_session, monkeypatch) -> None:
    """启用 prompt Mod（world/before_char/after_char）→ 各注入块就位；无世界书时仍产出注入块"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    mod_id = _create_mod(
        db_session,
        name="三区域 Mod",
        payload=_prompt_payload(world="W", before_char="B", after_char="A"),
    )
    _bind(db_session, char.id, mod_id)

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

    assert ctx.messages == [
        {"role": "system", "content": "B"},  # before_char 在 system prompt 之前
        {"role": "system", "content": "你是角色人格设定。"},
        {"role": "system", "content": "A"},  # after_char 在 system prompt 之后
        {"role": "system", "content": "[世界知识]\nW"},  # world → system
        {"role": "user", "content": "你好"},
    ]


# ════════════════════════════════════════════════════════════════
# 二、禁用绑定 / 非 prompt 区零影响
# ════════════════════════════════════════════════════════════════


def test_disabled_binding_zero_effect(db_session, monkeypatch) -> None:
    """禁用绑定（enabled=False）→ 注入结果与无 Mod 时相等（零影响）"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    mod_id = _create_mod(
        db_session,
        name="禁用 Mod",
        payload=_prompt_payload(world="不该出现", before_char="不该出现", after_char="不该出现"),
    )
    _bind(db_session, char.id, mod_id, enabled=False)

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

    assert ctx.messages == _base_messages()


def test_non_prompt_target_zero_effect(db_session, monkeypatch) -> None:
    """memory / css 区 Mod 不进入 prompt 注入块（零影响）"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    mem_id = _create_mod(
        db_session, name="记忆 Mod", target_area="memory",
        payload=_prompt_payload(world="记忆不该进"),
    )
    css_id = _create_mod(
        db_session, name="样式 Mod", target_area="css",
        payload=_prompt_payload(world="样式不该进"),
    )
    _bind(db_session, char.id, mem_id)
    _bind(db_session, char.id, css_id)

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

    assert ctx.messages == _base_messages()


# ════════════════════════════════════════════════════════════════
# 三、无 Mod / 无绑定零回归
# ════════════════════════════════════════════════════════════════


def test_no_bindings_zero_change(db_session, monkeypatch) -> None:
    """角色无任何 Mod 绑定 → 组装结果与改动前一致（零回归）"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

    assert ctx.messages == _base_messages()


# ════════════════════════════════════════════════════════════════
# 四、多启用 prompt Mod：按 (sort_order, mod_id) 升序叠加
# ════════════════════════════════════════════════════════════════


def test_multiple_prompt_mods_sorted_by_sort_order_then_mod_id(db_session, monkeypatch) -> None:
    """多个启用 prompt Mod 按 (sort_order, mod_id) 升序叠加（同序按 mod_id 稳定）"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    m1 = _create_mod(db_session, name="M1", payload=_prompt_payload(world="早"))
    m2 = _create_mod(db_session, name="M2", payload=_prompt_payload(world="中"))
    m3 = _create_mod(db_session, name="M3", payload=_prompt_payload(world="晚"))
    # m2 先挂（同 sort_order=0 下按 mod_id 决胜 → m1 在前）
    _bind(db_session, char.id, m2, sort_order=0)
    _bind(db_session, char.id, m1, sort_order=0)
    _bind(db_session, char.id, m3, sort_order=1)

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

    world_msg = next(m for m in ctx.messages if m["role"] == "system" and "[世界知识]" in m["content"])
    assert world_msg["content"] == "[世界知识]\n早\n\n中\n\n晚"


# ════════════════════════════════════════════════════════════════
# 五、叠加在世界书注入之上，不新增尾随 system
# ════════════════════════════════════════════════════════════════


def test_mod_overlays_on_top_of_lorebook_no_trailing_system(db_session, monkeypatch) -> None:
    """Mod 注入追加到世界书注入之上（同 [世界知识] 块），不新增尾随 system 消息"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    lorebook_service.create_entry(
        db_session, char.id,
        LorebookEntryCreate(keys=(), content="世界书内容", constant=True, position="world"),
    )
    mod_id = _create_mod(db_session, name="世界 Mod", payload=_prompt_payload(world="Mod内容"))
    _bind(db_session, char.id, mod_id)

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

    world_msgs = [m for m in ctx.messages if m["role"] == "system" and "[世界知识]" in m["content"]]
    assert len(world_msgs) == 1  # 世界书 + Mod 合并为单条，不新增独立尾随 system
    assert world_msgs[0]["content"] == "[世界知识]\n世界书内容\n\nMod内容"  # 世界书在前、Mod 追加在后
    assert ctx.messages[-1] == {"role": "user", "content": "你好"}  # 末条仍为 user，无尾随 system
