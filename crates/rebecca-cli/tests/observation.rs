use std::{
    os::unix::net::UnixListener,
    path::PathBuf,
    process::Command,
    thread,
    time::{SystemTime, UNIX_EPOCH},
};

use rebecca_protocol::{
    CaptureResponse, CaptureTarget, LogicalFrame, PROTOCOL_VERSION, PixelSize, Request, WindowInfo,
    WindowsResponse, read_message, write_message,
};
use serde_json::{Value, json};

fn socket_path(name: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    PathBuf::from("/tmp").join(format!(
        "rebecca-observation-{name}-{}-{nonce}.sock",
        std::process::id()
    ))
}

fn fixture_window() -> WindowInfo {
    WindowInfo {
        window_id: 481,
        owner_pid: Some(1234),
        bundle_id: Some("dev.jwoo0122.rebecca-fixture".into()),
        title: Some("Rebecca Fixture".into()),
        logical_frame: LogicalFrame {
            x: 120.0,
            y: 80.0,
            width: 640.0,
            height: 420.0,
        },
        onscreen: true,
        minimized: Some(false),
        focused: None,
        display_id: Some(1),
    }
}

#[test]
fn windows_json_sends_exact_bundle_filter_and_top_level_response() {
    let socket = socket_path("windows-filter");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "windows");
        assert_eq!(
            request.arguments,
            json!({"app": "dev.jwoo0122.rebecca-fixture"})
        );
        write_message(
            &mut stream,
            &WindowsResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: true,
                revision: Some(4),
                windows: Some(vec![fixture_window()]),
                error: None,
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "windows",
            "--app",
            "dev.jwoo0122.rebecca-fixture",
            "--json",
            "--no-start",
            "--socket",
        ])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value: Value =
        serde_json::from_str(String::from_utf8(output.stdout).unwrap().trim()).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["revision"], 4);
    assert_eq!(value["windows"][0]["window_id"], 481);
    assert_eq!(value["windows"][0]["focused"], Value::Null);
}

#[test]
fn windows_without_filter_sends_empty_arguments() {
    let socket = socket_path("windows-all");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "windows");
        assert_eq!(request.arguments, json!({}));
        write_message(
            &mut stream,
            &WindowsResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: true,
                revision: Some(1),
                windows: Some(Vec::new()),
                error: None,
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["windows", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["windows"], json!([]));
}

fn assert_invalid_window_response(name: &str, window: WindowInfo) {
    let socket = socket_path(name);
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        write_message(
            &mut stream,
            &WindowsResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: true,
                revision: Some(1),
                windows: Some(vec![window]),
                error: None,
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["windows", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert_eq!(output.status.code(), Some(11));
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["error"]["code"], "protocol_mismatch");
}

#[test]
fn windows_rejects_zero_display_id_and_contradictory_visibility() {
    let mut zero_display = fixture_window();
    zero_display.display_id = Some(0);
    assert_invalid_window_response("windows-zero-display", zero_display);

    let mut contradictory = fixture_window();
    contradictory.minimized = Some(true);
    assert_invalid_window_response("windows-contradictory-visibility", contradictory);
}

#[test]
fn capture_json_sends_absolute_output_and_returns_metadata() {
    let socket = socket_path("capture");
    let listener = UnixListener::bind(&socket).unwrap();
    let output_path = std::env::current_dir()
        .unwrap()
        .join("build/test-capture.png");
    let expected_output = output_path.to_string_lossy().into_owned();
    let worker_output = expected_output.clone();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "capture");
        assert_eq!(
            request.arguments,
            json!({"window_id": 481, "output": worker_output})
        );
        write_message(
            &mut stream,
            &CaptureResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: true,
                path: Some(worker_output),
                target: Some(CaptureTarget {
                    target_type: "window".into(),
                    id: 481,
                }),
                pixel_size: Some(PixelSize {
                    width: 1280,
                    height: 840,
                }),
                logical_frame: Some(fixture_window().logical_frame),
                scale_factor: Some(2.0),
                revision: Some(4),
                error: None,
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "capture",
            "--window-id",
            "481",
            "--output",
            "build/test-capture.png",
            "--json",
            "--no-start",
            "--socket",
        ])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["path"], expected_output);
    assert_eq!(value["target"]["type"], "window");
    assert_eq!(value["target"]["id"], 481);
}

