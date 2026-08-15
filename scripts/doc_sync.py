#!/usr/bin/env python3
"""F-01：CODE_WIKI 机械标记同步工具（Conver System 三渠道版）。

从代码中生成五类「数字/签名」机械标记，写入 CODE_WIKI.md 的 HTML 注释标记内，
防止文档与代码漂移：

    lines:<module>            §4 各模块标题的（~N 行）——非空行计数（.py/.js/.rs）
    tests:<test_file>         §5/§7 测试文件用例数——pytest / vitest / cargo 三渠道
    sig:<module>:<symbol>     §4 方法表签名——py 用 AST、js/rs 用正则提取
    tests_total:<key>         测试总数——pytest / vitest / cargo / total

标记语法：``<!--AUTO:<kind>:<key>-->内容<!--/AUTO-->``（HTML 注释，渲染不可见）。
工具只维护标记内的机械文本，绝不生成叙述性说明（F-01 规模悖论边界）。

测试渠道与可用性：
  - pytest：根目录 ``python -m pytest --collect-only -q``（必须可用，失败即报错）
  - vitest：frontend/ 下 ``npx vitest list``（node_modules/vitest 缺失或执行失败 → 降级跳过）
  - cargo：src-tauri/ 下 ``cargo test --test <名> -- --list`` + ``cargo test --lib -- --list``
    （cargo 工具链缺失或编译失败 → 降级跳过）
  降级渠道的标记不校验、不计数，避免克隆后无依赖环境误报。

用法::

    python scripts/doc_sync.py                # 更新：就地刷新所有现有标记内容
    python scripts/doc_sync.py --check        # 校验：有漂移则 exit 1（pre-commit 钩子用）
    python scripts/doc_sync.py --check --verbose
    python scripts/doc_sync.py --dump backend/app/services/chat.py  # 输出模块符号表（写作 §4 用）

--check 额外做结构完整性校验：
  - tests：每个可收集渠道的测试文件必须有标记；每个标记必须对应真实收集文件
  - lines：每个 §4 模块标题必须有标记；每个标记必须对应一个 §4 标题
  - sig：每个标记引用的符号必须存在于模块（删除/改名会被拦截）
  - tests_total：文档中 tests_total 标记内容 = 各渠道收集用例总数（防手工叙述测试数漂移）
  - files：叙述中反引号引用的 .py/.js/.rs 必须存在于仓库，且仓库全部源文件必须被引用
    （双向覆盖——删/改名文件与新增文件漏图都会被拦截；退役文件走白名单）
"""

from __future__ import annotations

import argparse
import ast
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

__all__ = [
    "MARKER_RE",
    "collect_cargo_counts",
    "collect_doc_file_refs",
    "collect_pytest_counts",
    "collect_source_files",
    "collect_vitest_counts",
    "compute_content",
    "count_nonblank_lines",
    "main",
    "render_signature",
    "resolve_signature",
    "resolve_symbol_exists",
    "scan_markers",
]

# ── 常量 ──────────────────────────────────────────────────

MARKER_RE = re.compile(
    r"<!--AUTO:(?P<kind>tests_total|lines|tests|sig):(?P<key>[^>]+)-->"
    r"(?P<content>.*?)"
    r"<!--/AUTO-->",
    re.DOTALL,
)

# §4 模块标题，如 `### 4.1 `backend/app/main.py` — 程序入口（~56 行）`
# 支持子编号（如 `### 4.13.5`）：子编号用非捕获组，文件名恒为 group(1)
HEADING_RE = re.compile(
    r"^### 4\.\d+(?:\.\d+)? .*?`([A-Za-z0-9_./-]+\.(?:py|js|rs))`", re.MULTILINE
)

# 叙述中反引号引用的源文件路径，如 `backend/app/main.py`、`frontend/js/chat.js`
FILE_REF_RE = re.compile(r"`([A-Za-z0-9_./\\-]+\.(?:py|js|rs))(?![A-Za-z0-9_./\\-])`")

# §3 文件树行中的源文件名（树行惯用裸名且无反引号），如 `│   ├── chat.py`
# 负前瞻防止把 `package.json` 截为 `package.js`（`.js` 后紧跟路径字符即不算）
TREE_FILE_RE = re.compile(
    r"^[│ ]*[├└]── ([A-Za-z0-9_./-]+\.(?:py|js|rs))(?![A-Za-z0-9_./-])", re.MULTILINE
)

