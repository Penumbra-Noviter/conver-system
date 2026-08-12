"""Conver System 后端启动器（PyInstaller onedir 打包入口，SPK-R1 spike 结论落地）。

PyInstaller 入口必须是可执行脚本（backend.app.main 无 __main__ 块）；
uvicorn.run 直传 app 对象，规避 frozen 环境下 import-string 解析差异。

日志落盘契约：Tauri 以 CREATE_NO_WINDOW 启动（console=True 的 stdout 无处可去），
uvicorn 日志必须写入数据目录 backend.log——否则排障无据。数据目录默认
%APPDATA%\\ConverSystem\\，可用 CONVER_DATA_DIR 环境变量覆盖（与 P6.4-3
迁移脚本同一契约）。

用法（网页版源码模式不受影响——不经过本启动器）：
    python -m backend.run_backend [--host 127.0.0.1] [--port 8000] [--log-level warning]
"""

from __future__ import annotations

import argparse
import copy
import traceback
from pathlib import Path
from typing import Sequence

import uvicorn

__all__ = ["build_log_config", "build_parser", "data_dir", "log_file_path", "main"]

#: 后端日志文件名（位于数据目录）
LOG_FILE_NAME = "backend.log"
#: 需要落盘的 uvicorn logger（uvicorn.error 无独立 handler，经 propagate 汇入 uvicorn，不重复挂）
_UVICORN_LOGGERS = ("uvicorn", "uvicorn.access")


def data_dir() -> Path:
    """桌面版数据目录：委托 `backend.app.services.data_dir`（同一契约，契约表 v1）。

    覆盖链：`CONVER_DATA_DIR`（非空）→ `%APPDATA%\\ConverSystem` →
    `home\\AppData\\Roaming\\ConverSystem`（决策 D1-D2 兜底统一）。
    契约表 v1 全文见 backend/tests/test_data_dir.py；壳侧 Rust 镜像实现见
    src-tauri/src/server.rs `default_data_dir`。
    （延迟导入：直执行 `python backend/run_backend.py --help` 时仓库根不在 sys.path，
    与下方 `from backend.app.main import app` 同一规避模式。）
    """
    from backend.app.services.data_dir import data_dir as resolve

    return resolve()


def log_file_path() -> Path:
    """后端日志文件路径：数据目录\\backend.log（委托 data_dir_file，同一契约）。"""
    from backend.app.services.data_dir import data_dir_file

    return data_dir_file(LOG_FILE_NAME)


def build_parser() -> argparse.ArgumentParser:
    """构造 CLI 参数解析器（Tauri 壳会追加 `--host 127.0.0.1 --port <port> --log-level warning`）"""
    parser = argparse.ArgumentParser(
        prog="conver-backend",
        description=(
            "Conver System 后端启动器（PyInstaller onedir 入口；"
            "uvicorn 日志落盘至数据目录 backend.log）"
        ),
    )
    parser.add_argument("--host", default="127.0.0.1", help="监听地址（默认 127.0.0.1）")
    parser.add_argument("--port", type=int, default=8000, help="监听端口（默认 8000）")
    parser.add_argument(
        "--log-level",
        default="warning",
        choices=uvicorn.config.LOG_LEVELS,  # 单一事实来源：与 uvicorn 支持的级别同步
        help="日志级别（默认 warning）",
    )
    return parser


def build_log_config(log_file: Path) -> dict:
    """构造 uvicorn 日志配置：保留默认控制台输出，并追加 backend.log 落盘 handler。

    以 uvicorn.config.LOGGING_CONFIG 为基底深拷贝（不得污染全局配置），
    追加 file handler 并挂到 uvicorn / uvicorn.access 两个 logger；
    uvicorn.error 经 propagate 汇入 uvicorn，由 uvicorn 的 file handler 统一落盘，不重复写。
    """
    log_config = copy.deepcopy(uvicorn.config.LOGGING_CONFIG)
    log_config["handlers"]["file"] = {
        "class": "logging.FileHandler",
        "filename": str(log_file),
        "mode": "a",
        "encoding": "utf-8",
        "formatter": "default",
    }
    for name in _UVICORN_LOGGERS:
        logger_cfg = log_config["loggers"].get(name)
        if logger_cfg is None:
            continue
        handlers = logger_cfg.setdefault("handlers", [])
        if "file" not in handlers:
            handlers.append("file")
    return log_config


def main(argv: Sequence[str] | None = None) -> None:
    """CLI 入口：解析参数 → 准备日志落盘 → 直传 app 对象启动 uvicorn。"""
    args = build_parser().parse_args(argv)
    if not 0 <= args.port <= 65535:
        raise SystemExit(f"端口超出范围（0-65535）：{args.port}")
    log_file = log_file_path()
    try:
        log_file.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise SystemExit(f"日志目录不可用：{log_file.parent}（{exc}）") from exc
    try:
        from backend.app.main import app  # 直传对象，规避 frozen 下 import-string 差异

        uvicorn.run(
            app,
            host=args.host,
            port=args.port,
            log_level=args.log_level,
            log_config=build_log_config(log_file),
        )
    except Exception:
        # 排障契约：启动失败（frozen 下 import 失败 / 端口占用等）必须留痕——
        # CREATE_NO_WINDOW 下 stderr 无处可去，traceback 追加写入日志文件后重抛。
        with log_file.open("a", encoding="utf-8") as fh:
            fh.write(traceback.format_exc())
        raise


if __name__ == "__main__":
    main()
