"""角色卡导入非 ASCII 头像 500 回归测试（B1，先红后绿）

缺陷路径：avatar 为非 ASCII 字符串时，_infer_mime 内 base64.b64decode
先做 ascii encode 校验，抛普通 ValueError（binascii.Error 之外），
既有 except 只捕 binascii.Error → 未处理异常 → POST /api/characters/import 500。

两层锁定真实缺陷路径（不 mock _infer_mime，不做「任意 500 消失」恒真断言）：
- 服务层：from_v2_card 直调，钉死 ValueError 分支 → 默认 png 容错行为契约
- API 层：POST /api/characters/import 全路径（TestClient over backend.app.main.app，
  先例 test_error_handler.py:297），断言 201 且库中可查得该角色
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from backend.app.database import get_db
from backend.app.services.character_card import from_v2_card

__all__: list[str] = []

# 非 ASCII 文本串：base64.b64decode 抛普通 ValueError 的最小输入（[:32] 切片后仍全非 ASCII）
_DIRTY_NON_ASCII_AVATAR = "中文头像数据不是base64"


def test_from_v2_non_ascii_avatar_defaults_png() -> None:
    """服务层机制钉死：非 ASCII avatar 走容错回退 png data URI，而非上抛 ValueError"""
    result = from_v2_card({"name": "脏头像角色", "avatar": _DIRTY_NON_ASCII_AVATAR})
    assert result.avatar == f"data:image/png;base64,{_DIRTY_NON_ASCII_AVATAR}"


def test_import_non_ascii_avatar_returns_201_and_persisted(db_session) -> None:
    """POST /api/characters/import 全路径：avatar 非 ASCII 文本串 → 201 且角色入库（不 500）

    raise_server_exceptions=False：未处理异常以字面 500 响应呈现（而非向测试上抛），
    使红态证据即工单所述的 500。
    """
    from backend.app.main import app

    card = {
        "spec": "chara_card_v2",
        "spec_version": "2.0",
        "data": {
            "name": "非ASCII头像回归",
            "description": "脏头像容忍回归测试",
            "avatar": _DIRTY_NON_ASCII_AVATAR,
        },
    }
    app.dependency_overrides[get_db] = lambda: db_session
    try:
        client = TestClient(app, raise_server_exceptions=False)  # 不进入 lifespan，避免真实数据目录副作用
        resp = client.post("/api/characters/import", json=card)
        assert resp.status_code == 201, (
            f"导入应成功而非服务端错误: {resp.status_code} {resp.text}"
        )
        body = resp.json()
        assert body["name"] == "非ASCII头像回归"

        # 库中可查得该角色（经同一路由回读）
        got = client.get(f"/api/characters/{body['id']}")
        assert got.status_code == 200
        assert got.json()["name"] == "非ASCII头像回归"
    finally:
        app.dependency_overrides.clear()