#[test]
fn capture_rejects_invalid_cli_arguments_before_connecting() {
    for arguments in [
        vec![
            "capture",
            "--window-id",
            "0",
            "--output",
            "/tmp/frame.png",
            "--json",
        ],
        vec![
            "capture",
            "--window-id",
            "1",
            "--output",
            "/tmp/frame.jpg",
            "--json",
        ],
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
            .args(arguments)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(2));
        let value: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "invalid_input");
    }
}

#[test]
fn capture_target_not_found_preserves_exit_mapping() {
    let socket = socket_path("capture-not-found");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        write_message(
            &mut stream,
            &CaptureResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: false,
                path: None,
                target: None,
                pixel_size: None,
                logical_frame: None,
                scale_factor: None,
                revision: None,
                error: Some(rebecca_protocol::ProtocolError {
                    code: "target_not_found".into(),
                    message: "Window 481 was not found.".into(),
                    details: None,
                }),
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "capture",
            "--window-id",
            "481",
            "--output",
            "/tmp/missing-window.png",
            "--json",
            "--no-start",
            "--socket",
        ])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert_eq!(output.status.code(), Some(6));
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["error"]["code"], "target_not_found");
}

#[test]
fn act_sends_request_scoped_locator_without_a_session_handle() {
    let socket = socket_path("act");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "act");
        assert_eq!(
            request.arguments,
            json!({
                "action": "press",
                "window_id": 2939,
                "role": "AXLink",
                "label": "에덴의 문"
            })
        );
        write_message(
            &mut stream,
            &json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": request.request_id,
                "ok": true,
                "action": "act",
                "executed": true,
                "method": "ax_press_background",
                "before_revision": 10,
                "after_revision": 11
            }),
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "act",
            "--window-id",
            "2939",
            "--action",
            "press",
            "--role",
            "AXLink",
            "--label",
            "에덴의 문",
            "--json",
            "--no-start",
            "--socket",
        ])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["action"], "act");
    assert_eq!(value["after_revision"], 11);
}

#[test]
fn act_rejects_ambiguous_target_arguments_before_connecting() {
    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "act",
            "--app",
            "com.apple.Safari",
            "--window-id",
            "2939",
            "--action",
            "press",
            "--label",
            "target",
            "--json",
        ])
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(2));
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "invalid_input");
}

#[test]
fn navigate_sends_expectations_as_one_stateless_request() {
    let socket = socket_path("navigate");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "navigate");
        assert_eq!(
            request.arguments,
            json!({
                "window_id": 2939,
                "url": "https://example.test/posts",
                "expect_url": "https://example.test/posts",
                "expect_title": "Example",
                "wait_ms": 1500
            })
        );
        write_message(
            &mut stream,
            &json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": request.request_id,
                "ok": true,
                "action": "navigate",
                "executed": true,
                "method": "cg_key_type_key",
                "before_revision": 10,
                "after_revision": 11,
                "verified": true,
                "before_url": "https://example.test/old",
                "after_url": "https://example.test/posts",
                "before_title": "Old",
                "after_title": "Example"
            }),
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "navigate",
            "--window-id",
            "2939",
            "--url",
            "https://example.test/posts",
            "--expect-url",
            "https://example.test/posts",
            "--expect-title",
            "Example",
            "--wait-ms",
            "1500",
            "--json",
            "--no-start",
            "--socket",
        ])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["action"], "navigate");
    assert_eq!(value["verified"], true);
    assert_eq!(value["after_title"], "Example");
}

#[test]
fn wait_until_requires_a_condition_before_connecting() {
    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "wait-until",
            "--window-id",
            "2939",
            "--wait-ms",
            "100",
            "--json",
        ])
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(2));
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "invalid_input");
}

#[test]
fn scroll_to_end_sends_only_the_request_scoped_target() {
    let socket = socket_path("scroll-to-end");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "scroll_to_end");
        assert_eq!(request.arguments, json!({"window_id": 2939}));
        write_message(
            &mut stream,
            &json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": request.request_id,
                "ok": true,
                "action": "scroll_to_end",
                "executed": true,
                "method": "ax_set_vertical_scroll_bar",
                "before_revision": 10,
                "after_revision": 11,
                "verified": true,
                "at_end": true
            }),
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "scroll-to-end",
            "--window-id",
            "2939",
            "--json",
            "--no-start",
            "--socket",
        ])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["action"], "scroll_to_end");
    assert_eq!(value["at_end"], true);
}
