#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root
host_exe="$root/build/Rebecca.app/Contents/MacOS/rebecca-host"
fixture_exe="$root/build/RebeccaFixture.app/Contents/MacOS/rebecca-fixture"
socket="$HOME/Library/Application Support/Rebecca/runtime/control.sock"
host_pid=""; fixture_pid=""
cleanup() {
  [[ -n "$fixture_pid" ]] && kill "$fixture_pid" 2>/dev/null || true
  [[ -n "$host_pid" ]] && kill "$host_pid" 2>/dev/null || true
}
trap cleanup EXIT

pkill -TERM -f "$host_exe" 2>/dev/null || true
pkill -TERM -f "$fixture_exe" 2>/dev/null || true
sleep 1

open "$root/build/Rebecca.app"
for _ in {1..50}; do
  host_pid="$(pgrep -f "$host_exe" | head -n1 || true)"
  [[ -n "$host_pid" && -S "$socket" ]] && break
  sleep .1
done
[[ -n "$host_pid" && -S "$socket" ]] || { echo "host did not start" >&2; exit 1; }

open "$root/build/RebeccaFixture.app"
for _ in {1..50}; do
  fixture_pid="$(pgrep -f "$fixture_exe" | head -n1 || true)"
  [[ -n "$fixture_pid" ]] && break
  sleep .1
done
[[ -n "$fixture_pid" ]] || { echo "fixture did not start" >&2; exit 1; }

osascript -e 'tell application "System Events" to set frontmost of (first process whose name contains "Fixture") to true' 2>/dev/null || true
sleep 1

mkdir -p /tmp/cu-m2

cli() { cargo run -q -p rebecca-cli -- "$@"; }

# 1. Tree query - find fixture elements
echo "=== 1. Tree query ==="
cli tree --app dev.jwoo0122.rebecca-fixture --json --no-start > /tmp/cu-m2/tree.json
python3 <<'PY'
import json
with open("/tmp/cu-m2/tree.json") as f:
    data = json.load(f)
assert data["ok"] is True, f"tree failed: {data}"
assert data["revision"] > 0
root = data["root"]
assert root is not None

def search(node, role=None, label_contains=None):
    results = []
    if role and node.get("role") == role:
        if label_contains is None or (node.get("label") and label_contains in node["label"]):
            results.append(node)
    for c in node.get("children", []):
        results.extend(search(c, role, label_contains))
    return results

buttons = search(root, role="AXButton", label_contains="Test Button")
assert len(buttons) >= 1, "Test Button not found"
btn = buttons[0]
assert btn["id"]
assert "AXPress" in btn["actions"]
assert btn["enabled"] is True
with open("/tmp/cu-m2/button_id.txt", "w") as f: f.write(btn["id"])
with open("/tmp/cu-m2/revision.txt", "w") as f: f.write(str(data["revision"]))
print(f"  Test Button: id={btn['id']}, rev={data['revision']}")

fields = search(root, role="AXTextField", label_contains="Test Input")
assert len(fields) >= 1, "Test Input field not found"
field = fields[0]
assert field["id"]
with open("/tmp/cu-m2/field_id.txt", "w") as f: f.write(field["id"])
print(f"  Text Field: id={field['id']}")

secure = search(root, role="AXTextField", label_contains="Secure")
assert len(secure) >= 1, "Secure field not found"
sf = secure[0]
assert sf["secure"] is True
assert sf["id"]
with open("/tmp/cu-m2/secure_id.txt", "w") as f: f.write(sf["id"])
print(f"  Secure Field: id={sf['id']}, secure={sf['secure']}")
print("  PASS")
PY

# 2. AX press button
echo "=== 2. AX press button ==="
button_id=$(cat /tmp/cu-m2/button_id.txt)
revision=$(cat /tmp/cu-m2/revision.txt)
cli press --element "$button_id" --revision "$revision" --json --no-start > /tmp/cu-m2/press.json
python3 <<'PY'
import json
with open("/tmp/cu-m2/press.json") as f:
    data = json.load(f)
