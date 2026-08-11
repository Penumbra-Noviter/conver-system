//! Seam 1 纯逻辑测试：端口探测、命令行解析、子进程启停、就绪判定、runtime.json 读写。
//!
//! 全部使用临时目录 / 桩进程（python 短脚本）或本地 TCP stub，不依赖真实 uvicorn 后端。

use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use conver_app_lib::server::{
    backend_config_from_env, data_dir_path, database_url, default_data_dir, find_prod_backend_exe,
    http_probe, parse_command_line, probe_free_port, prod_backend_exe_candidates,
    read_runtime_json, spawn_backend, wait_until_ready, write_runtime_json, BackendConfig,
    ReadyOutcome, RuntimeInfo, DEFAULT_DEV_BACKEND_CMD,
};

// ── 测试辅助 ────────────────────────────────────────────────────────────────

/// 创建独立临时目录（按测试名区分，进程内唯一）。
fn tmp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("p64-1-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("创建临时目录失败");
    dir
}

/// 在闭包执行期间临时设置/移除环境变量，闭包结束后恢复原值。
fn with_env(key: &str, value: Option<&str>, f: impl FnOnce()) {
    let old = std::env::var(key).ok();
    match value {
        Some(v) => std::env::set_var(key, v),
        None => std::env::remove_var(key),
    }
    f();
    match old {
        Some(v) => std::env::set_var(key, v),
        None => std::env::remove_var(key),
    }
}

/// 判断 python 是否可用（不可用时跳过依赖真实解释器的测试）。
fn python_available() -> bool {
    Command::new("python")
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// 构造「睡 N 秒」的 python 桩进程参数（用于启停/生命周期测试）。
fn sleep_child_script(seconds: u32) -> Vec<String> {
    vec![
        "-c".into(),
        format!("import time; time.sleep({seconds})"),
    ]
}

/// 在指定端口起一个返回 200 的 TCP stub 服务线程；返回句柄与就绪信号。
fn stub_server(port: u16) -> (std::thread::JoinHandle<()>, mpsc::Receiver<()>) {
    stub_server_with_response(port, b"HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n")
}

/// 在指定端口起一个返回指定响应体的 TCP stub 服务线程。
fn stub_server_with_response(
    port: u16,
    response: &'static [u8],
) -> (std::thread::JoinHandle<()>, mpsc::Receiver<()>) {
    let (tx, rx) = mpsc::channel();
    let handle = std::thread::spawn(move || {
        let listener = TcpListener::bind(("127.0.0.1", port)).expect("stub 绑定失败");
        let _ = tx.send(());
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { break };
            let _ = stream.read(&mut [0u8; 512]);
            let _ = stream.write_all(response);
        }
    });
    (handle, rx)
}

