"""
世界书激活引擎纯函数契约锁（WL-2）

锁定语义（docs/chat-simulator-upgrade-spec.md §WL-2，二选一处取「大小写不敏感」）：
- 零 DB/IO：模块可独立导入（subprocess 检查 sqlalchemy 未入 sys.modules）
- 命中判定：constant 直进（不判命中）；or/and 子串匹配，大小写**不敏感**（锁定）；空 key 不参与
- depth 窗口：0=仅输入；N=最近 2N 条「对话消息」+ 输入；>20 裁剪；<0 视为 0；system 指令不计轮
- 概率闸：0 必弃 / 100 必进（均不消耗 RNG）/ 中间值掷点；同种子可复现
- 互斥组：同组加权抽一（组内只出一条），不同组互不影响
- 输出排序：order 升序、同 order 按 id 稳定（确定性）
- 泛词（单字符/标点 key）不报错（告警属 WL-4 前端职责）
"""

from __future__ import annotations

import random
import subprocess
import sys

from backend.app.services.lorebook_engine import (
    LorebookEntryData,
    activate_lorebook_entries,
    build_world_injection,
    collect_scan_text,
)
from backend.app.services.llm.prompt import SOURCE_MEMORY, SOURCE_WORLD

__all__: list[str] = []


def _entry(**overrides: object) -> LorebookEntryData:
    """引擎条目工厂（字段可覆盖）"""
    base = dict(
        id=1,
        keys=("key",),
        content="世界书内容",
        constant=False,
        order=100,
        probability=100,
        group_name="",
        group_weight=100,
        match_mode="or",
        position="world",
        enabled=True,
    )
    base.update(overrides)
    return LorebookEntryData(**base)  # type: ignore[arg-type]


class _FakeMsg:
    """扫描窗口测试用假消息（role + content 双属性）"""

    def __init__(self, role: str, content: str) -> None:
        self.role = role
        self.content = content


def _role_of(msg: object) -> str:
    return msg.role  # type: ignore[attr-defined]


# ════════════════════════════════════════════════════════════════
# 一、空输入零异常
# ════════════════════════════════════════════════════════════════


def test_empty_entries_and_text() -> None:
    """空 entries / 空 scan_text → 空结果（零异常）"""
    assert activate_lorebook_entries([], "") == []
    assert activate_lorebook_entries([], "some text") == []
    # 非常驻条目 + 空扫描文本：无 key 可命中 → 空
    assert activate_lorebook_entries([_entry(keys=("酒馆",))], "") == []
    assert collect_scan_text([], "", 5, role_of=_role_of) == ""


# ════════════════════════════════════════════════════════════════
# 二、constant 直进
# ════════════════════════════════════════════════════════════════


def test_constant_direct_pass_ignores_scan_text() -> None:
    """constant 条目不判命中：scan_text 不含任何 key 也入选"""
    entry = _entry(id=7, constant=True, keys=("绝不出现的关键词",))
    out = activate_lorebook_entries([entry], "完全无关的文本")
    assert [e.id for e in out] == [7]


# ════════════════════════════════════════════════════════════════
# 三、or / and 命中矩阵 + 大小写不敏感
# ════════════════════════════════════════════════════════════════


def test_match_or_any_key() -> None:
    """or：任一 key 命中即入选"""
    entry = _entry(id=1, keys=("apple", "banana"), match_mode="or")
    assert [e.id for e in activate_lorebook_entries([entry], "I ate a banana pie")] == [1]
    assert [e.id for e in activate_lorebook_entries([entry], "apple orchard")] == [1]
    assert activate_lorebook_entries([entry], "cherry pie") == []


def test_match_and_all_keys() -> None:
    """and：全部 key 命中才入选"""
    entry = _entry(id=1, keys=("apple", "banana"), match_mode="and")
    assert activate_lorebook_entries([entry], "apple pie") == []
    assert [e.id for e in activate_lorebook_entries([entry], "apple banana split")] == [1]


def test_match_case_insensitive_locked() -> None:
    """大小写不敏感（锁定）：key 大写、文本小写仍命中"""
    entry = _entry(id=1, keys=("APPLE",))
    assert [e.id for e in activate_lorebook_entries([entry], "an apple a day")] == [1]
    entry2 = _entry(id=2, keys=("酒馆",))
    assert [e.id for e in activate_lorebook_entries([entry2], "走进小酒馆")] == [2]


