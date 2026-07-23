use std::{
    env, io,
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::{Duration, Instant},
};

use clap::{Parser, Subcommand, error::ErrorKind};
use rebecca_protocol::{
    AppsResponse, CaptureResponse, DisplayInfo, DisplaysResponse, FocusedResponse,
    PROTOCOL_VERSION, ProtocolError, Request, StatusResponse, TreeResponse, WindowInfo,
    WindowsResponse, read_message, write_message,
};
use serde::Serialize;
use serde_json::{Value, json};
use uuid::Uuid;

const START_TIMEOUT: Duration = Duration::from_secs(3);
const IO_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Parser)]
#[command(name = "rebecca", version, about = "macOS Rebecca command-line client")]
struct Cli {
    /// Emit one JSON object to stdout.
    #[arg(long, global = true)]
    json: bool,

    /// Connect to this Unix socket instead of the default host socket.
    #[arg(long, global = true)]
    socket: Option<PathBuf>,

    /// Do not launch Rebecca.app when the host is unavailable.
    #[arg(long, global = true)]
    no_start: bool,

    /// Set host-start and socket I/O timeout (positive integer with `ms` or `s` suffix, e.g. `250ms` or `2s`).
    #[arg(long, global = true, value_name = "duration", value_parser = parse_duration)]
    timeout: Option<Duration>,

    /// Print connection diagnostics to stderr.
    #[arg(long, global = true)]
    verbose: bool,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Report host and permission status.
    Status,
    /// Report active displays and their coordinate metadata.
    Displays,
    /// Report windows, optionally filtered by exact bundle ID.
    Windows {
        #[arg(long)]
        app: Option<String>,
    },
    /// Capture one window as a PNG without overwriting an existing file.
    Capture {
        #[arg(long = "window-id")]
        window_id: u32,
        #[arg(long)]
        output: PathBuf,
    },
    /// Report running applications.
    Apps,
    /// Report the focused app, window, and AX element.
    Focused,
    /// Query the accessibility tree.
    Tree {
        #[arg(long)]
        window: Option<String>,
        #[arg(long)]
        app: Option<String>,
        #[arg(long, default_value_t = 8)]
        depth: u32,
        #[arg(long)]
        visible_only: bool,
        #[arg(long)]
        condense_containers: bool,
    },
    /// Search accessibility elements by attribute.
    Find {
        #[arg(long)]
        role: Option<String>,
        #[arg(long)]
        label: Option<String>,
        #[arg(long = "label-contains")]
        label_contains: Option<String>,
        #[arg(long)]
        value: Option<String>,
        #[arg(long)]
        enabled: Option<bool>,
        #[arg(long)]
        focused: Option<bool>,
        #[arg(long)]
        window: Option<String>,
        #[arg(long)]
        app: Option<String>,
        #[arg(long, default_value_t = 8)]
        depth: u32,
    },
    /// Press an AX element (AXPress action).
    Press {
        #[arg(long)]
        element: String,
        #[arg(long)]
        revision: u64,
    },
    /// Set the value of an AX text field.
    SetValue {
        #[arg(long)]
        element: String,
        #[arg(long)]
        revision: u64,
        #[arg(long)]
        value: String,
    },
    /// Click an element or coordinate.
    Click {
        #[arg(long)]
        element: Option<String>,
        #[arg(long)]
        revision: Option<u64>,
        #[arg(long, allow_hyphen_values = true)]
        x: Option<f64>,
        #[arg(long, allow_hyphen_values = true)]
        y: Option<f64>,
        #[arg(long = "window-id")]
        window_id: Option<u32>,
        #[arg(long, default_value_t = 1)]
        count: u32,
    },
    /// Type text into an element or focused field.
    Type {
        #[arg(long)]
        text: String,
        #[arg(long)]
        element: Option<String>,
        #[arg(long)]
        revision: Option<u64>,
        #[arg(long = "window-id")]
        window_id: Option<u32>,
    },
    /// Press a key or chord.
    Key {
        #[arg(long)]
        chord: Option<String>,
        #[arg(long)]
        key: Option<String>,
        #[arg(long = "window-id")]
        window_id: u32,
    },
    /// Move the cursor to a coordinate.
    Move {
        #[arg(long, allow_hyphen_values = true)]
        x: f64,
        #[arg(long, allow_hyphen_values = true)]
        y: f64,
        #[arg(long = "window-id")]
        window_id: u32,
    },
    /// Scroll vertically or horizontally.
    Scroll {
        #[arg(long, allow_hyphen_values = true)]
        dx: Option<f64>,
        #[arg(long, allow_hyphen_values = true)]
        dy: Option<f64>,
        #[arg(long = "window-id")]
        window_id: u32,
    },
    /// Drag from one coordinate to another.
    Drag {
        #[arg(long, allow_hyphen_values = true)]
        from_x: f64,
        #[arg(long, allow_hyphen_values = true)]
        from_y: f64,
        #[arg(long, allow_hyphen_values = true)]
        to_x: f64,
        #[arg(long, allow_hyphen_values = true)]
        to_y: f64,
        #[arg(long)]
        duration_ms: Option<u64>,
        #[arg(long = "window-id")]
        window_id: u32,
    },
    /// Activate an application by bundle ID.
    Activate {
        #[arg(long)]
        app: String,
    },
    /// Move a window to the given coordinates.
    WindowMove {
        #[arg(long = "window-id")]
        window_id: u32,
        #[arg(long, allow_hyphen_values = true)]
        x: f64,
        #[arg(long, allow_hyphen_values = true)]
        y: f64,
    },
    /// Resize a window to the given dimensions.
    WindowResize {
        #[arg(long = "window-id")]
        window_id: u32,
        #[arg(long)]
        width: f64,
        #[arg(long)]
        height: f64,
    },
    /// Close a window.
    WindowClose {
        #[arg(long = "window-id")]
        window_id: u32,
    },
    /// Emergency stop — block all mutating actions.
    Stop {},
    /// Resume after emergency stop.
    Resume {},
    /// Print the skill markdown to stdout.
    SkillPrint {},
    /// Print the path to the skill markdown file.
    SkillPath {},
}

#[derive(Debug, Serialize)]
struct CliErrorOutput {
    ok: bool,
    error: ProtocolError,
}

