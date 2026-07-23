use std::{
    os::unix::net::UnixListener,
    path::PathBuf,
    process::Command,
    thread,
    time::{SystemTime, UNIX_EPOCH},
};

use rebecca_protocol::{Request, read_message, write_message};
use serde_json::{Value, json};

fn socket_path(name: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    PathBuf::from("/tmp").join(format!(
        "rebecca-actions-{name}-{}-{nonce}.sock",
        std::process::id()
    ))
}

fn action_response(request: &Request, action: &str) -> Value {
    json!({
        "protocol_version": 1,
        "request_id": request.request_id,
        "ok": true,
        "action": action,
        "executed": true,
        "method": format!("{action}_to_pid"),
        "before_revision": 1,
        "after_revision": 2
    })
}

#[test]
fn coordinate_click_sends_explicit_window_id() {
    let socket = socket_path("click-window");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "click");
        assert_eq!(
            request.arguments,
            json!({"count": 1, "x": 100.0, "y": 200.0, "window_id": 481})
        );
        write_message(&mut stream, &action_response(&request, "click")).unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "click",
            "--x",
            "100",
            "--y",
            "200",
            "--window-id",
            "481",
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
    assert_eq!(value["method"], "click_to_pid");
}

#[test]
fn untargeted_key_sends_explicit_window_id() {
    let socket = socket_path("key-window");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.command, "key");
        assert_eq!(
            request.arguments,
            json!({"chord": "cmd+a", "window_id": 481})
        );
        write_message(&mut stream, &action_response(&request, "key")).unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "key",
            "--chord",
            "cmd+a",
            "--window-id",
            "481",
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
    assert_eq!(value["method"], "key_to_pid");
}

#[test]
fn untargeted_type_without_window_id_is_rejected_before_connecting() {
    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "type",
            "--text",
            "hello",
            "--json",
            "--no-start",
            "--socket",
            "/tmp/rebecca-actions-missing-window-type.sock",
        ])
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(2));
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["error"]["code"], "target_window_required");
}

#[test]
fn coordinate_click_without_window_id_is_rejected_before_connecting() {
    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "click",
            "--x",
            "100",
            "--y",
            "200",
            "--json",
            "--no-start",
            "--socket",
            "/tmp/rebecca-actions-missing-window.sock",
        ])
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(2));
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["error"]["code"], "target_window_required");
}
