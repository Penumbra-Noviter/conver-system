#!/bin/sh
# F-01 pre-commit 钩子：拦截 CODE_WIKI 机械标记漂移的提交。
# 由 scripts/install-hooks.bat 复制到 .git/hooks/pre-commit（.git/hooks 不入库）。
# 未安装 Python/pytest 时跳过（不阻塞提交）；安装了则强校验。
# vitest/cargo 渠道在 doc_sync 内部自动降级（缺失/失败时不校验，不阻塞）。
# 手动测试：sh .git/hooks/pre-commit

cd "$(git rev-parse --show-toplevel)" 2>/dev/null || exit 1

if ! command -v python >/dev/null 2>&1; then
    echo "pre-commit: 未找到 python，跳过 doc_sync 校验" >&2
    exit 0
fi

# 未装 pytest（--check 内部依赖 pytest --collect-only）时跳过，不阻塞提交
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
