"""
manifest 读写工具（T-02 拆分自 simulator_store）

manifest 种子后幂等标记（spec T-02 决策 3）：
    manifest 存在 = 视为已种子（标记语义，数据目录为唯一事实来源）。
    全新目录整目录拷贝，manifest **最后**落盘（半拷中断语义见模块 docstring）。

原子写契约（工单 02 声明底座，工单 03 读-改-写原子追加复用）：
    `read_manifest` 读取解析；`write_manifest` 同目录临时文件 + os.replace
    原子替换（ensure_ascii=False 中文保真，version 字段由调用方保持）；
    `append_manifest_entry` 追加注册，manifest 缺失/损坏以磁盘现存 .html
    自愈重建（数据目录为唯一事实来源）。
    单用户桌面应用串行（spec Further Notes：并发导入不引入锁，记录判断）。

G4 约束：本模块仅 stdlib import（json/logging/os/pathlib），
与 data_dir 同层——不引入 app 业务代码。
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

__all__ = [
    "MANIFEST_FILE",
    "MANIFEST_TMP_SUFFIX",
    "read_manifest",
    "write_manifest",
    "append_manifest_entry",
    "update_manifest_entry",
]

logger = logging.getLogger(__name__)

#: 数据目录 simulators 下的清单文件名（前端 MANIFEST_URL 恒为 simulators/manifest.json）
MANIFEST_FILE = "manifest.json"
#: 原子写临时文件后缀（同目录临时文件 + os.replace；固定名，单用户串行无锁）
MANIFEST_TMP_SUFFIX = ".tmp"


def _current_write_manifest() -> None:
    """读取当前 write_manifest 实现（写操作入口）。

    回归锚 monkeypatch `simulator_store.write_manifest` 模拟注册失败回滚路径，
    append/_read_manifest_or_rebuild 的写操作按调用期从 simulator_store 解析
    （延迟导入，规避模块级循环引用）；未打补丁时即本模块自身的 write_manifest。
    """
    from backend.app.services import simulator_store  # type: ignore[import-untyped]
    return simulator_store.write_manifest


def read_manifest(sim_dir: Path) -> dict:
    """读取 sim_dir/manifest.json 并解析为 dict；文件不存在 → FileNotFoundError。"""
    with open(sim_dir / MANIFEST_FILE, encoding="utf-8") as fh:
        return json.load(fh)


def write_manifest(sim_dir: Path, manifest: dict) -> None:
    """原子写 sim_dir/manifest.json：同目录临时文件 + os.replace（UTF-8 明文，中文保真）。

    目录缺失自动创建（parents）；manifest 非 dict → TypeError（显式 isinstance
    校验，与 docstring 契约一致——json.dumps 对字符串等类型不抛，须前置拦截）；
    写入失败时旧 manifest 保持原样（os.replace 原子替换保证），临时文件残留
    无害（读取方只消费 manifest.json）。
    """
    if not isinstance(manifest, dict):
        raise TypeError(f"manifest 必须是 dict，收到 {type(manifest).__name__}")
    sim_dir.mkdir(parents=True, exist_ok=True)
    tmp = sim_dir / (MANIFEST_FILE + MANIFEST_TMP_SUFFIX)
    tmp.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    os.replace(tmp, sim_dir / MANIFEST_FILE)


def append_manifest_entry(sim_dir: Path, entry: dict) -> None:
    """manifest 读-改-写原子追加：合法则既有条目原样保留；缺失/损坏 → 以磁盘
    现存 .html 自愈重建（version=2，type=local 降级）再追加。"""
    manifest = _read_manifest_or_rebuild(sim_dir)
    manifest["simulators"].append(entry)
    _current_write_manifest()(sim_dir, manifest)


def update_manifest_entry(sim_dir: Path, entry_id: str, **updates: object) -> dict:
    """读-改-写原子更新 manifest 条目（按 id 定位，仅更新给定字段）。

    Args:
        sim_dir: 数据目录 simulators
        entry_id: 条目 id（manifest 结构性唯一）
        **updates: 要更新的字段（如 type="ai", config={...}, endpointMode="full"）

    Returns:
        更新后的条目 dict

    Raises:
        KeyError: 条目 id 不存在
    """
    manifest = _read_manifest_or_rebuild(sim_dir)
    for entry in manifest["simulators"]:
        if entry.get("id") == entry_id:
            entry.update(updates)
            _current_write_manifest()(sim_dir, manifest)
            return dict(entry)
    raise KeyError(f"游戏不存在：{entry_id}")


def _read_manifest_or_rebuild(sim_dir: Path, persist: bool = False) -> dict:
    """读取 manifest；缺失或损坏 → 磁盘重建兜底。

    损坏口径（F-8 定版）：非法 JSON / 非 UTF-8 / 合法 JSON 但结构非预期
    （顶层非 dict 或 simulators 非 list——如字符串/字典/None）一律视为损坏
    重建；F-15 定版：读取路径 OSError 族（manifest.json 被替换为同名目录 →
    open 抛 IsADirectoryError、不可读 → PermissionError——读不了即损坏语义）
    同样并入自愈，否则 `_existing_ids` 迭代 dict/str 抛 TypeError、
    `append_manifest_entry` 的 `.append` 抛 AttributeError → 500（原子写保证
    正常运行不产生此类损坏，需手工损坏 manifest 触发；条目级字段不做校验，
    范围收敛）。persist=True 时重建结果立即原子落盘（import_game 先自愈再算
    id：避免「id 唯一化用瞬态重建、append 用磁盘重建（此时已含新落盘文件）」
    两次重建口径不一致产生退化重复条目）；落盘写失败（如目录形态仍阻挡
    os.replace）按既有契约抛出明确 OSError——写路径在 except 之外不受影响。
    """
    try:
        manifest = read_manifest(sim_dir)
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        manifest = None
    if not isinstance(manifest, dict) or not isinstance(manifest.get("simulators"), list):
        rebuilt = _rebuild_manifest(sim_dir)
        if persist:
            _current_write_manifest()(sim_dir, rebuilt)
        return rebuilt
    return manifest


def _rebuild_manifest(sim_dir: Path) -> dict:
    """以现存 .html 文件重建 manifest（自愈：数据目录为唯一事实来源）。

    条目：id=文件名干 slug（冲突 -2/-3 唯一化，保证结构性唯一）、file/name
    取实际文件名、type=local（重建为降级态，不逐文件探测）。"""
    # 函数级延迟导入避免循环引用：simulator_manifest → simulator_import → simulator_manifest
    from backend.app.services.simulator_import import slugify  # type: ignore[import-untyped]

    sim_dir.mkdir(parents=True, exist_ok=True)
    simulators: list[dict] = []
    seen: set[str] = set()
    for path in sorted(p for p in sim_dir.iterdir() if p.is_file() and p.suffix.lower() == ".html"):
        stem = path.stem
        base = slugify(stem)
        gid = base
        n = 2
        while gid in seen:
            gid = f"{base}-{n}"
            n += 1
        seen.add(gid)
        simulators.append({"id": gid, "file": path.name, "name": stem, "type": "local"})
    return {"version": 2, "simulators": simulators}