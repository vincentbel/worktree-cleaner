# Development Log

This is a concise record of implementation discoveries that affect architecture,
scope, safety, or future agent work. Routine code changes belong in Git history
instead.

## 2026-08-19

- Confirmed Swift 6, SwiftUI, macOS 14+, a standard Xcode app target, and a local
  `WorktreeCore` Swift package.
- Confirmed direct Developer ID/notarized distribution with App Sandbox disabled
  for the first version.
- Confirmed the public test seam as `WorktreeCore.GitWorkspace`.
- Confirmed a conservative cleanup policy: no forced removal, no implicit branch
  deletion, and a final preflight check before mutation.
- The repository started with only `.gitignore`; no pre-existing application
  structure or coding convention needed migration.
- Added the native Xcode application shell and local `WorktreeCore` package.
- Implemented the first read-only vertical slice: recursive discovery, common
  Git directory deduplication, worktree parsing, dirty/locked state, and a
  conservative local-ref cleanup recommendation.
- Adopted the Swift toolchain formatter with 2-space indentation and a 100-column
  line length as the repository formatting baseline.
- Local environment issue: `xcodebuild` currently fails before project loading
  because Xcode 26.6's `IDESimulatorFoundation` cannot resolve a symbol from the
  installed `DVTDownloads` framework. `swift test`, project plist validation,
  and direct SwiftUI source type-checking succeed. Do not run
  `xcodebuild -runFirstLaunch` or modify the host Xcode installation without
  explicit approval; repeat the application build after the host toolchain is
  repaired.