# pytest --collect-only -q 输出的测试项：`backend/tests/test_x.py::nodeid`
PY_TEST_ITEM_RE = re.compile(r"^([A-Za-z0-9_./\\-]+\.py)::")

# vitest list 输出的测试项：`tests/x.test.js > 套件 > 用例`
JS_TEST_LINE_RE = re.compile(r"^([A-Za-z0-9_./-]+\.test\.js) > ")

# cargo test -- --list 输出的测试项结尾：`name: test`
CARGO_TEST_LINE_RE = re.compile(r": test\s*$")

# 已知历史提及的已退役文件（叙述保留历史事实，白名单防误报；手动维护）
_KNOWN_RETIRED = frozenset()

# 扫描仓库源文件时排除的目录（运行时/生成物/工具目录）
_EXCLUDED_DIRS = frozenset({
    ".claude", ".git", ".mypy_cache", ".playwright-mcp", ".pytest_cache",
    ".scratch", ".serena", ".venv", ".worktrees", "__pycache__",
    "build", "coverage", "dist", "gen", "icons", "localpycs",
    "node_modules", "venv",
})


def project_root() -> Path:
    """项目根目录 = 本脚本父目录的父目录（scripts/ 的上一级）。"""
    return Path(__file__).resolve().parent.parent


def _run(argv: list[str], cwd: Path, timeout: int = 300) -> subprocess.CompletedProcess:
    """执行外部命令；Windows 下经 cmd /c 以支持 .cmd 脚本（npx.cmd）。"""
    if os.name == "nt":
        argv = ["cmd", "/c", *argv]
    return subprocess.run(
        argv, cwd=str(cwd), capture_output=True, text=True, timeout=timeout
    )


# ── 数值提取（三渠道）─────────────────────────────────────


def collect_pytest_counts(root: Path) -> dict[str, int]:
    """运行 ``python -m pytest --collect-only -q``，返回 {测试文件: 用例数}。

    以 pytest 实际收集为准（含参数化展开）；文件用正斜杠相对路径作 key。
    失败（如未装 pytest / 收集报错）即抛 RuntimeError——pytest 是强制渠道。
    """
    proc = _run([sys.executable, "-m", "pytest", "--collect-only", "-q"], root)
    if proc.returncode != 0:
        raise RuntimeError(
            "pytest --collect-only 失败（rc=%d）:\n%s"
            % (proc.returncode, proc.stderr[-2000:])
        )
    counts: dict[str, int] = {}
    for line in proc.stdout.splitlines():
        m = PY_TEST_ITEM_RE.match(line)
        if m:
            path = m.group(1).replace("\\", "/")
            counts[path] = counts.get(path, 0) + 1
    return counts


def collect_vitest_counts(root: Path) -> dict[str, int] | None:
    """运行 ``npx vitest list`` 收集前端用例数；不可用返回 None（降级跳过）。

    降级条件：frontend/node_modules/vitest 缺失、npx 不可用、命令失败或超时。
    """
    frontend = root / "frontend"
    if not (frontend / "node_modules" / "vitest").exists():
        return None
    npx = shutil.which("npx")
    if npx is None:
        return None
    try:
        proc = _run([npx, "vitest", "list"], frontend)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    counts: dict[str, int] = {}
    for line in proc.stdout.splitlines():
        m = JS_TEST_LINE_RE.match(line)
        if m:
            path = f"frontend/{m.group(1)}"
            counts[path] = counts.get(path, 0) + 1
    return counts


def collect_cargo_counts(root: Path) -> dict[str, int] | None:
    """收集 Rust 测试用例数；不可用返回 None（降级跳过）。

    集成测试按 src-tauri/tests/*.rs 每文件独立 ``cargo test --test <名> -- --list``；
    src-tauri/src/lib.rs 内 ``#[cfg(test)] mod tests`` 单元测试经
    ``cargo test --lib -- --list`` 归属 lib.rs（当前唯一单元测试宿主）。
    """
    tauri = root / "src-tauri"
    if not (tauri / "Cargo.toml").exists():
        return None
    cargo = shutil.which("cargo")
    if cargo is None:
        return None
    counts: dict[str, int] = {}

    def count_tests(argv: list[str]) -> int:
        try:
            proc = _run([cargo, *argv, "--", "--list"], tauri, timeout=600)
        except (OSError, subprocess.TimeoutExpired):
            return -1
        if proc.returncode != 0:
            return -1
        return sum(
            1 for line in proc.stdout.splitlines() if CARGO_TEST_LINE_RE.search(line)
        )

    for p in sorted((tauri / "tests").glob("*.rs")):
        n = count_tests(["test", "--test", p.stem])
        if n < 0:
            return None
        counts[f"src-tauri/tests/{p.name}"] = n
    n = count_tests(["test", "--lib"])
    if n < 0:
        return None
    if n:
        counts["src-tauri/src/lib.rs"] = n
    return counts


