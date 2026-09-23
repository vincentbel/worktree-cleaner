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
      from: repository,
      policy: .cleanableOnly
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
      from: repository,
      policy: .allowUnmerged
    )

    XCTAssertEqual(updatedSnapshot.worktrees.count, 1)
    XCTAssertTrue(updatedSnapshot.worktrees[0].isMain)
  }

  func testCleanableOnlyRemovalRefusesUnmergedLinkedWorktree() async throws {
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

    do {
      _ = try await workspace.remove(
        linkedWorktree,
        from: repository,
        policy: .cleanableOnly
      )
      XCTFail("Expected strict removal to reject an unmerged worktree")
    } catch let error as GitWorkspaceError {
      guard case .worktreeNotCleanable(let path, let recommendation) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(path, fixture.linkedWorktree.resolvingSymlinksInPath())
      XCTAssertEqual(
        recommendation,
        .needsReview(reason: .notMerged(target: "origin/main"))
      )
    }

    let currentSnapshot = try await workspace.snapshot(of: repository)
    XCTAssertEqual(currentSnapshot.worktrees.count, 2)
  }

  func testRemovalRefusesUnmergedDetachedHead() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try configureRemoteDefaultBranch(in: fixture.repository)
    try runGit(["switch", "--detach", "--quiet"], in: fixture.linkedWorktree)
    try Data("detached result".utf8).write(
      to: fixture.linkedWorktree.appending(path: "detached-result.txt")
    )
    try runGit(["add", "detached-result.txt"], in: fixture.linkedWorktree)
    try runGit(
      [
        "-c", "user.name=Worktree Cleaner Tests",
        "-c", "user.email=tests@example.com",
        "commit", "--quiet", "-m", "Unmerged detached result",
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
      .needsReview(reason: .detachedHeadNotMerged(target: "origin/main"))
    )

    do {
      _ = try await workspace.remove(
        linkedWorktree,
        from: repository,
        policy: .allowUnmerged
      )
      XCTFail("Expected removal to reject an unmerged detached HEAD")
    } catch let error as GitWorkspaceError {
      guard case .worktreeNotCleanable(let path, let recommendation) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(path, fixture.linkedWorktree.resolvingSymlinksInPath())
      XCTAssertEqual(
        recommendation,
        .needsReview(reason: .detachedHeadNotMerged(target: "origin/main"))
      )
    }

    let currentSnapshot = try await workspace.snapshot(of: repository)
    XCTAssertEqual(currentSnapshot.worktrees.count, 2)
  }

  func testRemoveCleansOnlySelectedMissingRegistrationAndPreservesBranches() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let otherWorktree = fixture.base.appending(path: "other-agent")
    try runGit(
      ["worktree", "add", "--quiet", "-b", "other-agent", otherWorktree.path],
      in: fixture.repository
    )
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    try FileManager.default.removeItem(at: otherWorktree)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let selectedWorktree = try XCTUnwrap(
      initialSnapshot.worktrees.first { $0.branch == "agent-task" }
    )

    let updatedSnapshot = try await workspace.remove(
      selectedWorktree,
      from: repository,
      policy: .cleanableOnly
    )

    XCTAssertEqual(updatedSnapshot.worktrees.map(\.branch), ["main", "other-agent"])
    XCTAssertEqual(updatedSnapshot.repository.linkedWorktreeCount, 1)
    try runGit(["show-ref", "--verify", "refs/heads/agent-task"], in: fixture.repository)
    try runGit(["show-ref", "--verify", "refs/heads/other-agent"], in: fixture.repository)

    let otherRecord = try XCTUnwrap(
      initialSnapshot.worktrees.first { $0.branch == "other-agent" }
    )
    let finalSnapshot = try await workspace.remove(otherRecord, from: repository)
    XCTAssertEqual(finalSnapshot.worktrees.map(\.branch), ["main"])
    XCTAssertEqual(finalSnapshot.repository.linkedWorktreeCount, 0)
  }

  func testRemoveRefusesMissingRegistrationAfterDirectoryIsRestored() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try configureRemoteDefaultBranch(in: fixture.repository)
    let savedDirectory = fixture.base.appending(path: "saved-agent")
    try FileManager.default.moveItem(at: fixture.linkedWorktree, to: savedDirectory)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let missingWorktree = try XCTUnwrap(initialSnapshot.worktrees.first { !$0.isMain })
    try FileManager.default.moveItem(at: savedDirectory, to: fixture.linkedWorktree)

    do {
      _ = try await workspace.remove(missingWorktree, from: repository)
      XCTFail("Expected record cleanup to preserve the restored directory")
    } catch let error as GitWorkspaceError {
      switch error {
      case .worktreeRegistrationNotPrunable(let path), .worktreeNotRegistered(let path):
        XCTAssertEqual(path, missingWorktree.path)
      default:
        return XCTFail("Unexpected error: \(error)")
      }
    }

    let currentSnapshot = try await workspace.snapshot(of: repository)
    let restoredWorktree = try XCTUnwrap(currentSnapshot.worktrees.first { !$0.isMain })
    XCTAssertFalse(restoredWorktree.isPrunable)
    XCTAssertEqual(restoredWorktree.cleanupRecommendation, .cleanable(target: "origin/main"))
  }

  func testRemoveRefusesMissingRegistrationLockedAfterSelection() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try FileManager.default.removeItem(at: fixture.linkedWorktree)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.base)
    )
    let repository = try XCTUnwrap(repositories.first)
    let initialSnapshot = try await workspace.snapshot(of: repository)
    let missingWorktree = try XCTUnwrap(initialSnapshot.worktrees.first { !$0.isMain })
    try runGit(["worktree", "lock", fixture.linkedWorktree.path], in: fixture.repository)

    do {
      _ = try await workspace.remove(missingWorktree, from: repository)
      XCTFail("Expected record cleanup to preserve the locked registration")
    } catch let error as GitWorkspaceError {
      guard case .worktreeRegistrationNotPrunable(let path) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(path, missingWorktree.path)
    }

    let currentSnapshot = try await workspace.snapshot(of: repository)
    let lockedWorktree = try XCTUnwrap(currentSnapshot.worktrees.first { !$0.isMain })
    XCTAssertTrue(lockedWorktree.isLocked)
    XCTAssertTrue(lockedWorktree.isPrunable)
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
