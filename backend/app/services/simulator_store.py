"""
模拟器数据存储（T-02：首启种子 + manifest 工具；工单 03 导入族继续扩展）

首启种子契约（spec T-02 决策 3 + 工单 02）：

    1. 种子标记 = 数据目录 simulators 的 manifest.json 存在（幂等；不做逐文件
       自愈，用户删了就是删了——尊重用户管理，数据目录为唯一事实来源）。
    2. 全新目录：从内置目录整目录拷贝（html + manifest 字节一致）。
    3. manifest **最后**落盘：中断于 manifest 之前 → 下次启动重种；中断于
       manifest 之后 → 视为已种子（标记语义，不逐文件修复）。
    4. 种子源缺失（打包态文件缺失：目录整体缺失或目录内缺 manifest.json）→
       降级不崩溃（返回 False，不建目录）；数据目录不可写 → 抛出带路径的
       明确 OSError（启动期可闻，不静默吞掉）。

manifest 工具（工单 02 声明底座，工单 03 读-改-写原子追加复用）：
    `read_manifest` 读取解析；`write_manifest` 同目录临时文件 + os.replace
    原子替换（ensure_ascii=False 中文保真，version 字段由调用方保持）；
    `append_manifest_entry` 追加注册，manifest 缺失/损坏以磁盘现存 .html
    自愈重建（数据目录为唯一事实来源）。
    单用户桌面应用串行（spec Further Notes：并发导入不引入锁，记录判断）。

导入族（工单 03，spec T-02 决策 4-8 契约锚点）：
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
    名仍视为保留，F-13 定版）加 `_` 前缀、总名 UTF-8 超 255 字节按字节截断
    不劈裂多字节字符（F-9 定版，落盘 OSError 预拦截）。

G4 约束：本模块仅 stdlib import（dataclasses/hashlib/html.parser/json/
logging/os/pathlib/re/shutil），与 data_dir 同层——工单 03 导入族在此继续
扩展，不引入 app 业务代码。
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import shutil
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path

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
    "scan_suspicious",
    "sha256_bytes",
    "slugify",
    "write_manifest",
]

logger = logging.getLogger(__name__)

#: 数据目录 simulators 下的清单文件名（前端 MANIFEST_URL 恒为 simulators/manifest.json）
MANIFEST_FILE = "manifest.json"
#: 原子写临时文件后缀（同目录临时文件 + os.replace；固定名，单用户串行无锁）
MANIFEST_TMP_SUFFIX = ".tmp"
#: 导入文件大小上限（≤5MB；spec T-02 决策 5「校验与去重」）
MAX_IMPORT_BYTES = 5 * 1024 * 1024
#: 文件名净化剔除字符：Windows 非法字符 + 路径分隔符 + 前端 file 判据拒绝的 % 与
#: #（URL fragment 分隔符——iframe src 遇 # 截断请求 → 404，落盘名必须兼容）+ 控制字符
_FORBIDDEN_FILENAME_CHARS = frozenset('<>:"/\\|?*%#') | frozenset(chr(i) for i in range(32))

#: Windows 保留设备名（大小写不敏感、带任意扩展名仍视为保留；F-9 定版——
#: 精确匹配才拦截，mycon/com10/lpt10 等邻近名不受影响）
_WINDOWS_RESERVED_NAMES = frozenset(
    {"con", "prn", "aux", "nul"}
    | {f"com{i}" for i in range(1, 10)}
    | {f"lpt{i}" for i in range(1, 10)}
)

#: 文件名 UTF-8 字节上限（含 .html 后缀；Windows 路径组件上限 255 字节，F-9 定版）
_MAX_FILENAME_BYTES = 255

#: 恶意模式粗筛常量清单（键 + 正则，常量单源——前端 warnings 文案映射以此为键集锚点；
#: 命中仅收集返回，绝不拦截；静态审查不承诺防住，定位知情提示）
SUSPICIOUS_PATTERNS: dict[str, re.Pattern[str]] = {
    "eval": re.compile(r"eval\s*\("),
    "document.cookie": re.compile(r"document\s*\.\s*cookie"),
    "cross-origin-fetch": re.compile(r"""fetch\s*\(\s*["'`]\s*(?:https?://|//)"""),
}


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