def collect_source_files(root: Path) -> set[str]:
    """扫描仓库全部 .py/.js/.rs 源文件，返回相对路径集合（正斜杠，排除生成物目录）。

    与 CODE_WIKI 的文档引用做双向覆盖：新增源文件漏进 §3 树、删除/改名
    文件残留引用都会被拦截（叙述部分无机械标记，文件级引用是唯一兜底）。
    """
    files: set[str] = set()
    for p in root.rglob("*.py"):
        parts = p.relative_to(root).parts
        if not any(part in _EXCLUDED_DIRS for part in parts):
            files.add("/".join(parts))
    for suffix in (".js", ".rs"):
        for p in root.rglob(f"*{suffix}"):
            parts = p.relative_to(root).parts
            if not any(part in _EXCLUDED_DIRS for part in parts):
                files.add("/".join(parts))
    return files


def collect_doc_file_refs(text: str) -> set[str]:
    """收集文档引用的全部源文件路径（相对项目根，正斜杠）。

    两类来源：反引号引用（`backend/app/main.py`）与 §3 文件树行
    （`│   ├── chat.py`，树行惯用裸名且无反引号）。
    """
    refs = {m.group(1).replace("\\", "/") for m in FILE_REF_RE.finditer(text)}
    refs |= {m.group(1).replace("\\", "/") for m in TREE_FILE_RE.finditer(text)}
    return refs


def count_nonblank_lines(path: Path) -> int:
    """统计非空行数（§4 标题的（~N 行）口径）。"""
    n = 0
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                n += 1
    return n


# ── 签名提取（py：AST / js、rs：正则）──────────────────────


def _default_text(node: ast.expr | None) -> str | None:
    """把参数默认值渲染为短文本。

    只展示「字面量 / 简单符号」：数字、字符串、None/True/False、一元正负、
    Name、Attribute。Call 等复杂表达式省略默认值（避免方法表噪音）。
    """
    if node is None:
        return None
    if isinstance(node, ast.Constant):
        v = node.value
        if v is None:
            return "None"
        if isinstance(v, bool):
            return "True" if v else "False"
        if isinstance(v, str):
            return repr(v)
        if isinstance(v, (int, float)):
            return repr(v)
        return None
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
        inner = node.operand
        if isinstance(inner, ast.Constant) and isinstance(inner.value, (int, float)):
            sign = "-" if isinstance(node.op, ast.USub) else ""
            return f"{sign}{inner.value!r}"
        return None
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return ast.unparse(node)
    return None


def render_signature(fn: ast.FunctionDef) -> str:
    """把函数 AST 渲染为 ``name(params)`` 签名文本（不含 self/cls，略复杂默认值）。"""
    a = fn.args
    posonly = list(a.posonlyargs)
    positional = list(a.args)
    all_pos = posonly + positional

    if all_pos and all_pos[0].arg in ("self", "cls"):
        if posonly:
            posonly.pop(0)
        else:
            positional.pop(0)
        all_pos = posonly + positional

    defaults = list(a.defaults)
    offset = len(all_pos) - len(defaults)

    parts: list[str] = []
    for i, arg in enumerate(all_pos):
        txt = arg.arg
        if i >= offset:
            d = _default_text(defaults[i - offset])
            if d is not None:
                txt = f"{arg.arg}={d}"
        parts.append(txt)

    if posonly:
        parts.insert(len(posonly), "/")

    if a.vararg is not None:
        parts.append(f"*{a.vararg.arg}")
    elif a.kwonlyargs:
        parts.append("*")

    for i, arg in enumerate(a.kwonlyargs):
        txt = arg.arg
        d = _default_text(a.kw_defaults[i])
        if d is not None:
            txt = f"{arg.arg}={d}"
        parts.append(txt)

    if a.kwarg is not None:
        parts.append(f"**{a.kwarg.arg}")

    return f"{fn.name}({', '.join(parts)})"


