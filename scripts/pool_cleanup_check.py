"""清出机制机械检查（挂 pre-commit，失败即拒绝提交）。

只读、无副作用——遵循仓库「gate first, side effects after」惯例，本脚本只报告违规与
处置指引，绝不自动修改文档（折叠/归档由人按指引执行，git 历史可溯）。

本脚本为**结构自适应**通用版，适用于 Craft 目录下各开发项目的同款 TECH_DEBT.md /
TO-TICKETS.md 文档（编号前缀 E-/TD-/T- 均支持），按文档结构自动判定两种模式：

- **simplified（B 简化，如 hanhua）**：无「技术债处置记录」台账节、已完成归档为每批一行
  纯索引 → 启用全部检查（含台账节缺失、纯索引行数上限）。
- **legacy（如 Control / GameCheating）**：保留处置记录台账与完整批次归档 → 跳过台账节
  缺失与纯索引相关检查，保留通用检查（候选区状态 / 复核关闭状态 / 活跃工单无 ✅❌ /
  重复标题 / 脚注最大编号一致 / 非空与必要节）。

检查项（唯一权威 = 各仓库 TECH_DEBT.md 规范说明「清出机制」，本清单为速览）：
1. TECH_DEBT 候选区主表只留开放条目（📝 待立项 / 🔄 进行中）
2. TECH_DEBT 不得再出现「技术债处置记录」台账节（仅 simplified 模式）
3. TECH_DEBT 复核关闭表状态全为 ❌ 复核关闭
4. TO-TICKETS 活跃工单/活跃表无 ✅/❌ 滞留
5. TO-TICKETS 已完成归档为每批一行纯索引，不得出现完整批次节（仅 simplified 模式）
6. TO-TICKETS 归档节内索引行数 ≤ MAX_INDEX_ROWS（仅 simplified 模式）
7. 两文件无重复顶层（## ）标题（跳过代码块、忽略尾随空格）
8. 脚注「当前最大 X-N」（维护说明/处置记录说明节内）与两文件表格行编号（含 +/ 简写）
   最大编号一致（防漂移；编号前缀从候选区自动探测）
9. 两文件非空且含必要节（候选区 / 活跃工单 + 已完成归档）
10. 节内表格行列数与表头不符的行显式报格式异常——绝不静默跳过（防列错位漏判状态）

表格解析契约：单元格不得含未转义 `|`（Markdown 表格列分隔符）；含则列数错位，
由检查 10 报格式异常并在提交前修复，而非误读状态列。
"""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Callable
from pathlib import Path

__all__ = ["MAX_INDEX_ROWS", "check_files", "main"]

MAX_INDEX_ROWS = 60
_STATUS_OPEN = {"📝 待立项", "🔄 进行中"}
_STATUS_CLOSED = "❌ 复核关闭"
_COL_ID = 0
_COL_STATUS = 4

_DISPOSAL_SECTION = "## 技术债处置记录"
_CANDIDATE_SECTION = "## 技术债候选区"
_CLOSED_SECTION_PREFIX = "### 复核关闭"
_ACTIVE_SECTIONS = ("## 活跃工单", "## 活跃表")
_INDEX_SECTION_PREFIX = "## 已完成归档"
_MAINTENANCE_SECTIONS = ("## 维护说明", "## 处置记录说明")
_TOP_HEADING = "## "
_BATCH_SECTION_RE = re.compile(r"^### 20\d\d")
_INDEX_ROW_RE = re.compile(r"^\| 20\d\d")
_FOOTER_PATTERN = re.compile(r"当前最大 ([A-Za-z]+-\d+)")
_ID_PREFIX_RE = re.compile(r"^\|\s*([A-Za-z]+)-(\d+)")
# 编号正则模板：`{p}` 由 _e_numbers 按探测前缀填充（E / TD / T）
_E_PATTERN = r"(?<![\w-]){p}-(\d+)(?:[+/](\d+))*"
# 空态占位符：表格节无条目时的 `| _（无）_ |` / `_（无）_` 行不参与状态判定
_EMPTY_PLACEHOLDERS = {"_（无）_", "（无）", "暂无", "_（空）_", "（空）", "—"}
# 表头首格标签（不同项目「编号」列名不同，如 Control 的候选区、conver 的 Ticket）
_HEADER_FIRST_CELLS = {"编号", "候选", "Ticket", "批次", "编号（E-N）"}


