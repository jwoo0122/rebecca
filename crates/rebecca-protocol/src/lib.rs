//! Version 1 of the local Rebecca socket protocol.

use std::io::{self, Read, Write};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_FRAME_BYTES: usize = 64 * 1024;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub protocol_version: u32,
    pub request_id: String,
    pub command: String,
    pub arguments: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StatusResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub host: Option<HostStatus>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub permissions: Option<Permissions>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub emergency_stop: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DisplaysResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub displays: Option<Vec<DisplayInfo>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WindowsResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub windows: Option<Vec<WindowInfo>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WindowInfo {
    pub window_id: u32,
    pub owner_pid: Option<u32>,
    pub bundle_id: Option<String>,
    pub title: Option<String>,
    pub logical_frame: LogicalFrame,
    pub onscreen: bool,
    pub minimized: Option<bool>,
    pub focused: Option<bool>,
    pub display_id: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CaptureResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<CaptureTarget>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pixel_size: Option<PixelSize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logical_frame: Option<LogicalFrame>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scale_factor: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AppsResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub apps: Option<Vec<AppInfo>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AppInfo {
    pub pid: u32,
    pub bundle_id: Option<String>,
    pub name: Option<String>,
    pub executable_url: Option<String>,
    pub active: bool,
    pub hidden: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FocusedResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_app: Option<FocusedApp>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub focused_window: Option<FocusedWindow>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub focused_element: Option<FocusedElement>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FocusedApp {
    pub pid: u32,
    pub bundle_id: Option<String>,
    pub name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FocusedWindow {
    pub window_id: Option<u32>,
    pub title: Option<String>,
    pub logical_frame: Option<LogicalFrame>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FocusedElement {
    pub role: String,
    pub label: Option<String>,
    pub description: Option<String>,
    pub logical_frame: Option<LogicalFrame>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CaptureTarget {
    #[serde(rename = "type")]
    pub target_type: String,
    pub id: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DisplayInfo {
    pub display_id: u32,
    pub logical_frame: LogicalFrame,
    pub pixel_size: PixelSize,
    pub scale_factor: f64,
    pub primary: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LogicalFrame {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PixelSize {
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TreeResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub root: Option<TreeNode>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub truncated: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TreeNode {
    pub id: String,
    pub role: String,
    pub subrole: Option<String>,
    pub label: Option<String>,
    pub description: Option<String>,
    pub value: Option<Value>,
    pub enabled: bool,
    pub focused: bool,
    pub secure: bool,
    pub frame: Option<LogicalFrame>,
    pub actions: Vec<String>,
    pub children: Vec<TreeNode>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FindResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub results: Option<Vec<TreeNode>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub truncated: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionResponse {
    pub protocol_version: u32,
    pub request_id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub executed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub method: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub before_revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub after_revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verified: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub at_end: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub before_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub after_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub before_title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub after_title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ProtocolError>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostStatus {
    pub running: bool,
    pub version: String,
    pub pid: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bundle_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub executable_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Permissions {
    pub accessibility: PermissionState,
    pub screen_recording: PermissionState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PermissionState {
    Granted,
    Denied,
    NotDetermined,
    Restricted,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProtocolError {
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<Value>,
}

#[derive(Debug, Error)]
pub enum FrameError {
    #[error("I/O error: {0}")]
    Io(#[from] io::Error),
    #[error("frame length {actual} exceeds maximum {maximum}")]
    TooLarge { actual: usize, maximum: usize },
    #[error("zero-length frames are not valid JSON messages")]
    Empty,
    #[error("invalid JSON message: {0}")]
    Json(#[from] serde_json::Error),
}

/// Writes one big-endian u32 length-prefixed JSON message.
pub fn write_message<W: Write, T: Serialize>(
    writer: &mut W,
    message: &T,
) -> Result<(), FrameError> {
    let payload = serde_json::to_vec(message)?;
    if payload.len() > MAX_FRAME_BYTES {
        return Err(FrameError::TooLarge {
            actual: payload.len(),
            maximum: MAX_FRAME_BYTES,
        });
    }

    let length = u32::try_from(payload.len()).expect("maximum frame size fits in u32");
    writer.write_all(&length.to_be_bytes())?;
    writer.write_all(&payload)?;
    writer.flush()?;
    Ok(())
}

/// Reads one big-endian u32 length-prefixed JSON message.
pub fn read_message<R: Read, T: for<'de> Deserialize<'de>>(
    reader: &mut R,
) -> Result<T, FrameError> {
    let mut header = [0_u8; 4];
    reader.read_exact(&mut header)?;
    let length = u32::from_be_bytes(header) as usize;
    if length == 0 {
        return Err(FrameError::Empty);
    }
    if length > MAX_FRAME_BYTES {
        return Err(FrameError::TooLarge {
            actual: length,
            maximum: MAX_FRAME_BYTES,
        });
    }

    let mut payload = vec![0_u8; length];
    reader.read_exact(&mut payload)?;
    Ok(serde_json::from_slice(&payload)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> Request {
        Request {
            protocol_version: PROTOCOL_VERSION,
            request_id: "test-request".into(),
            command: "status".into(),
            arguments: serde_json::json!({}),
        }
    }

    #[test]
    fn frame_round_trip() {
        let mut bytes = Vec::new();
        write_message(&mut bytes, &request()).unwrap();
        assert_eq!(
            read_message::<_, Request>(&mut bytes.as_slice()).unwrap(),
            request()
        );
    }

    #[test]
    fn displays_response_round_trip() {
        let response = DisplaysResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "display-request".into(),
            ok: true,
            revision: Some(3),
            displays: Some(vec![DisplayInfo {
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
            }]),
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, DisplaysResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );
    }

    #[test]
    fn windows_response_round_trip() {
        let response = WindowsResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "windows-request".into(),
            ok: true,
            revision: Some(12),
            windows: Some(vec![WindowInfo {
                window_id: 481,
                owner_pid: None,
                bundle_id: Some("com.apple.Safari".into()),
                title: None,
                logical_frame: LogicalFrame {
                    x: 120.0,
                    y: 80.0,
                    width: 800.0,
                    height: 500.0,
                },
                onscreen: true,
                minimized: Some(false),
                focused: None,
                display_id: Some(1),
            }]),
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, WindowsResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );

        let value = serde_json::to_value(&response.windows.as_ref().unwrap()[0]).unwrap();
        assert_eq!(value["owner_pid"], serde_json::Value::Null);
        assert_eq!(value["title"], serde_json::Value::Null);
        assert_eq!(value["focused"], serde_json::Value::Null);
    }

    #[test]
    fn capture_response_round_trip() {
        let response = CaptureResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "capture-request".into(),
            ok: true,
            path: Some("/tmp/frame.png".into()),
            target: Some(CaptureTarget {
                target_type: "window".into(),
                id: 481,
            }),
            pixel_size: Some(PixelSize {
                width: 1600,
                height: 1000,
            }),
            logical_frame: Some(LogicalFrame {
                x: 120.0,
                y: 80.0,
                width: 800.0,
                height: 500.0,
            }),
            scale_factor: Some(2.0),
            revision: Some(102),
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, CaptureResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );
    }

    #[test]
    fn capture_failure_has_only_common_fields_and_error() {
        let response = CaptureResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "capture-request".into(),
            ok: false,
            path: None,
            target: None,
            pixel_size: None,
            logical_frame: None,
            scale_factor: None,
            revision: None,
            error: Some(ProtocolError {
                code: "permission_denied".into(),
                message: "Screen Recording permission is required.".into(),
                details: None,
            }),
        };
        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": "capture-request",
                "ok": false,
                "error": {
                    "code": "permission_denied",
                    "message": "Screen Recording permission is required."
                }
            })
        );
        assert_eq!(
            serde_json::from_value::<CaptureResponse>(value).unwrap(),
            response
        );
    }

    #[test]
    fn action_response_round_trip() {
        let response = ActionResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "act-request".into(),
            ok: true,
            action: Some("act".into()),
            executed: Some(true),
            method: Some("ax_press_background".into()),
            before_revision: Some(10),
            after_revision: Some(11),
            verified: Some(true),
            at_end: None,
            before_url: Some("https://example.test/old".into()),
            after_url: Some("https://example.test/new".into()),
            before_title: Some("Old".into()),
            after_title: Some("New".into()),
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, ActionResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );
    }

    #[test]
    fn action_failure_has_only_common_fields_and_error() {
        let response = ActionResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "act-request".into(),
            ok: false,
            action: None,
            executed: None,
            method: None,
            before_revision: None,
            after_revision: None,
            verified: None,
            at_end: None,
            before_url: None,
            after_url: None,
            before_title: None,
            after_title: None,
            error: Some(ProtocolError {
                code: "ambiguous_element".into(),
                message: "Locator matched multiple elements.".into(),
                details: None,
            }),
        };
        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(value["action"], serde_json::Value::Null);
        assert_eq!(value["error"]["code"], "ambiguous_element");
        assert_eq!(
            serde_json::from_value::<ActionResponse>(value).unwrap(),
            response
        );
    }

    #[test]
    fn apps_response_round_trip() {
        let response = AppsResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "apps-request".into(),
            ok: true,
            revision: Some(42),
            apps: Some(vec![
                AppInfo {
                    pid: 1234,
                    bundle_id: Some("com.apple.Safari".into()),
                    name: Some("Safari".into()),
                    executable_url: None,
                    active: true,
                    hidden: false,
                },
                AppInfo {
                    pid: 5678,
                    bundle_id: None,
                    name: None,
                    executable_url: Some("file:///usr/bin/thing".into()),
                    active: false,
                    hidden: true,
                },
            ]),
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, AppsResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );

        let value = serde_json::to_value(&response.apps.as_ref().unwrap()[1]).unwrap();
        assert_eq!(value["bundle_id"], serde_json::Value::Null);
        assert_eq!(value["name"], serde_json::Value::Null);
    }

    #[test]
    fn focused_response_round_trip() {
        let response = FocusedResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "focused-request".into(),
            ok: true,
            revision: Some(7),
            active_app: Some(FocusedApp {
                pid: 1234,
                bundle_id: Some("com.apple.Safari".into()),
                name: Some("Safari".into()),
            }),
            focused_window: Some(FocusedWindow {
                window_id: Some(481),
                title: Some("Welcome".into()),
                logical_frame: Some(LogicalFrame {
                    x: 100.0,
                    y: 50.0,
                    width: 800.0,
                    height: 600.0,
                }),
            }),
            focused_element: Some(FocusedElement {
                role: "AXButton".into(),
                label: None,
                description: Some("Submit form".into()),
                logical_frame: Some(LogicalFrame {
                    x: 200.0,
                    y: 300.0,
                    width: 120.0,
                    height: 40.0,
                }),
            }),
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, FocusedResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );

        let value = serde_json::to_value(response.focused_element.as_ref().unwrap()).unwrap();
        assert_eq!(value["label"], serde_json::Value::Null);
    }

    #[test]
    fn focused_response_round_trip_with_null_nested_fields() {
        let response = FocusedResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "focused-nulls".into(),
            ok: true,
            revision: Some(1),
            active_app: None,
            focused_window: Some(FocusedWindow {
                window_id: None,
                title: None,
                logical_frame: None,
            }),
            focused_element: Some(FocusedElement {
                role: "AXUnknown".into(),
                label: None,
                description: None,
                logical_frame: None,
            }),
            error: None,
        };
        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(value["active_app"], serde_json::Value::Null);
        assert_eq!(
            value["focused_window"]["window_id"],
            serde_json::Value::Null
        );
        assert_eq!(value["focused_window"]["title"], serde_json::Value::Null);
        assert_eq!(
            value["focused_window"]["logical_frame"],
            serde_json::Value::Null
        );
        assert_eq!(value["focused_element"]["label"], serde_json::Value::Null);
        assert_eq!(
            value["focused_element"]["description"],
            serde_json::Value::Null
        );
        assert_eq!(
            value["focused_element"]["logical_frame"],
            serde_json::Value::Null
        );

        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, FocusedResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );
    }

    #[test]
    fn apps_failure_has_only_common_fields_and_error() {
        let response = AppsResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "apps-request".into(),
            ok: false,
            revision: None,
            apps: None,
            error: Some(ProtocolError {
                code: "permission_denied".into(),
                message: "Accessibility permission is required.".into(),
                details: None,
            }),
        };
        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": "apps-request",
                "ok": false,
                "error": {
                    "code": "permission_denied",
                    "message": "Accessibility permission is required."
                }
            })
        );
        assert_eq!(
            serde_json::from_value::<AppsResponse>(value).unwrap(),
            response
        );
    }

    #[test]
    fn focused_failure_has_only_common_fields_and_error() {
        let response = FocusedResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "focused-request".into(),
            ok: false,
            revision: None,
            active_app: None,
            focused_window: None,
            focused_element: None,
            error: Some(ProtocolError {
                code: "host_unavailable".into(),
                message: "Host process is not running.".into(),
                details: None,
            }),
        };
        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": "focused-request",
                "ok": false,
                "error": {
                    "code": "host_unavailable",
                    "message": "Host process is not running."
                }
            })
        );
        assert_eq!(
            serde_json::from_value::<FocusedResponse>(value).unwrap(),
            response
        );
    }

    #[test]
    fn apps_and_focused_response_types_reject_unknown_fields() {
        let mut apps = serde_json::to_value(AppsResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "apps-request".into(),
            ok: true,
            revision: Some(1),
            apps: Some(Vec::new()),
            error: None,
        })
        .unwrap();
        apps["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<AppsResponse>(apps).is_err());

        let mut focused = serde_json::to_value(FocusedResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "focused-request".into(),
            ok: true,
            revision: Some(1),
            active_app: None,
            focused_window: None,
            focused_element: None,
            error: None,
        })
        .unwrap();
        focused["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<FocusedResponse>(focused).is_err());
    }

    #[test]
    fn request_rejects_unknown_fields() {
        let mut request = serde_json::to_value(request()).unwrap();
        request["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<Request>(request).is_err());
    }

    #[test]
    fn new_response_types_reject_unknown_fields() {
        let mut windows = serde_json::to_value(WindowsResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "windows-request".into(),
            ok: true,
            revision: Some(1),
            windows: Some(Vec::new()),
            error: None,
        })
        .unwrap();
        windows["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<WindowsResponse>(windows).is_err());

        let mut capture = serde_json::to_value(CaptureResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "capture-request".into(),
            ok: true,
            path: Some("/tmp/frame.png".into()),
            target: Some(CaptureTarget {
                target_type: "window".into(),
                id: 481,
            }),
            pixel_size: Some(PixelSize {
                width: 1600,
                height: 1000,
            }),
            logical_frame: Some(LogicalFrame {
                x: 0.0,
                y: 0.0,
                width: 800.0,
                height: 500.0,
            }),
            scale_factor: Some(2.0),
            revision: Some(1),
            error: None,
        })
        .unwrap();
        capture["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<CaptureResponse>(capture).is_err());
    }

    #[test]
    fn rejects_oversized_frame_header_before_allocating_payload() {
        let bytes = (MAX_FRAME_BYTES as u32 + 1).to_be_bytes();
        assert!(matches!(
            read_message::<_, Request>(&mut bytes.as_slice()),
            Err(FrameError::TooLarge { .. })
        ));
    }

    #[test]
    fn rejects_truncated_frame() {
        let bytes = [0, 0, 0, 2, b'{'];
        assert!(matches!(
            read_message::<_, Request>(&mut bytes.as_slice()),
            Err(FrameError::Io(error)) if error.kind() == io::ErrorKind::UnexpectedEof
        ));
    }

    #[test]
    fn rejects_invalid_json() {
        let bytes = [0, 0, 0, 1, b'x'];
        assert!(matches!(
            read_message::<_, Request>(&mut bytes.as_slice()),
            Err(FrameError::Json(_))
        ));
    }

    #[test]
    fn tree_response_round_trip() {
        let response = TreeResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "tree-request".into(),
            ok: true,
            revision: Some(5),
            root: Some(TreeNode {
                id: "ax:window:0".into(),
                role: "AXWindow".into(),
                subrole: None,
                label: Some("Main".into()),
                description: None,
                value: None,
                enabled: true,
                focused: true,
                secure: true,
                frame: Some(LogicalFrame {
                    x: 0.0,
                    y: 0.0,
                    width: 1440.0,
                    height: 900.0,
                }),
                actions: vec!["focus".into()],
                children: vec![TreeNode {
                    id: "ax:button:1".into(),
                    role: "AXButton".into(),
                    subrole: Some("AXButton".into()),
                    label: Some("Submit".into()),
                    description: Some("Submit the form".into()),
                    value: Some(serde_json::json!("Click")),
                    enabled: true,
                    focused: false,
                    secure: false,
                    frame: Some(LogicalFrame {
                        x: 100.0,
                        y: 200.0,
                        width: 80.0,
                        height: 30.0,
                    }),
                    actions: vec!["click".into(), "focus".into()],
                    children: vec![],
                }],
            }),
            truncated: Some(false),
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, TreeResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );

        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(value["root"]["value"], serde_json::Value::Null);
        assert_eq!(value["root"]["subrole"], serde_json::Value::Null);
        assert_eq!(value["root"]["description"], serde_json::Value::Null);
        assert_eq!(
            value["root"]["children"][0]["value"],
            serde_json::json!("Click")
        );
    }

    #[test]
    fn find_response_round_trip() {
        let response = FindResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "find-request".into(),
            ok: true,
            revision: Some(3),
            results: Some(vec![
                TreeNode {
                    id: "ax:button:1".into(),
                    role: "AXButton".into(),
                    subrole: None,
                    label: Some("Submit".into()),
                    description: None,
                    value: Some(serde_json::json!("Click")),
                    enabled: true,
                    focused: false,
                    secure: false,
                    frame: Some(LogicalFrame {
                        x: 100.0,
                        y: 200.0,
                        width: 80.0,
                        height: 30.0,
                    }),
                    actions: vec!["click".into()],
                    children: vec![],
                },
                TreeNode {
                    id: "ax:textfield:2".into(),
                    role: "AXTextField".into(),
                    subrole: None,
                    label: None,
                    description: None,
                    value: None,
                    enabled: true,
                    focused: true,
                    secure: true,
                    frame: None,
                    actions: vec!["focus".into(), "set_value".into()],
                    children: vec![],
                },
            ]),
            truncated: None,
            error: None,
        };
        let mut bytes = Vec::new();
        write_message(&mut bytes, &response).unwrap();
        assert_eq!(
            read_message::<_, FindResponse>(&mut bytes.as_slice()).unwrap(),
            response
        );

        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(value["results"][1]["value"], serde_json::Value::Null);
        assert_eq!(value["results"][1]["frame"], serde_json::Value::Null);
    }

    #[test]
    fn tree_failure_has_only_common_fields_and_error() {
        let response = TreeResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "tree-request".into(),
            ok: false,
            revision: None,
            root: None,
            truncated: None,
            error: Some(ProtocolError {
                code: "permission_denied".into(),
                message: "Accessibility permission is required.".into(),
                details: None,
            }),
        };
        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": "tree-request",
                "ok": false,
                "error": {
                    "code": "permission_denied",
                    "message": "Accessibility permission is required."
                }
            })
        );
        assert_eq!(
            serde_json::from_value::<TreeResponse>(value).unwrap(),
            response
        );
    }

    #[test]
    fn find_failure_has_only_common_fields_and_error() {
        let response = FindResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "find-request".into(),
            ok: false,
            revision: None,
            results: None,
            truncated: None,
            error: Some(ProtocolError {
                code: "host_unavailable".into(),
                message: "Host process is not running.".into(),
                details: None,
            }),
        };
        let value = serde_json::to_value(&response).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "protocol_version": PROTOCOL_VERSION,
                "request_id": "find-request",
                "ok": false,
                "error": {
                    "code": "host_unavailable",
                    "message": "Host process is not running."
                }
            })
        );
        assert_eq!(
            serde_json::from_value::<FindResponse>(value).unwrap(),
            response
        );
    }

    #[test]
    fn tree_and_find_response_types_reject_unknown_fields() {
        let mut tree = serde_json::to_value(TreeResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "tree-request".into(),
            ok: true,
            revision: Some(1),
            root: Some(TreeNode {
                id: "root".into(),
                role: "AXWindow".into(),
                subrole: None,
                label: None,
                description: None,
                value: None,
                enabled: true,
                focused: true,
                secure: false,
                frame: None,
                actions: vec![],
                children: vec![],
            }),
            truncated: None,
            error: None,
        })
        .unwrap();
        tree["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<TreeResponse>(tree).is_err());

        let mut find = serde_json::to_value(FindResponse {
            protocol_version: PROTOCOL_VERSION,
            request_id: "find-request".into(),
            ok: true,
            revision: Some(1),
            results: Some(Vec::new()),
            truncated: None,
            error: None,
        })
        .unwrap();
        find["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<FindResponse>(find).is_err());
    }
}
