"""
NPD-06 预设对话 few-shot 注入 — 契约锁测试

覆盖三层（纯函数 prompt → message → chat）：
    1. build_messages / build_messages_with_source 的 preset_dialogue 参数透传与注入
    2. 注入序契约：preset few-shot 在角色 mes_example 之后、历史消息之前
    3. 空串/纯空白零注入（逐字节一致契约锁）
    4. few-shot 段 source 复用 SOURCE_CHARACTER（不新增 source 常量）
    5. 预设对话与叙述风格同时开启时注入序正确（叙述风格在前、preset 在后）
    6. message.build_message_list 显式接收 preset_dialogue 快照并透传（F-148 形参显式化，
       不再隐式读 ORM；快照读取责任由 chat 层调用方承担）
    7. chat.assemble_chat_context 普通/重生成两条路径 + build_prompt_debug 显式传快照
    8. CharacterData.from_orm 唯一角色投影入口（PROMPT_FIELDS + prompt_mode/expert_prompt
       + None 空角色，F-147）

依赖：pytest + SQLite 内存库（conftest.db_session）+ monkeypatch。
"""

from __future__ import annotations

from types import SimpleNamespace

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Role
from backend.app.services import chat as chat_service
from backend.app.services import message as message_service
from backend.app.services.llm.prompt import (
    SOURCE_CHARACTER,
    CharacterData,
    build_messages,
    build_messages_with_source,
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


# ── 1. prompt 纯函数：preset_dialogue 注入与注入序 ──


class TestPresetDialoguePrompt:
    """build_messages / build_messages_with_source 的 preset_dialogue 契约锁"""

    def test_injects_after_mes_example_before_history(self) -> None:
        """preset few-shot 位于角色 mes_example 之后、历史消息之前（注入序断言）"""
        char = _char(
            system_prompt="系统提示",
            mes_example="<START>\n{{user}}: 角色例问\n{{char}}: 角色例答",
        )
        history = [
            _msg(Role.USER, "历史问"),
            _msg(Role.ASSISTANT, "历史答"),
        ]
        preset = "<START>\n{{user}}: 预设问\n{{char}}: 预设答"

        msgs = build_messages(char, history, "当前", preset_dialogue=preset)

        contents = [m["content"] for m in msgs]
        assert msgs == [
            {"role": "system", "content": "系统提示"},
            {"role": "user", "content": "角色例问"},
            {"role": "assistant", "content": "角色例答"},
            {"role": "user", "content": "预设问"},
            {"role": "assistant", "content": "预设答"},
            {"role": "user", "content": "历史问"},
            {"role": "assistant", "content": "历史答"},
            {"role": "user", "content": "当前"},
        ]
        assert contents.index("预设问") > contents.index("角色例答")
        assert contents.index("预设答") < contents.index("历史问")

    def test_empty_preset_zero_injection_byte_identical(self) -> None:
        """空串 preset_dialogue 零注入，输出与不传逐字节一致（契约锁）"""
        char = _char(
            mes_example="<START>\n{{user}}: 例问\n{{char}}: 例答",
        )
        history = [_msg(Role.USER, "历史问"), _msg(Role.ASSISTANT, "历史答")]
        with_preset = build_messages(char, history, "当前", preset_dialogue="")
        without_preset = build_messages(char, history, "当前")
        assert with_preset == without_preset

    def test_none_preset_zero_injection(self) -> None:
        """None 直传 preset_dialogue 零注入（falsy 短路契约锁 F-153，生产经 or "" 归一）"""
        char = _char()
        msgs = build_messages(char, [], "当前", preset_dialogue=None)
        assert msgs == [
            {"role": "system", "content": ""},
            {"role": "user", "content": "当前"},
        ]

    def test_blank_preset_zero_injection(self) -> None:
        """纯空白 preset_dialogue 零注入（不产生空消息）"""
        char = _char()
        msgs = build_messages(char, [], "当前", preset_dialogue="   \n\t ")
        assert msgs == [
            {"role": "system", "content": ""},
            {"role": "user", "content": "当前"},
        ]

    def test_with_source_preset_uses_character_source(self) -> None:
        """build_messages_with_source 的 preset few-shot source == SOURCE_CHARACTER"""
        char = _char()
        preset = "<START>\n{{user}}: 预设问\n{{char}}: 预设答"
        segments = build_messages_with_source(char, [], "当前", preset_dialogue=preset)
        preset_segments = [
            s for s in segments if s["role"] in ("user", "assistant")
            and s["content"] in ("预设问", "预设答")
        ]
        assert len(preset_segments) == 2
        assert all(s["source"] == SOURCE_CHARACTER for s in preset_segments)

    def test_preset_and_narrative_order(self) -> None:
        """两者同时开启：叙述风格 system 在前（mes_example 之前）、preset few-shot 在后"""
        char = _char(
            system_prompt="系统提示",
            mes_example="<START>\n{{user}}: 例问\n{{char}}: 例答",
        )
        history = [_msg(Role.USER, "历史问"), _msg(Role.ASSISTANT, "历史答")]
        msgs = build_messages(
            char, history, "当前",
            narrative_style="第三人称",
            preset_dialogue="<START>\n{{user}}: 预设问\n{{char}}: 预设答",
        )
        assert msgs == [
            {"role": "system", "content": "系统提示"},
            {"role": "system", "content": "[叙述风格]\n第三人称"},
            {"role": "user", "content": "例问"},
            {"role": "assistant", "content": "例答"},
            {"role": "user", "content": "预设问"},
            {"role": "assistant", "content": "预设答"},
            {"role": "user", "content": "历史问"},
            {"role": "assistant", "content": "历史答"},
            {"role": "user", "content": "当前"},
        ]


# ── 2. message 层：build_message_list 读快照 ──


def _make_character(db, **overrides: object) -> Character:
    """落库一个无 greeting 的角色，返回 ORM 实例"""
    base = {"name": "测试角色", "personality": "冷静、睿智", "first_mes": ""}
    base.update(overrides)
    char = Character(**base)
    db.add(char)
    db.commit()
    db.refresh(char)
    return char


def _make_conversation(db, char_id: int, preset_dialogue: str | None = None) -> Conversation:
    """落库一个绑定角色的对话（直接控 preset_dialogue 快照列），返回 ORM 实例"""
    conv = Conversation(character_id=char_id, preset_dialogue=preset_dialogue)
    db.add(conv)
    db.commit()
    db.refresh(conv)
    return conv


class TestBuildMessageListPreset:
    """message.build_message_list 显式接收 preset_dialogue 快照并透传（F-148 形参显式化）"""

    def test_passes_snapshot_explicitly(self, db_session) -> None:
        """调用方显式传快照（非空）→ 产出 few-shot"""
        char = _make_character(db_session)
        preset = "<START>\n{{user}}: 预设问\n{{char}}: 预设答"
        conv = _make_conversation(db_session, char.id, preset_dialogue=preset)

        msgs = message_service.build_message_list(
            db_session, conv, "当前", preset_dialogue=conv.preset_dialogue or "",
        )

        contents = [m["content"] for m in msgs]
        assert "预设问" in contents
        assert "预设答" in contents

    def test_none_snapshot_zero_injection(self, db_session) -> None:
        """快照列为 None → 调用方归一为空串 → 零注入（输出不含 preset 内容）"""
        char = _make_character(db_session)
        conv = _make_conversation(db_session, char.id, preset_dialogue=None)
        msgs = message_service.build_message_list(
            db_session, conv, "当前", preset_dialogue=conv.preset_dialogue or "",
        )
        contents = [m["content"] for m in msgs]
        assert "预设问" not in contents


# ── 3. chat 层：assemble_chat_context 两条路径 + build_prompt_debug ──


def _patch_resolve_llm(monkeypatch) -> None:
    """让 chat_service.resolve_llm 返回 dummy provider（跳过真实凭据解析）"""
    monkeypatch.setattr(
        chat_service,
        "resolve_llm",
        lambda db, provider, model: (None, None, SimpleNamespace()),
    )


class TestAssembleChatContextPreset:
    """assemble_chat_context 普通/重生成两条路径均读会话快照并传参"""

    def test_normal_path_injects_snapshot(self, db_session, monkeypatch) -> None:
        """普通路径（current_input 非 None）：注入快照 few-shot"""
        _patch_resolve_llm(monkeypatch)
        char = _make_character(db_session)
        preset = "<START>\n{{user}}: 预设问\n{{char}}: 预设答"
        conv = _make_conversation(db_session, char.id, preset_dialogue=preset)

        ctx = chat_service.assemble_chat_context(
            db_session, conv.id, current_input="当前"
        )

        contents = [m["content"] for m in ctx.messages]
        assert "预设问" in contents
        assert "预设答" in contents

    def test_snapshot_vs_character_live_value(self, db_session, monkeypatch) -> None:
        """快照语义（chat 层承担读快照）：改角色卡 preset_dialogues 实时值不影响已建会话注入源"""
        _patch_resolve_llm(monkeypatch)
        char = _make_character(
            db_session,
            preset_dialogues=[{"name": "角色对话", "content": "{{user}}: 角色问\n{{char}}: 角色答"}],
        )
        preset = "<START>\n{{user}}: 快照问\n{{char}}: 快照答"
        conv = _make_conversation(db_session, char.id, preset_dialogue=preset)

        # 建会话后改角色卡实时值（模拟用户后续编辑角色）
        char.preset_dialogues = [{"name": "改后", "content": "{{user}}: 改后问\n{{char}}: 改后答"}]
        db_session.commit()

        ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="当前")
        contents = [m["content"] for m in ctx.messages]
        assert "快照问" in contents
        assert "快照答" in contents
        assert "改后问" not in contents

    def test_regenerate_path_injects_snapshot(self, db_session, monkeypatch) -> None:
        """重生成路径（current_input=None）：注入快照 few-shot"""
        _patch_resolve_llm(monkeypatch)
        char = _make_character(db_session)
        preset = "<START>\n{{user}}: 预设问\n{{char}}: 预设答"
        conv = _make_conversation(db_session, char.id, preset_dialogue=preset)

        ctx = chat_service.assemble_chat_context(
            db_session, conv.id, current_input=None
        )

        contents = [m["content"] for m in ctx.messages]
        assert "预设问" in contents
        assert "预设答" in contents


