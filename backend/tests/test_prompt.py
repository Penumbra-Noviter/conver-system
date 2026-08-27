"""
Prompt 组装纯函数单测 — backend/app/services/llm/prompt.py

覆盖：
    1. 模板变量替换（{{user}} / {{char}} / 空文本）
    2. mes_example 解析（<START> 多轮、空串、无前缀行、内容模板变量、空内容行）
    3. system prompt 回退（有 system_prompt vs 只有 personality）
    4. scenario / post_history_instructions 组装顺序与内容
    5. 滑窗截断边界（历史数 ≤ 与 > max_rounds*2）
    6. 当前输入追加（含模板变量）

新模块行覆盖率目标 ≥ 90%。
"""

from __future__ import annotations

from types import SimpleNamespace

from backend.app.models.message import Role
from backend.app.services.llm.prompt import (
    CharacterData,
    apply_template_vars,
    build_messages,
    parse_mes_example,
)

__all__: list[str] = []


def _msg(role: str | Role, content: str) -> SimpleNamespace:
    """构造历史消息条目（含 role 与 content 属性）"""
    return SimpleNamespace(role=role, content=content)


def _char(**overrides: object) -> CharacterData:
    """构造角色纯数据（name 固定为艾莉，其余字段可覆盖）"""
    base = {"name": "艾莉"}
    base.update(overrides)
    return CharacterData(**base)


# ── 1. 模板变量替换 ──


class TestApplyTemplateVars:
    def test_replaces_both_default(self) -> None:
        assert apply_template_vars("{{user}} 对 {{char}} 说") == "User 对 Character 说"

    def test_replaces_custom_names(self) -> None:
        assert apply_template_vars(
            "{{user}} 对 {{char}} 说", user_name="小明", char_name="艾莉"
        ) == "小明 对 艾莉 说"

    def test_empty_text(self) -> None:
        assert apply_template_vars("") == ""

    def test_no_vars_unchanged(self) -> None:
        assert apply_template_vars("你好，世界") == "你好，世界"


# ── 2. mes_example 解析 ──


class TestParseMesExample:
    def test_empty_string(self) -> None:
        assert parse_mes_example("") == []

    def test_blank_string(self) -> None:
        assert parse_mes_example("   \n  ") == []

    def test_single_round(self) -> None:
        assert parse_mes_example("<START>\n{{user}}: 你好\n{{char}}: 欢迎") == [
            {"role": "user", "content": "你好"},
            {"role": "assistant", "content": "欢迎"},
        ]

    def test_multiple_rounds(self) -> None:
        result = parse_mes_example(
            "<START>\n{{user}}: 第一问\n{{char}}: 第一答\n"
            "<START>\n{{user}}: 第二问\n{{char}}: 第二答"
        )
        assert result == [
            {"role": "user", "content": "第一问"},
            {"role": "assistant", "content": "第一答"},
            {"role": "user", "content": "第二问"},
            {"role": "assistant", "content": "第二答"},
        ]

    def test_no_prefix_line_ignored(self) -> None:
        result = parse_mes_example("<START>\n这是一句旁白\n{{user}}: 你好")
        assert result == [{"role": "user", "content": "你好"}]

    def test_content_template_vars(self) -> None:
        result = parse_mes_example(
            "{{user}}: 我是{{user}}\n{{char}}: 我是{{char}}",
            user_name="小明",
            char_name="艾莉",
        )
        assert result == [
            {"role": "user", "content": "我是小明"},
            {"role": "assistant", "content": "我是艾莉"},
        ]

    def test_empty_content_line_skipped(self) -> None:
        result = parse_mes_example("<START>\n{{user}}:\n{{char}}: 欢迎")
        assert result == [{"role": "assistant", "content": "欢迎"}]

    def test_blank_lines_skipped(self) -> None:
        result = parse_mes_example("<START>\n\n{{user}}: 你好\n\n{{char}}: 欢迎\n")
        assert result == [
            {"role": "user", "content": "你好"},
            {"role": "assistant", "content": "欢迎"},
        ]

    def test_colon_without_space(self) -> None:
        result = parse_mes_example("<START>\n{{user}}:你好\n{{char}}:欢迎")
        assert result == [
            {"role": "user", "content": "你好"},
            {"role": "assistant", "content": "欢迎"},
        ]


# ── 3. system prompt 回退 ──


class TestSystemPromptFallback:
    def test_system_prompt_preferred(self) -> None:
        char = _char(system_prompt="覆盖提示", personality="人格设定")
        msgs = build_messages(char, [], "你好")
        assert msgs[0] == {"role": "system", "content": "覆盖提示"}

    def test_personality_fallback_when_no_system_prompt(self) -> None:
        char = _char(system_prompt="", personality="人格设定")
        msgs = build_messages(char, [], "你好")
        assert msgs[0] == {"role": "system", "content": "人格设定"}


# ── 4. scenario / PHI 组装顺序与内容 ──


