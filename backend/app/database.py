"""
Conver System — 数据库引擎与会话管理

SQLAlchemy 2.0 同步引擎配置（项目当前使用同步 ORM），基于 pydantic-settings。
"""

from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import create_engine, event
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
    """创建所有表（如果不存在）"""
    import backend.app.models  # noqa: F401 — 确保模型被注册
    Base.metadata.create_all(bind=engine)
