"""
P6.4-2 单元测试 — 后端打包固化（backend/run_backend.py 启动器 + main.py _frontend_dir）

覆盖（Seam：公开函数边界；真实 PyInstaller 打包不做进单测，走工单真实运行步骤）：
    1. 启动器 CLI 参数解析：默认值 / 自定义 / 非法 port / 非法 log-level
    2. main 装配：CLI 参数 → uvicorn.run 透传（host/port/log-level/log_config）
    3. 日志落盘契约：数据目录解析（CONVER_DATA_DIR > %APPDATA% > 主目录兜底）、
       日志路径、log_config 含 file handler（不污染 uvicorn 全局配置）、dictConfig 后真实写入
    4. main 失败路径：日志目录不可用 / 端口越界 → 明确中文报错退出
    5. _frontend_dir 三分支：源码态 / frozen+_MEIPASS / frozen 无 _MEIPASS
    6. __main__ 入口真实运行冒烟（--help 子进程，不启动 uvicorn，无副作用）
    7. spec 配方锁定：前端运行所需子集随包分发（期末审核阻断2 防复发回归断言）

依赖：不触碰真实 %APPDATA%——一律 monkeypatch 环境变量指向 tmp_path。
"""

from __future__ import annotations

import ast
import logging
import logging.config
import subprocess
import sys
from pathlib import Path

import pytest
import uvicorn
from fastapi.testclient import TestClient

from backend.app.main import _frontend_dir
from backend.run_backend import build_log_config, build_parser, data_dir, log_file_path, main

__all__ = [
    "TestParser",
    "TestDataDir",
    "TestLogConfig",
    "TestMain",
    "TestFrontendDir",
    "TestEntrypoint",
    "TestSpecFrontendPackaging",
    "TestShellSpawnContract",
]


class TestParser:
    """CLI 参数解析：Tauri 壳会追加 `--host 127.0.0.1 --port <port> --log-level warning`"""

    def test_parse_defaults(self) -> None:
        args = build_parser().parse_args([])
        assert args.host == "127.0.0.1"
        assert args.port == 8000
        assert args.log_level == "warning"

    def test_parse_custom_values(self) -> None:
        args = build_parser().parse_args(
            ["--host", "0.0.0.0", "--port", "18081", "--log-level", "debug"]
        )
        assert args.host == "0.0.0.0"
        assert args.port == 18081
        assert args.log_level == "debug"

    def test_parse_invalid_port_exits(self, capsys: pytest.CaptureFixture[str]) -> None:
        """非法 port（非整数）→ argparse 报错退出（SystemExit 2）"""
        with pytest.raises(SystemExit) as exc:
            build_parser().parse_args(["--port", "abc"])
        assert exc.value.code == 2
        assert "invalid int value" in capsys.readouterr().err

    def test_parse_invalid_log_level_exits(self, capsys: pytest.CaptureFixture[str]) -> None:
        """非法 log-level → argparse choices 报错退出（SystemExit 2）"""
        with pytest.raises(SystemExit) as exc:
            build_parser().parse_args(["--log-level", "verbose"])
        assert exc.value.code == 2
        assert "invalid choice" in capsys.readouterr().err


