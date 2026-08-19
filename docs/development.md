# Development

## Requirements

- macOS 14 or later
- Xcode with the Swift 6 toolchain
- `/usr/bin/git` with `git worktree list --porcelain -z` support

The application target is intentionally thin. Git behavior and domain models
belong in the local package at `Packages/WorktreeCore` unless they are strictly
presentation concerns.

## Verification commands

Run core integration tests:

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

After each completed application change, build successfully and launch that
exact product for user verification:

```sh
open -n /tmp/worktree-cleaner-derived/Build/Products/Debug/WorktreeCleaner.app
```

Developer ID signing, notarization, Sparkle appcast generation, and publishing
are documented in [releasing.md](releasing.md).

Tests create temporary real repositories and invoke `/usr/bin/git`. They must
observe behavior through the public `GitWorkspace` interface rather than mock
the internal command runner or output parser.

## Change discipline

- Add one failing behavior test before changing `WorktreeCore` behavior.
- Do not put Git commands or cleanup policy in SwiftUI views.
- Do not add forced removal or implicit branch deletion.
- Update `architecture.md` when a decision changes and `development-log.md` when
  implementation reveals a material constraint or safety edge case.
