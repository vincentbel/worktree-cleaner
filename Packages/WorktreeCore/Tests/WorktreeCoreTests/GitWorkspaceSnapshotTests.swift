import Foundation
import WorktreeCore
import XCTest

final class GitWorkspaceSnapshotTests: XCTestCase {
  func testSnapshotListsMainAndLinkedWorktrees() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await workspace.discover(in: fixture.base)
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    XCTAssertEqual(snapshot.repository, repository)
    XCTAssertEqual(
      snapshot.worktrees.map(\.path),
      [
        fixture.repository.resolvingSymlinksInPath(),
        fixture.linkedWorktree.resolvingSymlinksInPath(),
      ]
    )
    XCTAssertEqual(snapshot.worktrees.map(\.branch), ["main", "agent-task"])
    XCTAssertEqual(snapshot.worktrees.map(\.isMain), [true, false])
  }

  func testSnapshotReportsUntrackedFilesInLinkedWorktree() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try Data("uncommitted work".utf8).write(
      to: fixture.linkedWorktree.appending(path: "notes.txt")
    )
    let workspace = GitWorkspace()
    let repositories = try await workspace.discover(in: fixture.base)
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let linkedWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertFalse(linkedWorktree.status.isClean)
    XCTAssertEqual(linkedWorktree.status.untrackedFileCount, 1)
    XCTAssertEqual(linkedWorktree.status.stagedFileCount, 0)
    XCTAssertEqual(linkedWorktree.status.modifiedFileCount, 0)
    XCTAssertEqual(linkedWorktree.status.conflictedFileCount, 0)
  }

  func testSnapshotReportsLockedWorktreeAndReason() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(
      ["worktree", "lock", "--reason", "Agent is running", fixture.linkedWorktree.path],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await workspace.discover(in: fixture.base)
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let linkedWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertTrue(linkedWorktree.isLocked)
    XCTAssertEqual(linkedWorktree.lockReason, "Agent is running")
  }

  func testSnapshotRecommendsCleanLinkedWorktreeWhoseHeadIsInRemoteDefaultBranch() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(
      ["update-ref", "refs/remotes/origin/main", "refs/heads/main"],
      in: fixture.repository
    )
    try runGit(
      ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await workspace.discover(in: fixture.base)
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let linkedWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertEqual(
      linkedWorktree.cleanupRecommendation,
      .cleanable(target: "origin/main")
    )
  }
}