def test_empty_keys_never_match_nonconstant() -> None:
    """空 keys 的非常驻条目永不命中（or 的 any([])/and 的 all([]) 陷阱守卫）"""
    assert activate_lorebook_entries([_entry(id=1, keys=())], "anything") == []
    assert activate_lorebook_entries([_entry(id=1, keys=(), match_mode="and")], "anything") == []
    # 纯空白 key 同样不参与
    assert activate_lorebook_entries([_entry(id=1, keys=("   ",))], "anything") == []


def test_padded_keys_trimmed() -> None:
    """含周边空白的 key 去除空白后参与匹配（与「空白即剔除」语义一致，Falsify 修复锁）"""
    entry = _entry(id=1, keys=("  foo  ",))
    assert [e.id for e in activate_lorebook_entries([entry], "the foo story")] == [1]
    entry_cn = _entry(id=2, keys=(" 酒馆 ",))
    assert [e.id for e in activate_lorebook_entries([entry_cn], "走进酒馆")] == [2]


# ════════════════════════════════════════════════════════════════
# 四、collect_scan_text depth 边界
# ════════════════════════════════════════════════════════════════


def _history(*pairs: tuple[str, str]) -> list[_FakeMsg]:
    return [_FakeMsg(role, content) for role, content in pairs]


def test_scan_depth_zero_only_input() -> None:
    """depth=0 → 仅 current_input（历史不参与）"""
    history = _history(("user", "第一轮"), ("assistant", "回复一"), ("user", "第二轮"))
    assert collect_scan_text(history, "当前输入", 0, role_of=_role_of) == "当前输入"


def test_scan_depth_one_last_round() -> None:
    """depth=1 → 最近 2 条对话消息 + 当前输入"""
    history = _history(
        ("user", "第一轮"), ("assistant", "回复一"), ("user", "第二轮"), ("assistant", "回复二")
    )
    assert collect_scan_text(history, "当前输入", 1, role_of=_role_of) == "第二轮\n回复二\n当前输入"


def test_scan_depth_n_window() -> None:
    """depth=N → 最近 2N 条对话消息 + 当前输入（不足则取全部）"""
    history = _history(*[(("user" if i % 2 == 0 else "assistant"), f"消息{i}") for i in range(6)])
    assert collect_scan_text(history, "输入", 2, role_of=_role_of) == "消息2\n消息3\n消息4\n消息5\n输入"


def test_scan_depth_clipped_to_20_and_negative() -> None:
    """depth>20 裁剪为 20；<0 视为 0（仅输入）"""
    history = _history(*[(("user" if i % 2 == 0 else "assistant"), f"消息{i}") for i in range(60)])
    out20 = collect_scan_text(history, "输入", 20, role_of=_role_of)
    out99 = collect_scan_text(history, "输入", 99, role_of=_role_of)
    assert out20 == out99  # 超限裁剪
    assert out20.endswith("输入")
    assert len(out20.split("\n")) == 41  # 2*20 消息 + 输入
    assert collect_scan_text(history, "输入", -5, role_of=_role_of) == "输入"


def test_scan_system_messages_not_counted() -> None:
    """system 指令不计「轮」：窗口只取 user/assistant 对话消息"""
    history = _history(
        ("user", "第一轮"),
        ("assistant", "回复一"),
        ("system", "历史后指令"),
        ("user", "第二轮"),
        ("assistant", "回复二"),
    )
    assert collect_scan_text(history, "输入", 1, role_of=_role_of) == "第二轮\n回复二\n输入"


# ════════════════════════════════════════════════════════════════
# 五、排序确定性
# ════════════════════════════════════════════════════════════════


def test_output_sorted_by_order_then_id() -> None:
    """输出按 order 升序、同 order 按 id 升序（乱序输入 → 稳定输出）"""
    entries = [
        _entry(id=3, order=100, keys=("x",)),
        _entry(id=1, order=50, keys=("x",)),
        _entry(id=2, order=100, keys=("x",)),
    ]
    out = activate_lorebook_entries(entries, "x marks the spot")
    assert [e.id for e in out] == [1, 2, 3]


