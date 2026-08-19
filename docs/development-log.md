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
- Missing worktree rows explain that only stale Git metadata remains and expose
  a dedicated registration-cleanup action. The operation rechecks the selected
  record, rejects restored or locked entries, runs `git worktree prune --expire
  now`, preserves branches and existing files, then refreshes the snapshot.
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
- The worktree grid remains custom so its action column can stay fixed while data
  columns scroll. Resizable data columns are feasible by adding header drag
  handles and persisted width state; switching to SwiftUI `Table` would work
  against the fixed-action-column requirement. The Worktree column currently
  defaults to 260 points.
- Added native English and Simplified Chinese localization. The app follows the
  system language, uses English as the development-region fallback, and keeps
  `WorktreeCore` error resources in the package's own bundle.
- Localization must cover computed labels, destructive confirmations, operation
  results, and errors in addition to static SwiftUI text. Count-based labels use
  strings dictionaries for correct English singular forms. Because the app
  target defaults to `MainActor`, bundle lookup helpers used by nonisolated
  `LocalizedError` requirements must also be explicitly `nonisolated`.
- Startup and project navigation now use stale-while-revalidate behavior. A
  persisted repository list and last selection render immediately while the
  recursive scan reconciles them; in-memory snapshots render immediately when
  revisiting a project while Git status refreshes in the background.
- Toolbar actions now follow their visible scope: the trailing refresh button
  reloads only the selected project's worktree state, base-directory addition
  and recursive rescanning stay beside the sidebar scope picker, and the scan
  follows its selected root or all-roots scope. Disk measurement remains a
  separate operation.
- Directory rescanning and selected-project refresh now replace their own icons
  with fixed-size progress indicators. The former independent toolbar spinner
  was removed so every loading state stays attached to the action that caused
  it without shifting adjacent controls.
- Disk traversal is cached independently for seven days because its result does
  not need Git-status freshness. The UI shows the measurement time and offers an
  explicit recalculation button. New worktrees, expiry, and successful removal
  trigger a fresh measurement; deletion safety still performs a live Git
  preflight and never relies on cached status.
- Base-directory configuration now supports multiple non-overlapping roots.
  Repository identity remains the normalized common Git directory, while a
  separate association catalog records every root that found it; this dedupes a
  project globally without breaking directory-scoped filtering. Exact duplicate
  and parent/child roots are rejected.
- The sidebar can filter all directories or one directory, and refresh follows
  that current scope. Root scans publish progressively with at most two roots
  active at once. A directory manager exposes project counts, scan progress and
  per-root errors; removing a root changes only app configuration and cache.
- `workspaceCache` persists multiple roots, associations, scope, selection, and
  disk measurements. The app is not released yet, so obsolete single-root keys
  and cache-schema migration code were removed instead of becoming permanent
  compatibility surface.
- Repository rows now reuse complete disk-usage cache entries to show total
  measured size beside the linked-worktree count. The total includes every
  worktree directory (including the main worktree) and shared Git data, and
  stays hidden until a full measurement finishes so progressive measurements
  are not mistaken for a final total.
- Added Sparkle 2.9.6 through Swift Package Manager for direct distribution.
  The application exposes a localized native update-check command and verifies
  update archives, appcasts, and release notes with a project-specific EdDSA
  key. Developer ID export, notarization, appcast generation, and publication
  are scripted without embedding a GitHub credential in the application.
- The private source repository cannot directly serve unauthenticated GitHub
  release assets. A separate public binary-only repository is the default
  update endpoint; keeping binaries private would require an authenticated
  gateway and a per-user or per-device authorization design.
- Moved base-directory management from a modal sheet into the native macOS
  Settings scene. The main window and Settings scene share one `AppState`, while
  the Updates tab writes automatic-check and automatic-download choices through
  Sparkle's own `NSUserDefaults`-backed properties.
- Kept the sidebar's add-directory shortcut and directory-count footer. The
  shortcut opens the folder picker directly, while the footer opens the full
  directory manager in Settings.
- Automatic update checks default to on through `SUEnableAutomaticChecks=YES`.
  Providing the preference explicitly suppresses Sparkle's second-launch
  permission prompt; users can opt out later from the Updates settings tab.
