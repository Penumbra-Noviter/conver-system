"""
PD-5 专家模式 — 契约锁测试

锁的内容（spec §4 PD-5 六条验收标准）：
    1. simple 模式 → build_messages 输出与改动前逐字节一致（零回归）
    2. expert + expert_prompt 非空 → system 段仅一条，content = expert_prompt（模板变量替换后）；
       无独立 scenario / post_history system
    3. expert + expert_prompt 空 → 回退 simple 结构化组装
    4. expert 模式下 mes_example 仍注入；before_char/after_char/world 世界书注入仍按序
    5. expert 模式下 history/user 仍按序；重生成路径 append_current_input=False 尾随 system 剥离不破坏
    6. 迁移幂等：连续两次补列不重复、不报错

另覆盖：build_message_list 的 CharacterData 构造显式补 prompt_mode/expert_prompt；
character_card 的 extensions.conver_system 往返保真。
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine, text

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Role
from backend.app.services.character_card import from_v2_card, to_v2_card
from backend.app.services.llm.prompt import CharacterData, build_messages
from backend.app.services.message import build_message_list

__all__: list[str] = []


# ── 纯数据构造 ──


def _msg(role: Role, content: str) -> SimpleNamespace:
    """构造历史消息条目（含 role 与 content 属性）"""
    return SimpleNamespace(role=role, content=content)


def _char(**overrides: object) -> CharacterData:
    """构造角色纯数据（name 固定为艾莉，其余字段可覆盖）"""
    base: dict[str, object] = {"name": "艾莉"}
    base.update(overrides)
    return CharacterData(**base)  # type: ignore[arg-type]


# ── 落库构造（build_message_list 用） ──


def _persist_character(db_session, **overrides: object) -> Character:
    """落库一个角色，返回持久化实例"""
    base = {
        "name": "测试角色",
        "personality": "冷静、睿智",
        "scenario": "月下竹林",
        "system_prompt": "你是测试角色。",
        "post_history_instructions": "保持人设。",
    }
    base.update(overrides)
    char = Character(**base)
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char


def _persist_conversation(db_session, character_id: int, **overrides: object) -> Conversation:
    """落库一个对话，返回持久化实例"""
    base = {
        "character_id": character_id,
        "title": "测试对话",
        "model_provider": "claude",
        "model_name": "claude-sonnet-5",
    }
    base.update(overrides)
    conv = Conversation(**base)
    db_session.add(conv)
    db_session.commit()
    db_session.refresh(conv)
    return conv


# ════════════════════════════════════════════════════════════════
# 一、simple 模式零回归（锁 1）
# ════════════════════════════════════════════════════════════════


class TestSimpleZeroRegression:
    def test_full_assembly_byte_identical(self) -> None:
        """simple 模式完整组装（system/scenario/mes_example/history/PHI/user）逐字节一致"""
        char = _char(
            system_prompt="系统提示",
            personality="人格设定",
            scenario="场景设定",
            mes_example="<START>\n{{user}}: 例1\n{{char}}: 例2",
            post_history_instructions="历史指令",
        )
        history = [_msg(Role.USER, "历史1"), _msg(Role.ASSISTANT, "历史2")]
        msgs = build_messages(char, history, "当前输入", user_name="小明")

        assert msgs == [
            {"role": "system", "content": "系统提示"},
            {"role": "system", "content": "[场景设定]\n场景设定"},
            {"role": "user", "content": "例1"},
            {"role": "assistant", "content": "例2"},
            {"role": "user", "content": "历史1"},
            {"role": "assistant", "content": "历史2"},
            {"role": "system", "content": "历史指令"},
            {"role": "user", "content": "当前输入"},
        ]

    def test_minimal_default_fields(self) -> None:
        """simple 模式最小默认字段：仅空 system + user（逐字节一致）"""
        msgs = build_messages(_char(), [], "你好")
        assert msgs == [
            {"role": "system", "content": ""},
            {"role": "user", "content": "你好"},
        ]


# ════════════════════════════════════════════════════════════════
# 二、expert 模式分流（锁 2 / 锁 3）
# ════════════════════════════════════════════════════════════════


class TestExpertMode:
    def test_expert_single_system_replaces_static(self) -> None:
        """expert + 非空 → system 段仅一条 expert_prompt，无 scenario/PHI 独立 system"""
        char = _char(
            prompt_mode="expert",
            expert_prompt="你是{{char}}，月下剑客。",
            system_prompt="系统提示",  # 应被忽略
            personality="人格设定",  # 应被忽略
            scenario="场景设定",  # 应被忽略（无 [场景设定]）
            post_history_instructions="历史指令",  # 应被忽略（无 PHI）
            mes_example="<START>\n{{user}}: 例1\n{{char}}: 例2",
        )
        history = [_msg(Role.USER, "历史1"), _msg(Role.ASSISTANT, "历史2")]
        msgs = build_messages(char, history, "当前输入", user_name="小明")

        assert msgs == [
            {"role": "system", "content": "你是艾莉，月下剑客。"},
            {"role": "user", "content": "例1"},
            {"role": "assistant", "content": "例2"},
            {"role": "user", "content": "历史1"},
            {"role": "assistant", "content": "历史2"},
            {"role": "user", "content": "当前输入"},
        ]
        systems = [m for m in msgs if m["role"] == "system"]
        assert len(systems) == 1  # 仅一条 system

    def test_expert_template_vars_applied(self) -> None:
        """expert_prompt 内 {{char}}/{{user}} 经 apply_template_vars 替换"""
        char = _char(prompt_mode="expert", expert_prompt="{{user}} 与 {{char}} 同行")
        msgs = build_messages(char, [], "你好", user_name="小明")
        assert msgs[0] == {"role": "system", "content": "小明 与 艾莉 同行"}

    def test_expert_empty_prompt_falls_back_simple(self) -> None:
        """expert + 空串 → 回退 simple 结构化组装（与 simple 一致）"""
        fields = {
            "prompt_mode": "expert",
            "expert_prompt": "",
            "system_prompt": "系统提示",
            "scenario": "场景设定",
            "post_history_instructions": "历史指令",
        }
        expert_msgs = build_messages(_char(**fields), [], "当前输入")
        simple_msgs = build_messages(_char(
            system_prompt="系统提示", scenario="场景设定", post_history_instructions="历史指令",
        ), [], "当前输入")
        assert expert_msgs == simple_msgs

    def test_expert_whitespace_prompt_falls_back_simple(self) -> None:
        """expert + 纯空白 → 回退 simple（strip 后为空即视为空）"""
        char = _char(prompt_mode="expert", expert_prompt="   \n  ")
        msgs = build_messages(char, [], "你好")
        # 回退 simple：默认空 system + user（与 simple 最小态一致）
        assert msgs == [
            {"role": "system", "content": ""},
            {"role": "user", "content": "你好"},
        ]


# ════════════════════════════════════════════════════════════════
# 三、expert + 世界书 + mes_example（锁 4）
# ════════════════════════════════════════════════════════════════


class TestExpertWorldInjection:
    def test_world_and_mes_example_preserved_order(self) -> None:
        """expert 只替代角色静态字段；before/after/world 世界书 + mes_example 仍按序注入"""
        char = _char(
            prompt_mode="expert",
            expert_prompt="专家指令",
            mes_example="<START>\n{{user}}: 例1\n{{char}}: 例2",
        )
        world = {
            "before_char": ["世界前"],
            "after_char": ["世界后"],
            "system": ["世界知识1", "世界知识2"],
        }
        history = [_msg(Role.USER, "历史1"), _msg(Role.ASSISTANT, "历史2")]
        msgs = build_messages(char, history, "当前输入", world=world)

        assert msgs == [
            {"role": "system", "content": "世界前"},
            {"role": "system", "content": "专家指令"},
            {"role": "system", "content": "世界后"},
            {"role": "system", "content": "[世界知识]\n世界知识1\n\n世界知识2"},
            {"role": "user", "content": "例1"},
            {"role": "assistant", "content": "例2"},
            {"role": "user", "content": "历史1"},
            {"role": "assistant", "content": "历史2"},
            {"role": "user", "content": "当前输入"},
        ]


# ════════════════════════════════════════════════════════════════
# 四、expert + history/user + 重生成（锁 5）
# ════════════════════════════════════════════════════════════════


class TestExpertHistoryUser:
    def test_history_user_order(self) -> None:
        """expert 下 history/user 仍按序注入"""
        char = _char(prompt_mode="expert", expert_prompt="专家指令")
        history = [_msg(Role.USER, "问1"), _msg(Role.ASSISTANT, "答1")]
        msgs = build_messages(char, history, "问2")
        assert msgs == [
            {"role": "system", "content": "专家指令"},
            {"role": "user", "content": "问1"},
            {"role": "assistant", "content": "答1"},
            {"role": "user", "content": "问2"},
        ]

    def test_regenerate_no_trailing_system(self) -> None:
        """append_current_input=False：末条为历史末条 user，无尾随 system"""
        char = _char(prompt_mode="expert", expert_prompt="专家指令")
        history = [
            _msg(Role.USER, "问1"),
            _msg(Role.ASSISTANT, "答1"),
            _msg(Role.USER, "问2"),
        ]
        msgs = build_messages(char, history, "忽略", append_current_input=False)
        assert msgs[-1] == {"role": "user", "content": "问2"}
        assert msgs[-1]["role"] != "system"

    def test_regenerate_empty_history_strips_expert_system(self) -> None:
        """append_current_input=False + 空历史：尾随 system 全剥离，输出无 user"""
        char = _char(prompt_mode="expert", expert_prompt="专家指令")
        msgs = build_messages(char, [], "忽略", append_current_input=False)
        assert [m for m in msgs if m["role"] == "user"] == []


# ════════════════════════════════════════════════════════════════
# 五、prompt_mode 非 expert 值（Falsify）
# ════════════════════════════════════════════════════════════════


class TestNonExpertModes:
    @pytest.mark.parametrize("mode", ["simple", "weird", None])
    def test_non_expert_uses_simple(self, mode: object) -> None:
        """非 'expert' 值（simple/weird/None）一律走 simple 结构化组装"""
        char = _char(prompt_mode=mode, expert_prompt="这段不应被注入")
        msgs = build_messages(char, [], "你好")
        assert msgs == [
            {"role": "system", "content": ""},
            {"role": "user", "content": "你好"},
        ]


# ════════════════════════════════════════════════════════════════
# 六、build_message_list 的 CharacterData 构造（message.py）
# ════════════════════════════════════════════════════════════════


class TestBuildMessageListExpert:
    def test_expert_fields_carried_into_build_messages(self, db_session) -> None:
        """CharacterData 显式补 prompt_mode/expert_prompt，expert 分流生效"""
        char = _persist_character(db_session, prompt_mode="expert", expert_prompt="你是{{char}}专家")
        conv = _persist_conversation(db_session, char.id)
        msgs = build_message_list(db_session, conv, "你好", user_name="小明")
        assert msgs[0] == {"role": "system", "content": "你是测试角色专家"}
        assert [m["role"] for m in msgs] == ["system", "user"]

    def test_simple_defaults_via_build_message_list(self, db_session) -> None:
        """未设 prompt_mode/expert_prompt 的角色经落库回读默认 simple，结构化组装生效"""
        char = _persist_character(db_session)
        conv = _persist_conversation(db_session, char.id)
        msgs = build_message_list(db_session, conv, "你好")
        assert msgs == [
            {"role": "system", "content": "你是测试角色。"},
            {"role": "system", "content": "[场景设定]\n月下竹林"},
            {"role": "system", "content": "保持人设。"},
            {"role": "user", "content": "你好"},
        ]

    def test_missing_character_raises(self, db_session) -> None:
        """角色不存在 → ValueError"""
        conv = _persist_conversation(db_session, 99999)
        with pytest.raises(ValueError, match="角色不存在"):
            build_message_list(db_session, conv, "你好")


# ════════════════════════════════════════════════════════════════
# 七、character_card extensions.conver_system 往返保真
# ════════════════════════════════════════════════════════════════


class TestExpertCardRoundtrip:
    def test_expert_roundtrip_preserved(self, make_character) -> None:
        """expert 态经 to_v2_card → from_v2_card 往返保真"""
        char = make_character(prompt_mode="expert", expert_prompt="你是{{char}}，专家整段提示")
        card = to_v2_card(char)
        ns = card["data"]["extensions"]["conver_system"]
        assert ns["prompt_mode"] == "expert"
        assert ns["expert_prompt"] == "你是{{char}}，专家整段提示"

        restored = from_v2_card(card)
        assert restored.prompt_mode == "expert"
        assert restored.expert_prompt == "你是{{char}}，专家整段提示"

    def test_simple_roundtrip_defaults(self, make_character) -> None:
        """simple 默认态：命名空间不写两字段，导入回读默认值"""
        char = make_character()  # prompt_mode/expert_prompt 未显式设置
        ns = to_v2_card(char)["data"]["extensions"]["conver_system"]
        assert "prompt_mode" not in ns
        assert "expert_prompt" not in ns

        restored = from_v2_card(to_v2_card(char))
        assert restored.prompt_mode == "simple"
        assert restored.expert_prompt == ""

    def test_expert_mode_empty_prompt_roundtrip_mode(self, make_character) -> None:
        """expert + 空 expert_prompt：mode 保真，空 prompt 不落卡"""
        char = make_character(prompt_mode="expert", expert_prompt="")
        ns = to_v2_card(char)["data"]["extensions"]["conver_system"]
        assert ns["prompt_mode"] == "expert"
        assert "expert_prompt" not in ns

        restored = from_v2_card(to_v2_card(char))
        assert restored.prompt_mode == "expert"
        assert restored.expert_prompt == ""


# ════════════════════════════════════════════════════════════════
# 八、自愈迁移幂等（锁 6）
# ════════════════════════════════════════════════════════════════


class TestExpertMigration:
    def test_migration_idempotent(self) -> None:
        """缺两列补列，连续两次调用无副作用（不重复、不报错）"""
        from backend.app.database import _ensure_character_expert_columns

        engine = create_engine("sqlite://")
        # 旧 schema 的 characters 表（缺专家模式两列）
        with engine.connect() as conn:
            conn.execute(text(
                "CREATE TABLE characters ("
                "id INTEGER NOT NULL PRIMARY KEY, "
                "name VARCHAR(100) NOT NULL)"
            ))
            conn.commit()

        _ensure_character_expert_columns(engine)  # 首次补列
        _ensure_character_expert_columns(engine)  # 幂等：再跑无事

        with engine.connect() as conn:
            cols = {row[1] for row in conn.execute(text("PRAGMA table_info(characters)"))}
        for col in ("prompt_mode", "expert_prompt"):
            assert col in cols, f"缺专家模式列 {col}"
