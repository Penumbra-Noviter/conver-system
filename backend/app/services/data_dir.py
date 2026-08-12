"""
数据目录共享模块（ARC9-T04 · 决策 D1-D1 / D1-D2，契约表 v2）

统一桌面版数据目录解析，供后端启动器（run_backend.data_dir）、迁移脚本
（migrate_data.default_target_path）与壳侧（src-tauri/server.rs，Rust 镜像实现）
三方共用同一契约：

    1. `CONVER_DATA_DIR`（环境变量，**非空串才生效**，空串视为未设置）——值即数据目录；
    2. `%APPDATA%\\ConverSystem`（默认）；
    3. `home\\AppData\\Roaming\\ConverSystem`（APPDATA 缺失兜底，决策 D1-D2）。

契约表 v2 全文见 `backend/tests/test_data_dir.py` 模块 docstring（双端镜像，
Rust 侧 `src-tauri/tests/server_test.rs` 互引同一版本号）；URL 编码（壳侧
`database_url`）编码集 = {`?` → `%3F`}，其余字符（含空格/中文/`#`/`%`）一律
原样保留（`?` 是 SQLAlchemy URL 解析器的唯一实际分隔符，防御性编码）；Python
侧不做编码——resolve 返回的 Path 必须与用户给定值**非分隔符字符**逐字符一致
（空格/中文/`#`/`%` 等一律原样）；**仅分隔符按 pathlib 规范化**——重复分隔符
折叠（`//` → `/`）、`.` 段消除、尾分隔符去除；`..` 段原样保留，由文件系统在
访问时解析。**UNC 前导特例（TD-16）**：`Path('//server/share/x')` 保留 UNC
前缀**不折叠**（Windows；实测背书：`parts == ('\\\\server\\share\\', 'x')`）——
折叠只作用于路径分段内部，不作用于盘符/UNC 前导。

G4 约束：本模块**仅允许 stdlib import**（导入链已核实无副作用：
`backend/app/__init__.py` 为空包、`backend/app/services/__init__.py` 为纯
`__all__` manifest、`backend/` 为 PEP 420 namespace package）——迁移脚本依赖
本模块不引入任何 app 业务代码。
"""

from __future__ import annotations

import os
from pathlib import Path

__all__ = [
    "DATA_DIR_ENV",
    "DATA_DIR_NAME",
    "DB_FILE",
    "data_dir",
    "data_dir_file",
    "database_path",
]

#: 数据目录环境变量名（值即数据目录；空串视为未设置）
DATA_DIR_ENV = "CONVER_DATA_DIR"
#: %APPDATA% 之下的数据目录名（与壳侧 src-tauri/src/server.rs 的 DATA_DIR_NAME 一致）
DATA_DIR_NAME = "ConverSystem"
#: 数据库文件名（与壳侧 src-tauri/src/server.rs 的 DB_FILE 一致）
DB_FILE = "conver_system.db"


def data_dir() -> Path:
    """桌面版数据目录（契约表 v2）：CONVER_DATA_DIR（非空）→ %APPDATA%\\ConverSystem → home\\AppData\\Roaming\\ConverSystem。

    与迁移脚本 `default_target_path` / 壳侧 `default_data_dir` 同一契约（契约表 v2，
    见本模块 docstring）；APPDATA 缺失时兜底 home\\AppData\\Roaming（决策 D1-D2），
    与迁移脚本既有语义一致。
    """
    if override := os.environ.get(DATA_DIR_ENV):
        return Path(override)
    base = os.environ.get("APPDATA") or (Path.home() / "AppData" / "Roaming")
    return Path(base) / DATA_DIR_NAME


def data_dir_file(file_name: str) -> Path:
    """数据目录下指定文件的路径（如日志 / 数据库 / runtime.json）。"""
    return data_dir() / file_name


def database_path() -> Path:
    """数据目录下数据库文件的路径（%DATA_DIR%\\conver_system.db）。"""
    return data_dir_file(DB_FILE)
