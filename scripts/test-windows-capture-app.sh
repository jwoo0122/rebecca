#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root
readonly host_app="$root/build/Rebecca.app"
readonly fixture_app="$root/build/RebeccaFixture.app"
readonly host_executable="$host_app/Contents/MacOS/rebecca-host"
readonly fixture_executable="$fixture_app/Contents/MacOS/rebecca-fixture"
readonly socket="$HOME/Library/Application Support/Rebecca/runtime/control.sock"
readonly fixture_bundle_id="dev.jwoo0122.rebecca-fixture"
test_root="$(mktemp -d /tmp/rebecca-window-capture.XXXXXX)"
readonly test_root

host_pid=""
fixture_pid=""
cleanup() {
  if [[ -n "$fixture_pid" ]]; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  if [[ -n "$host_pid" ]]; then
    kill "$host_pid" 2>/dev/null || true
    wait "$host_pid" 2>/dev/null || true
  fi
  rm -rf "$test_root"
}
trap cleanup EXIT

[[ -x "$host_executable" ]] || { echo "build Rebecca.app first" >&2; exit 1; }
[[ -x "$fixture_executable" ]] || { echo "build RebeccaFixture.app first" >&2; exit 1; }

if pgrep -f "$host_executable" >/dev/null 2>&1 || pgrep -f "$fixture_executable" >/dev/null 2>&1; then
  echo "the host or fixture is already running; quit both before this test" >&2
  exit 1
fi

open "$host_app"
for _ in {1..50}; do
  host_pid="$(pgrep -f "$host_executable" | head -n 1 || true)"
  [[ -n "$host_pid" && -S "$socket" ]] && break
  sleep 0.1
done
[[ -n "$host_pid" && -S "$socket" ]] || { echo "Rebecca.app did not start" >&2; exit 1; }

open "$fixture_app"
for _ in {1..50}; do
  fixture_pid="$(pgrep -f "$fixture_executable" | head -n 1 || true)"
  [[ -n "$fixture_pid" ]] && break
  sleep 0.1
done
[[ -n "$fixture_pid" ]] || { echo "RebeccaFixture.app did not start" >&2; exit 1; }

set +e
windows_json="$(cargo run -q -p rebecca-cli -- windows --app "$fixture_bundle_id" --json --no-start)"
windows_status=$?
set -e
if [[ "$windows_status" -ne 0 ]]; then
  echo "windows failed; grant Screen Recording to the exact rebuilt Rebecca.app and restart it" >&2
  printf '%s\n' "$windows_json" >&2
  exit 1
fi

WINDOWS_JSON="$windows_json" python3 - <<'PY'
import json
import os

response = json.loads(os.environ["WINDOWS_JSON"])
assert response["ok"] is True
assert response["revision"] > 0
windows = [window for window in response["windows"] if window["onscreen"]]
assert len(windows) == 1, windows
window = windows[0]
assert window["window_id"] > 0
assert window["owner_pid"] > 0
assert window["bundle_id"] == "dev.jwoo0122.rebecca-fixture"
assert window["title"] == "Rebecca Fixture"
assert window["logical_frame"]["width"] > 0
assert window["logical_frame"]["height"] > 0
assert window["onscreen"] is True
assert window["minimized"] is False
assert window["display_id"] > 0
PY
window_id="$(WINDOWS_JSON="$windows_json" python3 -c 'import json, os; print(json.loads(os.environ["WINDOWS_JSON"])["windows"][0]["window_id"])')"
output="$test_root/frame.png"

capture_json="$(cargo run -q -p rebecca-cli -- capture --window-id "$window_id" --output "$output" --json --no-start)"
CAPTURE_JSON="$capture_json" OUTPUT="$output" WINDOW_ID="$window_id" python3 - <<'PY'
import json
import os
import struct

response = json.loads(os.environ["CAPTURE_JSON"])
output = os.environ["OUTPUT"]
assert response["ok"] is True
assert response["path"] == output
assert response["target"] == {"type": "window", "id": int(os.environ["WINDOW_ID"])}
assert response["pixel_size"]["width"] > 0
assert response["pixel_size"]["height"] > 0
assert response["logical_frame"]["width"] > 0
assert response["logical_frame"]["height"] > 0
assert response["scale_factor"] > 0
assert response["revision"] > 0
with open(output, "rb") as stream:
    data = stream.read()
assert data[:8] == b"\x89PNG\r\n\x1a\n"
width, height = struct.unpack(">II", data[16:24])
assert [width, height] == [response["pixel_size"]["width"], response["pixel_size"]["height"]]
PY

before_hash="$(shasum -a 256 "$output")"
set +e
second_output="$(cargo run -q -p rebecca-cli -- capture --window-id "$window_id" --output "$output" --json --no-start)"
second_status=$?
set -e
[[ "$second_status" -eq 2 ]] || { echo "existing output was not rejected: $second_output" >&2; exit 1; }
[[ "$before_hash" == "$(shasum -a 256 "$output")" ]] || { echo "existing output changed" >&2; exit 1; }

missing_output="$test_root/missing.png"
set +e
missing_response="$(cargo run -q -p rebecca-cli -- capture --window-id 4294967295 --output "$missing_output" --json --no-start)"
missing_status=$?
set -e
[[ "$missing_status" -eq 6 ]] || { echo "missing window did not map to exit 6: $missing_response" >&2; exit 1; }
[[ ! -e "$missing_output" ]] || { echo "missing target created an output file" >&2; exit 1; }

printf 'windows/capture app integration passed: window %s, output %s\n' "$window_id" "$output"
