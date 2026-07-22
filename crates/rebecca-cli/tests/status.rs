use std::{
    os::unix::net::UnixListener,
    path::PathBuf,
    process::Command,
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use rebecca_protocol::{
    DisplayInfo, DisplaysResponse, HostStatus, LogicalFrame, PROTOCOL_VERSION, PermissionState,
    Permissions, PixelSize, Request, StatusResponse, read_message, write_message,
};
use serde_json::{Value, json};

fn socket_path(name: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    PathBuf::from("/tmp").join(format!(
        "rebecca-{name}-{}-{nonce}.sock",
        std::process::id()
    ))
}

#[test]
fn status_json_uses_one_valid_json_object_and_sends_versioned_request() {
    let socket = socket_path("status");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.protocol_version, PROTOCOL_VERSION);
        assert_eq!(request.command, "status");
        assert!(!request.request_id.is_empty());

        write_message(
            &mut stream,
            &StatusResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: true,
                host: Some(HostStatus {
                    running: true,
                    version: "0.1.0".into(),
                    pid: 42,
                    bundle_id: None,
                    executable_path: None,
                }),
                permissions: Some(Permissions {
                    accessibility: PermissionState::Granted,
                    screen_recording: PermissionState::Denied,
                }),
                emergency_stop: Some(false),
                error: None,
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["status", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["protocol_version"], PROTOCOL_VERSION);
    assert_eq!(value["host"]["running"], true);
}

#[test]
fn displays_json_uses_top_level_result_and_revision() {
    let socket = socket_path("displays");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        assert_eq!(request.protocol_version, PROTOCOL_VERSION);
        assert_eq!(request.command, "displays");
        assert_eq!(request.arguments, json!({}));
        assert!(!request.request_id.is_empty());

        write_message(
            &mut stream,
            &DisplaysResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: true,
                revision: Some(7),
                displays: Some(vec![DisplayInfo {
                    display_id: 1,
                    logical_frame: LogicalFrame {
                        x: -1440.0,
                        y: 0.0,
                        width: 1440.0,
                        height: 900.0,
                    },
                    pixel_size: PixelSize {
                        width: 2880,
                        height: 1800,
                    },
                    scale_factor: 2.0,
                    primary: false,
                }]),
                error: None,
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["displays", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["revision"], 7);
    assert_eq!(value["displays"][0]["display_id"], 1);
    assert_eq!(value["displays"][0]["logical_frame"]["x"], -1440.0);
    assert_eq!(value["displays"][0]["pixel_size"]["width"], 2880);
}

fn assert_invalid_display_response(name: &str, display: DisplayInfo) {
    let socket = socket_path(name);
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        write_message(
            &mut stream,
            &DisplaysResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: true,
                revision: Some(1),
                displays: Some(vec![display]),
                error: None,
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["displays", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert_eq!(output.status.code(), Some(11));
    assert!(output.stderr.is_empty());
    let value: Value =
        serde_json::from_str(String::from_utf8(output.stdout).unwrap().trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "protocol_mismatch");
}

#[test]
fn invalid_display_metadata_is_protocol_mismatch() {
    let base = DisplayInfo {
        display_id: 1,
        logical_frame: LogicalFrame {
            x: 0.0,
            y: 0.0,
            width: 1440.0,
            height: 900.0,
        },
        pixel_size: PixelSize {
            width: 2880,
            height: 1800,
        },
        scale_factor: 2.0,
        primary: true,
    };

    let mut zero_id = base.clone();
    zero_id.display_id = 0;
    assert_invalid_display_response("displays-zero-id", zero_id);

    let mut zero_frame = base.clone();
    zero_frame.logical_frame.width = 0.0;
    assert_invalid_display_response("displays-zero-frame", zero_frame);

    let mut zero_pixel_width = base.clone();
    zero_pixel_width.pixel_size.width = 0;
    assert_invalid_display_response("displays-zero-pixel-width", zero_pixel_width);

    let mut zero_pixel_height = base.clone();
    zero_pixel_height.pixel_size.height = 0;
    assert_invalid_display_response("displays-zero-pixel-height", zero_pixel_height);

    let mut invalid_scale = base;
    invalid_scale.scale_factor = -1.0;
    assert_invalid_display_response("displays-invalid-scale", invalid_scale);
}

#[test]
fn displays_permission_denied_maps_to_host_error_exit_code() {
    let socket = socket_path("displays-permission");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        write_message(
            &mut stream,
            &DisplaysResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id: request.request_id,
                ok: false,
                revision: None,
                displays: None,
                error: Some(rebecca_protocol::ProtocolError {
                    code: "permission_denied".into(),
                    message: "Screen Recording permission is required for displays.".into(),
                    details: None,
                }),
            },
        )
        .unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["displays", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert_eq!(output.status.code(), Some(5));
    assert!(output.stderr.is_empty());
    let value: Value =
        serde_json::from_str(String::from_utf8(output.stdout).unwrap().trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "permission_denied");
}

#[test]
fn information_parse_outcomes_exit_zero_and_write_standard_output() {
    for (arguments, expected_output) in [
        (vec!["--help"], "Usage: rebecca"),
        (vec!["status", "--help"], "Usage: rebecca status"),
        (vec!["--version"], "rebecca 0.1.0"),
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
            .args(arguments)
            .output()
            .unwrap();

        assert_eq!(output.status.code(), Some(0));
        assert!(output.stderr.is_empty());
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(stdout.contains(expected_output));
        assert!(serde_json::from_str::<Value>(stdout.trim()).is_err());
    }
}

#[test]
fn global_timeout_and_verbose_are_accepted_before_and_after_the_command() {
    for (name, arguments) in [
        (
            "before",
            vec![
                "--timeout",
                "250ms",
                "--verbose",
                "status",
                "--json",
                "--no-start",
                "--socket",
            ],
        ),
        (
            "after",
            vec![
                "status",
                "--timeout",
                "250ms",
                "--verbose",
                "--json",
                "--no-start",
                "--socket",
            ],
        ),
    ] {
        let socket = socket_path(name);
        let listener = UnixListener::bind(&socket).unwrap();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let request: Request = read_message(&mut stream).unwrap();
            write_message(
                &mut stream,
                &StatusResponse {
                    protocol_version: PROTOCOL_VERSION,
                    request_id: request.request_id,
                    ok: true,
                    host: Some(HostStatus {
                        running: true,
                        version: "0.1.0".into(),
                        pid: 42,
                        bundle_id: None,
                        executable_path: None,
                    }),
                    permissions: Some(Permissions {
                        accessibility: PermissionState::Granted,
                        screen_recording: PermissionState::Denied,
                    }),
                    emergency_stop: Some(false),
                    error: None,
                },
            )
            .unwrap();
        });

        let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
            .args(arguments)
            .arg(&socket)
            .output()
            .unwrap();
        worker.join().unwrap();
        std::fs::remove_file(&socket).unwrap();

        assert!(output.status.success());
        assert!(!output.stderr.is_empty());
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert_eq!(stdout.lines().count(), 1);
        assert_eq!(
            serde_json::from_str::<Value>(stdout.trim()).unwrap()["ok"],
            true
        );
    }
}

#[test]
fn socket_timeout_uses_json_stdout_without_verbose_diagnostics() {
    let socket = socket_path("timeout");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let _: Request = read_message(&mut stream).unwrap();
        thread::sleep(Duration::from_millis(100));
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args([
            "status",
            "--json",
            "--timeout",
            "10ms",
            "--no-start",
            "--socket",
        ])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert_eq!(output.status.code(), Some(4));
    assert!(output.stderr.is_empty());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "ipc_error");
}

#[test]
fn bad_cli_input_exits_two_and_json_output_is_one_object() {
    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["status", "--json", "--socket"])
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(2));
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "invalid_input");
}