/// 探测一个未被占用的端口。
fn free_port() -> u16 {
    TcpListener::bind(("127.0.0.1", 0))
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

// ── 端口探测 ────────────────────────────────────────────────────────────────

#[test]
fn probe_free_port_returns_bindable_port() {
    let port = probe_free_port().expect("端口探测应成功");
    assert!(port > 0, "端口号应大于 0");
    let listener = TcpListener::bind(("127.0.0.1", port)).expect("探测出的端口应可再次绑定");
    assert_eq!(listener.local_addr().unwrap().port(), port);
}

// ── 命令行解析（CONVER_BACKEND_CMD seam）────────────────────────────────────

#[test]
fn parse_command_line_splits_whitespace() {
    let tokens = parse_command_line("python -m uvicorn backend.app.main:app").unwrap();
    assert_eq!(tokens, vec!["python", "-m", "uvicorn", "backend.app.main:app"]);
}

#[test]
fn parse_command_line_handles_double_quotes() {
    let tokens = parse_command_line("\"C:/Program Files/app.exe\" --host 127.0.0.1").unwrap();
    assert_eq!(tokens, vec!["C:/Program Files/app.exe", "--host", "127.0.0.1"]);
}

#[test]
fn parse_command_line_rejects_unclosed_quote() {
    assert!(parse_command_line("python \"abc").is_err(), "未闭合引号应报错");
}

#[test]
fn parse_command_line_rejects_empty_or_blank() {
    assert!(parse_command_line("").is_err(), "空命令应报错");
    assert!(parse_command_line("   ").is_err(), "纯空白命令应报错");
}

#[test]
fn backend_config_from_env_env_variants() {
    // 顺序执行全部断言（同一测试内无并发），避免 CONVER_BACKEND_CMD 相关用例并行互踩环境变量。
    assert_eq!(DEFAULT_DEV_BACKEND_CMD, "python -m uvicorn backend.app.main:app");
    let prod_dir = Some(Path::new(r"C:\Users\Me\AppData\Roaming\Conver System"));
    // 开发态（dev_mode=true）：显式环境变量覆盖 > 缺省 uvicorn 命令
    with_env("CONVER_BACKEND_CMD", None, || {
        let cfg = backend_config_from_env(true, None).expect("默认配置应可解析");
        assert_eq!(cfg.program, "python");
        assert_eq!(cfg.args, vec!["-m", "uvicorn", "backend.app.main:app"]);
        assert_eq!(cfg.cwd, None);
    });
    with_env("CONVER_BACKEND_CMD", Some("\"C:/Program Files/app.exe\" --flag"), || {
        let cfg = backend_config_from_env(true, None).expect("覆盖配置应可解析");
        assert_eq!(cfg.program, "C:/Program Files/app.exe");
        assert_eq!(cfg.args, vec!["--flag"]);
    });
    with_env("CONVER_BACKEND_CMD", Some("python \"unclosed"), || {
        assert!(backend_config_from_env(true, None).is_err(), "非法命令串应报错");
    });
    // 生产态（dev_mode=false）+ 资源目录含随包后端 → 命中 `_up_/dist/conver_backend` 布局
    let prod_dir = tmp_dir("prod-layout");
    let prod_exe = prod_dir
        .join("_up_")
        .join("dist")
        .join("conver_backend")
        .join("conver_backend.exe");
    std::fs::create_dir_all(prod_exe.parent().unwrap()).unwrap();
    std::fs::write(&prod_exe, b"stub").unwrap();
    with_env("CONVER_BACKEND_CMD", None, || {
        let cfg = backend_config_from_env(false, Some(&prod_dir)).expect("生产态配置应可解析");
        assert_eq!(
            cfg.program,
            prod_exe.to_string_lossy(),
            "生产态应定位随包后端 exe"
        );
        assert!(cfg.args.is_empty(), "随包 exe 无需附加参数");
    });
    // 生产态但资源目录无随包后端（如 --no-bundle 直接跑 release exe）→ 降级开发态命令
    let empty_dir = tmp_dir("prod-empty");
    with_env("CONVER_BACKEND_CMD", None, || {
        let cfg = backend_config_from_env(false, Some(&empty_dir)).expect("回退配置应可解析");
        assert_eq!(cfg.program, "python");
        assert_eq!(cfg.args, vec!["-m", "uvicorn", "backend.app.main:app"]);
    });
    // 生产态下 CONVER_BACKEND_CMD 仍是权威通道（覆盖随包 exe 定位）
    with_env("CONVER_BACKEND_CMD", Some("\"D:/custom/backend.exe\""), || {
        let cfg = backend_config_from_env(false, Some(&prod_dir)).expect("覆盖配置应可解析");
        assert_eq!(cfg.program, "D:/custom/backend.exe");
        assert!(cfg.args.is_empty());
    });
}

// ── 生产态后端定位（P6.4-6 期末审核阻断 1：安装态双击直启，US-1）────────────

#[test]
fn prod_backend_exe_candidates_ordered_by_windows_layout() {
    // 安装目录含空格（NSIS currentUser → %LOCALAPPDATA%\Conver System\）；
    // 候选 1 = _up_/dist/conver_backend（Tauri Windows 实测布局），候选 2 = 平铺兜底
    let candidates = prod_backend_exe_candidates(Path::new(r"C:\Users\Me\AppData\Roaming\Conver System"));
    assert_eq!(
        candidates[0].to_string_lossy(),
        r"C:\Users\Me\AppData\Roaming\Conver System\_up_\dist\conver_backend\conver_backend.exe"
    );
    assert_eq!(
        candidates[1].to_string_lossy(),
        r"C:\Users\Me\AppData\Roaming\Conver System\conver_backend\conver_backend.exe"
    );
}

#[test]
fn find_prod_backend_exe_detects_up_layout_then_fallback_layout() {
    // 构造「安装态 _up_/dist/conver_backend」布局 → 命中候选 1
    let dir = tmp_dir("prod-up");
    let up_exe = dir
        .join("_up_")
        .join("dist")
        .join("conver_backend")
        .join("conver_backend.exe");
    std::fs::create_dir_all(up_exe.parent().unwrap()).unwrap();
    std::fs::write(&up_exe, b"stub").unwrap();
    assert_eq!(find_prod_backend_exe(&dir), Some(up_exe));

    // 无 _up_ 布局、仅有平铺布局 → 命中候选 2
    let dir2 = tmp_dir("prod-flat");
    let flat_exe = dir2.join("conver_backend").join("conver_backend.exe");
    std::fs::create_dir_all(flat_exe.parent().unwrap()).unwrap();
    std::fs::write(&flat_exe, b"stub").unwrap();
    assert_eq!(find_prod_backend_exe(&dir2), Some(flat_exe));

    // 两种布局都不存在 → None（调用方回退开发态命令）
    let dir3 = tmp_dir("prod-none");
    assert_eq!(find_prod_backend_exe(&dir3), None);
}

// ── DATABASE_URL 契约 ───────────────────────────────────────────────────────

#[test]
fn database_url_points_at_data_dir_db_with_forward_slashes() {
    let dir = tmp_dir("dburl");
    let url = database_url(&dir);
    let expected = format!(
        "sqlite+aiosqlite:///{}/conver_system.db",
        dir.to_string_lossy().replace('\\', "/")
    );
    assert_eq!(url, expected);
    assert!(!url.contains('\\'), "Windows 反斜杠应转换为正斜杠");
}

// ── 子进程启停 ──────────────────────────────────────────────────────────────

#[test]
fn spawn_backend_injects_env_and_database_url() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("spawn-env");
    let out = dir.join("env.txt");
    // argv: [-c, script, <out>, --host 127.0.0.1 --port 8123 --log-level warning]
    // 注意：python -c 时 sys.argv[0] == "-c"，第一个位置参数从 argv[1] 起。
    let script = "import os,sys;open(sys.argv[1],'w').write(os.environ['DATABASE_URL']+'|'+os.environ.get('CONVER_TEST_FLAG',''))";
    let cfg = BackendConfig {
        program: "python".into(),
        args: vec!["-c".into(), script.into(), out.to_string_lossy().into_owned()],
        cwd: None,
        extra_env: vec![("CONVER_TEST_FLAG".into(), "42".into())],
    };
    let mut child = spawn_backend(&cfg, 8123, &dir).expect("spawn 应成功");
    assert!(child.pid().is_some(), "子进程应有 pid");

    let deadline = Instant::now() + Duration::from_secs(10);
    let content = loop {
        if out.exists() {
            break std::fs::read_to_string(&out).expect("env.txt 应可读");
        }
        assert!(Instant::now() < deadline, "env.txt 未在时限内写出");
        std::thread::sleep(Duration::from_millis(100));
    };
    let expected = format!(
        "sqlite+aiosqlite:///{}/conver_system.db|42",
        dir.to_string_lossy().replace('\\', "/")
    );
    assert_eq!(content, expected, "DATABASE_URL 与额外环境变量应注入子进程");
    child.kill();
}