fn main() {
    let json_requested = env::args().any(|argument| argument == "--json");
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) => {
            if matches!(
                error.kind(),
                ErrorKind::DisplayHelp | ErrorKind::DisplayVersion
            ) {
                error.print().expect("information output writes");
                return;
            }
            emit_error(json_requested, "invalid_input", &error.to_string(), None);
            std::process::exit(2);
        }
    };

    let exit_code = match &cli.command {
        Commands::Status => status(&cli),
        Commands::Displays => displays(&cli),
        Commands::Windows { app } => windows(&cli, app.as_deref()),
        Commands::Capture { window_id, output } => capture(&cli, *window_id, output),
        Commands::Apps => apps(&cli),
        Commands::Focused => focused(&cli),
        Commands::Tree {
            window,
            app,
            depth,
            visible_only,
            condense_containers,
        } => tree(
            &cli,
            window.as_deref(),
            app.as_deref(),
            *depth,
            *visible_only,
            *condense_containers,
        ),
        Commands::Find {
            role,
            label,
            label_contains,
            value,
            enabled,
            focused,
            window,
            app,
            depth,
        } => find(
            &cli,
            FindOptions {
                role: role.as_deref(),
                label: label.as_deref(),
                label_contains: label_contains.as_deref(),
                value: value.as_deref(),
                enabled: *enabled,
                focused: *focused,
                window: window.as_deref(),
                app: app.as_deref(),
                depth: *depth,
            },
        ),
        Commands::Press { element, revision } => press(&cli, element, *revision),
        Commands::SetValue {
            element,
            revision,
            value,
        } => set_value(&cli, element, *revision, value),
        Commands::Click {
            element,
            revision,
            x,
            y,
            window_id,
            count,
        } => click(
            &cli,
            element.as_deref(),
            *revision,
            *x,
            *y,
            *window_id,
            *count,
        ),
        Commands::Type {
            text,
            element,
            revision,
            window_id,
        } => type_text(&cli, text, element.as_deref(), *revision, *window_id),
        Commands::Key {
            chord,
            key,
            window_id,
        } => key_cmd(&cli, chord.as_deref(), key.as_deref(), *window_id),
        Commands::Move { x, y, window_id } => move_cursor(&cli, *x, *y, *window_id),
        Commands::Scroll { dx, dy, window_id } => scroll(&cli, *dx, *dy, *window_id),
        Commands::Drag {
            from_x,
            from_y,
            to_x,
            to_y,
            duration_ms,
            window_id,
        } => drag(
            &cli,
            *from_x,
            *from_y,
            *to_x,
            *to_y,
            *duration_ms,
            *window_id,
        ),
        Commands::Activate { app } => activate(&cli, app),
        Commands::WindowMove { window_id, x, y } => window_move(&cli, *window_id, *x, *y),
        Commands::WindowResize {
            window_id,
            width,
            height,
        } => window_resize(&cli, *window_id, *width, *height),
        Commands::WindowClose { window_id } => window_close(&cli, *window_id),
        Commands::Stop {} => stop(&cli),
        Commands::Resume {} => resume(&cli),
        Commands::SkillPrint {} => skill_print(&cli),
        Commands::SkillPath {} => skill_path(&cli),
    };
    if exit_code != 0 {
        std::process::exit(exit_code);
    }
}

fn status(cli: &Cli) -> i32 {
    if let Err(code) = ensure_compatible_host(cli) {
        return code;
    }
    let custom_socket = cli.socket.is_some();
    let socket_path = cli.socket.clone().unwrap_or_else(default_socket_path);
    diagnostic(
        cli.verbose,
        format!("connecting to host at {}", socket_path.display()),
    );
    let mut stream = match UnixStream::connect(&socket_path) {
        Ok(stream) => stream,
        Err(initial_error) => {
            diagnostic(
                cli.verbose,
                format!("initial host connection failed: {initial_error}"),
            );
            if cli.no_start || custom_socket {
                return unavailable(cli.json, &socket_path, initial_error);
            }
            diagnostic(cli.verbose, "launching Rebecca.app");
            if let Err(error) = launch_app() {
                return unavailable(cli.json, &socket_path, error);
            }
            match wait_for_host(
                &socket_path,
                cli.timeout.unwrap_or(START_TIMEOUT),
                cli.verbose,
            ) {
                Ok(stream) => stream,
                Err(error) => return unavailable(cli.json, &socket_path, error),
            }
        }
    };

    let io_timeout = cli.timeout.unwrap_or(IO_TIMEOUT);
    if let Err(error) = stream.set_read_timeout(Some(io_timeout)) {
        return ipc_error(cli.json, error);
    }
    if let Err(error) = stream.set_write_timeout(Some(io_timeout)) {
        return ipc_error(cli.json, error);
    }

    let request_id = Uuid::new_v4().to_string();
    let request = Request {
        protocol_version: PROTOCOL_VERSION,
        request_id: request_id.clone(),
        command: "status".into(),
        arguments: json!({}),
    };
    if let Err(error) = write_message(&mut stream, &request) {
        return ipc_error(cli.json, error);
    }

    let response_value: Value = match read_message(&mut stream) {
        Ok(response) => response,
        Err(rebecca_protocol::FrameError::Json(_)) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid status response.",
                None,
            );
            return 11;
        }
        Err(error) => return ipc_error(cli.json, error),
    };
    let response_has_error = response_value.get("error").is_some();
    let failure_forbidden_fields = ["host", "permissions", "emergency_stop"]
        .into_iter()
        .filter(|field| response_value.get(*field).is_some())
        .collect::<Vec<_>>();
    let response: StatusResponse = match serde_json::from_value(response_value) {
        Ok(response) => response,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid status response.",
                None,
            );
            return 11;
        }
    };

    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            Some(json!({"host_protocol_version": response.protocol_version})),
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match the request.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful status response without an error.",
                None,
            );
            return 11;
        };
        if !failure_forbidden_fields.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful status response with result fields.",
                Some(json!({"forbidden": failure_forbidden_fields})),
            );
            return 11;
        }
        let exit_code = exit_code_for(&error.code);
        emit_protocol_error(cli.json, error);
        return exit_code;
    }

    let missing_fields = [
        ("host", response.host.is_none()),
        ("permissions", response.permissions.is_none()),
        ("emergency_stop", response.emergency_stop.is_none()),
    ]
    .into_iter()
    .filter_map(|(field, missing)| missing.then_some(field))
    .collect::<Vec<_>>();
    if !missing_fields.is_empty() {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful status response missing required fields.",
            Some(json!({"missing": missing_fields})),
        );
        return 11;
    }

    let host = response
        .host
        .as_ref()
        .expect("status fields were validated");
    let invalid_fields = [
        ("host.running", !host.running),
        ("host.pid", host.pid == 0),
        ("error", response_has_error),
    ]
    .into_iter()
    .filter_map(|(field, invalid)| invalid.then_some(field))
    .collect::<Vec<_>>();
    if !invalid_fields.is_empty() {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful status response with invalid fields.",
            Some(json!({"invalid": invalid_fields})),
        );
        return 11;
    }

    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("status response serializes")
        );
    } else {
        let host = response
            .host
            .as_ref()
            .expect("status fields were validated");
        let permissions = response
            .permissions
            .as_ref()
            .expect("status fields were validated");
        println!(
            "host {} (pid {}): accessibility={}, screen_recording={}",
            host.version,
            host.pid,
            serde_json::to_value(permissions.accessibility).unwrap(),
            serde_json::to_value(permissions.screen_recording).unwrap(),
        );
    }
    0
}

