import Foundation
import WorktreeCore
import XCTest

final class GitWorkspaceRemovalTests: XCTestCase {
  func testRemoveDeletesEligibleLinkedWorktree() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try configureRemoteDefaultBranch(in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let linkedWorktree = try XCTUnwrap(
      initialSnapshot.worktrees.first { !$0.isMain }
    )

    let updatedSnapshot = try await workspace.remove(
      linkedWorktree,
      from: repository
    )

    XCTAssertEqual(updatedSnapshot.worktrees.count, 1)
    XCTAssertTrue(updatedSnapshot.worktrees[0].isMain)
    XCTAssertEqual(updatedSnapshot.repository.linkedWorktreeCount, 0)
  }

  func testRemoveRepeatsPreflightAndRefusesNewUntrackedFile() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try configureRemoteDefaultBranch(in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let linkedWorktree = try XCTUnwrap(
      initialSnapshot.worktrees.first { !$0.isMain }
    )
    try Data("new agent output".utf8).write(
      to: fixture.linkedWorktree.appending(path: "agent-output.txt")
    )

    do {
      _ = try await workspace.remove(linkedWorktree, from: repository)
      XCTFail("Expected removal to fail after the worktree became dirty")
    } catch let error as GitWorkspaceError {
      guard case .worktreeNotCleanable(let path, let recommendation) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(path, fixture.linkedWorktree.resolvingSymlinksInPath())
      XCTAssertEqual(
        recommendation,
        .blocked(reasons: [.uncommittedChanges])
      )
    }

    let currentSnapshot = try await workspace.snapshot(of: repository)
    XCTAssertEqual(currentSnapshot.worktrees.count, 2)
  }

  func testRemoveDeletesCleanLinkedWorktreeWhoseCommitIsNotMerged() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try configureRemoteDefaultBranch(in: fixture.repository)
    try Data("agent result".utf8).write(
      to: fixture.linkedWorktree.appending(path: "result.txt")
    )
    try runGit(["add", "result.txt"], in: fixture.linkedWorktree)
    try runGit(
      [
        "-c", "user.name=Worktree Cleaner Tests",
        "-c", "user.email=tests@example.com",
        "commit", "--quiet", "-m", "Unmerged agent result",
      ],
      in: fixture.linkedWorktree
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let linkedWorktree = try XCTUnwrap(
      initialSnapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertEqual(
      linkedWorktree.cleanupRecommendation,
      .needsReview(reason: .notMerged(target: "origin/main"))
    )

    let updatedSnapshot = try await workspace.remove(
      linkedWorktree,
      from: repository
    )

    XCTAssertEqual(updatedSnapshot.worktrees.count, 1)
    XCTAssertTrue(updatedSnapshot.worktrees[0].isMain)
  }

  func testPruneRemovesMissingWorktreeRegistrationAndPreservesBranch() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let linkedWorktree = try XCTUnwrap(
      initialSnapshot.worktrees.first { !$0.isMain }
    )
    XCTAssertTrue(linkedWorktree.isPrunable)

    let updatedSnapshot = try await workspace.prune(
      linkedWorktree,
      from: repository
    )

    XCTAssertEqual(updatedSnapshot.worktrees.count, 1)
    XCTAssertTrue(updatedSnapshot.worktrees[0].isMain)
    try runGit(["show-ref", "--verify", "refs/heads/agent-task"], in: fixture.repository)
  }

  func testPruneRefusesRegistrationWhoseDirectoryStillExists() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let linkedWorktree = try XCTUnwrap(
      initialSnapshot.worktrees.first { !$0.isMain }
    )

    do {
      _ = try await workspace.prune(linkedWorktree, from: repository)
      XCTFail("Expected pruning to reject an existing worktree directory")
    } catch let error as GitWorkspaceError {
      guard case .worktreeRegistrationNotPrunable(let path) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(path, fixture.linkedWorktree.resolvingSymlinksInPath())
    }
  }
}
