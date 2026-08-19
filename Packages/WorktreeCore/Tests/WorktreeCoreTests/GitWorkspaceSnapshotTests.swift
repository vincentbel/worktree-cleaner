import Foundation
import WorktreeCore
import XCTest

final class GitWorkspaceSnapshotTests: XCTestCase {
  func testSnapshotListsMainAndLinkedWorktrees() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
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
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let linkedWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    let status = try XCTUnwrap(linkedWorktree.status)
    XCTAssertFalse(status.isClean)
    XCTAssertEqual(status.untrackedFileCount, 1)
    XCTAssertEqual(status.stagedFileCount, 0)
    XCTAssertEqual(status.modifiedFileCount, 0)
    XCTAssertEqual(status.conflictedFileCount, 0)
  }

  func testSnapshotReportsLockedWorktreeAndReason() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(
      ["worktree", "lock", "--reason", "Agent is running", fixture.linkedWorktree.path],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
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
    try configureRemoteDefaultBranch(in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
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

  func testDiskUsageStreamsWorktreeAndSharedGitMeasurements() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try Data(repeating: 0xA5, count: 4_096).write(
      to: fixture.linkedWorktree.appending(path: "generated.bin")
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)
    var worktreeUsage: [URL: Int64] = [:]
    var sharedGitUsage: Int64?

    for try await update in workspace.diskUsage(of: snapshot) {
      switch update {
      case .worktree(let path, let allocatedBytes):
        worktreeUsage[path] = allocatedBytes
      case .sharedGit(let allocatedBytes):
        sharedGitUsage = allocatedBytes
      }
    }

    XCTAssertGreaterThanOrEqual(
      try XCTUnwrap(worktreeUsage[fixture.linkedWorktree.resolvingSymlinksInPath()]),
      4_096
    )
    XCTAssertGreaterThan(try XCTUnwrap(sharedGitUsage), 0)
  }

  func testSnapshotKeepsMissingWorktreeAsPrunableRecord() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    let missingWorktree = try XCTUnwrap(
      snapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertTrue(missingWorktree.isPrunable)
    XCTAssertNotNil(missingWorktree.prunableReason)
    XCTAssertNil(missingWorktree.status)
  }
}
