# Worktree Manager Architecture

Status: Accepted  
Last updated: 2026-08-19

## Product goal

Worktree Manager is a native macOS application for discovering Git repositories
under a user-selected directory, inspecting their worktrees, and providing
conservative cleanup recommendations. It is aimed at developers who create many
worktrees for parallel agent tasks and need one place to understand their state
and disk usage.

## Confirmed technical decisions

- Build a native macOS application with Swift 6 and SwiftUI.
- Support macOS 14 and later so the app can use Observation and
  `NavigationSplitView` without compatibility wrappers.
- Use a standard Xcode application target for the app shell and a local Swift
  package named `WorktreeCore` for Git and domain logic.
- Use Foundation `Process` to invoke Git directly. Do not use a shell or embed
  libgit2.
- Keep UI state in a small `@Observable`, `@MainActor` store. Do not introduce a
  third-party state-management framework.
- Persist the configured base-directory list plus a small, discardable cache of
  root-to-repository associations, the last scope and project selection, and
  disk-usage measurements in `UserDefaults`. Git status remains derived at
  runtime, so the first version does not need a database.
- Distribute the first version with Developer ID signing and notarization, with
  App Sandbox disabled. This allows a repository below the selected root to
  reference registered worktrees outside that root.
- Keep third-party runtime dependencies at zero for the first version.

## Module seam

`WorktreeCore.GitWorkspace` is the public seam used by the app and by integration
tests. Its initial responsibilities are deliberately small:

1. Stream logical Git repositories found below a directory.
2. Produce a Git-state worktree snapshot for a discovered repository.
3. Stream disk-usage measurements for that snapshot separately.
4. Perform a preflight check and remove an eligible linked worktree.

Git command execution, output parsing, traversal, bounded concurrency, disk
measurement, and recommendation rules remain implementation details behind this
seam. Tests exercise the public behavior against temporary real Git repositories
instead of mocking internal collaborators.

## Repository discovery

The app accepts multiple base directories. Exact duplicates and parent/child
overlaps are rejected so a subtree is not intentionally scanned twice. Each
configured root is still independent: an inaccessible root remains configured
and reports its own scan error instead of hiding cached projects from every
other root.

The scanner recursively looks for both `.git` directories and `.git` files. Each
candidate is validated with Git rather than accepted from its filesystem shape
alone. A validated logical repository is emitted immediately; the app updates
the sidebar without waiting for the rest of that directory to finish.

- `git worktree list --porcelain -z` identifies the main working-tree root and
  validates that the candidate belongs to a registered worktree set. The same
  output supplies the number of extra linked worktrees shown in the sidebar, so
  discovery does not run status checks for every repository.
- `git rev-parse --git-common-dir` identifies the shared repository metadata.
- The normalized common Git directory is the logical repository identity. This
  prevents a linked worktree from appearing as a second project in the sidebar,
  including when the main worktree and a linked worktree are discovered under
  different configured roots. The catalog retains every root association so a
  directory-scoped filter still shows the project in both places.
- Finding a repository does not stop traversal of its ordinary subdirectories,
  so nested repositories and submodules remain discoverable.
- The scanner does not descend into `.git`, does not follow directory symbolic
  links, and stops traversing common generated or dependency directories. The
  skipped names cover Swift/Xcode, Node, Python, Java, Rust, Terraform, CocoaPods,
  Carthage, vendored dependencies, and common build/cache output.
- Cancellation stops traversal between filesystem entries. Starting another
  scan for the same root supersedes its previous stream so stale results cannot
  update the UI. At most two configured roots scan concurrently; additional
  roots wait in order while each active root continues publishing repositories
  progressively.

## Worktree inspection

Machine-readable Git output is the source of truth:

- `git worktree list --porcelain -z`
- `git status --porcelain=v2 --branch -z`
- `git rev-parse`
- `git merge-base --is-ancestor`

A worktree snapshot can contain its path, HEAD, branch or detached state, main
worktree flag, lock/prunable state, tracked and untracked changes, conflicts,
upstream divergence, and cleanup recommendation. Disk usage is not part of this
blocking snapshot.

Inspection supplies `--expire now` when listing worktrees so a path deleted by
another tool remains visible immediately as a prunable Git record. Such a record
has no filesystem status or worktree disk measurement and is never eligible for
normal worktree removal.

The preferred cleanup target is `refs/remotes/origin/HEAD`. If Git cannot resolve
it, the product must ask for a project-specific target instead of guessing
`main` or `master`.

## Cleanup safety policy

The UI uses the phrase "cleanable based on local Git checks" rather than
claiming absolute safety. A high-confidence cleanup recommendation requires all
of the following:

- It is not the main worktree.
- Its directory still exists.
- It is not locked.
- It has no staged, modified, untracked, or conflicted files.
- Its HEAD is an ancestor of the selected cleanup target.
- The same checks pass again immediately before removal.