def _cells(line: str) -> list[str]:
    """表格行去壳取格（去头尾竖线、去空白）。

    契约：单元格内含未转义 `|` 属格式缺陷——由 _table_rows 的列数校验报格式异常，
    而非在本层猜测列位。
    """
    core = line.strip()
    if core.startswith("|"):
        core = core[1:]
    if core.endswith("|"):
        core = core[:-1]
    return [c.strip() for c in core.split("|")]


def _detect_prefix(td: str) -> str:
    """从候选区/复核关闭表首个编号提取前缀（E / TD / T），默认 E。"""
    for line in td.splitlines():
        m = _ID_PREFIX_RE.match(line)
        if m:
            return m.group(1)
    return "E"


def _is_simplified(td: str) -> bool:
    """simplified = 无「技术债处置记录」台账节（B 简化结构）。"""
    return _DISPOSAL_SECTION not in td


def _e_numbers(text: str, prefix: str) -> list[int]:
    """仅对表格行（| 开头）提取 `{prefix}-N` 编号（含 `+M`/`/M` 简写）。

    排除正文/列表行：正文大号假编号（如 E-999）不应拉高 max 造成 footer 误报；
    footer 行自报数字不得参与 max（否则「当前最大 E-250」自洽漏报方向性缺陷）。
    """
    nums: list[int] = []
    pattern = _E_PATTERN.format(p=prefix)
    for line in text.splitlines():
        if not line.strip().startswith("|"):
            continue
        for m in re.finditer(pattern, line):
            nums.append(int(m.group(1)))
            rest = m.group(0)[len(f"{prefix}-{m.group(1)}"):]
            nums.extend(int(s) for s in re.findall(r"[+/](\d+)", rest))
    return nums


def _is_placeholder_row(cells: list[str]) -> bool:
    """整行空态占位判定（如 `| — | （无待立项条目） | — | — | — | — |`）。

    编号列与状态列皆为占位符/空 → 非数据行，跳过状态判定。
    真实数据行编号列形如 `E-225`/`TD-85`/`T-01`，不命中。
    """
    first = cells[_COL_ID]
    if not (
        first in _EMPTY_PLACEHOLDERS
        or first.startswith("（无")
        or first.startswith("（当前无")
    ):
        return False
    if len(cells) <= _COL_STATUS:
        return True
    status = cells[_COL_STATUS]
    return not status.strip() or status in _EMPTY_PLACEHOLDERS


def _table_rows(
    text: str, start: str, end_prefix: str | None, expect_cells: int | None
) -> tuple[list[list[str]], list[str]]:
    """取节内表格行：返回 (可判定行, 格式异常行原文)。

    expect_cells = 期望列数；None = 以节内表头行（首格属 _HEADER_FIRST_CELLS）的列数为准
    （兼容各项目表头列数差异，如 conver 活跃表 4 列）。列数不符的行列为格式异常
    （不静默跳过，防漏判）。分隔行（含 `| :--- |` 对齐）、表头与整行占位跳过。
    """
    lines = text.splitlines()
    rows: list[list[str]] = []
    malformed: list[str] = []
    on = False
    for line in lines:
        if line.startswith(start):
            on = True
            continue
        if on and end_prefix is not None and line.startswith(end_prefix):
            break
        if not on:
            continue
        stripped = line.strip()
        if not stripped or not stripped.startswith("|"):
            continue
        if set(stripped) <= {"|", "-", " ", ":"}:
            continue
        cells = _cells(line)
        if not cells:
            continue
        if cells[0] in _HEADER_FIRST_CELLS:
            if expect_cells is None:
                expect_cells = len(cells)  # 表头列数即表格契约列数
            continue
        if _is_placeholder_row(cells):
            continue  # 整行空态占位（候选区/复核关闭「无条目」占位），非数据行
        if len(cells) == 1 and cells[0] in _EMPTY_PLACEHOLDERS:
            continue  # 单格空态占位行（如 `| _（无）_ |`）
        if expect_cells is not None and len(cells) != expect_cells:
            malformed.append(stripped[:80])
            continue
        rows.append(cells)
    return rows, malformed


