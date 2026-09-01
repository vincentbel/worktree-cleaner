<p align="center">
  <img src="WorktreeCleaner/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png"
       width="128" height="128" alt="Worktree Cleaner app icon">
</p>

# Worktree Cleaner

Find Git worktrees across your projects, see exactly what is safe to remove, and
reclaim disk space without losing work.

A native macOS app that scans multiple directories and puts Git status, merge
safety, and disk usage in one place.

<p align="center">
  <img src="docs/images/worktree-cleaner.png"
       alt="Worktree Cleaner showing cleanup recommendations for multiple Git worktrees">
</p>

## Features

- **Find worktrees across projects.** Scan multiple directories and surface projects
  with linked worktrees first.
- **Know what is safe to remove.** See uncommitted changes, merge state, locks,
  missing directories, and disk usage with a clear recommendation.
- **Reclaim disk space safely.** Remove eligible worktrees individually or in a
  batch without deleting their Git branches.
- **Repair stale registrations.** Prune records whose worktree directories no
  longer exist.
- **Jump to any worktree.** Open it in Finder, a terminal, or an installed editor,
  or copy its path.

## Safety guarantees

- **State is rechecked immediately before removal.**
- **Worktrees are never force-removed, and branches are never deleted.**
- **Main, dirty, and locked worktrees are blocked.**
- A clean unmerged worktree can be removed when its branch keeps the commits
  reachable. An unmerged detached HEAD is blocked until you create a branch.

## Install

Download the latest signed and notarized build from
[latest GitHub release][releases], unzip it, and move `WorktreeCleaner.app`
to Applications.

Requires **macOS 14 or later** and Git at `/usr/bin/git`.

## Getting started

1. Add one or more directories containing Git projects.
2. Select a project and review its worktrees and recommendations.
3. Clean up eligible worktrees individually or in a batch.

**Scanning is read-only.** Files change only after you explicitly confirm cleanup.

## Project documentation

- [Development](docs/development.md)
- [Architecture and safety decisions](docs/architecture.md)
- [Release process](docs/releasing.md)

[releases]: https://github.com/vincentbel/worktree-cleaner/releases/latest
