"""
ARC9-T04 单元测试 — 数据目录共享模块契约（backend/app/services/data_dir.py）

契约表 v2（双端镜像；Rust 侧 src-tauri/tests/server_test.rs 同一版本号互引，防漂移）：

    1. 解析链（resolve，三端一致）：
       CONVER_DATA_DIR（环境变量，**非空串才生效**，空串视为未设置）
       → %APPDATA%\\ConverSystem
       → home\\AppData\\Roaming\\ConverSystem（APPDATA 缺失兜底，决策 D1-D2）
    2. URL 编码（壳侧 database_url 契约）：编码集 = {`?` → `%3F`}，其余字符
       （含空格/中文/`#`/`%`）一律原样保留。`?` 是 SQLAlchemy URL 解析器的唯一
       实际分隔符（防御性编码，Windows 非法文件名不可达）；sqlite 方言对
       DATABASE_URL 零解码，契约表 v1 的全量百分号编码（urllib.parse.quote
       safe="/:" 口径）在真实消费者处报 OperationalError（期末审核 Falsify
       阻断项修复；连接级验证见 test_data_dir_connection.py）。
    3. G4 守卫：data_dir 模块仅 stdlib import，导入链不得拉入其它 backend.app.* 模块。

冒烟脚本（scripts/smoke-desktop.ps1 74-81 段）为显式例外（决策 D1-D4）：
冒烟是断言环境而非解析器，APPDATA 缺失即环境错误 → throw，不参与本契约的兜底链。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from backend.app.services import data_dir as data_dir_service

__all__ = [
    "TestResolveContract",
    "TestUrlEncodingReference",
    "TestPureStdlibGuard",
]


def _encode_url_path(path: str) -> str:
    """契约表 v2 编码参考（镜像 Rust `encode_url_path`）：仅 `?` → `%3F`，其余原样。

    契约表 v1 曾以 `urllib.parse.quote(s, safe="/:")` 为基准做全量百分号编码——
    SQLAlchemy sqlite 方言零解码，`%XX` 被当字面文件名，真实消费者打不开数据库
    （OperationalError，连接级复现见 test_data_dir_connection.py）。
    """
    return path.replace("?", "%3F")


class TestResolveContract:
    """resolve 契约：CONVER_DATA_DIR（非空）→ %APPDATA% → home\\AppData\\Roaming 兜底"""

    def test_env_override_wins(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """CONVER_DATA_DIR 非空 → 值即数据目录（不做任何路径改写）"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path / "custom"))
        monkeypatch.setenv("APPDATA", str(tmp_path / "ignored"))
        assert data_dir_service.data_dir() == tmp_path / "custom"

    def test_env_override_keeps_special_chars_verbatim(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """契约表 v2：resolve 不编码——含 #/?/空格/中文的 CONVER_DATA_DIR 原样返回

        编码是壳侧 database_url 的职责（见 TestUrlEncodingReference 与 Rust 镜像用例）；
        resolve 返回的 Path 必须与用户给定值**非分隔符字符**逐字符一致（空格/中文/`#`/`%`
        等一律原样），否则迁移/日志会写到错误位置；仅分隔符按 pathlib 规范化——重复
        分隔符折叠、`.` 段消除、尾分隔符去除，`..` 段原样保留由文件系统在访问时解析
        （规范化边界见 test_env_override_separators_normalized）。
        """
        special = tmp_path / "Conver 数据#目录?v1%"
        monkeypatch.setenv("CONVER_DATA_DIR", str(special))
        monkeypatch.setenv("APPDATA", str(tmp_path / "ignored"))
        assert data_dir_service.data_dir() == special

    def test_env_override_separators_normalized(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """契约锁（基线即绿非先红，语义与 TD-12 先例一致）：resolve 仅分隔符按 pathlib 规范化

        钉住 v2 契约边界，防实现漂移——与 test_env_override_keeps_special_chars_verbatim
        互为补集（后者钉非分隔符原样，本用例钉分隔符规范化）：
        重复分隔符折叠（`//` → `/`）与 `.` 段消除；`..` 段**不提前解析**，
        原样保留于 parts，由文件系统在访问时解析。
        """
        monkeypatch.setenv("CONVER_DATA_DIR", "C:/a//b/./c")
        monkeypatch.setenv("APPDATA", "C:/ignored")
        assert data_dir_service.data_dir() == Path("C:/a/b/c")
        monkeypatch.setenv("CONVER_DATA_DIR", "C:/a/../b")
        assert ".." in data_dir_service.data_dir().parts

    def test_empty_env_treated_as_unset(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """契约表 v2：CONVER_DATA_DIR="" 视为未设置（与壳侧 var_os 非空判定对齐）"""
        monkeypatch.setenv("CONVER_DATA_DIR", "")
        monkeypatch.setenv("APPDATA", str(tmp_path / "appdata"))
        assert data_dir_service.data_dir() == tmp_path / "appdata" / "ConverSystem"

    def test_appdata_default(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """无覆盖 → %APPDATA%\\ConverSystem"""
        monkeypatch.delenv("CONVER_DATA_DIR", raising=False)
        monkeypatch.setenv("APPDATA", str(tmp_path / "AppData" / "Roaming"))
        assert data_dir_service.data_dir() == tmp_path / "AppData" / "Roaming" / "ConverSystem"

    def test_home_appdata_roaming_fallback(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """契约表 v2（决策 D1-D2）：APPDATA 缺失 → home\\AppData\\Roaming\\ConverSystem

        注意：兜底是 home\\AppData\\Roaming（不是 home 根）——兜底统一 = T-01 修复本身，
        与迁移脚本既有语义一致，评审按此口径。
        """
        monkeypatch.delenv("CONVER_DATA_DIR", raising=False)
        monkeypatch.delenv("APPDATA", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        assert data_dir_service.data_dir() == tmp_path / "AppData" / "Roaming" / "ConverSystem"

    def test_relative_env_override_kept_as_is(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Falsify：CONVER_DATA_DIR 为相对路径 → 原样返回（resolve 不做归一化/绝对化）"""
        monkeypatch.setenv("CONVER_DATA_DIR", "relative/data dir")
        monkeypatch.setenv("APPDATA", "C:/ignored")
        assert data_dir_service.data_dir() == Path("relative/data dir")

    def test_data_dir_file_appends_under_data_dir(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """data_dir_file(name) = data_dir() / name"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        assert data_dir_service.data_dir_file("backend.log") == tmp_path / "backend.log"

    def test_database_path_defaults_to_conver_system_db(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """database_path() = data_dir()\\conver_system.db（与壳侧 DB_FILE 常量对齐）"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        assert data_dir_service.database_path() == tmp_path / "conver_system.db"

    def test_constants_aligned_with_shell(self) -> None:
        """目录名/库文件名常量与壳侧（src-tauri/src/server.rs DATA_DIR_NAME / DB_FILE）一致"""
        assert data_dir_service.DATA_DIR_NAME == "ConverSystem"
        assert data_dir_service.DATA_DIR_ENV == "CONVER_DATA_DIR"
        assert data_dir_service.DB_FILE == "conver_system.db"


class TestUrlEncodingReference:
    """契约表 v2 编码参考（Python 侧基准）：编码集 = {`?` → `%3F`}，其余原样保留。

    这些字面量即 Rust 侧 encode_url_path 逐字符用例的期望值来源（镜像契约）；
    若任一侧漂移，本组用例先红，双端同步修正契约表版本号。
    连接级验证（真实 SQLAlchemy 消费者）见 test_data_dir_connection.py。
    """

    def test_headline_cases(self) -> None:
        assert _encode_url_path("a#b?c%d e") == "a#b%3Fc%d e"
        assert _encode_url_path("数据 目录") == "数据 目录"
        assert _encode_url_path("C:/Users/x/AppData/Roaming/Conver System") == (
            "C:/Users/x/AppData/Roaming/Conver System"
        )
        assert _encode_url_path("C:/Users/x/数据#目录%v1/") == (
            "C:/Users/x/数据#目录%v1/"
        )

    def test_only_question_mark_is_encoded(self) -> None:
        """逐字符钉住 v2 编码集边界：ASCII 全表仅 `?` → %3F，其余原样保留（大写字面量）"""
        for code in range(128):
            char = chr(code)
            expected = "%3F" if char == "?" else char
            assert _encode_url_path(char) == expected, (
                f"字符 {char!r} 编码与契约表 v2 不符"
            )

    def test_question_mark_encoded_inside_path(self) -> None:
        """`?` 编码：URL 解析器分隔符防御——字面 `?` 会使数据库路径被截断
        （连接级截断行为见 test_data_dir_connection.py）"""
        assert _encode_url_path("dir?v1") == "dir%3Fv1"
        assert _encode_url_path("C:/a/b?c/d") == "C:/a/b%3Fc/d"

    def test_non_question_mark_chars_kept_verbatim(self) -> None:
        """非 `?` 字符一律原样：`~` 与空格/中文/#/% 同表（v2 无保留集概念，防过编码）"""
        assert _encode_url_path("a~b.c-d_e") == "a~b.c-d_e"
        assert _encode_url_path("a b#c%d~e") == "a b#c%d~e"


class TestPureStdlibGuard:
    """G4 守卫：子进程导入 data_dir，断言 sys.modules 无其它 backend.app.* 模块"""

    def test_subprocess_import_pulls_no_app_modules(self) -> None:
        repo_root = Path(__file__).resolve().parents[2]
        script = (
            "import sys;"
            "import backend.app.services.data_dir;"
            "imported = sorted(m for m in sys.modules if m == 'backend' or m.startswith('backend.'));"
            "allowed = ['backend', 'backend.app', 'backend.app.services', "
            "'backend.app.services.data_dir'];"
            "assert imported == allowed, imported;"
            "assert 'sqlalchemy' not in sys.modules and 'uvicorn' not in sys.modules;"
            "print('stdlib-only-ok')"
        )
        run = subprocess.run(
            [sys.executable, "-c", script],
            capture_output=True,
            text=True,
            encoding="utf-8",
            cwd=repo_root,
        )
        assert run.returncode == 0, run.stderr
        assert "stdlib-only-ok" in run.stdout