fn displays(cli: &Cli) -> i32 {
    if let Err(code) = ensure_compatible_host(cli) {
        return code;
    }
    let custom_socket = cli.socket.is_some();
    let socket_path = cli.socket.clone().unwrap_or_else(default_socket_path);
    diagnostic(
        cli.verbose,
        format!("connecting to host at {}", socket_path.display()),
    );
    let mut stream = match UnixStream::connect(&socket_path) {
        Ok(stream) => stream,
        Err(initial_error) => {
            diagnostic(
                cli.verbose,
                format!("initial host connection failed: {initial_error}"),
            );
            if cli.no_start || custom_socket {
                return unavailable(cli.json, &socket_path, initial_error);
            }
            diagnostic(cli.verbose, "launching Rebecca.app");
            if let Err(error) = launch_app() {
                return unavailable(cli.json, &socket_path, error);
            }
            match wait_for_host(
                &socket_path,
                cli.timeout.unwrap_or(START_TIMEOUT),
                cli.verbose,
            ) {
                Ok(stream) => stream,
                Err(error) => return unavailable(cli.json, &socket_path, error),
            }
        }
    };

    let io_timeout = cli.timeout.unwrap_or(IO_TIMEOUT);
    if let Err(error) = stream.set_read_timeout(Some(io_timeout)) {
        return ipc_error(cli.json, error);
    }
    if let Err(error) = stream.set_write_timeout(Some(io_timeout)) {
        return ipc_error(cli.json, error);
    }

    let request_id = Uuid::new_v4().to_string();
    let request = Request {
        protocol_version: PROTOCOL_VERSION,
        request_id: request_id.clone(),
        command: "displays".into(),
        arguments: json!({}),
    };
    if let Err(error) = write_message(&mut stream, &request) {
        return ipc_error(cli.json, error);
    }

    let response_value: Value = match read_message(&mut stream) {
        Ok(response) => response,
        Err(rebecca_protocol::FrameError::Json(_)) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid displays response.",
                None,
            );
            return 11;
        }
        Err(error) => return ipc_error(cli.json, error),
    };
    let response_has_error = response_value.get("error").is_some();
    let failure_forbidden_fields = ["revision", "displays"]
        .into_iter()
        .filter(|field| response_value.get(*field).is_some())
        .collect::<Vec<_>>();
    let response: DisplaysResponse = match serde_json::from_value(response_value) {
        Ok(response) => response,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid displays response.",
                None,
            );
            return 11;
        }
    };

    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            Some(json!({"host_protocol_version": response.protocol_version})),
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match the request.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful displays response without an error.",
                None,
            );
            return 11;
        };
        if !failure_forbidden_fields.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful displays response with result fields.",
                Some(json!({"forbidden": failure_forbidden_fields})),
            );
            return 11;
        }
        let exit_code = exit_code_for(&error.code);
        emit_protocol_error(cli.json, error);
        return exit_code;
    }

    let missing_fields = [
        ("revision", response.revision.is_none()),
        ("displays", response.displays.is_none()),
    ]
    .into_iter()
    .filter_map(|(field, missing)| missing.then_some(field))
    .collect::<Vec<_>>();
    if !missing_fields.is_empty() || response_has_error {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful displays response with invalid fields.",
            Some(json!({"missing": missing_fields})),
        );
        return 11;
    }

    let revision = response.revision.expect("displays fields were validated");
    let displays = response
        .displays
        .as_ref()
        .expect("displays fields were validated");
    if revision == 0 {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a displays response with an invalid revision.",
            None,
        );
        return 11;
    }
    if let Some((index, field)) = invalid_display_field(displays) {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a displays response with invalid display metadata.",
            Some(json!({"display_index": index, "field": field})),
        );
        return 11;
    }

    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("displays response serializes")
        );
    } else {
        println!("revision {revision}: {} display(s)", displays.len());
        for display in displays {
            println!(
                "display {}: frame=({}, {}, {}, {}), pixels={}x{}, scale={}, primary={}",
                display.display_id,
                display.logical_frame.x,
                display.logical_frame.y,
                display.logical_frame.width,
                display.logical_frame.height,
                display.pixel_size.width,
                display.pixel_size.height,
                display.scale_factor,
                display.primary,
            );
        }
    }
    0
}

fn invalid_display_field(displays: &[DisplayInfo]) -> Option<(usize, &'static str)> {
    displays.iter().enumerate().find_map(|(index, display)| {
        let frame = &display.logical_frame;
        let pixels = &display.pixel_size;
        if display.display_id == 0 {
            return Some((index, "display_id"));
        }
        if !frame.x.is_finite()
            || !frame.y.is_finite()
            || !frame.width.is_finite()
            || frame.width <= 0.0
            || !frame.height.is_finite()
            || frame.height <= 0.0
        {
            return Some((index, "logical_frame"));
        }
        if pixels.width == 0 || pixels.height == 0 {
            return Some((index, "pixel_size"));
        }
        if !display.scale_factor.is_finite() || display.scale_factor <= 0.0 {
            return Some((index, "scale_factor"));
        }
        None
    })
}

fn windows(cli: &Cli, app: Option<&str>) -> i32 {
    let arguments = match app {
        Some(value) if !value.is_empty() => json!({"app": value}),
        Some(_) => {
            emit_error(
                cli.json,
                "invalid_input",
                "app must be a non-empty bundle identifier.",
                None,
            );
            return 2;
        }
        None => json!({}),
    };
    let (request_id, response_value) = match request_value(cli, "windows", arguments) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let response_has_error = response_value.get("error").is_some();
    let failure_forbidden_fields = ["revision", "windows"]
        .into_iter()
        .filter(|field| response_value.get(*field).is_some())
        .collect::<Vec<_>>();
    let response: WindowsResponse = match serde_json::from_value(response_value) {
        Ok(response) => response,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid windows response.",
                None,
            );
            return 11;
        }
    };
    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            None,
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match the request.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful windows response without an error.",
                None,
            );
            return 11;
        };
        if !failure_forbidden_fields.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful windows response with result fields.",
                None,
            );
            return 11;
        }
        emit_protocol_error(cli.json, error.clone());
        return exit_code_for(&error.code);
    }
    let Some(revision) = response.revision else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful windows response without revision.",
            None,
        );
        return 11;
    };
    let Some(windows) = response.windows.as_ref() else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful windows response without windows.",
            None,
        );
        return 11;
    };
    if revision == 0 || response_has_error {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful windows response with invalid fields.",
            None,
        );
        return 11;
    }
    if let Some((index, field)) = invalid_window_field(windows) {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned invalid window metadata.",
            Some(json!({"window_index": index, "field": field})),
        );
        return 11;
    }
    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("windows response serializes")
        );
    } else {
        println!("revision {revision}: {} window(s)", windows.len());
        for window in windows {
            println!(
                "window {}: pid={:?}, bundle={:?}, title={:?}, frame=({}, {}, {}, {}), onscreen={}, minimized={:?}, focused={:?}, display={:?}",
                window.window_id,
                window.owner_pid,
                window.bundle_id,
                window.title,
                window.logical_frame.x,
                window.logical_frame.y,
                window.logical_frame.width,
                window.logical_frame.height,
                window.onscreen,
                window.minimized,
                window.focused,
                window.display_id,
            );
        }
    }
    0
}

