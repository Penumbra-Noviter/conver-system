# Conver System 桌面版（Tauri）— 构建 / 冒烟 / 数据目录

> Conver System 桌面版 = Tauri v2 壳（Rust）+ PyInstaller 打包后端 + 原生前端（零改动）。
> 工具链安装见 [tauri-setup.md](tauri-setup.md)（本文档不重复）。
> 规格与决策见 `.scratch/p64-tauri/spec.md`（P6.4 工单波次）。

---

## 1. 一键构建（scripts/build-desktop.ps1）

```powershell
# cmd 或 PowerShell（Git Bash 会遮蔽 MSVC link.exe，构建必须避开 Git Bash）
powershell -ExecutionPolicy Bypass -File scripts/build-desktop.ps1
```

构建链（spec 构建链契约）：**cargo test → pytest → vitest → tauri build（NSIS）→ 冒烟**。

| 步骤 | 内容 | 产物/判据 |
|------|------|-----------|
| 1 | `cargo test`（src-tauri） | 壳纯逻辑 43 用例 |
| 2 | `pytest`（backend，仓库根 .venv） | 261 用例 + 1 skip |
| 3 | `vitest run`（frontend） | 186 用例 |
| 4 | `tauri build`（默认 NSIS；`-SkipInstaller` 时 `--no-bundle` 仅编译壳） | 安装器 + 壳 exe（SkipInstaller 时仅壳） |
| 5 | `smoke-desktop.ps1` | 验收 1-7 自动化 |

产物：

- 安装器（仅未加 `-SkipInstaller` 时产出）：`src-tauri/target/release/bundle/nsis/Conver System_0.1.0_x64-setup.exe`（**内含后端随包资源** `dist/conver_backend`，经 `bundle.resources` 分发——安装后即可双击直启，无需 python）
- 壳 exe：`src-tauri/target/release/conver-system.exe`
- 后端打包 exe：`dist/conver_backend/conver_backend.exe`（build-backend.ps1 产出；构建时缺失自动补齐——tauri build 的 resources 依赖它）

常用参数：

| 参数 | 作用 |
|------|------|
| `-SkipTests` | 跳过全部测试步骤 |
| `-SkipSmoke` | 构建后不执行冒烟 |
| `-SkipBackendBuild` | 后端 exe 缺失时不自动打包 |
| `-SmokeArgs @('-UseInstaller')` | 透传给冒烟脚本 |

注意事项：

- **R4（网络依赖）**：tauri build 首次打包会下载 NSIS / WebView2 bootstrapper。失败自动重试 1 次；仍失败则回退 `--no-bundle` 仅验证编译并记录——此时无安装器，但 `conver-system.exe` 已产出，修复网络后重跑本脚本即可补齐。
- 首次 release 编译约 400+ crate，耗时较长属正常。

## 2. 自动化冒烟（scripts/smoke-desktop.ps1）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/smoke-desktop.ps1            # 直接跑构建产物
powershell -ExecutionPolicy Bypass -File scripts/smoke-desktop.ps1 -UseInstaller   # 安装器静默安装后启动
```

覆盖验收（spec Seam 2）：

| 验收 | 断言 |
|------|------|
| 4 | 启动壳 → 轮询 `%APPDATA%\ConverSystem\runtime.json` 就绪标记（ready:true，容忍解析失败重试）→ `GET http://127.0.0.1:\<port\>/api/models` 200 |
| 5 | 首次运行 `%APPDATA%\ConverSystem\conver_system.db` 存在、表结构完整（`GET /api/characters` 返回 `[]`）；数据目录已存在时只验结构并告警 |
| 6 | 壳经 `CONVER_EXIT_AFTER_SECS` 钩子优雅退出 → 端口释放 + 无 `conver_backend.exe` / uvicorn 残留（查端口而非 pid，P6.4-1 遗留） |
| 7 | 迁移脚本幂等由 P6.4-3 pytest 用例覆盖；`-RunMigrationCheck` 可轻量复跑 |
| 阻断 1 回归 | **干净环境用例**：`-UseInstaller` 且不注入 `CONVER_BACKEND_CMD` 启动已安装应用 → 壳按 prod 随包资源定位后端（`resource_dir/conver_backend/conver_backend.exe`）→ runtime.json ready + `/api/models` 200——真实用户双击路径纳入自动化闭环 |
| 阻断 2 回归 | `GET /` 200 且含 `<title>Conver System` 应用标记（webview 就绪跳转目标；依赖 PyInstaller datas 随包前端，未合并前预期 FAIL） |

后端通道语义（期末审核阻断 1 修复后）：

| 场景 | CONVER_BACKEND_CMD | 壳定位 |
|------|--------------------|--------|
| 开发态（cargo run / debug 构建） | 未注入 | 缺省 `python -m uvicorn backend.app.main:app` |
| 安装态（release 构建 + 安装器，**真实用户**） | 未注入 | **随包资源**：`%LOCALAPPDATA%\Conver System\_up_\dist\conver_backend\conver_backend.exe`（Tauri Windows 把 resources 置于安装目录 `_up_` 子目录并保留相对路径结构；壳按候选探测，平铺布局兜底） |
| 任意态显式注入 | 注入（`-BackendEnv` 或构建脚本） | env 权威通道优先 |

