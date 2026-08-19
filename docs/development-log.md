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