class TestBuildPromptDebugPreset:
    """build_prompt_debug 读快照，保持 debug 追溯与线上 messages 逐条一致"""

    def test_reads_snapshot(self, db_session) -> None:
        """快照非空 → segments 含 preset few-shot（source=character）"""
        char = _make_character(db_session)
        preset = "<START>\n{{user}}: 预设问\n{{char}}: 预设答"
        conv = _make_conversation(db_session, char.id, preset_dialogue=preset)

        resp = chat_service.build_prompt_debug(db_session, conv.id)

        preset_segments = [
            s for s in resp.segments
            if s.role in ("user", "assistant") and s.content in ("预设问", "预设答")
        ]
        assert len(preset_segments) == 2
        assert all(s.source == SOURCE_CHARACTER for s in preset_segments)


# ── 4. CharacterData.from_orm 唯一投影入口 ──


class TestCharacterDataFromOrm:
    """CharacterData.from_orm 角色投影（F-147）：PROMPT_FIELDS + 补位 + None 空角色"""

    def test_projects_prompt_fields_with_defaults(self, db_session) -> None:
        """PROMPT_FIELDS 通配投影 + prompt_mode/expert_prompt 补位（DB 未设置 → 默认）"""
        char = _make_character(
            db_session,
            name="投影角色",
            personality="投影人格",
            scenario="投影场景",
            mes_example="范例",
            post_history_instructions="历史后指令",
        )
        data = CharacterData.from_orm(char)
        assert data.name == "投影角色"
        assert data.system_prompt == ""
        assert data.personality == "投影人格"
        assert data.scenario == "投影场景"
        assert data.mes_example == "范例"
        assert data.post_history_instructions == "历史后指令"
        assert data.prompt_mode == "simple"  # 未设置 → 默认补位
        assert data.expert_prompt == ""

    def test_projects_expert_mode_fields(self, db_session) -> None:
        """prompt_mode/expert_prompt 从 ORM 透传（expert 模式）"""
        char = _make_character(db_session, prompt_mode="expert", expert_prompt="专家提示")
        data = CharacterData.from_orm(char)
        assert data.prompt_mode == "expert"
        assert data.expert_prompt == "专家提示"

    def test_none_returns_empty_character(self) -> None:
        """character 为 None → 空角色 CharacterData(name="")（对齐 build_prompt_debug 可空语义）"""
        assert CharacterData.from_orm(None) == CharacterData(name="")
