"""
模拟器导入族（T-02 拆分自 simulator_store）

导入族（spec T-02 决策 4-8 契约锚点）：
    `import_game` 为服务编排（校验 → 净化 → SHA-256 去重 → 冲突改名 → cfg-
    三元组探测 → 恶意模式粗筛 → 落盘 → manifest 原子注册）；校验失败
    SimulatorImportError（400 语义）、重复 SimulatorDuplicateError（409 语义、
    文案含「已存在」）；warnings 键集 = SUSPICIOUS_PATTERNS 常量单源
    （eval / document.cookie / cross-origin-fetch，命中不拦截）；id 由最终
    文件名干 slug 生成（仅保留 [a-z0-9-]、折叠分隔符、空回退 imported-game）
    并按现存 id 集唯一化（-2/-3 后缀，manifest 结构性唯一）。
    文件名净化规则（定版）：取最后路径段 + 剔除 Windows 非法字符/%/#（# 为
    URL fragment 分隔符，iframe src 截断风险）+ 首尾点剔除，空名回退
    imported-game（防目录穿越，Windows 路径安全）；stem 按「首点前组件」
    判定命中 Windows 保留设备名（con/prn/aux/nul/com1-9/lpt1-9，带任意扩展
    名仍视为保留，F-13 定版）加 `_` 前缀、总名 UTF-8 超 120 字节按字节截断
    不劈裂多字节字符（F-17 定版：Windows MAX_PATH = 260 全路径上限兼容，
    落盘 OSError 预拦截）。

G4 约束：本模块仅 stdlib import（dataclasses/hashlib/html.parser/json/
logging/os/pathlib/re），与 data_dir 同层——不引入 app 业务代码。
"""

from __future__ import annotations

import hashlib
import html.parser
import json
import logging
import os
import re
from dataclasses import dataclass
from pathlib import Path

from backend.app.services.simulator_manifest import (
    MANIFEST_FILE,
    _read_manifest_or_rebuild,
    append_manifest_entry,
    read_manifest,
    write_manifest,
)

