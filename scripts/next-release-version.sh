#!/usr/bin/env bash
set -euo pipefail

latest_tag="$(git tag --list 'v[0-9]*' --sort=-version:refname | head -n 1)"
if [[ -z "$latest_tag" ]]; then
  echo "error: no semantic version tag found" >&2
  exit 1
fi

version="${latest_tag#v}"
IFS=. read -r major minor patch <<< "$version"
if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "$patch" =~ ^[0-9]+$ ]]; then
  echo "error: invalid semantic version tag: $latest_tag" >&2
  exit 1
fi

bump=none
while IFS= read -r commit; do
  subject="$(git log -1 --format=%s "$commit")"
  body="$(git log -1 --format=%b "$commit")"
  breaking_subject='^[[:alnum:]_-]+(\([^)]*\))?!:'
  feat_subject='^feat(\([^)]*\))?:'
  patch_subject='^(fix|perf)(\([^)]*\))?:'

  if grep -Eq 'BREAKING[- ]CHANGE([ :]|$)' <<< "$body" || \
    [[ "$subject" =~ $breaking_subject ]]; then
    bump=major
    continue
  fi

  if [[ "$subject" =~ $feat_subject ]]; then
    [[ "$bump" == major ]] || bump=minor
  elif [[ "$subject" =~ $patch_subject ]]; then
    [[ "$bump" == major || "$bump" == minor ]] || bump=patch
  fi
done < <(git rev-list "$latest_tag..HEAD")

case "$bump" in
  major)
    ((major += 1))
    minor=0
    patch=0
    ;;
  minor)
    ((minor += 1))
    patch=0
    ;;
  patch)
    ((patch += 1))
    ;;
  none)
    exit 0
    ;;
esac

printf '%d.%d.%d\n' "$major" "$minor" "$patch"
