//! Tauri 命令层（就绪页 boot.html 经 `window.__TAURI_INTERNALS__.invoke` 调用）。

use tauri::State;

use crate::server::BackendStatus;
use crate::ShellState;

/// 查询后端启动状态 `{ ready, url, port, error }`。
///
/// boot.html 轮询本命令：`ready == true` 后 `location.replace(url)` 跳转到
/// `http://127.0.0.1:<port>`；超时 / 子进程提前退出时 `error` 携带原因供页面展示。
#[tauri::command]
pub fn backend_status(state: State<'_, ShellState>) -> BackendStatus {
    state.status()
}
