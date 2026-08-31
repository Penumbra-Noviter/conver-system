#!/bin/sh
# conver system mobile pre-commit 钩子安装：清出机制机械检查（每个新 clone 执行一次）
# 本库为变体结构：任务池 TICKETS.md、候选区节名「候选区」——钩子固定带对应参数。
# 用法：sh scripts/install-pre-commit.sh
set -e
ROOT="$(git rev-parse --show-toplevel)"
HOOKS="$(git rev-parse --git-path hooks)"

cat > "$HOOKS/pre-commit" <<'EOF'
#!/bin/sh
# conver mobile 清出机制机械检查：失败即拒绝提交（处置指引见 TECH_DEBT.md「清出机制」第 5 条）
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then
    echo "pre-commit: 非 git 仓库，跳过清出检查" >&2
    exit 0
fi
if ! command -v python >/dev/null 2>&1; then
    echo "pre-commit: 找不到 python —— 清出检查无法执行，请激活 venv 后重试" >&2
    echo "          （或 git commit --no-verify 临时绕过，但请随后补上）" >&2
    exit 1
fi
if ! python "$ROOT/scripts/pool_cleanup_check.py" --check --tickets-file TICKETS.md --candidate-section "## 候选区" 2>&1; then
    echo "pre-commit: 清出检查未通过 —— 先折叠/清理再提交（可 --no-verify 临时绕过，但请随后补上）" >&2
    exit 1
fi
EOF

chmod +x "$HOOKS/pre-commit"
echo "installed: $HOOKS/pre-commit (TICKETS.md + 候选区节名)"