//! Conver System — Tauri 桌面壳。
//!
//! 职责（spec D1 / 工单 03-P6.4-1 + 06-P6.4-4）：
//! 1. 探测动态端口 → 以 CREATE_NO_WINDOW 启动后端子进程（dev = uvicorn 源码 / prod = 打包 exe）；
//! 2. 注入 `DATABASE_URL` 指向 %APPDATA%\ConverSystem\conver_system.db（与网页版数据独立）；
//! 3. 后台线程轮询 HTTP 就绪（GET /api/models 200），就绪后写 %APPDATA%\ConverSystem\runtime.json；
//! 4. webview 加载 boot.html（Tauri 资产页）→ 经 `backend_status` 命令轮询 → `location.replace` 跳转；
//! 5. 单实例（tauri-plugin-single-instance）：二次启动在插件 setup 中同步退出，不重复 spawn 后端；
//! 6. 系统托盘（D5/D6）：关闭窗口 = 最小化到托盘；菜单 [显示/隐藏窗口、开机自启勾选、退出]；
//! 7. 应用退出（含异常路径）kill 后端子进程，保证无残留。

pub mod commands;
pub mod server;
pub mod tray;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use server::{BackendConfig, BackendStatus, ManagedChild, ReadyOutcome, RuntimeInfo};
use tauri::Manager;

/// 桌面壳运行状态：动态端口、数据目录、子进程、就绪标记与最近错误。
///
/// 字段全部并发安全；子进程生命周期（含 Drop 兜底）由 `ManagedChild` 保证，
/// 即壳进程任何退出路径都不会残留后端进程。
pub struct ShellState {
    inner: Arc<ShellStateInner>,
}

struct ShellStateInner {
    port: AtomicU16,
    data_dir: PathBuf,
    child: Mutex<Option<ManagedChild>>,
    ready: AtomicBool,
    error: Mutex<Option<String>>,
}

impl ShellState {
    /// 创建壳状态（port 为 0 表示尚未探测动态端口）。
    pub fn new(port: u16, data_dir: PathBuf) -> ShellState {
        ShellState {
            inner: Arc::new(ShellStateInner {
                port: AtomicU16::new(port),
                data_dir,
                child: Mutex::new(None),
                ready: AtomicBool::new(false),
                error: Mutex::new(None),
            }),
        }
    }

    /// 应用入口：按环境配置启动后端并返回壳状态（失败原因记录到状态，不 panic）。
    ///
    /// `resource_dir`：打包态资源目录（随包后端 exe 定位依据，见 `server::backend_config_from_env`）；
    /// 开发态传 None。setup 中经 `app.path().resource_dir()` 获取。
    pub fn launch(resource_dir: Option<PathBuf>) -> ShellState {
        let state = ShellState::new(0, server::default_data_dir());
        let _ = state.try_start(resource_dir);
        state
    }

    /// 从运行模式（debug=开发态 / release=生产态）与资源目录解析配置并启动后端。
    ///
    /// 生产态（release 构建）默认定位随包后端 exe（安装器 bundle.resources 分发，US-1 双击直启）；
    /// `CONVER_BACKEND_CMD` 环境变量覆盖保留。任何失败路径都会把原因记录到状态
    /// （`status().error`），供就绪页展示。
    pub fn try_start(&self, resource_dir: Option<PathBuf>) -> Result<(), String> {
        match server::backend_config_from_env(cfg!(debug_assertions), resource_dir.as_deref()) {
            Ok(config) => self.try_start_with(config),
            Err(e) => {
                self.set_error(e.clone());
                Err(e)
            }
        }
    }

    /// 使用给定配置启动后端（就绪超时取环境变量，缺省 60s）。
    pub fn try_start_with(&self, config: BackendConfig) -> Result<(), String> {
        self.try_start_with_timeout(config, ready_timeout_from_env())
    }

    /// 使用给定配置与就绪超时启动后端：建数据目录 → 探测端口 → spawn 子进程 → 后台就绪线程。
    ///
    /// 任何失败路径都会把原因记录到状态（`status().error`），供就绪页展示。
    pub fn try_start_with_timeout(
        &self,
        config: BackendConfig,
        timeout: Duration,
    ) -> Result<(), String> {
        let result = self.try_start_inner(config, timeout);
        if let Err(ref e) = result {
            self.set_error(e.clone());
        }
        result
    }

    fn try_start_inner(&self, config: BackendConfig, timeout: Duration) -> Result<(), String> {
        let inner = &self.inner;
        std::fs::create_dir_all(&inner.data_dir)
            .map_err(|e| format!("创建数据目录失败: {e}"))?;
        let port = server::probe_free_port().map_err(|e| format!("端口探测失败: {e}"))?;
        inner.port.store(port, Ordering::SeqCst);
        let child = server::spawn_backend(&config, port, &inner.data_dir)
            .map_err(|e| format!("启动后端进程失败: {e}"))?;
        inner.child.lock().unwrap().replace(child);
        let thread_inner = Arc::clone(inner);
        std::thread::spawn(move || readiness_loop(thread_inner, timeout));
        Ok(())
    }

    /// 当前后端状态（boot.html 就绪页轮询的契约来源）。
    pub fn status(&self) -> BackendStatus {
        let inner = &self.inner;
        let port = inner.port.load(Ordering::SeqCst);
        BackendStatus {
            ready: inner.ready.load(Ordering::SeqCst),
            url: (port != 0).then(|| format!("http://127.0.0.1:{port}")),
            port,
            error: inner.error.lock().unwrap().clone(),
        }
    }

