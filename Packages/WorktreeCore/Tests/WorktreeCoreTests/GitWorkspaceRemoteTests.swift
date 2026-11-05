import Foundation
import WorktreeCore
import XCTest

final class GitWorkspaceRemoteTests: XCTestCase {
  func testSyncFetchesRemoteDefaultBranchAndUpdatesRecommendations() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let remote = fixture.base.appending(path: "remote.git")
    try runGit(
      ["init", "--quiet", "--bare", "--initial-branch=trunk", remote.path],
      in: fixture.repository
    )
    try runGit(["remote", "add", "origin", remote.path], in: fixture.repository)
    try runGit(
      ["config", "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/main"],
      in: fixture.repository
    )
    try runGit(
      ["push", "--quiet", "origin", "refs/heads/main:refs/heads/trunk"],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    let changed = try await workspace.synchronizeDefaultBranch(of: repository)
    let changedAgain = try await workspace.synchronizeDefaultBranch(of: repository)

    let snapshot = try await workspace.snapshot(of: repository)
    XCTAssertTrue(changed)
    XCTAssertFalse(changedAgain)
    XCTAssertEqual(
      snapshot.worktrees.first { !$0.isMain }?.cleanupRecommendation,
      .cleanable(target: "origin/trunk")
    )

    try runGit(
      [
        "-c", "user.name=Worktree Cleaner Tests",
        "-c", "user.email=tests@example.com",
        "commit", "--quiet", "--allow-empty", "-m", "Remote update",
      ],
      in: fixture.repository
    )
    try runGit(
      ["push", "--quiet", "origin", "refs/heads/main:refs/heads/trunk"],
      in: fixture.repository
    )
    let updated = try await workspace.synchronizeDefaultBranch(of: repository)
    XCTAssertTrue(updated)
    try runGit(
      ["merge-base", "--is-ancestor", "refs/heads/main", "refs/remotes/origin/trunk"],
      in: fixture.repository
    )
  }

  func testSyncUpdatesAnExistingDefaultReferenceWhenTheRemoteChangesIt() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let remote = fixture.base.appending(path: "remote.git")
    try runGit(
      ["init", "--quiet", "--bare", "--initial-branch=trunk", remote.path],
      in: fixture.repository
    )
    try runGit(["remote", "add", "origin", remote.path], in: fixture.repository)
    try runGit(
      ["push", "--quiet", "origin", "refs/heads/main:refs/heads/trunk"],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)
    _ = try await workspace.synchronizeDefaultBranch(of: repository)
    try runGit(
      ["push", "--quiet", "origin", "refs/heads/main:refs/heads/release"],
      in: fixture.repository
    )
    try runGit(["symbolic-ref", "HEAD", "refs/heads/release"], in: remote)

    let changed = try await workspace.synchronizeDefaultBranch(of: repository)
    let snapshot = try await workspace.snapshot(of: repository)

