"""
02 叙述风格 prompt 注入与接线 — 契约锁

覆盖（issue 02 八条验收标准）：
    1. SOURCE_NARRATIVE 进 prompt.__all__ 且值为 "narrative"
    2. build_messages / build_messages_with_source 新增 narrative_style 参数透传 _assemble
    3. _assemble 注入序：after_char 之后、[世界知识] 之前；content = "[叙述风格]\\n<规则>"
    4. narrative_style 空串 / 纯空白零注入，输出与不传逐字节一致（契约锁）
    5. build_message_list 查 narrative_style_enabled + rules 并透传（关闭时零注入且不读 rules）
    6. assemble_chat_context 普通 / 重生成两条路径均注入
    7. expert 模式同样注入（after_char 不在 expert 替代范围）
    8. build_prompt_debug 输出 source="narrative" 段，位置在 after_char 之后、世界知识之前

依赖：pytest + SQLite 内存库（db_session fixture，见 conftest.py）。
"""

from __future__ import annotations

import pytest

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message, Role
from backend.app.models.setting import Setting
from backend.app.schemas.lorebook import LorebookEntryCreate
from backend.app.services import chat as chat_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.llm import prompt as prompt_module
from backend.app.services.llm import resolver as llm_resolver
from backend.app.services.llm.prompt import (
    CharacterData,
    build_messages,
    build_messages_with_source,
)

__all__: list[str] = []


def _character(**overrides: object) -> CharacterData:
    """角色纯数据工厂（字段可覆盖；默认无 scenario / mes_example / PHI）"""
    base: dict[str, object] = {
        "name": "测试角色",
        "system_prompt": "",
        "personality": "你是测试角色。",
        "scenario": "",
        "mes_example": "",
        "post_history_instructions": "",
    }
    base.update(overrides)
    return CharacterData(**base)  # type: ignore[arg-type]


def _persist_character(db_session, **overrides: object) -> Character:
    """落库角色（字段可覆盖），返回持久化实例"""
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
    """落库对话（字段可覆盖），返回持久化实例"""
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


def _save_setting(db_session, key: str, value: str) -> None:
    """写入一条设置记录"""
    db_session.add(Setting(key=key, value=value))
    db_session.commit()


class TestSourceNarrativeConstant:
    def test_constant_value_and_all(self) -> None:
        """SOURCE_NARRATIVE == "narrative" 且进 __all__"""
        assert prompt_module.SOURCE_NARRATIVE == "narrative"
        assert "SOURCE_NARRATIVE" in prompt_module.__all__


class TestPromptNarrativeInjection:
    def test_injects_between_after_char_and_world_knowledge(self) -> None:
        """注入序：after_char 之后、[世界知识] 之前，source="narrative"（锁 3）"""
        char = _character()
        world = {"after_char": ["场景后注入"], "system": ["世界知识"]}
        segments = build_messages_with_source(
            char, [], "输入", world=world, narrative_style="规则"
        )

        assert segments == [
            {"role": "system", "content": "你是测试角色。", "source": "character"},
            {"role": "system", "content": "场景后注入", "source": "world"},
            {"role": "system", "content": "[叙述风格]\n规则", "source": "narrative"},
            {"role": "system", "content": "[世界知识]\n世界知识", "source": "world"},
            {"role": "user", "content": "输入", "source": "user"},
        ]

    def test_build_messages_returns_no_source_key(self) -> None:
        """build_messages 零来源语义：narrative 段同样剥离 source，仅 role/content"""
        char = _character()
        msgs = build_messages(char, [], "输入", narrative_style="规则")
        assert {"role": "system", "content": "[叙述风格]\n规则"} in msgs
        assert all("source" not in m for m in msgs)

    def test_empty_narrative_byte_identical(self) -> None:
        """空串零注入：输出与不传 narrative_style 逐字节一致（锁 4）"""
        char = _character()
        baseline = build_messages(char, [], "输入")
        assert build_messages(char, [], "输入", narrative_style="") == baseline

    @pytest.mark.parametrize("blank", ["", "   ", "\n\t\n", " \t "])
    def test_whitespace_narrative_zero_injection(self, blank: str) -> None:
        """纯空白零注入：与不传逐字节一致"""
        char = _character()
        baseline = build_messages(char, [], "输入")
        assert build_messages(char, [], "输入", narrative_style=blank) == baseline

    def test_with_source_narrative_source(self) -> None:
        """build_messages_with_source：narrative 段 source="narrative"（锁 2）"""
        segments = build_messages_with_source(
            _character(), [], "输入", narrative_style="自定义规则"
        )
        narrative = [s for s in segments if s.get("source") == "narrative"]
        assert narrative == [
            {"role": "system", "content": "[叙述风格]\n自定义规则", "source": "narrative"}
        ]


