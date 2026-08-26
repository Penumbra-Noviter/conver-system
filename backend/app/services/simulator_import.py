"""
模拟器导入族（T-02 拆分自 simulator_store）

导入族（spec T-02 决策 4-8 契约锚点）：
    `import_game` 为服务编排（校验 → 净化 → SHA-256 去重 → 冲突改名 → 类型
    探测 → 恶意模式粗筛 → 落盘 → manifest 原子注册）；校验失败
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

类型探测（三层，2026-08-26 补强）：`probe_config` L1 严格 cfg- 三元组
（生成器作者契约）→ L2 关键词启发（endpoint|url|base / key / model 三组
各命中 → ai + 各组首个 id 为 config）→ L3 local。`scan_input_ids` 双层扫描：
HTMLParser 静态层（input/select）+ 脚本层 raw-regex（JS 模板字符串渲染的
运行时控件——引擎系游戏设置面板全在此路径，HTMLParser 不解析 script 内容）。
`probe_endpoint_mode` 从默认端点值推断 'full'/'base'（SIM-API-1 口径：
以 /chat/completions 结尾 → full），import_game 条目追加 endpointMode。

G4 约束：本模块仅 stdlib import（dataclasses/hashlib/html.parser/
logging/pathlib/re），与 data_dir 同层——不引入 app 业务代码。
"""

from __future__ import annotations

import hashlib
import html.parser
import logging
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
    "ScanResult",
    "SimulatorDuplicateError",
    "SimulatorImportError",
    "find_duplicate",
    "import_game",
    "next_available_filename",
    "probe_config",
    "probe_endpoint_mode",
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

#: 启发式关键词组（id 判定；每组命中任一即视为该字段控件。endpoint 组覆盖
#: 引擎系全部约定——endpoint/url 子串 + base 结尾（inpBase/api-base/a-base）；
#: database 等尾部 base 的非控件 id 属已接受残留（须三组同时命中才判 ai，实际面窄）
_ENDPOINT_RE = re.compile(r"endpoint|url|base$", re.I)
_KEY_RE = re.compile(r"key", re.I)
_MODEL_RE = re.compile(r"model", re.I)

#: 脚本层 raw-regex：注释剥离后扫描 <input|select> 的 id 属性（覆盖 JS 模板字符串
#: 渲染的运行时控件——HTMLParser 不解析 <script> 内部，引擎系游戏（小马宝莉/斗罗大陆
#: 等）的设置控件全部在此）。匹配 id 的引号形式（`id="..."` / `id='...'`），
#: 不匹配无引号形式（如 `id=cfg-endpoint`）——现有测试依赖此精度。
_SCRIPT_TIER_RE = re.compile(r"""<(?:input|select)\b[^>]*?\bid=["']([^"']+)["']""", re.IGNORECASE)

#: 端点默认值提取正则（endpointMode 推断用）：匹配 JS 中 endpoint 赋值的引号内 URL
_ENDPOINT_DEFAULT_RE = re.compile(r"""endpoint\s*[:=]\s*["'](https?://[^"']+)["']""", re.IGNORECASE)


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


@dataclass(frozen=True)
class ScanResult:
    """预计算扫描结果（避免生成器路径双重扫描：T-03 消除 import_game 内部的 probe_config / scan_suspicious 重复计算）

    game_type: probe_config 判定的游戏类型（"ai" / "local"）
    config: ai 时三元组 dict，local 时 None
    warnings: scan_suspicious 命中的 SUSPICIOUS_PATTERNS 键集
    endpoint_mode: probe_endpoint_mode 推断值（'full'/'base'/None）
    """

    game_type: str
    config: dict | None
    warnings: list[str]
    endpoint_mode: str | None = None


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
    """扫描 input/select 元素 id（stdlib HTMLParser；script/注释内容不解析——实测语义）"""

    def __init__(self) -> None:
        super().__init__()
        self.ids: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() not in ("input", "select"):
            return
        for key, value in attrs:
            if key.lower() == "id" and value:
                self.ids.append(value.strip())


def _strip_html_comments(text: str) -> str:
    """剥离 HTML 注释（<!-- ... -->），为脚本层 raw-regex 提供干净的文本。"""
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def _collect_ordered_ids(html_text: str) -> list[str]:
    """返回文档序的控件 id 列表（parser 静态层在前，脚本层去重补漏在后）。

    用于 probe_config 启发式（须按文档序取各组首个命中，避免 set 无序）。
    """
    scanner = _InputIdScanner()
    scanner.feed(html_text)
    seen: set[str] = set()
    result: list[str] = []
    for cid in scanner.ids:
        if cid not in seen:
            seen.add(cid)
            result.append(cid)
    for cid in _SCRIPT_TIER_RE.findall(_strip_html_comments(html_text)):
        if cid not in seen:
            seen.add(cid)
            result.append(cid)
    return result


def scan_input_ids(html_text: str) -> set[str]:
    """扫描 HTML 中所有 input/select 元素的 id 集合（含脚本模板字符串内的运行时控件）

    双层扫描取并集（覆盖静态 HTML 与 JS 模板字符串渲染两种场景）：
      1. HTMLParser 层：scanner 解析静态 HTML（input/select 元素，script/注释内容
         不解析——HTMLParser 语义，保证边界正确如属性含 > 等）；
      2. 脚本层 raw-regex：注释剥离后对全文正则匹配 `<input|select ... id="..."`，
         捕获 JS 模板字符串内部渲染的控件（引擎系游戏的设置面板全部走此路径）。

    返回 set 而非 list，便于子集/差集运算（game_generator._check_cfg_contract
    和 probe_config 的 L1 严格层均做集合运算，无需保留顺序）。
    """
    return set(_collect_ordered_ids(html_text))


