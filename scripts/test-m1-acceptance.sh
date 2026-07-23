#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root
host_exe="$root/build/Rebecca.app/Contents/MacOS/rebecca-host"
fixture_exe="$root/build/RebeccaFixture.app/Contents/MacOS/rebecca-fixture"
socket="$HOME/Library/Application Support/Rebecca/runtime/control.sock"
host_pid=""; fixture_pid=""
cleanup() { [[ -n "$fixture_pid" ]] && kill "$fixture_pid" 2>/dev/null || true; [[ -n "$host_pid" ]] && kill "$host_pid" 2>/dev/null || true; }
trap cleanup EXIT

pkill -TERM -f "$host_exe" 2>/dev/null || true
pkill -TERM -f "$fixture_exe" 2>/dev/null || true
sleep 1

open "$root/build/Rebecca.app"
for _ in {1..50}; do host_pid="$(pgrep -f "$host_exe" | head -n1 || true)"; [[ -n "$host_pid" && -S "$socket" ]] && break; sleep .1; done
[[ -n "$host_pid" && -S "$socket" ]] || { echo "host did not start" >&2; exit 1; }

open "$root/build/RebeccaFixture.app"
for _ in {1..50}; do fixture_pid="$(pgrep -f "$fixture_exe" | head -n1 || true)"; [[ -n "$fixture_pid" ]] && break; sleep .1; done
[[ -n "$fixture_pid" ]] || { echo "fixture did not start" >&2; exit 1; }

osascript -e 'tell application "System Events" to set frontmost of (first process whose name contains "Fixture") to true' 2>/dev/null || true
sleep 1

mkdir -p /tmp/cu-m1
cargo run -q -p rebecca-cli -- displays --json --no-start > /tmp/cu-m1/displays.json
cargo run -q -p rebecca-cli -- apps --json --no-start > /tmp/cu-m1/apps.json
cargo run -q -p rebecca-cli -- focused --json --no-start > /tmp/cu-m1/focused.json
cargo run -q -p rebecca-cli -- windows --app dev.jwoo0122.rebecca-fixture --json --no-start > /tmp/cu-m1/windows.json

python3 /tmp/cu-m1/verify.py

fixture_window_id="$(python3 - <<'PY'
import json
with open("/tmp/cu-m1/windows.json") as stream:
    data = json.load(stream)
print(data["windows"][0]["window_id"])
PY
)"

cargo run -q -p rebecca-cli -- act \
  --window-id "$fixture_window_id" \
  --action press \
  --role AXButton \
  --label "Test Button" \
  --json \
  --no-start > /tmp/cu-m1/act.json
python3 - <<'PY'
import json
with open("/tmp/cu-m1/act.json") as stream:
    response = json.load(stream)
assert response["ok"] is True
assert response["action"] == "act"
assert response["executed"] is True
assert response["verified"] is True
PY

set +e
cargo run -q -p rebecca-cli -- act \
  --window-id "$fixture_window_id" \
  --action press \
  --role AXButton \
  --label-contains "Button" \
  --json \
  --no-start > /tmp/cu-m1/ambiguous-act.json
ambiguous_status=$?
set -e
[[ "$ambiguous_status" -eq 14 ]]
python3 - <<'PY'
import json
with open("/tmp/cu-m1/ambiguous-act.json") as stream:
    response = json.load(stream)
assert response["ok"] is False
assert response["error"]["code"] == "ambiguous_element"
PY