def _is_property(fn: ast.FunctionDef) -> bool:
    return any(
        isinstance(d, ast.Name) and d.id in ("property", "cached_property")
        for d in fn.decorator_list
    )


def _render_py(fn: ast.FunctionDef) -> str:
    """按函数形态渲染：property 无括号，普通方法带签名。"""
    if _is_property(fn):
        return fn.name
    return render_signature(fn)


# JS 模块级函数：`export function name(...)` / `function name(...)` / `async function`
# （MULTILINE：^ 按行匹配，finditer 全文可用）
_JS_FN_RE = re.compile(
    r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(([^)]*)\)",
    re.MULTILINE,
)

# JS 简单箭头函数：`const name = (a, b) =>`（单行；复杂解构/跨行签名不解析，
# 文档中对这类符号用「名称列」引用，只锁存在性）
_JS_CONST_FN_RE = re.compile(
    r"^\s*(?:export\s+)?const\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\(([^)\n]*)\)\s*=>",
    re.MULTILINE,
)

# Rust 函数：`pub fn name(...)` / `fn name(...)`，带可选的返回类型
_RS_FN_RE = re.compile(
    r"^\s*(?:pub(?:\(crate\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_][\w]*)"
    r"\s*(?:<[^>]*>)?\(([^)]*)\)\s*(?:->\s*([^{;]+))?",
    re.MULTILINE,
)
_RS_IMPL_RE = re.compile(
    r"^\s*impl(?:\s+<[^>]+>)?\s+([A-Za-z_][\w]*)", re.MULTILINE
)


def _js_symbol_map(text: str) -> dict[str, str]:
    """JS 模块级函数映射：{函数名: 渲染签名}（function 优先，const 兜底）。"""
    syms = {m.group(1): _render_js_fn(m) for m in _JS_FN_RE.finditer(text)}
    for m in _JS_CONST_FN_RE.finditer(text):
        syms.setdefault(m.group(1), _render_js_fn(m))
    return syms


def _rs_symbol_map(text: str) -> dict[str, str]:
    """Rust fn 映射：{符号名: 渲染签名}；impl 块内方法 key 带 `Type.method` 前缀。

    用大括号深度追踪 impl 边界（fn 体内的独立 ``}`` 不会误退出）；
    括号计数为近似（字符串/注释内的括号可能扰动，仅影响 impl 归属，可接受）。
    """
    syms: dict[str, str] = {}
    in_impl: str | None = None
    depth = 0
    for line in text.splitlines():
        m = _RS_IMPL_RE.match(line)
        if m and depth == 0:
            in_impl = m.group(1)
        m = _RS_FN_RE.match(line)
        if m:
            name = m.group(1)
            key = f"{in_impl}.{name}" if in_impl else name
            syms[key] = _render_rs_fn(m)
        depth += line.count("{") - line.count("}")
        if depth <= 0 and in_impl:
            in_impl = None
            depth = 0
    return syms


def _collect_js_symbols(text: str) -> set[str]:
    """JS 模块级函数名集合（宽松存在性校验用）。"""
    return set(_js_symbol_map(text))


def _collect_rs_symbols(text: str) -> set[str]:
    """Rust fn 名集合（impl 块内方法带 `Type.method` 前缀）。"""
    return set(_rs_symbol_map(text))


def _render_js_fn(m: re.Match) -> str:
    return f"{m.group(1)}({m.group(2).strip()})"


def _render_rs_fn(m: re.Match) -> str:
    out = f"{m.group(1)}({m.group(2).strip()})"
    ret = (m.group(3) or "").strip()
    if ret:
        out += f" -> {ret}"
    return out


def resolve_signature(module: Path, symbol: str) -> str | None:
    """返回模块中符号的渲染签名；符号不存在返回 None。

    symbol 形如 ``main``（模块级函数）或 ``BaseLLM.generate``（类方法）。
    常量/枚举成员等非函数符号返回 None（会被判为 stale）。
    """
    try:
        text = module.read_text(encoding="utf-8")
    except OSError:
        return None
    suffix = module.suffix
    if suffix == ".py":
        try:
            tree = ast.parse(text)
        except SyntaxError:
            return None
        if "." not in symbol:
            for node in tree.body:
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == symbol:
                    return _render_py(node)
            return None
        cls_name, _, meth = symbol.partition(".")
        for node in tree.body:
            if isinstance(node, ast.ClassDef) and node.name == cls_name:
                for item in node.body:
                    if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) and item.name == meth:
                        return _render_py(item)
                return None
        return None
    if suffix == ".js":
        return _js_symbol_map(text).get(symbol)
    if suffix == ".rs":
        return _rs_symbol_map(text).get(symbol)
    return None


