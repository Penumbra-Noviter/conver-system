"""
P6.4-3 单元测试 — 数据迁移脚本（backend/scripts/migrate_data.py）

覆盖（Seam 3：临时目录 + 构造源数据库，全部使用 tmp_path，绝不触碰真实数据）：
    1. 成功迁移：源复制到目标 + 数据完整 + 完成标记 + 源字节级未动
    2. 源异常：缺失 / 是目录 / 损坏（非 SQLite）/ 空文件 / 缺核心表 / 源=目标 → 明确报错
    3. 幂等：完成标记存在跳过（不复制不覆盖）/ 目标同健康数据跳过（防覆盖）/ 标记在但目标缺失
    4. 目标冲突：数据不一致拒绝覆盖，--force 才覆盖
    5. 目标路径问题：被目录占用 / 目标目录被文件占用 / 目标目录不可写
    6. 迁移后验证失败不写标记 / 标记写入失败可自愈重跑
    7. 并发锁：锁文件存在报错
    8. CLI：main 退出码、--force、--help 中文说明、默认路径（APPDATA / CONVER_DATA_DIR）
    9. 路径含空格与中文

依赖：纯 stdlib（sqlite3 + shutil），不依赖后端 app 代码。
"""

from __future__ import annotations

import json
import os
import shutil
import sqlite3
from pathlib import Path

import pytest

from backend.scripts.migrate_data import (
    LOCK_NAME,
    MARKER_NAME,
    MigrationError,
    check_source,
    databases_equivalent,
    default_source_path,
    default_target_path,
    main,
    marker_path_for,
    migrate,
    verify_database,
)

__all__: list[str] = []


def _truncate_to(path: Path, new_size: int) -> None:
    """把数据库文件截断到指定字节数制造损坏（模拟末页残缺 / 整页丢失）"""
    data = path.read_bytes()
    assert 0 < new_size < len(data)
    path.write_bytes(data[:new_size])


def _make_db(path: Path, name: str = "测试角色") -> None:
    """用 sqlite3 直接构造一个合法的 Conver System 数据库（4 张核心表 + 数据）"""
    conn = sqlite3.connect(path)
    try:
        conn.executescript(
            """
            CREATE TABLE characters (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name VARCHAR(100) NOT NULL,
                description TEXT DEFAULT '',
                personality TEXT DEFAULT '',
                scenario TEXT DEFAULT '',
                first_mes TEXT DEFAULT '',
                mes_example TEXT DEFAULT '',
                system_prompt TEXT DEFAULT '',
                post_history_instructions TEXT DEFAULT '',
                alternate_greetings TEXT DEFAULT '[]',
                tags TEXT DEFAULT '[]',
                creator TEXT DEFAULT '',
                version TEXT DEFAULT '',
                creator_notes TEXT DEFAULT '{}',
                extensions TEXT DEFAULT '{}',
                avatar TEXT,
                temperature FLOAT DEFAULT 0.7
            );
            CREATE TABLE conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                character_id INTEGER,
                title TEXT,
                provider TEXT,
                model TEXT
            );
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id INTEGER,
                role TEXT,
                content TEXT
            );
            CREATE TABLE settings (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            """
        )
        conn.execute("INSERT INTO characters (name) VALUES (?)", (name,))
        conn.execute(
            "INSERT INTO settings (key, value) VALUES (?, ?)",
            ("default_provider", "claude"),
        )
        conn.commit()
    finally:
        conn.close()


# ── 1. 成功迁移：复制非移动 + 完成标记 ──


