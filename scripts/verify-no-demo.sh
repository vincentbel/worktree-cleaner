#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! -d "$1/Contents/MacOS" ]]; then
  echo "Usage: $0 <path-to-release.app>" >&2
  exit 64
fi

readonly app_contents="$1/Contents"
readonly demo_pattern='--demo-directory|demoDirectoryURL|DemoLaunch|WORKTREE_DEMO_|generated-by-worktree-cleaner|demo@example.com|aurora-editor|nebula-api'

if matches="$(LC_ALL=C grep -aERl -- "$demo_pattern" "$app_contents")"; then
  echo "Demo code or fixture content found in the release app:" >&2
  echo "$matches" >&2
  exit 1
else
  status=$?
  if [[ $status -ne 1 ]]; then
    exit "$status"
  fi
fi

demo_paths="$(find "$app_contents" -iname '*demo*' -print)"
if [[ -n "$demo_paths" ]]; then
  echo "Demo files found in the release app:" >&2
  echo "$demo_paths" >&2
  exit 1
fi

echo "Release app contains no demo code or fixtures."
