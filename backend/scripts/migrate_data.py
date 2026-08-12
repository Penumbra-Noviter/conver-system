"""
Conver System 数据迁移脚本（P6.4-3）

把网页版根目录数据库（默认 ./conver_system.db）迁移到桌面版数据目录
（默认 %APPDATA%\\ConverSystem\\conver_system.db，可用 CONVER_DATA_DIR 环境变量覆盖数据目录）。

铁律（知识库「打包覆盖丢数据」经验）：
    1. 复制非移动 —— 源数据库原样保留，绝不删除；
    2. 完成标记 —— 迁移完成且验证通过后，在目标目录写 .migrated 标记；
    3. 幂等 —— 目标已带完成标记则跳过，可重复运行；
    4. 防覆盖 —— 目标已存在同健康数据时跳过；数据不一致时须 --force 才覆盖。

独立命令行工具，不进产品 UI。运行方式（二选一）：
    python -m backend.scripts.migrate_data [--source ...] [--target ...] [--force]
    python backend/scripts/migrate_data.py [--source ...] [--target ...] [--force]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

if __package__ in (None, ""):
    # 直执行形态（python backend/scripts/migrate_data.py）：仓库根不在 sys.path，
    # 手工加入使 backend.app.services.data_dir（纯 stdlib 共享模块）可导入；
    # python -m backend.scripts.migrate_data 形态由解释器把 cwd 置入 sys.path，无需此处处理。
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

__all__ = [
    "MigrationError",
    "MARKER_NAME",
    "LOCK_NAME",
    "CORE_TABLES",
    "default_source_path",
    "default_target_path",
    "marker_path_for",
    "verify_database",
    "databases_equivalent",
    "check_source",
    "migrate",
    "main",
]

#: 完成标记文件名（位于目标数据库同目录，存在即视为已完成迁移）
MARKER_NAME = ".migrated"
#: 并发锁文件名（迁移期间持有，防止多进程同时写目标）
LOCK_NAME = ".migrate.lock"
#: Conver System 核心表（源/目标库必须齐全才视为健康）
CORE_TABLES = ("characters", "conversations", "messages", "settings")


class MigrationError(Exception):
    """迁移失败异常，message 面向用户（中文），由 main 捕获后非零退出"""


# ── 默认路径 ──


def default_source_path() -> Path:
    """默认源数据库路径：当前工作目录下 conver_system.db（网页版根目录）"""
    return Path.cwd() / "conver_system.db"


def default_target_path() -> Path:
    """默认目标数据库路径：%APPDATA%\\ConverSystem\\conver_system.db

    委托 `backend.app.services.data_dir.database_path`（同一契约，契约表 v2）：
    覆盖链 `CONVER_DATA_DIR`（非空）→ `%APPDATA%` → `home\\AppData\\Roaming`，
    均拼 `ConverSystem` 子目录（决策 D1-D2；本函数原兜底语义即契约默认）。
    契约表 v2 全文见 backend/tests/test_data_dir.py；壳侧 Rust 镜像实现见
    src-tauri/src/server.rs `default_data_dir`。
    """
    from backend.app.services.data_dir import database_path

    return database_path()


def marker_path_for(target: Path) -> Path:
    """完成标记路径：目标数据库同目录下的 .migrated"""
    return target.parent / MARKER_NAME


# ── 数据库校验与比对 ──


def _open_readonly(path: Path) -> sqlite3.Connection:
    """以只读模式打开 SQLite 数据库（mode=ro，绝不创建或修改文件）

    路径经 URI 百分号编码，兼容空格、中文、#、? 等特殊字符。
    """
    uri = "file:" + quote(str(path.resolve()).replace("\\", "/"), safe="/:") + "?mode=ro"
    return sqlite3.connect(uri, uri=True)


def _list_user_tables(conn: sqlite3.Connection) -> list[str]:
    """列出用户数据表（排除 sqlite_* 内部表）"""
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    ).fetchall()
    return [r[0] for r in rows]


def verify_database(path: Path) -> list[str]:
    """校验 SQLite 数据库完整性，返回问题列表（空列表 = 健康）

    校验项：PRAGMA integrity_check、存在用户数据表、核心表齐全。
    """
    problems: list[str] = []
    try:
        conn = _open_readonly(path)
    except sqlite3.Error as exc:
        return [f"无法作为 SQLite 数据库打开：{exc}"]
    try:
        try:
            row = conn.execute("PRAGMA integrity_check").fetchone()
        except sqlite3.Error as exc:
            problems.append(f"完整性检查失败（数据库可能损坏）：{exc}")
        else:
            if row is None or row[0] != "ok":
                problems.append(f"完整性检查未通过：{row}")
        tables = _list_user_tables(conn)
        if not tables:
            problems.append("未发现任何数据表（空数据库）")
        missing = [t for t in CORE_TABLES if t not in tables]
        if missing:
            problems.append(f"缺少核心表：{', '.join(missing)}")
    except sqlite3.Error as exc:
        problems.append(f"读取数据库结构失败：{exc}")
    finally:
        conn.close()
    return problems


def databases_equivalent(left: Path, right: Path) -> tuple[bool, str]:
    """逐表逐行比对两个数据库是否一致（表集合 + 每表行数据）

    Returns:
        (是否一致, 不一致原因；一致时原因为空字符串)
    """
    try:
        conn_left = _open_readonly(left)
        conn_right = _open_readonly(right)
    except sqlite3.Error as exc:
        return False, f"无法打开数据库进行比对：{exc}"
    try:
        tables_left = _list_user_tables(conn_left)
        tables_right = _list_user_tables(conn_right)
        if tables_left != tables_right:
            return False, f"表结构不一致：{tables_left} != {tables_right}"
        for table in tables_left:
            rows_left = conn_left.execute(
                f'SELECT * FROM "{table}" ORDER BY rowid'
            ).fetchall()
            rows_right = conn_right.execute(
                f'SELECT * FROM "{table}" ORDER BY rowid'
            ).fetchall()
            if rows_left != rows_right:
                return False, f"表 {table} 数据不一致"
        return True, ""
    except sqlite3.Error as exc:
        return False, f"比对数据失败：{exc}"
    finally:
        conn_left.close()
        conn_right.close()


def check_source(source: Path) -> None:
    """校验源数据库可用（存在、是文件、完整性健康、含核心表），不通过抛 MigrationError"""
    if not source.exists():
        raise MigrationError(f"源数据库不存在：{source}")
    if source.is_dir():
        raise MigrationError(f"源路径是目录而非数据库文件：{source}")
    problems = verify_database(source)
    if problems:
        raise MigrationError("源数据库不可用：" + "；".join(problems))


# ── 标记写入 ──


def _write_marker(marker: Path, source: Path, target: Path) -> None:
    """原子写入完成标记（临时文件 + os.replace）"""
    payload = {
        "source": str(source),
        "target": str(target),
        "migrated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "integrity": "ok",
    }
    tmp = marker.with_name(marker.name + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, marker)


def _write_marker_safe(marker: Path, source: Path, target: Path) -> None:
    """写完成标记，失败时给出可自愈的错误提示（数据已就位，重跑即可补写）"""
    try:
        _write_marker(marker, source, target)
    except OSError as exc:
        raise MigrationError(
            f"数据已就位于目标（{target}），但写入完成标记失败：{exc}；再次运行脚本即可补写标记"
        ) from exc


# ── 核心迁移 ──


def migrate(
    source: str | os.PathLike[str],
    target: str | os.PathLike[str],
    force: bool = False,
) -> dict[str, str]:
    """执行迁移，返回结果说明 {"action": ..., "message": ...}

    action 取值：
        already-migrated  目标带完成标记，幂等跳过；
        skipped           目标已存在同健康数据，补写完成标记后跳过（防覆盖）；
        copied            完成复制 + 验证 + 完成标记。

    失败一律抛 MigrationError（main 捕获后非零退出）；源数据库任何情况下不被删除。
    """
    src = Path(source).resolve()
    tgt = Path(target).resolve()

    # Falsify：源=目标同路径，复制无意义且易误伤，直接拒绝
    if src == tgt:
        raise MigrationError("源与目标是同一个文件，无需迁移")

    check_source(src)

    # 目标路径被目录占用：任何分支（含 --force）都不可覆盖目录
    if tgt.is_dir():
        raise MigrationError(f"目标路径被目录占用：{tgt}")

    marker = marker_path_for(tgt)
    if marker.exists() and not force:
        if not tgt.exists():
            raise MigrationError(
                "完成标记存在但目标数据库缺失，状态不一致；确认无误后可加 --force 重新迁移"
            )
        return {"action": "already-migrated", "message": f"目标已带完成标记，跳过迁移（{tgt}）"}

    if tgt.exists() and not force:
        problems = verify_database(tgt)
        if not problems:
            same, _reason = databases_equivalent(src, tgt)
            if same:
                _write_marker_safe(marker, src, tgt)
                return {
                    "action": "skipped",
                    "message": "目标已存在且数据与源一致，补写完成标记后跳过（未覆盖任何数据）",
                }
        raise MigrationError(
            "目标数据库已存在且与源数据不一致（或目标不可用），为避免覆盖既有数据，"
            "请确认后用 --force 重新迁移"
        )

    # 确保目标目录存在
    try:
        tgt.parent.mkdir(parents=True, exist_ok=True)
    except FileExistsError:
        raise MigrationError(f"目标目录路径被文件占用，无法创建：{tgt.parent}") from None
    except OSError as exc:
        raise MigrationError(f"无法创建目标目录：{exc}") from exc

    # 并发锁 + 可写性探测（O_EXCL 创建失败即视为有锁；权限不足会抛 PermissionError）
    lock = tgt.parent / LOCK_NAME
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        os.write(fd, str(os.getpid()).encode("utf-8"))
        os.close(fd)
    except FileExistsError:
        raise MigrationError(
            f"检测到迁移锁文件（{lock}），可能另有迁移进程在运行或上次迁移异常中断；"
            "确认无其他进程后删除锁文件重试"
        ) from None
    except OSError as exc:
        raise MigrationError(f"目标目录不可写：{exc}") from exc

    try:
        # 先复制到临时文件再原子替换：中途失败不破坏已有目标文件
        tmp_target = tgt.with_name(tgt.name + ".tmp")
        try:
            shutil.copy2(src, tmp_target)
            os.replace(tmp_target, tgt)
        except OSError as exc:
            raise MigrationError(
                f"复制源数据库到目标失败：{exc}（源数据库未受影响）"
            ) from exc

        # 迁移后完整性验证：通过才写完成标记
        problems = verify_database(tgt)
        if problems:
            raise MigrationError(
                "迁移后完整性验证未通过：" + "；".join(problems) + "（源数据库未受影响，可重试）"
            )

        _write_marker_safe(marker, src, tgt)
    finally:
        try:
            lock.unlink()  # 锁清理尽力而为：失败不影响迁移结果
        except OSError:
            pass

    return {
        "action": "copied",
        "message": f"迁移完成：{src} → {tgt}（源数据库保留未动）",
    }


# ── CLI ──


def build_parser() -> argparse.ArgumentParser:
    """构造 CLI 参数解析器（中文说明）"""
    parser = argparse.ArgumentParser(
        prog="migrate_data",
        description=(
            "Conver System 数据迁移脚本：把网页版根目录数据库复制到桌面版数据目录。"
            "复制非移动（源数据库保留不删）；迁移完成且验证通过后写入 .migrated 完成标记；"
            "重复运行幂等（已迁移则跳过）。"
        ),
    )
    parser.add_argument(
        "--source",
        default=str(default_source_path()),
        help="源数据库路径（默认：当前目录下 conver_system.db）",
    )
    parser.add_argument(
        "--target",
        default=str(default_target_path()),
        help=(
            "目标数据库路径（默认：%%APPDATA%%\\ConverSystem\\conver_system.db；"
            "可用环境变量 CONVER_DATA_DIR 覆盖数据目录）"
        ),
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="目标已存在（含带完成标记或数据不一致）时强制重新复制覆盖",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI 入口：解析参数并执行迁移，返回进程退出码（0 成功，1 失败）"""
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = migrate(args.source, args.target, force=args.force)
    except MigrationError as exc:
        print(f"迁移失败：{exc}", file=sys.stderr)
        return 1
    print(result["message"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
