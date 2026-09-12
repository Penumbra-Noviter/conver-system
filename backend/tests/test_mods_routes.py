"""
Mod 库与挂载 CRUD 路由契约锁（MD-2 / 01 后端）

覆盖（镜像 test_lorebook_routes.py 形态：真实路由 + 统一异常处理器的最小应用，
get_db 覆盖为内存会话）：
    GET    /api/mods                             → 空库 [] / id 升序
    POST   /api/mods                             → 创建（prompt 区），422 校验
    PUT    /api/mods/{mod_id}                    → 部分更新；不存在 → 404
    DELETE /api/mods/{mod_id}                    → 204；不存在 → 404
    GET    /api/characters/{character_id}/mods   → 挂载列表（sort_order 升序）
    POST   /api/characters/{character_id}/mods   → 挂载；角色不存在 → 404；重复 → 400
    PUT    /api/mod-bindings/{binding_id}        → 切换 enabled；不存在 → 404
    PUT    /api/mod-bindings/{binding_id}/sort   → 调整 sort_order；不存在 → 404
    DELETE /api/mod-bindings/{binding_id}        → 204；不存在 → 404
    PUT    /api/characters/{character_id}/mods/order → 原子批量重排；空列表 400 /
    归属不符 404 / 缺失 404 / 角色不存在 404 / 重复或非法 body 422
"""

from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from backend.app.api.errors import domain_error_handler
from backend.app.api.routes import mods as mods_route
from backend.app.database import get_db
from backend.app.schemas.mods import ModCreate
from backend.app.services import mods as mods_service
from backend.app.services.exceptions import DomainError

__all__: list[str] = []


@pytest.fixture
def wire_app(db_session: Session) -> FastAPI:
    """真实路由 + 统一 handler 的最小应用（get_db 覆盖为内存会话）"""
    app = FastAPI()
    app.add_exception_handler(DomainError, domain_error_handler)
    app.include_router(mods_route.router)
    app.dependency_overrides[get_db] = lambda: db_session
    return app


def _create_character(db_session: Session, name: str = "Mod 路由角色") -> int:
    """落库角色，返回 id"""
    from backend.app.models.character import Character

    char = Character(name=name, personality="测试人格", first_mes="")
    db_session.add(char)
    db_session.commit()
    db_session.refresh(char)
    return char.id


def _create_mod(db_session: Session, *, name: str = "测试 Mod", target_area: str = "prompt") -> int:
    """落库 Mod，返回 id"""
    mod = mods_service.create_mod(db_session, ModCreate(name=name, target_area=target_area))
    return mod.id


# ── 1. Mod 库 CRUD ──


def test_list_mods_empty(db_session: Session, wire_app: FastAPI) -> None:
    """空库 → 200 与 []"""
    with TestClient(wire_app) as client:
        resp = client.get("/api/mods")
    assert resp.status_code == 200
    assert resp.json() == []


def test_create_mod_and_list(db_session: Session, wire_app: FastAPI) -> None:
    """创建 prompt 区 Mod → 响应含 id/target_area；随后 GET 列表含该条"""
    with TestClient(wire_app) as client:
        created = client.post(
            "/api/mods", json={"name": "提示词 Mod", "target_area": "prompt", "payload": "w"}
        )
    assert created.status_code == 200
    body = created.json()
    assert body["id"] is not None
    assert body["target_area"] == "prompt"
    assert body["name"] == "提示词 Mod"

    with TestClient(wire_app) as client:
        listed = client.get("/api/mods")
    assert listed.status_code == 200
    items = listed.json()
    assert len(items) == 1
    assert items[0]["id"] == body["id"]


def test_list_mods_id_asc(db_session: Session, wire_app: FastAPI) -> None:
    """列表按 id 升序（确定性）"""
    with TestClient(wire_app) as client:
        client.post("/api/mods", json={"name": "A"})
        client.post("/api/mods", json={"name": "B"})
        listed = client.get("/api/mods")
    names = [m["name"] for m in listed.json()]
    assert names == ["A", "B"]


