"""pubspec.lock 全量依赖的追踪-SDK 排除名单审计（可 import，T04 门禁复用）。

「零第三方 SDK 追踪」= 依赖树（pubspec.lock 直接 + 传递全量包名）命中排除名单条数为 0。
口径（与 docs/privacy-android.md 一致）：「收集 = 上传至第三方服务器」；排查范围限定在本库
依赖事实（pubspec.lock）；匹配按包名字串子串命中 TRACKING_PATTERNS。

用法：
    python scripts/privacy_audit.py [项目根目录]          # CLI（默认当前目录）
    from privacy_audit import audit_project, TRACKING_PATTERNS
    result = audit_project(".")                            # 读 pubspec.yaml + pubspec.lock
    result.is_clean  # True = 零第三方 SDK 追踪实证通过

只读、无副作用——不修改 pubspec / lock / manifest。未来任何新增依赖（含传递依赖）都必须过
此审计（新增后先 `flutter pub get` 刷新 lock 再审计，否则 unresolved_direct 会报警）。
"""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

__all__ = [
    "TRACKING_PATTERNS",
    "AuditResult",
    "LockedPackage",
    "audit_lockfile",
    "audit_project",
    "main",
    "parse_lock_packages",
    "parse_pubspec_direct_names",
]

# 追踪 / 统计 / 崩溃上报 SDK 排除名单（包名字串子串命中）。
# 每条即一个 vendor 的「该 vendor 旗下全部包」检测锚点：appsflyer / sentry /
# firebase / mixpanel / amplitude / adjust / braze / branch / clevertap /
# kochava / crashlytics。名单变更须同步 docs/privacy-android.md §③ 与本节注释。
TRACKING_PATTERNS: tuple[str, ...] = (
    "appsflyer",
    "firebase",
    "amplitude",
    "mixpanel",
    "sentry",
    "crashlytics",
    "adjust",
    "braze",
    "branch",
    "clevertap",
    "kochava",
)

# pubspec.lock 包条目首行：两空格缩进的 `name:`（四/六空格者是 description 内嵌键，不匹配）
_PACKAGE_HEADER_RE = re.compile(r"^  ([A-Za-z0-9_.-]+):$")
# pubspec.yaml 依赖节条目（两空格缩进）：顶层键（零缩进，含 `flutter:`/`name:`）不是条目
_ENTRY_RE = re.compile(r"^  ([A-Za-z0-9_]+):")
_TOP_KEY_RE = re.compile(r"^[A-Za-z0-9_]+:")


@dataclass(frozen=True)
class LockedPackage:
    """pubspec.lock 中的一个包记录（含传递依赖——lock 列出的即是全量）。"""

    name: str
    version: str = ""
    dependency_kind: str = ""  # "direct main" / "direct dev" / "transitive"
    source: str = ""  # "hosted" / "sdk" / "git" / "path"


@dataclass(frozen=True)
class AuditResult:
    """一次审计的结果：全量包数、命中名单、未解析的直接依赖。"""

    package_count: int
    hits: tuple[str, ...] = ()
    unresolved_direct: tuple[str, ...] = ()
    #: 审计使用的排除名单（审计方自持，便于报告与复读）
    patterns: tuple[str, ...] = TRACKING_PATTERNS

    @property
    def is_clean(self) -> bool:
        """零命中且无未解析直接依赖 = 零第三方 SDK 追踪实证通过。"""
        return not self.hits and not self.unresolved_direct


def _strip_quote(value: str) -> str:
    """去值两侧引号（lock 中 version/dependency 可能带引号）。"""
    return value.strip().strip("\"'")


def parse_lock_packages(lock_text: str) -> list[LockedPackage]:
    """解析 pubspec.lock 的 packages 段，返回全部包记录（直接 + 传递）。

    lock 是 pub 机器生成文件，结构固定：`packages:` 下每个包首行为两空格缩进的 `name:`，
    其内 4 空格缩进为 version / dependency / source / description 键。sdks 段（零缩进
    顶层键）不参与。空文本 / 无 packages 段 → 空列表。
    """
    packages: list[LockedPackage] = []
    lines = lock_text.splitlines()
    i = 0
    n = len(lines)
    while i < n and not lines[i].strip().startswith("packages:"):
        i += 1
    if i >= n:
        return packages
    i += 1
    while i < n:
        line = lines[i]
        if line and not line[0].isspace():
            break  # 顶层键（sdks: 等），packages 段结束
        if not line.strip():
            i += 1
            continue
        m = _PACKAGE_HEADER_RE.match(line)
        if not m:
            i += 1
            continue
        name = m.group(1)
        version = ""
        kind = ""
        source = ""
        i += 1
        while i < n:
            sub = lines[i]
            if not sub or sub[0] != " ":
                break  # 顶层键或行尾，条目结束
            if _PACKAGE_HEADER_RE.match(sub):
                break  # 下一包条目首行，条目结束
            key, _, value = sub.strip().partition(":")
            if key == "version":
                version = _strip_quote(value)
            elif key == "dependency":
                kind = _strip_quote(value)
            elif key == "source":
                source = _strip_quote(value)
            i += 1
        packages.append(LockedPackage(name=name, version=version, dependency_kind=kind, source=source))
    return packages


