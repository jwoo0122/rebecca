#!/usr/bin/env bash
set -euo pipefail

export MACOSX_DEPLOYMENT_TARGET=15.0
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root
readonly target="arm64-apple-macosx15.0"
readonly app="$root/build/RebeccaFixture.app"
readonly contents="$app/Contents"
readonly executable="$contents/MacOS/rebecca-fixture"

rm -rf "$app"
mkdir -p "$contents/MacOS"
cp "$root/fixture/Info.plist" "$contents/Info.plist"

swiftc \
  -parse-as-library \
  -target "$target" \
  -framework AppKit \
  "$root/fixture/Sources/main.swift" \
  -o "$executable"

plutil -lint "$contents/Info.plist" >/dev/null
lipo -archs "$executable" | grep -qw arm64
