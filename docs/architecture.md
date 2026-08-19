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
- Persist only user choices such as the selected root. Repository and worktree
  state is derived by scanning, so the first version does not need a database.
- Distribute the first version with Developer ID signing and notarization, with
  App Sandbox disabled. This allows a repository below the selected root to
  reference registered worktrees outside that root.
- Keep third-party runtime dependencies at zero for the first version.

## Module seam

`WorktreeCore.GitWorkspace` is the public seam used by the app and by integration
tests. Its initial responsibilities are deliberately small:

1. Discover logical Git repositories below a directory.
2. Produce a complete worktree snapshot for a discovered repository.
3. Later, perform a preflight check and remove an eligible linked worktree.

Git command execution, output parsing, traversal, bounded concurrency, disk
measurement, and recommendation rules remain implementation details behind this
seam. Tests exercise the public behavior against temporary real Git repositories
instead of mocking internal collaborators.

## Repository discovery

The scanner recursively looks for both `.git` directories and `.git` files. Each
candidate is validated with Git rather than accepted from its filesystem shape
alone.

- `git rev-parse --show-toplevel` finds the working-tree root.
- `git rev-parse --git-common-dir` identifies the shared repository metadata.
- The normalized common Git directory is the logical repository identity. This
  prevents a linked worktree from appearing as a second project in the sidebar.
- The scanner does not descend into `.git`, does not follow directory symbolic
  links, and continues after recoverable permission failures.
- Nested repositories remain discoverable.

## Worktree inspection

Machine-readable Git output is the source of truth:

- `git worktree list --porcelain -z`
- `git status --porcelain=v2 --branch -z`
- `git rev-parse`
- `git merge-base --is-ancestor`

A worktree snapshot can contain its path, HEAD, branch or detached state, main
worktree flag, lock/prunable state, tracked and untracked changes, conflicts,
upstream divergence, disk usage, and cleanup recommendation.

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

Removal uses `git worktree remove <absolute-path>` without `--force`. The first
version never deletes the associated branch as a side effect. Missing/prunable
administrative records are handled separately from worktree removal.

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
- Measure allocated bytes in a cancellable background task and cache the result.
- A large size can raise recommendation priority but can never make a worktree
  eligible for removal by itself.

The initial large-worktree threshold may be 5 GB. It is a transparent product
rule, not a safety rule, and can be revisited after real usage data exists.

## UI shape

The primary window uses a two-column `NavigationSplitView`:

- Sidebar: discovered logical repositories and their aggregate health.
- Detail: a native table of worktrees with branch, path, status, disk usage,
  recommendation, and actions.
- Toolbar: choose root, rescan, and later refresh remote refs explicitly.

Long-running scans and inspections are asynchronous, cancellable, and never run
on the main actor.

## Verification

- `swift test` verifies `WorktreeCore` through its public seam using temporary
  real repositories.
- Tests cover normal repositories, linked worktrees, common-directory deduping,
  detached/dirty/locked states, unusual paths, and cleanup ancestry as those
  behaviors are implemented.
- `xcodebuild` verifies that the native application target compiles for macOS.
- Every behavior change must update tests first; architectural discoveries and
  changed assumptions must update this document or the development log.