    XCTAssertTrue(changed)
    XCTAssertEqual(
      snapshot.worktrees.first { !$0.isMain }?.cleanupRecommendation,
      .cleanable(target: "origin/release")
    )
  }

  func testSyncReportsFailureWhenOriginIsUnavailable() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    do {
      _ = try await workspace.synchronizeDefaultBranch(of: repository)
      XCTFail("Expected synchronization to fail without a configured origin")
    } catch {
      let snapshot = try await workspace.snapshot(of: repository)
      XCTAssertEqual(
        snapshot.worktrees.first { !$0.isMain }?.cleanupRecommendation,
        .needsReview(reason: .cleanupTargetUnavailable)
      )
    }
  }

  func testDanglingRemoteDefaultBranchIsReportedAsUnavailable() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(
      ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk"],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    XCTAssertEqual(
      snapshot.worktrees.first { !$0.isMain }?.cleanupRecommendation,
      .needsReview(reason: .cleanupTargetUnavailable)
    )
  }

  func testLocalBranchIsNotUsedAsTheRemoteDefaultTarget() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    try runGit(
      ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/heads/main"],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    let snapshot = try await workspace.snapshot(of: repository)

    XCTAssertEqual(
      snapshot.worktrees.first { !$0.isMain }?.cleanupRecommendation,
      .needsReview(reason: .cleanupTargetUnavailable)
    )
  }

  func testSyncPreservesASymbolicRemoteTrackingReferenceAndItsTarget() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let remote = fixture.base.appending(path: "remote.git")
    try runGit(
      ["init", "--quiet", "--bare", "--initial-branch=trunk", remote.path],
      in: fixture.repository
    )
    try runGit(["remote", "add", "origin", remote.path], in: fixture.repository)
    try runGit(["branch", "saved"], in: fixture.repository)
    try runGit(
      [
        "-c", "user.name=Worktree Cleaner Tests",
        "-c", "user.email=tests@example.com",
        "commit", "--quiet", "--allow-empty", "-m", "Remote update",
      ],
      in: fixture.repository
    )
    try runGit(
      ["push", "--quiet", "origin", "refs/heads/main:refs/heads/trunk"],
      in: fixture.repository
    )
    try runGit(
      ["symbolic-ref", "refs/remotes/origin/trunk", "refs/heads/saved"],
      in: fixture.repository
    )
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    do {
      _ = try await workspace.synchronizeDefaultBranch(of: repository)
      XCTFail("Expected a symbolic remote-tracking reference to be rejected")
    } catch let error as GitWorkspaceError {
      XCTAssertEqual(error, .invalidRemoteTrackingReference("refs/remotes/origin/trunk"))
    }
    try runGit(
      ["merge-base", "--is-ancestor", "refs/heads/main^", "refs/heads/saved"],
      in: fixture.repository
    )
    try runGit(
      ["merge-base", "--is-ancestor", "refs/heads/saved", "refs/heads/main^"],
      in: fixture.repository
    )
  }

  func testSyncPreservesLocalBranchWhenTrackingReferenceChangesDuringFetch() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let remote = fixture.base.appending(path: "remote.git")
    try runGit(
      ["init", "--quiet", "--bare", "--initial-branch=trunk", remote.path],
      in: fixture.repository
    )
    try runGit(["remote", "add", "origin", remote.path], in: fixture.repository)
    try runGit(
      ["config", "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/main"],
      in: fixture.repository
    )
    try runGit(["branch", "saved"], in: fixture.repository)
    try runGit(
      [
        "-c", "user.name=Worktree Cleaner Tests",
        "-c", "user.email=tests@example.com",
        "commit", "--quiet", "--allow-empty", "-m", "Remote update",
      ],
      in: fixture.repository
    )
    try runGit(
      ["push", "--quiet", "origin", "refs/heads/main:refs/heads/trunk"],
      in: fixture.repository
    )
    let uploadPack = fixture.base.appending(path: "upload-pack")
    let script = """
      #!/bin/sh
      if [ -f "$0.seen" ]; then
        /usr/bin/git -C "$(dirname "$0")/project" symbolic-ref refs/remotes/origin/trunk refs/heads/saved
      else
        touch "$0.seen"
      fi
      exec /usr/bin/git-upload-pack "$@"

      """
    try script.write(to: uploadPack, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: uploadPack.path)
    try runGit(["config", "remote.origin.uploadpack", uploadPack.path], in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    do {
      _ = try await workspace.synchronizeDefaultBranch(of: repository)
      XCTFail("Expected synchronization to report the concurrent reference change")
    } catch {
      try runGit(
        ["merge-base", "--is-ancestor", "refs/heads/main^", "refs/heads/saved"],
        in: fixture.repository
      )
      try runGit(
        ["merge-base", "--is-ancestor", "refs/heads/saved", "refs/heads/main^"],
        in: fixture.repository
      )
    }
  }

  func testSyncReportsWhenRemoteDefaultChangesDuringFetch() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let remote = fixture.base.appending(path: "remote.git")
    try runGit(
      ["init", "--quiet", "--bare", "--initial-branch=trunk", remote.path],
      in: fixture.repository
    )
    try runGit(["remote", "add", "origin", remote.path], in: fixture.repository)
    try runGit(
      ["config", "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/main"],
      in: fixture.repository
    )
    for branch in ["trunk", "release"] {
      try runGit(
        ["push", "--quiet", "origin", "refs/heads/main:refs/heads/\(branch)"],
        in: fixture.repository
      )
    }
    let uploadPack = fixture.base.appending(path: "upload-pack")
    let script = """
      #!/bin/sh
      if [ -f "$0.seen" ]; then
        /usr/bin/git -C "$(dirname "$0")/remote.git" symbolic-ref HEAD refs/heads/release
      else
        touch "$0.seen"
      fi
      exec /usr/bin/git-upload-pack "$@"

      """
    try script.write(to: uploadPack, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: uploadPack.path)
    try runGit(["config", "remote.origin.uploadpack", uploadPack.path], in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    do {
      _ = try await workspace.synchronizeDefaultBranch(of: repository)
      XCTFail("Expected the changed default branch to be reported")
    } catch let error as GitWorkspaceError {
      XCTAssertEqual(
        error,
        .remoteDefaultBranchChanged(fixture.repository.resolvingSymlinksInPath())
      )
    }
    let snapshot = try await workspace.snapshot(of: repository)
    XCTAssertEqual(
      snapshot.worktrees.first { !$0.isMain }?.cleanupRecommendation,
      .needsReview(reason: .cleanupTargetUnavailable)
    )
  }

  func testSyncReportsAnEmptyRemoteWithoutGuessingABranch() async throws {
    let fixture = try makeRepositoryWithLinkedWorktree()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let remote = fixture.base.appending(path: "empty.git")
    try runGit(
      ["init", "--quiet", "--bare", "--initial-branch=trunk", remote.path],
      in: fixture.repository
    )
    try runGit(["remote", "add", "origin", remote.path], in: fixture.repository)
    let workspace = GitWorkspace()
    let repositories = try await collectRepositories(from: workspace.discover(in: fixture.base))
    let repository = try XCTUnwrap(repositories.first)

    do {
      _ = try await workspace.synchronizeDefaultBranch(of: repository)
      XCTFail("Expected an empty origin to report no default branch")
    } catch let error as GitWorkspaceError {
      XCTAssertEqual(
        error,
        .remoteDefaultBranchUnavailable(fixture.repository.resolvingSymlinksInPath())
      )
    }
  }
}