class TestMigrateSuccess:
    def test_copy_source_to_target_with_marker(self, tmp_path) -> None:
        """源复制到目标，源字节级未动，目标同目录写 .migrated 标记"""
        source = tmp_path / "conver_system.db"
        _make_db(source)
        source_bytes = source.read_bytes()
        target = tmp_path / "AppData" / "Roaming" / "ConverSystem" / "conver_system.db"

        result = migrate(source, target)

        assert result["action"] == "copied"
        assert target.exists()
        assert target.read_bytes() == source_bytes  # 复制内容一致
        assert source.read_bytes() == source_bytes  # 源原样未动（复制非移动）
        marker = marker_path_for(target)
        assert marker.exists()
        payload = json.loads(marker.read_text(encoding="utf-8"))
        assert payload["source"] == str(source.resolve())
        assert payload["target"] == str(target.resolve())
        assert payload["integrity"] == "ok"
        assert payload["migrated_at"]

    def test_target_contains_source_data(self, tmp_path) -> None:
        """目标库表结构完整、数据一致（库级断言）"""
        source = tmp_path / "src.db"
        _make_db(source, name="中文角色 测试")
        target = tmp_path / "dst" / "conver_system.db"

        migrate(source, target)

        conn = sqlite3.connect(target)
        try:
            assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            tables = {
                r[0]
                for r in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
                )
            }
            assert tables == {"characters", "conversations", "messages", "settings"}
            assert conn.execute("SELECT COUNT(*) FROM characters").fetchone()[0] == 1
            assert conn.execute("SELECT name FROM characters").fetchone()[0] == "中文角色 测试"
            assert conn.execute("SELECT COUNT(*) FROM settings").fetchone()[0] == 1
        finally:
            conn.close()


# ── 2. 源异常：缺失 / 目录 / 损坏 / 空文件 / 缺核心表 / 源=目标 ──