def resolve_symbol_exists(module: Path, symbol: str) -> bool:
    """宽松存在性校验：symbol（含 `Type.method` 形式）在模块中是否存在。

    py 走 AST 名称集合；js/rs 走文本符号集合（含 impl 前缀）。
    用于 sig「名称列」（无括号形态）的校验——复杂签名（如 JS 解构参数、
    跨行签名）无法机械渲染时，文档以纯名称引用，只锁存在性。
    """
    try:
        text = module.read_text(encoding="utf-8")
    except OSError:
        return False
    suffix = module.suffix
    if suffix == ".py":
        try:
            tree = ast.parse(text)
        except SyntaxError:
            return False
        if "." not in symbol:
            return any(
                isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == symbol
                for n in tree.body
            )
        cls_name, _, meth = symbol.partition(".")
        for node in tree.body:
            if isinstance(node, ast.ClassDef) and node.name == cls_name:
                return any(
                    isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)) and m.name == meth
                    for m in node.body
                )
        return False
    if suffix == ".js":
        return symbol in _collect_js_symbols(text)
    if suffix == ".rs":
        return symbol in _collect_rs_symbols(text)
    return False


# ── 标记计算 ──────────────────────────────────────────────


class _Unavailable(KeyError):
    """渠道不可用（vitest/cargo 降级），标记跳过而非报漂移。"""


def compute_content(
    kind: str, key: str, root: Path, counts: dict[str, int]
) -> str:
    """计算某标记当前的机械文本（不含 HTML 注释壳）。

    counts 携带渠道可用性：{路径: 用例数}，另有伪 key
    ``_pytest_total`` / ``_vitest_total`` / ``_cargo_total`` / ``_grand_total``。
    """
    if kind == "lines":
        return f"~{count_nonblank_lines(root / key)} 行"
    if kind == "tests_total":
        if key == "pytest":
            return str(counts["_pytest_total"])
        if key == "vitest":
            if "_vitest_total" not in counts:
                raise _Unavailable("vitest 渠道不可用（未安装/执行失败）")
            return str(counts["_vitest_total"])
        if key == "cargo":
            if "_cargo_total" not in counts:
                raise _Unavailable("cargo 渠道不可用（未安装/编译失败）")
            return str(counts["_cargo_total"])
        if key == "total":
            return str(counts["_grand_total"])
        raise KeyError(f"未知 tests_total 键: {key}")
    if kind == "tests":
        count = counts.get(key)
        if count is None:
            raise KeyError(f"未收集到该测试文件: {key}")
        return str(count)
    if kind == "sig":
        module, _, symbol = key.partition(":")
        sig = resolve_signature(root / module, symbol)
        if sig is None:
            raise KeyError(f"符号不存在: {key}")
        return f"`{sig}`"
    raise ValueError(f"未知标记类型: {kind!r}")


def scan_markers(text: str) -> list[tuple[str, str, str, int, int]]:
    """扫描文档中全部标记，返回 (kind, key, content, start, end)。"""
    return [
        (m.group("kind"), m.group("key"), m.group("content"), m.start(), m.end())
        for m in MARKER_RE.finditer(text)
    ]


def _sig_check(key: str, content: str, root: Path, issues: list[str]) -> None:
    """校验 sig 标记：含括号 → 严格签名一致；纯名称 → 宽松存在性。"""
    module, _, symbol = key.partition(":")
    stripped = content.strip().strip("`")
    name = symbol.split(".")[-1]
    if stripped == name and "(" not in stripped:
        if not resolve_symbol_exists(root / module, symbol):
            issues.append(f"[sig] 符号不存在（删除/改名？）: {key}")
        return
    rendered = resolve_signature(root / module, symbol)
    if rendered is None:
        issues.append(f"[sig] 符号不存在（删除/改名？）: {key}")
    elif stripped != rendered:
        issues.append(f"[sig] 签名不一致: {key}  文档={content!r}  实际=`{rendered}`")


# ── 校验 / 更新 ───────────────────────────────────────────