#[test]
fn spawn_backend_missing_program_errors() {
    let dir = tmp_dir("spawn-missing");
    let cfg = BackendConfig {
        program: "conver-definitely-not-exist-xyz".into(),
        args: vec![],
        cwd: None,
        extra_env: vec![],
    };
    assert!(spawn_backend(&cfg, 8123, &dir).is_err(), "不存在的程序应报错");
}

#[test]
fn managed_child_kill_terminates_process() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("kill");
    let cfg = BackendConfig {
        program: "python".into(),
        args: sleep_child_script(300),
        cwd: None,
        extra_env: vec![],
    };
    let mut child = spawn_backend(&cfg, 8123, &dir).expect("spawn 应成功");
    let pid = child.pid().expect("应有 pid");
    assert!(child.try_exit_code().is_none(), "进程应仍在运行");

    // kill() 会 take 掉 child（之后 try_exit_code 恒为 None），以系统层面验证进程已终止。
    child.kill();
    assert_process_gone(pid);
}

#[test]
fn managed_child_drop_kills_process() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("drop");
    let pid = {
        let cfg = BackendConfig {
            program: "python".into(),
            args: sleep_child_script(300),
            cwd: None,
            extra_env: vec![],
        };
        let child = spawn_backend(&cfg, 8123, &dir).expect("spawn 应成功");
        child.pid().expect("应有 pid")
    }; // 离开作用域 → Drop 兜底 kill
    std::thread::sleep(Duration::from_millis(300));
    assert_process_gone(pid);
}