class TestSourceErrors:
    def test_source_missing_raises(self, tmp_path) -> None:
        with pytest.raises(MigrationError, match="不存在"):
            migrate(tmp_path / "nope.db", tmp_path / "dst" / "conver_system.db")

    def test_source_is_directory_raises(self, tmp_path) -> None:
        with pytest.raises(MigrationError, match="目录"):
            migrate(tmp_path, tmp_path / "dst" / "conver_system.db")

    def test_source_corrupt_raises(self, tmp_path) -> None:
        """非 SQLite 文件作源 → 明确报错"""
        source = tmp_path / "corrupt.db"
        source.write_text("这不是一个 SQLite 数据库", encoding="utf-8")
        with pytest.raises(MigrationError, match="源数据库不可用"):
            migrate(source, tmp_path / "dst" / "conver_system.db")

    def test_source_empty_file_raises(self, tmp_path) -> None:
        """0 字节空文件（SQLite 视为空库）→ 无数据表，拒绝迁移"""
        source = tmp_path / "empty.db"
        source.write_bytes(b"")
        with pytest.raises(MigrationError, match="源数据库不可用"):
            migrate(source, tmp_path / "dst" / "conver_system.db")

    def test_source_missing_core_tables_raises(self, tmp_path) -> None:
        """合法 SQLite 但缺核心表（不是 Conver System 库）→ 拒绝迁移"""
        source = tmp_path / "partial.db"
        conn = sqlite3.connect(source)
        conn.execute("CREATE TABLE unrelated (id INTEGER)")
        conn.commit()
        conn.close()
        with pytest.raises(MigrationError, match="缺少核心表"):
            migrate(source, tmp_path / "dst" / "conver_system.db")

    def test_source_truncated_raises(self, tmp_path) -> None:
        """文件被截断（末页残缺，integrity 报问题行）→ 完整性检查未通过，拒绝迁移"""
        source = tmp_path / "truncated.db"
        _make_db(source)
        _truncate_to(source, source.stat().st_size - 1)  # 末页残缺 1 字节
        with pytest.raises(MigrationError, match="完整性检查未通过"):
            migrate(source, tmp_path / "dst" / "conver_system.db")

    def test_source_truncated_hard_raises(self, tmp_path) -> None:
        """文件被截断（整页丢失，integrity 直接报错）→ 完整性检查失败，拒绝迁移"""
        source = tmp_path / "truncated3q.db"
        _make_db(source)
        _truncate_to(source, source.stat().st_size * 3 // 4)  # 缺失约 1/4 文件
        with pytest.raises(MigrationError, match="完整性检查失败"):
            migrate(source, tmp_path / "dst" / "conver_system.db")

    def test_source_symlink_followed(self, tmp_path) -> None:
        """源为符号链接 → 按真实文件复制（无链接权限的环境跳过）"""
        source = tmp_path / "real.db"
        _make_db(source)
        link = tmp_path / "link.db"
        try:
            link.symlink_to(source)
        except OSError:
            pytest.skip("当前环境无法创建符号链接")
        target = tmp_path / "dst" / "conver_system.db"

        result = migrate(link, target)

        assert result["action"] == "copied"
        assert target.read_bytes() == source.read_bytes()
        assert source.read_bytes() == target.read_bytes()

    def test_target_inside_source_directory_is_safe(self, tmp_path) -> None:
        """目标在源所在目录的子目录（复制到自身内部）→ 合法复制，源不受影响"""
        base = tmp_path / "base"
        base.mkdir()
        source = base / "conver_system.db"
        _make_db(source)
        source_bytes = source.read_bytes()
        target = base / "sub" / "conver_system.db"

        result = migrate(source, target)

        assert result["action"] == "copied"
        assert source.read_bytes() == source_bytes
        assert target.read_bytes() == source_bytes
        assert marker_path_for(target).exists()

    def test_source_equals_target_raises(self, tmp_path) -> None:
        source = tmp_path / "same.db"
        _make_db(source)
        with pytest.raises(MigrationError, match="同一个文件"):
            migrate(source, source)


# ── 3. 幂等：完成标记 / 同健康数据跳过 ──


class TestIdempotency:
    def test_marker_exists_skips_without_touching_target(self, tmp_path) -> None:
        """二次运行：不复制、不覆盖、不报错，返回 already-migrated"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        migrate(source, target)
        source_bytes = source.read_bytes()
        target_bytes = target.read_bytes()

        result = migrate(source, target)

        assert result["action"] == "already-migrated"
        assert target.read_bytes() == target_bytes
        assert source.read_bytes() == source_bytes

    def test_main_rerun_returns_zero(self, tmp_path, capsys) -> None:
        """CLI 二次运行退出码 0，输出跳过提示"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        assert main(["--source", str(source), "--target", str(target)]) == 0
        capsys.readouterr()
        assert main(["--source", str(source), "--target", str(target)]) == 0
        assert "跳过" in capsys.readouterr().out

    def test_target_identical_without_marker_skips_and_writes_marker(self, tmp_path) -> None:
        """目标已存在同健康数据但无标记 → 防覆盖跳过并补写完成标记"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        target.parent.mkdir(parents=True)
        shutil.copyfile(source, target)  # 模拟此前已复制但未写标记
        target_bytes = target.read_bytes()

        result = migrate(source, target)

        assert result["action"] == "skipped"
        assert target.read_bytes() == target_bytes  # 防覆盖：目标未改动
        assert marker_path_for(target).exists()

    def test_marker_exists_but_target_missing_raises(self, tmp_path) -> None:
        """完成标记存在但目标库缺失（状态不一致）→ 报错要求 --force"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        target.parent.mkdir(parents=True)
        marker_path_for(target).write_text("{}", encoding="utf-8")
        with pytest.raises(MigrationError, match="状态不一致"):
            migrate(source, target)


# ── 4. 目标冲突：防覆盖与 --force ──


class TestTargetConflict:
    def test_target_different_data_raises_without_force(self, tmp_path) -> None:
        """目标已存在且数据不一致 → 拒绝覆盖（防丢数据），提示 --force"""
        source = tmp_path / "src.db"
        _make_db(source, name="源角色")
        target = tmp_path / "dst" / "conver_system.db"
        target.parent.mkdir(parents=True)
        _make_db(target, name="目标角色（不同数据）")
        target_bytes = target.read_bytes()

        with pytest.raises(MigrationError, match="--force"):
            migrate(source, target)
        assert target.read_bytes() == target_bytes  # 目标未动

    def test_force_overwrites_existing_target(self, tmp_path) -> None:
        """--force：即使目标带旧标记/数据不同也重新复制覆盖，重写标记"""
        source = tmp_path / "src.db"
        _make_db(source, name="源角色")
        target = tmp_path / "dst" / "conver_system.db"
        target.parent.mkdir(parents=True)
        _make_db(target, name="旧目标")
        marker_path_for(target).write_text("old", encoding="utf-8")

        result = migrate(source, target, force=True)

        assert result["action"] == "copied"
        assert target.read_bytes() == source.read_bytes()
        payload = json.loads(marker_path_for(target).read_text(encoding="utf-8"))
        assert payload["integrity"] == "ok"


# ── 5. 目标路径问题 ──


class TestTargetDirectoryIssues:
    def test_target_path_occupied_by_directory_raises(self, tmp_path) -> None:
        source = tmp_path / "src.db"
        _make_db(source)
        target_dir = tmp_path / "dst" / "conver_system.db"
        target_dir.mkdir(parents=True)
        with pytest.raises(MigrationError, match="目录占用"):
            migrate(source, target_dir)

    def test_target_dir_path_occupied_by_file_raises(self, tmp_path) -> None:
        """目标目录路径被同名文件占用 → 无法创建目录报错"""
        source = tmp_path / "src.db"
        _make_db(source)
        blocker = tmp_path / "blocker"
        blocker.write_text("占用", encoding="utf-8")
        with pytest.raises(MigrationError, match="被文件占用"):
            migrate(source, blocker / "conver_system.db")

    def test_target_dir_not_writable_raises(self, tmp_path, monkeypatch) -> None:
        """目标目录不可写（锁文件创建被拒）→ 明确报错"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        real_open = os.open

        def fake_open(path, flags, mode=0o644):
            if str(path).endswith(LOCK_NAME):
                raise PermissionError(13, "拒绝访问", str(path))
            return real_open(path, flags, mode)

        monkeypatch.setattr(os, "open", fake_open)
        with pytest.raises(MigrationError, match="不可写"):
            migrate(source, target)

    def test_lock_file_present_raises(self, tmp_path) -> None:
        """并发锁存在（另一进程在跑或上次异常中断）→ 报错"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        target.parent.mkdir(parents=True)
        (target.parent / LOCK_NAME).write_text("12345", encoding="utf-8")
        with pytest.raises(MigrationError, match="迁移锁"):
            migrate(source, target)

    def test_marker_exists_but_target_is_dir(self, tmp_path) -> None:
        """完成标记存在但目标路径是目录 → 报错而非假跳过"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        target.mkdir(parents=True)
        marker_path_for(target).write_text("{}", encoding="utf-8")
        with pytest.raises(MigrationError, match="目录占用"):
            migrate(source, target)

    def test_force_with_target_dir_raises(self, tmp_path) -> None:
        """--force 也不能把目录当目标覆盖"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        target.mkdir(parents=True)
        with pytest.raises(MigrationError, match="目录占用"):
            migrate(source, target, force=True)

    def test_mkdir_permission_error_raises(self, tmp_path, monkeypatch) -> None:
        """目标目录创建被拒（非文件占用类错误）→ 明确报错"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"

        def fake_mkdir(self, *args, **kwargs):
            raise PermissionError(13, "拒绝访问", str(self))

        monkeypatch.setattr(Path, "mkdir", fake_mkdir)
        with pytest.raises(MigrationError, match="无法创建目标目录"):
            migrate(source, target)

    def test_lock_cleanup_failure_does_not_break_success(self, tmp_path, monkeypatch) -> None:
        """锁文件清理失败（尽力而为）不影响迁移成功"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"

        def fake_unlink(self, *args, **kwargs):
            raise OSError(5, "拒绝访问")

        monkeypatch.setattr(Path, "unlink", fake_unlink)
        result = migrate(source, target)
        assert result["action"] == "copied"
        assert marker_path_for(target).exists()


# ── 6. 验证与标记失败路径 ──


class TestVerificationFailures:
    def test_post_copy_verification_failure_no_marker(self, tmp_path, monkeypatch) -> None:
        """复制后目标损坏 → 验证失败报错且不写完成标记"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        real_copy2 = shutil.copy2

        def fake_copy2(src, dst):
            real_copy2(src, dst)
            with open(dst, "wb") as f:
                f.write(b"corrupt after copy")

        monkeypatch.setattr(shutil, "copy2", fake_copy2)
        with pytest.raises(MigrationError, match="验证"):
            migrate(source, target)
        assert not marker_path_for(target).exists()

    def test_copy_failure_reports_source_untouched(self, tmp_path, monkeypatch) -> None:
        """复制过程中 I/O 失败 → 明确报错，源不受影响"""
        source = tmp_path / "src.db"
        _make_db(source)
        source_bytes = source.read_bytes()
        target = tmp_path / "dst" / "conver_system.db"

        def fake_copy2(src, dst):
            raise OSError(28, "No space left on device")

        monkeypatch.setattr(shutil, "copy2", fake_copy2)
        with pytest.raises(MigrationError, match="复制源数据库到目标失败"):
            migrate(source, target)
        assert source.read_bytes() == source_bytes

    def test_marker_write_failure_self_heals_on_rerun(self, tmp_path, monkeypatch) -> None:
        """标记写入失败 → 报错说明数据已就位；重跑可补写标记"""
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        real_replace = os.replace

        def fake_replace(src, dst):
            if str(dst).endswith(MARKER_NAME):
                raise PermissionError(13, "拒绝访问", str(dst))
            return real_replace(src, dst)

        monkeypatch.setattr(os, "replace", fake_replace)
        with pytest.raises(MigrationError, match="完成标记"):
            migrate(source, target)
        assert target.read_bytes() == source.read_bytes()  # 数据已在目标

        monkeypatch.undo()
        result = migrate(source, target)
        assert result["action"] == "skipped"
        assert marker_path_for(target).exists()


# ── 7. 校验与比对函数（公共 API）──


class TestVerifyAndCompare:
    def test_verify_database_healthy(self, tmp_path) -> None:
        source = tmp_path / "db.db"
        _make_db(source)
        assert verify_database(source) == []

    def test_verify_database_corrupt(self, tmp_path) -> None:
        bad = tmp_path / "bad.db"
        bad.write_text("garbage", encoding="utf-8")
        problems = verify_database(bad)
        assert problems and "file is not a database" in problems[0]

    def test_verify_database_on_directory(self, tmp_path) -> None:
        """目录路径当数据库 → 无法打开报错"""
        problems = verify_database(tmp_path)
        assert problems and "无法作为 SQLite 数据库打开" in problems[0]

    def test_integrity_check_reports_truncated_db(self, tmp_path) -> None:
        """末页残缺 → integrity_check 返回问题行而非 ok"""
        db = tmp_path / "truncated.db"
        _make_db(db)
        _truncate_to(db, db.stat().st_size - 1)  # 截断 1 字节
        problems = verify_database(db)
        assert any("完整性检查未通过" in p for p in problems)

    def test_integrity_check_raises_on_truncated_db(self, tmp_path) -> None:
        """整页缺失 → integrity_check 抛错，映射为「完整性检查失败」"""
        db = tmp_path / "truncated3q.db"
        _make_db(db)
        _truncate_to(db, db.stat().st_size * 3 // 4)  # 截断至 3/4
        problems = verify_database(db)
        assert any("完整性检查失败" in p for p in problems)

    def test_verify_database_empty(self, tmp_path) -> None:
        empty = tmp_path / "empty.db"
        empty.write_bytes(b"")
        problems = verify_database(empty)
        assert any("数据表" in p for p in problems)

    def test_verify_database_missing_core_tables(self, tmp_path) -> None:
        db = tmp_path / "partial.db"
        conn = sqlite3.connect(db)
        conn.execute("CREATE TABLE t (id INTEGER)")
        conn.commit()
        conn.close()
        problems = verify_database(db)
        assert any("核心表" in p for p in problems)

    def test_databases_equivalent_identical(self, tmp_path) -> None:
        a = tmp_path / "a.db"
        b = tmp_path / "b.db"
        _make_db(a)
        _make_db(b)
        ok, reason = databases_equivalent(a, b)
        assert ok is True
        assert reason == ""

    def test_databases_equivalent_table_set_differs(self, tmp_path) -> None:
        a = tmp_path / "a.db"
        b = tmp_path / "b.db"
        _make_db(a)
        _make_db(b)
        conn = sqlite3.connect(b)
        conn.execute("CREATE TABLE extra (id INTEGER)")
        conn.commit()
        conn.close()
        ok, reason = databases_equivalent(a, b)
        assert ok is False
        assert "表结构" in reason

    def test_databases_equivalent_row_differs(self, tmp_path) -> None:
        a = tmp_path / "a.db"
        b = tmp_path / "b.db"
        _make_db(a, name="角色A")
        _make_db(b, name="角色B")
        ok, reason = databases_equivalent(a, b)
        assert ok is False
        assert "数据不一致" in reason

    def test_databases_equivalent_unopenable(self, tmp_path) -> None:
        """一侧无法打开（目录路径）→ 返回不一致与原因"""
        good = tmp_path / "good.db"
        _make_db(good)
        ok, reason = databases_equivalent(tmp_path, good)
        assert ok is False
        assert "无法打开数据库进行比对" in reason

    def test_databases_equivalent_query_failure(self, tmp_path) -> None:
        """一侧为损坏文件（查询阶段失败）→ 返回不一致与原因"""
        good = tmp_path / "good.db"
        _make_db(good)
        bad = tmp_path / "bad.db"
        bad.write_text("garbage", encoding="utf-8")
        ok, reason = databases_equivalent(good, bad)
        assert ok is False
        assert "比对数据失败" in reason

    def test_check_source_ok(self, tmp_path) -> None:
        source = tmp_path / "db.db"
        _make_db(source)
        check_source(source)  # 健康源不抛异常


# ── 8. CLI 与默认路径 ──


class TestCli:
    def test_main_success_prints_message(self, tmp_path, capsys) -> None:
        source = tmp_path / "src.db"
        _make_db(source)
        target = tmp_path / "dst" / "conver_system.db"
        assert main(["--source", str(source), "--target", str(target)]) == 0
        assert "迁移完成" in capsys.readouterr().out

    def test_main_missing_source_returns_nonzero(self, tmp_path, capsys) -> None:
        rc = main(
            ["--source", str(tmp_path / "missing.db"), "--target", str(tmp_path / "dst" / "x.db")]
        )
        assert rc == 1
        assert "迁移失败" in capsys.readouterr().err

    def test_main_force_flag(self, tmp_path) -> None:
        source = tmp_path / "src.db"
        _make_db(source, name="源")
        target = tmp_path / "dst" / "conver_system.db"
        target.parent.mkdir(parents=True)
        _make_db(target, name="旧目标")
        assert main(["--source", str(source), "--target", str(target), "--force"]) == 0
        assert target.read_bytes() == source.read_bytes()

    def test_main_help_in_chinese(self, capsys) -> None:
        with pytest.raises(SystemExit) as exc:
            main(["--help"])
        assert exc.value.code == 0
        out = capsys.readouterr().out
        assert "迁移" in out
        assert "--source" in out and "--target" in out and "--force" in out

    def test_script_entrypoint_subprocess(self, tmp_path) -> None:
        """真实运行：直接脚本路径与 python -m 两种调用形态都成功（覆盖 __main__ 入口）"""
        import subprocess
        import sys

        repo_root = Path(__file__).resolve().parents[2]
        script = repo_root / "backend" / "scripts" / "migrate_data.py"
        source = tmp_path / "src.db"
        _make_db(source, name="子进程迁移 角色")
        source_bytes = source.read_bytes()
        target = tmp_path / "dst" / "conver_system.db"

        # 形态一：python backend/scripts/migrate_data.py
        run1 = subprocess.run(
            [sys.executable, str(script), "--source", str(source), "--target", str(target)],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        assert run1.returncode == 0, run1.stderr
        assert "迁移完成" in run1.stdout
        assert target.read_bytes() == source_bytes
        assert source.read_bytes() == source_bytes  # 源未动
        assert marker_path_for(target).exists()

        # 形态二：python -m backend.scripts.migrate_data（幂等跳过）
        run2 = subprocess.run(
            [sys.executable, "-m", "backend.scripts.migrate_data", "--source", str(source),
             "--target", str(target)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            cwd=repo_root,
        )
        assert run2.returncode == 0, run2.stderr
        assert "跳过" in run2.stdout
        assert target.read_bytes() == source_bytes


class TestDefaultPaths:
    """契约表 v1（委托 backend.app.services.data_dir.database_path；Rust 侧镜像见
    src-tauri/tests/server_test.rs，同一版本号互引）：
    CONVER_DATA_DIR（非空）→ %APPDATA% → home\\AppData\\Roaming，均拼 ConverSystem"""

    def test_default_source_path(self) -> None:
        assert default_source_path() == Path.cwd() / "conver_system.db"

    def test_default_target_uses_appdata(self, tmp_path, monkeypatch) -> None:
        monkeypatch.setenv("APPDATA", str(tmp_path / "AppData" / "Roaming"))
        monkeypatch.delenv("CONVER_DATA_DIR", raising=False)
        assert default_target_path() == (
            tmp_path / "AppData" / "Roaming" / "ConverSystem" / "conver_system.db"
        )

    def test_default_target_env_override(self, tmp_path, monkeypatch) -> None:
        """CONVER_DATA_DIR 环境变量优先于 APPDATA"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path / "custom"))
        monkeypatch.setenv("APPDATA", str(tmp_path / "ignored"))
        assert default_target_path() == tmp_path / "custom" / "conver_system.db"

    def test_default_target_empty_env_treated_as_unset(self, tmp_path, monkeypatch) -> None:
        """契约表 v1：CONVER_DATA_DIR="" 视为未设置"""
        monkeypatch.setenv("CONVER_DATA_DIR", "")
        monkeypatch.setenv("APPDATA", str(tmp_path / "AppData" / "Roaming"))
        assert default_target_path() == (
            tmp_path / "AppData" / "Roaming" / "ConverSystem" / "conver_system.db"
        )

    def test_default_target_fallback_without_appdata(self, tmp_path, monkeypatch) -> None:
        """APPDATA 缺失 → home\\AppData\\Roaming\\ConverSystem\\conver_system.db（D1-D2 兜底统一）"""
        monkeypatch.delenv("APPDATA", raising=False)
        monkeypatch.delenv("CONVER_DATA_DIR", raising=False)
        monkeypatch.setenv("USERPROFILE", str(tmp_path))
        monkeypatch.setenv("HOME", str(tmp_path))
        expected = (
            Path.home() / "AppData" / "Roaming" / "ConverSystem" / "conver_system.db"
        )
        assert default_target_path() == expected


# ── 9. 路径含空格与中文（Windows 真实文件系统）──


class TestExoticPaths:
    def test_paths_with_spaces_and_chinese(self, tmp_path) -> None:
        source = tmp_path / "数据 目录" / "conver_system.db"
        source.parent.mkdir(parents=True)
        _make_db(source)
        target = tmp_path / "目标 目录-中文" / "conver_system.db"

        result = migrate(source, target)

        assert result["action"] == "copied"
        assert target.read_bytes() == source.read_bytes()
        assert marker_path_for(target).exists()
