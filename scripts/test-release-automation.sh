#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version_script="$root/scripts/next-release-version.sh"
cask_script="$root/scripts/render-homebrew-cask.sh"

new_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  printf '%s\n' "$dir"
}

commit() {
  local dir=$1 message=$2
  printf '%s\n' "$message" >> "$dir/CHANGELOG"
  git -C "$dir" add CHANGELOG
  git -C "$dir" commit -q -m "$message"
}

repo="$(new_repo)"
trap 'rm -rf "$repo"' EXIT
commit "$repo" 'chore: initial repository'
git -C "$repo" -c tag.gpgSign=false tag -f v1.2.3

[[ -z "$(cd "$repo" && "$version_script")" ]]
commit "$repo" 'docs: clarify installation'
[[ -z "$(cd "$repo" && "$version_script")" ]]
commit "$repo" 'fix: handle missing socket'
[[ "$(cd "$repo" && "$version_script")" == 1.2.4 ]]

git -C "$repo" -c tag.gpgSign=false tag -f v1.2.3
commit "$repo" 'feat: add cask installation'
[[ "$(cd "$repo" && "$version_script")" == 1.3.0 ]]

git -C "$repo" -c tag.gpgSign=false tag -f v1.2.3
commit "$repo" $'feat!: change release boundary\n\nBREAKING CHANGE: installation path changed'
[[ "$(cd "$repo" && "$version_script")" == 2.0.0 ]]

cask="$($cask_script 1.2.3 d0bd76dd0133b04b144df8ae31044f6ae740dad5edc689d1db1fe574e80d1190)"
grep -Fq 'version "1.2.3"' <<< "$cask"
grep -Fq 'sha256 "d0bd76dd0133b04b144df8ae31044f6ae740dad5edc689d1db1fe574e80d1190"' <<< "$cask"
grep -Fq 'Rebecca-v#{version}.zip' <<< "$cask"
grep -Fq 'binary "Rebecca.app/Contents/Resources/bin/rebecca"' <<< "$cask"

echo 'release automation tests passed'
