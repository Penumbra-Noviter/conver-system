# Conver System 桌面版一键构建（P6.4-6，spec 构建链契约 D7/D8 + US-11）
#
# 用法（仓库根或任意目录，**cmd / PowerShell**，勿用 Git Bash）：
#     powershell -ExecutionPolicy Bypass -File scripts/build-desktop.ps1
#
# 构建链（spec「构建链」契约）：cargo test → pytest → vitest → tauri build（NSIS 安装器）
#     → 冒烟（可选，默认开启；-SkipSmoke 跳过）
#
# 铁律（spec 环境事实）：
#   - 必须在 cmd/PowerShell 执行——Git Bash 自带的 /usr/bin/link.exe（GNU coreutils）
#     会遮蔽 MSVC 的 link.exe，导致 cargo 链接阶段失败（tauri build 同理）。
#   - tauri build 经 frontend/node_modules/.bin/tauri 调用（CLI 只搜 cwd 及子目录，
#     从仓库根调用即可命中 src-tauri/tauri.conf.json）。
#   - R4：tauri build 首次打包会下载 NSIS/WebView2 bootstrapper（网络依赖），
#     失败自动重试 1 次；仍失败则回退 --no-bundle 验证编译并记录，不阻塞其余交付。
#
# 前置条件：
#   - 仓库根 .venv：backend/requirements.txt 依赖 + pytest（pytest.ini 已就位）
#   - frontend/：npm 依赖（@tauri-apps/cli、vitest）；缺失时本脚本自动 npm install
#   - Rust 工具链（x86_64-pc-windows-msvc，见 docs/tauri-setup.md）
#
# 产物：
#   - 安装器：src-tauri/target/release/bundle/nsis/Conver System_0.1.0_x64-setup.exe
#     （NSIS installMode=currentUser → 安装到 %LOCALAPPDATA%\Programs\，免管理员；
#     卸载不影响 %APPDATA%\ConverSystem 数据，见 docs/tauri-desktop.md）
#   - 壳 exe：src-tauri/target/release/conver-system.exe
#
# 冒烟依赖后端打包产物 dist/conver_backend/conver_backend.exe（build-backend.ps1 产出）；
# 缺失时冒烟脚本会自动调用 build-backend.ps1 补齐（-SkipBackendBuild 可关闭）。

[CmdletBinding()]
param(
    # 跳过全部测试步骤（仅构建 + 冒烟）
    [switch]$SkipTests,
    # 构建完成后不执行冒烟
    [switch]$SkipSmoke,
    # 后端打包产物缺失时不自动调用 build-backend.ps1（冒烟将报错退出）
    [switch]$SkipBackendBuild,
    # 透传给冒烟脚本的额外参数（如 -UseInstaller、-ReadyTimeoutSec）
    [string[]]$SmokeArgs = @()
)

$ErrorActionPreference = "Stop"

# 共享工具函数（ARC9-T05，决策 D2-D1 点源）：后端 exe 补齐 + 端口限定清理
. (Join-Path $PSScriptRoot "lib\desktop-common.ps1")

$Root = Split-Path -Parent $PSScriptRoot
$Py = Join-Path $Root ".venv\Scripts\python.exe"
$TauriCli = Join-Path $Root "frontend\node_modules\.bin\tauri.cmd"
$BackendExe = Join-Path $Root "dist\conver_backend\conver_backend.exe"
$SmokeScript = Join-Path $PSScriptRoot "smoke-desktop.ps1"

function Write-Step {
    param([string]$Title)
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "==> $Title" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
}

function Assert-ExitOk {
    param([string]$Step, [int]$Code)
    if ($Code -ne 0) {
        throw "步骤失败（$Step，退出码 $Code），详见上方输出"
    }
}

# ── 前置检查 ────────────────────────────────────────────────────────────────

Write-Step "前置检查"

if (-not (Test-Path $Py)) {
    throw "未找到 $Py，请先在仓库根创建 .venv 并安装 backend/requirements.txt 依赖与 pytest"
}

