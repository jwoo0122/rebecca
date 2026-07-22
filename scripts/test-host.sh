#!/usr/bin/env bash
set -euo pipefail

# Keep native test compilation aligned with the app deployment target.
export MACOSX_DEPLOYMENT_TARGET=15.0
readonly target="arm64-apple-macosx15.0"
readonly host_binary="build/tests/rebecca-host"
mkdir -p build/tests
swiftc \
  -target "$target" \
  host/Sources/PermissionState.swift host/Tests/PermissionStateTests.swift \
  -o build/tests/permission-state-tests
build/tests/permission-state-tests

swiftc \
  -target "$target" \
  host/Sources/SocketSupport.swift host/Tests/SocketSupportTests.swift \
  -o build/tests/socket-support-tests
build/tests/socket-support-tests

swiftc \
  -target "$target" \
  -framework AppKit \
  host/Sources/PermissionState.swift host/Sources/StatusWindow.swift host/Tests/StatusWindowTests.swift \
  -o build/tests/status-window-tests
build/tests/status-window-tests

swiftc \
  -target "$target" \
  -framework CoreGraphics \
  -framework ScreenCaptureKit \
  host/Sources/SocketSupport.swift host/Sources/ShareableContentSupport.swift host/Sources/DisplaySupport.swift host/Sources/DisplayRevision.swift host/Tests/DisplayRevisionTests.swift \
  -o build/tests/display-revision-tests
build/tests/display-revision-tests

swiftc \
  -target "$target" \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework ScreenCaptureKit \
  host/Sources/SocketSupport.swift host/Sources/ShareableContentSupport.swift host/Sources/DisplaySupport.swift host/Sources/CaptureSupport.swift host/Tests/CaptureSupportTests.swift \
  -o build/tests/capture-support-tests
build/tests/capture-support-tests

swiftc \
  -parse-as-library \
  -D HOST_TEST \
  -target "$target" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework ScreenCaptureKit \
  host/Sources/PermissionState.swift host/Sources/SocketSupport.swift host/Sources/StatusWindow.swift host/Sources/ShareableContentSupport.swift host/Sources/DisplaySupport.swift host/Sources/DisplayRevision.swift host/Sources/WindowSupport.swift host/Sources/CaptureSupport.swift host/Sources/AppSupport.swift host/Sources/FocusSupport.swift host/Sources/TreeSupport.swift host/Sources/ActionSupport.swift host/Sources/CGEventSupport.swift host/Sources/WindowControlSupport.swift host/Sources/AuditLogSupport.swift host/Sources/AppMain.swift \
  -o "$host_binary"

test_root="$(mktemp -d /tmp/rebecca.XXXXXX)"
readonly test_root
host_pid=""
stale_host_pid=""
idle_client_pid=""
cleanup() {
  if [[ -n "$idle_client_pid" ]]; then
    kill "$idle_client_pid" 2>/dev/null || true
    wait "$idle_client_pid" 2>/dev/null || true
  fi
  if [[ -n "$host_pid" ]]; then
    kill "$host_pid" 2>/dev/null || true
    wait "$host_pid" 2>/dev/null || true
  fi
  if [[ -n "$stale_host_pid" ]]; then
    kill "$stale_host_pid" 2>/dev/null || true
    wait "$stale_host_pid" 2>/dev/null || true
  fi
  rm -rf "$test_root"
}
trap cleanup EXIT

# The startup guard must reject and preserve a regular file at the socket path.
readonly regular_socket="$test_root/regular/control.sock"
mkdir -p "$(dirname "$regular_socket")"
printf 'preserve me\n' > "$regular_socket"
set +e
COMPUTER_USE_TEST_SOCKET_PATH="$regular_socket" "$host_binary" >"$test_root/regular-host.log" 2>&1
readonly regular_host_status=$?
set -e
[[ "$regular_host_status" -ne 0 ]]
[[ "$(cat "$regular_socket")" == "preserve me" ]]
test -f "$regular_socket"

# A stale socket is removed before the new host binds its replacement.
readonly stale_socket="$test_root/stale/control.sock"
mkdir -p "$(dirname "$stale_socket")"
SOCKET_PATH="$stale_socket" python3 - <<'PY'
import os
import socket

listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
listener.bind(os.environ["SOCKET_PATH"])
listener.close()
PY
COMPUTER_USE_TEST_SOCKET_PATH="$stale_socket" "$host_binary" >"$test_root/stale-host.log" 2>&1 &
stale_host_pid=$!
for _ in {1..50}; do
  if SOCKET_PATH="$stale_socket" python3 -c 'import os, socket; client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); client.settimeout(1); client.connect(os.environ["SOCKET_PATH"]); client.close()' 2>/dev/null; then
    break
  fi
  sleep 0.1
done
SOCKET_PATH="$stale_socket" python3 -c 'import os, socket; client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); client.settimeout(1); client.connect(os.environ["SOCKET_PATH"]); client.close()'
kill "$stale_host_pid"
wait "$stale_host_pid" || true
stale_host_pid=""

# A regular file swapped in after the stale probe must be restored, not unlinked.
readonly swapped_socket="$test_root/swapped/control.sock"
readonly swapped_replacement="$test_root/swapped/replacement"
mkdir -p "$(dirname "$swapped_socket")"
SOCKET_PATH="$swapped_socket" python3 - <<'PY'
import os
import socket

listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
listener.bind(os.environ["SOCKET_PATH"])
listener.close()
PY
printf 'replacement survives\n' > "$swapped_replacement"
set +e
COMPUTER_USE_TEST_SOCKET_PATH="$swapped_socket" \
  COMPUTER_USE_TEST_STALE_SOCKET_REPLACEMENT_PATH="$swapped_replacement" \
  "$host_binary" >"$test_root/swapped-host.log" 2>&1
readonly swapped_host_status=$?
set -e
[[ "$swapped_host_status" -ne 0 ]]
[[ "$(cat "$swapped_socket")" == "replacement survives" ]]
test -f "$swapped_socket"
test ! -e "$swapped_replacement"

# A partial frame must time out so a subsequent status request can be served.
readonly runtime_socket="$test_root/runtime/control.sock"
mkdir -p "$(dirname "$runtime_socket")"
# The host must force restrictive modes even if it inherits a permissive umask.
(umask 000; exec env COMPUTER_USE_TEST_SOCKET_PATH="$runtime_socket" "$host_binary" >"$test_root/runtime-host.log" 2>&1) &
host_pid=$!
for _ in {1..50}; do
  [[ -S "$runtime_socket" ]] && break
  sleep 0.1
done
test -S "$runtime_socket"
[[ "$(stat -f '%Lp' "$(dirname "$runtime_socket")")" == "700" ]]
[[ "$(stat -f '%Lp' "$runtime_socket")" == "600" ]]
set +e
COMPUTER_USE_TEST_SOCKET_PATH="$runtime_socket" "$host_binary" >"$test_root/active-host.log" 2>&1
readonly active_host_status=$?
set -e
[[ "$active_host_status" -ne 0 ]]
test -S "$runtime_socket"

SOCKET_PATH="$runtime_socket" python3 - <<'PY' &
import os
import socket
import time

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.connect(os.environ["SOCKET_PATH"])
client.sendall(b"\0")
time.sleep(4)
PY
idle_client_pid=$!
sleep 0.2
SOCKET_PATH="$runtime_socket" python3 - <<'PY'
import json
import os
import socket
import struct


def receive_exact(client, size):
    data = bytearray()
    while len(data) < size:
        chunk = client.recv(size - len(data))
        assert chunk, "host closed the connection before sending a response"
        data.extend(chunk)
    return bytes(data)


def receive_response(client):
    header = receive_exact(client, 4)
    length = struct.unpack(">I", header)[0]
    assert 0 < length <= 64 * 1024, "host response frame is not bounded"
    return json.loads(receive_exact(client, length))


def send_request(request):
    payload = json.dumps(request).encode()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5)
    client.connect(os.environ["SOCKET_PATH"])
    client.sendall(struct.pack(">I", len(payload)) + payload)
    response = receive_response(client)
    client.close()
    return response


def invalid_frame_header(length):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5)
    client.connect(os.environ["SOCKET_PATH"])
    client.sendall(struct.pack(">I", length))
    response = receive_response(client)
    assert response["protocol_version"] == 1
    assert isinstance(response["request_id"], str) and response["request_id"]
    assert response["ok"] is False
    assert response["error"]["code"] == "invalid_input"
    assert set(response) == {"protocol_version", "request_id", "ok", "error"}
    assert client.recv(1) == b"", "host wrote more than one response"
    client.close()


def invalid_input(request):
    response = send_request(request)
    assert response["protocol_version"] == 1
    assert response["request_id"]
    assert response["ok"] is False
    assert response["error"]["code"] == "invalid_input"


# Invalid declared sizes are framed invalid_input responses; the subsequent valid request verifies the host remains available.
invalid_frame_header(0)
invalid_frame_header(64 * 1024 + 1)

invalid_input({
    "protocol_version": 1,
    "request_id": "unknown-property",
    "command": "status",
    "arguments": {},
    "unexpected": True,
})
invalid_input({
    "protocol_version": 1,
    "request_id": "",
    "command": "status",
    "arguments": {},
})
invalid_input({
    "protocol_version": 1,
    "request_id": "empty-command",
    "command": "",
    "arguments": {},
})
response = send_request({
    "protocol_version": 1,
    "request_id": "timeout-test",
    "command": "status",
    "arguments": {},
})
assert response["ok"] is True, "host did not respond after the idle client timed out"
assert response["host"]["bundle_id"]
assert response["host"]["executable_path"]

# Displays requires Screen Recording permission. The test host binary is not the app bundle,
# so a prepared runner may return permission_denied; when permission is available, verify the
# native display shape and monotonic revision.
displays = send_request({
    "protocol_version": 1,
    "request_id": "displays-test",
    "command": "displays",
    "arguments": {},
})
assert displays["protocol_version"] == 1
assert displays["request_id"] == "displays-test"
if displays["ok"]:
    assert isinstance(displays["revision"], int) and displays["revision"] > 0
    assert isinstance(displays["displays"], list) and displays["displays"]
    assert sum(display["primary"] for display in displays["displays"]) == 1
    for display in displays["displays"]:
        assert display["display_id"] > 0
        assert display["logical_frame"]["width"] > 0
        assert display["logical_frame"]["height"] > 0
        assert display["pixel_size"]["width"] > 0
        assert display["pixel_size"]["height"] > 0
        assert display["scale_factor"] > 0
    second_displays = send_request({
        "protocol_version": 1,
        "request_id": "displays-test-second",
        "command": "displays",
        "arguments": {},
    })
    assert second_displays["ok"] is True
    assert second_displays["revision"] == displays["revision"]
else:
    assert displays["error"]["code"] == "permission_denied"
PY
