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


# ════════════════════════════════════════════════════════════════
# 六、memory 区回读链路（T3：_memory_mod_instructions，归纳注入数据源）
# ════════════════════════════════════════════════════════════════


def test_memory_mod_instructions_sort_order_then_mod_id(db_session) -> None:
    """多个启用 memory Mod 按 (sort_order, mod_id) 升序以 \\n 连接（纯文本直拼）"""
    char = _create_character(db_session)
    m1 = _create_mod(db_session, name="M1", target_area="memory", payload="口径一")
    m2 = _create_mod(db_session, name="M2", target_area="memory", payload="口径二")
    m3 = _create_mod(db_session, name="M3", target_area="memory", payload="口径三")
    # m2 先挂（同 sort_order=0 下按 mod_id 决胜 → m1 在前）
    _bind(db_session, char.id, m2, sort_order=0)
    _bind(db_session, char.id, m1, sort_order=0)
    _bind(db_session, char.id, m3, sort_order=1)

    assert chat_service._memory_mod_instructions(db_session, char) == "口径一\n口径二\n口径三"


def test_memory_mod_instructions_filters_disabled_and_other_areas(db_session) -> None:
    """disabled 绑定与 target_area 为 prompt/css 的 Mod 不出现"""
    char = _create_character(db_session)
    mem_ok = _create_mod(db_session, name="记忆", target_area="memory", payload="口径")
    mem_off = _create_mod(db_session, name="禁用记忆", target_area="memory", payload="不该出现")
    prompt_mod = _create_mod(db_session, name="提示", target_area="prompt", payload="提示不该出现")
    css_mod = _create_mod(db_session, name="样式", target_area="css", payload="样式不该出现")
    _bind(db_session, char.id, mem_ok)
    _bind(db_session, char.id, mem_off, enabled=False)
    _bind(db_session, char.id, prompt_mod)
    _bind(db_session, char.id, css_mod)

    assert chat_service._memory_mod_instructions(db_session, char) == "口径"


def test_memory_mod_instructions_empty_cases(db_session) -> None:
    """角色 None / 无绑定 / 无 memory Mod（全非 memory 区）→ 返回空串（归纳链路零影响）"""
    assert chat_service._memory_mod_instructions(db_session, None) == ""

    char = _create_character(db_session)
    assert chat_service._memory_mod_instructions(db_session, char) == ""  # 无绑定

    prompt_mod = _create_mod(db_session, name="提示", target_area="prompt", payload="提示内容")
    _bind(db_session, char.id, prompt_mod)
    assert chat_service._memory_mod_instructions(db_session, char) == ""  # 绑定存在但非 memory 区


def test_memory_mod_instructions_skips_blank_payload(db_session) -> None:
    """payload 空串/纯空白 Mod 跳过；全空白 → 返回空串；空白与非空白混合只留非空白"""
    char = _create_character(db_session)
    blank1 = _create_mod(db_session, name="空", target_area="memory", payload="")
    blank2 = _create_mod(db_session, name="纯空白", target_area="memory", payload=" \n\t ")
    real = _create_mod(db_session, name="有效", target_area="memory", payload="有效口径")
    _bind(db_session, char.id, blank1, sort_order=0)
    _bind(db_session, char.id, blank2, sort_order=1)
    _bind(db_session, char.id, real, sort_order=2)

    assert chat_service._memory_mod_instructions(db_session, char) == "有效口径"

    # 全空白：另建角色只挂空白
    char2 = _create_character(db_session, name="空白角色")
    _bind(db_session, char2.id, blank1)
    assert chat_service._memory_mod_instructions(db_session, char2) == ""


def test_memory_mod_instructions_payload_verbatim_no_json_parse(db_session) -> None:
    """payload 纯文本直拼（不做 JSON 解析/转义）：JSON 形态文本原样透传"""
    char = _create_character(db_session)
    raw = '{"world": "不该被解析成结构"}'
    mod_id = _create_mod(db_session, name="伪装 JSON", target_area="memory", payload=raw)
    _bind(db_session, char.id, mod_id)

    assert chat_service._memory_mod_instructions(db_session, char) == raw


def test_memory_mod_instructions_skips_deleted_mod_binding(db_session) -> None:
    """绑定指向已删除的 Mod（悬挂绑定）→ 跳过不崩溃"""
    from sqlalchemy import delete as sa_delete

    from backend.app.models.mods import Mod as ModModel

    char = _create_character(db_session)
    ok = _create_mod(db_session, name="有效", target_area="memory", payload="有效口径")
    dangling = _create_mod(db_session, name="将删", target_area="memory", payload="悬挂不该出现")
    _bind(db_session, char.id, ok, sort_order=0)
    _bind(db_session, char.id, dangling, sort_order=1)
    db_session.execute(sa_delete(ModModel).where(ModModel.id == dangling))
    db_session.commit()

    assert chat_service._memory_mod_instructions(db_session, char) == "有效口径"


def test_memory_mod_instructions_single_in_query_no_nplus1(db_session) -> None:
    """N 个启用 memory 绑定 → mods 表恰 1 次 SELECT（IN 查询防 N+1，与 _mod_prompt_injection 同型）"""
    from sqlalchemy import event

    char = _create_character(db_session)
    for i in range(3):
        mod_id = _create_mod(db_session, name=f"M{i}", target_area="memory", payload=f"口{i}")
        _bind(db_session, char.id, mod_id, sort_order=i)
    db_session.expire_all()  # 强制后续访问走 DB（排除 identity map 缓存假象）

    statements: list[str] = []

    def _record(conn, cursor, statement, parameters, context, executemany) -> None:
        statements.append(statement)

    engine = db_session.get_bind()
    event.listen(engine, "before_cursor_execute", _record)
    try:
        chat_service._memory_mod_instructions(db_session, char)
    finally:
        event.remove(engine, "before_cursor_execute", _record)

    mod_selects = [
        s for s in statements
        if "from mods" in s.lower() and not s.lower().startswith(("insert", "update", "delete"))
    ]
    assert len(mod_selects) == 1

