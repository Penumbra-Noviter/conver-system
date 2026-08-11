//! ShellState 状态机 + 完整启动链测试（spawn → HTTP 探测 → 就绪 → runtime.json 写出）。
//!
//! 关键链使用本地 python 桩 HTTP 服务（非真实 uvicorn），验证 shell 契约：
//! 端口探测 → 子进程启动（含环境注入由 server_test 覆盖）→ 就绪判定 → 就绪标记落盘。

use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant};

use conver_app_lib::server::{read_runtime_json, BackendConfig};
use conver_app_lib::ShellState;

// ── 测试辅助 ────────────────────────────────────────────────────────────────

fn tmp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("p64-1-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("创建临时目录失败");
    dir
}

fn python_available() -> bool {
    Command::new("python")
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// 在任意端口返回 200 的 python 桩后端脚本；端口来自 spawn 追加的 --port 参数。
fn stub_backend_script() -> String {
    "import sys\n\
     from http.server import BaseHTTPRequestHandler, HTTPServer\n\
     i = sys.argv.index('--port')\n\
     port = int(sys.argv[i+1])\n\
     class H(BaseHTTPRequestHandler):\n\
     \x20   def do_GET(self):\n\
     \x20       self.send_response(200); self.end_headers()\n\
     \x20   def log_message(self, *a): pass\n\
     HTTPServer(('127.0.0.1', port), H).serve_forever()"
        .into()
}

fn sleep_child_script(seconds: u32) -> Vec<String> {
    vec!["-c".into(), format!("import time; time.sleep({seconds})")]
}

fn sleep_until(deadline: Instant, mut cond: impl FnMut() -> bool, msg: &str) {
    while !cond() {
        assert!(Instant::now() < deadline, "{msg}");
        std::thread::sleep(Duration::from_millis(100));
    }
}

// ── 状态机基础 ──────────────────────────────────────────────────────────────

#[test]
fn status_reports_not_started() {
    let dir = tmp_dir("state-new");
    let state = ShellState::new(0, dir);
    let s = state.status();
    assert!(!s.ready, "未启动不应就绪");
    assert_eq!(s.port, 0);
    assert!(s.url.is_none(), "端口未知不应有 url");
    assert!(s.error.is_none());
}

#[test]
fn status_reports_url_when_port_known() {
    let dir = tmp_dir("state-port");
    let state = ShellState::new(8123, dir);
    let s = state.status();
    assert_eq!(s.port, 8123);
    assert_eq!(s.url.as_deref(), Some("http://127.0.0.1:8123"));
    assert!(!s.ready);
}

#[test]
fn try_start_records_error_for_bad_command() {
    let dir = tmp_dir("state-badcmd");
    let state = ShellState::new(0, dir);
    let old = std::env::var("CONVER_BACKEND_CMD").ok();
    std::env::set_var("CONVER_BACKEND_CMD", "python \"unclosed");
    let result = state.try_start();
    match old {
        Some(v) => std::env::set_var("CONVER_BACKEND_CMD", v),
        None => std::env::remove_var("CONVER_BACKEND_CMD"),
    }
    assert!(result.is_err(), "非法命令串应启动失败");
    assert!(state.status().error.is_some(), "失败原因应记录到状态");
}

// ── 完整关键链：spawn → 探测 → 就绪 → runtime.json ─────────────────────────

#[test]
fn full_chain_spawn_probe_ready_and_runtime_json() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("state-ready");
    let state = ShellState::new(0, dir.clone());
    let cfg = BackendConfig {
        program: "python".into(),
        args: vec!["-c".into(), stub_backend_script()],
        cwd: None,
        extra_env: vec![],
    };
    state
        .try_start_with_timeout(cfg, Duration::from_secs(8))
        .expect("启动桩后端应成功");

    sleep_until(
        Instant::now() + Duration::from_secs(15),
        || state.status().ready,
        "桩后端未在时限内就绪",
    );

    let s = state.status();
    assert!(s.port > 0, "应探测到动态端口");
    assert_eq!(s.url.as_deref(), Some(format!("http://127.0.0.1:{}", s.port).as_str()));

    // 就绪契约：runtime.json 含 port + ready + pid，外部轮询可读
    let path = dir.join("runtime.json");
    let info = read_runtime_json(&path).expect("runtime.json 应已写出");
    assert!(info.ready);
    assert_eq!(info.port, s.port);
    assert!(info.pid.is_some(), "runtime.json 应含后端 pid");
    assert!(info.error.is_none());

    state.kill_child();
}

#[test]
fn full_chain_timeout_records_error_and_runtime_json() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("state-timeout");
    let state = ShellState::new(0, dir.clone());
    let cfg = BackendConfig {
        program: "python".into(),
        args: sleep_child_script(120), // 不监听任何端口 → 永不就绪
        cwd: None,
        extra_env: vec![],
    };
    state
        .try_start_with_timeout(cfg, Duration::from_millis(700))
        .expect("spawn 应成功");

    sleep_until(
        Instant::now() + Duration::from_secs(10),
        || state.status().error.is_some(),
        "超时错误未记录",
    );

    let s = state.status();
    assert!(!s.ready, "超时路径不应就绪");
    assert!(
        s.error.as_deref().unwrap_or("").contains("超时"),
        "错误信息应说明超时，实际: {:?}",
        s.error
    );

    let info = read_runtime_json(&dir.join("runtime.json")).expect("runtime.json 应写出");
    assert!(!info.ready);
    assert!(info.error.is_some());
    state.kill_child();
}

#[test]
fn full_chain_child_exit_records_error_and_runtime_json() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("state-exited");
    let state = ShellState::new(0, dir.clone());
    let cfg = BackendConfig {
        program: "python".into(),
        args: vec!["-c".into(), "import sys; sys.exit(7)".into()],
        cwd: None,
        extra_env: vec![],
    };
    state
        .try_start_with_timeout(cfg, Duration::from_secs(8))
        .expect("spawn 应成功");

    sleep_until(
        Instant::now() + Duration::from_secs(10),
        || state.status().error.is_some(),
        "提前退出错误未记录",
    );

    let s = state.status();
    assert!(!s.ready, "提前退出路径不应就绪");
    assert!(
        s.error.as_deref().unwrap_or("").contains("提前退出"),
        "错误信息应说明提前退出，实际: {:?}",
        s.error
    );
    assert!(
        s.error.as_deref().unwrap_or("").contains("7"),
        "错误信息应含退出码 7，实际: {:?}",
        s.error
    );

    let info = read_runtime_json(&dir.join("runtime.json")).expect("runtime.json 应写出");
    assert!(!info.ready);
    assert!(info.error.is_some());
    state.kill_child();
}

#[test]
fn kill_child_terminates_backend_process() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("state-kill");
    let state = ShellState::new(0, dir);
    let cfg = BackendConfig {
        program: "python".into(),
        args: sleep_child_script(300),
        cwd: None,
        extra_env: vec![],
    };
    state
        .try_start_with_timeout(cfg, Duration::from_millis(500))
        .expect("spawn 应成功");
    let pid = state.child_pid().expect("应有子进程 pid");

    state.kill_child();
    std::thread::sleep(Duration::from_millis(300));

    let out = Command::new("tasklist")
        .args(["/FI", &format!("PID eq {pid}"), "/FO", "CSV", "/NH"])
        .output()
        .expect("tasklist 应可执行");
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(
        !text.contains(&pid.to_string()),
        "kill_child 后 pid {pid} 应已退出（输出: {text}）"
    );
}