# ── 导入族（工单 03：校验 / 净化 / 去重 / 改名 / 探测 / 粗筛 / manifest 注册）──


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
    保留设备名 + 255 字节上限）。

    定版规则：取最后路径段（`/` 与 `\\` 皆按分隔符，杜绝穿越）、剔除 Windows
    非法字符与控制字符、剔除 `%` 与 `#`（前端 isValidSimulatorFile 单点拒绝，
    落盘名必须兼容——`#` 为 URL fragment 分隔符，入 iframe src 会截断请求）、
    剔除首尾点与空格（防隐藏文件与 `..` 段）；空名回退 `imported-game`；
    扩展名归一化为小写 `.html`。stem（去 .html 后的主名）按「首点前组件」
    大小写不敏感判定 Windows 保留设备名（con/prn/aux/nul/com1-9/lpt1-9，
    带任意扩展名仍视为保留——F-13 定版：MSDN 判定取首点前组件，NUL.tar.gz
    等价 NUL，双扩展形态 con.txt.html 同样拦截）→ 加 `_` 前缀（`_con` 非
    保留名）；非精确匹配（mycon/com10/lpt10 等）不受影响。总名（含 .html
    后缀）UTF-8 编码超 255 字节 → 按字节截断 stem 且不劈裂多字节字符（截断
    后复用首尾点剔除与空名回退兜底链）。
    净化静默收敛不报错——校验失败仅限 400 矩阵（非 .html / 超 5MB / 空文件，
    见 import_game）。
    """
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
    stem = _truncate_utf8_bytes(stem, _MAX_FILENAME_BYTES - len(suffix))
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
    不劈裂多字节字符）——杜绝 NAME_MAX 顶破（250 字节 stem 拼 -2 溢出 255
    字节 → 落盘 OSError 500）。
    目录不存在视为无冲突（导入会在落盘前创建目录）。
    """
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
        candidate = _truncate_utf8_bytes(stem, _MAX_FILENAME_BYTES - len(suffix)) + suffix
        n += 1
    return candidate


class _InputIdScanner(HTMLParser):
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


def probe_config(html_text: str) -> tuple[str, dict | None]:
    """元数据探测：cfg- 前缀 input id 三元组（cfg-endpoint/cfg-apikey/cfg-model）
    齐全 → ('ai', config 三元组)；否则 ('local', None)——三元组不完整即降级，
    不保留部分 config（spec 决策 6 条目级降级兜底）。

    config 值为输入框 id（key-injector 契约：按 id 定位输入框注入凭证）。
    """
    scanner = _InputIdScanner()
    scanner.feed(html_text)
    cfg_ids = {i for i in scanner.ids if i.startswith("cfg-")}
    if {"cfg-endpoint", "cfg-apikey", "cfg-model"} <= cfg_ids:
        return ("ai", {"endpoint": "cfg-endpoint", "apikey": "cfg-apikey", "model": "cfg-model"})
    return ("local", None)


def scan_suspicious(html_text: str) -> list[str]:
    """恶意模式粗筛：按 SUSPICIOUS_PATTERNS 常量清单命中收集键集（排序确定，不拦截）。

    静态审查不承诺防住（spec 决策 7 定位为知情提示）；误报不拦截导入。
    """
    return sorted(key for key, pattern in SUSPICIOUS_PATTERNS.items() if pattern.search(html_text))


def append_manifest_entry(sim_dir: Path, entry: dict) -> None:
    """manifest 读-改-写原子追加：合法则既有条目原样保留；缺失/损坏 → 以磁盘
    现存 .html 自愈重建（version=2，type=local 降级）再追加。"""
    manifest = _read_manifest_or_rebuild(sim_dir)
    manifest["simulators"].append(entry)
    write_manifest(sim_dir, manifest)


def _read_manifest_or_rebuild(sim_dir: Path, persist: bool = False) -> dict:
    """读取 manifest；缺失或损坏 → 磁盘重建兜底。

    损坏口径（F-8 定版）：非法 JSON / 非 UTF-8 / 合法 JSON 但结构非预期
    （顶层非 dict 或 simulators 非 list——如字符串/字典/None）一律视为损坏
    重建，否则 `_existing_ids` 迭代 dict/str 抛 TypeError、`append_manifest_entry`
    的 `.append` 抛 AttributeError → 500（原子写保证正常运行不产生此类
    损坏，需手工损坏 manifest 触发；条目级字段不做校验，范围收敛）。
    persist=True 时重建结果立即原子落盘（import_game 先自愈再算 id：避免
    「id 唯一化用瞬态重建、append 用磁盘重建（此时已含新落盘文件）」两次
    重建口径不一致产生退化重复条目）。
    """
    try:
        manifest = read_manifest(sim_dir)
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError):
        manifest = None
    if not isinstance(manifest, dict) or not isinstance(manifest.get("simulators"), list):
        rebuilt = _rebuild_manifest(sim_dir)
        if persist:
            write_manifest(sim_dir, rebuilt)
        return rebuilt
    return manifest


def _rebuild_manifest(sim_dir: Path) -> dict:
    """以现存 .html 文件重建 manifest（自愈：数据目录为唯一事实来源）。

    条目：id=文件名干 slug（冲突 -2/-3 唯一化，保证结构性唯一）、file/name
    取实际文件名、type=local（重建为降级态，不逐文件探测）。"""
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


def import_game(sim_dir: Path, filename: str, content: bytes) -> ImportResult:
    """导入单文件 HTML 模拟器游戏（服务编排：校验 → 净化 → 去重 → 改名 →
    探测 → 粗筛 → 落盘 → manifest 注册）。

    Args:
        sim_dir: 数据目录 simulators（请求期解析，调用方负责；不缓存于 import 期）
        filename: 上传文件名（原始值，扩展名校验与净化均在此进行）
        content: 上传文件字节

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
        "source": "imported",
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
