# Worktree Cleaner

Terminology for reviewing and cleaning up Git worktrees. Both English and Chinese
use the terms **main worktree** and **linked worktree**, capitalized only at the
start of a sentence or standalone label.

## Language

**main worktree**:
The original working tree created with a non-bare Git repository. It is protected
from cleanup.

**linked worktree**:
An additional working tree registered with the same Git repository. Its
registration counts as a linked worktree even when its directory no longer exists.

**Branch**:
A named reference to a line of development that a worktree can check out. A
worktree with a detached HEAD has no checked-out branch.