def _table_violations(
    text: str,
    start: str,
    end_prefix: str | None,
    expect_cells: int | None,
    label: str,
    check_row: Callable[[list[str]], str | None],
) -> list[str]:
    """节内表格行状态检查：check_row(row) 返回违规描述（None = 通过）。

    格式异常行独立报告，不做状态判定。
    """
    rows, malformed = _table_rows(text, start, end_prefix, expect_cells)
    expect_note = "以表头列数为准" if expect_cells is None else f"应 {expect_cells} 列"
    violations = [f"{label} 表格格式异常（{expect_note}）：{r}" for r in malformed]
    for cells in rows:
        msg = check_row(cells)
        if msg:
            violations.append(msg)
    return violations


def _check_candidate_section(text: str, section: str = _CANDIDATE_SECTION) -> list[str]:
    def bad(cells: list[str]) -> str | None:
        if not any(cells[_COL_STATUS].startswith(s) for s in _STATUS_OPEN):
            return (
                f"TECH_DEBT 候选区 {cells[_COL_ID]} 状态「{cells[_COL_STATUS]}」非开放条目——"
                "已处置条目整行移出候选区，处置详情只写 DEV_LOG"
            )
        return None

    # 截止 = 复核关闭节（若有），否则下一顶级节（## ）——兼容无复核关闭表的仓库
    # （如 conver mobile 用「## 候选区」，候选区后直接接「## 技术债处置记录」）
    end_prefix = _CLOSED_SECTION_PREFIX if _CLOSED_SECTION_PREFIX in text else _TOP_HEADING
    return _table_violations(
        text, section, end_prefix, None, "TECH_DEBT 候选区", bad
    )


def _check_closed_section(text: str) -> list[str]:
    def bad(cells: list[str]) -> str | None:
        # 前缀匹配：兼容 `❌ 复核关闭（理由…）` 注释后缀（Control 写法），
        # 但仍拦下 `❌ 不立项` 等非关闭态
        if not cells[_COL_STATUS].startswith(_STATUS_CLOSED):
            return (
                f"TECH_DEBT 复核关闭表 {cells[_COL_ID]} 状态「{cells[_COL_STATUS]}」"
                f"非「{_STATUS_CLOSED}」"
            )
        return None

    # 限界 = 下一个顶级节（## ）：复核关闭表后若有其他表格，不该被误读为本表行
    return _table_violations(
        text, _CLOSED_SECTION_PREFIX, _TOP_HEADING, None, "TECH_DEBT 复核关闭表", bad
    )


def _active_list_violations(text: str) -> list[str]:
    """活跃节内列表行（`- ` 开头）的状态标记检测：含 ✅/❌ 即完成/关闭态滞留。

    活跃工单既可能是表格行（`|` 开头，走 _table_violations 的表格路径）也可能是列表
    行（`- ✅ **T-01** …` / `- 📝 **E-101** …`）——列表行的状态标记落在行内文本而非
    单元格，单独扫描。跳过代码块（围栏内示例可能含 ✅/❌，如 DEV_LOG 引用）与表格行；
    终止于活跃节后下一个顶级节（## ），兼容「活跃表后直接接其他节」的仓库。
    """
    violations: list[str] = []
    lines = text.splitlines()
    in_section = False
    in_fence = False
    for line in lines:
        if line.strip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if any(line.startswith(s) for s in _ACTIVE_SECTIONS):
            in_section = True
            continue
        if in_section and line.startswith(_TOP_HEADING):
            break
        if not in_section:
            continue
        stripped = line.strip()
        if not stripped.startswith("- "):  # 表格行/正文跳过，仅扫 `- ` 列表行
            continue
        if "✅" in stripped or "❌" in stripped:
            label = stripped.split("（", 1)[0].split("：", 1)[0][:60]
            violations.append(
                f"TO-TICKETS 活跃工单出现完成/关闭态行「{label}」——完成即归档"
            )
    return violations


