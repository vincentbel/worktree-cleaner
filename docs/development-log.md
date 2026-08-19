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
- Added allocated-byte disk usage for each worktree (excluding its own `.git`)
  and for shared Git data. Worktrees at or above 5 GB are highlighted, but size
  does not affect cleanup eligibility.
- Discovery of a registered worktree whose directory was deleted externally
  originally caused the entire repository snapshot to fail. Inspection now asks
  Git to evaluate records with `--expire now`, preserves the missing worktree as
  a prunable record, and skips status and disk traversal for the absent path.
- Added single-worktree removal. The public operation refreshes the snapshot as
  a final preflight, accepts only a current `cleanable` recommendation, invokes
  `git worktree remove` without force, preserves the branch, and returns a fresh
  snapshot.
- The first discovery implementation accumulated every `.git` candidate before
  publishing any result and descended into dependency/build output. On large
  development roots this could leave the window empty for over a minute.
  Discovery now streams each validated logical repository immediately and
  prunes common generated, dependency, cache, and build directories.
- A discovered Git repository does not terminate traversal: ordinary child
  directories are still scanned so nested repositories and submodules appear.
  Only `.git` metadata, symbolic links, and the explicit generated-directory
  name set are pruned.
- Disk traversal no longer blocks the initial repository snapshot. Worktree and
  shared Git allocated-byte results are delivered as a second stream and update
  the detail table incrementally. Switching roots or repositories invalidates
  stale scan, snapshot, and disk results.
- The host Xcode installation now completes the command-line macOS application
  build successfully; the earlier `IDESimulatorFoundation` issue is no longer a
  current local blocker.
- Worktree rows now keep their trailing operation controls visible while the
  data columns scroll horizontally. A first layout attempt still allowed the
  content's ideal width to push the action column off-screen; constraining the
  scroll area from the available geometry fixed this and was verified in the
  running app.
- Added native path actions based on the referenced e-tars target list. The app
  detects installed editors and terminals in system, global, and per-user
  application locations, uses their bundle icons, and opens paths with
  `NSWorkspace`. Finder and path copying are included.
- Clean linked worktrees with commits not merged into the configured cleanup
  target can now be explicitly removed. They keep the "needs review" status and
  require a stronger warning; main, dirty, locked, missing, and unknown-target
  cases remain blocked. Removal shows an in-row progress indicator, returns a
  fresh snapshot, and reports success or failure to the user.
- Repository discovery now derives each project's extra linked-worktree count
  from the `git worktree list` output it already fetched. The sidebar groups
  projects with extra worktrees first, shows that count, and moves muted
  main-only projects to the bottom without adding per-project status commands.
  A refreshed post-removal snapshot updates the grouping immediately.
- Path copying now uses a non-blocking 1.5-second toast instead of an alert that
  requires another click. The sidebar grouping and muted styling were verified
  in the running native app.
