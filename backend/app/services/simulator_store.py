"""
模拟器数据存储（T-02：首启种子 + manifest 工具；工单 03 导入族继续扩展）

首启种子契约（spec T-02 决策 3 + 工单 02）：

    1. 种子标记 = 数据目录 simulators 的 manifest.json 存在（幂等；不做逐文件
       自愈，用户删了就是删了——尊重用户管理，数据目录为唯一事实来源）。
    2. 全新目录：从内置目录整目录拷贝（html + manifest 字节一致）。
    3. manifest **最后**落盘：中断于 manifest 之前 → 下次启动重种；中断于
       manifest 之后 → 视为已种子（标记语义，不逐文件修复）。
    4. 种子源缺失（打包态文件缺失）→ 降级不崩溃（返回 False，不建目录）；
       数据目录不可写 → 抛出带路径的明确 OSError（启动期可闻，不静默吞掉）。

manifest 工具（工单 02 声明底座，工单 03 读-改-写原子追加复用）：
    `read_manifest` 读取解析；`write_manifest` 同目录临时文件 + os.replace
    原子替换（ensure_ascii=False 中文保真，version 字段由调用方保持）。
    单用户桌面应用串行（spec Further Notes：并发导入不引入锁，记录判断）。

G4 约束：本模块仅 stdlib import（json/logging/os/shutil/pathlib），与 data_dir
同层——工单 03 导入族在此继续扩展，不引入 app 业务代码。
"""

from __future__ import annotations

import json
import logging
import os
import shutil
from pathlib import Path

__all__ = [
    "MANIFEST_FILE",
    "MANIFEST_TMP_SUFFIX",
    "ensure_seeded",
    "read_manifest",
    "write_manifest",
]

logger = logging.getLogger(__name__)

#: 数据目录 simulators 下的清单文件名（前端 MANIFEST_URL 恒为 simulators/manifest.json）
MANIFEST_FILE = "manifest.json"
#: 原子写临时文件后缀（同目录临时文件 + os.replace；固定名，单用户串行无锁）
MANIFEST_TMP_SUFFIX = ".tmp"


def ensure_seeded(builtin_dir: Path, target_dir: Path) -> bool:
    """首启种子：target_dir 缺 manifest → 从 builtin_dir 整目录拷贝（含 manifest）。

    返回 True 表示本次执行了种子拷贝；False 表示已种子（标记存在）或种子源缺失
    （降级不崩溃，不创建 target_dir）。数据目录不可写 → 抛明确 OSError（含路径）。
    拷贝范围：builtin_dir 下的文件条目（html + manifest；目录条目跳过——
    内置种子源当前纯文件形态）。
    """
    if not builtin_dir.is_dir():
        logger.warning("模拟器种子源缺失，跳过首启种子：%s", builtin_dir)
        return False
    if (target_dir / MANIFEST_FILE).exists():
        return False
    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        copied = 0
        for entry in builtin_dir.iterdir():
            if entry.name == MANIFEST_FILE or not entry.is_file():
                continue
            shutil.copy2(entry, target_dir / entry.name)
            copied += 1
        # manifest 最后落盘：种子标记最晚生效（半拷中断语义见模块 docstring）
        shutil.copy2(builtin_dir / MANIFEST_FILE, target_dir / MANIFEST_FILE)
    except OSError as exc:
        raise OSError(
            f"模拟器数据目录不可用，无法写入种子：{target_dir}（{exc}）"
        ) from exc
    logger.info("首启种子完成：%s → %s（%d 款游戏 + manifest）", builtin_dir, target_dir, copied)
    return True


def read_manifest(sim_dir: Path) -> dict:
    """读取 sim_dir/manifest.json 并解析为 dict；文件不存在 → FileNotFoundError。"""
    with open(sim_dir / MANIFEST_FILE, encoding="utf-8") as fh:
        return json.load(fh)


def write_manifest(sim_dir: Path, manifest: dict) -> None:
    """原子写 sim_dir/manifest.json：同目录临时文件 + os.replace（UTF-8 明文，中文保真）。

    目录缺失自动创建（parents）；manifest 非 dict → TypeError（json.dumps 语义，
    调用方契约）；写入失败时旧 manifest 保持原样（os.replace 原子替换保证），
    临时文件残留无害（读取方只消费 manifest.json）。
    """
    sim_dir.mkdir(parents=True, exist_ok=True)
    tmp = sim_dir / (MANIFEST_FILE + MANIFEST_TMP_SUFFIX)
    tmp.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    os.replace(tmp, sim_dir / MANIFEST_FILE)
