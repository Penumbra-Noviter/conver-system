//! 系统托盘（D5/D6）：关闭窗口 = 最小化到托盘；菜单 [显示/隐藏窗口、开机自启勾选、退出]。
//!
//! 纯逻辑部分（`action_for_menu_id` / `decide_window_intent` / `TrayStatus` 状态机）
//! 不依赖 GUI 与插件，可在 cargo test 中以 Seam 1 注入断言；
//! GUI 胶水（`setup_tray` / `handle_menu_event`）为薄层，直接操作 Tauri 运行时。

use std::sync::Mutex;

use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager, Wry};
use tauri_plugin_autostart::ManagerExt;

/// 主窗口 label（与 tauri.conf.json 的 windows[0].label 一致）。
pub const MAIN_WINDOW_LABEL: &str = "main";

/// 托盘菜单项 id（与 `action_for_menu_id` 的映射一致）。
pub const MENU_ID_SHOW_HIDE: &str = "show_hide";
pub const MENU_ID_AUTOSTART: &str = "autostart";
pub const MENU_ID_QUIT: &str = "quit";

/// 托盘菜单动作（由菜单项 id 路由而来）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayAction {
    /// 显示/隐藏主窗口（按当前可见性切换）。
    ShowHideWindow,
    /// 切换开机自启（写注册表，D6）。
    ToggleAutostart,
    /// 退出应用（走 ExitRequested → Exit → kill 后端子进程）。
    Quit,
    /// 未知菜单项（防御分支）。
    Unknown,
}

/// 菜单项 id → 动作映射（纯逻辑，可注入测试）。
pub fn action_for_menu_id(id: &str) -> TrayAction {
    match id {
        MENU_ID_SHOW_HIDE => TrayAction::ShowHideWindow,
        MENU_ID_AUTOSTART => TrayAction::ToggleAutostart,
        MENU_ID_QUIT => TrayAction::Quit,
        _ => TrayAction::Unknown,
    }
}

/// 窗口显隐意图。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowIntent {
    /// 显示并聚焦主窗口。
    Show,
    /// 隐藏主窗口（驻留托盘）。
    Hide,
}

/// 依据当前窗口可见性决策「显示/隐藏窗口」意图（D5：菜单切换显隐）。
pub fn decide_window_intent(window_visible: bool) -> WindowIntent {
    if window_visible {
        WindowIntent::Hide
    } else {
        WindowIntent::Show
    }
}

/// 自启切换意图。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutostartIntent {
    /// 开启开机自启（写入注册表 Run 键）。
    Enable,
    /// 关闭开机自启（移除注册表 Run 键）。
    Disable,
}

/// 托盘状态机（Seam 1 纯逻辑）：窗口可见性 + 开机自启开关。
///
/// 约定（D6）：开机自启默认关；勾选状态在启动时从插件回读注册表同步。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrayStatus {
    /// 主窗口可见性镜像（GUI 层应用意图后以真实窗口状态回写）。
    pub window_visible: bool,
    /// 开机自启当前开关状态。
    pub autostart_enabled: bool,
}

impl Default for TrayStatus {
    fn default() -> Self {
        Self::new()
    }
}

impl TrayStatus {
    /// 初始状态：窗口可见、开机自启默认关（D6）。
    pub fn new() -> Self {
        Self {
            window_visible: true,
            autostart_enabled: false,
        }
    }

    /// 启动时从自启插件回读实际状态并同步（插件失败时保持默认关）。
    pub fn sync_autostart(&mut self, enabled: bool) {
        self.autostart_enabled = enabled;
    }

    /// 切换自启开关：翻转状态并返回应执行的插件意图（Enable/Disable）。
    pub fn toggle_autostart(&mut self) -> AutostartIntent {
        if self.autostart_enabled {
            self.autostart_enabled = false;
            AutostartIntent::Disable
        } else {
            self.autostart_enabled = true;
            AutostartIntent::Enable
        }
    }

    /// GUI 层应用窗口显隐意图后，以实际窗口状态同步记录。
    pub fn apply_window_intent(&mut self, intent: WindowIntent) {
        self.window_visible = match intent {
            WindowIntent::Show => true,
            WindowIntent::Hide => false,
        };
    }
}

/// 托盘运行时状态（Tauri managed）：状态机 + 自启勾选菜单项句柄（供切换勾选态）。
pub struct TrayState {
    /// 托盘状态机（GUI 层读写）。
    pub status: Mutex<TrayStatus>,
    /// 自启勾选菜单项（切换后需同步 checked 态）。
    autostart_item: Mutex<CheckMenuItem<Wry>>,
}

