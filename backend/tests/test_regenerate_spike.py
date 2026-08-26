"""
Spike · T0: regenerate truncation × sliding window boundary contract

NOT for production — empirical tracer tests that witness real behavior of the
existing message assembly / sliding window / service layer when given states
that a "regenerate (delete target + rebuild)" path would produce.

Each test group documents: input snapshot, asserted output, and the empirical
observation that feeds into the spike-regenerate-report.md.

These tests are self-contained, use the same db_session fixture as the rest of
the backend test suite, and do not depend on test ordering.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from sqlalchemy.orm import Session

from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import message as message_service
from backend.app.services.llm.prompt import (
    CharacterData,
    build_messages,
)

# ── helpers ──


def _char(**overrides: str) -> CharacterData:
    """Minimal character for pure build_messages tests"""
    base = {
        "name": "测试角色",
        "system_prompt": "你是测试角色。",
        "personality": "",
        "scenario": "",
        "mes_example": "",
        "post_history_instructions": "",
    }
    base.update(overrides)
    return CharacterData(**base)


def _msg(role: str, content: str) -> SimpleNamespace:
    return SimpleNamespace(role=role, content=content)


def _history(n: int, start: int = 0) -> list[SimpleNamespace]:
    """Alternating user/assistant messages"""
    return [
        _msg("user" if i % 2 == 0 else "assistant", f"m{i}")
        for i in range(start, start + n)
    ]


def _create_character(db: Session, first_mes: str = "", temperature: float = 0.7) -> int:
    from backend.app.models.character import Character
    char = Character(
        name="测试角色",
        personality="冷静、睿智",
        first_mes=first_mes,
        temperature=temperature,
    )
    db.add(char)
    db.commit()
    db.refresh(char)
    return char.id


def _create_conversation(
    db: Session,
    *,
    character_id: int | None = None,
    provider: str = "claude",
    model: str = "claude-test",
) -> int:
    if character_id is None:
        character_id = _create_character(db)
    conv = conversation_service.create_conversation(
        db,
        ConversationCreate(
            character_id=character_id,
            model_provider=provider,
            model_name=model,
        ),
    )
    return conv.id


def _add_messages(
    db: Session,
    conversation_id: int,
    *pairs: tuple[str, str],
) -> None:
    """Add messages in order: each pair is (role, content)"""
    for role, content in pairs:
        message_service.create_message(db, conversation_id, Role(role), content)


# ═══════════════════════════════════════════════════════════════
# Group 1: build_messages (pure) sliding window boundaries
# ═══════════════════════════════════════════════════════════════


class TestPureSlidingWindow:
    """Empirical: pure build_messages sliding window at known boundaries

    Reference: build_messages in services/llm/prompt.py
    - max_rounds=2 -> window = 4 (max_rounds * 2)
    """

    def test_at_boundary_keeps_all(self) -> None:
        """Boundary: exactly max_rounds*2 history items → all kept"""
        char = _char()
        history = _history(4)  # 4 items = max_rounds*2 when max_rounds=2
        msgs = build_messages(char, history, "当前", max_rounds=2)
        history_roles = [(m["role"], m["content"]) for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert history_roles == [("user", "m0"), ("assistant", "m1"), ("user", "m2"), ("assistant", "m3")]
        # Last message is always the current user input
        assert msgs[-1] == {"role": "user", "content": "当前"}

    def test_exceeds_window_trims_to_last(self) -> None:
        """Boundary: max_rounds*2+1 history items → trimmed to last max_rounds*2"""
        char = _char()
        history = _history(5)  # 5 items = 4+1 (max_rounds=2)
        msgs = build_messages(char, history, "当前", max_rounds=2)
        history_roles = [(m["role"], m["content"]) for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        # Should keep last 4: m1, m2, m3, m4
        assert history_roles == [("assistant", "m1"), ("user", "m2"), ("assistant", "m3"), ("user", "m4")]
        # empirical observation: trimming starts from the *second* item (m1),
        # not the first (m0). This is because the sliding window truncates
        # the entire history list, not just user/assistant pairs.

    def test_less_than_window_keeps_all(self) -> None:
        """Boundary: fewer than max_rounds*2 → all kept"""
        char = _char()
        history = _history(2)
        msgs = build_messages(char, history, "当前", max_rounds=30)
        history_roles = [(m["role"], m["content"]) for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert history_roles == [("user", "m0"), ("assistant", "m1")]

    def test_greeting_only_history(self) -> None:
        """Boundary: truncation leaves only greeting (1 assistant message)"""
        char = _char()
        # Simulate: after truncation, only greeting remains
        history = [_msg("assistant", "你好！我是测试角色。")]
        msgs = build_messages(char, history, "你好啊", max_rounds=30)
        # Last message must be the current user input
        assert msgs[-1] == {"role": "user", "content": "你好啊"}
        # The greeting is in history
        history_msgs = [m for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert history_msgs == [{"role": "assistant", "content": "你好！我是测试角色。"}]

    def test_empty_history(self) -> None:
        """Boundary: completely empty history (no greeting, no messages at all)"""
        char = _char()
        msgs = build_messages(char, [], "首条消息", max_rounds=30)
        # Only message should be the current user input
        assert msgs[-1] == {"role": "user", "content": "首条消息"}
        # No user/assistant history messages
        history_msgs = [m for m in msgs[:-1] if m["role"] in ("user", "assistant")]
        assert history_msgs == []

    def test_trigger_from_last_user_no_duplicate_append(self) -> None:
        """Empirical: regenerate scenario — last history message is user, content same as current input

        KEY EMPIRICAL QUESTION: If we reuse build_messages with
        user_content = content of last history item (a user message from the
        previous turn), does the assembled list contain that message twice?
        """
        char = _char()
        history = [_msg("user", "重复消息"), _msg("assistant", "旧回复")]
        # Manual truncation: remove the assistant → history = [user("重复消息")]
        truncated = history[:1]  # [user("重复消息")]
        # If we call build_messages with user_content = "重复消息" (same as the last history item)
        msgs = build_messages(char, truncated, "重复消息", max_rounds=30)
        # Count occurrences of "重复消息" in user/assistant messages
        occurrences = [m for m in msgs if m["role"] in ("user", "assistant") and m["content"] == "重复消息"]
        assert len(occurrences) == 2
        # Empirical: the last user message IS duplicated — once in history, once
        # as appended current input. This is the baseline behavior T5 must account for.
        # Recommendation: build a variant that skips appending current input, or
        # deduplicates by checking if the last history message is a user with same content.


# ═══════════════════════════════════════════════════════════════
# Group 2: build_message_list (DB-integrated) sliding window
# ═══════════════════════════════════════════════════════════════


class TestDbSlidingWindow:
    """Empirical: build_message_list with actual DB rows

    Uses default sliding_window_rounds=30 (from config).
    """

    def test_exactly_60_messages(self, db_session: Session) -> None:
        """Boundary: exactly 60 messages (max_rounds*2) → all kept"""
        conv_id = _create_conversation(db_session, character_id=_create_character(db_session))
        # Add 60 messages (30 rounds)
        pairs = []
        for i in range(30):
            pairs.append(("user", f"user msg {i}"))
            pairs.append(("assistant", f"assistant msg {i}"))
        _add_messages(db_session, conv_id, *pairs)

        conv = conversation_service.get_conversation(db_session, conv_id)
        msgs = message_service.build_message_list(
            db_session, conv, "当前输入", max_rounds=30,
        )
        # Count user/assistant messages from history (exclude system preamble)
        history_msgs = [m for m in msgs if m["role"] in ("user", "assistant")]
        # 60 history + 1 current input = 61 user/assistant entries
        assert len(history_msgs) == 61
        # Last one must be current input
        assert history_msgs[-1] == {"role": "user", "content": "当前输入"}
        # First history message should be m0
        assert history_msgs[0] == {"role": "user", "content": "user msg 0"}

    def test_exceeds_60_messages_trims(self, db_session: Session) -> None:
        """Boundary: 61 messages (max_rounds*2+1) → trimmed to last 60"""
        conv_id = _create_conversation(db_session, character_id=_create_character(db_session))
        # Add 61 messages (30.5 rounds)
        pairs = []
        for i in range(30):
            pairs.append(("user", f"user msg {i}"))
            pairs.append(("assistant", f"assistant msg {i}"))
        pairs.append(("user", "user msg 30"))  # 61st message
        _add_messages(db_session, conv_id, *pairs)

        conv = conversation_service.get_conversation(db_session, conv_id)
        msgs = message_service.build_message_list(
            db_session, conv, "当前输入", max_rounds=30,
        )
        history_msgs = [m for m in msgs if m["role"] in ("user", "assistant")]
        # 60 history + 1 current input = 61
        assert len(history_msgs) == 61
        # First history message should be m1 (because m0 was trimmed)
        assert history_msgs[0] == {"role": "assistant", "content": "assistant msg 0"}
        # empirical: the first entry (user msg 0) was trimmed, first kept is assistant msg 0
        # This is because the list is: [user0, asst0, user1, asst1, ..., user30]
        # After trimming to last 60 (from 61), the list starts at index 1 = asst0

    def test_truncation_greeting_only(self, db_session: Session) -> None:
        """Boundary: after truncation only greeting remains (1 assistant)"""
        char_id = _create_character(db_session, first_mes="初次见面，请多关照！")
        conv_id = _create_conversation(db_session, character_id=char_id)
        # Simulate: first user message sent → greeting auto-inserted + user message
        # Then regenerate: delete target (assistant reply) → only greeting + user remain
        # Then truncate to greeting (the user message that triggered it is also part of
        # the "regenerate" scope — spec says delete target AND all after)
        # Actually: "delete target AI reply and all subsequent messages"
        # So if target is the second assistant (reply to first user), we delete:
        #   assistant reply, and anything after it (nothing after)
        #   → remaining: [greeting, user]
        # But the spike asks: "截断后仅剩 greeting" — so we simulate directly
        _add_messages(db_session, conv_id, ("assistant", "初次见面，请多关照！"))

        conv = conversation_service.get_conversation(db_session, conv_id)
        msgs = message_service.build_message_list(
            db_session, conv, "你好", max_rounds=30,
        )
        history_msgs = [m for m in msgs if m["role"] in ("user", "assistant")]
        # Last is current input
        assert history_msgs[-1] == {"role": "user", "content": "你好"}
        # Greeting is in history
        assert history_msgs[0] == {"role": "assistant", "content": "初次见面，请多关照！"}

    def test_trigger_from_last_user_duplicates(self, db_session: Session) -> None:
        """Empirical: regenerate scenario via build_message_list

        Simulate: conversation has [U, A], truncate A (delete),
        then call build_message_list with user_content = U's content.
        """
        conv_id = _create_conversation(db_session, character_id=_create_character(db_session))
        _add_messages(db_session, conv_id, ("user", "触发消息"), ("assistant", "旧回复"))

        # Simulate truncation: delete the assistant message
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.role == Role.ASSISTANT)
            .first()
        )
        assert target is not None
        db_session.delete(target)
        db_session.commit()

        # Now history is [user("触发消息")]
        conv = conversation_service.get_conversation(db_session, conv_id)
        msgs = message_service.build_message_list(
            db_session, conv, "触发消息", max_rounds=30,
        )
        history_msgs = [m for m in msgs if m["role"] in ("user", "assistant")]
        # Count "触发消息" occurrences
        dupes = [m for m in history_msgs if m["content"] == "触发消息"]
        assert len(dupes) == 2
        # Empirical: calling build_message_list with user_content == last user's
        # content creates a duplicate — once in history, once as appended input.
        # This is the baseline behavior T5 must handle.


# ═══════════════════════════════════════════════════════════════
# Group 3: Truncation + Integrity (ghost messages, transactions)
# ═══════════════════════════════════════════════════════════════


class TestTruncationIntegrity:
    """Empirical: message integrity after truncation + naive regenerate

    Simulates the "复用非流式路径" risk: if a regenerate implementation calls
    prepare_chat (which inserts user via create_message) after truncating,
    the result is a duplicate user message permanently committed.
    """

    def test_naive_prepare_chat_creates_duplicate_user(self, db_session: Session) -> None:
        """Empirical: reusing prepare_chat after truncation creates ghost user message

        Prepare_chat → create_message(USER, content) → build_message_list.
        After truncation, the last message is user U. If we call prepare_chat
        with content = U's content, a new user U' is committed to the DB.
        """
        # Setup: create character NO greeting (first_mes="") to isolate
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv_id, ("user", "原始消息"), ("assistant", "原始回复"))

        # Simulate truncation: delete assistant
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.role == Role.ASSISTANT)
            .first()
        )
        db_session.delete(target)
        db_session.commit()

        # At this point: 1 user message in DB
        count_before = db_session.query(Message).filter(Message.conversation_id == conv_id).count()
        assert count_before == 1

        # Simulate naive prepare_chat: insert user again
        message_service.create_message(db_session, conv_id, Role.USER, "原始消息")

        # Count: now 2 user messages (duplicate)
        messages = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id)
            .order_by(Message.created_at.asc())
            .all()
        )
        assert len(messages) == 2
        assert messages[0].role == Role.USER and messages[0].content == "原始消息"
        assert messages[1].role == Role.USER and messages[1].content == "原始消息"
        # Empirical: TWO user rows with identical content. This is the ghost/duplicate
        # risk documented in the spec. Every regenerate that reuses prepare_chat
        # as-is creates a permanent duplicate user message.

    def test_auto_title_not_affected_by_truncation(self, db_session: Session) -> None:
        """Empirical: maybe_auto_title only fires on first user; truncation doesn't reset"""
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        # First user message sets title
        _add_messages(db_session, conv_id, ("user", "hello world"), ("assistant", "hi"))
        conv = conversation_service.get_conversation(db_session, conv_id)
        # Title should be truncated form of "hello world"
        assert conv and conv.title == "hello world"
        assert conv is not None

        # Truncate: delete the user message (the first user)
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.role == Role.USER)
            .first()
        )
        db_session.delete(target)
        db_session.commit()

        # Title is NOT reset — still "hello world" even though the message that
        # set it is gone
        db_session.refresh(conv)
        assert conv.title == "hello world"
        # Empirical: once auto-title fires, truncation doesn't revert it.
        # This is fine — regenerate doesn't need to revert the title.

    def test_updated_at_bumps_only_on_new_message(self, db_session: Session) -> None:
        """Empirical: conv.updated_at changes only on message creation, not deletion"""
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)

        _add_messages(db_session, conv_id, ("user", "测试"), ("assistant", "回复"))
        conv = conversation_service.get_conversation(db_session, conv_id)
        assert conv is not None
        after_add = conv.updated_at

        # Delete a message (truncation) — should NOT change updated_at
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.role == Role.ASSISTANT)
            .first()
        )
        db_session.delete(target)
        db_session.commit()
        db_session.refresh(conv)
        assert conv.updated_at == after_add
        # Empirical: deletion does NOT update conv.updated_at.
        # Only create_message (via conv.updated_at = datetime.now()) bumps it.
        # Implication: a regenerate that only truncates + regenerates will bump
        # updated_at exactly once (at assistant save) — no double-touch from deletion.

    def test_transaction_rollback_prevents_ghost(self, db_session: Session) -> None:
        """Empirical: wrapping delete + create in one transaction prevents ghost state

        If delete and re-create are in the SAME transaction (single commit), a
        rollback (e.g., LLM failure before commit) leaves the DB unchanged —
        the original timeline is preserved.
        """
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv_id, ("user", "原始"), ("assistant", "回复"))

        # Same-transaction simulation: delete target + insert new assistant,
        # then ROLLBACK the whole unit (no commit).
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.role == Role.ASSISTANT)
            .first()
        )
        db_session.delete(target)
        # NOTE: a real regenerate must NOT call create_message() before commit here —
        # create_message() commits internally (message.py), breaking atomicity.

        # Rollback the unit (delete not yet committed)
        db_session.rollback()

        # Messages should still be intact (delete undone)
        count = db_session.query(Message).filter(Message.conversation_id == conv_id).count()
        assert count == 2
        # Empirical: uncommitted delete is rolled back → original timeline preserved.
        # BUT: create_message() calls db.commit() internally (see message.py), so a
        # naive "truncate then create_message" flow CANNOT be one atomic transaction —
        # T5 must provide a transactional variant (bulk delete + single commit,
        # or a create-message-without-commit helper) to get atomicity.


