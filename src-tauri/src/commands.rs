//! Tauri 命令层（boot.html 就绪页 + 前端页面经 `window.__TAURI_INTERNALS__.invoke` 调用）。

use tauri::State;

use crate::server::BackendStatus;
use crate::settings::{self, CloseAction};
use crate::ShellState;

/// 查询后端启动状态 `{ ready, url, port, error }`。
///
/// boot.html 轮询本命令：`ready == true` 后 `location.replace(url)` 跳转到
/// `http://127.0.0.1:<port>`；超时 / 子进程提前退出时 `error` 携带原因供页面展示。
#[tauri::command]
pub fn backend_status(state: State<'_, ShellState>) -> BackendStatus {
    state.status()
}

/// 查询关闭行为偏好（D11）：未设置（首次运行 / 文件损坏）返回 None。
///
/// 前端据此决定是否展示首次选择弹窗；纯网页模式（无 Tauri 桥）不调用本命令。
#[tauri::command]
pub fn get_close_action(state: State<'_, ShellState>) -> Option<String> {
    settings::load_close_action(&state.data_dir()).map(|a| a.as_str().to_string())
}

/// 写入关闭行为偏好（D11）：非法取值拒绝，防前端 bug 覆盖用户偏好。
/// 返回持久化后的取值（前端据此做读回验证，防静默写入失败）。
#[tauri::command]
pub fn set_close_action(state: State<'_, ShellState>, action: String) -> Result<String, String> {
    let parsed =
        CloseAction::parse(&action).ok_or_else(|| format!("非法关闭行为取值: {action}"))?;
    settings::save_close_action(&state.data_dir(), parsed)?;
    Ok(parsed.as_str().to_string())
}
