#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root
readonly project="$root/macos/Rebecca.xcodeproj"
readonly config="Release"
readonly derived_data="$root/build/DerivedData"
readonly dist_dir="$root/dist"
readonly release_version="${REBECCA_RELEASE_VERSION:-0.1.0}"

# Use Xcode beta if available
if [[ -x "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
elif ! command -v xcodebuild &>/dev/null; then
  echo "error: Xcode is required but not found" >&2
  echo "Install Xcode or set DEVELOPER_DIR" >&2
  exit 1
fi

# Build Rust CLI binary
echo "Building Rust CLI binary..."
BUILD_PROFILE="${REBECCA_BUILD_PROFILE:-dev}"
cargo build --locked --profile "$BUILD_PROFILE"

# Ensure Xcode project exists
if [[ ! -d "$project" ]]; then
  echo "error: Xcode project not found at $project" >&2
  echo "Open Xcode and create the project, or run xcodegen." >&2
  exit 1
fi

# Build the app with xcodebuild (respects Xcode project settings as-is)
echo "Building Rebecca.app..."
xcodebuild \
  -project "$project" \
  -scheme Rebecca \
  -configuration "$config" \
  -derivedDataPath "$derived_data" \
  -destination 'platform=macOS' \
  MARKETING_VERSION="$release_version" \
  CURRENT_PROJECT_VERSION="1" \
  build

# Locate the built app
built_app="$derived_data/Build/Products/$config/Rebecca.app"
if [[ ! -d "$built_app" ]]; then
  echo "error: Build product not found at $built_app" >&2
  exit 1
fi

# Copy resources not handled by Xcode into the bundle
echo "Copying resources..."
resources_dir="$built_app/Contents/Resources"
mkdir -p "$resources_dir/schemas"
cp "$root/resources/SKILL.md" "$resources_dir/SKILL.md"
cp "$root/schemas/protocol-v1.json" "$resources_dir/schemas/protocol-v1.json"

# Copy Rust CLI binary into the bundle
echo "Copying CLI binary..."
mkdir -p "$resources_dir/bin"
# Map profile name to target directory (dev -> debug, release -> release)
if [[ "$BUILD_PROFILE" == "dev" ]]; then
  TARGET_DIR="debug"
else
  TARGET_DIR="$BUILD_PROFILE"
fi
cp "$root/target/$TARGET_DIR/rebecca" "$resources_dir/bin/rebecca"
chmod +x "$resources_dir/bin/rebecca"

# Verify
echo "Verifying..."
test -f "$built_app/Contents/Info.plist"
test -x "$built_app/Contents/MacOS/Rebecca"
plutil -lint "$built_app/Contents/Info.plist" >/dev/null

# Copy to dist/
mkdir -p "$dist_dir"
rm -rf "$dist_dir/Rebecca.app"
cp -R "$built_app" "$dist_dir/Rebecca.app"

echo ""
echo "Build succeeded: $dist_dir/Rebecca.app"
echo "Executable: $(file "$dist_dir/Rebecca.app/Contents/MacOS/Rebecca" | cut -d: -f2)"