fn capture(cli: &Cli, window_id: u32, output: &PathBuf) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "invalid_input",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let output = match normalize_output_path(output) {
        Ok(path) => path,
        Err(message) => {
            emit_error(cli.json, "invalid_input", &message, None);
            return 2;
        }
    };
    let output_string = output.to_string_lossy().into_owned();
    let arguments = json!({"window_id": window_id, "output": output_string});
    let (request_id, response_value) = match request_value(cli, "capture", arguments) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let response_has_error = response_value.get("error").is_some();
    let forbidden_fields = [
        "path",
        "target",
        "pixel_size",
        "logical_frame",
        "scale_factor",
        "revision",
    ]
    .into_iter()
    .filter(|field| response_value.get(*field).is_some())
    .collect::<Vec<_>>();
    let response: CaptureResponse = match serde_json::from_value(response_value) {
        Ok(response) => response,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid capture response.",
                None,
            );
            return 11;
        }
    };
    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            None,
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match the request.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful capture response without an error.",
                None,
            );
            return 11;
        };
        if !forbidden_fields.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful capture response with result fields.",
                None,
            );
            return 11;
        }
        emit_protocol_error(cli.json, error.clone());
        return exit_code_for(&error.code);
    }
    if response_has_error {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful capture response with an error field.",
            None,
        );
        return 11;
    }
    let (
        Some(path),
        Some(target),
        Some(pixel_size),
        Some(logical_frame),
        Some(scale_factor),
        Some(revision),
    ) = (
        response.path.as_ref(),
        response.target.as_ref(),
        response.pixel_size.as_ref(),
        response.logical_frame.as_ref(),
        response.scale_factor,
        response.revision,
    )
    else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an incomplete capture response.",
            None,
        );
        return 11;
    };
    if path != &output_string
        || target.target_type != "window"
        || target.id != window_id
        || pixel_size.width == 0
        || pixel_size.height == 0
        || !logical_frame.x.is_finite()
        || !logical_frame.y.is_finite()
        || !logical_frame.width.is_finite()
        || logical_frame.width <= 0.0
        || !logical_frame.height.is_finite()
        || logical_frame.height <= 0.0
        || !scale_factor.is_finite()
        || scale_factor <= 0.0
        || revision == 0
    {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned invalid capture metadata.",
            None,
        );
        return 11;
    }
    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("capture response serializes")
        );
    } else {
        println!(
            "captured window {window_id} to {path} ({}, {} pixels)",
            pixel_size.width, pixel_size.height
        );
    }
    0
}

fn request_value(cli: &Cli, command: &str, arguments: Value) -> Result<(String, Value), i32> {
    ensure_compatible_host(cli)?;
    let custom_socket = cli.socket.is_some();
    let socket_path = cli.socket.clone().unwrap_or_else(default_socket_path);
    let mut stream = match UnixStream::connect(&socket_path) {
        Ok(stream) => stream,
        Err(initial_error) => {
            if cli.no_start || custom_socket {
                return Err(unavailable(cli.json, &socket_path, initial_error));
            }
            if let Err(error) = launch_app() {
                return Err(unavailable(cli.json, &socket_path, error));
            }
            match wait_for_host(
                &socket_path,
                cli.timeout.unwrap_or(START_TIMEOUT),
                cli.verbose,
            ) {
                Ok(stream) => stream,
                Err(error) => return Err(unavailable(cli.json, &socket_path, error)),
            }
        }
    };
    let io_timeout = cli.timeout.unwrap_or(IO_TIMEOUT);
    if let Err(error) = stream.set_read_timeout(Some(io_timeout)) {
        return Err(ipc_error(cli.json, error));
    }
    if let Err(error) = stream.set_write_timeout(Some(io_timeout)) {
        return Err(ipc_error(cli.json, error));
    }
    let request_id = Uuid::new_v4().to_string();
    let request = Request {
        protocol_version: PROTOCOL_VERSION,
        request_id: request_id.clone(),
        command: command.into(),
        arguments,
    };
    if let Err(error) = write_message(&mut stream, &request) {
        return Err(ipc_error(cli.json, error));
    }
    let value = match read_message(&mut stream) {
        Ok(value) => value,
        Err(rebecca_protocol::FrameError::Json(_)) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned invalid JSON.",
                None,
            );
            return Err(11);
        }
        Err(rebecca_protocol::FrameError::Io(error))
            if matches!(
                error.kind(),
                io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock
            ) =>
        {
            emit_error(
                cli.json,
                "timeout",
                "Timed out waiting for the host response.",
                None,
            );
            return Err(8);
        }
        Err(error) => return Err(ipc_error(cli.json, error)),
    };
    Ok((request_id, value))
}

fn normalize_output_path(path: &PathBuf) -> Result<PathBuf, String> {
    if path
        .extension()
        .and_then(|extension| extension.to_str())
        .is_none_or(|extension| !extension.eq_ignore_ascii_case("png"))
    {
        return Err("output path must end in .png.".into());
    }
    if path.is_absolute() {
        Ok(path.clone())
    } else {
        Ok(env::current_dir()
            .map_err(|error| format!("unable to resolve output path: {error}"))?
            .join(path))
    }
}

fn invalid_window_field(windows: &[WindowInfo]) -> Option<(usize, &'static str)> {
    windows.iter().enumerate().find_map(|(index, window)| {
        let frame = &window.logical_frame;
        if window.window_id == 0 {
            return Some((index, "window_id"));
        }
        if !frame.x.is_finite()
            || !frame.y.is_finite()
            || !frame.width.is_finite()
            || frame.width <= 0.0
            || !frame.height.is_finite()
            || frame.height <= 0.0
        {
            return Some((index, "logical_frame"));
        }
        if window.display_id == Some(0) {
            return Some((index, "display_id"));
        }
        if window.onscreen && window.minimized == Some(true) {
            return Some((index, "onscreen_minimized"));
        }
        None
    })
}