/// 断言指定 pid 已不在系统中（tasklist 过滤查询）。
fn assert_process_gone(pid: u32) {
    let out = Command::new("tasklist")
        .args(["/FI", &format!("PID eq {pid}"), "/FO", "CSV", "/NH"])
        .output()
        .expect("tasklist 应可执行");
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(
        !text.contains(&pid.to_string()),
        "pid {pid} 不应仍存活（tasklist 输出: {text}）"
    );
}

// ── 就绪判定 ────────────────────────────────────────────────────────────────

#[test]
fn wait_until_ready_immediate_ready() {
    let outcome = wait_until_ready(|| true, || None, Duration::from_millis(120), Duration::from_millis(10));
    assert_eq!(outcome, ReadyOutcome::Ready);
}

#[test]
fn wait_until_ready_succeeds_after_retries() {
    let mut attempts = 0;
    let outcome = wait_until_ready(
        || {
            attempts += 1;
            attempts >= 3
        },
        || None,
        Duration::from_secs(5),
        Duration::from_millis(10),
    );
    assert_eq!(outcome, ReadyOutcome::Ready);
    assert_eq!(attempts, 3, "应重试到第三次才就绪");
}

#[test]
fn wait_until_ready_times_out_when_never_ready() {
    let outcome = wait_until_ready(|| false, || None, Duration::from_millis(120), Duration::from_millis(10));
    assert!(matches!(outcome, ReadyOutcome::TimedOut));
}

#[test]
fn wait_until_ready_detects_child_exit() {
    let outcome = wait_until_ready(|| false, || Some(3), Duration::from_secs(5), Duration::from_millis(10));
    assert!(matches!(outcome, ReadyOutcome::ChildExited(3)));
}

#[test]
fn http_probe_returns_true_for_200_response() {
    let port = free_port();
    let (handle, rx) = stub_server(port);
    rx.recv_timeout(Duration::from_secs(2)).expect("stub 应就绪");
    assert!(http_probe(port, Duration::from_secs(2)), "200 响应应判定就绪");
    drop(handle);
}

#[test]
fn http_probe_false_when_connection_refused() {
    let port = free_port(); // 端口已释放，无服务监听
    assert!(!http_probe(port, Duration::from_millis(500)));
}

#[test]
fn http_probe_false_for_non_200_response() {
    let port = free_port();
    let (handle, rx) = stub_server_with_response(port, b"HTTP/1.0 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n");
    rx.recv_timeout(Duration::from_secs(2)).expect("stub 应就绪");
    assert!(!http_probe(port, Duration::from_secs(2)), "非 200 响应不应判定就绪");
    drop(handle);
}

// ── runtime.json 读写 ───────────────────────────────────────────────────────

#[test]
fn runtime_json_roundtrip() {
    let dir = tmp_dir("runtime");
    let path = dir.join("runtime.json");
    let info = RuntimeInfo {
        port: 8123,
        ready: true,
        pid: Some(42),
        error: None,
    };
    write_runtime_json(&path, &info).expect("写入应成功");
    let read = read_runtime_json(&path).expect("读取应成功");
    assert_eq!(read, info);

    let text = std::fs::read_to_string(&path).unwrap();
    assert!(text.contains("\"port\": 8123"), "应输出人类可读 JSON");
    assert!(text.contains("\"ready\": true"));
}

#[test]
fn runtime_json_missing_file_errors() {
    let dir = tmp_dir("runtime-missing");
    assert!(read_runtime_json(&dir.join("runtime.json")).is_err(), "文件缺失应报错");
}

