#!/usr/bin/env bash
set -euo pipefail

# Manual native integration test for the permission-bearing app bundle.
export MACOSX_DEPLOYMENT_TARGET=15.0
readonly app="build/Rebecca.app"
readonly executable="$app/Contents/MacOS/rebecca-host"
readonly socket="$HOME/Library/Application Support/Rebecca/runtime/control.sock"

[[ -x "$executable" ]] || {
  echo "missing $app; run scripts/build-app.sh first" >&2
  exit 1
}

if pgrep -f "$executable" >/dev/null 2>&1; then
  echo "$app is already running; quit it before running this test" >&2
  exit 1
fi

host_pid=""
cleanup() {
  if [[ -n "$host_pid" ]]; then
    kill "$host_pid" 2>/dev/null || true
    wait "$host_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

open "$app"
for _ in {1..50}; do
  host_pid="$(pgrep -f "$executable" | head -n 1 || true)"
  [[ -n "$host_pid" && -S "$socket" ]] && break
  sleep 0.1
done
[[ -n "$host_pid" && -S "$socket" ]] || {
  echo "Rebecca.app did not start its default socket" >&2
  exit 1
}

set +e
first="$(cargo run -q -p rebecca-cli -- displays --json --no-start)"
first_status=$?
set -e
if [[ "$first_status" -ne 0 ]]; then
  echo "displays failed for the rebuilt Rebecca.app; grant Screen Recording to this exact bundle and restart it" >&2
  printf '%s\n' "$first" >&2
  exit 1
fi

set +e
second="$(cargo run -q -p rebecca-cli -- displays --json --no-start)"
second_status=$?
set -e
if [[ "$second_status" -ne 0 ]]; then
  echo "the second displays request failed" >&2
  printf '%s\n' "$second" >&2
  exit 1
fi

FIRST="$first" SECOND="$second" python3 - <<'PY'
import json
import os

first = json.loads(os.environ["FIRST"])
second = json.loads(os.environ["SECOND"])
for response in (first, second):
    assert response["ok"] is True
    assert isinstance(response["revision"], int) and response["revision"] > 0
    displays = response["displays"]
    assert displays
    assert sum(display["primary"] for display in displays) == 1
    for display in displays:
        assert display["display_id"] > 0
        assert display["logical_frame"]["width"] > 0
        assert display["logical_frame"]["height"] > 0
        assert display["pixel_size"]["width"] > 0
        assert display["pixel_size"]["height"] > 0
        assert display["scale_factor"] > 0
assert second["revision"] == first["revision"]
print(f"displays app integration passed: {len(first['displays'])} display(s), revision {first['revision']}")
PY
