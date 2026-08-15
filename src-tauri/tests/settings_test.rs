//! Seam 1 关闭行为偏好纯逻辑测试（D11）：解析、决策、settings.json 读写。
//!
//! 全部使用临时目录，不依赖真实 GUI 与 Tauri 运行时。

use std::path::{Path, PathBuf};

use conver_app_lib::settings::{
    decide_close, load_close_action, save_close_action, settings_file, CloseAction, CloseDecision,
    SETTINGS_FILE,
};

// ── 测试辅助 ────────────────────────────────────────────────────────────────

/// 创建独立临时目录（按测试名区分，进程内唯一）。
fn tmp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("p64-1-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("创建临时目录失败");
    dir
}

/// 直接写 settings.json（构造损坏/异常文件场景）。
fn write_raw(dir: &Path, content: &str) {
    std::fs::write(dir.join(SETTINGS_FILE), content).expect("写入 settings.json 失败");
}

// ── CloseAction 解析 ─────────────────────────────────────────────────────────

#[test]
fn close_action_parses_known_values() {
    assert_eq!(CloseAction::parse("tray"), Some(CloseAction::Tray));
    assert_eq!(CloseAction::parse("quit"), Some(CloseAction::Quit));
}

#[test]
fn close_action_rejects_unknown_values() {
    assert_eq!(CloseAction::parse("minimize"), None, "未知取值不应静默兜底");
    assert_eq!(CloseAction::parse(""), None);
    assert_eq!(CloseAction::parse("TRAY"), None, "大小写敏感");
}

#[test]
fn close_action_as_str_roundtrips() {
    for action in [CloseAction::Tray, CloseAction::Quit] {
        assert_eq!(CloseAction::parse(action.as_str()), Some(action));
    }
}

// ── 决策（偏好 → 关闭行为）──────────────────────────────────────────────────

#[test]
fn decide_close_quits_only_on_explicit_choice() {
    assert_eq!(
        decide_close(Some(CloseAction::Quit)),
        CloseDecision::Quit,
        "显式选择直接退出 → 放行关闭"
    );
}

#[test]
fn decide_close_defaults_to_tray() {
    assert_eq!(
        decide_close(None),
        CloseDecision::MinimizeToTray,
        "未设置（首次运行）→ 保持 D5 默认最小化到托盘"
    );
    assert_eq!(
        decide_close(Some(CloseAction::Tray)),
        CloseDecision::MinimizeToTray
    );
}

// ── settings.json 读写 ───────────────────────────────────────────────────────

#[test]
fn load_missing_file_is_unset() {
    let dir = tmp_dir("missing");
    assert_eq!(load_close_action(&dir), None, "文件缺失 = 未设置");
}

#[test]
fn save_then_load_roundtrips() {
    for action in [CloseAction::Tray, CloseAction::Quit] {
        let dir = tmp_dir("roundtrip");
        save_close_action(&dir, action).expect("保存失败");
        assert_eq!(load_close_action(&dir), Some(action));
        assert!(
            !dir.join(SETTINGS_FILE).with_extension("json.tmp").exists(),
            "原子写不应残留临时文件"
        );
    }
}

#[test]
fn save_overwrites_previous_choice() {
    let dir = tmp_dir("overwrite");
    save_close_action(&dir, CloseAction::Tray).expect("保存失败");
    save_close_action(&dir, CloseAction::Quit).expect("覆盖失败");
    assert_eq!(load_close_action(&dir), Some(CloseAction::Quit));
}

#[test]
fn load_corrupt_json_is_unset() {
    let dir = tmp_dir("corrupt");
    write_raw(&dir, "{ 这不是 JSON");
    assert_eq!(load_close_action(&dir), None, "JSON 损坏 = 未设置（自愈重问）");
}

#[test]
fn load_invalid_field_is_unset() {
    let dir = tmp_dir("invalid-field");
    write_raw(&dir, r#"{ "close_action": "minimize" }"#);
    assert_eq!(load_close_action(&dir), None, "字段取值非法 = 未设置");
}

#[test]
fn load_missing_field_is_unset() {
    let dir = tmp_dir("missing-field");
    write_raw(&dir, r#"{ "other": 1 }"#);
    assert_eq!(load_close_action(&dir), None, "字段缺失 = 未设置");
}

#[test]
fn settings_file_path_joins_data_dir() {
    let dir = tmp_dir("path");
    assert_eq!(
        settings_file(&dir),
        dir.join(SETTINGS_FILE),
        "settings.json 与 runtime.json 同目录"
    );
}