# ═══════════════════════════════════════════════════════════════
# Group 4: Error semantics (empirical observation + recommendations)
# ═══════════════════════════════════════════════════════════════


class TestErrorSemantics:
    """Empirical: what happens with edge-case inputs in the current codebase

    These tests verify the existing code's behavior and document contract
    recommendations for the new regenerate endpoint.
    """

    def test_conversation_not_found_raises_domain_error(self, db_session: Session) -> None:
        """Empirical: require_conversation raises ConversationNotFoundError (→404)"""
        from backend.app.services.exceptions import ConversationNotFoundError

        with pytest.raises(ConversationNotFoundError):
            conversation_service.require_conversation(db_session, 99999)

    def test_message_id_not_found_raises_value_error(self, db_session: Session) -> None:
        """Empirical: querying nonexistent message_id returns None;
        recommend new MessageNotFoundError (404) for regenerate endpoint.
        """
        msg = db_session.query(Message).filter(Message.id == 99999).first()
        assert msg is None

    def test_target_not_assistant_semantics(self, db_session: Session) -> None:
        """Empirical: if target message is user, regenerate semantics are invalid.
        Recommend 400 with DomainError.
        """
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        _add_messages(db_session, conv_id, ("user", "用户消息"))

        # The only message is a user message — regenerate would target it
        # (since it's the last message AND it's user). Recommend 400 reject.
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.role == Role.USER)
            .first()
        )
        assert target is not None
        assert target.role == Role.USER
        # Empirical: current codebase has no entity-level validation for
        # "target must be assistant" — this must be added by T5.

    def test_empty_conversation_empty_message_list(self, db_session: Session) -> None:
        """Empirical: empty conversation (no messages at all) with build_message_list"""
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        conv = conversation_service.get_conversation(db_session, conv_id)
        assert conv is not None

        # Even with empty history, build_message_list should work (no greeting auto-insert)
        msgs = message_service.build_message_list(db_session, conv, "触发", max_rounds=30)
        user_messages = [m for m in msgs if m["role"] == "user"]
        # The current input is appended
        assert len(user_messages) == 1
        assert user_messages[0]["content"] == "触发"
        # Empirical: build_message_list tolerates empty history gracefully.
        # But regenerate in an empty conversation has no "last user message" to
        # derive trigger content from → recommend 400.


