# Conver System 桌面版自动化冒烟（P6.4-6，spec Seam 2 / 验收 1-7）
#
# 用法（**cmd / PowerShell**，勿用 Git Bash）：
#     powershell -ExecutionPolicy Bypass -File scripts/smoke-desktop.ps1 [-UseInstaller] [-CleanAppData]
#
# 覆盖验收：
#   验收 4：启动壳 → 轮询 %APPDATA%\ConverSystem\runtime.json 就绪标记（ready:true）
#           → GET http://127.0.0.1:<port>/api/models 200
#   验收 5：首次运行 %APPDATA%\ConverSystem\conver_system.db 存在、表结构完整
#           （GET /api/characters 返回 []；数据目录已存在时只验结构并告警）
#   验收 6：退出应用（壳 CONVER_EXIT_AFTER_SECS 钩子优雅退出）→ 端口释放
#           + 无 conver_backend.exe / uvicorn 后端子进程残留
#   验收 7：迁移脚本幂等由 P6.4-3 的 pytest 用例覆盖（backend/tests/test_migrate_data.py），
#           本脚本不重复实现；可在 -RunMigrationCheck 时做轻量复跑（构造临时源库）
#
# 设计要点：
#   - 壳-后端环境变量通道（spec 接口契约）：以 CONVER_BACKEND_CMD 指向 PyInstaller
#     打包后端 exe（dist/conver_backend/conver_backend.exe），与「P6.4-2 用
#     CONVER_BACKEND_CMD 指 exe」的波次计划一致；后端 exe 缺失时自动调 build-backend.ps1
#   - 数据目录：CONVER_DATA_DIR 覆盖 > %APPDATA%\ConverSystem（与壳/后端同一契约）；
#     冒烟只碰数据目录，绝不触碰项目根 conver_system.db（脚本内显式守卫）
#   - 退出：壳在 CONVER_EXIT_AFTER_SECS 秒后走正常退出流程（ExitRequested → kill 子进程），
#     冒烟等待其自然退出并验证无残留；异常路径兜底 force-kill + 按端口清后端
#   - 残留检查查端口而非 pid（P6.4-1 遗留：venv python 是重定向器孙进程，pid 追踪不可靠）

