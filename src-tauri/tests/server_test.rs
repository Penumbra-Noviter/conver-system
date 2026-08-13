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
    backend_config_from_env, data_dir_path, database_url, default_data_dir, encode_url_path,
    find_prod_backend_exe, http_probe, parse_command_line, probe_free_port,
    prod_backend_exe_candidates, read_runtime_json, spawn_arguments, spawn_backend,
    wait_until_ready, write_runtime_json, BackendConfig, ReadyOutcome, RuntimeInfo,
    DEFAULT_DEV_BACKEND_CMD,
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

/// 在指定端口起一个「记录请求首行并返回 200」的 TCP stub 服务线程。
///
/// 监听器在主线程绑定（无「http_probe 先于 bind 连接」的竞态），
/// 返回句柄与首行接收通道——用于钉就绪探测的请求形状（RS-1 R1 契约锁）。
fn stub_server_capture(port: u16) -> (std::thread::JoinHandle<()>, mpsc::Receiver<String>) {
    let listener = TcpListener::bind(("127.0.0.1", port)).expect("stub 绑定失败");
    let (tx, rx) = mpsc::channel();
    let handle = std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { break };
            let mut buf = [0u8; 512];
            let n = stream.read(&mut buf).unwrap_or(0);
            let _ = tx.send(String::from_utf8_lossy(&buf[..n]).into_owned());
            let _ = stream.write_all(b"HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n");
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

// ── 契约表 v2：URL 编码（镜像 backend/tests/test_data_dir.py，同一版本号互引）────

#[test]
fn encode_url_path_matches_contract_table_v2() {
    // 契约表 v2（期末审核 Falsify 阻断项修复）：编码集 = {? → %3F}，其余原样保留——
    // SQLAlchemy sqlite 方言对 DATABASE_URL 零解码，空格/中文/#/% 必须直连
    // （基线实测可用；连接级验证见 backend/tests/test_data_dir_connection.py）；
    // ? 是 URL 解析器唯一实际分隔符（防御性编码，Windows 非法文件名不可达）。
    assert_eq!(encode_url_path("a#b?c%d e"), "a#b%3Fc%d e");
    assert_eq!(encode_url_path("数据 目录"), "数据 目录");
    assert_eq!(
        encode_url_path("C:/Users/x/AppData/Roaming/Conver System"),
        "C:/Users/x/AppData/Roaming/Conver System"
    );
    assert_eq!(
        encode_url_path("C:/Users/x/AppData/Roaming/数据#目录%v1/"),
        "C:/Users/x/AppData/Roaming/数据#目录%v1/"
    );
    assert_eq!(encode_url_path("a~b.c-d_e"), "a~b.c-d_e", "非 ? 字符一律原样保留");
}

#[test]
fn encode_url_path_ascii_boundary() {
    // 逐字符钉住 v2 编码集边界（ASCII 0x00-0x7F 全表）：
    // 仅 `?` → %3F（大写十六进制），其余全部原样保留——防过编码也防漏编码。
    for code in 0u8..=127u8 {
        let c = code as char;
        let input = c.to_string();
        let expected = if c == '?' { "%3F".to_string() } else { input.clone() };
        assert_eq!(encode_url_path(&input), expected, "ASCII 0x{code:02X} 编码与契约表 v2 不符");
    }
}

#[test]
fn database_url_keeps_special_chars_encodes_question_mark() {
    // 数据目录含空格/中文/#/%：原样保留直连（零解码消费者）；仅字面 `?` 编码为 %3F
    // （URL 解析器分隔符防御；`?` 为 Windows 非法文件名，真实目录不可达）
    let dir = Path::new(r"C:/Users/tester/AppData/Roaming/Conver 数据#目录?v1%");
    let url = database_url(dir);
    assert_eq!(
        url,
        "sqlite+aiosqlite:///C:/Users/tester/AppData/Roaming/Conver 数据#目录%3Fv1%/conver_system.db"
    );
    assert!(!url.contains('\\'), "反斜杠应已转正斜杠");
}

// ── 子进程启停 ──────────────────────────────────────────────────────────────

// ── 壳追加参数契约（RS-1 R1：argv 精确形状）────────────────────────────────

/// 契约锁：壳追加的后端启动参数精确形状（顺序敏感）——
/// `--host <BACKEND_HOST> --port <port> --log-level warning`。
/// 后端镜像契约：`run_backend.build_parser`（pytest 互引见 backend/tests/test_packaging.py）。
#[test]
fn spawn_arguments_exact_shape_with_order() {
    assert_eq!(
        spawn_arguments(8123),
        vec![
            "--host".to_string(),
            "127.0.0.1".to_string(),
            "--port".to_string(),
            "8123".to_string(),
            "--log-level".to_string(),
            "warning".to_string(),
        ]
    );
    // 边界：端口 0 也要能构成合法形状（参数键序不变）
    assert_eq!(
        spawn_arguments(0),
        vec![
            "--host".to_string(),
            "127.0.0.1".to_string(),
            "--port".to_string(),
            "0".to_string(),
            "--log-level".to_string(),
            "warning".to_string(),
        ]
    );
}

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

/// 已退出进程 kill 不挂死（有界回收契约）：子进程自行退出后 kill() 必须即时返回。
///
/// 实际覆盖路径：try_wait 早返回（early-return 先于 taskkill，taskkill 分支在此用例
/// 中不会执行——注入失败分支无 seam，见 spec 风险清单）；已退出进程恒返回 Some 故
/// early-return 恒生效，任何路径不得无限阻塞（旧实现 taskkill 失败且进程存活时
/// 无条件 child.wait() 会挂死）。
#[test]
fn managed_child_kill_on_exited_process_returns_promptly() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("kill-exited");
    let cfg = BackendConfig {
        program: "python".into(),
        args: vec!["-c".into(), "import sys; sys.exit(0)".into()],
        cwd: None,
        extra_env: vec![],
    };
    let mut child = spawn_backend(&cfg, 8123, &dir).expect("spawn 应成功");
    let pid = child.pid().expect("应有 pid");
    // 等子进程自行退出（不回收句柄，模拟「已退出未回收」状态）
    let deadline = Instant::now() + Duration::from_secs(10);
    while process_alive(pid) {
        assert!(Instant::now() < deadline, "子进程未在时限内自行退出");
        std::thread::sleep(Duration::from_millis(100));
    }
    // kill() 必须即时返回（有界 wait 契约：已退出路径不得挂死）
    let start = Instant::now();
    child.kill();
    assert!(
        start.elapsed() < Duration::from_secs(5),
        "已退出进程的 kill() 应即时返回（实测 {:?}）",
        start.elapsed()
    );
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

/// R2（Windows）：带树终止——python 桩 spawn 孙进程后 kill 父进程，孙进程必须一并消失。
///
/// dev 态 venv 的 python 重定向器会 spawn 孙进程，只杀直接子进程会残留后端进程；
/// taskkill /T 保证整树终止。非 Windows 分支无树终止语义，断言不可达属预期
/// （平台守卫先例：TD-25 批次 skipif 隔离）。
#[test]
#[cfg(windows)]
fn managed_child_kill_reaps_grandchild_tree_on_windows() {
    if !python_available() {
        return;
    }
    let dir = tmp_dir("kill-tree");
    let out = dir.join("grandchild.pid");
    // 父 python 桩：spawn 一个睡 300s 的孙进程 → 孙进程 pid 落盘 → 父进程长睡
    // （sys.argv[1] = 输出路径；壳追加的 --host/--port 等参数排在更后面，不影响）
    let script = "import subprocess, sys, time\n\
        p = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'])\n\
        open(sys.argv[1], 'w').write(str(p.pid))\n\
        time.sleep(300)";
    let cfg = BackendConfig {
        program: "python".into(),
        args: vec!["-c".into(), script.into(), out.to_string_lossy().into_owned()],
        cwd: None,
        extra_env: vec![],
    };
    let mut child = spawn_backend(&cfg, 8123, &dir).expect("spawn 应成功");
    let parent_pid = child.pid().expect("父进程应有 pid");

    // 等待孙进程 pid 落盘，并确认孙进程确实存活（kill 前先验条件）
    let deadline = Instant::now() + Duration::from_secs(10);
    let grandchild_pid: u32 = loop {
        if let Ok(text) = std::fs::read_to_string(&out) {
            break text.trim().parse().expect("孙进程 pid 应为数字");
        }
        assert!(Instant::now() < deadline, "孙进程 pid 未在时限内写出");
        std::thread::sleep(Duration::from_millis(100));
    };
    assert!(process_alive(grandchild_pid), "孙进程 {grandchild_pid} 应存活于 kill 前");

    // kill 父进程 → 树终止 → 孙进程一并消失（taskkill /F 异步终止，轮询等待退出）
    child.kill();
    let deadline = Instant::now() + Duration::from_secs(5);
    while process_alive(grandchild_pid) {
        assert!(Instant::now() < deadline, "孙进程 {grandchild_pid} 未在时限内退出");
        std::thread::sleep(Duration::from_millis(100));
    }
    assert_process_gone(parent_pid);
}

/// 查询 pid 是否仍在系统中（tasklist 过滤查询）。
fn process_alive(pid: u32) -> bool {
    let out = Command::new("tasklist")
        .args(["/FI", &format!("PID eq {pid}"), "/FO", "CSV", "/NH"])
        .output()
        .expect("tasklist 应可执行");
    String::from_utf8_lossy(&out.stdout).contains(&pid.to_string())
}

/// 断言指定 pid 已不在系统中（tasklist 过滤查询）。
fn assert_process_gone(pid: u32) {
    assert!(
        !process_alive(pid),
        "pid {pid} 不应仍存活（tasklist 应查无此进程）"
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

/// 契约锁（RS-1 R1）：就绪探测请求行必须命中就绪路径字面量 `GET /api/models HTTP/1.1`——
/// 路径漂移会让壳就绪探测永远失败（后端 models 路由互引见
/// backend/tests/test_packaging.py；实现用 `READY_PROBE_PATH` 常量）。
#[test]
fn http_probe_requests_ready_probe_path() {
    let port = free_port();
    let (handle, rx) = stub_server_capture(port);
    assert!(http_probe(port, Duration::from_secs(2)), "200 响应应判定就绪");
    let request = rx
        .recv_timeout(Duration::from_secs(2))
        .expect("stub 应收到探测请求");
    let request_line = request.lines().next().unwrap_or("");
    assert_eq!(
        request_line,
        "GET /api/models HTTP/1.1",
        "请求行必须含就绪路径字面量，实际: {request_line:?}"
    );
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
    // 契约表 v2（与 backend/tests/test_data_dir.py 互引，同一版本号）：
    // CONVER_DATA_DIR（非空）> APPDATA > USERPROFILE\AppData\Roaming > CWD 末位兜底（不可达）。
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
                "CONVER_DATA_DIR 空串应视为未设置（契约表 v2：非空才生效）"
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
    // APPDATA 缺失 → USERPROFILE\AppData\Roaming 兜底（决策 D1-D2，对齐 Python home 兜底）
    with_env("CONVER_DATA_DIR", None, || {
        with_env("APPDATA", None, || {
            with_env("USERPROFILE", Some("C:/Users/tester"), || {
                assert_eq!(
                    default_data_dir(),
                    PathBuf::from("C:/Users/tester/AppData/Roaming/ConverSystem"),
                    "USERPROFILE 兜底应对齐 Python 侧 home\\AppData\\Roaming 语义"
                );
            });
        });
    });
    // USERPROFILE 也缺失的不可达场景：CWD 末位兜底保留（注释说明，正常 Windows 必有 USERPROFILE）
    with_env("CONVER_DATA_DIR", None, || {
        with_env("APPDATA", None, || {
            with_env("USERPROFILE", None, || {
                let dir = default_data_dir();
                assert!(dir.ends_with("ConverSystem"), "无任何变量时应回退到 CWD 下");
            });
        });
    });
}