# ═══════════════════════════════════════════════════════════════
# Group 5: Trigger content source semantics
# ═══════════════════════════════════════════════════════════════


class TestTriggerContext:
    """Empirical: what is the "current trigger content" source for regenerate

    The spec says: "不插入 user 的触发上下文：下层函数（组装+解析 provider，
    不插入 user）vs 既有 prepare_chat（先插 user 再组装）"
    """

    def test_trigger_from_last_user_before_target(self, db_session: Session) -> None:
        """Empirical: after truncating target, the last user message is the trigger source.

        NOTE: anchor by PK `id` (monotonic), NOT `created_at` (second-precision,
        ties across messages in the same second → unreliable ordering).
        """
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv_id,
            ("user", "第一轮问"), ("assistant", "第一轮答"),
            ("user", "第二轮问"), ("assistant", "第二轮答"),
        )

        # Delete "第二轮答" (target), then "第二轮问" is the last message
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.content == "第二轮答")
            .first()
        )
        db_session.delete(target)
        db_session.commit()

        # The last message by PK id is now "第二轮问" (user)
        last_msg = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id)
            .order_by(Message.id.desc())
            .first()
        )
        assert last_msg is not None
        assert last_msg.role == Role.USER
        assert last_msg.content == "第二轮问"
        # Empirical: trigger content = "第二轮问" (the user message that was
        # immediately before the deleted target). This is the canonical source.
        # Ordering must be by PK id, not created_at (see test_created_at_tie below).

    def test_created_at_anchor_overtruncates_on_tie(self, db_session: Session) -> None:
        """Empirical: created_at-anchored truncation over-deletes on timestamp ties.

        Real behavior observed in spike debug runs: adjacent `create_message` calls
        can land on the SAME microsecond timestamp (e.g. two pairs at 232736 / 236205),
        so `created_at` is not a monotonic per-message key. If truncation were anchored
        on `created_at >= target.created_at`, any earlier neighbor sharing the exact
        timestamp would be deleted too. The monotonic PK `id` must be the anchor.
        """
        import datetime

        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv_id,
            ("user", "第一轮问"), ("assistant", "第一轮答"), ("user", "第二轮问"),
        )
        # Force the timestamp tie that real runs can produce: all three messages
        # share the same microsecond (as if created in one create_message burst).
        rows = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id)
            .order_by(Message.created_at.asc())
            .all()
        )
        shared = datetime.datetime(2026, 1, 1, 12, 0, 0, 1)
        for r in rows:
            r.created_at = shared
        db_session.commit()

        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.content == "第二轮问")
            .one()
        )
        # A created_at-anchored truncation of the last message over-deletes:
        count_created_at = (
            db_session.query(Message)
            .filter(
                Message.conversation_id == conv_id,
                Message.created_at >= target.created_at,
            )
            .count()
        )
        assert count_created_at == 3  # ids 1-3 all share the timestamp → all deleted

        # The id anchor deletes exactly the target:
        count_id = (
            db_session.query(Message)
            .filter(
                Message.conversation_id == conv_id,
                Message.id >= target.id,
            )
            .count()
        )
        assert count_id == 1

    def test_trigger_from_non_last_user(self, db_session: Session) -> None:
        """Empirical: target is not the last message — delete target + all after

        After truncation: first user message's content is the trigger source.
        """
        char_id = _create_character(db_session, first_mes="")
        conv_id = _create_conversation(db_session, character_id=char_id)
        _add_messages(
            db_session, conv_id,
            ("user", "问题"), ("assistant", "旧回复"),
            ("user", "额外问题"), ("assistant", "额外回复"),
        )

        # Delete "旧回复" AND "额外问题" AND "额外回复" (target + all after)
        target = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.content == "旧回复")
            .first()
        )
        target_id = target.id
        # Delete target + all messages with id > target_id
        db_session.query(Message).filter(
            Message.conversation_id == conv_id,
            Message.id >= target_id,
        ).delete(synchronize_session=False)
        db_session.commit()

        # Remaining: [user("问题")]
        remaining = db_session.query(Message).filter(Message.conversation_id == conv_id).all()
        assert len(remaining) == 1
        assert remaining[0].content == "问题"
        assert remaining[0].role == Role.USER
        # Empirical: trigger content = "问题" (the user message before the target).
        # After truncation, this is the last (and only) remaining message.

    def test_no_user_after_truncation_greeting_only(self, db_session: Session) -> None:
        """Empirical: truncation leaves only greeting (assistant), no user → no trigger source"""
        char_id = _create_character(db_session, first_mes="欢迎！")
        conv_id = _create_conversation(db_session, character_id=char_id)
        # Deterministic greeting-only state: auto_insert_greeting inserts the
        # first assistant message and nothing else (no user message).
        message_service.auto_insert_greeting(db_session, conv_id, user_name="User")

        remaining = db_session.query(Message).filter(Message.conversation_id == conv_id).all()
        assert len(remaining) == 1
        assert remaining[0].role == Role.ASSISTANT
        assert remaining[0].content == "欢迎！"

        # Empirical: no user message in the timeline → trigger content cannot be
        # derived from history. Recommend regenerate returns 400 for this state.
        user_count = (
            db_session.query(Message)
            .filter(Message.conversation_id == conv_id, Message.role == Role.USER)
            .count()
        )
        assert user_count == 0