def _probe_keyword_groups(ordered_ids: list[str]) -> dict[str, str] | None:
    """关键词启发式探测：endpoint/url/base、key、model 三组各命中 ≥1 时返回 config。

    Args:
        ordered_ids: 文档序控件 id 列表（每组取第一个命中，保证确定性）

    Returns:
        config 三元组 {endpoint, apikey, model} 或 None（未全中）
    """
    endpoint = apikey = model = None
    for cid in ordered_ids:
        if endpoint is None and _ENDPOINT_RE.search(cid):
            endpoint = cid
        if apikey is None and _KEY_RE.search(cid):
            apikey = cid
        if model is None and _MODEL_RE.search(cid):
            model = cid
    if endpoint and apikey and model:
        return {"endpoint": endpoint, "apikey": apikey, "model": model}
    return None


def probe_config(html_text: str) -> tuple[str, dict | None]:
    """元数据探测：三层判定（L1 严格 cfg- 三元组 → L2 关键词启发 → L3 local）。

    L1（cfg- 前缀严格匹配）：cfg-endpoint/cfg-apikey/cfg-model 三个控件齐全 →
      ('ai', config 三元组)；不降级到 L2 的 cfg- 前缀——生成器作者契约。
    L2（关键词启发）：endpoint|url|base / key / model 三组关键词各命中 ≥1 个 id →
      ('ai', 各组文档序首个 id 组成的 config)；不保留部分匹配。
    L3（fallback）：('local', None)。

    config 值为输入框 id（key-injector 契约：按 id 定位输入框注入凭证）。
    """
    all_ids = scan_input_ids(html_text)
    cfg_ids = {i for i in all_ids if i.startswith("cfg-")}
    # L1：严格 cfg- 三元组
    if CFG_REQUIRED_IDS <= cfg_ids:
        return ("ai", {"endpoint": "cfg-endpoint", "apikey": "cfg-apikey", "model": "cfg-model"})
    # L2：关键词启发（用文档序列表，保证各组首个命中确定性）
    ordered = _collect_ordered_ids(html_text)
    heuristic = _probe_keyword_groups(ordered)
    if heuristic is not None:
        return ("ai", heuristic)
    # L3：纯本地
    return ("local", None)


def probe_endpoint_mode(html_text: str) -> str | None:
    """从源码默认端点值推断 endpointMode（SIM-API-1 口径）。

    匹配 JS 中 `endpoint = '...'` 或 `endpoint: '...'` 的默认 URL 值：
    - 以 /chat/completions 结尾 → 'full'（游戏期望完整路径，主应用需追加后缀）
    - 其他 → 'base'（游戏自行拼接）
    - 未匹配默认值 → None（不转换，兼容旧数据 / 无默认端点声明的游戏）

    Returns:
        'full' | 'base' | None
    """
    m = _ENDPOINT_DEFAULT_RE.search(html_text)
    if not m:
        return None
    url = m.group(1).rstrip("/")
    return "full" if url.endswith("/chat/completions") else "base"


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
    sim_dir: Path, filename: str, content: bytes, source: str = "imported",
    *, precomputed_scan: ScanResult | None = None,
) -> ImportResult:
    """导入单文件 HTML 模拟器游戏（服务编排：校验 → 净化 → 去重 → 改名 →
    探测 → 粗筛 → 落盘 → manifest 注册）。

    precomputed_scan 用于生成器路径（T-03）：传值时跳过 probe_config 与
    scan_suspicious 的结果计算，直接使用预计算值（game_type/config/warnings）；
    不传时行为与现状逐字一致（import 路由路径不传）。

    Args:
        sim_dir: 数据目录 simulators（请求期解析，调用方负责；不缓存于 import 期）
        filename: 上传文件名（原始值，扩展名校验与净化均在此进行）
        content: 上传文件字节
        source: manifest 条目 source 标记（默认 imported；AI 生成游戏传
            generated——game_generator 消费，`source` 白名单见前端 parseManifest）
        precomputed_scan: 预计算扫描结果（T-03 双重扫描消除）；keyword-only

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

    if precomputed_scan is not None:
        game_type = precomputed_scan.game_type
        config = precomputed_scan.config
        warnings = precomputed_scan.warnings
        endpoint_mode = precomputed_scan.endpoint_mode
        if endpoint_mode is None:
            # 旧 ScanResult 未携带 endpoint_mode（生成路径兜底）：现场推断
            text = content.decode("utf-8", errors="replace")
            endpoint_mode = probe_endpoint_mode(text)
    else:
        text = content.decode("utf-8", errors="replace")
        game_type, config = probe_config(text)
        endpoint_mode = probe_endpoint_mode(text)
        warnings = scan_suspicious(text)
    entry: dict = {
        "id": _unique_game_id(sim_dir, slugify(stem)),
        "file": final_name,
        "name": stem,
        "type": game_type,
        "source": source,
    }
    if config is not None:
        entry["config"] = config
    if endpoint_mode is not None:
        entry["endpointMode"] = endpoint_mode

    sim_dir.mkdir(parents=True, exist_ok=True)
    (sim_dir / final_name).write_bytes(content)
    try:
        append_manifest_entry(sim_dir, entry)
    except Exception:
        (sim_dir / final_name).unlink(missing_ok=True)
        raise
    return ImportResult(game=entry, renamed=renamed, warnings=warnings)