#[test]
fn invalid_duration_exits_two_and_emits_json_invalid_input() {
    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["status", "--json", "--timeout", "5m"])
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(2));
    assert!(output.stderr.is_empty());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "invalid_input");
}

#[test]
fn unavailable_host_with_no_start_exits_three_and_emits_json_error() {
    let socket = socket_path("unavailable");
    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["status", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(3));
    assert!(output.stderr.is_empty());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "host_unavailable");
}

fn valid_status_response() -> Value {
    json!({
        "protocol_version": PROTOCOL_VERSION,
        "request_id": "placeholder",
        "ok": true,
        "host": {"running": true, "version": "0.1.0", "pid": 42},
        "permissions": {"accessibility": "granted", "screen_recording": "denied"},
        "emergency_stop": false,
    })
}

fn assert_protocol_mismatch(name: &str, mut response: Value, match_request_id: bool) {
    let socket = socket_path(name);
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        if match_request_id {
            response["request_id"] = Value::String(request.request_id);
        }
        write_message(&mut stream, &response).unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["status", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert_eq!(output.status.code(), Some(11));
    assert!(output.stderr.is_empty());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "protocol_mismatch");
}

fn valid_failure_response() -> Value {
    json!({
        "protocol_version": PROTOCOL_VERSION,
        "request_id": "placeholder",
        "ok": false,
        "error": {"code": "permission_denied", "message": "Permission is denied."},
    })
}

