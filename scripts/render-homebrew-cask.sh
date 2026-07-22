#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
sha256="${2:-}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 VERSION SHA256" >&2
  exit 2
fi
if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "usage: $0 VERSION SHA256" >&2
  exit 2
fi

cat <<CASK
cask "rebecca" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/jwoo0122/rebecca/releases/download/v#{version}/Rebecca-v#{version}.zip"
  name "Rebecca"
  desc "macOS GUI automation tool for AI agents"
  homepage "https://github.com/jwoo0122/rebecca"

  app "Rebecca.app"
  binary "Rebecca.app/Contents/Resources/bin/rebecca"

  uninstall delete: [
    "~/Library/Application Support/Rebecca",
  ]

  zap trash: [
    "~/Library/Application Support/Rebecca",
    "~/Library/Preferences/dev.jwoo0122.rebecca.plist",
  ]
end
CASK
