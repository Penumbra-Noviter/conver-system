"""
模拟器数据存储（T-02：首启种子；manifest 工具与导入族拆分至独立模块）

职责收敛（T-02 决策）：本模块承载首启种子契约；manifest 读写已拆分至
`simulator_manifest`，导入族拆分至 `simulator_import`，本模块保留顶层
re-export（`__all__` 21 符号与 import 兼容不变——`from backend.app.services
import simulator_store` 下的所有旧符号仍可用）。

首启种子契约（spec T-02 决策 3 + 工单 02）：

    1. 种子标记 = 数据目录 simulators 的 manifest.json 存在（幂等；不做逐文件
       自愈，用户删了就是删了——尊重用户管理，数据目录为唯一事实来源）。
    2. 全新目录：从内置目录整目录拷贝（html + manifest 字节一致）。
    3. manifest **最后**落盘：中断于 manifest 之前 → 下次启动重种；中断于
       manifest 之后 → 视为已种子（标记语义，不逐文件修复）。
    4. 种子源缺失（打包态文件缺失：目录整体缺失或目录内缺 manifest.json）→
       降级不崩溃（返回 False，不建目录）；数据目录不可写 → 抛出带路径的
       明确 OSError（启动期可闻，不静默吞掉）。

G4 约束：本模块仅 stdlib import（logging/shutil/pathlib）——manifest 工具与导入族
的 stdlib 依赖随拆分已移入各自模块；与 data_dir 同层，不引入 app 业务代码。
"""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

# ── 顶层 re-export（__all__ 21 符号与拆分前保持一致；详见 __all__）
from backend.app.services.simulator_import import (
    CFG_REQUIRED_IDS,
    MAX_IMPORT_BYTES,
    SUSPICIOUS_PATTERNS,
    ImportResult,
    SimulatorDuplicateError,
    SimulatorImportError,
    _existing_ids,  # 回归锚测试直接访问，非 __all__ 但保持模块属性
    find_duplicate,
    import_game,
    next_available_filename,
    probe_config,
    sanitize_filename,
    scan_input_ids,
    scan_suspicious,
    sha256_bytes,
    slugify,
)
from backend.app.services.simulator_manifest import (
    MANIFEST_FILE,
    MANIFEST_TMP_SUFFIX,
    _read_manifest_or_rebuild,  # 回归锚测试直接访问，非 __all__ 但保持模块属性
    append_manifest_entry,
    read_manifest,
    write_manifest,
)

__all__ = [
    "MANIFEST_FILE",
    "MANIFEST_TMP_SUFFIX",
    "MAX_IMPORT_BYTES",
    "SUSPICIOUS_PATTERNS",
    "ImportResult",
    "SimulatorDuplicateError",
    "SimulatorImportError",
    "append_manifest_entry",
    "ensure_seeded",
    "find_duplicate",
    "import_game",
    "next_available_filename",
    "probe_config",
    "read_manifest",
    "sanitize_filename",
    "scan_input_ids",
    "scan_suspicious",
    "CFG_REQUIRED_IDS",
    "sha256_bytes",
    "slugify",
    "write_manifest",
]

logger = logging.getLogger(__name__)

#: 文件名 UTF-8 字节上限（含 .html 后缀；F-17 定版 120 字节——定义于本模块：
#: 回归锚测试通过 monkeypatch `simulator_store._MAX_FILENAME_BYTES` 模拟组件上限
#: 顶破场景，文件名截断函数按调用期读取本常量——Windows MAX_PATH = 260 全路径
#: 上限且 Python open 无 `\\?\` 前缀：默认数据目录（%APPDATA%/ConverSystem/
#: simulators ~55 字符前缀）下 205-255 字节名全长 260+ 仍落盘失败，255 组件
#: 上限在真实路径不可达；120 = 260 - 常见数据目录前缀余量，超长名截断静默收敛）
_MAX_FILENAME_BYTES = 120


def ensure_seeded(builtin_dir: Path, target_dir: Path) -> bool:
    """首启种子：target_dir 缺 manifest → 从 builtin_dir 整目录拷贝（含 manifest）。

    返回 True 表示本次执行了种子拷贝；False 表示已种子（标记存在）或种子源缺失
    （目录缺失或目录内缺 manifest.json，降级不崩溃，不创建 target_dir）。
    数据目录不可写 → 抛明确 OSError（含路径）。
    拷贝范围：builtin_dir 下的文件条目（html + manifest；目录条目跳过——
    内置种子源当前纯文件形态）。
    """
    if not builtin_dir.is_dir():
        logger.warning("模拟器种子源缺失，跳过首启种子：%s", builtin_dir)
        return False
    if not (builtin_dir / MANIFEST_FILE).is_file():
        logger.warning("模拟器种子源 manifest 缺失，跳过首启种子：%s", builtin_dir / MANIFEST_FILE)
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