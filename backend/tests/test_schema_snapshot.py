"""
D3 — schema 快照漂移检测（ARC-10 T-17）

快照即契约：backend/tests/fixtures/schema.sql 是迁移测试（test_migrate_data.py 的
_make_db）建表语句的单一来源。本测试用 ORM 元数据（Base.metadata.create_all →
sqlite DDL）生成真实建表语句集合，与快照语句集合比对——ORM 或快照任一漂移
（新列/改类型/新索引/丢表）都显式失败，杜绝测试替身静默失真（历史教训：手抄
17 列 vs 真实 ORM 19 列，缺 created_at/updated_at）。

G4 边界说明：纯 stdlib 承诺只罩 migrate_data 产品代码与其测试文件
（test_migrate_data.py）；本文件**允许** import 应用 ORM（D-D3-1），
否则无法生成契约真值。
"""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path

from sqlalchemy import create_engine, text

import backend.app.models  # noqa: F401 — 注册全部 ORM 模型（metadata 发现）
from backend.app.database import Base

__all__ = ["TestSchemaSnapshotDrift"]

#: 快照文件路径（backend/tests/fixtures/schema.sql）
SCHEMA_SNAPSHOT = Path(__file__).resolve().parent / "fixtures" / "schema.sql"

#: 导出用户建表/建索引语句的查询（排除 sqlite_* 内部表）
_USER_DDL_SQL = (
    "SELECT sql FROM sqlite_master "
    "WHERE type IN ('table', 'index') AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL"
)


def _normalize_ddl(sql: str) -> str:
    """归一化 DDL 语句：折叠空白（语义等价即可，忽略排版差异）"""
    return re.sub(r"\s+", " ", sql).strip()


def _user_ddl_statements(conn: sqlite3.Connection, sql: str) -> set[str]:
    """从连接导出用户建表/建索引语句集合（归一化后）

    sql 参数：sqlite3 原生连接传 str，SQLAlchemy 连接传 text() 包装。
    """
    rows = conn.execute(sql).fetchall()
    return {_normalize_ddl(row[0]) for row in rows}


def _orm_ddl_statements() -> set[str]:
    """ORM 元数据在内存 SQLite 上生成的真实建表语句集合（契约真值）"""
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with engine.connect() as conn:
        return _user_ddl_statements(conn, text(_USER_DDL_SQL))


def _snapshot_ddl_statements() -> set[str]:
    """快照文件执行后的语句集合（经 SQLite 同一 sqlite_master 通道归一）"""
    conn = sqlite3.connect(":memory:")
    try:
        conn.executescript(SCHEMA_SNAPSHOT.read_text(encoding="utf-8"))
        return _user_ddl_statements(conn, _USER_DDL_SQL)
    finally:
        conn.close()


class TestSchemaSnapshotDrift:
    """快照与 ORM 逐语句对齐：任何漂移显式失败（静默失真 → 显式失败）"""

    def test_snapshot_matches_orm_ddl(self) -> None:
        """ORM 真实 DDL 与快照语句集合一致；漂移时给出两侧差异明细"""
        orm_ddl = _orm_ddl_statements()
        snapshot_ddl = _snapshot_ddl_statements()
        assert snapshot_ddl == orm_ddl, (
            "schema.sql 快照与 ORM 定义漂移——快照即契约，请在核验 ORM 变更后同步更新"
            " backend/tests/fixtures/schema.sql（并跑全量迁移测试确认行为）。"
            f"\n  快照独有（ORM 已无）：{sorted(snapshot_ddl - orm_ddl)}"
            f"\n  ORM 独有（快照缺失/过期）：{sorted(orm_ddl - snapshot_ddl)}"
        )