#[test]
fn malformed_failure_responses_exit_eleven() {
    let mut null_error = valid_failure_response();
    null_error["error"] = Value::Null;

    let missing_error = json!({
        "protocol_version": PROTOCOL_VERSION,
        "request_id": "placeholder",
        "ok": false,
    });

    for (name, response) in [("null-error", null_error), ("missing-error", missing_error)] {
        assert_protocol_mismatch(name, response, true);
    }
}

#[test]
fn failure_responses_missing_required_correlation_fields_exit_eleven() {
    let mut missing_protocol_version = valid_failure_response();
    missing_protocol_version
        .as_object_mut()
        .unwrap()
        .remove("protocol_version");

    let mut missing_request_id = valid_failure_response();
    missing_request_id
        .as_object_mut()
        .unwrap()
        .remove("request_id");

    let mut empty_request_id = valid_failure_response();
    empty_request_id["request_id"] = Value::String(String::new());

    for (name, response) in [
        ("failure-missing-protocol-version", missing_protocol_version),
        ("failure-missing-request-id", missing_request_id),
        ("failure-empty-request-id", empty_request_id),
    ] {
        assert_protocol_mismatch(name, response, false);
    }
}

#[test]
fn failure_responses_with_result_fields_exit_eleven() {
    for field in ["host", "permissions", "emergency_stop"] {
        let mut response = valid_failure_response();
        response[field] = Value::Null;
        assert_protocol_mismatch(&format!("failure-with-{field}"), response, true);
    }
}

#[test]
fn valid_failure_response_preserves_host_error_exit_mapping() {
    let socket = socket_path("mapped-host-error");
    let listener = UnixListener::bind(&socket).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let request: Request = read_message(&mut stream).unwrap();
        let mut response = valid_failure_response();
        response["request_id"] = Value::String(request.request_id);
        write_message(&mut stream, &response).unwrap();
    });

    let output = Command::new(env!("CARGO_BIN_EXE_rebecca"))
        .args(["status", "--json", "--no-start", "--socket"])
        .arg(&socket)
        .output()
        .unwrap();
    worker.join().unwrap();
    std::fs::remove_file(&socket).unwrap();

    assert_eq!(output.status.code(), Some(5));
    assert!(output.stderr.is_empty());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1);
    let value: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "permission_denied");
}

#[test]
fn malformed_success_response_exits_nonzero_without_emitting_invalid_status_json() {
    assert_protocol_mismatch(
        "missing-success-fields",
        json!({
            "protocol_version": PROTOCOL_VERSION,
            "request_id": "placeholder",
            "ok": true,
        }),
        true,
    );
}

#[test]
fn successful_status_responses_that_violate_schema_exit_eleven() {
    let mut host_not_running = valid_status_response();
    host_not_running["host"]["running"] = json!(false);

    let mut zero_pid = valid_status_response();
    zero_pid["host"]["pid"] = json!(0);

    let mut success_with_error = valid_status_response();
    success_with_error["error"] = json!({"code": "internal_error", "message": "unexpected"});

    let mut success_with_null_error = valid_status_response();
    success_with_null_error["error"] = Value::Null;

    let mut unknown_response_field = valid_status_response();
    unknown_response_field["unexpected"] = json!(true);

    let mut unknown_host_field = valid_status_response();
    unknown_host_field["host"]["unexpected"] = json!(true);

    for (name, response) in [
        ("host-not-running", host_not_running),
        ("zero-pid", zero_pid),
        ("success-with-error", success_with_error),
        ("success-with-null-error", success_with_null_error),
        ("unknown-response-field", unknown_response_field),
        ("unknown-host-field", unknown_host_field),
    ] {
        assert_protocol_mismatch(name, response, true);
    }
}