class TestScenarioAndPhi:
    def test_scenario_and_phi_positions(self) -> None:
        char = _char(scenario="竹林", post_history_instructions="保持人设")
        msgs = build_messages(char, [], "你好")
        assert msgs[1] == {"role": "system", "content": "[场景设定]\n竹林"}
        assert msgs[-2] == {"role": "system", "content": "保持人设"}
        assert msgs[-1] == {"role": "user", "content": "你好"}

    def test_scenario_and_phi_template_vars(self) -> None:
        char = _char(
            scenario="{{char}}场景",
            post_history_instructions="{{char}}指令",
        )
        msgs = build_messages(char, [], "{{user}}你好", user_name="小明")
        assert msgs[1]["content"] == "[场景设定]\n艾莉场景"
        assert msgs[-2]["content"] == "艾莉指令"
        assert msgs[-1]["content"] == "小明你好"

    def test_absent_scenario_and_phi(self) -> None:
        char = _char()
        msgs = build_messages(char, [], "你好")
        assert [m["role"] for m in msgs] == ["system", "user"]


# ── 5. 完整组装顺序 ──


class TestFullAssembly:
    def test_full_order_with_mes_example_and_history(self) -> None:
        char = _char(
            system_prompt="系统提示",
            scenario="场景设定",
            mes_example="<START>\n{{user}}: 例1\n{{char}}: 例2",
            post_history_instructions="历史指令",
        )
        history = [
            _msg(Role.USER, "历史1"),
            _msg(Role.ASSISTANT, "历史2"),
        ]
        msgs = build_messages(char, history, "当前输入", user_name="小明")

        assert [m["role"] for m in msgs] == [
            "system",   # system prompt
            "system",   # scenario
            "user",     # mes_example 例1
            "assistant",  # mes_example 例2
            "user",     # 历史1
            "assistant",  # 历史2
            "system",   # PHI
            "user",     # 当前输入
        ]
        assert msgs[0] == {"role": "system", "content": "系统提示"}
        assert msgs[1] == {"role": "system", "content": "[场景设定]\n场景设定"}
        assert msgs[2] == {"role": "user", "content": "例1"}
        assert msgs[3] == {"role": "assistant", "content": "例2"}
        assert msgs[4] == {"role": "user", "content": "历史1"}
        assert msgs[5] == {"role": "assistant", "content": "历史2"}
        assert msgs[6] == {"role": "system", "content": "历史指令"}
        assert msgs[7] == {"role": "user", "content": "当前输入"}


# ── 6. 滑窗截断边界 ──