def _gather_issues(
    text: str, root: Path, counts: dict[str, int]
) -> list[str]:
    """汇总全部漂移项（内容不一致 + 结构覆盖 + 符号 stale）。"""
    issues: list[str] = []
    markers = scan_markers(text)

    for kind, key, content, _, _ in markers:
        if kind == "sig":
            _sig_check(key, content, root, issues)
            continue
        try:
            expected = compute_content(kind, key, root, counts)
        except _Unavailable:
            continue
        except KeyError as e:
            issues.append(f"[{kind}] {key}: {e}")
            continue
        if content != expected:
            issues.append(
                f"[{kind}] {key}: 文档={content!r} 实际={expected!r}"
            )

    # tests：双向覆盖（新测试文件漏标 / 标记指向已删文件）
    tests_marked = {key for kind, key, *_ in markers if kind == "tests"}
    test_files = {
        k for k in counts if k.startswith(("backend/tests/", "frontend/tests/", "src-tauri/tests/"))
    }
    for path in sorted(test_files):
        if path not in tests_marked:
            issues.append(
                f"[tests] 缺少标记: {path}（收集 {counts[path]} 个用例，文档无 tests: 标记）"
            )
    for key in sorted(tests_marked):
        if key not in counts:
            issues.append(f"[tests] 标记指向未收集的测试文件: {key}")

    # lines：双向覆盖（新 §4 标题漏标 / 标记无对应标题）
    lines_marked = {key for kind, key, *_ in markers if kind == "lines"}
    headings = {m.group(1) for m in HEADING_RE.finditer(text)}
    for path in sorted(headings):
        if path not in lines_marked:
            issues.append(f"[lines] §4 标题缺少行数标记: {path}")
    for key in sorted(lines_marked):
        if key not in headings:
            issues.append(f"[lines] 行数标记无对应 §4 标题: {key}")

    # files：叙述反引号引用存在性 + 仓库源文件 ↔ 文档引用双向覆盖。
    # 引用分两形态：带路径（backend/app/main.py）→ 相对路径精确存在；
    # 裸文件名（chat.py/__init__.py，§3 文件树与历史叙述惯用）→ 仓库同名即可。
    # 双向覆盖按「路径或裸名任一出现」判定，保 §3 树「文件名列表」语义。
    source_files = collect_source_files(root)
    source_names = {p.rsplit("/", 1)[-1] for p in source_files}
    refs = collect_doc_file_refs(text)
    ref_paths = {r for r in refs if "/" in r}
    ref_names = {r for r in refs if "/" not in r}
    for ref in sorted(refs):
        if ref in _KNOWN_RETIRED:
            continue
        exists = (root / ref).exists() if "/" in ref else ref in source_names
        if not exists:
            issues.append(f"[files] 文档引用不存在的文件: {ref}（删除/改名？或补入退役名单）")
    for path in sorted(source_files):
        if path not in ref_paths and path.rsplit("/", 1)[-1] not in ref_names:
            issues.append(f"[files] 源文件未出现在文档引用中: {path}")

    return issues


def _sig_update_text(key: str, content: str, root: Path) -> str | None:
    """返回 sig 标记的新内容（保持原样式）；符号不存在返回 None（无法修复）。"""
    module, _, symbol = key.partition(":")
    if "(" in content.strip().strip("`"):
        rendered = resolve_signature(root / module, symbol)
        if rendered is None:
            return None
        return f"`{rendered}`"
    if not resolve_symbol_exists(root / module, symbol):
        return None
    return f"`{symbol.split('.')[-1]}`"


def _collect_counts(root: Path) -> dict[str, int]:
    """汇总三渠道用例数；pytest 失败抛 RuntimeError，vitest/cargo 降级跳过。"""
    counts = collect_pytest_counts(root)
    counts["_pytest_total"] = sum(counts.values())
    vitest = collect_vitest_counts(root)
    if vitest is not None:
        counts.update(vitest)
        counts["_vitest_total"] = sum(vitest.values())
    cargo = collect_cargo_counts(root)
    if cargo is not None:
        counts.update(cargo)
        counts["_cargo_total"] = sum(cargo.values())
    counts["_grand_total"] = (
        counts.get("_pytest_total", 0)
        + counts.get("_vitest_total", 0)
        + counts.get("_cargo_total", 0)
    )
    return counts