fn apps(cli: &Cli) -> i32 {
    let (request_id, response_value) = match request_value(cli, "apps", json!({})) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let response_has_error = response_value.get("error").is_some();
    let failure_forbidden_fields = ["revision", "apps"]
        .into_iter()
        .filter(|field| response_value.get(*field).is_some())
        .collect::<Vec<_>>();
    let response: AppsResponse = match serde_json::from_value(response_value) {
        Ok(response) => response,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid apps response.",
                None,
            );
            return 11;
        }
    };
    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            None,
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match the request.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful apps response without an error.",
                None,
            );
            return 11;
        };
        if !failure_forbidden_fields.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful apps response with result fields.",
                None,
            );
            return 11;
        }
        emit_protocol_error(cli.json, error.clone());
        return exit_code_for(&error.code);
    }
    let Some(revision) = response.revision else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful apps response without revision.",
            None,
        );
        return 11;
    };
    let Some(apps) = response.apps.as_ref() else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful apps response without apps.",
            None,
        );
        return 11;
    };
    if revision == 0 || response_has_error {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful apps response with invalid fields.",
            None,
        );
        return 11;
    }
    for app in apps {
        if app.pid == 0 {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned invalid app metadata.",
                Some(json!({"field": "pid"})),
            );
            return 11;
        }
    }
    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("apps response serializes")
        );
    } else {
        println!("revision {revision}: {} app(s)", apps.len());
        for app in apps {
            println!(
                "app {} (pid={}): bundle={:?}, name={:?}, active={}, hidden={}",
                app.pid, app.pid, app.bundle_id, app.name, app.active, app.hidden
            );
        }
    }
    0
}

fn focused(cli: &Cli) -> i32 {
    let (request_id, response_value) = match request_value(cli, "focused", json!({})) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let response_has_error = response_value.get("error").is_some();
    let forbidden_fields = [
        "active_app",
        "focused_window",
        "focused_element",
        "revision",
    ]
    .into_iter()
    .filter(|field| response_value.get(*field).is_some())
    .collect::<Vec<_>>();
    let response: FocusedResponse = match serde_json::from_value(response_value) {
        Ok(response) => response,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid focused response.",
                None,
            );
            return 11;
        }
    };
    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            None,
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match the request.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful focused response without an error.",
                None,
            );
            return 11;
        };
        if !forbidden_fields.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful focused response with result fields.",
                None,
            );
            return 11;
        }
        emit_protocol_error(cli.json, error.clone());
        return exit_code_for(&error.code);
    }
    let Some(revision) = response.revision else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful focused response without revision.",
            None,
        );
        return 11;
    };
    if revision == 0 || response_has_error {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful focused response with invalid fields.",
            None,
        );
        return 11;
    }
    let Some(active_app) = response.active_app.as_ref() else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a successful focused response without active_app.",
            None,
        );
        return 11;
    };
    if active_app.pid == 0 {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned invalid active_app metadata.",
            None,
        );
        return 11;
    }
    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("focused response serializes")
        );
    } else {
        println!(
            "revision {revision}: active app {} (pid={}), bundle={:?}, name={:?}",
            active_app.pid, active_app.pid, active_app.bundle_id, active_app.name
        );
    }
    0
}

fn tree(
    cli: &Cli,
    window: Option<&str>,
    app: Option<&str>,
    depth: u32,
    visible_only: bool,
    condense_containers: bool,
) -> i32 {
    let (window_arg, app_arg) = match (window, app) {
        (Some(w), None) => (Some(w.to_string()), None),
        (None, Some(a)) => (None, Some(a.to_string())),
        (Some(_), Some(_)) => {
            emit_error(
                cli.json,
                "invalid_input",
                "Specify only one of --window or --app.",
                None,
            );
            return 2;
        }
        (None, None) => {
            emit_error(
                cli.json,
                "invalid_input",
                "Specify --window or --app.",
                None,
            );
            return 2;
        }
    };
    let mut arguments = json!({
        "depth": depth,
        "visible_only": visible_only,
        "condense_containers": condense_containers,
    });
    if let Some(w) = &window_arg {
        arguments["window"] = json!(w);
    }
    if let Some(a) = &app_arg {
        arguments["app"] = json!(a);
    }
    let (request_id, response_value) = match request_value(cli, "tree", arguments) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let response_has_error = response_value.get("error").is_some();
    let forbidden = ["revision", "root", "truncated"]
        .into_iter()
        .filter(|f| response_value.get(*f).is_some())
        .collect::<Vec<_>>();
    let response: TreeResponse = match serde_json::from_value(response_value) {
        Ok(r) => r,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid tree response.",
                None,
            );
            return 11;
        }
    };
    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            None,
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful tree response without an error.",
                None,
            );
            return 11;
        };
        if !forbidden.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful tree response with result fields.",
                None,
            );
            return 11;
        }
        emit_protocol_error(cli.json, error.clone());
        return exit_code_for(&error.code);
    }
    let Some(revision) = response.revision else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a tree response without revision.",
            None,
        );
        return 11;
    };
    let Some(root) = response.root.as_ref() else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a tree response without root.",
            None,
        );
        return 11;
    };
    if revision == 0 || response_has_error {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a tree response with invalid fields.",
            None,
        );
        return 11;
    }
    if root.id.is_empty() || root.role.is_empty() {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned invalid tree root metadata.",
            None,
        );
        return 11;
    }
    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("tree response serializes")
        );
    } else {
        let truncated = response.truncated.unwrap_or(false);
        println!(
            "revision {revision}: root={} role={} (truncated={})",
            root.id, root.role, truncated
        );
    }
    0
}

struct FindOptions<'a> {
    role: Option<&'a str>,
    label: Option<&'a str>,
    label_contains: Option<&'a str>,
    value: Option<&'a str>,
    enabled: Option<bool>,
    focused: Option<bool>,
    window: Option<&'a str>,
    app: Option<&'a str>,
    depth: u32,
}

fn find(cli: &Cli, options: FindOptions<'_>) -> i32 {
    let FindOptions {
        role,
        label,
        label_contains,
        value,
        enabled,
        focused,
        window,
        app,
        depth,
    } = options;
    let (window_arg, app_arg) = match (window, app) {
        (Some(w), None) => (Some(w.to_string()), None),
        (None, Some(a)) => (None, Some(a.to_string())),
        (Some(_), Some(_)) => {
            emit_error(
                cli.json,
                "invalid_input",
                "Specify only one of --window or --app.",
                None,
            );
            return 2;
        }
        (None, None) => {
            emit_error(
                cli.json,
                "invalid_input",
                "Specify --window or --app.",
                None,
            );
            return 2;
        }
    };
    let mut arguments = json!({"depth": depth});
    if let Some(w) = &window_arg {
        arguments["window"] = json!(w);
    }
    if let Some(a) = &app_arg {
        arguments["app"] = json!(a);
    }
    if let Some(v) = role {
        arguments["role"] = json!(v);
    }
    if let Some(v) = label {
        arguments["label"] = json!(v);
    }
    if let Some(v) = label_contains {
        arguments["label_contains"] = json!(v);
    }
    if let Some(v) = value {
        arguments["value"] = json!(v);
    }
    if let Some(v) = enabled {
        arguments["enabled"] = json!(v);
    }
    if let Some(v) = focused {
        arguments["focused"] = json!(v);
    }
    let (request_id, response_value) = match request_value(cli, "find", arguments) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let response_has_error = response_value.get("error").is_some();
    let forbidden = ["revision", "results", "truncated"]
        .into_iter()
        .filter(|f| response_value.get(*f).is_some())
        .collect::<Vec<_>>();
    let response: rebecca_protocol::FindResponse = match serde_json::from_value(response_value) {
        Ok(r) => r,
        Err(_) => {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an invalid find response.",
                None,
            );
            return 11;
        }
    };
    if response.protocol_version != PROTOCOL_VERSION {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            None,
        );
        return 11;
    }
    if response.request_id != request_id {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match.",
            None,
        );
        return 11;
    }
    if !response.ok {
        let Some(error) = response.error else {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful find response without an error.",
                None,
            );
            return 11;
        };
        if !forbidden.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful find response with result fields.",
                None,
            );
            return 11;
        }
        emit_protocol_error(cli.json, error.clone());
        return exit_code_for(&error.code);
    }
    let Some(revision) = response.revision else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a find response without revision.",
            None,
        );
        return 11;
    };
    let Some(results) = response.results.as_ref() else {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a find response without results.",
            None,
        );
        return 11;
    };
    if revision == 0 || response_has_error {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned a find response with invalid fields.",
            None,
        );
        return 11;
    }
    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response).expect("find response serializes")
        );
    } else {
        println!("revision {revision}: {} result(s)", results.len());
        for r in results {
            println!(
                "  {} role={} label={:?} enabled={}",
                r.id, r.role, r.label, r.enabled
            );
        }
    }
    0
}

