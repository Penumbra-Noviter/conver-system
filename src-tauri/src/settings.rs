//! 桌面壳用户设置（D11：关闭行为偏好）：settings.json 持久化。
//!
//! 纯逻辑部分（`CloseAction` 解析 / `decide_close` 决策）不依赖 GUI 与文件，
//! 可在 cargo test 中注入断言；文件读写（`load_close_action` / `save_close_action`）
//! 与命令层为薄胶水。文件与 runtime.json 同目录（数据目录见 `server::default_data_dir`）。

use std::path::{Path, PathBuf};

/// settings.json 文件名（数据目录下，与 runtime.json 并列）。
pub const SETTINGS_FILE: &str = "settings.json";

/// 关闭窗口时的行为偏好。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CloseAction {
    /// 最小化到托盘（后台继续运行，D5 既有默认）。
    Tray,
    /// 直接退出程序（走正常退出流，Exit 事件清理后端子进程）。
    Quit,
}

impl CloseAction {
    /// 持久化字符串（settings.json 的 `close_action` 字段取值）。
    pub fn as_str(&self) -> &'static str {
        match self {
            CloseAction::Tray => "tray",
            CloseAction::Quit => "quit",
        }
    }

    /// 严格解析：未知取值返回 None（写路径拒绝非法值，不静默兜底）。
    pub fn parse(s: &str) -> Option<CloseAction> {
        match s {
            "tray" => Some(CloseAction::Tray),
            "quit" => Some(CloseAction::Quit),
            _ => None,
        }
    }
}

/// 关闭窗口决策（由偏好派生，CloseRequested 处理器消费）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CloseDecision {
    /// 拦截关闭 → 隐藏窗口驻留托盘。
    MinimizeToTray,
    /// 放行关闭 → 应用走正常退出流（Exit 清理子进程，无残留）。
    Quit,
}

/// 偏好 → 关闭决策：未设置（首次运行 / 文件损坏）与非法值回退最小化到托盘
/// （保持 D5 既有行为，用户未选择前不改变关闭语义）。
pub fn decide_close(action: Option<CloseAction>) -> CloseDecision {
    match action {
        Some(CloseAction::Quit) => CloseDecision::Quit,
        _ => CloseDecision::MinimizeToTray,
    }
}

/// settings.json 绝对路径。
pub fn settings_file(data_dir: &Path) -> PathBuf {
    data_dir.join(SETTINGS_FILE)
}

/// 读取关闭行为偏好：文件缺失 / JSON 损坏 / 字段缺失或非法 → None（未设置）。
///
/// None 语义：首次运行（前端据此弹首次选择）或文件损坏自愈（前端重新引导写入）；
/// 关闭决策侧由 `decide_close` 回退 D5 默认，不改变既有行为。
pub fn load_close_action(data_dir: &Path) -> Option<CloseAction> {
    let data = std::fs::read_to_string(settings_file(data_dir)).ok()?;
    let value: serde_json::Value = serde_json::from_str(&data).ok()?;
    value
        .get("close_action")
        .and_then(|v| v.as_str())
        .and_then(CloseAction::parse)
}

/// 写入关闭行为偏好（原子写：先写同目录临时文件再 rename 替换，
/// 与 `server::write_runtime_json` 同款，防半截文件被读作损坏）。
pub fn save_close_action(data_dir: &Path, action: CloseAction) -> Result<(), String> {
    let path = settings_file(data_dir);
    // 防御性确保目录存在（调用方通常已创建，但首次写入前或数据目录被清理时可兜底）
    std::fs::create_dir_all(data_dir).map_err(|e| format!("创建设置目录失败: {e}"))?;
    let json = serde_json::json!({ "close_action": action.as_str() });
    let text =
        serde_json::to_string_pretty(&json).map_err(|e| format!("序列化 settings.json 失败: {e}"))?;
    let file_name = path
        .file_name()
        .ok_or_else(|| "settings.json 路径缺少文件名".to_string())?;
    let tmp_path = path.with_file_name(format!("{}.tmp", file_name.to_string_lossy()));
    std::fs::write(&tmp_path, format!("{text}\n"))
        .map_err(|e| format!("写入 settings.json 失败: {e}"))?;
    std::fs::rename(&tmp_path, &path).map_err(|e| format!("替换 settings.json 失败: {e}"))?;
    Ok(())
}