    /// 当前后端子进程 pid（无子进程时为 None）。
    pub fn child_pid(&self) -> Option<u32> {
        self.inner
            .child
            .lock()
            .unwrap()
            .as_ref()
            .and_then(|c| c.pid())
    }

    /// 终止后端子进程（幂等；应用退出与测试收尾调用，重复调用无副作用）。
    pub fn kill_child(&self) {
        if let Some(mut child) = self.inner.child.lock().unwrap().take() {
            child.kill();
        }
    }

    fn set_error(&self, message: String) {
        *self.inner.error.lock().unwrap() = Some(message);
    }
}

/// 后台就绪线程：轮询 HTTP 就绪 → 写 runtime.json（就绪 / 超时 / 提前退出三种终态）。
fn readiness_loop(inner: Arc<ShellStateInner>, timeout: Duration) {
    let port = inner.port.load(Ordering::SeqCst);
    let pid = inner.child.lock().unwrap().as_ref().and_then(|c| c.pid());
    let outcome = server::wait_until_ready(
        || server::http_probe(port, server::HTTP_PROBE_TIMEOUT),
        || {
            inner
                .child
                .lock()
                .unwrap()
                .as_mut()
                .and_then(|c| c.try_exit_code())
        },
        timeout,
        server::READY_POLL_INTERVAL,
    );
    let info = match outcome {
        ReadyOutcome::Ready => {
            inner.ready.store(true, Ordering::SeqCst);
            RuntimeInfo {
                port,
                ready: true,
                pid,
                error: None,
            }
        }
        ReadyOutcome::TimedOut => {
            let e = format!("等待后端就绪超时（{timeout:?}）");
            *inner.error.lock().unwrap() = Some(e.clone());
            RuntimeInfo {
                port,
                ready: false,
                pid,
                error: Some(e),
            }
        }
        ReadyOutcome::ChildExited(code) => {
            let e = format!("后端进程提前退出（退出码 {code}）");
            *inner.error.lock().unwrap() = Some(e.clone());
            RuntimeInfo {
                port,
                ready: false,
                pid,
                error: Some(e),
            }
        }
    };
    let path = inner.data_dir.join(server::RUNTIME_JSON);
    if let Err(e) = server::write_runtime_json(&path, &info) {
        eprintln!("[conver-shell] 写入 runtime.json 失败: {e}");
    }
}

/// 就绪超时：`CONVER_READY_TIMEOUT_SECS` 环境变量（秒），非法 / 缺失回退默认值。
fn ready_timeout_from_env() -> Duration {
    std::env::var("CONVER_READY_TIMEOUT_SECS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .map(Duration::from_secs)
        .unwrap_or(server::DEFAULT_READY_TIMEOUT)
}

/// 应用入口：挂载插件 → setup 启动壳与托盘 → 运行事件循环（关闭=托盘 / 退出清理子进程）。
///
/// 生命周期（D5）：窗口关闭 → CloseRequested 被拦截 → 隐藏窗口驻留托盘（不退出）；
/// 托盘「退出」→ ExitRequested → Exit → kill 后端子进程（无残留）。
///
/// 单实例（D5）：tauri-plugin-single-instance 在插件 setup 中**同步**检查互斥量，
/// 二次实例在应用 setup 执行前即退出 → 壳（后端 spawn）在应用 setup 中启动，
/// 保证二次启动绝不重复拉起后端（防双 uvicorn 与 SQLite 并发写）。
///
/// 自动化 seam：设置环境变量 `CONVER_EXIT_AFTER_SECS=<秒>` 时，应用在指定秒数后
/// 走正常退出流程（ExitRequested → Exit → kill 子进程），供冒烟脚本自动化收尾。
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            // 二次实例回调（只会在首个实例上触发）：聚焦已有实例主窗口
            if let Some(window) = app.get_webview_window(tray::MAIN_WINDOW_LABEL) {
                let _ = window.unminimize();
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .app_name("Conver System")
                .build(),
        )
        .invoke_handler(tauri::generate_handler![commands::backend_status])
        .setup(|app| {
            // 壳在 setup 中启动：single-instance 插件已同步完成二次实例检查；
            // 打包态资源目录用于定位随包后端 exe（US-1 双击直启，阻断 1 修复）
            let shell = ShellState::launch(app.path().resource_dir().ok());
            app.manage(shell);
            tray::setup_tray(app.handle())?;
            if let Some(secs) = std::env::var("CONVER_EXIT_AFTER_SECS")
                .ok()
                .and_then(|v| v.parse::<u64>().ok())
            {
                let handle = app.handle().clone();
                std::thread::spawn(move || {
                    std::thread::sleep(Duration::from_secs(secs));
                    handle.exit(0);
                });
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Conver System Tauri 应用构建失败")
        .run(|app, event| match event {
            // 关闭窗口 = 最小化到托盘（D5）；托盘「退出」走 ExitRequested → Exit
            tauri::RunEvent::WindowEvent {
                event: tauri::WindowEvent::CloseRequested { api, .. },
                ..
            } => {
                api.prevent_close();
                if let Some(window) = app.get_webview_window(tray::MAIN_WINDOW_LABEL) {
                    let _ = window.hide();
                }
                if let Some(state) = app.try_state::<tray::TrayState>() {
                    state
                        .status
                        .lock()
                        .unwrap()
                        .apply_window_intent(tray::WindowIntent::Hide);
                }
            }
            tauri::RunEvent::Exit => {
                if let Some(shell) = app.try_state::<ShellState>() {
                    shell.kill_child();
                }
            }
            _ => {}
        });
}
