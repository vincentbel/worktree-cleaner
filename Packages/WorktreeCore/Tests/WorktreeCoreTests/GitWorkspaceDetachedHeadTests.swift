import Foundation
import WorktreeCore
import XCTest

final class GitWorkspaceDetachedHeadTests: XCTestCase {
  func testRemoveDetachedHeadPreservedByLocalBranchDescendant() async throws {
    let fixture = try makePreservedDetachedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)
    let snapshot = try await workspace.snapshot(of: repository)
    let worktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })
    XCTAssertTrue(worktree.isDetached)
    XCTAssertNil(worktree.branch)
    XCTAssertEqual(
      worktree.cleanupRecommendation,
      .needsReview(reason: .notMerged(target: "origin/main", preservingBranch: "saved-work"))
    )

    try await workspace.remove(worktree, from: repository, policy: .allowUnmerged)

    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.linkedWorktree.path))
    let updatedSnapshot = try await workspace.snapshot(of: repository)
    XCTAssertEqual(updatedSnapshot.worktrees.count, 1)
    try runGit(
      ["merge-base", "--is-ancestor", worktree.head, "refs/heads/saved-work"],
      in: fixture.repository
    )
  }

  func testCleanableOnlyRemovalRefusesPreservedDetachedHead() async throws {
    let fixture = try makePreservedDetachedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)
    let snapshot = try await workspace.snapshot(of: repository)
    let worktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })

    do {
      try await workspace.remove(worktree, from: repository, policy: .cleanableOnly)
      XCTFail("Expected unmerged commits to require explicit review")
    } catch let error as GitWorkspaceError {
      XCTAssertEqual(
        error,
        .worktreeNotCleanable(
          worktree.path,
          .needsReview(reason: .notMerged(target: "origin/main", preservingBranch: "saved-work"))
        )
      )
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.linkedWorktree.path))
  }

  func testRemovalRechecksDeletedPreservingBranch() async throws {
    try await assertRemovalRechecksPreservingBranch(["branch", "-D", "saved-work"])
  }

  func testRemovalRechecksMovedPreservingBranch() async throws {
    try await assertRemovalRechecksPreservingBranch(["branch", "-f", "saved-work", "main"])
  }

  func testRemoteBranchAndTagRequireLocalBranchForDetachedCleanup() async throws {
    let fixture = try makePreservedDetachedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(
      ["update-ref", "refs/remotes/origin/saved-work", "saved-work"], in: fixture.repository)
    try runGit(["tag", "saved-result", "saved-work"], in: fixture.repository)
    try runGit(["branch", "-D", "saved-work"], in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)
    let snapshot = try await workspace.snapshot(of: repository)
    let worktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })
    XCTAssertEqual(
      worktree.cleanupRecommendation,
      .needsReview(reason: .detachedHeadNotMerged(target: "origin/main"))
    )

    do {
      try await workspace.remove(worktree, from: repository, policy: .allowUnmerged)
      XCTFail("Expected detached cleanup to require a local branch")
    } catch let error as GitWorkspaceError {
      XCTAssertEqual(error, .worktreeNotCleanable(worktree.path, worktree.cleanupRecommendation))
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.linkedWorktree.path))
  }

  func testMergedDetachedHeadRemainsCleanable() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try configureRemoteDefaultBranch(in: fixture.repository)
    try runGit(["switch", "--quiet", "--detach"], in: fixture.linkedWorktree)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)
    let snapshot = try await workspace.snapshot(of: repository)
    let worktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })
    XCTAssertEqual(worktree.cleanupRecommendation, .cleanable(target: "origin/main"))

    try await workspace.remove(worktree, from: repository, policy: .cleanableOnly)

    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.linkedWorktree.path))
  }

  private func assertRemovalRechecksPreservingBranch(_ change: [String]) async throws {
    let fixture = try makePreservedDetachedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(
      from: workspace.discover(in: fixture.repository))
    let repository = try XCTUnwrap(repositories.first)
    let snapshot = try await workspace.snapshot(of: repository)
    let worktree = try XCTUnwrap(snapshot.worktrees.first { !$0.isMain })
    XCTAssertEqual(
      worktree.cleanupRecommendation,
      .needsReview(reason: .notMerged(target: "origin/main", preservingBranch: "saved-work"))
    )
    try runGit(change, in: fixture.repository)

    do {
      try await workspace.remove(worktree, from: repository, policy: .allowUnmerged)
      XCTFail("Expected removal to preserve commits without a local branch")
    } catch let error as GitWorkspaceError {
      XCTAssertEqual(
        error,
        .worktreeNotCleanable(
          worktree.path, .needsReview(reason: .detachedHeadNotMerged(target: "origin/main")))
      )
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.linkedWorktree.path))
    let currentSnapshot = try await workspace.snapshot(of: repository)
    XCTAssertEqual(currentSnapshot.worktrees.count, 2)
  }

  private func makePreservedDetachedWorktree() throws -> (
    base: URL, repository: URL, linkedWorktree: URL
  ) {
    let fixture = try makeRepositoryWithLinkedWorktree()
    try configureRemoteDefaultBranch(in: fixture.repository)
    try runGit(["switch", "--quiet", "-c", "saved-work"], in: fixture.linkedWorktree)
    for message in ["Saved result", "Later work"] {
      try runGit(
        [
          "-c", "user.name=Worktree Cleaner Tests",
          "-c", "user.email=tests@example.com",
          "commit", "--quiet", "--allow-empty", "-m", message,
        ],
        in: fixture.linkedWorktree
      )
    }
    try runGit(["switch", "--quiet", "--detach", "HEAD~1"], in: fixture.linkedWorktree)
    return fixture
  }
}