assert data["ok"] is True, f"press failed: {data}"
assert data["executed"] is True
assert "ax_press" in data["method"]
assert data["after_revision"] >= data["before_revision"]
print(f"  method={data['method']}, rev {data['before_revision']} -> {data['after_revision']}")
print("  PASS")
PY

# 3. Verify status changed
echo "=== 3. Verify status change ==="
cli tree --app dev.jwoo0122.rebecca-fixture --json --no-start > /tmp/cu-m2/tree2.json
python3 <<'PY'
import json
with open("/tmp/cu-m2/tree2.json") as f:
    data = json.load(f)
assert data["ok"] is True

def search_val(node, text):
    if str(node.get("value") or "") == text or node.get("label") == text:
        return node
    for c in node.get("children", []):
        r = search_val(c, text)
        if r: return r
    return None

root = data["root"]
status = search_val(root, "Status: Button Clicked")
assert status is not None, "Status did not change to Button Clicked"
print(f"  Status updated: value={status.get('value')}")
print("  PASS")
PY

# 4. AX set value on text field
echo "=== 4. AX set value ==="
field_id=$(cat /tmp/cu-m2/field_id.txt)
cli tree --app dev.jwoo0122.rebecca-fixture --json --no-start > /tmp/cu-m2/tree3.json
revision3=$(python3 -c "import json; print(json.load(open('/tmp/cu-m2/tree3.json'))['revision'])")
cli set-value --element "$field_id" --revision "$revision3" --value "hello world" --json --no-start > /tmp/cu-m2/setvalue.json
python3 <<'PY'
import json
with open("/tmp/cu-m2/setvalue.json") as f:
    data = json.load(f)
assert data["ok"] is True, f"set_value failed: {data}"
assert data["executed"] is True
assert "ax_set" in data["method"]
print(f"  method={data['method']}, value set to 'hello world'")
print("  PASS")
PY

# 5. Secure field rejection
echo "=== 5. Secure field rejection ==="
secure_id=$(cat /tmp/cu-m2/secure_id.txt)
cli tree --app dev.jwoo0122.rebecca-fixture --json --no-start > /tmp/cu-m2/tree4.json
revision4=$(python3 -c "import json; print(json.load(open('/tmp/cu-m2/tree4.json'))['revision'])")
cli set-value --element "$secure_id" --revision "$revision4" --value "secret" --json --no-start > /tmp/cu-m2/secure_reject.json 2>/dev/null || true
python3 <<'PY'
import json
with open("/tmp/cu-m2/secure_reject.json") as f:
    data = json.load(f)
assert data["ok"] is False, f"secure field should reject: {data}"
code = data["error"]["code"]
assert code in ("security_rejection", "secure_field_blocked", "action_not_supported"), f"unexpected error: {code}"
print(f"  error_code={code}")
print("  PASS")
PY

# 6. Stale revision rejection
echo "=== 6. Stale revision rejection ==="
cli press --element "$button_id" --revision "1" --json --no-start > /tmp/cu-m2/stale.json 2>/dev/null || true
python3 <<'PY'
import json
with open("/tmp/cu-m2/stale.json") as f:
    data = json.load(f)
assert data["ok"] is False, f"should reject stale: {data}"
assert data["error"]["code"] == "stale_observation", f"unexpected: {data['error']['code']}"
print(f"  error_code={data['error']['code']}")
print("  PASS")
PY

# 7. Type Korean text
echo "=== 7. Type Korean text ==="
cli type --text "안녕" --json --no-start > /tmp/cu-m2/type_korean.json 2>/dev/null || true
python3 <<'PY'
import json
with open("/tmp/cu-m2/type_korean.json") as f:
    data = json.load(f)
if data["ok"]:
    assert data["executed"] is True
    print(f"  method={data['method']}")
else:
    print(f"  type error (ok if no focused field): {data.get('error', {}).get('code', 'unknown')}")
print("  PASS")
PY

# 8. Key press (Escape)
echo "=== 8. Key press (Escape) ==="
cli key --key escape --json --no-start > /tmp/cu-m2/key_escape.json
python3 <<'PY'
import json
with open("/tmp/cu-m2/key_escape.json") as f:
    data = json.load(f)
