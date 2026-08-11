# Conver System 后端 PyInstaller onedir 一键打包（P6.4-2）
#
# 用法（仓库根或任意目录，PowerShell）：
#     powershell -ExecutionPolicy Bypass -File scripts/build-backend.ps1
#
# 前置条件：
#   - 仓库根 .venv 已安装 backend/requirements.txt 依赖 + pyinstaller
#     （SPK-R1 已验证：pyinstaller 6.22.0 + pyinstaller-hooks-contrib 2026.6）
#   - 必须在 cmd/PowerShell 执行——Git Bash 的 link.exe 会遮蔽 MSVC linker
#     （spec 构建链契约；PyInstaller 虽是 Python 工具，统一走本脚本防坑）
#
# 产物：dist/conver_backend/conver_backend.exe（onedir，含 _internal/，约 25M）
# 配方：backend/conver_backend.spec（SPK-R1 spike 验证成品，勿随意改参数）
#
# 运行验证（打包后，Windows 绝对路径 DATABASE_URL，勿用 POSIX 路径）：
#     $env:DATABASE_URL = "sqlite+aiosqlite:///C:/Users/<user>/AppData/Roaming/ConverSystem/conver_system.db"
#     dist/conver_backend/conver_backend.exe --host 127.0.0.1 --port 18081 --log-level warning

$ErrorActionPreference = "Stop"

# 仓库根 = 本脚本所在目录的上一级（scripts/build-backend.ps1 → 仓库根）
$Root = Split-Path -Parent $PSScriptRoot

$Py = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
    throw "未找到 $Py，请先在仓库根创建虚拟环境并安装依赖与 pyinstaller"
}

Push-Location $Root
try {
    Write-Host "==> PyInstaller 打包（配方：backend/conver_backend.spec）"
    & $Py -m PyInstaller backend/conver_backend.spec --distpath dist --workpath build --noconfirm
    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller 打包失败（退出码 $LASTEXITCODE），详见上方输出与 build/ 下 warn-*.txt"
    }
    Write-Host "==> 打包完成：dist/conver_backend/conver_backend.exe（onedir，含 _internal/）"
} finally {
    Pop-Location
}