class TestSlidingWindow:
    def _history(self, n: int) -> list[SimpleNamespace]:
        return [
            _msg(Role.USER if i % 2 == 0 else Role.ASSISTANT, f"m{i}")
            for i in range(n)
        ]

    def test_at_boundary_no_trim(self) -> None:
        char = _char()
        history = self._history(4)  # max_rounds=2 → 窗口 4，恰好相等
        msgs = build_messages(char, history, "当前", max_rounds=2)
        contents = [m["content"] for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert contents == ["m0", "m1", "m2", "m3"]

    def test_exceeds_window_trims_to_last(self) -> None:
        char = _char()
        history = self._history(10)
        msgs = build_messages(char, history, "当前", max_rounds=2)
        contents = [m["content"] for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert contents == ["m6", "m7", "m8", "m9"]

    def test_less_than_window_keeps_all(self) -> None:
        char = _char()
        history = self._history(2)
        msgs = build_messages(char, history, "当前", max_rounds=30)
        contents = [m["content"] for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert contents == ["m0", "m1"]

    def test_string_role_history(self) -> None:
        """历史 role 为纯字符串（非枚举）时也能正确归一化"""
        char = _char()
        history = [_msg("user", "s1"), _msg("assistant", "s2")]
        msgs = build_messages(char, history, "当前", max_rounds=1)
        history_msgs = [m for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert history_msgs == [
            {"role": "user", "content": "s1"},
            {"role": "assistant", "content": "s2"},
        ]


# ── 7. 当前输入追加 / 其他边界 ──


class TestMisc:
    def test_current_input_appended(self) -> None:
        char = _char()
        msgs = build_messages(char, [], "{{user}}说")
        assert msgs[-1] == {"role": "user", "content": "User说"}

    def test_empty_char_name_falls_back(self) -> None:
        char = CharacterData(name="", system_prompt="{{char}}提示")
        msgs = build_messages(char, [], "你好")
        assert msgs[0] == {"role": "system", "content": "Character提示"}

    def test_no_history_and_no_extras(self) -> None:
        char = _char()
        msgs = build_messages(char, [], "你好")
        assert msgs == [
            {"role": "system", "content": ""},
            {"role": "user", "content": "你好"},
        ]


# ── 8. append_current_input 显式路径 ──


class TestAppendCurrentInput:
    """重生成消息组装：append_current_input 显式契约

    - True（默认）：逐字保持现组装行为（追加当前 user 输入）。
    - False：不追加当前 user 输入；输出末条为历史末条 user（待回复触发源）；
      不得残留尾随 system（PHI 已剥离）。
    """

    def test_true_default_appends_current_input(self) -> None:
        """默认 True：追加当前 user 输入，末条为当前输入"""
        char = _char()
        history = [
            _msg(Role.USER, "历史1"),
            _msg(Role.ASSISTANT, "历史2"),
        ]
        msgs = build_messages(char, history, "当前输入")
        assert msgs[-1] == {"role": "user", "content": "当前输入"}

    def test_true_explicit_keeps_phi_and_current_input(self) -> None:
        """True 显式传参：PHI（system）保留在末条 user 之前"""
        char = _char(post_history_instructions="保持人设")
        history = [_msg(Role.USER, "历史1"), _msg(Role.ASSISTANT, "历史2")]
        msgs = build_messages(char, history, "当前输入", append_current_input=True)
        assert msgs[-2] == {"role": "system", "content": "保持人设"}
        assert msgs[-1] == {"role": "user", "content": "当前输入"}

    def test_false_no_current_user_appended(self) -> None:
        """False：不追加当前 user 输入（末尾不出现当前输入内容）"""
        char = _char()
        history = [_msg(Role.USER, "历史1"), _msg(Role.ASSISTANT, "历史2")]
        msgs = build_messages(char, history, "被忽略的当前输入", append_current_input=False)
        contents = [m["content"] for m in msgs]
        assert "被忽略的当前输入" not in contents

    def test_false_last_is_last_history_user(self) -> None:
        """False：输出末条为历史末条 user（待回复触发源，截断后末条恒为 user）"""
        char = _char()
        history = [
            _msg(Role.USER, "第一轮问"),
            _msg(Role.ASSISTANT, "第一轮答"),
            _msg(Role.USER, "第二轮问"),
        ]
        msgs = build_messages(char, history, "忽略", append_current_input=False)
        assert msgs[-1] == {"role": "user", "content": "第二轮问"}

    def test_false_no_trailing_system(self) -> None:
        """False + PHI：末条为触发 user，不残留尾随 PHI system（PHI 已剥离）"""
        char = _char(post_history_instructions="保持人设")
        history = [
            _msg(Role.USER, "第一轮问"),
            _msg(Role.ASSISTANT, "第一轮答"),
            _msg(Role.USER, "第二轮问"),
        ]
        msgs = build_messages(char, history, "忽略", append_current_input=False)
        assert msgs[-1] == {"role": "user", "content": "第二轮问"}
        # 尾随 system（PHI）已被剥离，不再出现在末尾
        assert msgs[-1].get("role") != "system"
        # 触发 user 在列表中只出现一次（不重复）
        trigger_occurrences = [
            m for m in msgs if m["role"] == "user" and m["content"] == "第二轮问"
        ]
        assert len(trigger_occurrences) == 1

    def test_false_empty_history_no_user(self) -> None:
        """False + 空历史：不抛错，输出无 user 消息"""
        char = _char()
        msgs = build_messages(char, [], "忽略", append_current_input=False)
        assert [m for m in msgs if m["role"] == "user"] == []

    def test_false_user_content_ignored_not_validated(self) -> None:
        """False：user_content 值被忽略、不校验、不追加（签名兼容）"""
        char = _char()
        history = [
            _msg(Role.USER, "第一轮问"),
            _msg(Role.ASSISTANT, "第一轮答"),
            _msg(Role.USER, "第二轮问"),
        ]
        # 空串与任意非空值，False 下均不追加
        for ignored in ("", "任意内容"):
            msgs = build_messages(char, history, ignored, append_current_input=False)
            assert msgs[-1] == {"role": "user", "content": "第二轮问"}

    def test_false_without_phi_no_trailing_system(self) -> None:
        """False + 无 PHI：无残留 system 尾随（末条即历史末条 user）"""
        char = _char()
        history = [
            _msg(Role.USER, "问1"),
            _msg(Role.ASSISTANT, "答1"),
            _msg(Role.USER, "问2"),
        ]
        msgs = build_messages(char, history, "忽略", append_current_input=False)
        assert msgs[-1] == {"role": "user", "content": "问2"}

    def test_false_with_window_truncation_and_phi(self) -> None:
        """False + 滑窗截断边界 + PHI：滑窗后末条仍为触发 user，无尾随 system"""
        char = _char(post_history_instructions="保持人设")
        history = [
            _msg(Role.USER if i % 2 == 0 else Role.ASSISTANT, f"m{i}")
            for i in range(10)  # 10 条 + 触发问 = 11 条，max_rounds=2 → 窗口 4
        ]
        history.append(_msg(Role.USER, "触发问"))  # 末条触发 user（重生成截断后形态）
        msgs = build_messages(char, history, "忽略", max_rounds=2, append_current_input=False)
        # 滑窗保留 [m7, m8, m9, 触发问]，PHI 伪尾随被剥离 → 末条 = 触发问
        assert msgs[-1] == {"role": "user", "content": "触发问"}
        assert msgs[-1].get("role") != "system"
