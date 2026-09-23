#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <application-path> <dmg-path>" >&2
  exit 64
fi

application_path="$1"
disk_image="$2"

if [[ ! -d "$application_path" || "$application_path" != *.app ]]; then
  echo "Application bundle not found: $application_path" >&2
  exit 66
fi

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/worktree-cleaner-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT

ditto "$application_path" "$staging_directory/WorktreeCleaner.app"
ln -s /Applications "$staging_directory/Applications"
hdiutil create \
  -volname "Worktree Cleaner" \
  -srcfolder "$staging_directory" \
  -fs HFS+ \
  -format UDZO \
  "$disk_image"
