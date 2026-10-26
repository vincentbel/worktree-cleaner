<p align="center">
  <img src="WorktreeCleaner/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png"
       width="128" height="128" alt="Worktree Cleaner app icon">
</p>

# Worktree Cleaner

Worktree Cleaner is a free, open-source, lightweight native macOS app for safely
cleaning up Git worktrees across projects.

See what is safe to remove, reclaim disk space, and keep branches and uncommitted
work protected.

<p align="center">
  <strong><a href="https://github.com/vincentbel/worktree-cleaner/releases/download/v0.1.2/WorktreeCleaner-0.1.2.dmg">Download Worktree Cleaner 0.1.2</a></strong>
</p>

<p align="center">
  <img src="docs/images/worktree-cleaner.png"
       alt="Worktree Cleaner showing cleanup recommendations for multiple Git worktrees">
</p>

## Features

<table>
  <tr>
    <td width="50%">
      <a href="docs/images/intro-en/01-repositories.png">
        <img src="docs/images/intro-en/01-repositories.png" width="100%" alt="Add a parent folder to recursively discover multiple Git repositories in one scan">
      </a>
    </td>
    <td width="50%">
      <a href="docs/images/intro-en/02-locations.png">
        <img src="docs/images/intro-en/02-locations.png" width="100%" alt="Registered worktrees from a sibling folder, a temporary directory, and an agent directory grouped under one repository">
      </a>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <a href="docs/images/intro-en/03-disk-usage.png">
        <img src="docs/images/intro-en/03-disk-usage.png" width="100%" alt="Compare worktree disk usage, including a build worktree using 402.7 MB and a preview worktree using 134.2 MB">
      </a>
    </td>
    <td width="50%">
      <a href="docs/images/intro-en/04-cleanup-decision.png">
        <img src="docs/images/intro-en/04-cleanup-decision.png" width="100%" alt="Git cleanup recommendations distinguish merged worktrees, unmerged branches needing review, and protected uncommitted work">
      </a>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <a href="docs/images/intro-en/05-batch-cleanup.png">
        <img src="docs/images/intro-en/05-batch-cleanup.png" width="100%" alt="Select two worktrees in one repository and review the batch cleanup confirmation while preserving their Git branches">
      </a>
    </td>
    <td width="50%">
      <a href="docs/images/intro-en/06-sort-select.png">
        <img src="docs/images/intro-en/06-sort-select.png" width="100%" alt="Sort worktrees by commit time, disk usage, branch, or path, and Shift-click to select a range">
      </a>
    </td>
  </tr>
</table>

## Safety guarantees

- **State is rechecked immediately before removal.**
- **Worktrees are never force-removed, and branches are never deleted.**
- **Main, dirty, and locked worktrees are blocked.**
- A clean unmerged worktree can be removed when its branch keeps the commits
  reachable. An unmerged detached HEAD is blocked until you create a branch.

## Install

Download the signed and notarized [Worktree Cleaner 0.1.2 DMG][download].
Open it, drag `WorktreeCleaner.app` onto the **Applications** shortcut, then
launch the app from Applications and eject the disk image.

Requires **macOS 14 or later** and Git at `/usr/bin/git`.

## Getting started

1. Add one or more directories containing Git projects.
2. Select a project and review its worktrees and recommendations.
3. Click **Last Commit**, **Disk Usage**, **Branch**, or **Path** to sort; click
   again to reverse the order. The default is oldest commit first.
4. Select eligible worktrees with the checkboxes. Hold **Shift** while clicking
   another checkbox to select or deselect the range, then clean up individually
   or in a batch.

**Last Commit** shows the current HEAD commit's committer time in your local time
zone. Uncommitted file edits do not change this time. The main worktree stays
first when sorting, and unknown dates or disk sizes stay last.

**Scanning is read-only.** Files change only after you explicitly confirm cleanup.

## Project documentation

- [Development](docs/development.md)
- [Architecture and safety decisions](docs/architecture.md)
- [Release process](docs/releasing.md)
- [Edit and export the introduction images](docs/marketing/intro-en/README.md)

[download]: https://github.com/vincentbel/worktree-cleaner/releases/download/v0.1.2/WorktreeCleaner-0.1.2.dmg
