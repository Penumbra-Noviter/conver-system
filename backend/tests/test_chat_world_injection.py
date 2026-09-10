"""
assemble_chat_context 世界书注入集成契约锁（WL-3，chat 层）

锁定语义（docs/chat-simulator-upgrade-spec.md §WL-3）：
- 查角色 → list_entries → collect_scan_text(history, current_input, max(enabled.depth))
  → activate → build_world_injection → 传入 build_message_list
- 普通路径（current_input 非空）与重生成路径（current_input=None）都吃到注入（两路径一致）
- 无条目角色零开销、输出无注入内容
- 滑窗（max_rounds）与激活窗口（depth）解耦：被滑窗截掉的历史仍在扫描窗内可命中
"""

from __future__ import annotations

import pytest
from sqlalchemy.orm import Session

from backend.app.models.character import Character
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.lorebook import LorebookEntryCreate
from backend.app.services import chat as chat_service
from backend.app.services import conversation as conversation_service
from backend.app.services import lorebook as lorebook_service
from backend.app.services import message as message_service
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
    """替代 LLMFactory.get_provider 的工厂（与 test_chat_service 同模式）"""

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


def _create_character(db: Session, name: str = "世界书角色") -> Character:
    """落库角色（无 greeting，简化断言）"""
    char = Character(name=name, personality="你是世界书测试角色。", scenario="测试场景", first_mes="")
    db.add(char)
    db.commit()
    db.refresh(char)
    return char


def _create_conversation(db: Session, character_id: int):
    """落库对话（默认 provider/model 回退 settings）"""
    return conversation_service.create_conversation(
        db, ConversationCreate(character_id=character_id)
    )


# ════════════════════════════════════════════════════════════════
# 一、普通路径注入
# ════════════════════════════════════════════════════════════════


def test_assemble_injects_world_block(db_session, monkeypatch) -> None:
    """普通路径：关键词命中 → [世界知识] 注入；constant 直进 → before_char 注入"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    lorebook_service.create_entry(
        db_session, char.id, LorebookEntryCreate(keys=("龙",), content="龙之国度", position="world", depth=20)
    )
    lorebook_service.create_entry(
        db_session, char.id, LorebookEntryCreate(keys=(), content="常驻指引", constant=True, position="before_char")
    )

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="龙在哪")

    contents = [m["content"] for m in ctx.messages]
    assert any("世界知识" in c and "龙之国度" in c for c in contents)  # 关键词命中注入
    assert contents[0] == "常驻指引"  # constant 条目直进，且置于 system prompt 前
    assert contents[1] == "你是世界书测试角色。"


def test_injection_key_from_history(db_session, monkeypatch) -> None:
    """depth 窗口：当前输入不含关键词但历史含 → 仍命中注入"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    message_service.create_message(db_session, conv.id, Role.USER, "上次我们聊到酒馆")
    message_service.create_message(db_session, conv.id, Role.ASSISTANT, "是的")
    lorebook_service.create_entry(
        db_session, char.id, LorebookEntryCreate(keys=("酒馆",), content="酒馆的老板是莉莉", depth=10)
    )

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="还有呢")
    contents = [m["content"] for m in ctx.messages]
    assert any("酒馆的老板是莉莉" in c for c in contents)


# ════════════════════════════════════════════════════════════════
# 二、重生成路径一致性
# ════════════════════════════════════════════════════════════════


def test_regenerate_path_injects_world(db_session, monkeypatch) -> None:
    """重生成路径（current_input=None）同样吃到注入：末条为历史末条 user"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    # 重生成截断后历史以触发 user 结尾（真实流程：_last_user_before 保证存在）
    message_service.create_message(db_session, conv.id, Role.USER, "我听说过龙")
    message_service.create_message(db_session, conv.id, Role.ASSISTANT, "是的")
    message_service.create_message(db_session, conv.id, Role.USER, "龙在哪里")
    lorebook_service.create_entry(
        db_session, char.id, LorebookEntryCreate(keys=("龙",), content="龙之国度", position="world")
    )

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input=None)
    contents = [m["content"] for m in ctx.messages]
    assert any("龙之国度" in c for c in contents)  # 重生成路径吃到注入
    assert ctx.messages[-1] == {"role": "user", "content": "龙在哪里"}  # 末条为历史末条 user


# ════════════════════════════════════════════════════════════════
# 三、空世界书零开销
# ════════════════════════════════════════════════════════════════


def test_no_entries_no_injection(db_session, monkeypatch) -> None:
    """角色无条目 → 无注入内容、无 [世界知识] system（不污染上下文）"""
    _patch_llm_env(monkeypatch)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    message_service.create_message(db_session, conv.id, Role.USER, "你好")
    message_service.create_message(db_session, conv.id, Role.ASSISTANT, "你好呀")

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="继续")
    contents = [m["content"] for m in ctx.messages]
    joined = "\n".join(contents)
    assert "世界知识" not in joined
    assert contents[0] == "你是世界书测试角色。"  # 结构不变：system prompt 在首位


# ════════════════════════════════════════════════════════════════
# 四、滑窗与 depth 解耦
# ════════════════════════════════════════════════════════════════


def test_scan_depth_independent_of_max_rounds(db_session, monkeypatch) -> None:
    """滑窗与激活窗口解耦：被滑窗截掉的最早消息仍在 depth 扫描窗内 → 命中注入
    （max_rounds=1 → 上下文只留最近 2 条；entry depth=20 → 扫描全历史）"""
    _patch_llm_env(monkeypatch)
    monkeypatch.setattr(setting_service, "sliding_window_rounds", lambda db: 1)
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    for i, text in enumerate(["第一轮问题", "回答一", "第二轮问题", "回答二", "第三轮问题", "回答三"]):
        role = Role.USER if i % 2 == 0 else Role.ASSISTANT
        message_service.create_message(db_session, conv.id, role, text)
    lorebook_service.create_entry(
        db_session, char.id, LorebookEntryCreate(keys=("第一轮",), content="旧闻命中", depth=20)
    )

    ctx = chat_service.assemble_chat_context(db_session, conv.id, current_input="问题")
    contents = [m["content"] for m in ctx.messages]
    joined = "\n".join(contents)
    assert "旧闻命中" in joined  # 注入块存在（depth 窗口含最早消息）
    assert "第一轮问题" not in joined  # 但最早消息本身已被滑窗截出上下文
    assert "第三轮问题" in joined  # 窗口内消息保留


def test_build_message_list_accepts_external_history(db_session, monkeypatch) -> None:
    """显式传 history 时不再重复查库（F-95 修复锁）"""
    char = _create_character(db_session)
    conv = _create_conversation(db_session, char.id)
    message_service.create_message(db_session, conv.id, Role.USER, "你好")
    message_service.create_message(db_session, conv.id, Role.ASSISTANT, "你好呀")

    def _forbid(_db, _cid) -> None:
        raise AssertionError("build_message_list 收到 history 后不应再查询历史")

    history = message_service.get_messages(db_session, conv.id)  # 调用方显式取一次
    monkeypatch.setattr(message_service, "get_messages", _forbid)
    msgs = message_service.build_message_list(db_session, conv, "输入", history=history)
    assert msgs[-1] == {"role": "user", "content": "输入"}
    assert any(m["content"] == "你好" for m in msgs)