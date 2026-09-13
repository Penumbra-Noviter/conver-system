"""
F-125（T4）自愈迁移原语 `_ensure_column` — 契约测试

锁定语义（吸收三个 `_ensure_*` 的公共原语 + `_ensure_cg_images_weight` 的并发安全）：
    1. 缺列补列 + 幂等（连续两次调用无副作用）
    2. 已存在列 no-op（探测命中即返回，不执行任何 ALTER）
    3. concurrent=True 时过期探测快照 → duplicate column 被吞不抛（竞态视为「他方已补齐」）
    4. ALTER 失败（非 duplicate column）→ 原样上抛（concurrent 只吞竞态 duplicate）
    5. Connection 双形态：直接传连接复用（不代管生命周期），补列后连接仍可用

依赖：pytest + SQLite 内存/临时文件库；本文件直测私有原语 `_ensure_column`（不进 `__all__`）。
"""

from __future__ import annotations

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError

from backend.app.database import _ensure_column

__all__: list[str] = []


class TestEnsureColumnPrimitive:
    """通用自愈原语 `_ensure_column` 的语义契约（Falsify 矩阵）"""

    def test_adds_missing_column_and_idempotent(self) -> None:
        """缺列补列 + 幂等：首次补列，二次调用无事（列仅一条、定义一致）"""
        engine = create_engine("sqlite://")
        with engine.connect() as conn:
            conn.execute(text("CREATE TABLE t (id INTEGER PRIMARY KEY)"))
            conn.commit()

        _ensure_column(engine, "t", "weight", "INTEGER NOT NULL DEFAULT 100")
        _ensure_column(engine, "t", "weight", "INTEGER NOT NULL DEFAULT 100")  # 幂等

        with engine.connect() as conn:
            info = conn.execute(text("PRAGMA table_info(t)")).fetchall()
            cols = {row[1]: row for row in info}
            assert "weight" in cols
            col = cols["weight"]
            # PRAGMA 列序：type=2, notnull=3, dflt=4
            assert col[2] == "INTEGER" and col[3] == 1 and col[4] == "100"

    def test_existing_column_noop(self) -> None:
        """已存在列 no-op：探测命中即返回，不执行任何 ALTER（代理在 ALTER 时抛错）"""
        engine = create_engine("sqlite://")
        with engine.connect() as conn:
            conn.execute(text("CREATE TABLE t (id INTEGER PRIMARY KEY, c INTEGER)"))
            conn.commit()

        class _NoAlterConn:
            """已存在列场景下，任何 ALTER 都被判为违规（探测命中即应返回）"""

            def __init__(self, real) -> None:
                self._real = real

            def execute(self, stmt, *args, **kwargs):
                assert "ALTER" not in str(stmt), "已存在列不应触发 ALTER"
                return self._real.execute(stmt, *args, **kwargs)

            def commit(self) -> None:
                self._real.commit()

            def rollback(self) -> None:
                self._real.rollback()

        with engine.connect() as conn:
            _ensure_column(_NoAlterConn(conn), "t", "c", "INTEGER", concurrent=True)

    def test_concurrent_swallows_duplicate_column(self, tmp_path) -> None:
        """并发竞态：过期探测快照 → ALTER 撞 duplicate column 被吞不抛（不得崩溃）"""
        engine = create_engine(f"sqlite:///{tmp_path / 'race.db'}")
        with engine.connect() as conn:
            conn.execute(text("CREATE TABLE t (id INTEGER PRIMARY KEY)"))
            conn.commit()

        conn1 = engine.connect()
        try:
            # 他方连接抢先补列并提交（竞态的「他方」半边，真实 DDL）
            conn1.execute(text("ALTER TABLE t ADD COLUMN c INTEGER NOT NULL DEFAULT 0"))
            conn1.commit()

            class _StaleProbeResult:
                """过期探测快照：PRAGMA table_info 返回空（看不见 c），其余透传"""

                def fetchall(self) -> list:
                    return []

            class _StaleProbeConn:
                """竞态窗口模拟：探测命中过期快照，ALTER 落在真实连接上（撞 duplicate）"""

                def __init__(self, real) -> None:
                    self._real = real

                def execute(self, stmt, *args, **kwargs):
                    result = self._real.execute(stmt, *args, **kwargs)
                    if "table_info" in str(stmt):
                        return _StaleProbeResult()
                    return result

                def commit(self) -> None:
                    self._real.commit()

                def rollback(self) -> None:
                    self._real.rollback()

            _ensure_column(
                _StaleProbeConn(conn1), "t", "c", "INTEGER NOT NULL DEFAULT 0", concurrent=True
            )  # 不得抛 duplicate column

            cols = {row[1] for row in conn1.execute(text("PRAGMA table_info(t)"))}
            assert "c" in cols
        finally:
            conn1.close()

    def test_non_duplicate_operational_error_raised(self, tmp_path) -> None:
        """ALTER 失败（非 duplicate column）→ 原样上抛（concurrent 只吞竞态 duplicate）"""
        engine = create_engine(f"sqlite:///{tmp_path / 'err.db'}")
        with engine.connect() as conn:
            conn.execute(text("CREATE TABLE t (id INTEGER PRIMARY KEY)"))
            conn.commit()

        class _RaisingAlterConn:
            """ALTER 时抛非 duplicate 的 OperationalError，其余透传"""

            def __init__(self, real) -> None:
                self._real = real

            def execute(self, stmt, *args, **kwargs):
                if "ALTER" in str(stmt):
                    raise OperationalError("no such table: t", None, None)
                return self._real.execute(stmt, *args, **kwargs)

            def commit(self) -> None:
                self._real.commit()

            def rollback(self) -> None:
                self._real.rollback()

        with engine.connect() as conn:
            with pytest.raises(OperationalError, match="no such table"):
                _ensure_column(_RaisingAlterConn(conn), "t", "c", "INTEGER", concurrent=True)

    def test_connection_reuse_form(self, tmp_path) -> None:
        """Connection 双形态：直接传连接复用（不代管生命周期），补列后连接仍可用"""
        engine = create_engine(f"sqlite:///{tmp_path / 'conn.db'}")
        with engine.connect() as conn:
            conn.execute(text("CREATE TABLE t (id INTEGER PRIMARY KEY)"))
            conn.commit()

        conn = engine.connect()
        try:
            _ensure_column(conn, "t", "c", "INTEGER")

            cols = {row[1] for row in conn.execute(text("PRAGMA table_info(t)"))}
            assert "c" in cols
            # 连接仍可用（未被原语关闭）
            assert conn.execute(text("SELECT count(*) FROM t")).scalar() == 0
        finally:
            conn.close()