关键参数：

| 参数 | 作用 |
|------|------|
| `-UseInstaller` | 安装器静默安装（`/S`）后启动已安装应用（缺省直接运行构建产物 exe） |
| `-AppExe <路径>` / `-BackendExe <路径>` | 覆盖壳 exe / 后端打包 exe 路径 |
| `-InstallerPath <路径>` | 覆盖安装器路径（缺省按 tauri.conf.json 版本推导） |
| `-ReadyTimeoutSec <秒>` | 就绪等待超时（默认 60；壳自动退出计时 = 本值 + 45） |
| `-RunMigrationCheck` | 轻量复跑迁移脚本幂等（验收 7） |
| `-ForceKillStale` | 强制清理残留壳实例（单实例机制会拦截新实例；默认遇到即报错） |
| `-CleanAppData` | 冒烟后删除数据目录（**危险**，会删除既有数据，默认关） |
| `-SkipBackendBuild` | 后端 exe 缺失时不自动打包（直接报错） |
| `-SkipInstaller` | tauri build 改 `--no-bundle` 仅编译壳，不产 NSIS 安装器（常规打包默认加——用户惯例：安装包仅在明确提需求时打包） |

安全边界（脚本内显式守卫）：

- 冒烟**只碰数据目录**（`CONVER_DATA_DIR` 覆盖 > `%APPDATA%\ConverSystem`），数据目录落在项目根内会直接拒绝执行——绝不触碰项目根 `conver_system.db`；
- 启动前删除陈旧 `runtime.json`，防上次残留的 ready:true 假阳性；
- 既有数据目录不会因冒烟被删除（`-CleanAppData` 需显式指定）。

## 3. 数据目录与迁移

### 3.1 目录布局（默认 `%APPDATA%\ConverSystem\`）

| 文件 | 用途 |
|------|------|
| `conver_system.db` | 桌面版数据库（与网页版根数据库完全独立，互不干扰，D3/数据分离铁律） |
| `runtime.json` | 就绪契约：port + ready 标记 + pid（壳原子写，就绪页与冒烟轮询） |
| `settings.json` | 壳级用户设置：关闭行为偏好 `close_action`（tray/quit，D11；缺失/损坏回退默认 tray） |
| `backend.log` | 后端子进程日志（uvicorn 落盘契约，CREATE_NO_WINDOW 下 stdout 无处可去） |
| `.migrated` | 迁移完成标记（migrate_data.py 写入） |

### 3.2 数据目录覆盖（CONVER_DATA_DIR）

壳（`src-tauri/src/server.rs::default_data_dir`）、后端（`backend/run_backend.py::data_dir` → 委托 `backend/app/services/data_dir.py`）、迁移脚本（`backend/scripts/migrate_data.py` → 委托同模块）同一契约（**契约表 v2，2026-08-12**）：`CONVER_DATA_DIR`（环境变量，值即数据目录，空串视为未设置）→ `%APPDATA%\ConverSystem` → `home\AppData\Roaming\ConverSystem` 兜底统一（Rust 侧 `USERPROFILE\AppData\Roaming`，USERPROFILE 也缺失时 CWD 末位兜底）。双端镜像契约测试：`backend/tests/test_data_dir.py` + `test_data_dir_connection.py` ↔ `src-tauri/tests/server_test.rs`。

**URL 编码（v2）**：壳注入 `DATABASE_URL` 仅对 `?` 编码为 `%3F`——SQLAlchemy sqlite 方言对 `%XX` **零解码**（v1 全量编码曾致含空格/中文路径 `unable to open database file`，2026-08-12 期末审核阻断修复）；空格/中文/`#`/`%` 一律原样。`migrate_data::_open_readonly` 走 `sqlite3.connect(uri=True)`（SQLite URI 规则**会**解码 `%XX`），其编码语义独立保留——两路径消费者解码语义不同，勿再对齐。

```powershell
$env:CONVER_DATA_DIR = "D:\conver-data"   # 覆盖后桌面版全部数据落此处
```

**POSIX 路径警告**：`CONVER_DATA_DIR` 传 Git Bash 形态的 POSIX 路径（如 `/c/Users/<name>/conver-data`）时**不做归一化**——**路径形态**限定（TD-18）：代码**不改写路径整体**（不绝对化、不折叠分段），仅 Path 构造固有的分隔符规范化（按逐字符契约；契约表 v2，见上）直接落位，数据将落在字面路径 `<当前盘根>\c\Users\<name>\conver-data`（进程当前盘符为 C: 时即 `C:\c\Users\<name>\conver-data`；而非 `C:\Users\<name>\conver-data`）。若 Git Bash/MSYS2 的路径转换在参数传递边界生效（`CONVER_DATA_DIR` 未被排除时），实际落位可能随之转换；未转换时按字面拼接。Git Bash 环境部署请改用 Windows 风格路径（如 `C:\conver-data`）；代码在**路径形态**上不做归一化是契约行为，非缺陷。