def _check_active_section(text: str) -> list[str]:
    def bad(cells: list[str]) -> str | None:
        if any(("✅" in c or "❌" in c) for c in cells):
            return f"TO-TICKETS 活跃工单出现完成/关闭态行「{'|'.join(cells[:2])}」——完成即归档"
        return None

    violations: list[str] = []
    for section in _ACTIVE_SECTIONS:
        # expect_cells=None：列数以节内表头为准（conver 活跃表 4 列 / 标准 3 列均兼容）
        violations += _table_violations(
            text, section, _INDEX_SECTION_PREFIX, None, "TO-TICKETS 活跃工单", bad
        )
    violations += _active_list_violations(text)
    return violations


def _check_no_full_batch_sections(text: str) -> list[str]:
    relics = [l for l in text.splitlines() if _BATCH_SECTION_RE.match(l)]
    if relics:
        return [
            "TO-TICKETS 出现完整批次节，须折叠为索引行（每批一行）："
            + "；".join(r.strip("# ").split("（")[0] for r in relics[:5])
        ]
    return []


def _check_index_row_count(text: str) -> list[str]:
    count = 0
    in_section = False
    for line in text.splitlines():
        if line.startswith(_INDEX_SECTION_PREFIX):
            in_section = True
            continue
        if in_section and line.startswith(_TOP_HEADING):
            break
        if in_section and _INDEX_ROW_RE.match(line):
            count += 1
    if count > MAX_INDEX_ROWS:
        return [
            f"TO-TICKETS 归档索引 {count} 行 > 上限 {MAX_INDEX_ROWS}——删最旧（git 历史可溯）"
        ]
    return []


def _check_duplicate_heads(text: str, label: str) -> list[str]:
    heads: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if line.strip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if line.startswith(_TOP_HEADING):
            heads.append(line.rstrip())
    seen: dict[str, int] = {}
    for h in heads:
        seen[h] = seen.get(h, 0) + 1
    dups = [h for h, n in seen.items() if n > 1]
    return [f"{label} 重复顶层标题「{h}」×{seen[h]}" for h in dups]


def _check_disposal_section_absent(text: str) -> list[str]:
    if _DISPOSAL_SECTION in text:
        return [
            f"TECH_DEBT 出现「{_DISPOSAL_SECTION}」台账节——2026-08-31 简化后删除，处置详情只写 DEV_LOG"
        ]
    return []


def _footer_max_from(text: str) -> int | None:
    """锁定「维护说明」（兼容旧名「处置记录说明」）节内解析脚注「当前最大 X-N」。

    节名锚定可避免正文其他位置出现「当前最大 E-99」之类的文字被误当脚注。
    返回 None 有两种含义：无维护说明节（该仓库无此约定，调用方跳过检查）或
    有节但无脚注标记（该仓库有约定却缺锚点，应报「脚注缺失」）。
    """
    lines = text.splitlines()
    in_section = False
    for line in lines:
        if line.startswith(_MAINTENANCE_SECTIONS[0]) or line.startswith(_MAINTENANCE_SECTIONS[1]):
            in_section = True
            continue
        if in_section:
            m = _FOOTER_PATTERN.search(line)
            if m:
                return int(m.group(1).split("-")[1])
    return None


def _has_maintenance_section(text: str) -> bool:
    return any(s in text for s in _MAINTENANCE_SECTIONS)


def _check_footer_max(texts: list[str], footer_text: str, prefix: str) -> list[str]:
    # 无维护说明/处置记录说明节 = 该仓库没有「当前最大编号」约定 → 跳过 footer 检查
    if not _has_maintenance_section(footer_text):
        return []
    all_nums: list[int] = []
    for t in texts:
        all_nums.extend(_e_numbers(t, prefix))
    max_num = max(all_nums) if all_nums else None
    footer_num = _footer_max_from(footer_text)
    if footer_num is None:
        return ["TECH_DEBT 脚注缺失「当前最大 X-N」标记（应在「维护说明/处置记录说明」节内）"]
    if max_num is None or footer_num != max_num:
        return [
            f"TECH_DEBT 脚注「当前最大 {prefix}-{footer_num}」与全库最大编号 {prefix}-{max_num} 不一致"
        ]
    return []


