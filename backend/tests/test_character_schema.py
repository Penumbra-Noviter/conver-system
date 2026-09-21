"""preset_dialogues NULL 响应归一回归测试（冒烟 GET /api/characters 500 → 200）

存量库升级路径：characters.preset_dialogues 由自愈迁移补列（可空 JSON，无回填），
旧行值为 NULL；响应 schema 声明 list[PresetDialogue] 必填（default_factory 仅
在字段缺席时生效，显式 None 会验不过）→ FastAPI serialize_response 抛
ResponseValidationError → GET /api/characters 500（2026-09-21 桌面打包冒烟实测）。

修复：CharacterBase.preset_dialogues 增 mode="before" 验证器，None → []。
本测试锁定契约：NULL 行经 GET /api/characters 返回 200 且 preset_dialogues 归一为 []。
"""

from __future__ import annotations

from fastapi.testclient import TestClient
from sqlalchemy import text

from backend.app.database import get_db

__all__: list[str] = []


def _force_null_preset_dialogues(db_session, character_id: int) -> None:
    """模拟存量行：绕过 ORM default，直接把列置 NULL（自愈迁移补列后的旧库形态）"""
    db_session.execute(
        text("UPDATE characters SET preset_dialogues = NULL WHERE id = :id"),
        {"id": character_id},
    )
    db_session.commit()
    # 失效身份映射缓存，后续读取回库取真值（否则 ORM 对象持 stale [] 掩盖缺陷）
    db_session.expire_all()


def test_list_characters_serializes_null_preset_dialogues(db_session, make_character) -> None:
    """GET /api/characters：preset_dialogues 为 NULL 的存量行 → 200 且归一为 []（不 500）"""
    from backend.app.main import app

    char = make_character()
    db_session.add(char)
    db_session.commit()
    _force_null_preset_dialogues(db_session, char.id)

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