__all__ = [
    "MAX_IMPORT_BYTES",
    "SUSPICIOUS_PATTERNS",
    "ImportResult",
    "SimulatorDuplicateError",
    "SimulatorImportError",
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

#: 导入文件大小上限（≤5MB；spec T-02 决策 5「校验与去重」）
MAX_IMPORT_BYTES = 5 * 1024 * 1024

#: 文件名净化剔除字符：Windows 非法字符 + 路径分隔符 + 前端 file 判据拒绝的 % 与
#: #（URL fragment 分隔符——iframe src 遇 # 截断请求 → 404，落盘名必须兼容）+ 控制字符
_FORBIDDEN_FILENAME_CHARS = frozenset('<>:"/\\|?*%#') | frozenset(chr(i) for i in range(32))

#: Windows 保留设备名（大小写不敏感、带任意扩展名仍视为保留；F-9 定版精确匹配，F-13 修订——
#: 判定取首点前组件（NUL.tar.gz 等价 NUL，见 sanitize_filename），mycon/com10/lpt10 等邻近名不受影响）
_WINDOWS_RESERVED_NAMES = frozenset(
    {"con", "prn", "aux", "nul"}
    | {f"com{i}" for i in range(1, 10)}
    | {f"lpt{i}" for i in range(1, 10)}
)

#: 恶意模式粗筛常量清单（键 + 正则，常量单源——前端 warnings 文案映射以此为键集锚点；
#: 命中仅收集返回，绝不拦截；静态审查不承诺防住，定位知情提示）
SUSPICIOUS_PATTERNS: dict[str, re.Pattern[str]] = {
    "eval": re.compile(r"eval\s*\("),
    "document.cookie": re.compile(r"document\s*\.\s*cookie"),
    "cross-origin-fetch": re.compile(r"""fetch\s*\(\s*["'`]\s*(?:https?://|//)"""),
}

#: cfg- 契约所需的三元组 input id（key-injector 探测用，常量单源——generator 校验层复用）
CFG_REQUIRED_IDS: frozenset[str] = frozenset({"cfg-endpoint", "cfg-apikey", "cfg-model"})


class SimulatorImportError(Exception):
    """导入校验失败（非 .html / 超 5MB / 空文件 / 缺文件名）→ 路由映射 400"""


class SimulatorDuplicateError(Exception):
    """SHA-256 内容重复（文案含「已存在」）→ 路由映射 409"""


@dataclass(frozen=True)
class ImportResult:
    """导入成功结果：game 为 manifest 条目字典；renamed 是否自动改名；warnings 粗筛键集"""

    game: dict
    renamed: bool
    warnings: list[str]


# ── 文件名常量（_MAX_FILENAME_BYTES 定义在 simulator_store，测试 monkeypatch 依赖其命名空间——
# sanitize_filename / next_available_filename 通过函数级延迟导入读取）──


def _filename_limit() -> int:
    """读取文件名字节上限（延迟导入 simulator_store 规避循环引用）。"""
    from backend.app.services import simulator_store  # type: ignore[import-untyped]
    return simulator_store._MAX_FILENAME_BYTES


def sha256_bytes(content: bytes) -> str:
    """内容字节的 SHA-256 十六进制摘要（去重主键）。"""
    return hashlib.sha256(content).hexdigest()


def _truncate_utf8_bytes(s: str, max_bytes: int) -> str:
    """UTF-8 字节截断（不劈裂多字节字符；sanitize 与改名路径共用）。

    仅当 s 编码后字节数超 max_bytes 才截断（未超原样返回）；截断点若落在
    多字节字符中间（末字节为 UTF-8 尾随字节 10xxxxxx）回退到完整字符边界，
    避免乱码半字符；截断后复用净化链的首尾点/空格剔除（防截出尾随点等
    非法形态）。截断为空时返回空串，兜底回退由调用方决定。
    """
    data = s.encode("utf-8")
    if len(data) <= max_bytes:
        return s
    data = data[:max_bytes]
    while data and (data[-1] & 0xC0) == 0x80:
        data = data[:-1]
    return data.decode("utf-8", errors="ignore").strip(" .")


def sanitize_filename(raw: str) -> str:
    """净化上传文件名 → 安全落盘名（防目录穿越 + Windows 非法字符 + %/# +
    保留设备名 + 120 字节上限）。

    定版规则：取最后路径段（`/` 与 `\\` 皆按分隔符，杜绝穿越）、剔除 Windows
    非法字符与控制字符、剔除 `%` 与 `#`（前端 isValidSimulatorFile 单点拒绝，
    落盘名必须兼容——`#` 为 URL fragment 分隔符，入 iframe src 会截断请求）、
    剔除首尾点与空格（防隐藏文件与 `..` 段）；空名回退 `imported-game`；
    扩展名归一化为小写 `.html`。stem（去 .html 后的主名）按「首点前组件」
    大小写不敏感判定 Windows 保留设备名（con/prn/aux/nul/com1-9/lpt1-9，
    带任意扩展名仍视为保留——F-13 定版：MSDN 判定取首点前组件，NUL.tar.gz
    等价 NUL，双扩展形态 con.txt.html 同样拦截）→ 加 `_` 前缀（`_con` 非
    保留名）；非精确匹配（mycon/com10/lpt10 等）不受影响。总名（含 .html
    后缀）UTF-8 编码超 120 字节 → 按字节截断 stem 且不劈裂多字节字符（截断
    后复用首尾点剔除与空名回退兜底链）。上限定版依据（F-17）：Windows
    MAX_PATH = 260 全路径上限，Python open 无 `\\?` 前缀——255 组件上限在
    真实数据目录路径下不可达（默认 %APPDATA%/ConverSystem/simulators ~55
    字符前缀 + 205-255 字节名全长 260+ 即 FileNotFoundError），120 = 260 -
    常见数据目录前缀余量，保证净化结果在真实路径可落盘；超长名截断静默收敛。
    净化静默收敛不报错——校验失败仅限 400 矩阵（非 .html / 超 5MB / 空文件，
    见 import_game）。
    """
    max_bytes = _filename_limit()
    name = raw.strip().replace("\\", "/").rsplit("/", 1)[-1]
    name = "".join(ch for ch in name if ch not in _FORBIDDEN_FILENAME_CHARS)
    name = name.strip(" .")
    if not name:
        name = "imported-game"
    if name.lower().endswith(".html"):
        stem = name[:-5]
    else:
        stem = name
    if stem.split(".", 1)[0].lower() in _WINDOWS_RESERVED_NAMES:
        stem = "_" + stem
    suffix = ".html"
    stem = _truncate_utf8_bytes(stem, max_bytes - len(suffix))
    if not stem:
        stem = "imported-game"
    return stem + suffix


def slugify(stem: str) -> str:
    """id slug（定版规则，工单 03/04 共享）：仅保留 [a-z0-9-]、分隔符折叠、
    无 ASCII 回退 `imported-game`。"""
    slug = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
    return slug or "imported-game"


def find_duplicate(sim_dir: Path, content: bytes) -> str | None:
    """SHA-256 去重：与 sim_dir 现存 *.html 文件比对，命中返回文件名。

    仅比对 .html（后缀大小写不敏感）：per-game CSS 等非游戏文件是内容独立
    资产（数据目录 <game-id>.css 覆盖层），字节相同不得误报「游戏已存在」。
    种子后内置游戏即数据目录内容（spec 决策 5），重复判定自然覆盖内置重复。
    """
    digest = sha256_bytes(content)
    if not sim_dir.is_dir():
        return None
    for path in sim_dir.iterdir():
        if not path.is_file() or path.name == MANIFEST_FILE:
            continue
        if path.suffix.lower() != ".html":
            continue
        if sha256_bytes(path.read_bytes()) == digest:
            return path.name
    return None


def next_available_filename(sim_dir: Path, desired: str) -> str:
    """文件名冲突自动改名：xxx-2.html 递增；冲突判定大小写不敏感（Windows 定版）。

    改名路径保证总名（含 -N 后缀与扩展名）UTF-8 不超过 _MAX_FILENAME_BYTES
    字节：拼 -N 后缀前按余量对 stem 重做字节截断（复用 _truncate_utf8_bytes，
    不劈裂多字节字符）——杜绝 NAME_MAX/MAX_PATH 顶破（长 stem 拼 -2 溢出
    组件上限 → 落盘 OSError 500；F-14 起因即 250 字节 stem 拼 -2 得 257 字节
    溢出 255 组件上限，现上限收紧为 120 后触发面收窄、机制不变）。
    目录不存在视为无冲突（导入会在落盘前创建目录）。
    入参契约：desired 应传入完整文件名（含扩展名），且调用方须保证 stem 非空
    ——空 stem（如 ".html"）冲突时产出 "-N.html" 畸形名，本函数不兜底
    （空名兜底由 sanitize_filename 的 imported-game 承担）。
    无点或空串输入为契约外行为（rsplit 直接 ValueError），违约后果自负。
    """
    max_bytes = _filename_limit()
    stem, ext = desired.rsplit(".", 1)
    existing = (
        {p.name.lower() for p in sim_dir.iterdir() if p.is_file()}
        if sim_dir.is_dir()
        else set()
    )
    candidate = desired
    n = 2
    while candidate.lower() in existing:
        suffix = f"-{n}.{ext}"
        candidate = _truncate_utf8_bytes(stem, max_bytes - len(suffix)) + suffix
        n += 1
    return candidate


class _InputIdScanner(html.parser.HTMLParser):
    """扫描 input 元素 id（stdlib HTMLParser；script/注释内容不解析——实测语义）。"""

    def __init__(self) -> None:
        super().__init__()
        self.ids: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "input":
            return
        for key, value in attrs:
            if key.lower() == "id" and value:
                self.ids.append(value.strip())


def scan_input_ids(html_text: str) -> set[str]:
    """扫描 HTML 中所有 input 元素的 id 集合（为 cfg- 契约校验提供单源扫描器）

    返回 set 而非 list，便于子集/差集运算（game_generator._check_cfg_contract
    和 probe_config 均做集合运算，无需保留顺序）。
    """
    scanner = _InputIdScanner()
    scanner.feed(html_text)
    return set(scanner.ids)


def probe_config(html_text: str) -> tuple[str, dict | None]:
    """元数据探测：cfg- 前缀 input id 三元组（cfg-endpoint/cfg-apikey/cfg-model）
    齐全 → ('ai', config 三元组)；否则 ('local', None)——三元组不完整即降级，
    不保留部分 config（spec 决策 6 条目级降级兜底）。

    config 值为输入框 id（key-injector 契约：按 id 定位输入框注入凭证）。
    """
    cfg_ids = {i for i in scan_input_ids(html_text) if i.startswith("cfg-")}
    if CFG_REQUIRED_IDS <= cfg_ids:
        return ("ai", {"endpoint": "cfg-endpoint", "apikey": "cfg-apikey", "model": "cfg-model"})
    return ("local", None)


def scan_suspicious(html_text: str) -> list[str]:
    """恶意模式粗筛：按 SUSPICIOUS_PATTERNS 常量清单命中收集键集（排序确定，不拦截）。

    静态审查不承诺防住（spec 决策 7 定位为知情提示）；误报不拦截导入。
    """
    return sorted(key for key, pattern in SUSPICIOUS_PATTERNS.items() if pattern.search(html_text))


def _existing_ids(sim_dir: Path) -> set[str]:
    """现存 manifest 条目 id 集（缺失/损坏按磁盘重建口径，与 append 自愈一致）。"""
    return {g["id"] for g in _read_manifest_or_rebuild(sim_dir).get("simulators", [])}


def _unique_game_id(sim_dir: Path, base: str) -> str:
    """id 按现存 id 集唯一化（-2/-3 后缀）——id 重复是 manifest 结构性错误
    （前端 parseManifest 整体失败），必须保证唯一。"""
    existing = _existing_ids(sim_dir)
    gid = base
    n = 2
    while gid in existing:
        gid = f"{base}-{n}"
        n += 1
    return gid


def import_game(
    sim_dir: Path, filename: str, content: bytes, source: str = "imported"
) -> ImportResult:
    """导入单文件 HTML 模拟器游戏（服务编排：校验 → 净化 → 去重 → 改名 →
    探测 → 粗筛 → 落盘 → manifest 注册）。

    Args:
        sim_dir: 数据目录 simulators（请求期解析，调用方负责；不缓存于 import 期）
        filename: 上传文件名（原始值，扩展名校验与净化均在此进行）
        content: 上传文件字节
        source: manifest 条目 source 标记（默认 imported；AI 生成游戏传
            generated——game_generator 消费，`source` 白名单见前端 parseManifest）

    Raises:
        SimulatorImportError: 非 .html / 超 5MB / 空文件 / 缺文件名（400 语义）
        SimulatorDuplicateError: SHA-256 与现存文件重复（409 语义，文案含「已存在」）
        OSError: 数据目录不可写等落盘失败（500 语义，不静默吞掉）

    顺序保证：校验先于一切副作用（校验失败零落盘）；去重在改名之前（重复即
    409，不产生改名条目）；manifest 注册失败回滚已落盘文件（不遗留孤儿文件）。
    单用户桌面应用串行（spec Further Notes：并发导入不引入锁）。
    """
    if not filename.strip():
        raise SimulatorImportError("未提供文件名")
    if not filename.lower().endswith(".html"):
        raise SimulatorImportError(f"仅支持 .html 文件（当前：{filename}）")
    if len(content) > MAX_IMPORT_BYTES:
        raise SimulatorImportError("文件超过 5MB 上限")
    if not content:
        raise SimulatorImportError("文件内容为空")

    safe_name = sanitize_filename(filename)
    if dup := find_duplicate(sim_dir, content):
        raise SimulatorDuplicateError(f"游戏已存在（内容与现有文件相同）：{dup}")

    final_name = next_available_filename(sim_dir, safe_name)
    renamed = final_name != safe_name
    stem = final_name.rsplit(".", 1)[0]

    # manifest 缺失/损坏先自愈落盘（口径一致见 _read_manifest_or_rebuild persist）
    _read_manifest_or_rebuild(sim_dir, persist=True)
    text = content.decode("utf-8", errors="replace")
    game_type, config = probe_config(text)
    entry: dict = {
        "id": _unique_game_id(sim_dir, slugify(stem)),
        "file": final_name,
        "name": stem,
        "type": game_type,
        "source": source,
    }
    if config is not None:
        entry["config"] = config

    sim_dir.mkdir(parents=True, exist_ok=True)
    (sim_dir / final_name).write_bytes(content)
    try:
        append_manifest_entry(sim_dir, entry)
    except Exception:
        (sim_dir / final_name).unlink(missing_ok=True)
        raise
    return ImportResult(game=entry, renamed=renamed, warnings=scan_suspicious(text))