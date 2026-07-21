#!/usr/bin/env bash
set -euo pipefail

app="${1:-dist/Rebecca.app}"

if [[ ! -d "$app" ]]; then
  echo "error: App bundle not found: $app" >&2
  exit 1
fi

echo "Verifying $app"

# Bundle structure
test -d "$app"
test -f "$app/Contents/Info.plist"
test -x "$app/Contents/MacOS/Rebecca"
echo "  Bundle structure: OK"

# Plist validation
plutil -lint "$app/Contents/Info.plist" >/dev/null
echo "  Info.plist: OK"

# Plist keys
bundle_id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" 2>/dev/null || echo "")
bundle_name=$(plutil -extract CFBundleName raw "$app/Contents/Info.plist" 2>/dev/null || echo "")
bundle_exec=$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist" 2>/dev/null || echo "")
min_version=$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist" 2>/dev/null || echo "")

[[ "$bundle_id" == "dev.jwoo0122.rebecca" ]] || { echo "  FAIL: CFBundleIdentifier=$bundle_id"; exit 1; }
[[ "$bundle_name" == "Rebecca" ]] || { echo "  FAIL: CFBundleName=$bundle_name"; exit 1; }
[[ "$bundle_exec" == "Rebecca" ]] || { echo "  FAIL: CFBundleExecutable=$bundle_exec"; exit 1; }
[[ -n "$min_version" ]] || { echo "  FAIL: LSMinimumSystemVersion missing"; exit 1; }
echo "  Bundle ID: $bundle_id"
echo "  Bundle name: $bundle_name"
echo "  Executable: $bundle_exec"
echo "  Min OS version: $min_version"

# Architecture
echo "  Architecture: $(lipo -archs "$app/Contents/MacOS/Rebecca")"

# Resources
[[ -f "$app/Contents/Resources/SKILL.md" ]] && echo "  SKILL.md: present" || echo "  SKILL.md: MISSING"
if [[ -f "$app/Contents/Resources/Assets.car" ]] || find "$app" -name "*.icns" -quit 2>/dev/null; then echo "  Icon: present"; else echo "  Icon: MISSING"; fi
[[ -f "$app/Contents/Resources/bin/rebecca" ]] && echo "  CLI binary: present" || echo "  CLI binary: MISSING"
[[ -f "$app/Contents/Resources/schemas/protocol-v1.json" ]] && echo "  Schema: present" || echo "  Schema: MISSING"

# Code signing (skip if unsigned)
if codesign --verify --deep --strict "$app" 2>/dev/null; then
  echo "  Code signing: verified"
else
  echo "  Code signing: unsigned (development build)"
fi

echo ""
echo "Verification complete."
