"""preset_dialogues NULL 响应归一回归测试（冒烟 GET /api/characters 500 → 200）

存量库升级路径：characters.preset_dialogues 由自愈迁移补列（可空 JSON，无回填），
旧行值为 NULL；响应 schema 声明 list[PresetDialogue] 必填（default_factory 仅
在字段缺席时生效，显式 None 会验不过）→ FastAPI serialize_response 抛
ResponseValidationError → GET /api/characters 500（2026-09-21 桌面打包冒烟实测）。

修复：CharacterBase.preset_dialogues 增 mode="before" 验证器，None → []。
本测试锁定契约：NULL 行经 GET /api/characters 返回 200 且 preset_dialogues 归一为 []。

F-157（2026-09-21 折回消费）：同型补齐 tags/alternate_greetings/creator_notes/extensions
——update 显式 null 会经 exclude_unset+setattr 落 NULL 库后再序列化 500；存量 NULL
行同样在响应面 500。契约统一为「None 不入库」：create/update 显式 null 归一默认形态
（code-review 锁定，见 test_create_explicit_null_coerces_to_default），省略字段不受影响。
见 test_update_explicit_null_coerces_to_default / test_response_serializes_null_json_default_fields。
"""

from __future__ import annotations

from fastapi.testclient import TestClient
from sqlalchemy import text

from backend.app.database import get_db

__all__: list[str] = []

# (列名, 归一后的响应默认值) — 与 CharacterBase 字段默认形态同口径
_JSON_DEFAULT_FIELDS: list[tuple[str, object]] = [
    ("tags", []),
    ("alternate_greetings", []),
    ("creator_notes", {}),
    ("extensions", {}),
]


def _force_null_column(db_session, character_id: int, column: str) -> None:
    """模拟存量行：绕过 ORM default，直接把列置 NULL（自愈迁移补列后的旧库形态）"""
    db_session.execute(
        text(f"UPDATE characters SET {column} = NULL WHERE id = :id"),
        {"id": character_id},
    )
    db_session.commit()
    # 失效身份映射缓存，后续读取回库取真值（否则 ORM 对象持 stale 值掩盖缺陷）
    db_session.expire_all()


def test_list_characters_serializes_null_preset_dialogues(db_session, make_character) -> None:
    """GET /api/characters：preset_dialogues 为 NULL 的存量行 → 200 且归一为 []（不 500）"""
    from backend.app.main import app

    char = make_character()
    db_session.add(char)
    db_session.commit()
    _force_null_column(db_session, char.id, "preset_dialogues")

    app.dependency_overrides[get_db] = lambda: db_session
    try:
        client = TestClient(app, raise_server_exceptions=False)
        resp = client.get("/api/characters")
        assert resp.status_code == 200, f"存量 NULL 行不应 500: {resp.status_code} {resp.text}"
        body = resp.json()
        assert len(body) == 1
        assert body[0]["preset_dialogues"] == []
    finally:
        app.dependency_overrides.clear()


def test_response_serializes_null_json_default_fields(db_session, make_character) -> None:
    """GET /api/characters：tags/alternate_greetings/creator_notes/extensions 存量 NULL → 200 且归一默认形态"""
    from backend.app.main import app

    char = make_character()
    db_session.add(char)
    db_session.commit()
    for column, _ in _JSON_DEFAULT_FIELDS:
        _force_null_column(db_session, char.id, column)

    app.dependency_overrides[get_db] = lambda: db_session
    try:
        client = TestClient(app, raise_server_exceptions=False)
        resp = client.get("/api/characters")
        assert resp.status_code == 200, f"存量 NULL 行不应 500: {resp.status_code} {resp.text}"
        body = resp.json()[0]
        for column, default in _JSON_DEFAULT_FIELDS:
            assert body[column] == default, f"{column} 应归一为 {default!r}，实际 {body[column]!r}"
    finally:
        app.dependency_overrides.clear()


def test_update_explicit_null_coerces_to_default(db_session, make_character) -> None:
    """PUT 显式 null：list/dict JSON 字段 → 归一默认形态写库（不再产 NULL，响应不 500）"""
    from backend.app.main import app

    char = make_character()
    db_session.add(char)
    db_session.commit()

    app.dependency_overrides[get_db] = lambda: db_session
    try:
        client = TestClient(app, raise_server_exceptions=False)
        patch = {column: None for column, _ in _JSON_DEFAULT_FIELDS}
        patch["preset_dialogues"] = None
        resp = client.put(f"/api/characters/{char.id}", json=patch)
        assert resp.status_code == 200, f"显式 null 不应 500: {resp.status_code} {resp.text}"
        body = resp.json()
        for column, default in _JSON_DEFAULT_FIELDS:
            assert body[column] == default, f"{column} 应写库归一旦响应归一，实际 {body[column]!r}"
        assert body["preset_dialogues"] == []
    finally:
        app.dependency_overrides.clear()


def test_create_explicit_null_coerces_to_default(db_session) -> None:
    """POST 显式 null：list/dict JSON 字段归一默认形态（None 不入库契约，code-review 锁定）"""
    from backend.app.main import app

    app.dependency_overrides[get_db] = lambda: db_session
    try:
        client = TestClient(app, raise_server_exceptions=False)
        payload = {"name": "create-null-contract"}
        for column, _ in _JSON_DEFAULT_FIELDS:
            payload[column] = None
        payload["preset_dialogues"] = None
        resp = client.post("/api/characters", json=payload)
        assert resp.status_code == 201, f"显式 null 不应 422: {resp.status_code} {resp.text}"
        body = resp.json()
        for column, default in _JSON_DEFAULT_FIELDS + [("preset_dialogues", [])]:
            assert body[column] == default, f"{column} 应归一为 {default!r}，实际 {body[column]!r}"
    finally:
        app.dependency_overrides.clear()
