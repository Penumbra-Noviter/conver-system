"""
包导出冒烟测试 — services / schemas 的 `__all__` 清单覆盖实际模块名

覆盖：
    1. `from backend.app import services` / `from backend.app import schemas` 可导入
    2. `set(__all__)` 覆盖包内实际模块名（防清单漂移，新增模块未登记时即红）

依赖：pytest（纯元数据检查，不建库、不发网络请求）。
"""

from __future__ import annotations

import pkgutil

from backend.app import schemas, services

__all__: list[str] = []


def test_services_all_covers_actual_modules() -> None:
    """services.__all__ 必须覆盖 services 包内全部实际模块名"""
    actual = {m.name for m in pkgutil.iter_modules(services.__path__)}
    assert actual.issubset(set(services.__all__)), (
        f"services.__all__ 缺模块: {actual - set(services.__all__)}"
    )


def test_schemas_all_covers_actual_modules() -> None:
    """schemas.__all__ 必须覆盖 schemas 包内全部实际模块名"""
    actual = {m.name for m in pkgutil.iter_modules(schemas.__path__)}
    assert actual.issubset(set(schemas.__all__)), (
        f"schemas.__all__ 缺模块: {actual - set(schemas.__all__)}"
    )
