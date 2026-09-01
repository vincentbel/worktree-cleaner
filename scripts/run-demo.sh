#!/bin/bash

set -euo pipefail

readonly demo_root="/tmp/worktree-cleaner-demo"
readonly demo_marker="$demo_root/.generated-by-worktree-cleaner"
readonly derived_data="/tmp/worktree-cleaner-demo-derived"
readonly app_path="$derived_data/Build/Products/Debug/WorktreeCleaner.app"

if [[ -e "$demo_root" && ! -f "$demo_marker" ]]; then
  echo "Refusing to replace $demo_root because it was not created by this script." >&2
  exit 1
fi

rm -rf "$demo_root"
mkdir -p "$demo_root/.remotes"
touch "$demo_marker"

git_quiet() {
  if ! git "$@" >/dev/null 2>&1; then
    echo "Git command failed: git $*" >&2
    return 1
  fi
}

configure_repository() {
  local repository="$1"
  git_quiet -C "$repository" config user.name "Demo Developer"
  git_quiet -C "$repository" config user.email "demo@example.com"
}

write_demo_file() {
  local repository="$1"
  local relative_path="$2"
  local contents="$3"
  mkdir -p "$(dirname "$repository/$relative_path")"
  printf '%s\n' "$contents" > "$repository/$relative_path"
}

commit_demo_file() {
  local repository="$1"
  local relative_path="$2"
  local contents="$3"
  local message="$4"
  write_demo_file "$repository" "$relative_path" "$contents"
  git_quiet -C "$repository" add "$relative_path"
  git_quiet -C "$repository" commit -m "$message"
}

create_repository() {
  local name="$1"
  local remote="$demo_root/.remotes/$name.git"
  local repository="$demo_root/$name"

  git_quiet init --bare --initial-branch=main "$remote"
  git_quiet clone "$remote" "$repository"
  configure_repository "$repository"
  commit_demo_file \
    "$repository" \
    "README.md" \
    "# ${name//-/ }\n\nA privacy-safe demo repository for Worktree Cleaner." \
    "Create demo project"
  commit_demo_file \
    "$repository" \
    "Sources/App.swift" \
    "struct DemoApp { let isReady = true }" \
    "Add application entry point"
  commit_demo_file \
    "$repository" \
    ".gitignore" \
    "Assets/*.bin" \
    "Ignore generated demo assets"
  git_quiet -C "$repository" push -u origin main
  git_quiet -C "$repository" remote set-head origin main
}

add_clean_merged_worktree() {
  local repository="$1"
  local branch="$2"
  local directory="$3"

  git_quiet -C "$repository" worktree add -b "$branch" "$directory"
  commit_demo_file \
    "$directory" \
    "Sources/CompletedFeature.swift" \
    "struct CompletedFeature { let enabled = true }" \
    "Complete feature"
  git_quiet -C "$repository" merge --no-ff "$branch" -m "Merge $branch"
  git_quiet -C "$repository" push origin main
}

add_clean_unmerged_worktree() {
  local repository="$1"
  local branch="$2"
  local directory="$3"

  git_quiet -C "$repository" worktree add -b "$branch" "$directory"
  commit_demo_file \
    "$directory" \
    "Sources/Experiment.swift" \
    "struct Experiment { let variant = \"B\" }" \
    "Prototype experiment"
}

create_repository "aurora-editor"
aurora="$demo_root/aurora-editor"

add_clean_merged_worktree \
  "$aurora" \
  "feature/completed-dashboard" \
  "$demo_root/aurora-completed-dashboard"
add_clean_unmerged_worktree \
  "$aurora" \
  "feature/live-preview" \
  "$demo_root/aurora-live-preview"

git_quiet -C "$aurora" worktree add -b "fix/sidebar-spacing" "$demo_root/aurora-sidebar-spacing"
write_demo_file \
  "$demo_root/aurora-sidebar-spacing" \
  "Sources/Sidebar.swift" \
  "struct Sidebar { let spacing = 12 }"

git_quiet -C "$aurora" worktree add -b "feature/search-index" "$demo_root/aurora-search-index"
write_demo_file \
  "$demo_root/aurora-search-index" \
  "Sources/SearchIndex.swift" \
  "struct SearchIndex { let batchSize = 100 }"
git_quiet -C "$demo_root/aurora-search-index" add "Sources/SearchIndex.swift"

git_quiet -C "$aurora" worktree add -b "release/2.4" "$demo_root/aurora-release-2.4"
git_quiet -C "$aurora" worktree lock \
  --reason "Kept for the upcoming release" \
  "$demo_root/aurora-release-2.4"

git_quiet -C "$aurora" worktree add --detach "$demo_root/aurora-detached-experiment"
commit_demo_file \
  "$demo_root/aurora-detached-experiment" \
  "Sources/DetachedExperiment.swift" \
  "struct DetachedExperiment { let score = 0.98 }" \
  "Try detached experiment"

git_quiet -C "$aurora" worktree add -b "chore/retired-assets" "$demo_root/aurora-retired-assets"
rm -rf "$demo_root/aurora-retired-assets"

create_repository "nebula-api"
add_clean_merged_worktree \
  "$demo_root/nebula-api" \
  "feature/request-tracing" \
  "$demo_root/nebula-request-tracing"
add_clean_unmerged_worktree \
  "$demo_root/nebula-api" \
  "feature/rate-limits" \
  "$demo_root/nebula-rate-limits"

create_repository "pixel-dashboard"
add_clean_merged_worktree \
  "$demo_root/pixel-dashboard" \
  "feature/chart-legend" \
  "$demo_root/pixel-chart-legend"

create_repository "atlas-cli"
create_repository "comet-design-system"
create_repository "harbor-docs"
create_repository "lumen-mobile"
create_repository "orbit-analytics"
create_repository "quartz-scheduler"

mkdir -p \
  "$aurora/Assets" \
  "$demo_root/aurora-completed-dashboard/Assets" \
  "$demo_root/aurora-live-preview/Assets"
dd if=/dev/zero of="$aurora/Assets/demo-video.bin" bs=1m count=12 status=none
dd if=/dev/zero \
  of="$demo_root/aurora-completed-dashboard/Assets/demo-archive.bin" \
  bs=1m \
  count=8 \
  status=none
dd if=/dev/zero \
  of="$demo_root/aurora-live-preview/Assets/demo-preview.bin" \
  bs=1m \
  count=5 \
  status=none

xcodebuild \
  -quiet \
  -project WorktreeCleaner.xcodeproj \
  -scheme WorktreeCleaner \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

open -n "$app_path" --args -AppleLanguages '(en)' --demo-directory "$demo_root"

echo "Demo app opened with data from $demo_root"