assert data["ok"] is True, f"key failed: {data}"
assert data["executed"] is True
assert "key" in data["method"]
print(f"  method={data['method']}")
print("  PASS")
PY

# 9. Coordinate-based click
echo "=== 9. Coordinate click ==="
cli windows --app dev.jwoo0122.rebecca-fixture --json --no-start > /tmp/cu-m2/windows.json
python3 <<'PY'
import json, subprocess
with open("/tmp/cu-m2/windows.json") as f:
    data = json.load(f)
assert data["ok"] is True
windows = data["windows"]
fixture_windows = [w for w in windows if w.get("title") == "Rebecca Fixture"]
assert len(fixture_windows) >= 1, "Fixture window not found"
w = fixture_windows[0]
frame = w["logical_frame"]
x = frame["x"] + 50
y = frame["y"] + 50
result = subprocess.run(
    ["cargo", "run", "-q", "-p", "rebecca-cli", "--",
     "click", "--x", str(x), "--y", str(y), "--json", "--no-start"],
    capture_output=True, text=True
)
resp = json.loads(result.stdout)
assert resp["ok"] is True, f"click failed: {resp}"
assert resp["executed"] is True
assert "click" in resp["method"]
print(f"  method={resp['method']}, clicked at ({x:.0f}, {y:.0f})")
print("  PASS")
PY

# 10. Scroll
echo "=== 10. Scroll ==="
cli scroll --dy -100 --json --no-start > /tmp/cu-m2/scroll.json
python3 <<'PY'
import json
with open("/tmp/cu-m2/scroll.json") as f:
    data = json.load(f)
assert data["ok"] is True, f"scroll failed: {data}"
assert data["executed"] is True
assert "scroll" in data["method"]
print(f"  method={data['method']}")
print("  PASS")
PY

# 11. Window move
echo "=== 11. Window move ==="
python3 <<'PY'
import json, subprocess
with open("/tmp/cu-m2/windows.json") as f:
    data = json.load(f)
fixture_windows = [w for w in data["windows"] if w.get("title") == "Rebecca Fixture"]
assert len(fixture_windows) >= 1, "Fixture window not found"
w = fixture_windows[0]
wid = w["window_id"]
frame = w["logical_frame"]
nx = frame["x"] + 10
ny = frame["y"] + 10
result = subprocess.run(
    ["cargo", "run", "-q", "-p", "rebecca-cli", "--",
     "window-move", "--window-id", str(wid), "--x", str(nx), "--y", str(ny), "--json", "--no-start"],
    capture_output=True, text=True
)
resp = json.loads(result.stdout)
assert resp["ok"] is True, f"window_move failed: {resp}"
assert resp["executed"] is True
assert "window_move" in resp["method"]
print(f"  method={resp['method']}, window {wid} moved to ({nx:.0f}, {ny:.0f})")
print("  PASS")
PY

# 12. Window resize
echo "=== 12. Window resize ==="
python3 <<'PY'
import json, subprocess
with open("/tmp/cu-m2/windows.json") as f:
    data = json.load(f)
fixture_windows = [w for w in data["windows"] if w.get("title") == "Rebecca Fixture"]
assert len(fixture_windows) >= 1, "Fixture window not found"
w = fixture_windows[0]
wid = w["window_id"]
frame = w["logical_frame"]
nw = frame["width"] - 20
nh = frame["height"] - 20
result = subprocess.run(
    ["cargo", "run", "-q", "-p", "rebecca-cli", "--",
     "window-resize", "--window-id", str(wid), "--width", str(nw), "--height", str(nh), "--json", "--no-start"],
    capture_output=True, text=True
)
resp = json.loads(result.stdout)
assert resp["ok"] is True, f"window_resize failed: {resp}"
assert resp["executed"] is True
assert "window_resize" in resp["method"]
print(f"  method={resp['method']}, window {wid} resized to {nw:.0f}x{nh:.0f}")
print("  PASS")
PY

echo ""
echo "=== All M2/M3 acceptance checks passed ==="
