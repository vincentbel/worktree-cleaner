#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <version> [updates-directory]" >&2
  exit 64
fi

release_version="$1"

if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "Version must use x.y.z or x.y.z-prerelease format: $release_version" >&2
  exit 64
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
updates_directory="${2:-$repository_root/build/release/$release_version/updates}"
release_repository="${RELEASE_REPOSITORY:-vincentbel/worktree-cleaner}"
update_archive="$updates_directory/WorktreeCleaner-${release_version}.zip"
appcast="$updates_directory/appcast.xml"
release_notes="$updates_directory/WorktreeCleaner-${release_version}.md"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required." >&2
  exit 69
fi

if [[ ! -f "$update_archive" || ! -f "$appcast" ]]; then
  echo "Missing release archive or appcast in $updates_directory" >&2
  exit 66
fi

visibility="$(gh repo view "$release_repository" --json visibility --jq .visibility)"
if [[ "$visibility" != "PUBLIC" ]]; then
  echo "Sparkle's token-free endpoint requires a PUBLIC repository:" >&2
  echo "  $release_repository" >&2
  exit 77
fi

default_branch="$(gh repo view "$release_repository" --json defaultBranchRef --jq .defaultBranchRef.name)"
if [[ -z "$default_branch" ]]; then
  echo "Initialize $release_repository with a default branch before publishing." >&2
  exit 65
fi

release_notes_options=(--notes "Worktree Cleaner $release_version")
if [[ -f "$release_notes" ]]; then
  release_notes_options=(--notes-file "$release_notes")
fi

create_state_options=(--draft)
publish_state_options=(--draft=false --latest)
published_appcast="https://github.com/$release_repository/releases/latest/download/appcast.xml"
if [[ "$release_version" == *-* ]]; then
  create_state_options+=(--prerelease)
  publish_state_options=(--draft=false --prerelease)
  published_appcast="https://github.com/$release_repository/releases/download/v$release_version/appcast.xml"
fi

gh release create \
  "v$release_version" \
  "$update_archive#Worktree Cleaner $release_version" \
  "$appcast#Sparkle appcast" \
  --repo "$release_repository" \
  --target "$default_branch" \
  --title "Worktree Cleaner $release_version" \
  "${create_state_options[@]}" \
  "${release_notes_options[@]}"

gh release edit \
  "v$release_version" \
  --repo "$release_repository" \
  "${publish_state_options[@]}"

echo "Published Worktree Cleaner $release_version to $release_repository."
echo "Feed: $published_appcast"