fn press(cli: &Cli, element: &str, revision: u64) -> i32 {
    if element.is_empty() {
        emit_error(
            cli.json,
            "invalid_input",
            "element must not be empty.",
            None,
        );
        return 2;
    }
    if revision == 0 {
        emit_error(
            cli.json,
            "invalid_input",
            "revision must be greater than zero.",
            None,
        );
        return 2;
    }
    let arguments = json!({"element": element, "revision": revision});
    let (request_id, response_value) = match request_value(cli, "press", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "press")
}

fn set_value(cli: &Cli, element: &str, revision: u64, value: &str) -> i32 {
    if element.is_empty() {
        emit_error(
            cli.json,
            "invalid_input",
            "element must not be empty.",
            None,
        );
        return 2;
    }
    if revision == 0 {
        emit_error(
            cli.json,
            "invalid_input",
            "revision must be greater than zero.",
            None,
        );
        return 2;
    }
    let arguments = json!({"element": element, "revision": revision, "value": value});
    let (request_id, response_value) = match request_value(cli, "set_value", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "set_value")
}

fn handle_action_response(
    cli: &Cli,
    request_id: &str,
    response_value: Value,
    action_name: &str,
) -> i32 {
    let response_has_error = response_value.get("error").is_some();
    let forbidden = [
        "action",
        "executed",
        "method",
        "before_revision",
        "after_revision",
    ]
    .into_iter()
    .filter(|f| response_value.get(*f).is_some())
    .collect::<Vec<_>>();

    if !response_value.get("ok").is_none_or(|v| v == true) {
        let error = response_value.get("error");
        if error.is_none() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful action response without an error.",
                None,
            );
            return 11;
        }
        if !forbidden.is_empty() {
            emit_error(
                cli.json,
                "protocol_mismatch",
                "Host returned an unsuccessful action response with result fields.",
                None,
            );
            return 11;
        }
        let error = error.unwrap();
        let code = error
            .get("code")
            .and_then(|c| c.as_str())
            .unwrap_or("internal_error");
        let message = error
            .get("message")
            .and_then(|m| m.as_str())
            .unwrap_or("Unknown error");
        let exit_code = exit_code_for(code);
        let protocol_error = ProtocolError {
            code: code.to_string(),
            message: message.to_string(),
            details: error.get("details").cloned(),
        };
        emit_protocol_error(cli.json, protocol_error);
        return exit_code;
    }

    let action = response_value.get("action").and_then(|v| v.as_str());
    let executed = response_value.get("executed").and_then(|v| v.as_bool());
    let method = response_value.get("method").and_then(|v| v.as_str());
    let before_rev = response_value
        .get("before_revision")
        .and_then(|v| v.as_u64());
    let after_rev = response_value
        .get("after_revision")
        .and_then(|v| v.as_u64());

    if response_has_error
        || action.is_none()
        || executed.is_none()
        || method.is_none()
        || before_rev.is_none()
        || after_rev.is_none()
    {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an incomplete action response.",
            None,
        );
        return 11;
    }

    let resp_request_id = response_value.get("request_id").and_then(|v| v.as_str());
    if resp_request_id != Some(request_id) {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host response request_id does not match.",
            None,
        );
        return 11;
    }

    let protocol_version = response_value
        .get("protocol_version")
        .and_then(|v| v.as_u64());
    if protocol_version != Some(PROTOCOL_VERSION as u64) {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unsupported protocol version.",
            None,
        );
        return 11;
    }

    if action != Some(action_name) {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned an unexpected action name.",
            None,
        );
        return 11;
    }

    if !executed.unwrap_or(false) {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host reported the action was not executed.",
            None,
        );
        return 11;
    }

    if after_rev <= before_rev {
        emit_error(
            cli.json,
            "protocol_mismatch",
            "Host returned non-increasing revision.",
            None,
        );
        return 11;
    }

    if cli.json {
        println!(
            "{}",
            serde_json::to_string(&response_value).expect("action response serializes")
        );
    } else {
        println!(
            "{}: method={} revision {}->{}",
            action.unwrap(),
            method.unwrap(),
            before_rev.unwrap(),
            after_rev.unwrap()
        );
    }
    0
}

fn click(
    cli: &Cli,
    element: Option<&str>,
    revision: Option<u64>,
    x: Option<f64>,
    y: Option<f64>,
    window_id: Option<u32>,
    count: u32,
) -> i32 {
    let mut arguments = json!({"count": count});
    if let Some(e) = element {
        if let Some(r) = revision {
            arguments["element"] = json!(e);
            arguments["revision"] = json!(r);
        } else {
            emit_error(
                cli.json,
                "invalid_input",
                "revision is required with element.",
                None,
            );
            return 2;
        }
    } else if let (Some(x), Some(y)) = (x, y) {
        let Some(window_id) = window_id.filter(|window_id| *window_id > 0) else {
            emit_error(
                cli.json,
                "target_window_required",
                "window-id is required with coordinate input.",
                None,
            );
            return 2;
        };
        arguments["x"] = json!(x);
        arguments["y"] = json!(y);
        arguments["window_id"] = json!(window_id);
    } else {
        emit_error(
            cli.json,
            "invalid_input",
            "click requires element+revision or x+y.",
            None,
        );
        return 2;
    }
    let (request_id, response_value) = match request_value(cli, "click", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "click")
}

