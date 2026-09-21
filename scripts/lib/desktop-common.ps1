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

function Get-ConverRepoRoot {
    <#
    .SYNOPSIS
        推导仓库根目录（本文件 scripts/lib/desktop-common.ps1 两级上溯）。
    .OUTPUTS
        返回归一化（Resolve-Path）后的仓库根绝对路径字符串。
    #>
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-ConverBackendRebuildInputs {
    <#
    .SYNOPSIS
        后端打包 exe 的全部重建输入路径（即 PyInstaller spec 打包面）。
    .DESCRIPTION
        输入 = backend 源（app/scripts/run_backend/spec/requirements）+ 前端运行子集
        （conver_backend.spec 的 _FRONTEND_RUNTIME datas：index.html/css/js/simulators）。
        前端子集漏列会让「前端改动不进后端包」被误判为新鲜；node_modules 不在打包面，不列。
    .PARAMETER Root
        仓库根（见 Get-ConverRepoRoot）。
    .OUTPUTS
        输入路径字符串数组（不存在路径由调用方静默容错）。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )
    return @(
        (Join-Path $Root "backend\app"),
        (Join-Path $Root "backend\scripts"),
        (Join-Path $Root "backend\run_backend.py"),
        (Join-Path $Root "backend\conver_backend.spec"),
        (Join-Path $Root "backend\requirements.txt"),
        (Join-Path $Root "frontend\index.html"),
        (Join-Path $Root "frontend\css"),
        (Join-Path $Root "frontend\js"),
        (Join-Path $Root "frontend\simulators")
    )
}

function Test-ConverBackendExeIsCurrent {
    <#
    .SYNOPSIS
        判断后端打包 exe 是否为最新（F-156：只认缺失不认过期的旧缺口）。
    .DESCRIPTION
        exe 存在且 LastWriteTime 不早于全部重建输入的最新 mtime → $true（新鲜）；
        exe 缺失或任输入更新 → $false（过期）。mtime 口径对 git 检出场景宽松（同批检出
        时间接近），仅源码改动后明显拉开。输入集为空的异常场景返回 $true（不阻塞调用方）。
    .PARAMETER ExePath
        后端 exe 完整路径（dist\conver_backend\conver_backend.exe）。
    .PARAMETER Root
        仓库根；缺省按 Get-ConverRepoRoot 推导（测试可注入临时根）。
    .OUTPUTS
        布尔：exe 是否新鲜。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExePath,
        [string]$Root
    )
    if (-not (Test-Path $ExePath)) { return $false }
    if (-not $Root) { $Root = Get-ConverRepoRoot }
    $exeTime = (Get-Item $ExePath).LastWriteTime
    $newest = Get-ChildItem -Path (Get-ConverBackendRebuildInputs -Root $Root) -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property LastWriteTime -Maximum
    if ($null -eq $newest.Maximum) { return $true }
    return ($exeTime -ge $newest.Maximum)
}

function Assert-Or-Build-BackendExe {
    <#
    .SYNOPSIS
        断言后端打包 exe 存在且不过期；缺失/过期时自动调 build-backend.ps1 补齐，复查仍不对则 throw。
    .DESCRIPTION
        合并 build-desktop.ps1 与 smoke-desktop.ps1 两处重复实现（ARC9-T05）：
        - 缺失（F-156 前即有的行为）：-SkipBackendBuild 指定时直接 throw；未指定时调
          scripts/build-backend.ps1（PyInstaller onedir），执行后复查，仍缺失即 throw——绝不静默继续。
        - 过期（F-156 补齐，2026-09-21）：exe 早于 backend/前端运行子集源码时自动重建，
          防「旧后端包被静默复用」（实测 8-28 后端进 9-14 包）；-SkipBackendBuild 指定时
          降级为警告放行（exe 已存在，用户显式选择不构建，交由调用方判断）。
    .PARAMETER Path
        后端 exe 完整路径（dist\conver_backend\conver_backend.exe）。
    .PARAMETER SkipBackendBuild
        缺失/过期时不自动调 build-backend.ps1（缺失直接报错，过期告警放行）。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$SkipBackendBuild
    )
    $buildScript = Join-Path $PSScriptRoot "..\build-backend.ps1"
    # F-156 四象限统一入口：缺失→补、过期→重建、-SkipBackendBuild 时缺失报错/过期告警放行
    if ((Test-Path $Path) -and (Test-ConverBackendExeIsCurrent -ExePath $Path)) { return }
    $stale = Test-Path $Path  # 仍存在 = 过期而非缺失
    if ($SkipBackendBuild) {
        if (-not $stale) {
            throw "未找到后端打包 exe：$Path（-SkipBackendBuild 已指定，不自动打包）"
        }
        Write-Host "警告：后端打包 exe 已过期（backend/前端源码更新），-SkipBackendBuild 已指定不重建：$Path" -ForegroundColor Yellow
        return
    }
    $reason = if ($stale) { "过期（backend/前端源码更新）" } else { "缺失" }
    Write-Host "后端打包 exe $reason，调用 build-backend.ps1（PyInstaller onedir）..." -ForegroundColor Yellow
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
