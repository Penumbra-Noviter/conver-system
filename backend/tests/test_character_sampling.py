"""
SP-1 采样参数扩展 — 契约锁测试

锁的内容：
1. 自愈迁移幂等：`_ensure_character_sampling_columns` 连续两次调用无副作用
2. 角色卡往返保真：采样参数（top_p / presence_penalty / frequency_penalty /
   max_tokens）经 to_v2_card → from_v2_card 还原（非 None 写 conver_system 命名空间，
   None 不落卡）
3. 采样参数裁剪：非法/越界值回退 None 或夹到合法区间
"""

from __future__ import annotations

from sqlalchemy import create_engine, text

from backend.app.services.character_card import from_v2_card, to_v2_card

__all__: list[str] = []


def test_migration_idempotent() -> None:
    """自愈迁移：缺采样四列时补列，连续两次调用无副作用"""
    from backend.app.database import _ensure_character_sampling_columns

    engine = create_engine("sqlite://")
    # 旧 schema 的 characters 表（缺采样四列）
    with engine.connect() as conn:
        conn.execute(text(
            "CREATE TABLE characters ("
            "id INTEGER NOT NULL PRIMARY KEY, "
            "name VARCHAR(100) NOT NULL, "
            "temperature FLOAT)"
        ))
        conn.commit()

    _ensure_character_sampling_columns(engine)  # 首次补列
    _ensure_character_sampling_columns(engine)  # 幂等：再跑无事

    with engine.connect() as conn:
        cols = {row[1] for row in conn.execute(text("PRAGMA table_info(characters)"))}
    for col in ("top_p", "presence_penalty", "frequency_penalty", "max_tokens"):
        assert col in cols, f"缺采样列 {col}"


def test_roundtrip_sampling_params(make_character) -> None:
    """往返保真：设置采样参数 → 导出 → 导入逐字段还原"""
    char = make_character(
        top_p=0.9, presence_penalty=0.5, frequency_penalty=-0.3, max_tokens=4096,
    )
    restored = from_v2_card(to_v2_card(char))
    assert restored.top_p == 0.9
    assert restored.presence_penalty == 0.5
    assert restored.frequency_penalty == -0.3
    assert restored.max_tokens == 4096


def test_roundtrip_none_sampling_params(make_character) -> None:
    """None 采样参数不落卡（conver_system 命名空间不写入），导入回读为 None"""
    char = make_character()  # 采样参数全 None
    ns = to_v2_card(char)["data"]["extensions"]["conver_system"]
    assert "top_p" not in ns
    assert "presence_penalty" not in ns
    assert "frequency_penalty" not in ns
    assert "max_tokens" not in ns

    restored = from_v2_card(to_v2_card(char))
    assert restored.top_p is None
    assert restored.presence_penalty is None
    assert restored.frequency_penalty is None
    assert restored.max_tokens is None


def test_clamp_sampling_params() -> None:
    """裁剪：越界值夹到合法区间，非法值回退 None"""
    assert from_v2_card({"name": "x", "top_p": 5.0}).top_p == 1.0
    assert from_v2_card({"name": "x", "top_p": -1.0}).top_p == 0.0
    assert from_v2_card({"name": "x", "presence_penalty": -99}).presence_penalty == -2.0
    assert from_v2_card({"name": "x", "frequency_penalty": 99}).frequency_penalty == 2.0
    assert from_v2_card({"name": "x", "max_tokens": 0}).max_tokens == 1
    assert from_v2_card({"name": "x", "max_tokens": 999999}).max_tokens == 131072
    # 非法值（字符串脏数据）回退 None（不覆盖 provider 默认）
    assert from_v2_card({"name": "x", "top_p": "abc"}).top_p is None
    assert from_v2_card({"name": "x", "max_tokens": "abc"}).max_tokens is None