fn type_text(
    cli: &Cli,
    text: &str,
    element: Option<&str>,
    revision: Option<u64>,
    window_id: Option<u32>,
) -> i32 {
    if text.is_empty() {
        emit_error(cli.json, "invalid_input", "text must not be empty.", None);
        return 2;
    }
    let mut arguments = json!({"text": text});
    if let Some(e) = element {
        if let Some(r) = revision {
            arguments["element"] = json!(e);
            arguments["revision"] = json!(r);
        } else {
            emit_error(
                cli.json,
                "invalid_input",
                "revision is required with element.",
                None,
            );
            return 2;
        }
    } else {
        let Some(window_id) = window_id.filter(|window_id| *window_id > 0) else {
            emit_error(
                cli.json,
                "target_window_required",
                "window-id is required without element.",
                None,
            );
            return 2;
        };
        arguments["window_id"] = json!(window_id);
    }
    let (request_id, response_value) = match request_value(cli, "type", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "type")
}

fn key_cmd(cli: &Cli, chord: Option<&str>, key: Option<&str>, window_id: u32) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "target_window_required",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let mut arguments = json!({"window_id": window_id});
    if let Some(c) = chord {
        arguments["chord"] = json!(c);
    } else if let Some(k) = key {
        arguments["key"] = json!(k);
    } else {
        emit_error(
            cli.json,
            "invalid_input",
            "key requires chord or key.",
            None,
        );
        return 2;
    }
    let (request_id, response_value) = match request_value(cli, "key", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "key")
}

fn move_cursor(cli: &Cli, x: f64, y: f64, window_id: u32) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "target_window_required",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let arguments = json!({"x": x, "y": y, "window_id": window_id});
    let (request_id, response_value) = match request_value(cli, "move", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "move")
}

fn scroll(cli: &Cli, dx: Option<f64>, dy: Option<f64>, window_id: u32) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "target_window_required",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let mut arguments = json!({"window_id": window_id});
    if let Some(dx) = dx {
        arguments["dx"] = json!(dx);
    }
    if let Some(dy) = dy {
        arguments["dy"] = json!(dy);
    }
    if dx.is_none() && dy.is_none() {
        emit_error(cli.json, "invalid_input", "scroll requires dx or dy.", None);
        return 2;
    }
    let (request_id, response_value) = match request_value(cli, "scroll", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "scroll")
}

fn drag(
    cli: &Cli,
    from_x: f64,
    from_y: f64,
    to_x: f64,
    to_y: f64,
    duration_ms: Option<u64>,
    window_id: u32,
) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "target_window_required",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let mut arguments = json!({
        "window_id": window_id,
        "from_x": from_x,
        "from_y": from_y,
        "to_x": to_x,
        "to_y": to_y,
    });
    if let Some(d) = duration_ms {
        arguments["duration_ms"] = json!(d);
    }
    let (request_id, response_value) = match request_value(cli, "drag", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "drag")
}

fn activate(cli: &Cli, app: &str) -> i32 {
    if app.is_empty() {
        emit_error(cli.json, "invalid_input", "app must not be empty.", None);
        return 2;
    }
    let arguments = json!({"app": app});
    let (request_id, response_value) = match request_value(cli, "activate", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "activate")
}

fn window_move(cli: &Cli, window_id: u32, x: f64, y: f64) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "invalid_input",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let arguments = json!({"window_id": window_id, "x": x, "y": y});
    let (request_id, response_value) = match request_value(cli, "window_move", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "window_move")
}

fn window_resize(cli: &Cli, window_id: u32, width: f64, height: f64) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "invalid_input",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let arguments = json!({"window_id": window_id, "width": width, "height": height});
    let (request_id, response_value) = match request_value(cli, "window_resize", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "window_resize")
}

fn window_close(cli: &Cli, window_id: u32) -> i32 {
    if window_id == 0 {
        emit_error(
            cli.json,
            "invalid_input",
            "window-id must be greater than zero.",
            None,
        );
        return 2;
    }
    let arguments = json!({"window_id": window_id});
    let (request_id, response_value) = match request_value(cli, "window_close", arguments) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "window_close")
}

fn stop(cli: &Cli) -> i32 {
    let (request_id, response_value) = match request_value(cli, "stop", json!({})) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "stop")
}

fn resume(cli: &Cli) -> i32 {
    let (request_id, response_value) = match request_value(cli, "resume", json!({})) {
        Ok(v) => v,
        Err(code) => return code,
    };
    handle_action_response(cli, &request_id, response_value, "resume")
}

fn skill_print(cli: &Cli) -> i32 {
    let content = skill_content();
    if cli.json {
        print!("{}", serde_json::to_string(&content).unwrap_or_default());
        println!();
    } else {
        print!("{}", content);
    }
    0
}

fn skill_path(cli: &Cli) -> i32 {
    let path = skill_file_path();
    if cli.json {
        print!("{}", serde_json::to_string(&path).unwrap_or_default());
        println!();
    } else {
        println!("{}", path);
    }
    0
}

fn skill_file_path() -> String {
    // Check bundle Resources first, then repo resources/
    let bundle_path = "/Applications/Rebecca.app/Contents/Resources/SKILL.md";
    if std::path::Path::new(bundle_path).exists() {
        return bundle_path.to_string();
    }
    let env_path = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|p| p.join("../../../Resources/SKILL.md")))
        .map(|p| p.to_string_lossy().to_string());
    if let Some(p) = env_path {
        if std::path::Path::new(&p).exists() {
            return p;
        }
    }
    "SKILL.md".to_string()
}

fn skill_content() -> String {
    let path = skill_file_path();
    std::fs::read_to_string(&path)
        .unwrap_or_else(|_| include_str!("../../../resources/SKILL.md").to_string())
}

const DEFAULT_APP_PATH: &str = "/Applications/Rebecca.app";
const REBECCA_BUNDLE_ID: &str = "dev.jwoo0122.rebecca";

fn installed_app_path() -> PathBuf {
    env::var_os("REBECCA_APP_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_APP_PATH))
}

fn expected_host_executable() -> PathBuf {
    let app_path = installed_app_path();
    let executable = Command::new("/usr/bin/plutil")
        .args(["-extract", "CFBundleExecutable", "raw", "-o", "-"])
        .arg(app_path.join("Contents/Info.plist"))
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "Rebecca".to_string());
    app_path.join("Contents/MacOS").join(executable)
}

fn installed_app_version() -> Option<String> {
    let output = Command::new("/usr/bin/plutil")
        .args(["-extract", "CFBundleShortVersionString", "raw", "-o", "-"])
        .arg(installed_app_path().join("Contents/Info.plist"))
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let version = String::from_utf8(output.stdout).ok()?.trim().to_string();
    (!version.is_empty()).then_some(version)
}

fn host_matches_installation(host: &rebecca_protocol::HostStatus) -> bool {
    host.running
        && host.pid > 0
        && host.bundle_id.as_deref() == Some(REBECCA_BUNDLE_ID)
        && host.executable_path.as_deref()
            == Some(expected_host_executable().to_string_lossy().as_ref())
        && installed_app_version()
            .as_deref()
            .is_none_or(|version| host.version == version)
}

