//! 壳纯逻辑（Seam 1，可测面）：端口探测、命令行解析、子进程启停、就绪判定、runtime.json 读写。
//!
//! 本模块不依赖 Tauri 运行时，全部逻辑可在 cargo test 中以注入 seam 验证：
//! 后端进程命令（`BackendConfig`）、HTTP 探测（`wait_until_ready` 闭包）、数据目录（参数注入）。

use std::io::{self, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

/// 开发态默认后端启动命令（uvicorn 源码模式；可用 `CONVER_BACKEND_CMD` 覆盖）。
pub const DEFAULT_DEV_BACKEND_CMD: &str = "python -m uvicorn backend.app.main:app";

/// 就绪等待默认超时（秒级环境变量 `CONVER_READY_TIMEOUT_SECS` 可覆盖）。
pub const DEFAULT_READY_TIMEOUT: Duration = Duration::from_secs(60);

/// 就绪轮询间隔。
pub const READY_POLL_INTERVAL: Duration = Duration::from_millis(500);

/// 单次 HTTP 探测超时。
pub const HTTP_PROBE_TIMEOUT: Duration = Duration::from_secs(2);

/// 就绪标记文件名（数据目录下）。
pub const RUNTIME_JSON: &str = "runtime.json";

/// 数据目录名（%APPDATA% 下）。
pub const DATA_DIR_NAME: &str = "ConverSystem";

/// 数据库文件名。
pub const DB_FILE: &str = "conver_system.db";

/// Windows CREATE_NO_WINDOW 标志（0x08000000）：防止后端进程弹出控制台窗口。
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

// ── 端口探测 ────────────────────────────────────────────────────────────────

/// 通过 `TcpListener::bind(("127.0.0.1", 0))` 探测一个空闲端口并立即释放。
///
/// 返回的端口在探测与后端子进程绑定之间理论上存在被占用的竞态窗口，
/// 由后端子进程绑定失败 + 就绪超时报错兜底（见 `ReadyOutcome::TimedOut` / `ChildExited`）。
pub fn probe_free_port() -> io::Result<u16> {
    let listener = TcpListener::bind(("127.0.0.1", 0))?;
    Ok(listener.local_addr()?.port())
}

// ── 命令行解析（CONVER_BACKEND_CMD seam）────────────────────────────────────

/// 将命令行字符串拆分为 token（支持双引号包裹的空格路径），供 `BackendConfig` 使用。
///
/// - 双引号内的空白保留（如 `"C:/Program Files/app.exe"`）；
/// - 未闭合引号 / 空命令返回 `Err`。
pub fn parse_command_line(line: &str) -> Result<Vec<String>, String> {
    let mut tokens: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut token_started = false;
    for c in line.chars() {
        match c {
            '"' => {
                in_quotes = !in_quotes;
                token_started = true;
            }
            ' ' | '\t' if !in_quotes => {
                if token_started {
                    tokens.push(std::mem::take(&mut current));
                    token_started = false;
                }
            }
            _ => {
                current.push(c);
                token_started = true;
            }
        }
    }
    if in_quotes {
        return Err("命令行含未闭合的引号".into());
    }
    if token_started {
        tokens.push(current);
    }
    if tokens.is_empty() {
        return Err("命令行不能为空".into());
    }
    Ok(tokens)
}

/// 后端进程配置：程序 + 参数 + 工作目录 + 额外环境变量。
#[derive(Debug, Clone)]
pub struct BackendConfig {
    /// 可执行程序路径或命令名。
    pub program: String,
    /// 程序参数（壳会追加 `--host 127.0.0.1 --port <port> --log-level warning`）。
    pub args: Vec<String>,
    /// 工作目录（None = 继承壳进程）。
    pub cwd: Option<PathBuf>,
    /// 额外环境变量（`DATABASE_URL` 由壳自动注入，无需在此声明）。
    pub extra_env: Vec<(String, String)>,
}

/// 从环境变量与运行模式解析后端配置：
///
/// 优先级（P6.4-6 期末审核阻断 1 修复——安装态双击直启必须可用，US-1）：
/// 1. `CONVER_BACKEND_CMD` 显式覆盖（权威通道，行为不变）；
/// 2. 生产态（`dev_mode=false`，即 release 构建）且资源目录可用 → **随包后端 exe**
///    （`resource_dir/conver_backend/conver_backend.exe`，安装器经 bundle.resources 分发，
///    干净用户机无 python 也可双击即用）；
/// 3. 其余（开发态 / 生产态但无资源目录如 --no-bundle 直接跑）→ 开发态 uvicorn 命令。
///
/// `dev_mode` 由调用方注入（lib.rs：`cfg!(debug_assertions)`），保证两个分支均可单测。
pub fn backend_config_from_env(
    dev_mode: bool,
    resource_dir: Option<&Path>,
) -> Result<BackendConfig, String> {
    let cwd = std::env::var("CONVER_BACKEND_CWD").ok().map(PathBuf::from);
    if let Ok(cmd) = std::env::var("CONVER_BACKEND_CMD") {
        let mut parts = parse_command_line(&cmd)?;
        let program = parts.remove(0);
        return Ok(BackendConfig {
            program,
            args: parts,
            cwd,
            extra_env: Vec::new(),
        });
    }
    if !dev_mode {
        if let Some(dir) = resource_dir {
            if let Some(exe) = find_prod_backend_exe(dir) {
                return Ok(BackendConfig {
                    program: exe.to_string_lossy().into_owned(),
                    args: Vec::new(),
                    cwd,
                    extra_env: Vec::new(),
                });
            }
        }
    }
    let mut parts = parse_command_line(DEFAULT_DEV_BACKEND_CMD)?;
    let program = parts.remove(0);
    Ok(BackendConfig {
        program,
        args: parts,
        cwd,
        extra_env: Vec::new(),
    })
}

/// 生产态后端可执行文件候选（按 Tauri Windows 打包布局探测，优先返回存在的）：
///
/// 1. `resource_dir/_up_/dist/conver_backend/conver_backend.exe`——NSIS 安装态实测布局：
///    `bundle.resources` 保留相对 src-tauri 的路径结构（`../dist/conver_backend`），
///    整体置于安装目录的 `_up_` 子目录下；
/// 2. `resource_dir/conver_backend/conver_backend.exe`——手工分发 / 未来布局兜底。
///
/// 路径含空格可直接作为 `Command::new` 程序名，无需引号；
/// 安装态 `resource_dir` = 安装目录（NSIS currentUser → `%LOCALAPPDATA%\<productName>\`）。
pub fn prod_backend_exe_candidates(resource_dir: &Path) -> Vec<PathBuf> {
    vec![
        resource_dir
            .join("_up_")
            .join("dist")
            .join("conver_backend")
            .join("conver_backend.exe"),
        resource_dir
            .join("conver_backend")
            .join("conver_backend.exe"),
    ]
}

/// 返回第一个实际存在的随包后端 exe（无则 None——调用方回退开发态命令）。
pub fn find_prod_backend_exe(resource_dir: &Path) -> Option<PathBuf> {
    prod_backend_exe_candidates(resource_dir)
        .into_iter()
        .find(|p| p.is_file())
}

// ── 子进程启停 ──────────────────────────────────────────────────────────────

/// 生成指向数据目录数据库的 DATABASE_URL（`sqlite+aiosqlite:///` + 正斜杠绝对路径）。
///
/// 契约（spec 接口契约）：pydantic-settings 环境变量优先于默认值；
/// 后端 `config.py` 默认 `sqlite+aiosqlite:///./conver_system.db`（相对 CWD），
/// 桌面版必须以环境变量改写为 %APPDATA% 绝对路径，保证与网页版数据相互独立。
/// 反斜杠转正斜杠：SQLAlchemy 对 Windows 绝对路径统一按正斜杠解析；
/// 随后做最小编百分号编码（契约表 v1，`encode_url_path`）——数据目录含
/// `#`/`?`/空格/中文时保证 URL 不被截断，与迁移脚本 URI 语义一致（决策 D1-D3）。
pub fn database_url(data_dir: &Path) -> String {
    let db_path_buf = data_dir.join(DB_FILE);
    let db_path = db_path_buf.to_string_lossy();
    let normalized = db_path.replace('\\', "/");
    format!("sqlite+aiosqlite:///{}", encode_url_path(&normalized))
}

/// 以 CREATE_NO_WINDOW 方式启动后端子进程并注入环境变量。
///
/// 追加参数：`--host 127.0.0.1 --port <port> --log-level warning`；
/// 注入环境：`DATABASE_URL`（指向数据目录）+ `extra_env`。
pub fn spawn_backend(
    config: &BackendConfig,
    port: u16,
    data_dir: &Path,
) -> io::Result<ManagedChild> {
    let mut cmd = Command::new(&config.program);
    cmd.args(&config.args);
    cmd.arg("--host").arg("127.0.0.1");
    cmd.arg("--port").arg(port.to_string());
    cmd.arg("--log-level").arg("warning");
    cmd.env("DATABASE_URL", database_url(data_dir));
    for (key, value) in &config.extra_env {
        cmd.env(key, value);
    }
    if let Some(cwd) = &config.cwd {
        cmd.current_dir(cwd);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    let child = cmd.spawn()?;
    Ok(ManagedChild { child: Some(child) })
}

/// 受管子进程：显式 `kill` + Drop 兜底，保证任何退出路径（含 panic）都不残留后端进程。
pub struct ManagedChild {
    child: Option<Child>,
}

impl ManagedChild {
    /// 子进程 pid（已退出/未启动时为 None）。
    pub fn pid(&self) -> Option<u32> {
        self.child.as_ref().map(Child::id)
    }

    /// 子进程退出码（仍在运行返回 None）。
    pub fn try_exit_code(&mut self) -> Option<i32> {
        self.child
            .as_mut()
            .and_then(|c| c.try_wait().ok().flatten())
            .map(|status| status.code().unwrap_or(-1))
    }

    /// 终止并回收子进程（幂等；已退出时无副作用）。
    pub fn kill(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for ManagedChild {
    fn drop(&mut self) {
        self.kill();
    }
}

// ── 就绪判定 ────────────────────────────────────────────────────────────────

/// 就绪轮询终态。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReadyOutcome {
    /// HTTP 探测成功。
    Ready,
    /// 超时未就绪。
    TimedOut,
    /// 子进程提前退出（携带退出码）。
    ChildExited(i32),
}

/// 以固定间隔轮询探测函数直到就绪 / 超时 / 子进程退出。
///
/// - `probe`：单次就绪探测（如 `http_probe`），返回 true 表示就绪；
/// - `child_status`：子进程退出码（运行中返回 None）；
/// - 每轮先查子进程退出（快速失败），再查就绪，最后判定超时。
pub fn wait_until_ready(
    mut probe: impl FnMut() -> bool,
    mut child_status: impl FnMut() -> Option<i32>,
    timeout: Duration,
    interval: Duration,
) -> ReadyOutcome {
    let start = Instant::now();
    loop {
        if let Some(code) = child_status() {
            return ReadyOutcome::ChildExited(code);
        }
        if probe() {
            return ReadyOutcome::Ready;
        }
        if start.elapsed() >= timeout {
            return ReadyOutcome::TimedOut;
        }
        std::thread::sleep(interval);
    }
}

/// 单次 HTTP 就绪探测：`GET /api/models`，响应状态行以 `HTTP/1.x 200` 开头即就绪。
///
/// 连接失败 / 非 200 / 读写超时均返回 false（探测本身不抛错）。
pub fn http_probe(port: u16, timeout: Duration) -> bool {
    let Ok(addr) = format!("127.0.0.1:{port}").parse::<SocketAddr>() else {
        return false;
    };
    let Ok(mut stream) = TcpStream::connect_timeout(&addr, timeout) else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let request = format!(
        "GET /api/models HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n"
    );
    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }
    let mut buf = [0u8; 1024];
    let mut total = 0usize;
    loop {
        match stream.read(&mut buf[total..]) {
            Ok(0) => break,
            Ok(n) => {
                total += n;
                if total >= buf.len() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    let head = String::from_utf8_lossy(&buf[..total]);
    let status_line = head.lines().next().unwrap_or("");
    status_line.starts_with("HTTP/1.1 200") || status_line.starts_with("HTTP/1.0 200")
}

// ── runtime.json 读写（就绪契约）────────────────────────────────────────────

/// 后端状态（boot.html 轮询契约）：就绪标记 + 后端地址 + 端口 + 错误。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackendStatus {
    /// 后端是否就绪。
    pub ready: bool,
    /// 后端地址（`http://127.0.0.1:<port>`；端口未知为 None）。
    pub url: Option<String>,
    /// 动态端口（未探测为 0）。
    pub port: u16,
    /// 最近错误（无错误为 None）。
    pub error: Option<String>,
}

/// 就绪标记内容：端口 + 就绪标记 + 后端 pid + 错误信息（可选）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeInfo {
    /// 后端监听端口。
    pub port: u16,
    /// 就绪标记。
    pub ready: bool,
    /// 后端进程 pid。
    pub pid: Option<u32>,
    /// 未就绪原因（就绪时为 None）。
    pub error: Option<String>,
}

/// 写入 runtime.json（人类可读 JSON 文本；父目录必须已存在，由调用方保证）。
///
/// 原子写（F2，与迁移脚本 `_write_marker` 同款）：先写同目录临时文件再 rename 替换，
/// 保证轮询方（就绪页 / 冒烟脚本）读到的始终是完整 JSON，不会出现半截文件。
pub fn write_runtime_json(path: &Path, info: &RuntimeInfo) -> io::Result<()> {
    let json = serde_json::to_string_pretty(info).map_err(|e| {
        io::Error::new(io::ErrorKind::InvalidData, format!("序列化 runtime.json 失败: {e}"))
    })?;
    let file_name = path.file_name().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "runtime.json 路径缺少文件名")
    })?;
    let tmp_path = path.with_file_name(format!("{}.tmp", file_name.to_string_lossy()));
    std::fs::write(&tmp_path, format!("{json}\n"))?;
    std::fs::rename(&tmp_path, path)?;
    Ok(())
}

