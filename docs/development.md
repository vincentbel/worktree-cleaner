# Development

## Requirements

- macOS 14 or later
- Xcode with the Swift 6 toolchain
- `/usr/bin/git` with `git worktree list --porcelain -z` support

The application target is intentionally thin. Git behavior and domain models
belong in the local package at `Packages/WorktreeCore` unless they are strictly
presentation concerns.

## Open and run in Xcode

From the repository root, open the project:

```sh
open WorktreeCleaner.xcodeproj
```

Select the `WorktreeCleaner` scheme and the `My Mac` destination, then press
Command-R. In the running app, select **Choose Directory** to add a scan directory
that contains Git projects.

## Command-line build

Build the native application without requiring a signing identity:

```sh
xcodebuild \
  -project WorktreeCleaner.xcodeproj \
  -scheme WorktreeCleaner \
  -configuration Debug \
  -derivedDataPath /tmp/worktree-cleaner-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Launch that exact build for manual verification:

```sh
open -n /tmp/worktree-cleaner-derived/Build/Products/Debug/WorktreeCleaner.app
```

## Screenshot demo data

Generate disposable Git repositories and launch the Debug app with privacy-safe
demo data:

```sh
./scripts/run-demo.sh
```

The script rebuilds `/private/tmp/worktree-cleaner-demo`, creates repositories
covering the main cleanup states, builds the app, and opens it with
`--demo-directory` in English for the README screenshot. Demo mode ignores the
saved scan directories and workspace cache without changing them. A normal
launch returns to the saved workspace.

Demo mode uses a light appearance and starts with automatic update checks disabled.
Set the demo language and scan directory for localized introduction images:

```sh
WORKTREE_DEMO_LANGUAGE=zh-Hans \
WORKTREE_DEMO_ROOT=/tmp/worktree-cleaner-intro/repos \
  ./scripts/run-demo.sh
```

For the location-discovery image, generate one repository with linked worktrees
in a tool directory, a temporary directory, and beside the main worktree:

```sh
WORKTREE_DEMO_LANGUAGE=zh-Hans \
WORKTREE_DEMO_SCENARIO=locations \
WORKTREE_DEMO_ROOT=/tmp/wtc-demo-home \
  ./scripts/run-demo.sh
```

This scenario scans only the `repos` subdirectory. Git registration supplies
the worktrees outside that scan directory. The temporary worktree has a separate
ownership marker so reruns replace only generated demo data.

For the disk-usage image, generate one repository with three worktrees and
different amounts of ignored dependencies or build products:

```sh
WORKTREE_DEMO_LANGUAGE=zh-Hans \
WORKTREE_DEMO_SCENARIO=disk-usage \
WORKTREE_DEMO_ROOT=/tmp/worktree-cleaner-disk-demo \
  ./scripts/run-demo.sh
```

This scenario writes 528 MiB of disposable files. The app measures their actual
allocated disk space; all three worktrees remain clean.

For the cleanup-decision and batch-confirmation images, generate one repository
with a merged worktree, an unmerged branch, and uncommitted work:

```sh
WORKTREE_DEMO_LANGUAGE=zh-Hans \
WORKTREE_DEMO_SCENARIO=decision \
WORKTREE_DEMO_ROOT=/tmp/worktree-cleaner-decision-demo \
  ./scripts/run-demo.sh
```

The two clean linked worktrees can be selected for batch cleanup. The worktree
with uncommitted changes is protected. Open the confirmation sheet to capture
the merged/unmerged breakdown and the branch-preservation message.

To reuse generated data with an existing Debug build, pass the scan directory
directly (use the `repos` subdirectory for the `locations` scenario):

```sh
open -n /tmp/worktree-cleaner-demo-derived/Build/Products/Debug/WorktreeCleaner.app \
  --args -AppleLanguages '(zh-Hans)' --demo-directory /tmp/worktree-cleaner-demo
```

All demo argument handling, startup behavior, and workspace persistence overrides
are guarded by `#if DEBUG`. Release builds compile them out entirely. The demo
script and generated repositories live outside the app target and are never
copied into the app bundle. The release script checks the exported app for demo
symbols, argument strings, and fixture content before packaging it. Run the same
check on a local Release build with:

```sh
./scripts/verify-no-demo.sh /path/to/Release/WorktreeCleaner.app
```

## Tests and formatting

Run the core integration tests:

```sh
swift test --package-path Packages/WorktreeCore
```

Check formatting:

```sh
swift format lint --recursive \
  Packages/WorktreeCore/Sources \
  Packages/WorktreeCore/Tests \
  WorktreeCleaner
```

Tests create temporary real repositories and invoke `/usr/bin/git`. They must
observe behavior through the public `GitWorkspace` interface rather than mock
the internal command runner or output parser.

## Xcode setup troubleshooting

If `xcodebuild` reports `IDESimulatorFoundation` or `DVTDownloads` errors, open
Xcode and allow its first-launch components to finish installing. If the error
continues, update or reinstall the Xcode version that matches the current macOS
version before changing the project as a workaround.

## Release builds

Developer ID signing, notarization, Sparkle appcast generation, and publishing
are documented in [releasing.md](releasing.md).

## Change discipline

- Add one failing behavior test before changing `WorktreeCore` behavior.
- Do not put Git commands or cleanup policy in SwiftUI views.
- Do not add forced removal or implicit branch deletion.
- Update `architecture.md` when a decision changes and `development-log.md` when
  implementation reveals a material constraint or safety edge case.