fn probe_host(
    stream: &mut UnixStream,
    timeout: Duration,
) -> io::Result<rebecca_protocol::HostStatus> {
    stream.set_read_timeout(Some(timeout))?;
    stream.set_write_timeout(Some(timeout))?;
    let request_id = Uuid::new_v4().to_string();
    let request = Request {
        protocol_version: PROTOCOL_VERSION,
        request_id,
        command: "status".into(),
        arguments: json!({}),
    };
    write_message(stream, &request)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    let value: Value = read_message(stream)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    let response: StatusResponse = serde_json::from_value(value)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    if response.protocol_version != PROTOCOL_VERSION || !response.ok {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "host status handshake was rejected",
        ));
    }
    response.host.ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            "host status handshake omitted host metadata",
        )
    })
}

fn wait_for_socket_closed(path: &Path, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    loop {
        if UnixStream::connect(path).is_err() {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        thread::sleep(Duration::from_millis(50));
    }
}

fn terminate_host(pid: u32, path: &Path, timeout: Duration, verbose: bool) -> bool {
    diagnostic(
        verbose,
        format!("restarting incompatible Rebecca host pid {pid}"),
    );
    let pid = pid.to_string();
    let terminated = Command::new("/bin/kill")
        .args(["-TERM", &pid])
        .status()
        .map(|status| status.success())
        .unwrap_or(false);
    if !terminated || wait_for_socket_closed(path, timeout) {
        return terminated;
    }

    let _ = Command::new("/bin/kill").args(["-KILL", &pid]).status();
    wait_for_socket_closed(path, timeout)
}

fn ensure_compatible_host(cli: &Cli) -> Result<(), i32> {
    if cli.socket.is_some() {
        return Ok(());
    }

    let socket_path = cli.socket.clone().unwrap_or_else(default_socket_path);
    let timeout = cli.timeout.unwrap_or(START_TIMEOUT);
    for attempt in 0..2 {
        let stream = match UnixStream::connect(&socket_path) {
            Ok(stream) => stream,
            Err(error) => {
                if cli.no_start {
                    return Err(unavailable(cli.json, &socket_path, error));
                }
                launch_app().map_err(|error| unavailable(cli.json, &socket_path, error))?;
                wait_for_host(&socket_path, timeout, cli.verbose)
                    .map_err(|error| unavailable(cli.json, &socket_path, error))?;
                continue;
            }
        };

        let mut stream = stream;
        match probe_host(&mut stream, cli.timeout.unwrap_or(IO_TIMEOUT)) {
            Ok(host) if host_matches_installation(&host) => return Ok(()),
            Ok(host) => {
                diagnostic(
                    cli.verbose,
                    format!(
                        "host mismatch: pid={}, version={}, bundle_id={:?}, executable_path={:?}",
                        host.pid, host.version, host.bundle_id, host.executable_path
                    ),
                );
                if cli.no_start || !terminate_host(host.pid, &socket_path, timeout, cli.verbose) {
                    emit_error(
                        cli.json,
                        "protocol_mismatch",
                        "A different Rebecca host is already running.",
                        Some(json!({"host_pid": host.pid})),
                    );
                    return Err(11);
                }
            }
            Err(error) => {
                if cli.no_start || attempt == 1 {
                    return Err(unavailable(cli.json, &socket_path, error));
                }
                let _ = wait_for_socket_closed(&socket_path, timeout);
            }
        }

        if attempt == 1 {
            break;
        }
        launch_app().map_err(|error| unavailable(cli.json, &socket_path, error))?;
        wait_for_host(&socket_path, timeout, cli.verbose)
            .map_err(|error| unavailable(cli.json, &socket_path, error))?;
    }

    Err(unavailable(
        cli.json,
        &socket_path,
        "compatible Rebecca host did not start",
    ))
}

fn parse_duration(value: &str) -> Result<Duration, String> {
    let (amount, unit) = value
        .strip_suffix("ms")
        .map(|amount| (amount, "ms"))
        .or_else(|| value.strip_suffix('s').map(|amount| (amount, "s")))
        .ok_or_else(|| "timeout must be a positive integer with an `ms` or `s` suffix (for example, `250ms` or `2s`)".to_string())?;
    let amount = amount.parse::<u64>().map_err(|_| {
        "timeout must be a positive integer with an `ms` or `s` suffix (for example, `250ms` or `2s`)"
            .to_string()
    })?;
    if amount == 0 {
        return Err("timeout must be greater than zero".to_string());
    }
    Ok(match unit {
        "ms" => Duration::from_millis(amount),
        "s" => Duration::from_secs(amount),
        _ => unreachable!("duration suffix was validated"),
    })
}

fn diagnostic(verbose: bool, message: impl std::fmt::Display) {
    if verbose {
        eprintln!("diagnostic: {message}");
    }
}

fn default_socket_path() -> PathBuf {
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"));
    home.join("Library/Application Support/Rebecca/runtime/control.sock")
}

fn launch_app() -> io::Result<()> {
    let status = Command::new("open").arg(installed_app_path()).status()?;
    if status.success() {
        Ok(())
    } else {
        Err(io::Error::other("open -a Rebecca failed"))
    }
}

fn wait_for_host(path: &PathBuf, timeout: Duration, verbose: bool) -> io::Result<UnixStream> {
    let deadline = Instant::now() + timeout;
    loop {
        match UnixStream::connect(path) {
            Ok(stream) => return Ok(stream),
            Err(error) if Instant::now() >= deadline => return Err(error),
            Err(error) => {
                diagnostic(verbose, format!("waiting for host: {error}"));
                thread::sleep(
                    deadline
                        .saturating_duration_since(Instant::now())
                        .min(Duration::from_millis(50)),
                );
            }
        }
    }
}

fn unavailable(json_output: bool, socket: &Path, error: impl std::fmt::Display) -> i32 {
    emit_error(
        json_output,
        "host_unavailable",
        &format!(
            "Rebecca host is unavailable at {}: {error}",
            socket.display()
        ),
        None,
    );
    3
}

fn ipc_error(json_output: bool, error: impl std::fmt::Display) -> i32 {
    emit_error(json_output, "ipc_error", &error.to_string(), None);
    4
}

fn emit_protocol_error(json_output: bool, error: ProtocolError) {
    if json_output {
        println!(
            "{}",
            serde_json::to_string(&CliErrorOutput { ok: false, error }).expect("error serializes")
        );
    } else {
        eprintln!("error: {}", error.message);
    }
}

fn emit_error(json_output: bool, code: &str, message: &str, details: Option<Value>) {
    emit_protocol_error(
        json_output,
        ProtocolError {
            code: code.into(),
            message: message.into(),
            details,
        },
    );
}

fn exit_code_for(code: &str) -> i32 {
    match code {
        "invalid_input" => 2,
        "host_unavailable" => 3,
        "ipc_error" => 4,
        "permission_denied" => 5,
        "target_not_found" => 6,
        "stale_observation" => 7,
        "timeout" => 8,
        "emergency_stop" => 9,
        "unsupported" => 10,
        "protocol_mismatch" => 11,
        "security_rejection" => 12,
        _ => 1,
    }
}