class TestDataDir:
    """数据目录契约（契约表 v2，委托 backend.app.services.data_dir；Rust 侧镜像见
    src-tauri/tests/server_test.rs，同一版本号互引）：
    CONVER_DATA_DIR（非空）覆盖 > %APPDATA%\\ConverSystem > home\\AppData\\Roaming\\ConverSystem"""

    def test_env_override(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        monkeypatch.setenv("APPDATA", str(tmp_path / "appdata"))
        assert data_dir() == tmp_path

    def test_appdata_default(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.delenv("CONVER_DATA_DIR", raising=False)
        monkeypatch.setenv("APPDATA", str(tmp_path))
        assert data_dir() == tmp_path / "ConverSystem"

    def test_home_fallback(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """APPDATA 缺失（罕见）→ home\\AppData\\Roaming\\ConverSystem（决策 D1-D2 兜底统一 = T-01 修复本身）"""
        monkeypatch.delenv("CONVER_DATA_DIR", raising=False)
        monkeypatch.delenv("APPDATA", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        assert data_dir() == tmp_path / "AppData" / "Roaming" / "ConverSystem"

    def test_empty_env_treated_as_unset(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """契约表 v2：CONVER_DATA_DIR="" 视为未设置（与壳侧 var_os 非空判定对齐）"""
        monkeypatch.setenv("CONVER_DATA_DIR", "")
        monkeypatch.setenv("APPDATA", str(tmp_path))
        assert data_dir() == tmp_path / "ConverSystem"

    def test_log_file_path_under_data_dir(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        assert log_file_path() == tmp_path / "backend.log"


class TestLogConfig:
    """日志落盘契约：uvicorn 默认配置 + backend.log FileHandler"""

    def test_file_handler_wired(self, tmp_path: Path) -> None:
        log_file = tmp_path / "backend.log"
        cfg = build_log_config(log_file)
        assert cfg["handlers"]["file"] == {
            "class": "logging.FileHandler",
            "filename": str(log_file),
            "mode": "a",
            "encoding": "utf-8",
            "formatter": "default",
        }
        # uvicorn 与 uvicorn.access 挂 file handler；控制台 handler 保留（源码模式仍可见）
        assert "file" in cfg["loggers"]["uvicorn"]["handlers"]
        assert "default" in cfg["loggers"]["uvicorn"]["handlers"]
        assert "file" in cfg["loggers"]["uvicorn.access"]["handlers"]
        # uvicorn.error 无独立 handler：经 propagate 汇入 uvicorn，避免重复落盘
        assert "file" not in cfg["loggers"]["uvicorn.error"].get("handlers", [])

    def test_no_global_config_pollution(self, tmp_path: Path) -> None:
        """回归锁定：build_log_config 深拷贝 uvicorn 全局 LOGGING_CONFIG，不得污染"""
        build_log_config(tmp_path / "backend.log")
        assert "file" not in uvicorn.config.LOGGING_CONFIG["handlers"]
        assert "file" not in uvicorn.config.LOGGING_CONFIG["loggers"]["uvicorn"]["handlers"]

    def test_writes_to_file(self, tmp_path: Path) -> None:
        """dictConfig 后 uvicorn logger 真实写入落盘文件（含中文，utf-8）"""
        log_file = tmp_path / "backend.log"
        logging.config.dictConfig(build_log_config(log_file))
        try:
            logging.getLogger("uvicorn.error").error("落盘测试消息-abc123")
            logging.getLogger("uvicorn.access").info("访问日志-xyz789")
        finally:
            # 清理：摘除 file handler，避免污染其他测试的 uvicorn logger 全局状态
            for name in ("uvicorn", "uvicorn.access"):
                logger = logging.getLogger(name)
                logger.handlers[:] = [
                    h for h in logger.handlers if not isinstance(h, logging.FileHandler)
                ]
        text = log_file.read_text(encoding="utf-8")
        assert "落盘测试消息-abc123" in text
        assert "访问日志-xyz789" in text


class TestMain:
    """main 装配：CLI 参数 → uvicorn.run 透传；失败路径给出明确中文报错"""

    def test_passes_cli_args_to_uvicorn(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """stub uvicorn.run 验证装配：host/port/log-level/log_config 全部透传"""
        from backend.app.main import app as backend_app

        calls: list[dict[str, object]] = []

        def fake_run(app: object, **kwargs: object) -> None:
            calls.append({"app": app, **kwargs})

        monkeypatch.setattr(uvicorn, "run", fake_run)
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        main(["--host", "127.0.0.1", "--port", "18099", "--log-level", "warning"])
        assert len(calls) == 1
        call = calls[0]
        assert call["app"] is backend_app
        assert call["host"] == "127.0.0.1"
        assert call["port"] == 18099
        assert call["log_level"] == "warning"
        log_config = call["log_config"]
        assert isinstance(log_config, dict)
        assert log_config["handlers"]["file"]["filename"] == str(tmp_path / "backend.log")

    def test_creates_log_dir_if_missing(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """数据目录不存在时 main 先建目录再启动"""
        monkeypatch.setattr(uvicorn, "run", lambda app, **kwargs: None)
        target = tmp_path / "a" / "b"
        monkeypatch.setenv("CONVER_DATA_DIR", str(target))
        main([])
        assert target.is_dir()

    def test_log_dir_is_file_raises(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Falsify：日志目录被文件占用 → 明确中文报错退出，而非静默崩溃"""
        blocked = tmp_path / "blocked"
        blocked.write_text("被文件占用", encoding="utf-8")
        monkeypatch.setenv("CONVER_DATA_DIR", str(blocked))
        with pytest.raises(SystemExit, match="日志目录不可用"):
            main([])

    def test_port_out_of_range_raises(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Falsify：端口越界 → 明确中文报错退出（uvicorn ConfigError 前的早期拦截）"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        with pytest.raises(SystemExit, match="端口超出范围"):
            main(["--port", "99999"])

    def test_startup_failure_writes_traceback_to_log(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """排障契约：启动失败（frozen 下 import/绑定失败等）traceback 必须留痕日志文件"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))

        def boom(app: object, **kwargs: object) -> None:
            raise RuntimeError("模拟启动失败")

        monkeypatch.setattr(uvicorn, "run", boom)
        with pytest.raises(RuntimeError, match="模拟启动失败"):
            main([])
        log_text = (tmp_path / "backend.log").read_text(encoding="utf-8")
        assert "Traceback" in log_text and "模拟启动失败" in log_text


class TestFrontendDir:
    """_frontend_dir 三分支：源码态 / frozen+_MEIPASS / frozen 无 _MEIPASS"""

    def test_source_mode(self) -> None:
        """非 frozen：源码路径（仓库根 frontend），与打包前行为一致"""
        expected = Path(__file__).resolve().parents[2] / "frontend"
        assert _frontend_dir() == expected

    def test_frozen_meipass(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """frozen + _MEIPASS：指向 _MEIPASS/frontend"""
        monkeypatch.setattr(sys, "frozen", True, raising=False)
        monkeypatch.setattr(sys, "_MEIPASS", str(tmp_path), raising=False)
        assert _frontend_dir() == tmp_path / "frontend"

    def test_frozen_without_meipass(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """frozen 但无 _MEIPASS（极端）：回退 exe 同目录/frontend"""
        monkeypatch.setattr(sys, "frozen", True, raising=False)
        monkeypatch.delattr(sys, "_MEIPASS", raising=False)
        monkeypatch.setattr(sys, "executable", str(tmp_path / "conver_backend.exe"), raising=False)
        assert _frontend_dir() == tmp_path / "frontend"


class TestEntrypoint:
    """__main__ 入口真实运行冒烟（--help 不启动 uvicorn，无副作用）"""

    def test_help_subprocess(self) -> None:
        """python backend/run_backend.py 与 python -m backend.run_backend 两种形态都可用"""
        repo_root = Path(__file__).resolve().parents[2]
        script = repo_root / "backend" / "run_backend.py"
        commands = (
            [sys.executable, str(script)],
            [sys.executable, "-m", "backend.run_backend"],
        )
        for cmd in commands:
            run = subprocess.run(
                cmd + ["--help"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                cwd=repo_root,
            )
            assert run.returncode == 0, run.stderr
            assert "--host" in run.stdout and "--port" in run.stdout
            assert "--log-level" in run.stdout


class TestSpecFrontendPackaging:
    """conver_backend.spec 配方锁定：前端运行所需子集随包分发（期末审核阻断2 防复发）。

    阻断2 背景：datas=[] 不打包 frontend → 打包态 GET / 404（boot.html 跳转根路径
    用户看到 Not Found）。此断言锁定 datas 必须含 frontend 运行子集，且不得回退为
    全目录打包（node_modules 55M 必须排除）。
    """

    #: spec 文件路径（backend/conver_backend.spec）
    SPEC_PATH = Path(__file__).resolve().parents[1] / "conver_backend.spec"

    def test_spec_ships_frontend_runtime_assets(self) -> None:
        """datas 含 index.html 与 css/js 挂载，目标目录 frontend/ 与 _frontend_dir 对齐"""
        spec_text = self.SPEC_PATH.read_text(encoding="utf-8")
        # 接线断言（复审强化）：datas 必须引用 _FRONTEND_RUNTIME——原始阻断形态
        # `datas=[]` 不改定义、只改接线行，token 断言会漏报，此处锁定接线。
        assert "datas=list(_FRONTEND_RUNTIME)" in spec_text, "spec datas 接线必须引用 _FRONTEND_RUNTIME"
        # datas 源码形态（Path 拼接）：运行子集必须全部挂载
        # （assets 为空目录 git 不跟踪，不在此列；有内容时 spec 需追加挂载并同步本断言）
        for token in (
            '"frontend" / "index.html"',
            '"frontend" / "css"',
            '"frontend" / "js"',
            '"frontend" / "simulators"',
        ):
            assert token in spec_text, f"spec datas 缺少前端子集 {token}"
        # 挂载目标目录：index.html 必须落在 frontend/ 根（StaticFiles html=True 的入口）
        assert '"frontend"),' in spec_text

    def test_spec_excludes_node_modules_and_tests(self) -> None:
        """防回退：不得整目录打包 frontend/（node_modules 55M）或显式挂载 tests"""
        spec_text = self.SPEC_PATH.read_text(encoding="utf-8")
        # 整目录挂载形态 `…/ "frontend"), "frontend"` 会把 node_modules 整棵拖入
        assert '"frontend"), "frontend"' not in spec_text
        assert '"frontend/node_modules"' not in spec_text
        assert '"frontend/tests"' not in spec_text

    def test_runtime_datas_align_with_real_frontend_dir(self) -> None:
        """行为级：_FRONTEND_RUNTIME 定义挂载的每个源路径真实存在于 frontend/ 运行子集

        在 token/接线断言之上叠加：token 断言匹配「文本出现」，若定义漂移（变量
        改名后接线同步改名、或定义指向不存在/错误路径）token 仍可能全匹配。
        本测试解析定义本身（AST 提取 datas 元素）并与真实目录对齐——入口/样式/
        脚本在列、node_modules/tests 不在列、index.html 挂 frontend/ 根。
        """
        datas = _spec_runtime_datas(self.SPEC_PATH)
        assert datas, "_FRONTEND_RUNTIME 定义不得为空"
        frontend = _frontend_dir()
        assert frontend.is_dir(), f"frontend/ 目录不存在：{frontend}"
        sources = [src for src, _ in datas]
        for src in sources:
            assert src.exists(), f"datas 挂载的源路径在 frontend/ 中不存在：{src}"
            assert src.is_relative_to(frontend), f"datas 挂载源必须在 frontend/ 下：{src}"
        # 入口/样式/脚本在列
        for required in (frontend / "index.html", frontend / "css", frontend / "js"):
            assert required in sources, f"datas 运行子集缺少 {required}"
        # node_modules/tests 不在列
        assert not any(s.is_relative_to(frontend / "node_modules") for s in sources)
        assert not any(s.is_relative_to(frontend / "tests") for s in sources)
        # 挂载目标对齐 _frontend_dir：index.html 必须落在 frontend/ 根（StaticFiles 入口）
        targets = {t for _, t in datas}
        assert {"frontend", "frontend/css", "frontend/js"} <= targets

    def test_frontend_runtime_dirs_all_shipped(self) -> None:
        """反向防漂移：frontend/ 下新增运行目录必须进 _FRONTEND_RUNTIME 打包面

        教训（2026-08-14）：simulators/ 模块加入 frontend/ 时未同步打包清单，
        桌面版（PyInstaller 打包态）应用内游戏列表为空，网页版正常——单向校验
        （spec 声明的源路径都存在）拦不住「新增目录未声明」方向。本测试枚举
        frontend/ 实际目录与 spec datas 源路径做差集，新增运行目录漏打包即红。
        """
        datas = _spec_runtime_datas(self.SPEC_PATH)
        frontend = _frontend_dir()
        assert frontend.is_dir(), f"frontend/ 目录不存在：{frontend}"
        sources = {src for src, _ in datas}
        # 打包面排除：构建/测试/生成物目录
        excluded = {"node_modules", "tests", "coverage"}
        for d in frontend.iterdir():
            if not d.is_dir() or d.name in excluded:
                continue
            if d.name == "assets":
                # assets 为空目录（git 不跟踪）不挂载；有内容时必须进 spec
                if not any(d.iterdir()):
                    continue
            assert d in sources, (
                f"frontend/{d.name} 目录未进 _FRONTEND_RUNTIME 打包面——新增运行资源目录"
                f"必须同步 spec（教训 2026-08-14：simulators 漏打包致桌面版游戏列表为空）"
            )


class TestShellSpawnContract:
    """壳追加 argv / 就绪路径契约（RS-1 R1，与壳侧互引）：

    壳侧镜像实现见 src-tauri/src/server.rs `spawn_arguments` / `READY_PROBE_PATH`，
    cargo 契约锁见 src-tauri/tests/server_test.rs——两端互引锁死同一契约。
    票面修正注记：后端 `--host` 默认实为 127.0.0.1 与壳一致（0.0.0.0 只是
    test_parse_custom_values 的测试样例）；真实缺口 = 契约无测试钉住。
    """

    def test_shell_argv_shape_parses(self) -> None:
        """壳 spawn_arguments 精确形状（顺序敏感）喂 build_parser → 全部正确解析"""
        args = build_parser().parse_args(
            ["--host", "127.0.0.1", "--port", "8123", "--log-level", "warning"]
        )
        assert args.host == "127.0.0.1"
        assert args.port == 8123
        assert args.log_level == "warning"

    def test_models_route_exists(self) -> None:
        """就绪探测路径 /api/models 必须真实可 GET 200（壳 http_probe 的命中目标）

        路由删除 / 前缀漂移都会让壳就绪探测永远失败（就绪页卡死）。
        行为级断言（TestClient wire，仓库先例 test_error_handler.py）：
        http_probe 的就绪判定条件就是「HTTP/1.x 200」——这里直接钉住该条件。
        （注意：FastAPI 0.139 include_router 为惰性 _IncludedRouter，
        app.routes 扫描不到扁平 path，故用真实请求验证而非路由表扫描。）
        """
        from backend.app.main import app

        resp = TestClient(app).get("/api/models")
        assert resp.status_code == 200, f"/api/models 应可 GET 200，实际 {resp.status_code}"


def _spec_runtime_datas(spec_path: Path) -> list[tuple[Path, str]]:
    """解析 spec 文本中 _FRONTEND_RUNTIME 定义，返回 [(源路径, 挂载目标)]

    AST 提取而非正则：变量改名（接线与定义同步改名）时找不到该名字 → 显式失败，
    防「token 匹配但定义漂移」。源路径表达式为 `str(ROOT / "…" / "…")` 形态
    （Path 拼接按字符串 token 归一），ROOT 按 spec 自身定义（Path(SPECPATH).parent）
    绑定为 spec 所在目录的上级（仓库根）；不执行 spec 中的任意代码。
    """
    tree = ast.parse(spec_path.read_text(encoding="utf-8"))
    root = spec_path.resolve().parent.parent
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id == "_FRONTEND_RUNTIME":
                if not isinstance(node.value, ast.Tuple):
                    raise AssertionError("_FRONTEND_RUNTIME 定义必须是元组")
                datas: list[tuple[Path, str]] = []
                for el in node.value.elts:
                    if not isinstance(el, ast.Tuple) or len(el.elts) != 2:
                        raise AssertionError(
                            f"_FRONTEND_RUNTIME 元素必须是 (源, 目标) 二元组：{ast.dump(el)}"
                        )
                    mount = el.elts[1]
                    if not isinstance(mount, ast.Constant) or not isinstance(mount.value, str):
                        raise AssertionError(f"挂载目标必须是字符串常量：{ast.dump(mount)}")
                    datas.append((_datas_source_path(el.elts[0], root), mount.value))
                return datas
    raise AssertionError("spec 中未找到 _FRONTEND_RUNTIME 定义（变量被改名或删除？）")


def _datas_source_path(expr: ast.expr, root: Path) -> Path:
    """把 datas 源路径表达式还原为真实路径（Path 拼接形态按字符串 token 归一）

    只接受 `str(ROOT / "…" / "…")` 形态（spec 既有写法）；其他形态显式失败，
    提示同步本测试——防「token 匹配但定义漂移」。
    """
    if (
        isinstance(expr, ast.Call)
        and isinstance(expr.func, ast.Name)
        and expr.func.id == "str"
        and len(expr.args) == 1
    ):
        expr = expr.args[0]
    tokens: list[str] = []

    def walk(node: ast.AST) -> None:
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
            walk(node.left)
            walk(node.right)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str):
            tokens.append(node.value)
        elif isinstance(node, ast.Name) and node.id == "ROOT":
            tokens.append(str(root))
        else:
            raise AssertionError(f"不支持的数据源表达式：{ast.dump(node)}")

    walk(expr)
    return Path(*tokens)