if (-not (Test-Path $TauriCli)) {
    Write-Host "未找到 tauri CLI（$TauriCli），执行 npm install 安装前端依赖..."
    Push-Location (Join-Path $Root "frontend")
    try {
        & npm.cmd install
        Assert-ExitOk "npm install" $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

Write-Host "Python : $Py"
Write-Host "Tauri  : $TauriCli"
Write-Host "根目录 : $Root"

# ── 0. 后端打包产物前置（tauri-build 编译期校验 resources 路径）─────────────

# tauri.conf.json 的 bundle.resources 指向 dist/conver_backend（期末审核阻断1 修复）：
# tauri-build 在编译期校验该路径存在性——cargo test 即会失败（干净检出必挂），
# 故后端打包必须早于任何 cargo 编译（复审整改：原步骤 4 前置）。
# -SkipBackendBuild 语义不变（缺失时不自动打包）：原实现警告后继续、由 tauri-build
# 资源校验失败兜底；现统一走 helper 提前明确报错——同一失败结果，信息更清晰。

Assert-Or-Build-BackendExe -Path $BackendExe -SkipBackendBuild:$SkipBackendBuild

# ── 1. cargo test（Seam 1：壳纯逻辑）───────────────────────────────────────

if (-not $SkipTests) {
    Write-Step "1/4 cargo test（src-tauri，Seam 1 壳纯逻辑）"
    Push-Location (Join-Path $Root "src-tauri")
    try {
        & cargo test
        Assert-ExitOk "cargo test" $LASTEXITCODE
    } finally {
        Pop-Location
    }
} else {
    Write-Host "（-SkipTests 跳过 cargo test）" -ForegroundColor Yellow
}

# ── 2. pytest（Seam 3 迁移脚本 + Seam 4 基线）───────────────────────────────

if (-not $SkipTests) {
    Write-Step "2/4 pytest（backend，Seam 3 迁移 + Seam 4 基线）"
    Push-Location $Root
    try {
        & $Py -m pytest -q
        Assert-ExitOk "pytest" $LASTEXITCODE
    } finally {
        Pop-Location
    }
} else {
    Write-Host "（-SkipTests 跳过 pytest）" -ForegroundColor Yellow
}

# ── 3. vitest（Seam 4 前端基线）─────────────────────────────────────────────

if (-not $SkipTests) {
    Write-Step "3/4 vitest（frontend，Seam 4 前端基线）"
    Push-Location (Join-Path $Root "frontend")
    try {
        & npm.cmd test
        Assert-ExitOk "vitest" $LASTEXITCODE
    } finally {
        Pop-Location
    }
} else {
    Write-Host "（-SkipTests 跳过 vitest）" -ForegroundColor Yellow
}

# ── 4. tauri build（NSIS 安装器，R4 超时/重试）──────────────────────────────

Write-Step "4/4 tauri build（NSIS 安装器；首次打包可能下载 NSIS/WebView2，耗时较长）"

# 后端打包产物已在步骤 0 前置补齐（tauri-build resources 校验）；安装器随包分发
# dist/conver_backend（约 24MB，含后端 + 前端运行子集，见 docs/tauri-desktop.md）

Push-Location $Root
try {
    $bundleOk = $false
    foreach ($attempt in 1..2) {
        if ($attempt -gt 1) {
            Write-Host "tauri build 第 $attempt 次尝试（前次失败，通常为 NSIS/WebView2 下载超时）..." -ForegroundColor Yellow
        }
        & $TauriCli build
        if ($LASTEXITCODE -eq 0) {
            $bundleOk = $true
            break
        }
    }
    if (-not $bundleOk) {
        # R4 降级：NSIS 下载失败不阻塞其余交付，回退 --no-bundle 验证编译
        Write-Host "tauri build（含 NSIS 打包）两次尝试失败，回退 --no-bundle 仅验证编译并记录..." -ForegroundColor Yellow
        & $TauriCli build --no-bundle
        Assert-ExitOk "tauri build --no-bundle" $LASTEXITCODE
        Write-Host ""
        Write-Host "警告：NSIS 安装器未产出（网络下载失败）。已生成 src-tauri/target/release/conver-system.exe。" -ForegroundColor Yellow
        Write-Host "修复后重跑本脚本即可补齐安装器；网络代理/镜像说明见 docs/tauri-desktop.md。" -ForegroundColor Yellow
    } else {
        $Installer = Join-Path $Root "src-tauri\target\release\bundle\nsis\Conver System_0.1.0_x64-setup.exe"
        if (Test-Path $Installer) {
            $Size = (Get-Item $Installer).Length / 1MB
            Write-Host ""
            # 注意：-f 必须作用于括号内字符串——裸写 -f 会被解析为 -ForegroundColor 缩写
            Write-Host ("安装器产出：$Installer（{0:N1} MB）" -f $Size) -ForegroundColor Green
        } else {
            Write-Host "警告：tauri build 成功但未找到预期安装器路径：$Installer" -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}

# ── 5. 冒烟（可选）──────────────────────────────────────────────────────────

if ($SkipSmoke) {
    Write-Host "（-SkipSmoke 跳过冒烟）" -ForegroundColor Yellow
} else {
    Write-Step "冒烟：smoke-desktop.ps1（验收 1-7 自动化）"
    & $SmokeScript @SmokeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "冒烟失败（退出码 $LASTEXITCODE），详见上方输出"
    }
}

Write-Host ""
Write-Host "构建完成：一键构建全链通过" -ForegroundColor Green