A user may also explicitly remove a clean linked worktree whose HEAD is not an
ancestor of the cleanup target. This remains a "needs review" result rather than
becoming a cleanup recommendation. The UI must name the target branch, use a
stronger destructive warning, and explain that the worktree directory cannot be
restored automatically. The final preflight still rejects main, missing, locked,
or dirty worktrees. An unavailable cleanup target is not enough evidence to
offer this override.

Removal uses `git worktree remove <absolute-path>` without `--force`. The first
version never deletes the associated branch as a side effect. Missing/prunable
administrative records are handled separately with `git worktree prune
--expire now`. Pruning requires an explicit confirmation, repeats inspection as
a preflight, rejects a restored or locked target record, and may remove every
stale unlocked registration in that repository. It never deletes branches or
existing worktree files.

This policy is intentionally conservative:

- Squash or rebase merges can produce different commit identities, so a merged
  change may remain "needs review" without hosting-provider data.
- A clean worktree may still be in use by an agent. Git state alone cannot prove
  process inactivity, so removal always requires explicit confirmation.
- Recommendations are based on local refs. Any future fetch action must be
  explicit and must report authentication or network failures.

## Disk usage

Display working-copy disk usage separately from shared Git data:

- Worktree size excludes its `.git` entry and includes ignored build products
  and dependency directories.
- The common Git directory is measured once per logical repository.
- Stream allocated-byte results from a cancellable background task. The UI shows
  the Git snapshot first and fills each worktree size plus shared Git size as the
  measurements arrive.
- Reuse a complete disk-usage measurement for up to seven days. Display its
  timestamp, remeasure when it expires or a new worktree has no cached value,
  and let the user explicitly request an earlier recalculation.
- Persist disk usage separately from Git status. Switching projects or restarting
  the app may refresh Git status in the background without traversing every file
  again; removal still invalidates the affected repository's disk cache.
- A large size can raise recommendation priority but can never make a worktree
  eligible for removal by itself.

The initial large-worktree threshold may be 5 GB. It is a transparent product
rule, not a safety rule, and can be revisited after real usage data exists.

## UI shape

The primary window uses a two-column `NavigationSplitView`:

- Sidebar: discovered logical repositories and their aggregate health. A scope
  picker switches between all configured directories and one directory without
  duplicating the project catalog. Refresh rescans the current scope.
- Repositories with extra linked worktrees appear first and show the extra
  worktree count. Repositories with only their main working tree appear in a
  muted section at the bottom. A refreshed snapshot updates this grouping after
  removal without requiring a rescan. When a complete disk measurement is
  cached, each repository row also shows total allocated bytes across all
  worktree directories (including the main worktree) and shared Git data.
- Detail: a native table of worktrees with branch, path, status, disk usage,
  recommendation, and actions.
- Worktree data can scroll horizontally, while a narrow trailing action column
  stays visible at the right edge for path actions and removal progress.
- Path actions allow copying and opening through Finder or detected developer
  applications. Detection checks system, `/Applications`, and the user's
  `Applications` directory; opening uses native `NSWorkspace` and application
  icons come from the installed app bundles.
- Copying a path reports completion with a short, non-blocking toast. Destructive
  operation results continue to use explicit feedback because they warrant more
  attention.
- Toolbar: refresh the selected project's worktree status and recommendations;
  disk measurement remains a separate detail action. Base-directory addition
  and recursive rescanning stay beside the sidebar scope picker, so scanning
  follows either the selected root or the all-roots scope. The directory manager
  shows every configured path, project count, scan progress or error, and
  removes configuration without changing Git repositories or files on disk.

The sidebar restores its cached repository list, root associations, scope, and
last selection immediately, then reconciles each root with a progressive
background scan. Adding a root scans only that root; removing one drops only its
associations and orphaned cached projects. Worktree snapshots are cached only in
memory so revisiting a project can show its previous state while Git status
refreshes. Disk measurement progress stays in the detail area and is not treated
as a blocking window-level load.

Long-running scans and inspections are asynchronous, cancellable, and never run
on the main actor.

## Localization

- The app supports English and Simplified Chinese (`zh-Hans`) through native
  bundle localization. It follows the user's macOS language order and does not
  maintain a separate in-app language preference.
- English is the Xcode development region and therefore the fallback when the
  preferred system language is not supported.
- User-facing app strings use semantic keys in `Localizable.strings`; count-based
  text uses `Localizable.stringsdict` so each language follows its own plural
  rules.
- `WorktreeCore` owns localized descriptions for its public errors in SwiftPM
  resources. This keeps domain errors localized without coupling the package to
  the application bundle.

## Verification

- `swift test` verifies `WorktreeCore` through its public seam using temporary
  real repositories.
- Tests cover normal repositories, linked worktrees, common-directory deduping,
  detached/dirty/locked states, unusual paths, and cleanup ancestry as those
  behaviors are implemented.
- `xcodebuild` verifies that the native application target compiles for macOS.
- Every behavior change must update tests first; architectural discoveries and
  changed assumptions must update this document or the development log.
