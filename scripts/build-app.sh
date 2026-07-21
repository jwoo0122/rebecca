#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root

# Milestone 0 supports only macOS 15+ on Apple Silicon.
export MACOSX_DEPLOYMENT_TARGET=15.0
readonly target="arm64-apple-macosx15.0"
readonly app="build/Rebecca.app"
readonly macos_dir="$app/Contents/MacOS"
readonly resources_dir="$app/Contents/Resources"

rm -rf "$app"
mkdir -p "$macos_dir" "$resources_dir/schemas"
cp host/Info.plist "$app/Contents/Info.plist"
cp schemas/protocol-v1.json "$resources_dir/schemas/protocol-v1.json"
cp "$root/resources/SKILL.md" "$resources_dir/SKILL.md"
cp "$root/resources/Rebecca.icns" "$resources_dir/Rebecca.icns"

swiftc \
  -parse-as-library \
  -target "$target" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework ScreenCaptureKit \
  host/Sources/PermissionState.swift host/Sources/SocketSupport.swift host/Sources/StatusWindow.swift host/Sources/ShareableContentSupport.swift host/Sources/DisplaySupport.swift host/Sources/DisplayRevision.swift host/Sources/WindowSupport.swift host/Sources/CaptureSupport.swift host/Sources/AppSupport.swift host/Sources/FocusSupport.swift host/Sources/TreeSupport.swift host/Sources/ActionSupport.swift host/Sources/CGEventSupport.swift host/Sources/WindowControlSupport.swift host/Sources/AuditLogSupport.swift host/Sources/AppMain.swift \
  -o "$macos_dir/rebecca-host"

plutil -lint "$app/Contents/Info.plist" >/dev/null
lipo -archs "$macos_dir/rebecca-host" | grep -qw arm64

# Sign with a stable self-signed certificate so TCC permissions persist across rebuilds.
# Run scripts/setup-signing.sh once before the first build.
codesign --force --sign "Rebecca-Dev" --options runtime "$app" 2>/dev/null || true
