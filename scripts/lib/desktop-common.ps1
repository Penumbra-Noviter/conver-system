# Conver System 桌面工具链共享函数（ARC9-T05 · 决策 D2-D1 点源共享）
#
# 用法：调用方脚本点源导入（本文件不自动执行任何逻辑）：
#     . (Join-Path $PSScriptRoot "lib\desktop-common.ps1")
#
# 铁律（决策 D2-D1 / spec G5 冒烟纪律）：
#   - 安装器路径**唯一推导来源** = tauri.conf.json 的 productName/version
#     （Get-ConverInstallerPath）——build-desktop.ps1 与 smoke-desktop.ps1 共用，
#     禁止任何脚本硬编码安装器文件名（R4a 收口）。
#   - 后端进程清理**唯一手段** = 按「端口监听者」定位（Stop-ConverPortListeners），
#     绝不按全局进程名（Get-Process -Name）清理——会误杀用户另开的同名后端实例。
#   - 壳实例预清（conver-system）是显式例外：须 -ForceKillStale 显式授权（见
#     smoke-desktop.ps1 102-111 段），不在本文件清理面内。
#   - helper 只做单点职责：不触碰调用方 $ErrorActionPreference（全部经
#     逐命令 -ErrorAction 控制与显式参数），不改调用方位置/环境变量状态。

function Stop-ConverPortListeners {
    <#
    .SYNOPSIS
        终止监听指定本地端口的所有进程（端口限定，绝不按进程名）。
    .DESCRIPTION
        以 Get-NetTCPConnection -LocalPort $Port -State Listen 定位持有者 pid 并
        Stop-Process -Force。端口无监听者时静默返回（幂等，可安全重复调用）。
        这是后端进程清理的唯一手段——端口持有者即目标（无论进程名是 conver_backend
        还是 python* 等），绝不按全局进程名匹配。
    .PARAMETER Port
        要清理的本地端口号。
    .OUTPUTS
        返回被清理的 pid 数组（未清理任何进程时为空数组）。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )
    $killed = @()
    $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($l in $listeners) {
        Stop-Process -Id $l.OwningProcess -Force -ErrorAction SilentlyContinue
        $killed += $l.OwningProcess
    }
    return ,$killed
}

function Assert-Or-Build-BackendExe {
    <#
    .SYNOPSIS
        断言后端打包 exe 存在；缺失时自动调 build-backend.ps1 补齐，复查仍缺失则 throw。
    .DESCRIPTION
        合并 build-desktop.ps1 与 smoke-desktop.ps1 两处重复实现（ARC9-T05）：
        -SkipBackendBuild 指定时缺失直接 throw（不自动打包）；
        未指定时调 scripts/build-backend.ps1（PyInstaller onedir），执行后复查，
        仍缺失即 throw——绝不静默继续。
    .PARAMETER Path
        后端 exe 完整路径（dist\conver_backend\conver_backend.exe）。
    .PARAMETER SkipBackendBuild
        缺失时不自动调 build-backend.ps1（直接报错）。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$SkipBackendBuild
    )
    if (Test-Path $Path) { return }
    if ($SkipBackendBuild) {
        throw "未找到后端打包 exe：$Path（-SkipBackendBuild 已指定，不自动打包）"
    }
    $buildScript = Join-Path $PSScriptRoot "..\build-backend.ps1"
    Write-Host "后端打包 exe 缺失，调用 build-backend.ps1（PyInstaller onedir）..." -ForegroundColor Yellow
    & $buildScript
    if (-not (Test-Path $Path)) {
        throw "build-backend.ps1 执行后仍未找到 $Path"
    }
}

function Get-ConverInstallerPath {
    <#
    .SYNOPSIS
        推导 NSIS 安装器产物完整路径（单一来源 = tauri.conf.json 的 productName/version）。
    .DESCRIPTION
        产物命名契约：src-tauri\target\release\bundle\nsis\{productName}_{version}_x64-setup.exe
        （NSIS installMode=currentUser，见 tauri.conf.json bundle.windows.nsis）。
        版本升级只需改 tauri.conf.json——build-desktop.ps1 与 smoke-desktop.ps1 共用本
        helper（R4a 收口），禁止任何脚本硬编码安装器文件名（会随版本升级漂移）。
        本 helper 只推导路径，不校验文件存在性（调用方按需 Test-Path）。
    .PARAMETER Root
        仓库根目录（内含 src-tauri\tauri.conf.json）。
    .OUTPUTS
        返回安装器完整路径字符串；tauri.conf.json 缺失/解析失败/缺字段时 throw。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )
    $TauriConfPath = Join-Path $Root "src-tauri\tauri.conf.json"
    if (-not (Test-Path $TauriConfPath)) {
        throw "未找到 tauri.conf.json：$TauriConfPath（安装器路径推导需要 productName/version）"
    }
    try {
        $Conf = Get-Content $TauriConfPath -Raw | ConvertFrom-Json
    } catch {
        throw "tauri.conf.json 解析失败：$TauriConfPath（$($_.Exception.Message)）"
    }
    if (-not $Conf.productName -or -not $Conf.version) {
        throw "tauri.conf.json 缺少 productName 或 version 字段，无法推导安装器路径：$TauriConfPath"
    }
    return Join-Path $Root ("src-tauri\target\release\bundle\nsis\{0}_{1}_x64-setup.exe" -f $Conf.productName, $Conf.version)
}
