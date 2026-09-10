"""
build_messages 世界书注入契约锁（WL-3，纯函数层）

锁定语义（docs/chat-simulator-upgrade-spec.md §WL-3）：
- world=None / {} / 全空列表 → 输出与改动前逐字节一致（零变化硬约束）
- before_char 块插入 system prompt 之前（逐条 system，组内即注入序）
- after_char 块插入 [场景设定] 之后
- world（position='world'）内容合并为单条 [世界知识] system，多条以空行连接、按给定序（order 升序由 WL-2 build_world_injection 保证）
- append_current_input=False（重生成路径）：末条仍为历史末条 user，尾随 PHI system 剥离不被世界书注入破坏
- 世界书为空时不产生空 system 消息
"""

from __future__ import annotations

from types import SimpleNamespace

from backend.app.services.llm.prompt import CharacterData, build_messages

__all__: list[str] = []


def _character(**overrides: str) -> CharacterData:
    """角色纯数据工厂（字段可覆盖）"""
    base = dict(
        name="测试角色",
        system_prompt="",
        personality="你是测试角色。",
        scenario="月下竹林",
        mes_example="",
        post_history_instructions="",
    )
    base.update(overrides)
    return CharacterData(**base)  # type: ignore[arg-type]


def _msg(role: str, content: str) -> SimpleNamespace:
    """假消息（role + content 双属性）"""
    return SimpleNamespace(role=role, content=content)


def _history(*pairs: tuple[str, str]) -> list[SimpleNamespace]:
    return [_msg(role, content) for role, content in pairs]


# ════════════════════════════════════════════════════════════════
# 一、world=None 逐字节零回归
# ════════════════════════════════════════════════════════════════


def test_world_none_byte_identical_baseline() -> None:
    """world=None：输出与改动前基线逐字节一致（硬约束，由既有用例语义锁定）"""
    history = _history(("user", "第一句"), ("assistant", "回复一"))
    baseline = [
        {"role": "system", "content": "你是测试角色。"},
        {"role": "system", "content": "[场景设定]\n月下竹林"},
        {"role": "user", "content": "第一句"},
        {"role": "assistant", "content": "回复一"},
        {"role": "user", "content": "当前输入"},
    ]
    assert build_messages(_character(), history, "当前输入", world=None) == baseline
    assert build_messages(_character(), history, "当前输入", world={}) == baseline


# ════════════════════════════════════════════════════════════════
# 二、三注入位消息序列
# ════════════════════════════════════════════════════════════════


def test_three_positions_sequence() -> None:
    """before_char / after_char / world 三注入位的消息序列顺序断言"""
    world = {
        "before_char": ["角色前置知识"],
        "system": ["背景一", "背景二"],
        "after_char": ["场景后知识"],
    }
    messages = build_messages(_character(), _history(("user", "第一句"), ("assistant", "回复一")), "输入", world=world)
    roles = [m["role"] for m in messages]
    contents = [m["content"] for m in messages]
    assert roles[0] == "system" and contents[0] == "角色前置知识"      # before_char：system prompt 前
    assert contents[1] == "你是测试角色。"                              # system prompt
    assert contents[2] == "[场景设定]\n月下竹林"                        # 场景设定
    assert contents[3] == "场景后知识"                                  # after_char：场景设定后
    assert contents[4] == "[世界知识]\n背景一\n\n背景二"                # world：合并单条
    assert roles[5:] == ["user", "assistant", "user"]                   # 历史 + 输入


def test_world_knowledge_merged_single_system() -> None:
    """多条 [世界知识] 合并为一条 system，以空行连接、按给定顺序"""
    world = {"system": ["第一条", "第二条", "第三条"]}
    messages = build_messages(_character(), [], "输入", world=world)
    world_msgs = [m for m in messages if "世界知识" in m["content"]]
    assert len(world_msgs) == 1
    assert world_msgs[0] == {"role": "system", "content": "[世界知识]\n第一条\n\n第二条\n\n第三条"}


def test_before_char_multiple_kept_individual() -> None:
    """before_char 多条各成一条 system，顺序即注入序"""
    world = {"before_char": ["前置一", "前置二"]}
    messages = build_messages(_character(), [], "输入", world=world)
    head = [(m["role"], m["content"]) for m in messages[:3]]
    assert head == [
        ("system", "前置一"),
        ("system", "前置二"),
        ("system", "你是测试角色。"),
    ]


# ════════════════════════════════════════════════════════════════
# 三、重生成路径（append_current_input=False）
# ════════════════════════════════════════════════════════════════


def test_regenerate_path_trailing_strip_with_world() -> None:
    """重生成路径：末条仍为历史末条 user，尾随 PHI 剥离不被注入破坏"""
    char = _character(post_history_instructions="保持人设。")
    history = _history(("user", "历史提问"), ("assistant", "历史回答"), ("user", "触发源"))
    world = {"before_char": ["前置"], "system": ["知识"]}
    messages = build_messages(char, history, "", append_current_input=False, world=world)

    assert messages[-1] == {"role": "user", "content": "触发源"}      # 末条 = 历史末条 user
    assert messages[-2] == {"role": "assistant", "content": "历史回答"}  # PHI 已剥离
    assert messages[0] == {"role": "system", "content": "前置"}        # 注入块不受尾随剥离影响
    assert any("[世界知识]" in m["content"] for m in messages)


# ════════════════════════════════════════════════════════════════
# 四、空世界书不产生空 system 消息
# ════════════════════════════════════════════════════════════════


def test_empty_world_no_empty_system_messages() -> None:
    """世界书为空（{} / 全空列表 / 缺位）→ 输出与 world=None 一致，无空 system"""
    baseline = build_messages(_character(), _history(("user", "问"), ("assistant", "答")), "输入")
    for world in (
        {},
        {"before_char": [], "system": [], "after_char": []},
        {"system": []},
        {"before_char": None, "system": None, "after_char": None},
    ):
        assert build_messages(_character(), _history(("user", "问"), ("assistant", "答")), "输入", world=world) == baseline
    assert "世界知识" not in "".join(m["content"] for m in baseline)


def test_empty_content_entries_filtered() -> None:
    """空/纯空白 content 的注入块不产生空 system 消息（Falsify 修复锁）"""
    baseline = build_messages(_character(), [], "输入")
    # 全空内容 → 零注入，与 world=None 一致（无 content:"" 空壳、无 [世界知识] 空头）
    world_all_empty = {"before_char": [""], "system": ["  "], "after_char": [""]}
    assert build_messages(_character(), [], "输入", world=world_all_empty) == baseline
    # 混合：空条目被滤掉，非空条目保留
    mixed = build_messages(_character(), [], "输入", world={"system": ["", "知识"]})
    assert any("[世界知识]" in m["content"] and "知识" in m["content"] for m in mixed)
    assert not any(not m["content"].strip() for m in mixed)  # 无空 system 消息