impl TrayState {
    /// 构造托盘运行时状态。
    pub fn new(autostart_item: CheckMenuItem<Wry>) -> Self {
        Self {
            status: Mutex::new(TrayStatus::new()),
            autostart_item: Mutex::new(autostart_item),
        }
    }

    /// 同步自启勾选菜单项的 checked 态（与状态机一致）。
    pub fn set_autostart_checked(&self, checked: bool) {
        let _ = self.autostart_item.lock().unwrap().set_checked(checked);
    }
}

/// 构建托盘图标与菜单（在应用 setup 中调用，晚于 single-instance 插件 setup）。
///
/// 菜单：显示/隐藏窗口、开机自启（勾选，初始状态从插件回读）、退出。
/// 托盘图标交由 app 持有，避免 drop 后图标消失。
pub fn setup_tray(app: &AppHandle<Wry>) -> tauri::Result<()> {
    let show_hide =
        MenuItem::with_id(app, MENU_ID_SHOW_HIDE, "显示/隐藏窗口", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, MENU_ID_QUIT, "退出", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;

    // 自启初始状态：从插件回读注册表；失败回退默认关（D6）并记录。
    let mut status = TrayStatus::new();
    match app.autolaunch().is_enabled() {
        Ok(enabled) => status.sync_autostart(enabled),
        Err(e) => eprintln!("[conver-shell] 读取开机自启状态失败（按默认关处理）: {e}"),
    }
    let autostart_item = CheckMenuItem::with_id(
        app,
        MENU_ID_AUTOSTART,
        "开机自启",
        true,
        status.autostart_enabled,
        None::<&str>,
    )?;
    let menu = Menu::with_items(app, &[&show_hide, &autostart_item, &separator, &quit])?;

    let tray_state = TrayState::new(autostart_item);
    app.manage(tray_state);

    let icon = match app.default_window_icon() {
        Some(icon) => icon.clone(),
        None => return Err(tauri::Error::AssetNotFound("默认窗口图标缺失".into())),
    };
    let tray = TrayIconBuilder::with_id("main-tray")
        .icon(icon)
        .menu(&menu)
        .on_menu_event(|app, event| handle_menu_event(app, event.id().as_ref()))
        .build(app)?;
    app.manage(tray);
    Ok(())
}

/// 处理托盘菜单事件：路由 id → 应用动作 → 同步状态机。
fn handle_menu_event(app: &AppHandle<Wry>, menu_id: &str) {
    match action_for_menu_id(menu_id) {
        TrayAction::ShowHideWindow => {
            let state = app.state::<TrayState>();
            // 以真实窗口可见性决策（避免状态机镜像过期导致的错误切换）；查询失败按可见处理
            let window = app.get_webview_window(MAIN_WINDOW_LABEL);
            let visible = window
                .as_ref()
                .map(|w| w.is_visible().unwrap_or(true))
                .unwrap_or(true);
            match decide_window_intent(visible) {
                WindowIntent::Hide => {
                    if let Some(w) = &window {
                        let _ = w.hide();
                    }
                }
                WindowIntent::Show => {
                    if let Some(w) = &window {
                        let _ = w.unminimize();
                        let _ = w.show();
                        let _ = w.set_focus();
                    }
                }
            }
            // 以实际窗口状态回写状态机（显隐失败时保持一致）
            let actual = window
                .map(|w| w.is_visible().unwrap_or(true))
                .unwrap_or(true);
            state.status.lock().unwrap().apply_window_intent(if actual {
                WindowIntent::Show
            } else {
                WindowIntent::Hide
            });
        }
        TrayAction::ToggleAutostart => {
            let state = app.state::<TrayState>();
            let intent = { state.status.lock().unwrap().toggle_autostart() };
            let result = match intent {
                AutostartIntent::Enable => app.autolaunch().enable(),
                AutostartIntent::Disable => app.autolaunch().disable(),
            };
            match result {
                Ok(()) => state.set_autostart_checked(intent == AutostartIntent::Enable),
                Err(e) => {
                    // 插件失败：回滚状态机，菜单勾选保持原状
                    eprintln!("[conver-shell] 开机自启切换失败: {e}");
                    let rolled_back = intent == AutostartIntent::Disable;
                    state.status.lock().unwrap().sync_autostart(rolled_back);
                }
            }
        }
        TrayAction::Quit => {
            // 走正常退出流程：ExitRequested → Exit → lib.rs 中 kill 后端子进程
            app.exit(0);
        }
        TrayAction::Unknown => eprintln!("[conver-shell] 未知托盘菜单项: {menu_id}"),
    }
}