#[test]
fn runtime_json_corrupt_file_errors() {
    let dir = tmp_dir("runtime-corrupt");
    let path = dir.join("runtime.json");
    std::fs::write(&path, "not json {").unwrap();
    assert!(read_runtime_json(&path).is_err(), "损坏 JSON 应报错");
    // 写中断场景：轮询方读到半截 JSON（尾部截断）同样应报错而非误判
    std::fs::write(&path, "{\"port\": 8123, \"ready\": true,").unwrap();
    assert!(read_runtime_json(&path).is_err(), "半截 JSON 应报错");
}

#[test]
fn runtime_json_atomic_write_leaves_no_tmp() {
    // 原子写（F2）：写后目标目录不应残留临时文件
    let dir = tmp_dir("runtime-atomic");
    let path = dir.join("runtime.json");
    let info = RuntimeInfo {
        port: 8123,
        ready: true,
        pid: Some(42),
        error: None,
    };
    write_runtime_json(&path, &info).expect("写入应成功");
    let leftovers: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_name().to_string_lossy().contains(".tmp"))
        .collect();
    assert!(leftovers.is_empty(), "原子写后不应残留临时文件: {leftovers:?}");
}

#[test]
fn runtime_json_atomic_write_replaces_existing() {
    // 原子替换（F2）：旧值被完整替换为新值，读回始终是完整 JSON
    let dir = tmp_dir("runtime-replace");
    let path = dir.join("runtime.json");
    write_runtime_json(
        &path,
        &RuntimeInfo {
            port: 1,
            ready: false,
            pid: None,
            error: Some("旧值".into()),
        },
    )
    .expect("首次写入应成功");
    write_runtime_json(
        &path,
        &RuntimeInfo {
            port: 8123,
            ready: true,
            pid: Some(42),
            error: None,
        },
    )
    .expect("替换写入应成功");
    let read = read_runtime_json(&path).expect("替换后应可完整读回");
    assert_eq!(read.port, 8123);
    assert!(read.ready);
    assert!(read.error.is_none());
}

#[test]
fn runtime_json_write_missing_parent_dir_errors() {
    let dir = tmp_dir("runtime-parent");
    let info = RuntimeInfo {
        port: 1,
        ready: false,
        pid: None,
        error: None,
    };
    assert!(
        write_runtime_json(&dir.join("no-such-dir").join("runtime.json"), &info).is_err(),
        "父目录缺失应报错"
    );
}

// ── 数据目录 ────────────────────────────────────────────────────────────────

#[test]
fn data_dir_path_appends_conver_system() {
    assert_eq!(
        data_dir_path(Path::new("C:/base")),
        PathBuf::from("C:/base/ConverSystem")
    );
}

#[test]
fn default_data_dir_env_priority() {
    // 顺序执行四组断言（同一测试内无并发），避免环境变量用例并行互踩。
    // 优先级契约（与迁移脚本 P6.4-3 对齐）：CONVER_DATA_DIR > APPDATA > CWD 兜底。
    with_env("CONVER_DATA_DIR", Some("C:/custom/data"), || {
        with_env("APPDATA", None, || {
            assert_eq!(default_data_dir(), PathBuf::from("C:/custom/data"));
        });
    });
    with_env("CONVER_DATA_DIR", Some("C:/custom/data"), || {
        with_env("APPDATA", Some("C:/Users/tester/AppData/Roaming"), || {
            assert_eq!(
                default_data_dir(),
                PathBuf::from("C:/custom/data"),
                "CONVER_DATA_DIR 应优先于 APPDATA"
            );
        });
    });
    with_env("CONVER_DATA_DIR", Some(""), || {
        with_env("APPDATA", Some("C:/Users/tester/AppData/Roaming"), || {
            assert_eq!(
                default_data_dir(),
                PathBuf::from("C:/Users/tester/AppData/Roaming/ConverSystem"),
                "CONVER_DATA_DIR 空串应视为未设置（与迁移脚本 falsy 语义一致）"
            );
        });
    });
    with_env("CONVER_DATA_DIR", None, || {
        with_env("APPDATA", Some("C:/Users/tester/AppData/Roaming"), || {
            assert_eq!(
                default_data_dir(),
                PathBuf::from("C:/Users/tester/AppData/Roaming/ConverSystem")
            );
        });
    });
    with_env("CONVER_DATA_DIR", None, || {
        with_env("APPDATA", None, || {
            let dir = default_data_dir();
            assert!(dir.ends_with("ConverSystem"), "无任何变量时应回退到 CWD 下");
        });
    });
}