def test_update_mod_partial(db_session: Session, wire_app: FastAPI) -> None:
    """部分更新：仅改提交字段（target_area 变、payload 原样）"""
    mod_id = _create_mod(db_session, name="原名")
    with TestClient(wire_app) as client:
        resp = client.put(f"/api/mods/{mod_id}", json={"target_area": "css"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["target_area"] == "css"
    assert body["payload"] == ""  # 原样保留
    assert body["name"] == "原名"  # 未提交字段不动


def test_update_mod_not_found(db_session: Session, wire_app: FastAPI) -> None:
    """更新不存在的 Mod → 404"""
    with TestClient(wire_app) as client:
        resp = client.put("/api/mods/99999", json={"target_area": "css"})
    assert resp.status_code == 404


def test_delete_mod(db_session: Session, wire_app: FastAPI) -> None:
    """删除 → 204 且列表移除；不存在 → 404"""
    mod_id = _create_mod(db_session)
    with TestClient(wire_app) as client:
        resp = client.delete(f"/api/mods/{mod_id}")
        assert resp.status_code == 204
        assert client.get("/api/mods").json() == []
        assert client.delete("/api/mods/99999").status_code == 404


# ── 2. 角色挂载 CRUD ──


def test_bind_and_list_character_mods(db_session: Session, wire_app: FastAPI) -> None:
    """挂载 → 响应含 character_id/mod_id/enabled/sort_order；列表 sort_order 升序"""
    char_id = _create_character(db_session)
    m1 = _create_mod(db_session, name="M1")
    m2 = _create_mod(db_session, name="M2")

    with TestClient(wire_app) as client:
        b1 = client.post(f"/api/characters/{char_id}/mods", json={"mod_id": m1, "sort_order": 1})
        b2 = client.post(f"/api/characters/{char_id}/mods", json={"mod_id": m2, "sort_order": 0})

    assert b1.status_code == 200
    body = b1.json()
    assert body["character_id"] == char_id
    assert body["mod_id"] == m1
    assert body["enabled"] is True
    assert body["sort_order"] == 1
    assert b2.json()["sort_order"] == 0

    with TestClient(wire_app) as client:
        listed = client.get(f"/api/characters/{char_id}/mods")
    assert listed.status_code == 200
    items = listed.json()
    # sort_order 升序：0 (M2) 在前，1 (M1) 在后
    assert [item["mod_id"] for item in items] == [m2, m1]
    assert [item["sort_order"] for item in items] == [0, 1]


def test_update_binding_enabled_and_sort(db_session: Session, wire_app: FastAPI) -> None:
    """切开关 / 调排序 → 更新生效；不存在 → 404"""
    char_id = _create_character(db_session)
    mod_id = _create_mod(db_session)
    binding = mods_service.bind_mod(db_session, char_id, mod_id)

    with TestClient(wire_app) as client:
        off = client.put(f"/api/mod-bindings/{binding.id}", json={"enabled": False})
        assert off.status_code == 200
        assert off.json()["enabled"] is False

        sort = client.put(f"/api/mod-bindings/{binding.id}/sort", json={"sort_order": 7})
        assert sort.status_code == 200
        assert sort.json()["sort_order"] == 7

        assert client.put("/api/mod-bindings/99999", json={"enabled": True}).status_code == 404
        assert client.put("/api/mod-bindings/99999/sort", json={"sort_order": 0}).status_code == 404


def test_delete_binding(db_session: Session, wire_app: FastAPI) -> None:
    """解绑 → 204 且列表移除；不存在 → 404"""
    char_id = _create_character(db_session)
    mod_id = _create_mod(db_session)
    binding = mods_service.bind_mod(db_session, char_id, mod_id)

    with TestClient(wire_app) as client:
        resp = client.delete(f"/api/mod-bindings/{binding.id}")
        assert resp.status_code == 204
        assert client.get(f"/api/characters/{char_id}/mods").json() == []
        assert client.delete("/api/mod-bindings/99999").status_code == 404


# ── 3. 守卫与校验 ──


def test_guards_and_validation(db_session: Session, wire_app: FastAPI) -> None:
    """角色不存在挂载 → 404；非法请求体（target_area 越 Literal）→ 422"""
    mod_id = _create_mod(db_session)
    with TestClient(wire_app) as client:
        assert client.post("/api/characters/99999/mods", json={"mod_id": mod_id}).status_code == 404
        bad = client.post("/api/mods", json={"name": "x", "target_area": "invalid"})
        assert bad.status_code == 422


def test_duplicate_bind_conflict(db_session: Session, wire_app: FastAPI) -> None:
    """同角色同 Mod 重复挂载 → 400（ModAlreadyBoundError）"""
    char_id = _create_character(db_session)
    mod_id = _create_mod(db_session)
    with TestClient(wire_app) as client:
        first = client.post(f"/api/characters/{char_id}/mods", json={"mod_id": mod_id})
        assert first.status_code == 200
        dup = client.post(f"/api/characters/{char_id}/mods", json={"mod_id": mod_id})
        assert dup.status_code == 400


def test_sort_order_bounds(db_session: Session, wire_app: FastAPI) -> None:
    """sort_order 越界（超 2^63 / 负数 / >9999）→ 422 而非 500（F1 修复锁：防 SQLite OverflowError）"""
    char_id = _create_character(db_session)
    mod_id = _create_mod(db_session)

    with TestClient(wire_app) as client:
        # 挂载 body sort_order 超 64 位 → 422（F1：否则 db.commit 抛 OverflowError → 500）
        huge = client.post(
            f"/api/characters/{char_id}/mods", json={"mod_id": mod_id, "sort_order": 10**25}
        )
        assert huge.status_code == 422

        # 正常挂载后，sort 端点超界 / 负数 → 422
        ok = client.post(f"/api/characters/{char_id}/mods", json={"mod_id": mod_id})
        assert ok.status_code == 200
        binding_id = ok.json()["id"]
        sort_huge = client.put(
            f"/api/mod-bindings/{binding_id}/sort", json={"sort_order": 10**25}
        )
        assert sort_huge.status_code == 422
        sort_neg = client.put(
            f"/api/mod-bindings/{binding_id}/sort", json={"sort_order": -1}
        )
        assert sort_neg.status_code == 422


# ── 4. 原子批量重排 PUT /api/characters/{id}/mods/order（F-102 后端）──


def test_reorder_mods_persists_new_order(db_session: Session, wire_app: FastAPI) -> None:
    """提交 [binding_id...] → sort_order=0,1,2 持久化，GET 列表返回新序"""
    char_id = _create_character(db_session)
    m1 = _create_mod(db_session, name="M1")
    m2 = _create_mod(db_session, name="M2")
    m3 = _create_mod(db_session, name="M3")
    b1 = mods_service.bind_mod(db_session, char_id, m1)
    b2 = mods_service.bind_mod(db_session, char_id, m2)
    b3 = mods_service.bind_mod(db_session, char_id, m3)

    with TestClient(wire_app) as client:
        resp = client.put(
            f"/api/characters/{char_id}/mods/order", json=[b3.id, b1.id, b2.id]
        )

    assert resp.status_code == 200
    body = resp.json()
    assert [item["mod_id"] for item in body] == [m3, m1, m2]
    assert [item["sort_order"] for item in body] == [0, 1, 2]

    with TestClient(wire_app) as client:
        listed = client.get(f"/api/characters/{char_id}/mods")
    assert [item["mod_id"] for item in listed.json()] == [m3, m1, m2]


def test_reorder_foreign_binding_rejected_atomically(
    db_session: Session, wire_app: FastAPI
) -> None:
    """混入他角色 binding_id → 404 且原顺序零改动（单事务原子）"""
    char_id = _create_character(db_session)
    other_id = _create_character(db_session, name="另一角色")
    m1 = _create_mod(db_session, name="M1")
    m2 = _create_mod(db_session, name="M2")
    b1 = mods_service.bind_mod(db_session, char_id, m1)
    mods_service.bind_mod(db_session, char_id, m2)
    foreign = mods_service.bind_mod(db_session, other_id, m1)

    with TestClient(wire_app) as client:
        resp = client.put(
            f"/api/characters/{char_id}/mods/order", json=[b1.id, foreign.id]
        )
        assert resp.status_code == 404
        listed = client.get(f"/api/characters/{char_id}/mods")
    assert [item["mod_id"] for item in listed.json()] == [m1, m2]


def test_reorder_character_not_found(db_session: Session, wire_app: FastAPI) -> None:
    """角色不存在 → 404"""
    with TestClient(wire_app) as client:
        resp = client.put("/api/characters/99999/mods/order", json=[1])
    assert resp.status_code == 404


def test_reorder_missing_binding(db_session: Session, wire_app: FastAPI) -> None:
    """引用不存在的 binding_id → 404 无部分写入"""
    char_id = _create_character(db_session)
    m1 = _create_mod(db_session, name="M1")
    b1 = mods_service.bind_mod(db_session, char_id, m1)

    with TestClient(wire_app) as client:
        resp = client.put(f"/api/characters/{char_id}/mods/order", json=[b1.id, 99999])
        assert resp.status_code == 404


def test_reorder_empty_list_rejected(db_session: Session, wire_app: FastAPI) -> None:
    """空列表 → 400 明确拒绝（避免误清空）"""
    char_id = _create_character(db_session)
    m1 = _create_mod(db_session, name="M1")
    mods_service.bind_mod(db_session, char_id, m1)

    with TestClient(wire_app) as client:
        resp = client.put(f"/api/characters/{char_id}/mods/order", json=[])
    assert resp.status_code == 400


def test_reorder_incomplete_coverage_rejected(
    db_session: Session, wire_app: FastAPI
) -> None:
    """缺失某绑定（未恰好覆盖）→ 400 且无部分写入"""
    char_id = _create_character(db_session)
    m1 = _create_mod(db_session, name="M1")
    m2 = _create_mod(db_session, name="M2")
    b1 = mods_service.bind_mod(db_session, char_id, m1)
    mods_service.bind_mod(db_session, char_id, m2)

    with TestClient(wire_app) as client:
        resp = client.put(f"/api/characters/{char_id}/mods/order", json=[b1.id])
        assert resp.status_code == 400
        listed = client.get(f"/api/characters/{char_id}/mods")
    assert [item["mod_id"] for item in listed.json()] == [m1, m2]


def test_reorder_duplicate_and_invalid_body(db_session: Session, wire_app: FastAPI) -> None:
    """重复 binding_id / 非数组 / 含非整数 → 422"""
    char_id = _create_character(db_session)
    m1 = _create_mod(db_session, name="M1")
    m2 = _create_mod(db_session, name="M2")
    b1 = mods_service.bind_mod(db_session, char_id, m1)
    mods_service.bind_mod(db_session, char_id, m2)

    with TestClient(wire_app) as client:
        base = f"/api/characters/{char_id}/mods/order"
        assert client.put(base, json=[b1.id, b1.id]).status_code == 422
        assert client.put(base, json={"a": 1}).status_code == 422
        assert client.put(base, json=[b1.id, "x"]).status_code == 422