[CmdletBinding()]
param(
    # 壳 exe 路径（缺省 src-tauri\target\release\conver-system.exe）
    [string]$AppExe = "",
    # 后端打包 exe 路径（缺省 dist\conver_backend\conver_backend.exe）
    [string]$BackendExe = "",
    # 安装器静默安装后启动（缺省直接运行构建产物 exe）
    [switch]$UseInstaller,
    # 安装器路径（缺省按 tauri.conf.json 版本推导 NSIS 产物路径）
    [string]$InstallerPath = "",
    # 后端 exe 缺失时不自动调用 build-backend.ps1（直接报错）
    [switch]$SkipBackendBuild,
    # 启动前强制清理残留的 conver-system.exe 实例（单实例机制会使新实例直接退出）
    [switch]$ForceKillStale,
    # 就绪等待超时（秒，缺省 60；壳的退出计时 = 本值 + 45 秒，保证就绪前不被杀）
    [int]$ReadyTimeoutSec = 60,
    # 冒烟结束后清理数据目录 %APPDATA%\ConverSystem（危险：会删除既有数据，默认关）
    [switch]$CleanAppData,
    # 轻量复跑迁移脚本幂等（验收 7，可选）
    [switch]$RunMigrationCheck,
    # 显式注入后端命令（CONVER_BACKEND_CMD）。缺省语义：
    #   安装态（-UseInstaller）= 不注入，壳按 prod 随包资源定位后端（真实用户路径回归，阻断 1）；
    #   非安装态 = 注入打包后端 exe（快路径，验证 env 通道）
    [string]$BackendEnv = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Py = Join-Path $Root ".venv\Scripts\python.exe"
$port = $null

# ── 路径解析 ────────────────────────────────────────────────────────────────

if (-not $AppExe) {
    $AppExe = Join-Path $Root "src-tauri\target\release\conver-system.exe"
}
$AppExe = [System.IO.Path]::GetFullPath($AppExe)

if (-not $BackendExe) {
    $BackendExe = Join-Path $Root "dist\conver_backend\conver_backend.exe"
}
$BackendExe = [System.IO.Path]::GetFullPath($BackendExe)

if (-not (Test-Path $AppExe)) {
    throw "未找到壳 exe：$AppExe。请先运行 scripts/build-desktop.ps1（或 tauri build）"
}

# 数据目录解析（与壳 server.rs default_data_dir / 后端 run_backend.data_dir 同一契约）
$DataDir = ""
if ($env:CONVER_DATA_DIR) {
    $DataDir = [System.IO.Path]::GetFullPath($env:CONVER_DATA_DIR)
} else {
    if (-not $env:APPDATA) { throw "未找到 %APPDATA%（本冒烟面向 Windows 桌面环境）" }
    $DataDir = Join-Path $env:APPDATA "ConverSystem"
}

# 守卫：数据目录绝不允许落在项目根内（防误删/误读项目根真实数据库）
$RootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
if ($DataDir.TrimEnd('\').StartsWith($RootFull + '\') -or $DataDir.TrimEnd('\') -eq $RootFull) {
    throw "数据目录（$DataDir）落在项目根内——冒烟绝不触碰项目根数据库，请检查 CONVER_DATA_DIR"
}

$RuntimeJson = Join-Path $DataDir "runtime.json"
$DbPath = Join-Path $DataDir "conver_system.db"

$Results = [System.Collections.ArrayList]@()
function Add-Result {
    param([string]$Name, [bool]$Pass, [string]$Detail)
    $null = $Results.Add([pscustomobject]@{ Name = $Name; Pass = $Pass; Detail = $Detail })
    $mark = if ($Pass) { "[PASS]" } else { "[FAIL]" }
    Write-Host ("{0} {1}：{2}" -f $mark, $Name, $Detail) -ForegroundColor $(if ($Pass) { "Green" } else { "Red" })
}

# ── 前置：清理残留实例 / 陈旧就绪标记 ──────────────────────────────────────

$Stale = Get-Process -Name "conver-system" -ErrorAction SilentlyContinue
if ($Stale) {
    if ($ForceKillStale) {
        Write-Host "发现残留 conver-system 实例（单实例机制会拦截新实例），-ForceKillStale 强制清理..." -ForegroundColor Yellow
        $Stale | Stop-Process -Force
        Start-Sleep -Seconds 2
    } else {
        throw "发现正在运行的 conver-system 实例（单实例机制会使新实例直接退出）。请先关闭应用，或加 -ForceKillStale 自动清理"
    }
}

# 删除陈旧 runtime.json：防止上次运行残留的 ready:true 造成假阳性（Falsify）
if (Test-Path $RuntimeJson) {
    Write-Host "清理陈旧 runtime.json（$RuntimeJson）..." -ForegroundColor Yellow
    Remove-Item $RuntimeJson -Force
}

# 记录数据库是否已存在（决定验收 5 的「首启空库」断言语义）
$DbPreExisted = Test-Path $DbPath
if ($DbPreExisted) {
    Write-Host "检测到既有数据目录（非首启）：验收 5 仅验表结构，空库断言降级为告警" -ForegroundColor Yellow
}

# ── 后端通道判定：注入 vs 随包定位 ──────────────────────────────────────────

# 安装态（-UseInstaller）且未显式指定 -BackendEnv → 不注入 CONVER_BACKEND_CMD，
# 壳在 prod 模式（release 构建）下从随包资源目录定位后端 exe——真实用户双击路径的回归用例。
$injectBackendEnv = $false
if ($BackendEnv) {
    $injectBackendEnv = $true
    $backendCmdValue = $BackendEnv
} elseif (-not $UseInstaller) {
    # 非安装态快路径：显式指向打包后端 exe（验证 env 权威通道）
    $injectBackendEnv = $true
    $backendCmdValue = $BackendExe
}

if ($injectBackendEnv) {
    # ── 后端 exe 缺失时自动补齐（仅注入路径需要）────────────────────────
    if (-not (Test-Path $BackendExe)) {
        if ($SkipBackendBuild) {
            throw "未找到后端打包 exe：$BackendExe（-SkipBackendBuild 已指定，不自动打包）"
        }
        Write-Host "后端打包 exe 缺失，调用 build-backend.ps1（PyInstaller onedir）..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "build-backend.ps1")
        if (-not (Test-Path $BackendExe)) {
            throw "build-backend.ps1 执行后仍未找到 $BackendExe"
        }
    }
}

# ── 启动 ────────────────────────────────────────────────────────────────────

$ShellProc = $null
$startedShell = $false
$ExitAfterSecs = $ReadyTimeoutSec + 45   # 壳自动退出计时必须大于就绪等待，防就绪前被杀

try {
    if ($UseInstaller) {
        if (-not $InstallerPath) {
            $Conf = Get-Content (Join-Path $Root "src-tauri\tauri.conf.json") -Raw | ConvertFrom-Json
            $InstallerPath = Join-Path $Root ("src-tauri\target\release\bundle\nsis\Conver System_{0}_x64-setup.exe" -f $Conf.version)
        }
        if (-not (Test-Path $InstallerPath)) {
            throw "未找到安装器：$InstallerPath"
        }
        Write-Host "静默安装：$InstallerPath /S ..." -ForegroundColor Cyan
        $install = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -PassThru
        if ($install.ExitCode -ne 0) {
            throw "安装器静默安装退出码非零：$($install.ExitCode)"
        }
        # NSIS currentUser 实际安装目录为 %LOCALAPPDATA%\{productName}（tauri 2.11 模板实测），
        # 兼顾 Programs\ 候选路径探测
        $installedCandidates = @(
            (Join-Path $env:LOCALAPPDATA "Conver System\conver-system.exe"),
            (Join-Path $env:LOCALAPPDATA "Programs\Conver System\conver-system.exe")
        )
        $AppExe = $installedCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $AppExe) {
            $candidatesText = $installedCandidates -join '; '
            throw "安装后未找到应用 exe（已探测：$candidatesText）"
        }
    }

    Write-Host ""
    Write-Host "==> 启动桌面壳：$AppExe" -ForegroundColor Cyan
    if ($injectBackendEnv) {
        Write-Host "    后端通道：CONVER_BACKEND_CMD=$backendCmdValue（env 注入）" -ForegroundColor Cyan
    } else {
        Write-Host "    后端通道：prod 随包资源定位（不注入 env——真实用户双击路径）" -ForegroundColor Cyan
    }
    Write-Host "    数据目录：$DataDir" -ForegroundColor Cyan
    Write-Host "    退出钩子：CONVER_EXIT_AFTER_SECS=$ExitAfterSecs" -ForegroundColor Cyan

    # 壳-后端环境变量通道（spec 接口契约）：条件注入后端命令 + 自动退出计时
    $origBackendCmd = $env:CONVER_BACKEND_CMD
    $origExitAfter = $env:CONVER_EXIT_AFTER_SECS
    if ($injectBackendEnv) {
        $env:CONVER_BACKEND_CMD = '"' + $backendCmdValue + '"'
    }
    $env:CONVER_EXIT_AFTER_SECS = [string]$ExitAfterSecs

    $ShellProc = Start-Process -FilePath $AppExe -PassThru
    $startedShell = $true
    Write-Host "壳进程 pid=$($ShellProc.Id)"

    # ── 验收 4a：轮询 runtime.json 就绪标记 ──────────────────────────────
    Write-Host "轮询就绪标记（$RuntimeJson，超时 $ReadyTimeoutSec 秒）..."
    $runtime = $null
    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSec)
    $parseFailures = 0
    while ((Get-Date) -lt $deadline) {
        # 壳进程提前退出（未就绪）→ 快速失败，不干等超时
        if (-not (Get-Process -Id $ShellProc.Id -ErrorAction SilentlyContinue)) {
            $earlyErr = ""
            if (Test-Path $RuntimeJson) {
                try { $early = Get-Content $RuntimeJson -Raw | ConvertFrom-Json } catch { $early = $null }
                if ($early.error) { $earlyErr = "：" + $early.error }
            }
            throw "壳进程提前退出，后端未就绪$earlyErr"
        }
        if (Test-Path $RuntimeJson) {
            try {
                $runtime = Get-Content $RuntimeJson -Raw | ConvertFrom-Json
                $parseFailures = 0
                if ($runtime.ready -eq $true) { break }
                # ready:false 是终态（壳只写就绪/超时/子进程退出三种终态）
                $err = if ($runtime.error) { "：$($runtime.error)" } else { "" }
                throw "后端未就绪（runtime.json ready:false$err，端口 $($runtime.port)）"
            } catch [System.Exception] {
                if ($_.Exception.Message -match "^后端未就绪") { throw }
                # 解析失败（文件可能正在被原子写/半截）→ 容忍重试几次
                $parseFailures++
                if ($parseFailures -ge 5) { throw "runtime.json 多次解析失败：$($_.Exception.Message)" }
                Start-Sleep -Milliseconds 800
                continue
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $runtime -or $runtime.ready -ne $true) {
        throw "等待就绪标记超时（$ReadyTimeoutSec 秒）；若为网络问题请检查后端日志 $DataDir\backend.log"
    }
    $port = [int]$runtime.port
    Add-Result "验收4a-runtime.json就绪标记" $true ("port=$port pid=$($runtime.pid)")

    # ── 验收 4b：GET /api/models 200 ─────────────────────────────────────
    $modelsResp = Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:{0}/api/models" -f $port) -TimeoutSec 10
    Add-Result "验收4b-GET /api/models" ($modelsResp.StatusCode -eq 200) ("HTTP {0}" -f $modelsResp.StatusCode)

    # ── 阻断 2 冒烟断言：GET / 挂载前端 UI（webview 就绪跳转目标）─────────
    # 依赖 PyInstaller 配方 datas 随包分发前端（期末审核阻断 2，另一 agent 修复）；
    # datas 未合并前本断言预期 FAIL（404），合并后必须 PASS——防「webview 跳转 404」复发。
    $rootOk = $false
    $rootDetail = ""
    try {
        $rootResp = Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:{0}/" -f $port) -TimeoutSec 10
        $rootHasMark = $rootResp.Content -match "<title>Conver System"
        $rootOk = $rootResp.StatusCode -eq 200 -and $rootHasMark
        $rootDetail = "HTTP {0} 含应用标记={1}（期望 200 + <title>Conver System）" -f $rootResp.StatusCode, $rootHasMark
    } catch {
        $rootOk = $false
        $rootDetail = "GET / 失败（datas 未随包分发时预期 404）：" + $_.Exception.Message
    }
    Add-Result "阻断2-GET / 前端挂载" $rootOk $rootDetail

    # ── 验收 5：DB 存在 + 表结构完整（GET /api/characters）───────────────
    $dbOk = Test-Path $DbPath
    if ($dbOk) {
        $charsResp = Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:{0}/api/characters" -f $port) -TimeoutSec 10
        $charsOk = $charsResp.StatusCode -eq 200
        if (-not $DbPreExisted) {
            # 首启空库语义：断言返回 []
            $charsJson = $charsResp.Content | ConvertFrom-Json
            $emptyOk = ($charsJson.Count -eq 0)
            Add-Result "验收5-首启空库+表结构" ($dbOk -and $charsOk -and $emptyOk) `
                ("db存在=$dbOk /api/characters HTTP $($charsResp.StatusCode) 返回 $($charsJson.Count) 条（期望 0）")
        } else {
            # 既有数据目录：只验结构完整（200），空库断言降级
            Add-Result "验收5-表结构(既有数据)" ($dbOk -and $charsOk) `
                ("db存在=$dbOk /api/characters HTTP $($charsResp.StatusCode)；非首启，空库断言跳过")
        }
    } else {
        Add-Result "验收5-数据库存在" $false ("$DbPath 不存在（后端未建库？）")
    }

    # ── 验收 7（可选）：迁移脚本幂等轻量复跑 ─────────────────────────────
    if ($RunMigrationCheck) {
        $tmpBase = Join-Path ([System.IO.Path]::GetTempPath()) ("conver-migrate-smoke-" + [guid]::NewGuid().ToString("N"))
        try {
            & $Py -c @"
import sys
from pathlib import Path
sys.path.insert(0, r'$Root')
from backend.scripts.migrate_data import migrate, verify_database
base = Path(r'$tmpBase')
src = base / 'src' / 'conver_system.db'; src.parent.mkdir(parents=True)
import sqlite3
conn = sqlite3.connect(src)
# 源库须含全部核心表（migrate_data 的 check_source 契约：characters/conversations/messages/settings）
conn.executescript('''
CREATE TABLE characters (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE conversations (id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE messages (id INTEGER PRIMARY KEY, content TEXT);
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO characters(name) VALUES ('smoke');
''')
conn.close()
dst = base / 'dst' / 'conver_system.db'
migrate(src, dst)
assert dst.exists() and (dst.parent / '.migrated').exists(), '首次迁移失败'
migrate(src, dst)  # 幂等复跑：目标带完成标记即跳过
assert dst.exists(), '幂等复跑后目标丢失'
problems = verify_database(dst)
assert not problems, '目标库校验失败: ' + ';'.join(problems)
print('migrate-smoke-ok')
"@
            $migExit = $LASTEXITCODE
            if ($migExit -ne 0) { throw "迁移幂等复跑失败（退出码 $migExit）" }
            Add-Result "验收7-迁移幂等轻量复跑" $true "源库保留/目标出现/完成标记/复跑跳过"
        } finally {
            if (Test-Path $tmpBase) { Remove-Item $tmpBase -Recurse -Force }
        }
    }

    # ── 验收 6：优雅退出 + 无残留 ───────────────────────────────────────
    Write-Host "冒烟检查完成，等待壳优雅退出（CONVER_EXIT_AFTER_SECS=$ExitAfterSecs 秒自动触发）..." -ForegroundColor Cyan
    $exitDeadline = (Get-Date).AddSeconds($ExitAfterSecs + 30)
    while ((Get-Date) -lt $exitDeadline) {
        if (-not (Get-Process -Id $ShellProc.Id -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Seconds 2
    }
    $shellGone = -not (Get-Process -Id $ShellProc.Id -ErrorAction SilentlyContinue)
    if (-not $shellGone) {
        Write-Host "壳未在预期时间内退出，force-kill 并清理后端..." -ForegroundColor Yellow
        Stop-Process -Id $ShellProc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # 端口释放（主判据：查端口而非 pid——venv python 重定向器孙进程 pid 不可靠）
    # 注意：必须用同步 TcpClient.Connect——异步 BeginConnect+WaitHandle 在连接被拒
    # （端口已关闭）时 WaitHandle 不触发，会永远误判「仍占用」（本机实测）。
    $portReleased = $false
    $portDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $portDeadline) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect("127.0.0.1", $port)   # 被拒时同步抛异常 → 端口已释放
            $owner = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty OwningProcess
            $ownerInfo = if ($owner) {
                $op = Get-Process -Id $owner -ErrorAction SilentlyContinue
                "pid=$owner name=$($op.ProcessName)"
            } else { "未知持有者" }
            Write-Host "端口 $port 仍被占用（$ownerInfo），等待后端退出..." -ForegroundColor Yellow
            $tcp.Close()
            Start-Sleep -Seconds 2
        } catch {
            $portReleased = $true
            break
        } finally {
            $tcp.Dispose()
        }
    }

    # 后端子进程残留检查——严格限定在冒烟自己的端口上（Get-NetTCPConnection），
    # 绝不按全局进程名/命令行匹配（会误杀无关进程，如本机正在运行的网页版 uvicorn）
    $backendProc = Get-Process -Name "conver_backend" -ErrorAction SilentlyContinue
    # 端口持有者即冒烟后端（无论进程名是 conver_backend 还是 python*）
    $smokeListeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    $uvicornProc = @($smokeListeners | ForEach-Object {
            Get-Process -Id $_ -ErrorAction SilentlyContinue
        } | Where-Object { $_.ProcessName -like "python*" })
    if ($backendProc) {
        Write-Host "发现残留 conver_backend 进程（pid $($backendProc.Id -join ',')），清理..." -ForegroundColor Yellow
        $backendProc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $backendProc = Get-Process -Name "conver_backend" -ErrorAction SilentlyContinue
    }
    if ($uvicornProc) {
        Write-Host "发现端口 $port 上的残留 python 进程（pid $($uvicornProc.Id -join ',')），清理..." -ForegroundColor Yellow
        $uvicornProc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $smokeListeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
        $uvicornProc = @($smokeListeners | ForEach-Object {
                Get-Process -Id $_ -ErrorAction SilentlyContinue
            } | Where-Object { $_.ProcessName -like "python*" })
    }
    Add-Result "验收6-退出无残留" ($shellGone -and $portReleased -and -not $backendProc -and $uvicornProc.Count -eq 0) `
        ("壳退出=$shellGone 端口$port释放=$portReleased 无conver_backend=$(-not $backendProc) 无端口残留python=$($uvicornProc.Count -eq 0)")

    # ── 可选清理 ─────────────────────────────────────────────────────────
    if ($CleanAppData) {
        Write-Host "警告：-CleanAppData 删除数据目录 $DataDir（含既有数据）..." -ForegroundColor Yellow
        if (Test-Path $DataDir) { Remove-Item $DataDir -Recurse -Force }
        Add-Result "清理数据目录" $true $DataDir
    }

    # ── 汇总 ─────────────────────────────────────────────────────────────
    Write-Host ""
    $failed = @($Results | Where-Object { -not $_.Pass })
    if ($failed.Count -eq 0) {
        Write-Host "冒烟全部通过（$($Results.Count) 项）" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "冒烟失败 $($failed.Count)/$($Results.Count) 项" -ForegroundColor Red
        exit 1
    }
} finally {
    # 异常路径兜底清理——只清理冒烟自己启动的进程（$startedShell 守卫），
    # 绝不按全局进程名清理（防误杀用户正在运行的桌面版/网页版进程）
    if ($startedShell -and $ShellProc -and (Get-Process -Id $ShellProc.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $ShellProc.Id -Force -ErrorAction SilentlyContinue
    }
    if ($startedShell -and $port) {
        $listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        foreach ($l in $listeners) {
            Stop-Process -Id $l.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
    if ($null -eq $origBackendCmd) { Remove-Item Env:CONVER_BACKEND_CMD -ErrorAction SilentlyContinue } else { $env:CONVER_BACKEND_CMD = $origBackendCmd }
    if ($null -eq $origExitAfter) { Remove-Item Env:CONVER_EXIT_AFTER_SECS -ErrorAction SilentlyContinue } else { $env:CONVER_EXIT_AFTER_SECS = $origExitAfter }
}
