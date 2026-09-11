"""
世界书 CRUD 路由契约锁（WL-4 后端）

覆盖：
    GET    /api/characters/{id}/lorebook           → 列表（LorebookEntryResponse）
    POST   /api/characters/{id}/lorebook           → 创建（422 校验错误）
    PUT    /api/lorebook/{entry_id}                → 部分更新
    DELETE /api/lorebook/{entry_id}                → 204
    守卫：角色/条目不存在 → 404（统一异常处理器映射）；非法请求体 → 422
"""

from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.api.errors import domain_error_handler
from backend.app.api.routes import lorebook as lorebook_route
from backend.app.database import get_db
from backend.app.schemas.lorebook import LorebookEntryCreate
from backend.app.services import lorebook as lorebook_service
from backend.app.services.exceptions import DomainError

__all__: list[str] = []


@pytest.fixture
def wire_app(db_session) -> FastAPI:
    """真实路由 + 统一 handler 的最小应用（get_db 覆盖为内存会话）"""
    app = FastAPI()
    app.add_exception_handler(DomainError, domain_error_handler)
    app.include_router(lorebook_route.router)
    app.dependency_overrides[get_db] = lambda: db_session
    return app


def _create_character(db_session, name: str = "世界书角色") -> int:
    """落库角色（无 greeting），返回 id"""
    from backend.app.models.character import Character

    char = Character(name=name, personality="测试人格", first_mes="")
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char.id


def test_list_lorebook_empty(db_session, wire_app) -> None:
    """空世界书 → 空列表（200）"""
    char_id = _create_character(db_session)
    with TestClient(wire_app) as client:
        resp = client.get(f"/api/characters/{char_id}/lorebook")
    assert resp.status_code == 200
    assert resp.json() == []


def test_create_and_list_lorebook(db_session, wire_app) -> None:
    """创建条目 → 列表含该条目（字段往返一致）"""
    char_id = _create_character(db_session)
    payload = {
        "title": "酒馆",
        "keys": ["酒馆", "tavern"],
        "content": "酒馆的老板是莉莉。",
        "position": "world",
        "order": 50,
        "probability": 80,
        "depth": 10,
    }
    with TestClient(wire_app) as client:
        created = client.post(f"/api/characters/{char_id}/lorebook", json=payload)
        assert created.status_code == 200
        body = created.json()
        assert body["title"] == "酒馆"
        assert body["keys"] == ["酒馆", "tavern"]
        assert body["character_id"] == char_id

        listed = client.get(f"/api/characters/{char_id}/lorebook")
        assert listed.status_code == 200
        items = listed.json()
        assert len(items) == 1
        assert items[0]["id"] == body["id"]
        assert items[0]["keys"] == ["酒馆", "tavern"]


def test_update_lorebook_partial(db_session, wire_app) -> None:
    """部分更新：仅改提交字段，其余保留"""
    char_id = _create_character(db_session)
    entry = lorebook_service.create_entry(
        db_session, char_id, LorebookEntryCreate(title="旧", content="内容", order=5, keys=["x"])
    )
    with TestClient(wire_app) as client:
        resp = client.put(f"/api/lorebook/{entry.id}", json={"content": "新内容", "enabled": False})
    assert resp.status_code == 200
    body = resp.json()
    assert body["content"] == "新内容"
    assert body["enabled"] is False
    assert body["title"] == "旧"
    assert body["order"] == 5


def test_delete_lorebook(db_session, wire_app) -> None:
    """删除 → 204；列表为空"""
    char_id = _create_character(db_session)
    entry = lorebook_service.create_entry(db_session, char_id, LorebookEntryCreate(title="待删"))
    with TestClient(wire_app) as client:
        resp = client.delete(f"/api/lorebook/{entry.id}")
        assert resp.status_code == 204
        assert lorebook_service.list_entries(db_session, char_id) == []


def test_lorebook_guards(db_session, wire_app) -> None:
    """守卫：角色不存在 → 404；条目不存在 → 404；keys 非数组 → 422"""
    char_id = _create_character(db_session)
    entry = lorebook_service.create_entry(db_session, char_id, LorebookEntryCreate(title="t"))
    with TestClient(wire_app) as client:
        assert client.get("/api/characters/99999/lorebook").status_code == 404
        assert client.put("/api/lorebook/99999", json={"title": "x"}).status_code == 404
        assert client.delete("/api/lorebook/99999").status_code == 404
        bad = client.post(
            f"/api/characters/{char_id}/lorebook", json={"keys": "非数组", "content": "c"}
        )
        assert bad.status_code == 422
        assert client.put(f"/api/lorebook/{entry.id}", json={"order": 99999}).status_code == 422