class TestExpertNarrativeInjection:
    def test_expert_mode_narrative_injected(self) -> None:
        """expert 模式：narrative 段在 expert system 之后、[世界知识] 之前"""
        char = _character(prompt_mode="expert", expert_prompt="专家指令")
        world = {"after_char": ["场景后"], "system": ["世界知识"]}
        segments = build_messages_with_source(
            char, [], "输入", world=world, narrative_style="规则"
        )

        assert segments == [
            {"role": "system", "content": "专家指令", "source": "character"},
            {"role": "system", "content": "场景后", "source": "world"},
            {"role": "system", "content": "[叙述风格]\n规则", "source": "narrative"},
            {"role": "system", "content": "[世界知识]\n世界知识", "source": "world"},
            {"role": "user", "content": "输入", "source": "user"},
        ]


class TestBuildMessageListNarrative:
    def test_explicit_style_injects(self, db_session) -> None:
        """显式传 narrative_style → 注入（build_message_list 纯透传，不查设置）"""
        char = _persist_character(db_session)
        conv = _persist_conversation(db_session, char.id)

        msgs = message_service.build_message_list(
            db_session, conv, "你好", narrative_style="自定义规则"
        )

        assert {"role": "system", "content": "[叙述风格]\n自定义规则"} in msgs

    def test_empty_style_zero_injection(self, db_session) -> None:
        """显式传空串 → 零注入（不查设置）"""
        char = _persist_character(db_session)
        conv = _persist_conversation(db_session, char.id)

        msgs = message_service.build_message_list(
            db_session, conv, "你好", narrative_style=""
        )
        assert not any(m["content"].startswith("[叙述风格]") for m in msgs)


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


def _patch_llm(monkeypatch) -> None:
    """让 api_key 恒返回测试 Key + LLMFactory 返回假 Provider（绕过真实网络）"""
    monkeypatch.setattr(setting_service, "api_key", lambda db, provider: "test-key")
    monkeypatch.setattr(llm_resolver, "LLMFactory", _FakeLLMFactory(_FakeProvider()))


class TestAssembleChatContextNarrative:
    def test_normal_path_injects(self, db_session, monkeypatch) -> None:
        """普通发送路径（current_input 非 None）→ 注入叙述风格"""
        _patch_llm(monkeypatch)
        char = _persist_character(db_session)
        conv = _persist_conversation(db_session, char.id)
        _save_setting(db_session, "narrative_style_enabled", "1")
        _save_setting(db_session, "narrative_style_rules", "自定义规则")

        ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="你好")

        assert {"role": "system", "content": "[叙述风格]\n自定义规则"} in ctx.messages

    def test_regenerate_path_injects(self, db_session, monkeypatch) -> None:
        """重生成路径（current_input=None）→ 注入叙述风格"""
        _patch_llm(monkeypatch)
        char = _persist_character(db_session)
        conv = _persist_conversation(db_session, char.id)
        db_session.add(Message(conversation_id=conv.id, role=Role.USER, content="触发问"))
        db_session.commit()
        _save_setting(db_session, "narrative_style_enabled", "1")
        _save_setting(db_session, "narrative_style_rules", "自定义规则")

        ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input=None)

        assert {"role": "system", "content": "[叙述风格]\n自定义规则"} in ctx.messages


class TestPromptDebugNarrative:
    def test_source_narrative_and_position(self, db_session) -> None:
        """debug 输出 source="narrative" 段，位置在 after_char 之后、世界知识之前"""
        char = _persist_character(db_session)
        conv = _persist_conversation(db_session, char.id)
        _save_setting(db_session, "narrative_style_enabled", "1")
        _save_setting(db_session, "narrative_style_rules", "自定义规则")
        lorebook_service.create_entry(
            db_session, char.id,
            LorebookEntryCreate(
                keys=(), content="场景后", constant=True,
                position="after_char", source="manual",
            ),
        )
        lorebook_service.create_entry(
            db_session, char.id,
            LorebookEntryCreate(
                keys=(), content="世界知识", constant=True,
                position="world", source="manual",
            ),
        )

        debug = chat_service.build_prompt_debug(db_session, conv.id)

        contents = [s.content for s in debug.segments]
        sources = [s.source for s in debug.segments]
        assert "[叙述风格]\n自定义规则" in contents
        narr_idx = contents.index("[叙述风格]\n自定义规则")
        after_idx = contents.index("场景后")
        world_idx = contents.index("[世界知识]\n世界知识")
        assert after_idx < narr_idx < world_idx
        assert sources[narr_idx] == "narrative"