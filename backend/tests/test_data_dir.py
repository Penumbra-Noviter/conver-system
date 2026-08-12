"""
ARC9-T04 单元测试 — 数据目录共享模块契约（backend/app/services/data_dir.py）

契约表 v1（双端镜像；Rust 侧 src-tauri/tests/server_test.rs 同一版本号互引，防漂移）：

    1. 解析链（resolve，三端一致）：
       CONVER_DATA_DIR（环境变量，**非空串才生效**，空串视为未设置）
       → %APPDATA%\\ConverSystem
       → home\\AppData\\Roaming\\ConverSystem（APPDATA 缺失兜底，决策 D1-D2）
    2. URL 编码（壳侧 database_url 契约；Python 基准 = urllib.parse.quote(s, safe="/:")）：
       # → %23、? → %3F、% → %25、空格 → %20、非 ASCII（中文）→ UTF-8 逐字节 %XX；
       保留不编码：A-Z a-z 0-9 _ - . ~ / :（`~` 亦保留，属 RFC3986 unreserved）。
    3. G4 守卫：data_dir 模块仅 stdlib import，导入链不得拉入其它 backend.app.* 模块。

冒烟脚本（scripts/smoke-desktop.ps1 74-81 段）为显式例外（决策 D1-D4）：
冒烟是断言环境而非解析器，APPDATA 缺失即环境错误 → throw，不参与本契约的兜底链。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

import pytest

from backend.app.services import data_dir as data_dir_service

__all__ = [
    "TestResolveContract",
    "TestUrlEncodingReference",
    "TestPureStdlibGuard",
]

#: 契约表 v1 保留集（编码补集的边界，与 Rust 侧逐字符用例同一数据来源）
_KEEP_SET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~/:"


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
        """契约表 v1：resolve 不编码——含 #/?/空格/中文的 CONVER_DATA_DIR 原样返回

        编码是壳侧 database_url 的职责（见 TestUrlEncodingReference 与 Rust 镜像用例）；
        resolve 返回的 Path 必须与用户给定值逐字符一致，否则迁移/日志会写到错误位置。
        """
        special = tmp_path / "Conver 数据#目录?v1%"
        monkeypatch.setenv("CONVER_DATA_DIR", str(special))
        monkeypatch.setenv("APPDATA", str(tmp_path / "ignored"))
        assert data_dir_service.data_dir() == special

    def test_empty_env_treated_as_unset(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """契约表 v1：CONVER_DATA_DIR="" 视为未设置（与壳侧 var_os 非空判定对齐）"""
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
        """契约表 v1（决策 D1-D2）：APPDATA 缺失 → home\\AppData\\Roaming\\ConverSystem

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
    """契约表 v1 编码参考（Python 侧基准）：钉住 quote(safe="/:") 的补集边界。

    这些字面量即 Rust 侧 encode_url_path 逐字符用例的期望值来源（镜像契约）；
    若 stdlib 行为漂移，本组用例先红，双端同步修正契约表版本号。
    """

    def test_headline_cases(self) -> None:
        assert quote("a#b?c%d e", safe="/:") == "a%23b%3Fc%25d%20e"
        assert quote("数据 目录", safe="/:") == "%E6%95%B0%E6%8D%AE%20%E7%9B%AE%E5%BD%95"
        assert quote("C:/Users/x/AppData/Roaming/Conver System", safe="/:") == (
            "C:/Users/x/AppData/Roaming/Conver%20System"
        )

    def test_ascii_keep_set_boundary(self) -> None:
        """逐字符钉住补集边界：保留集 = _KEEP_SET，其余 ASCII 一律 %XX（大写字面量）"""
        for code in range(128):
            char = chr(code)
            if char in _KEEP_SET:
                assert quote(char, safe="/:") == char, f"保留字符 {char!r} 不应被编码"
            else:
                assert quote(char, safe="/:") == f"%{code:02X}", f"字符 {char!r} 应编码为 %{code:02X}"

    def test_tilde_is_kept(self) -> None:
        """`~` 属 RFC3986 unreserved，Python quote 恒保留——Rust 侧必须同表（防过编码）"""
        assert quote("a~z", safe="/:") == "a~z"


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
