#!/bin/sh
# pre-commit 钩子：①清出机制机械检查（TECH_DEBT/TO-TICKETS） ②拦截 CODE_WIKI 机械标记漂移。
# 由 scripts/install-hooks.bat 复制到 .git/hooks/pre-commit（.git/hooks 不入库）。
# 未安装 Python 时跳过（不阻塞提交）；安装了则强校验。
# 手动测试：sh .git/hooks/pre-commit

cd "$(git rev-parse --show-toplevel)" 2>/dev/null || exit 1

if ! command -v python >/dev/null 2>&1; then
    echo "pre-commit: 未找到 python，跳过清出/doc_sync 校验" >&2
    exit 0
fi

# ① 清出机制机械检查（任务池本库名为 TO-TICKETS.md；失败拒绝提交）
if ! python scripts/pool_cleanup_check.py --check --tickets-file TO-TICKETS.md; then
    echo ""
    echo "pre-commit 拦截：清出机制检查未通过（候选区/复核关闭/活跃工单/脚注编号/表格列数）。" >&2
    echo "处置指引见 TECH_DEBT.md「清出机制」第 5 条；可 --no-verify 临时绕过，但请随后补上。" >&2
    exit 1
fi

# ② doc_sync 机械标记（未装 pytest 时跳过，不阻塞提交）
if ! python -c "import pytest" >/dev/null 2>&1; then
    echo "pre-commit: 未安装 pytest，跳过 doc_sync 校验" >&2
    exit 0
fi

if python scripts/doc_sync.py --check; then
    exit 0
fi

echo ""
echo "F-01 pre-commit 拦截：CODE_WIKI.md 机械标记已漂移（测试数/模块行数/方法签名与代码不同步）。" >&2
echo "请先运行：python scripts/doc_sync.py  刷新标记后再提交。" >&2
exit 1
