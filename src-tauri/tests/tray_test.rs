//! Seam 1 托盘状态纯逻辑测试（D5/D6）：菜单路由、窗口显隐决策、自启开关状态机。
//!
//! 全部为纯函数 / 状态机断言，不依赖真实 GUI 与插件。

use conver_app_lib::tray::{
    action_for_menu_id, decide_window_intent, AutostartIntent, TrayAction, TrayStatus,
    WindowIntent, MENU_ID_AUTOSTART, MENU_ID_QUIT, MENU_ID_SHOW_HIDE,
};

// ── 菜单路由 ────────────────────────────────────────────────────────────────

#[test]
fn menu_id_routes_to_actions() {
    assert_eq!(action_for_menu_id(MENU_ID_SHOW_HIDE), TrayAction::ShowHideWindow);
    assert_eq!(action_for_menu_id(MENU_ID_AUTOSTART), TrayAction::ToggleAutostart);
    assert_eq!(action_for_menu_id(MENU_ID_QUIT), TrayAction::Quit);
}

#[test]
fn unknown_menu_id_maps_to_unknown() {
    assert_eq!(action_for_menu_id(""), TrayAction::Unknown);
    assert_eq!(action_for_menu_id("not-a-menu"), TrayAction::Unknown);
}

// ── 窗口显隐决策（D5：菜单切换显隐）──────────────────────────────────────────

#[test]
fn window_intent_toggles_by_visibility() {
    assert_eq!(decide_window_intent(true), WindowIntent::Hide, "可见 → 隐藏");
    assert_eq!(decide_window_intent(false), WindowIntent::Show, "隐藏 → 显示");
}

// ── 托盘状态机 ──────────────────────────────────────────────────────────────

#[test]
fn tray_status_defaults_window_visible_and_autostart_off() {
    let status = TrayStatus::new();
    assert!(status.window_visible, "初始窗口应可见");
    assert!(!status.autostart_enabled, "开机自启默认关（D6）");
}

#[test]
fn autostart_toggle_cycles_with_intents() {
    let mut status = TrayStatus::new();
    assert_eq!(status.toggle_autostart(), AutostartIntent::Enable);
    assert!(status.autostart_enabled, "第一次切换应打开自启");
    assert_eq!(status.toggle_autostart(), AutostartIntent::Disable);
    assert!(!status.autostart_enabled, "第二次切换应关闭自启");
    assert_eq!(status.toggle_autostart(), AutostartIntent::Enable);
    assert!(status.autostart_enabled, "第三次切换应再次打开");
}

#[test]
fn autostart_sync_from_plugin_state() {
    // 启动时从插件回读注册表状态同步（插件不可用/失败时保持默认关）
    let mut status = TrayStatus::new();
    status.sync_autostart(true);
    assert!(status.autostart_enabled, "回读为开则同步为开");
    status.sync_autostart(false);
    assert!(!status.autostart_enabled, "回读为关则同步为关");
}

#[test]
fn autostart_toggle_after_sync_keeps_consistency() {
    // 回读为开（用户此前勾选过）→ 下一次切换应为关闭
    let mut status = TrayStatus::new();
    status.sync_autostart(true);
    assert_eq!(status.toggle_autostart(), AutostartIntent::Disable);
    assert!(!status.autostart_enabled);
}

#[test]
fn window_intent_applies_to_status() {
    let mut status = TrayStatus::new();
    status.apply_window_intent(WindowIntent::Hide);
    assert!(!status.window_visible, "隐藏意图应回写为不可见");
    status.apply_window_intent(WindowIntent::Show);
    assert!(status.window_visible, "显示意图应回写为可见");
}