def run_update(
    doc: Path, root: Path, verbose: bool
) -> tuple[int, list[str]]:
    """就地刷新所有现有标记内容；返回 (变更数, 提示行)。"""
    text = doc.read_text(encoding="utf-8")
    counts = _collect_counts(root)
    notes: list[str] = []
    changed = 0

    def repl(m: re.Match) -> str:
        nonlocal changed
        kind, key, content = m.group("kind"), m.group("key"), m.group("content")
        if kind == "sig":
            new_text = _sig_update_text(key, content, root)
            if new_text is None:
                notes.append(f"  ⚠ 跳过（符号不存在，无法刷新）: {key}")
                return m.group(0)
        else:
            try:
                new_text = compute_content(kind, key, root, counts)
            except _Unavailable as e:
                notes.append(f"  ⚠ 跳过（{e}）: {kind}:{key}")
                return m.group(0)
            except KeyError as e:
                notes.append(f"  ⚠ 跳过（{e}）: {kind}:{key}")
                return m.group(0)
        if new_text == content:
            return m.group(0)
        changed += 1
        if verbose:
            notes.append(f"  {kind}:{key}: {content!r} → {new_text!r}")
        return m.group(0).replace(content, new_text, 1)

    new_text = MARKER_RE.sub(repl, text)
    if changed:
        doc.write_text(new_text, encoding="utf-8")

    remaining = _gather_issues(new_text, root, counts)
    return changed, notes + [f"  {s}" for s in remaining]


def run_check(
    doc: Path, root: Path, verbose: bool
) -> tuple[bool, list[str]]:
    """校验全部标记与结构；返回 (是否通过, 输出行)。"""
    text = doc.read_text(encoding="utf-8")
    try:
        counts = _collect_counts(root)
    except RuntimeError as e:
        return False, [str(e)]
    issues = _gather_issues(text, root, counts)
    if verbose or issues:
        n = len(scan_markers(text))
        header = f"doc_sync --check: CODE_WIKI.md（{n} 个标记）"
        if not issues:
            return True, [header + " 同步 ✅"]
        return False, [header + " 漂移 ❌"] + [f"  {s}" for s in issues]
    return True, []


def dump_symbols(module: Path) -> int:
    """输出模块符号表（供写作/维护 §4 方法表）。

    每行一个符号：可渲染签名输出 ``name(params)``；无法渲染的复杂符号
    （JS 解构/跨行签名、Rust 复杂形态）输出纯名称——对应「名称列」用法。
    """
    text = module.read_text(encoding="utf-8")
    suffix = module.suffix
    if suffix == ".py":
        try:
            tree = ast.parse(text)
        except SyntaxError:
            print(f"dump: 无法解析 {module}", file=sys.stderr)
            return 2
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                print(_render_py(node))
            elif isinstance(node, ast.ClassDef):
                for m in node.body:
                    if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        print(f"{node.name}.{_render_py(m)}")
        return 0
    if suffix == ".js":
        for name in sorted(_js_symbol_map(text)):
            print(_js_symbol_map(text)[name])
        return 0
    if suffix == ".rs":
        for key in sorted(_rs_symbol_map(text)):
            print(f"{key} | {_rs_symbol_map(text)[key]}")
        return 0
    print(f"dump: 不支持的扩展名 {suffix}", file=sys.stderr)
    return 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="校验模式：存在漂移则 exit 1（pre-commit 钩子用）；默认是更新模式",
    )
    parser.add_argument(
        "--doc",
        type=Path,
        default=None,
        help="目标文档路径（默认 <root>/CODE_WIKI.md）",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="项目根目录（默认由脚本位置推导）",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="输出每个标记的变更/校验明细",
    )
    parser.add_argument(
        "--dump",
        metavar="MODULE",
        default=None,
        help="输出指定模块的符号表后退出（写作 §4 方法表用）",
    )
    args = parser.parse_args(argv)

    root = args.root or project_root()

    if args.dump:
        return dump_symbols(root / args.dump)

    doc = args.doc or (root / "CODE_WIKI.md")

    if not doc.exists():
        print(f"doc_sync: 文档不存在: {doc}", file=sys.stderr)
        return 2

    if args.check:
        ok, lines = run_check(doc, root, args.verbose)
        print("\n".join(lines))
        return 0 if ok else 1

    changed, lines = run_update(doc, root, args.verbose)
    print("\n".join(lines))
    print(f"doc_sync --update: {changed} 个标记已刷新（现有标记就地更新，不新增）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