def check_files(
    tech_debt: Path,
    tickets: Path,
    mode: str | None = None,
    candidate_section: str = _CANDIDATE_SECTION,
) -> list[str]:
    """对两文件执行全部清出规则检查，返回违规列表（空 = 合规）。

    结构自适应：自动探测编号前缀；simplified/legacy 模式默认按「是否存在处置记录台账节」
    自动判定，也可用 mode="simplified" / "legacy" 显式指定（测试/防护场景用显式，
    避免「台账节重现」这类防护项自身翻转模式判定）。candidate_section 覆盖候选区节名
    （conver mobile 用「候选区」）。
    """
    if not tech_debt.is_file():
        return [f"缺少 {tech_debt}"]
    if not tickets.is_file():
        return [f"缺少 {tickets}"]
    td = tech_debt.read_text(encoding="utf-8")
    tk = tickets.read_text(encoding="utf-8")
    prefix = _detect_prefix(td)
    simplified = (mode == "simplified") if mode else _is_simplified(td)
    violations: list[str] = []
    if not td.strip():
        violations.append("TECH_DEBT.md 为空（应含候选区 / 复核关闭 / 维护说明）")
    if not tk.strip():
        violations.append("TO-TICKETS.md 为空（应含活跃工单 / 已完成归档索引）")
    if td.strip() and candidate_section not in td:
        violations.append(f"TECH_DEBT 缺少「{candidate_section}」节")
    if tk.strip() and not any(s in tk for s in _ACTIVE_SECTIONS):
        violations.append("TO-TICKETS 缺少「活跃工单/活跃表」节")
    if tk.strip() and _INDEX_SECTION_PREFIX not in tk:
        violations.append("TO-TICKETS 缺少「已完成归档」节")
    violations += _check_candidate_section(td, candidate_section)
    violations += _check_closed_section(td)
    violations += _check_active_section(tk)
    violations += _check_duplicate_heads(td, "TECH_DEBT")
    violations += _check_duplicate_heads(tk, "TO-TICKETS")
    violations += _check_footer_max([td, tk], td, prefix)
    if simplified:
        violations += _check_disposal_section_absent(td)
        violations += _check_no_full_batch_sections(tk)
        violations += _check_index_row_count(tk)
    return violations


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="清出机制机械检查（pre-commit 挂载，失败 exit 1；检查仓库根 TECH_DEBT.md / TO-TICKETS.md）"
    )
    # --check 为兼容各仓库文档/hook 既有引用而保留：恒执行检查，不改变行为
    ap.add_argument("--check", action="store_true", help="执行检查（默认即执行，兼容显式调用）")
    ap.add_argument(
        "--tickets-file",
        type=str,
        default="TO-TICKETS.md",
        help="任务池文件名（conver system 用 TICKETS.md，默认 TO-TICKETS.md）",
    )
    ap.add_argument(
        "--candidate-section",
        type=str,
        default=None,
        help="候选区节名（conver mobile 用「候选区」，默认「技术债候选区」）",
    )
    args = ap.parse_args(argv)
    root = Path(__file__).resolve().parent.parent
    candidate = args.candidate_section or "## 技术债候选区"
    violations = check_files(
        root / "TECH_DEBT.md", root / args.tickets_file, candidate_section=candidate
    )
    if violations:
        print(f"[pool-cleanup] {len(violations)} 项不通过：")
        for v in violations:
            print(f"  - {v}")
        print("处置指引：候选区只留开放条目；处置详情写 DEV_LOG；归档每批一行入索引（≤60）；")
        print("          表格行列数须与表头一致；脚注最大编号与全库一致；可 git commit --no-verify 临时绕过，但请随后补上。")
        return 1
    print("[pool-cleanup] OK：候选区 / 复核关闭 / 归档索引 / 脚注编号全部合规")
    return 0


if __name__ == "__main__":
    sys.exit(main())