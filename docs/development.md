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