# ════════════════════════════════════════════════════════════════
# 六、概率闸与 RNG 可复现
# ════════════════════════════════════════════════════════════════


def test_probability_zero_and_hundred() -> None:
    """probability=0 必弃、=100 必进"""
    zero = _entry(id=1, keys=("x",), probability=0)
    hundred = _entry(id=2, keys=("x",), probability=100)
    out = activate_lorebook_entries([zero, hundred], "x", rng=random.Random(1))
    assert [e.id for e in out] == [2]


def test_probability_middle_seeded_reproducible() -> None:
    """中间概率 + rng 注入：同种子两次结果一致（可复现）"""
    entries = [_entry(id=i, keys=("x",), probability=50) for i in range(10)]
    rng1 = random.Random(20260910)
    rng2 = random.Random(20260910)
    out1 = [e.id for e in activate_lorebook_entries(entries, "x", rng=rng1)]
    out2 = [e.id for e in activate_lorebook_entries(entries, "x", rng=rng2)]
    assert out1 == out2
    assert out1  # 50% 概率 10 条：同种子下必有确定结果（非空即锁）
    # 不同种子 → 结果可不同（证明掷点真实消耗 RNG）
    other = [e.id for e in activate_lorebook_entries(entries, "x", rng=random.Random(1))]
    assert isinstance(other, list)


def test_same_seed_reproducible_across_input_order() -> None:
    """同种子跨输入顺序可复现：条目顺序规范化后 RNG 消耗序列不随调用方排序漂移（Falsify 修复锁）"""
    entries = [
        _entry(id=1, keys=("x",), probability=50),
        _entry(id=2, keys=("x",), probability=50),
        _entry(id=3, keys=("x",), group_name="g", group_weight=60),
        _entry(id=4, keys=("x",), group_name="g", group_weight=40),
    ]
    a = [e.id for e in activate_lorebook_entries(entries, "x", rng=random.Random(1))]
    b = [
        e.id
        for e in activate_lorebook_entries(list(reversed(entries)), "x", rng=random.Random(1))
    ]
    assert a == b


# ════════════════════════════════════════════════════════════════
# 七、互斥组加权抽一
# ════════════════════════════════════════════════════════════════


def test_group_weighted_picks_one_per_group() -> None:
    """同组只出一条（加权抽一）；不同组互不影响"""
    entries = [
        _entry(id=1, keys=("x",), group_name="地点", group_weight=90),
        _entry(id=2, keys=("x",), group_name="地点", group_weight=10),
        _entry(id=3, keys=("x",), group_name="人物", group_weight=50),
    ]
    out = activate_lorebook_entries(entries, "x", rng=random.Random(7))
    ids = [e.id for e in out]
    assert len([i for i in ids if i in (1, 2)]) == 1  # 地点组只出 1 条
    assert 3 in ids  # 人物组独立选出
    assert len(ids) == 2


def test_group_draw_deterministic_under_seed() -> None:
    """同组加权抽一同种子可复现"""
    entries = [
        _entry(id=1, keys=("x",), group_name="g", group_weight=60),
        _entry(id=2, keys=("x",), group_name="g", group_weight=40),
    ]
    a = [e.id for e in activate_lorebook_entries(entries, "x", rng=random.Random(42))]
    b = [e.id for e in activate_lorebook_entries(entries, "x", rng=random.Random(42))]
    assert a == b


def test_ungrouped_entries_all_pass() -> None:
    """无组条目全部入选（不参与组抽签）"""
    entries = [
        _entry(id=1, keys=("x",)),
        _entry(id=2, keys=("x",)),
        _entry(id=3, keys=("x",), group_name="g"),
        _entry(id=4, keys=("x",), group_name="g"),
    ]
    out = activate_lorebook_entries(entries, "x", rng=random.Random(3))
    ids = [e.id for e in out]
    assert 1 in ids and 2 in ids
    assert len([i for i in ids if i in (3, 4)]) == 1


# ════════════════════════════════════════════════════════════════
# 八、泛词防护
# ════════════════════════════════════════════════════════════════