### 3.3 网页版 → 桌面版数据迁移（migrate_data.py）

迁移脚本独立命令行工具（P6.4-3，不进产品 UI）：

```powershell
# 仓库根，默认：网页版根 DB → %APPDATA%\ConverSystem\conver_system.db
.venv\Scripts\python.exe -m backend.scripts.migrate_data
# 指定源/目标 + 覆盖不一致目标（默认不一致时拒绝覆盖）
.venv\Scripts\python.exe -m backend.scripts.migrate_data --source <根db> --target <目标db> --force
```

铁律（复制非移动 + 完成标记 + 幂等 + 防覆盖）：源数据库**原样保留**（迁移后仍可回退网页版）；目标带 `.migrated` 完成标记则跳过；目标已存在同健康数据时跳过，不一致须 `--force`。可重复运行。

## 4. 环境注意

- **Git Bash link.exe 遮蔽**：Git Bash 自带 `/usr/bin/link.exe`（GNU coreutils）会遮蔽 MSVC linker——cargo / tauri build / PyInstaller 一律在 **cmd 或 PowerShell** 中执行。
- **SmartScreen（R5）**：安装器未代码签名，首次运行可能弹 SmartScreen「未知发布者」提示——点「更多信息 → 仍要运行」即可（已知可接受项）。
- **NSIS 安装位置**：`installMode: currentUser`（tauri.conf.json `bundle.windows.nsis`）→ 免管理员安装到 **`%LOCALAPPDATA%\Conver System\`**（tauri 2.11 NSIS 模板实测路径；旧文档所称 `Programs\` 子目录为 Electron 惯例，Tauri 直接落 `%LOCALAPPDATA%\{productName}`）。
- **卸载不影响数据**：数据在 `%APPDATA%\ConverSystem\`（安装目录之外），卸载安装器**不会删除**数据；如需彻底清理数据请手动删除该目录。
- **WebView2**：打包内嵌 bootstrapper，目标机缺 WebView2 时安装器会引导下载（R4 网络依赖；多数 Windows 10/11 已自带）。
- **CLI 调用位置**：tauri CLI 只搜 cwd 及子目录——从仓库根调用 `frontend\node_modules\.bin\tauri`。

## 5. 已知限制（P6.4-6 交接记录）

1. ~~壳的生产模式后端定位依赖环境变量通道~~ —— **已修复**（2026-08-11 期末审核阻断 1）：`bundle.resources` 随包分发后端，壳 release 构建按候选探测定位随包 exe（`server.rs::prod_backend_exe_candidates`：`_up_/dist/conver_backend/` 实测布局 + 平铺兜底），`CONVER_BACKEND_CMD` 覆盖保留；冒烟 `-UseInstaller` 干净环境用例（不注入 env）纳入自动化闭环。
2. ~~打包后端不随包挂载前端 UI~~ —— **已修复**（2026-08-11 期末审核阻断 2）：`backend/conver_backend.spec` 的 `datas` 已挂载 `frontend` 运行子集（index.html/css/js，排除 node_modules/tests，`_FRONTEND_RUNTIME` 接线，+364K），打包态下 webview 就绪后跳转 `http://127.0.0.1:\<port\>/` 返回 200 且含应用标记；冒烟 `GET /` 标记断言（阻断 2 回归）已 PASS。API 不受影响。
3. **验收 8/9 人工项**：托盘/自启/导出下载由人工清单记录（见下节），自动化冒烟不覆盖 GUI 行为（R6）。

## 6. 人工验收清单（验收 8 / 9，R6）

| 验收 | 检查项 | 结果 | 日期 | 备注 |
|------|--------|------|------|------|
| 8 | 托盘图标显示，关闭窗口 = 最小化到托盘 | ☐ | | |
| 8 | 托盘菜单：显示/隐藏窗口、开机自启勾选（默认关） | ☐ | | |
| 8 | 勾选自启后注册表 `HKCU\...\Run` 出现条目；取消后消失 | ☐ | | |
| 8 | 二次启动（应用已运行）聚焦已有窗口，不重复拉起后端 | ☐ | | |
| 8 | 关闭行为偏好（D11）：首次运行弹窗选择；设置页「关闭窗口」分组可改；选「直接退出」后关窗即退（无残留） | ☐ | | |
| 9 | 对话导出 JSON/Markdown 下载到 Downloads（WebView2 不拦截，SPK-R2 结论） | ☐ | | |
| 9 | 角色卡导出下载正常 | ☐ | | |

> 验收 9 依据：spike#02 实测 WebView2 不拦截 blob:URL + a.click() 下载（三种机制全放行），无需导出回退分支；spike 曾登记一个无法复现的瞬态 permission-request-dialog，人工点一次导出即可闭合。