/// 读取 runtime.json（文件缺失 / JSON 损坏返回 Err）。
pub fn read_runtime_json(path: &Path) -> io::Result<RuntimeInfo> {
    let data = std::fs::read(path)?;
    serde_json::from_slice(&data)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("解析 runtime.json 失败: {e}")))
}

// ── 数据目录 ────────────────────────────────────────────────────────────────

/// 数据目录 = base/ConverSystem（base 通常为 %APPDATA%）。
pub fn data_dir_path(base: &Path) -> PathBuf {
    base.join(DATA_DIR_NAME)
}

/// 默认数据目录（契约表 v1，与后端 `run_backend.data_dir` / 迁移脚本
/// `default_target_path` 同一契约；契约表全文见 backend/tests/test_data_dir.py）：
/// `CONVER_DATA_DIR`（环境变量覆盖，值即数据目录；空串视为未设置）→
/// `%APPDATA%\ConverSystem` → `%USERPROFILE%\AppData\Roaming\ConverSystem`
/// （对齐 Python 侧 `home\AppData\Roaming` 兜底，决策 D1-D2）。
/// USERPROFILE 也缺失的不可达场景保留 CWD 末位兜底（正常 Windows 环境必有 USERPROFILE）。
pub fn default_data_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("CONVER_DATA_DIR") {
        if !dir.is_empty() {
            return PathBuf::from(dir);
        }
    }
    if let Some(base) = std::env::var_os("APPDATA") {
        return data_dir_path(Path::new(&base));
    }
    if let Some(profile) = std::env::var_os("USERPROFILE") {
        let roaming = Path::new(&profile).join("AppData").join("Roaming");
        return data_dir_path(&roaming);
    }
    data_dir_path(&std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
}

/// 最小编百分号编码（契约表 v1，镜像 Python `urllib.parse.quote(s, safe="/:")`）：
///
/// 保留不编码：`A-Z a-z 0-9 _ - . ~ / :`（RFC3986 unreserved + `~` + `/` + `:`）；
/// 其余一律按 UTF-8 逐字节编码为 `%XX`（大写十六进制）——`#`/`?`/`%`/空格/中文等
/// 全部编码，保证注入的 DATABASE_URL 与迁移脚本 `_open_readonly` 的 URI 语义一致
/// （SQLAlchemy URI 解析器会把未编码的 `#`/`?` 当分隔符，导致连接串被截断）。
///
/// 契约表 v1 逐字符用例见 src-tauri/tests/server_test.rs（与 Python 侧测试文件互引版本号）。
pub fn encode_url_path(path: &str) -> String {
    let mut out = String::with_capacity(path.len());
    for c in path.chars() {
        if c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '~' | '/' | ':') {
            out.push(c);
        } else {
            let mut buf = [0u8; 4];
            for byte in c.encode_utf8(&mut buf).as_bytes() {
                out.push_str(&format!("%{byte:02X}"));
            }
        }
    }
    out
}