def parse_pubspec_direct_names(pubspec_text: str) -> list[str]:
    """提取 pubspec.yaml 直接依赖名（dependencies + dev_dependencies 两节）。

    条目 = 两空格缩进的 `name:` 行；四空格缩进为嵌套键（如 `sdk: flutter`），零缩进顶层键
    或注释行不中断依赖节。作「直接依赖是否已在 lock 解析」的过期防护输入。
    """
    names: list[str] = []
    in_section = False
    for line in pubspec_text.splitlines():
        stripped = line.strip()
        if stripped in ("dependencies:", "dev_dependencies:"):
            in_section = True
            continue
        if in_section:
            if _TOP_KEY_RE.match(line):
                in_section = False  # 下一个顶层键（flutter: / name: / 注释行除外）结束依赖节
                continue
            m = _ENTRY_RE.match(line)
            if m:
                names.append(m.group(1))
    return names


def _matches_any(name: str, patterns: Sequence[str]) -> bool:
    """包名字串子串命中任一排除模式。"""
    return any(p in name for p in patterns)


def audit_lockfile(
    lock_content: str,
    *,
    patterns: Sequence[str] = TRACKING_PATTERNS,
) -> AuditResult:
    """审计一份 pubspec.lock 文本，返回命中名单。

    lock_content 为 pubspec.lock 原文（str）；命中名单按包名在 lock 中出现顺序给出。
    非 str 输入抛 TypeError——本函数只接受 lock 文本形态（生产消费方 T04 门禁与 CLI
    均为文本路径，早期 str/Mapping 双输入分支为 Speculative Generality，已删除）。
    """
    if not isinstance(lock_content, str):
        raise TypeError(
            "audit_lockfile 只接受 pubspec.lock 文本（str），"
            f"收到 {type(lock_content).__name__}"
        )
    packages = parse_lock_packages(lock_content)
    hits = tuple(p.name for p in packages if _matches_any(p.name, patterns))
    return AuditResult(package_count=len(packages), hits=hits)


def audit_project(
    project_dir: str | Path = ".",
    *,
    patterns: Sequence[str] = TRACKING_PATTERNS,
) -> AuditResult:
    """审计一个项目目录：读 pubspec.yaml + pubspec.lock，输出命中名单与未解析直接依赖。

    未解析直接依赖 = pubspec.yaml 声明了但 pubspec.lock 没有（lock 过期）——此类「直接依赖
    不是 lock 全量一部分」也会让零收集结论失去实证，故一并报警。文件缺失抛 FileNotFoundError。
    """
    root = Path(project_dir)
    lock_path = root / "pubspec.lock"
    pubspec_path = root / "pubspec.yaml"
    missing = [str(p) for p in (pubspec_path, lock_path) if not p.is_file()]
    if missing:
        raise FileNotFoundError(f"缺少审计输入：{', '.join(missing)}")
    packages = parse_lock_packages(lock_path.read_text(encoding="utf-8"))
    direct = parse_pubspec_direct_names(pubspec_path.read_text(encoding="utf-8"))
    locked = {p.name for p in packages}
    hits = tuple(p.name for p in packages if _matches_any(p.name, patterns))
    unresolved = tuple(d for d in direct if d not in locked)
    return AuditResult(package_count=len(packages), hits=hits, unresolved_direct=unresolved)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=(
            "pubspec.lock 全量依赖（直接+传递）的追踪-SDK 排除名单审计："
            "零命中即「零第三方 SDK 追踪」实证通过；pubspec.yaml 声明但 lock 未解析也报警。"
        )
    )
    ap.add_argument(
        "project_dir",
        nargs="?",
        default=".",
        help="项目根目录（含 pubspec.yaml 与 pubspec.lock），默认当前目录",
    )
    args = ap.parse_args(argv)
    try:
        result = audit_project(Path(args.project_dir))
    except FileNotFoundError as exc:
        print(f"[privacy-audit] 失败:{exc}")
        return 1
    print(
        f"[privacy-audit] 审计 {result.package_count} 个包（直接+传递）"
        f"对 {len(result.patterns)} 条追踪-SDK 模式"
    )
    if result.hits:
        print(f"[privacy-audit] 命中 {len(result.hits)} 条（违反「零第三方 SDK 追踪」）：")
        for name in result.hits:
            print(f"  - {name}")
        return 1
    if result.unresolved_direct:
        print(
            f"[privacy-audit] {len(result.unresolved_direct)} 个直接依赖未在 pubspec.lock "
            "解析（lock 过期，先跑 flutter pub get 再审计）："
        )
        for name in result.unresolved_direct:
            print(f"  - {name}")
        return 1
    print("[privacy-audit] 命中 0，未解析直接依赖 0 —— OK：零第三方 SDK 追踪")
    return 0


if __name__ == "__main__":
    sys.exit(main())