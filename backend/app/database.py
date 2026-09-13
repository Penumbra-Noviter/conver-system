"""
Conver System — 数据库引擎与会话管理

SQLAlchemy 2.0 同步引擎配置（项目当前使用同步 ORM），基于 pydantic-settings。
"""

from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import Engine, create_engine, event
from sqlalchemy.engine import Connection
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from backend.app.config import settings

# ============================================================
# SQLite 同步引擎（项目当前使用同步 ORM 以减少异步复杂度）
# 后续如需高性能异步，可切换至 async 版本
# ============================================================

engine = create_engine(
    settings.DATABASE_URL.replace("+aiosqlite", ""),  # 移除异步驱动前缀
    connect_args={"check_same_thread": False},  # SQLite 多线程访问
    echo=False,  # 生产环境关掉 SQL 日志
)


# ── 启用 SQLite 外键约束 ──
# 默认 SQLite 不强制 FK，需 PRAGMA 开启以支持 ON DELETE CASCADE
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection: object, connection_record: object) -> None:
    """在每个新 SQLite 连接上开启外键约束。

    默认 SQLite 不强制外键，必须执行 ``PRAGMA foreign_keys=ON`` 后
    外键约束与 ON DELETE CASCADE 才会生效；挂在 connect 事件上，
    确保连接池取出的每条连接都已开启。
    """
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """ORM 基类，所有 Model 继承此基类"""
    pass


def get_db() -> Iterator[Session]:
    """FastAPI 依赖注入：获取数据库会话

    用法：
        @router.get("/items")
        def list_items(db: Session = Depends(get_db)):
            ...
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """创建所有表（如果不存在），并执行自愈迁移（MS-1：存量库补 messages.active_swipe_index；
    BR-1：存量库补 conversations 分支三列）"""
    import backend.app.models  # noqa: F401 — 确保模型被注册
    Base.metadata.create_all(bind=engine)
    _ensure_messages_active_swipe_index(engine)
    _ensure_conversation_branch_columns(engine)
    _ensure_cg_images_weight(engine)


def _ensure_column(
    bind: Engine | Connection, table: str, column_name: str, column_def: str, *, concurrent: bool = False,
) -> None:
    """通用自愈迁移原语：探测缺列 → 补列（幂等；concurrent 吞 duplicate column）

    三个 ``_ensure_*`` 迁移的公共原语。create_all 不会给已存在表加列（项目无
    alembic，spec §0 迁移约束）：列探测命中已存在 → 无事返回（幂等）；缺列 →
    追加 ``column_def`` 并提交。concurrent=True 时补列包 try/except OperationalError，
    命中 duplicate column 视为「他方已补齐」回滚吞错（列约束双方一致，无副作用），
    其余 OperationalError 原样上抛。

    Args:
        bind: Engine（借出连接并代管生命周期）或既有 Connection（直接复用，不代管）
        table: 目标表名
        column_name: 待补列名
        column_def: 列定义（含类型/默认值，如 "INTEGER NOT NULL DEFAULT 0"）
        concurrent: 是否并发安全（吞 duplicate column 竞态）
    """
    from sqlalchemy import text
    from sqlalchemy.exc import OperationalError

    if isinstance(bind, Engine):  # Engine → 借出连接；Connection → 直接复用（不代管生命周期）
        with bind.connect() as conn:
            return _ensure_column(
                conn, table, column_name, column_def, concurrent=concurrent
            )
    conn = bind
    columns = {
        row[1]
        for row in conn.execute(text(f"PRAGMA table_info({table})")).fetchall()
    }
    if column_name not in columns:
        try:
            conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column_name} {column_def}"))
            conn.commit()
        except OperationalError as exc:
            if not concurrent or "duplicate column" not in str(exc):
                raise
            conn.rollback()  # 竞态他方已补列 → 幂等无事


def _ensure_messages_active_swipe_index(bind=engine) -> None:
    """自愈迁移：存量 messages 表缺 active_swipe_index 列时补列（幂等，委托 _ensure_column）

    create_all 不会给已存在表加列（项目无 alembic，spec §0 迁移约束）：探测缺列 →
    补 INTEGER NOT NULL DEFAULT 0，已存在则无事。连续两次调用无副作用（幂等，
    契约锁 test_message_swipes::test_migration_idempotent）。

    Args:
        bind: 可连接的 Engine/Connection（默认应用引擎；测试可传入内存库）
    """
    _ensure_column(bind, "messages", "active_swipe_index", "INTEGER NOT NULL DEFAULT 0")


def _ensure_conversation_branch_columns(bind=engine) -> None:
    """自愈迁移：存量 conversations 表缺分支三列时补列（幂等，委托 _ensure_column）

    BR-1 分支元数据：parent_conversation_id（INTEGER，可空）/ branch_from_message_id
    （INTEGER，可空）/ branch_title（VARCHAR(200)，可空）。create_all 不会给已存在
    表加列（项目无 alembic，spec §0 迁移约束）：探测缺列 → 逐列补列；连续两次调用
    无副作用（幂等，契约锁 test_branch_snapshot::test_migration_adds_columns_idempotent）。

    Args:
        bind: 可连接的 Engine/Connection（默认应用引擎；测试可传入内存库）
    """
    for name, coltype in (
        ("parent_conversation_id", "INTEGER"),
        ("branch_from_message_id", "INTEGER"),
        ("branch_title", "VARCHAR(200)"),
    ):
        _ensure_column(bind, "conversations", name, coltype)


def _ensure_cg_images_weight(bind=engine) -> None:
    """自愈迁移：存量 cg_images 表缺 weight 列时补列（幂等，委托 _ensure_column 并发安全）

    T1 加权概率池地基：weight INTEGER NOT NULL DEFAULT 100（存量行统一补 100）。
    create_all 不会给已存在表加列（项目无 alembic，spec §0 迁移约束）：探测缺列 →
    补列，已存在则无事。连续两次调用无副作用（幂等，契约锁
    test_gallery::test_cg_weight_migration_on_legacy_db）。

    并发安全（Falsify 锁 test_gallery::test_cg_weight_migration_concurrent_no_duplicate_crash）：
    两连接竞态时后到者基于过期探测结果补列 → duplicate column，吞掉该错视为
    「他方已补齐」（列约束双方一致，无副作用）；其余 OperationalError 原样上抛。

    Args:
        bind: Engine 或既有 Connection（默认应用引擎；测试可直接传内存库连接）
    """
    _ensure_column(bind, "cg_images", "weight", "INTEGER NOT NULL DEFAULT 100", concurrent=True)