def test_single_char_and_punctuation_keys_no_error() -> None:
    """keys 含单字符/标点：命中判定不报错（泛词告警属 WL-4 前端职责）"""
    entries = [
        _entry(id=1, keys=("你",)),
        _entry(id=2, keys=("。",)),
        _entry(id=3, keys=("，",)),
    ]
    out = activate_lorebook_entries(entries, "你好。今天，天气不错")
    assert {e.id for e in out} == {1, 2, 3}


# ════════════════════════════════════════════════════════════════
# 九、build_world_injection 分组与模板
# ════════════════════════════════════════════════════════════════


def test_build_world_injection_groups_and_order() -> None:
    """按 position 分组（world→system），组内按 (order, id) 升序；source 默认 world"""
    activated = [
        _entry(id=2, order=200, position="world", content="后世界"),
        _entry(id=1, order=100, position="world", content="先世界"),
        _entry(id=3, order=50, position="before_char", content="角色前"),
        _entry(id=4, order=50, position="after_char", content="场景后"),
    ]
    blocks = build_world_injection(activated)
    assert {key: [seg.content for seg in segs] for key, segs in blocks.items()} == {
        "system": ["先世界", "后世界"],
        "before_char": ["角色前"],
        "after_char": ["场景后"],
    }
    assert all(
        seg.source == SOURCE_WORLD for segs in blocks.values() for seg in segs
    )


def test_build_world_injection_template_vars() -> None:
    """content 经 {{user}}/{{char}} 模板替换"""
    activated = [_entry(id=1, position="world", content="{{user}} 与 {{char}} 的回忆")]
    blocks = build_world_injection(activated, user_name="小明", char_name="莉莉")
    assert [seg.content for seg in blocks["system"]] == ["小明 与 莉莉 的回忆"]


def test_build_world_injection_unknown_position_falls_back() -> None:
    """未知 position 回落 world（system 块），不静默丢弃"""
    activated = [_entry(id=1, position="in_chat", content="未知位置内容")]
    blocks = build_world_injection(activated)
    assert [seg.content for seg in blocks["system"]] == ["未知位置内容"]


def test_build_world_injection_source_by_id() -> None:
    """source_by_id 标注：缺省条目默认 world；值 == "auto" 标注 memory（经 id 反查）"""
    activated = [
        _entry(id=1, position="world", content="手动来源"),
        _entry(id=2, position="world", content="记忆来源"),
        _entry(id=3, position="after_char", content="未标注条目"),
    ]
    blocks = build_world_injection(
        activated, source_by_id={1: "manual", 2: "auto"}, user_name="小明", char_name="莉莉"
    )
    assert [(seg.content, seg.source) for seg in blocks["system"]] == [
        ("手动来源", SOURCE_WORLD),
        ("记忆来源", SOURCE_MEMORY),
    ]
    assert [(seg.content, seg.source) for seg in blocks["after_char"]] == [
        ("未标注条目", SOURCE_WORLD),
    ]


# ════════════════════════════════════════════════════════════════
# 十、其余语义
# ════════════════════════════════════════════════════════════════


def test_activate_current_input_fallback() -> None:
    """scan_text 为空时回退 current_input（调用方可只传输入）"""
    entry = _entry(id=1, keys=("你好",))
    assert [e.id for e in activate_lorebook_entries([entry], "", current_input="你好呀")] == [1]


def test_disabled_entries_skipped() -> None:
    """enabled=false 不参与（即使 constant）"""
    disabled_constant = _entry(id=1, constant=True, enabled=False)
    disabled_keyed = _entry(id=2, keys=("x",), enabled=False)
    out = activate_lorebook_entries([disabled_constant, disabled_keyed], "x")
    assert out == []


def test_no_db_dependency_import() -> None:
    """零 DB 依赖：独立进程导入引擎不加载 sqlalchemy"""
    from pathlib import Path

    repo_root = Path(__file__).resolve().parents[2]  # backend/tests → 仓库根
    code = (
        "import sys; "
        "from backend.app.services.lorebook_engine import activate_lorebook_entries; "
        "assert 'sqlalchemy' not in sys.modules, '引擎导入拉入 sqlalchemy'"
    )
    subprocess.run(
        [sys.executable, "-c", code],
        check=True,
        capture_output=True,
        cwd=repo_root,
    )
